import 'dart:async';

import 'package:fl_clash/common/app_update.dart';
import 'package:fl_clash/providers/app_update.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:riverpod/riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('starts idle and coalesces concurrent checks', () async {
    final response = Completer<Object?>();
    var calls = 0;
    final container = _container(
      manifestLoader: (_) {
        calls++;
        return response.future;
      },
    );
    addTearDown(container.dispose);
    expect(container.read(appUpdateProvider).status, AppUpdateStatus.idle);
    expect(container.read(appUpdateProvider).hasUpdate, isFalse);
    final notifier = container.read(appUpdateProvider.notifier);
    final first = notifier.check();
    final second = notifier.check();
    expect(identical(first, second), isTrue);
    expect(container.read(appUpdateProvider).isChecking, isTrue);
    response.complete(_manifest());
    await Future.wait([first, second]);

    expect(calls, 1);
    final state = container.read(appUpdateProvider);
    expect(state.status, AppUpdateStatus.available);
    expect(state.isChecking, isFalse);
    expect(state.release?.version, '1.0.5');
    expect(state.hasUpdate, isTrue);
    expect(state.checkedAt, isNotNull);
  });

  test('each completed check reloads remote config and manifest', () async {
    var configCalls = 0;
    final requestedUrls = <Uri>[];
    final service = _service(
      mainConfigLoader: () async => {
        'UpdateUrl': 'https://update.example/${++configCalls}.json',
      },
      manifestLoader: (uri) async {
        requestedUrls.add(uri);
        return _manifest(version: configCalls == 1 ? '1.0.5' : '1.0.6');
      },
    );
    final container = _container(service: service);
    addTearDown(container.dispose);
    final notifier = container.read(appUpdateProvider.notifier);

    await notifier.check();
    final state = await notifier.check();

    expect(configCalls, 2);
    expect(requestedUrls.map((uri) => uri.path), ['/1.json', '/2.json']);
    expect(state.release?.version, '1.0.6');
  });

  test('ignoring a version does not remove the available update', () async {
    final service = _service();
    final container = _container(service: service);
    addTearDown(container.dispose);
    final notifier = container.read(appUpdateProvider.notifier);
    final first = await notifier.check();
    await service.ignore(first.release!);

    expect(await service.isIgnored(first.release!), isTrue);
    expect(container.read(appUpdateProvider).hasUpdate, isTrue);
    final next = await notifier.check();
    expect(next.hasUpdate, isTrue);
    expect(next.release?.version, '1.0.5');
    expect(next.status, AppUpdateStatus.available);
  });

  test(
    'a successful current-version result clears both update indicators',
    () async {
      var version = '1.0.5';
      final container = _container(
        manifestLoader: (_) async => _manifest(version: version),
      );
      addTearDown(container.dispose);
      final notifier = container.read(appUpdateProvider.notifier);
      await notifier.check();
      version = '1.0.4';

      final result = await notifier.check();

      expect(result.status, AppUpdateStatus.upToDate);
      expect(result.hasUpdate, isFalse);
      expect(result.release, isNull);
    },
  );

  test(
    'loading and request failure preserve the known newer release',
    () async {
      final response = Completer<Object?>();
      var calls = 0;
      final container = _container(
        manifestLoader: (_) async {
          if (++calls == 1) return _manifest();
          return response.future;
        },
      );
      addTearDown(container.dispose);
      final notifier = container.read(appUpdateProvider.notifier);
      final first = await notifier.check();
      final pending = notifier.check();
      expect(container.read(appUpdateProvider).isChecking, isTrue);
      expect(container.read(appUpdateProvider).release, same(first.release));
      response.completeError(StateError('Request failed'));

      final result = await pending;

      expect(result.status, AppUpdateStatus.failed);
      expect(result.isChecking, isFalse);
      expect(result.hasUpdate, isTrue);
      expect(result.release, same(first.release));
    },
  );

  test(
    'missing update URL preserves known release and reports unavailable',
    () async {
      var configured = true;
      final container = _container(
        service: _service(
          mainConfigLoader: () async => {
            if (configured) 'UpdateUrl': 'https://update.example/manifest.json',
          },
        ),
      );
      addTearDown(container.dispose);
      final notifier = container.read(appUpdateProvider.notifier);
      await notifier.check();
      configured = false;

      final result = await notifier.check();

      expect(result.status, AppUpdateStatus.unavailable);
      expect(result.hasUpdate, isTrue);
    },
  );

  for (final enabled in [false, null]) {
    test(
      'a disabled or missing package clears a previously known release ($enabled)',
      () async {
        var manifest = _manifest();
        final container = _container(manifestLoader: (_) async => manifest);
        addTearDown(container.dispose);
        final notifier = container.read(appUpdateProvider.notifier);
        await notifier.check();
        manifest = _manifest(enabled: enabled);

        final result = await notifier.check();

        expect(result.status, AppUpdateStatus.unavailable);
        expect(result.hasUpdate, isFalse);
        expect(result.release, isNull);
      },
    );
  }

  test(
    'missing package version reports unavailable without network calls',
    () async {
      var calls = 0;
      final container = _container(
        currentVersion: null,
        manifestLoader: (_) async {
          calls++;
          return _manifest();
        },
      );
      addTearDown(container.dispose);

      final result = await container.read(appUpdateProvider.notifier).check();

      expect(result.status, AppUpdateStatus.unavailable);
      expect(result.hasUpdate, isFalse);
      expect(calls, 0);
    },
  );

  test('unsupported platform is unavailable instead of up to date', () async {
    final container = _container(
      service: AppUpdateService(packageKeyResolver: () => null),
    );
    addTearDown(container.dispose);

    final result = await container.read(appUpdateProvider.notifier).check();

    expect(result.status, AppUpdateStatus.unavailable);
    expect(result.hasUpdate, isFalse);
  });

  test(
    'initial request failure is retryable and does not report latest',
    () async {
      var failed = true;
      final container = _container(
        manifestLoader: (_) async {
          if (failed) throw StateError('Offline');
          return _manifest();
        },
      );
      addTearDown(container.dispose);
      final notifier = container.read(appUpdateProvider.notifier);
      final failure = await notifier.check();
      expect(failure.status, AppUpdateStatus.failed);
      expect(failure.isChecking, isFalse);
      expect(failure.hasUpdate, isFalse);
      failed = false;

      expect((await notifier.check()).status, AppUpdateStatus.available);
    },
  );

  test('disposing during a check prevents late provider writes', () async {
    final response = Completer<Object?>();
    final container = _container(manifestLoader: (_) => response.future);
    final pending = container.read(appUpdateProvider.notifier).check();
    container.dispose();
    response.complete(_manifest());

    final result = await pending;

    expect(result.status, AppUpdateStatus.available);
    expect(result.isChecking, isFalse);
  });
}

ProviderContainer _container({
  AppUpdateService? service,
  AppUpdateManifestLoader? manifestLoader,
  String? currentVersion = '1.0.4',
}) {
  final dependency = service ?? _service(manifestLoader: manifestLoader);
  addTearDown(dependency.close);
  return ProviderContainer(
    overrides: [
      appUpdateServiceProvider.overrideWithValue(dependency),
      appUpdateCurrentVersionProvider.overrideWithValue(currentVersion),
    ],
  );
}

AppUpdateService _service({
  AppUpdateMainConfigLoader? mainConfigLoader,
  AppUpdateManifestLoader? manifestLoader,
}) => AppUpdateService(
  mainConfigLoader:
      mainConfigLoader ??
      () async => {'UpdateUrl': 'https://update.example/manifest.json'},
  manifestLoader: manifestLoader ?? (_) async => _manifest(),
  packageKeyResolver: () => 'windows-x64',
  aesKey: '',
  signingPublicKey: '',
);

Map<String, Object?> _manifest({
  String version = '1.0.5',
  bool? enabled = true,
}) => {
  'Authentication': 'FengWo',
  'format': 'fengwo-update',
  'schemaVersion': 1,
  'packages': {
    if (enabled != null)
      'windows-x64': {
        'enabled': enabled,
        'version': version,
        'downloadUrl': 'https://update.example/FengWo-$version.exe',
        'releaseNotesHtml': '<p>Update</p>',
      },
  },
};

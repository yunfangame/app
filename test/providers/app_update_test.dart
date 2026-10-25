import 'dart:async';

import 'package:fl_clash/common/api_health.dart';
import 'package:fl_clash/common/app_update.dart';
import 'package:fl_clash/providers/app_update.dart';
import 'package:fl_clash/state.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:riverpod/riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    globalState.setOfflineMode(false);
  });

  tearDown(() => globalState.setOfflineMode(false));

  test(
    'automatic entry points share work and reuse results for ten minutes',
    () async {
      final policy = _PolicyUpdate();
      final service = _PolicyService();
      final response = Completer<AppUpdateCheckResult>();
      service.loader = (_) => response.future;
      final container = _container(service: service, notifier: policy);
      addTearDown(container.dispose);
      final first = policy.check(forceRefresh: false);
      final second = policy.check(forceRefresh: false);
      expect(identical(first, second), isTrue);
      response.complete(_result());
      await first;
      policy.now = policy.now.add(
        const Duration(minutes: 10) - const Duration(milliseconds: 1),
      );
      await policy.check(forceRefresh: false);
      expect(service.forces, [false]);
      policy.now = policy.now.add(const Duration(milliseconds: 1));
      service.loader = (_) async => _result('1.0.6');
      expect(
        (await policy.check(forceRefresh: false)).release?.version,
        '1.0.6',
      );
      expect(service.forces, [false, false]);
    },
  );

  test(
    'automatic failures back off while manual success bypasses and resets',
    () async {
      final policy = _PolicyUpdate();
      final service = _PolicyService()
        ..loader = (_) async => throw StateError('controlled outage');
      final container = _container(service: service, notifier: policy);
      addTearDown(container.dispose);
      await policy.check(forceRefresh: false);
      var calls = 1;
      for (final seconds in [30, 60, 120, 300, 300]) {
        policy.now = policy.now.add(
          Duration(seconds: seconds) - const Duration(milliseconds: 1),
        );
        await policy.check(forceRefresh: false);
        expect(service.forces, hasLength(calls));
        policy.now = policy.now.add(const Duration(milliseconds: 1));
        await policy.check(forceRefresh: false);
        expect(service.forces, hasLength(++calls));
      }
      service.loader = (_) async => _result();
      await policy.check();
      expect(service.forces.last, isTrue);
      await policy.check(forceRefresh: false);
      expect(service.forces, hasLength(calls + 1));
      policy.now = policy.now.add(const Duration(minutes: 10));
      service.loader = (_) async => throw StateError('new outage');
      await policy.check(forceRefresh: false);
      policy.now = policy.now.add(const Duration(seconds: 30));
      await policy.check(forceRefresh: false);
      expect(service.forces, hasLength(calls + 3));
    },
  );

  for (final lateFailure in [false, true]) {
    test(
      'manual fresh result supersedes a late automatic result ($lateFailure)',
      () async {
        final policy = _PolicyUpdate();
        final automatic = Completer<AppUpdateCheckResult>();
        final manual = Completer<AppUpdateCheckResult>();
        final service = _PolicyService()
          ..loader = (force) => force ? manual.future : automatic.future;
        final container = _container(service: service, notifier: policy);
        addTearDown(container.dispose);
        final old = policy.check(forceRefresh: false);
        expect(container.read(appUpdateProvider).isAutomaticCheck, isTrue);
        final fresh = policy.check();
        final joined = policy.check();
        expect(identical(fresh, joined), isTrue);
        expect(container.read(appUpdateProvider).isManualChecking, isTrue);
        manual.complete(_result('1.0.6'));
        expect((await fresh).release?.version, '1.0.6');
        expect((await old).release?.version, '1.0.6');
        if (lateFailure) {
          automatic.completeError(StateError('late outage'));
        } else {
          automatic.complete(_result('1.0.5'));
        }
        await Future<void>.delayed(Duration.zero);
        expect(container.read(appUpdateProvider).release?.version, '1.0.6');
        await policy.check(forceRefresh: false);
        expect(service.forces, [false, true]);
      },
    );
  }

  test(
    'automatic checks pause offline or hidden while manual requests remain explicit',
    () async {
      final policy = _PolicyUpdate()..available = false;
      final service = _PolicyService();
      final container = _container(service: service, notifier: policy);
      addTearDown(container.dispose);
      final hidden = policy.check(forceRefresh: false);
      expect(container.read(appUpdateProvider).status, AppUpdateStatus.idle);
      expect(service.forces, isEmpty);
      await policy.check();
      await hidden;
      expect(service.forces, [true]);
      policy.available = true;
      policy.now = policy.now.add(const Duration(minutes: 10));
      globalState.setOfflineMode(true);
      final offline = policy.check(forceRefresh: false);
      expect(service.forces, [true]);
      globalState.setOfflineMode(false);
      policy.activity.networkChanged();
      await offline;
      expect(service.forces, [true, false]);
    },
  );

  test(
    'deferred automatic work does not cache a success or invent failure cooldown',
    () async {
      final policy = _PolicyUpdate();
      final response = Completer<AppUpdateCheckResult>();
      final service = _PolicyService()..loader = (_) => response.future;
      final container = _container(service: service, notifier: policy);
      addTearDown(container.dispose);
      final pending = policy.check(forceRefresh: false);
      policy.available = false;
      response.completeError(const AppUpdateCheckDeferred());
      await Future<void>.delayed(Duration.zero);
      expect(container.read(appUpdateProvider).status, AppUpdateStatus.idle);
      service.loader = (_) async => _result();
      policy.available = true;
      expect((await pending).status, AppUpdateStatus.available);
      expect(service.forces, [false, false]);
    },
  );

  test(
    'a paused startup replays once and removes its listener on disposal',
    () async {
      final policy = _PolicyUpdate()..available = false;
      final service = _PolicyService();
      final container = _container(service: service, notifier: policy);
      final first = policy.check(forceRefresh: false);
      final second = policy.check(forceRefresh: false);
      expect(identical(first, second), isTrue);
      expect(service.forces, isEmpty);
      policy.available = true;
      await Future.wait([first, second]);
      expect(service.forces, [false]);
      policy.available = false;
      policy.available = true;
      await Future<void>.delayed(Duration.zero);
      expect(service.forces, [false]);
      container.dispose();
      policy.available = false;
      policy.available = true;
      expect(service.forces, [false]);
    },
  );

  test(
    'disposing while paused completes pending callers without a resume request',
    () async {
      final policy = _PolicyUpdate()..available = false;
      final service = _PolicyService();
      final container = _container(service: service, notifier: policy);
      final pending = policy.check(forceRefresh: false);
      container.dispose();
      expect((await pending).status, AppUpdateStatus.idle);
      policy.available = true;
      await Future<void>.delayed(Duration.zero);
      expect(service.forces, isEmpty);
    },
  );

  test('clock rollback causes a fresh automatic check', () async {
    final policy = _PolicyUpdate();
    final service = _PolicyService();
    final container = _container(service: service, notifier: policy);
    addTearDown(container.dispose);
    await policy.check(forceRefresh: false);
    policy.now = policy.now.subtract(const Duration(seconds: 1));
    await policy.check(forceRefresh: false);
    expect(service.forces, [false, false]);
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
  AppUpdate? notifier,
}) {
  final dependency = service ?? _service(manifestLoader: manifestLoader);
  addTearDown(dependency.close);
  final container = ProviderContainer(
    overrides: [
      appUpdateServiceProvider.overrideWithValue(dependency),
      appUpdateCurrentVersionProvider.overrideWithValue(currentVersion),
      if (notifier != null) appUpdateProvider.overrideWith(() => notifier),
    ],
  );
  container.read(appUpdateProvider);
  return container;
}

AppUpdateService _service({
  AppUpdateMainConfigLoader? mainConfigLoader,
  AppUpdateManifestLoader? manifestLoader,
}) => AppUpdateService(
  mainConfigLoader:
      mainConfigLoader ??
      () async => {'UpdateUrl': 'https://update.example/manifest.json'},
  manifestLoader: manifestLoader ?? (_) async => _manifest(),
  packageKeyResolver: () => 'android-arm64-v8a',
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
      'android-arm64-v8a': {
        'enabled': enabled,
        'version': version,
        'downloadUrl': 'https://update.example/FengWo-$version.apk',
        'releaseNotesHtml': '<p>Update</p>',
      },
  },
};

class _PolicyUpdate extends AppUpdate {
  DateTime now = DateTime.utc(2026, 10, 25);
  final activity = ApiRemoteConfigActivity();
  bool get available => activity.isAvailable;
  set available(bool value) => activity.setAppForeground(value);

  @override
  ApiHealthService createUpdateAvailabilityService() =>
      ApiHealthService(activity: activity);

  @override
  DateTime get updateCheckNow => now;

  @override
  bool get canAutomaticallyCheckUpdates =>
      available && !globalState.isOfflineMode;
}

class _PolicyService extends AppUpdateService {
  final forces = <bool>[];
  Future<AppUpdateCheckResult> Function(bool)? loader;

  @override
  Future<AppUpdateCheckResult> discoverUpdate({
    required String currentVersion,
    bool forceRefresh = false,
    bool Function()? canFetch,
  }) {
    forces.add(forceRefresh);
    return loader?.call(forceRefresh) ?? Future.value(_result());
  }
}

AppUpdateCheckResult _result([String version = '1.0.5']) =>
    AppUpdateCheckResult(
      status: AppUpdateCheckStatus.available,
      release: AppUpdateRelease(
        packageKey: 'windows-x64',
        version: version,
        downloadUri: Uri.parse('https://update.example/app.exe'),
        releaseNotesHtml: '',
      ),
    );

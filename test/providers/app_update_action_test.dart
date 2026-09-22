import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:fl_clash/common/app_update.dart';
import 'package:fl_clash/common/app_update_download.dart';
import 'package:fl_clash/l10n/l10n.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/app_update_download.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await AppLocalizations.load(const Locale('en'));
  });

  testWidgets(
    'manual click joins an ignored automatic check and opens one dialog',
    (tester) async {
      final response = Completer<Object?>();
      var calls = 0;
      final service = _service(
        manifestLoader: (_) {
          calls++;
          return response.future;
        },
      );
      await service.ignore(_release());
      final container = _container(service);
      await _mount(tester);
      try {
        final action = container.read(commonActionProvider.notifier);
        final automatic = action.checkAppUpdate();
        final manual = action.checkAppUpdate(isUser: true);
        expect(identical(automatic, manual), isTrue);
        response.complete(_manifest());
        await tester.pumpAndSettle();

        expect(calls, 1);
        expect(find.byKey(const ValueKey('app-update-dialog')), findsOneWidget);
        expect(container.read(appUpdateProvider).isChecking, isFalse);
        expect(container.read(appUpdateProvider).hasUpdate, isTrue);
        final repeated = action.checkAppUpdate(isUser: true);
        expect(identical(manual, repeated), isTrue);

        await tester.tap(find.byKey(const ValueKey('app-update-later')));
        await tester.pumpAndSettle();
        await Future.wait([automatic, manual, repeated]);
        expect(find.byKey(const ValueKey('app-update-dialog')), findsNothing);
        expect(container.read(appUpdateProvider).hasUpdate, isTrue);
        expect(calls, 1);
      } finally {
        await tester.pumpWidget(const SizedBox());
        container.dispose();
      }
    },
  );

  testWidgets(
    'manual request can promote a check waiting on ignored preferences',
    (tester) async {
      final preferences = _PendingPreferences();
      final container = _container(_service(preferenceStore: preferences));
      await _mount(tester);
      try {
        final action = container.read(commonActionProvider.notifier);
        final automatic = action.checkAppUpdate();
        await tester.pumpAndSettle();
        expect(preferences.calls, 1);
        expect(container.read(appUpdateProvider).isChecking, isFalse);
        expect(find.byKey(const ValueKey('app-update-dialog')), findsNothing);
        final manual = action.checkAppUpdate(isUser: true);
        preferences.response.complete(true);
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('app-update-dialog')), findsOneWidget);
        await tester.tap(find.byKey(const ValueKey('app-update-close')));
        await tester.pumpAndSettle();
        await Future.wait([automatic, manual]);
      } finally {
        await tester.pumpWidget(const SizedBox());
        container.dispose();
      }
    },
  );

  testWidgets(
    'ignored automatic updates keep dots and a later manual check still opens',
    (tester) async {
      final service = _service();
      await service.ignore(_release());
      final container = _container(service);
      await _mount(tester);
      try {
        final action = container.read(commonActionProvider.notifier);
        final automatic = action.checkAppUpdate();
        await tester.pumpAndSettle();
        await automatic;
        expect(find.byKey(const ValueKey('app-update-dialog')), findsNothing);
        expect(container.read(appUpdateProvider).hasUpdate, isTrue);

        final manual = action.checkAppUpdate(isUser: true);
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('app-update-dialog')), findsOneWidget);
        await tester.tap(find.byKey(const ValueKey('app-update-ignore')));
        await tester.pumpAndSettle();
        await manual;
        expect(container.read(appUpdateProvider).hasUpdate, isTrue);
      } finally {
        await tester.pumpWidget(const SizedBox());
        container.dispose();
      }
    },
  );

  testWidgets('a manual request is not swallowed by silent badge discovery', (
    tester,
  ) async {
    final response = Completer<Object?>();
    var calls = 0;
    final container = _container(
      _service(
        manifestLoader: (_) {
          calls++;
          return response.future;
        },
      ),
    );
    await _mount(tester);
    try {
      final action = container.read(commonActionProvider.notifier);
      final silent = action.checkAppUpdate(showPrompt: false);
      final manual = action.checkAppUpdate(isUser: true);
      response.complete(_manifest());
      await tester.pumpAndSettle();
      await silent;
      expect(calls, 1);
      expect(find.byKey(const ValueKey('app-update-dialog')), findsOneWidget);
      expect(container.read(appUpdateProvider).isChecking, isFalse);

      await tester.tap(find.byKey(const ValueKey('app-update-close')));
      await tester.pumpAndSettle();
      await manual;
      expect(container.read(appUpdateProvider).hasUpdate, isTrue);
    } finally {
      await tester.pumpWidget(const SizedBox());
      container.dispose();
    }
  });

  for (final previousAutoPreference in [false, true]) {
    testWidgets(
      'desktop startup only updates badges with legacy preference $previousAutoPreference',
      (tester) async {
        var calls = 0;
        final container = _container(
          _service(
            manifestLoader: (_) async {
              calls++;
              return _manifest();
            },
          ),
          autoCheckUpdate: previousAutoPreference,
        );
        await _mount(tester);
        try {
          final action = container.read(commonActionProvider.notifier);
          final automatic = action.autoCheckUpdate();
          await tester.pumpAndSettle();
          await automatic;
          expect(calls, 1);
          expect(container.read(appUpdateProvider).hasUpdate, isTrue);
          expect(container.read(appUpdateProvider).isChecking, isFalse);
          expect(find.byKey(const ValueKey('app-update-dialog')), findsNothing);

          final manual = action.checkAppUpdate(isUser: true);
          await tester.pumpAndSettle();
          expect(calls, 2);
          expect(
            find.byKey(const ValueKey('app-update-dialog')),
            findsOneWidget,
          );
          await tester.tap(find.byKey(const ValueKey('app-update-close')));
          await tester.pumpAndSettle();
          await manual;
          expect(container.read(appUpdateProvider).hasUpdate, isTrue);
        } finally {
          await tester.pumpWidget(const SizedBox());
          container.dispose();
        }
      },
      skip: !Platform.isWindows && !Platform.isMacOS,
    );
  }

  testWidgets('manual checks do not depend on automatic prompt preferences', (
    tester,
  ) async {
    final container = _container(
      _service(preferenceStore: _UnavailablePreferences()),
    );
    await _mount(tester);
    try {
      final check = container
          .read(commonActionProvider.notifier)
          .checkAppUpdate(isUser: true);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('app-update-dialog')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('app-update-close')));
      await tester.pumpAndSettle();
      await check;
    } finally {
      await tester.pumpWidget(const SizedBox());
      container.dispose();
    }
  });

  testWidgets(
    'manual update hands off to scoped download progress and verified installation',
    (tester) async {
      final temporary = (await tester.runAsync(
        () => Directory.systemTemp.createTemp('fengwo-action-download-'),
      ))!;
      final bytes = utf8.encode('FengWo action test installer');
      final stream = StreamController<List<int>>();
      final started = Completer<void>();
      var downloads = 0;
      final launchedPaths = <String>[];
      final downloadService = AppUpdateDownloadService(
        temporaryDirectoryLoader: () async => temporary,
        packageKeyResolver: () => 'windows-x64',
        transport: (uri, _) async {
          expect(uri, Uri.parse('https://update.example/FengWo.exe'));
          downloads++;
          started.complete();
          return AppUpdateDownloadResponse(
            bytes: stream.stream,
            totalBytes: bytes.length,
          );
        },
        launcher: (path) async {
          launchedPaths.add(path);
          return true;
        },
      );
      final manifest = _manifest();
      ((manifest['packages'] as Map)['windows-x64'] as Map)['sha256'] = sha256
          .convert(bytes)
          .toString();
      final container = _container(
        _service(manifestLoader: (_) async => manifest),
        downloadService: downloadService,
      );
      final progress = Completer<void>();
      final ready = Completer<void>();
      final installed = Completer<void>();
      final stateSubscription = container.listen(appUpdateDownloadProvider, (
        _,
        next,
      ) {
        if (next.receivedBytes == bytes.length && !progress.isCompleted) {
          progress.complete();
        }
        if (next.status == AppUpdateDownloadStatus.ready &&
            !ready.isCompleted) {
          ready.complete();
        }
        if (next.installerLaunched && !installed.isCompleted) {
          installed.complete();
        }
      });
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            navigatorKey: globalState.navigatorKey,
            localizationsDelegates: const [AppLocalizations.delegate],
            home: const Scaffold(body: SizedBox()),
          ),
        ),
      );
      try {
        final action = container.read(commonActionProvider.notifier);
        final check = action.checkAppUpdate(isUser: true);
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('app-update-dialog')), findsOneWidget);
        await tester.tap(find.byKey(const ValueKey('app-update-confirm')));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        await _pumpUntil(tester, () => started.isCompleted);
        expect(container.read(appUpdateProvider).isChecking, isFalse);
        expect(downloads, 1);
        stream.add(bytes);
        await _pumpUntil(tester, () => progress.isCompleted);
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('app-update-dialog')), findsNothing);
        expect(
          find.byKey(const ValueKey('app-update-download-dialog')),
          findsOneWidget,
        );
        expect(find.text('100%'), findsOneWidget);
        expect(
          tester
              .widget<LinearProgressIndicator>(
                find.byKey(const ValueKey('app-update-download-progress')),
              )
              .value,
          1,
        );
        expect(launchedPaths, isEmpty);
        expect(identical(action.checkAppUpdate(isUser: true), check), isTrue);
        unawaited(stream.close());
        await _pumpUntil(tester, () => ready.isCompleted);
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('app-update-install')),
          findsOneWidget,
        );
        expect(container.read(appUpdateProvider).hasUpdate, isTrue);
        await tester.tap(find.byKey(const ValueKey('app-update-install')));
        await tester.pump();
        await _pumpUntil(tester, () => installed.isCompleted);
        await tester.pumpAndSettle();
        expect(launchedPaths, hasLength(1));
        expect(launchedPaths.single, endsWith('.exe'));
        expect(downloads, 1);
        await tester.tap(
          find.byKey(const ValueKey('app-update-download-close')),
        );
        await tester.pumpAndSettle();
        await check;
        expect(
          find.byKey(const ValueKey('app-update-download-dialog')),
          findsNothing,
        );
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox());
        stateSubscription.close();
        container.dispose();
        downloadService.dispose();
        await tester.runAsync(() async {
          if (!stream.isClosed) unawaited(stream.close());
          await temporary.delete(recursive: true);
        });
      }
    },
    skip: !Platform.isWindows && !Platform.isMacOS,
  );

  testWidgets('disposal before check completion suppresses late dialogs', (
    tester,
  ) async {
    final response = Completer<Object?>();
    final container = _container(
      _service(manifestLoader: (_) => response.future),
    );
    await _mount(tester);
    try {
      final check = container
          .read(commonActionProvider.notifier)
          .checkAppUpdate(isUser: true);
      container.dispose();
      response.complete(_manifest());
      await tester.pumpAndSettle();
      await check;
      expect(find.byKey(const ValueKey('app-update-dialog')), findsNothing);
      expect(tester.takeException(), isNull);
    } finally {
      await tester.pumpWidget(const SizedBox());
    }
  });
}

Future<void> _mount(WidgetTester tester) => tester.pumpWidget(
  MaterialApp(
    navigatorKey: globalState.navigatorKey,
    localizationsDelegates: const [AppLocalizations.delegate],
    home: const Scaffold(body: SizedBox()),
  ),
);

ProviderContainer _container(
  AppUpdateService service, {
  bool autoCheckUpdate = true,
  AppUpdateDownloadService? downloadService,
}) {
  addTearDown(service.close);
  return ProviderContainer(
    overrides: [
      appUpdateServiceProvider.overrideWithValue(service),
      if (downloadService != null)
        appUpdateDownloadServiceProvider.overrideWithValue(downloadService),
      appUpdateCurrentVersionProvider.overrideWithValue('1.0.4+104'),
      appSettingProvider.overrideWithBuild(
        (_, _) => AppSettingProps(autoCheckUpdate: autoCheckUpdate),
      ),
    ],
  );
}

AppUpdateService _service({
  AppUpdateManifestLoader? manifestLoader,
  AppUpdatePreferenceStore? preferenceStore,
}) => AppUpdateService(
  mainConfigLoader: () async => {
    'UpdateUrl': 'https://update.example/update.json',
  },
  manifestLoader: manifestLoader ?? (_) async => _manifest(),
  packageKeyResolver: () => 'windows-x64',
  preferenceStore: preferenceStore,
  aesKey: '',
  signingPublicKey: '',
);

AppUpdateRelease _release() => AppUpdateRelease(
  packageKey: 'windows-x64',
  version: '1.0.5',
  downloadUri: Uri.parse('https://update.example/FengWo.exe'),
  releaseNotesHtml: '<p>Update</p>',
);

Map<String, Object?> _manifest() => {
  'Authentication': 'FengWo',
  'format': 'fengwo-update',
  'schemaVersion': 1,
  'packages': {
    'windows-x64': {
      'enabled': true,
      'version': '1.0.5',
      'downloadUrl': 'https://update.example/FengWo.exe',
      'releaseNotesHtml': '<p>Update</p>',
    },
  },
};

class _UnavailablePreferences extends AppUpdatePreferenceStore {
  @override
  Future<bool> isIgnored(String packageKey, String version) async {
    throw StateError('Preferences unavailable');
  }
}

class _PendingPreferences extends AppUpdatePreferenceStore {
  final response = Completer<bool>();
  int calls = 0;

  @override
  Future<bool> isIgnored(String packageKey, String version) {
    calls++;
    return response.future;
  }
}

Future<void> _pumpUntil(WidgetTester tester, bool Function() completed) async {
  final clock = Stopwatch()..start();
  while (!completed()) {
    if (clock.elapsed > const Duration(seconds: 5)) {
      fail('Download state did not complete');
    }
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump();
  }
}

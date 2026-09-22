import 'dart:async';

import 'package:fl_clash/common/app_update.dart';
import 'package:fl_clash/common/app_update_download.dart';
import 'package:fl_clash/l10n/l10n.dart';
import 'package:fl_clash/providers/app_update.dart';
import 'package:fl_clash/providers/app_update_download.dart';
import 'package:fl_clash/widgets/app_update_controls.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'both red dots preserve known updates on failure and clear when current',
    (tester) async {
      var remoteVersion = '1.0.5';
      var fail = false;
      final container = _container(
        manifestLoader: (_) async {
          if (fail) throw StateError('offline');
          return _manifest(remoteVersion);
        },
      );
      final updates = container.read(appUpdateProvider.notifier);
      await updates.check();
      await tester.pumpWidget(_TestApp(container: container));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('app-update-red-dot')),
        findsNWidgets(2),
      );
      expect(find.text('发现新版本 v1.0.5'), findsOneWidget);

      fail = true;
      await updates.check();
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('app-update-red-dot')),
        findsNWidgets(2),
      );
      expect(find.text('检查更新失败，请稍后重试。'), findsOneWidget);

      fail = false;
      remoteVersion = '1.0.4';
      await updates.check();
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('app-update-red-dot')), findsNothing);
      expect(find.text('v1.0.4 已是最新版本'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'settings check button disables while checking and displays a clean version',
    (tester) async {
      final response = Completer<Object?>();
      var calls = 0;
      final container = _container(
        manifestLoader: (_) {
          calls++;
          return response.future;
        },
      );
      await tester.pumpWidget(_TestApp(container: container));
      await tester.pump();

      expect(container.read(appUpdateProvider).isChecking, isTrue);
      expect(find.text('当前版本 v1.0.4'), findsOneWidget);
      expect(find.textContaining('+'), findsNothing);
      expect(
        tester
            .widget<FilledButton>(
              find.byKey(const ValueKey('advanced-check-update')),
            )
            .onPressed,
        isNull,
      );

      await tester.tap(find.byKey(const ValueKey('advanced-check-update')));
      await tester.pump();
      expect(calls, 1);
      final check = container.read(appUpdateProvider.notifier).check();
      response.complete(_manifest('1.0.5'));
      await check;
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<FilledButton>(
              find.byKey(const ValueKey('advanced-check-update')),
            )
            .onPressed,
        isNotNull,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'background progress remains visible and details reopen without restarting',
    (tester) async {
      final service = _ControlledDownloadService();
      final container = _container(downloadService: service);
      final result = await container.read(appUpdateProvider.notifier).check();
      await tester.pumpWidget(_TestApp(container: container));
      final download = container
          .read(appUpdateDownloadProvider.notifier)
          .download(result.release!);
      await tester.pumpAndSettle();

      expect(find.text('正在下载更新…'), findsOneWidget);
      expect(find.text('25%'), findsOneWidget);
      expect(
        tester
            .widget<LinearProgressIndicator>(
              find.byKey(const ValueKey('app-update-download-progress')),
            )
            .value,
        0.25,
      );
      await tester.tap(
        find.byKey(const ValueKey('advanced-update-download-details')),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('app-update-download-dialog')),
        findsOneWidget,
      );
      expect(find.text('后台下载'), findsOneWidget);
      expect(service.downloadCalls, 1);

      await tester.tap(find.byKey(const ValueKey('app-update-download-close')));
      await tester.pumpAndSettle();
      service.emitProgress(512, 1024);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('app-update-download-dialog')),
        findsNothing,
      );
      expect(find.text('50%'), findsOneWidget);
      expect(container.read(appUpdateDownloadProvider).isBusy, isTrue);

      await tester.tap(
        find.byKey(const ValueKey('advanced-update-download-details')),
      );
      await tester.pumpAndSettle();
      final dialog = find.byKey(const ValueKey('app-update-download-dialog'));
      expect(
        find.descendant(of: dialog, matching: find.text('50%')),
        findsOneWidget,
      );
      expect(service.downloadCalls, 1);

      service.complete();
      await download;
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('app-update-install')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('app-update-download-close')));
      await tester.pumpAndSettle();
      expect(find.text('下载和校验已完成，可以安装更新。'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}

ProviderContainer _container({
  AppUpdateManifestLoader? manifestLoader,
  AppUpdateDownloadService? downloadService,
}) {
  final service = AppUpdateService(
    mainConfigLoader: () async => {
      'UpdateUrl': 'https://update.example/manifest.json',
    },
    manifestLoader: manifestLoader ?? (_) async => _manifest('1.0.5'),
    packageKeyResolver: () => 'windows-x64',
    aesKey: '',
    signingPublicKey: '',
  );
  final downloads = downloadService ?? AppUpdateDownloadService();
  final container = ProviderContainer(
    overrides: [
      appUpdateServiceProvider.overrideWithValue(service),
      appUpdateCurrentVersionProvider.overrideWithValue('v1.0.4+104'),
      appUpdateDownloadServiceProvider.overrideWithValue(downloads),
    ],
  );
  addTearDown(service.close);
  addTearDown(downloads.dispose);
  addTearDown(container.dispose);
  return container;
}

Map<String, Object?> _manifest(String version) => {
  'Authentication': 'FengWo',
  'format': 'fengwo-update',
  'schemaVersion': 1,
  'packages': {
    'windows-x64': {
      'enabled': true,
      'version': version,
      'downloadUrl': 'https://update.example/FengWo-$version.exe',
      'releaseNotesHtml': '<p>Update</p>',
    },
  },
};

class _ControlledDownloadService extends AppUpdateDownloadService {
  final _completion = Completer<String>();
  AppUpdateDownloadProgress? _onProgress;
  var downloadCalls = 0;

  @override
  Future<String> download(
    AppUpdateRelease release, {
    AppUpdateDownloadProgress? onProgress,
    void Function()? onVerifying,
  }) {
    downloadCalls++;
    _onProgress = onProgress;
    emitProgress(256, 1024);
    return _completion.future;
  }

  void emitProgress(int received, int total) =>
      _onProgress?.call(received, total);

  void complete() => _completion.complete('/tmp/FengWo-1.0.5.exe');

  @override
  void cancel() {
    if (downloadCalls > 0 && !_completion.isCompleted) {
      _completion.completeError(const AppUpdateDownloadCancelled());
    }
  }
}

class _TestApp extends StatelessWidget {
  const _TestApp({required this.container});

  final ProviderContainer container;

  @override
  Widget build(BuildContext context) {
    return UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        locale: const Locale('zh', 'CN'),
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.delegate.supportedLocales,
        home: const Scaffold(
          body: SingleChildScrollView(
            padding: EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                AppUpdateBadge(child: Text('高级设置')),
                SizedBox(height: 12),
                AppUpdateSettingsContent(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

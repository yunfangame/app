import 'package:fl_clash/common/app_update.dart';
import 'package:fl_clash/common/app_update_download.dart';
import 'package:fl_clash/l10n/l10n.dart';
import 'package:fl_clash/providers/app_update_download.dart';
import 'package:fl_clash/widgets/app_update_download_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

final _release = AppUpdateRelease(
  packageKey: 'windows-x64',
  version: '1.0.5+105',
  downloadUri: Uri.parse('https://example.com/FengWo.exe'),
  releaseNotesHtml: '',
);

void main() {
  testWidgets('downloads once and closing keeps the transfer in background', (
    tester,
  ) async {
    final notifier = _Download();
    final context = await _pump(tester, notifier);
    final first = showAppUpdateDownloadDialog(
      context: context,
      release: _release,
    );
    final second = showAppUpdateDownloadDialog(
      context: context,
      release: _release,
    );
    expect(identical(first, second), isTrue);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(notifier.downloads, 1);
    expect(
      find.byKey(const ValueKey('app-update-download-dialog')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('app-update-install')), findsNothing);
    expect(find.textContaining('+105'), findsNothing);

    notifier.emit(
      AppUpdateDownloadState(
        release: _release,
        status: AppUpdateDownloadStatus.downloading,
        receivedBytes: 1024 * 1024,
        totalBytes: 4 * 1024 * 1024,
      ),
    );
    await tester.pump();
    expect(find.text('25%'), findsOneWidget);
    expect(
      tester
          .widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator))
          .value,
      0.25,
    );
    expect(
      find.byKey(const ValueKey('app-update-download-bytes')),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey('app-update-download-close')));
    await tester.pumpAndSettle();
    await first;
    expect(notifier.cancels, 0);
    expect(notifier.state.status, AppUpdateDownloadStatus.downloading);

    final reopened = showAppUpdateDownloadDialog(
      context: context,
      release: _release,
      startDownload: false,
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('25%'), findsOneWidget);
    expect(notifier.downloads, 1);
    await tester.tap(find.byKey(const ValueKey('app-update-download-cancel')));
    await tester.pumpAndSettle();
    expect(notifier.cancels, 1);
    expect(find.byKey(const ValueKey('app-update-install')), findsNothing);
    expect(
      find.byKey(const ValueKey('app-update-download-retry')),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey('app-update-download-retry')));
    await tester.pump();
    expect(notifier.downloads, 2);
    await tester.tap(find.byKey(const ValueKey('app-update-download-close')));
    await tester.pumpAndSettle();
    await reopened;
  });

  testWidgets('unknown length remains indeterminate and shows received bytes', (
    tester,
  ) async {
    final notifier = _Download(
      initial: AppUpdateDownloadState(
        release: _release,
        status: AppUpdateDownloadStatus.downloading,
        receivedBytes: 2048,
      ),
    );
    final context = await _pump(tester, notifier);
    final dialog = showAppUpdateDownloadDialog(
      context: context,
      release: _release,
      startDownload: false,
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(
      tester
          .widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator))
          .value,
      isNull,
    );
    expect(
      find.byKey(const ValueKey('app-update-download-percentage')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('app-update-download-bytes')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
    await tester.tap(find.byKey(const ValueKey('app-update-download-close')));
    await tester.pumpAndSettle();
    await dialog;
  });

  testWidgets(
    'install is explicit and unavailable before successful verification',
    (tester) async {
      final notifier = _Download(
        initial: AppUpdateDownloadState(
          release: _release,
          status: AppUpdateDownloadStatus.verifying,
        ),
      );
      final context = await _pump(tester, notifier);
      final dialog = showAppUpdateDownloadDialog(
        context: context,
        release: _release,
        startDownload: false,
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(notifier.installs, 0);
      expect(find.byKey(const ValueKey('app-update-install')), findsNothing);
      notifier.emit(
        AppUpdateDownloadState(
          release: _release,
          status: AppUpdateDownloadStatus.ready,
          filePath: '/tmp/FengWo.exe',
        ),
      );
      await tester.pumpAndSettle();
      expect(notifier.installs, 0);
      await tester.tap(find.byKey(const ValueKey('app-update-install')));
      await tester.pump();
      expect(notifier.installs, 1);
      expect(find.byKey(const ValueKey('app-update-install')), findsNothing);
      expect(
        find.byKey(const ValueKey('app-update-download-cancel')),
        findsNothing,
      );
      notifier.emit(
        AppUpdateDownloadState(
          release: _release,
          status: AppUpdateDownloadStatus.ready,
          installerLaunched: true,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('app-update-install')), findsNothing);
      expect(find.textContaining('安装程序已打开'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('app-update-download-close')));
      await tester.pumpAndSettle();
      await dialog;
    },
  );

  testWidgets(
    'checksum error cannot install and retries downloading in narrow view',
    (tester) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final notifier = _Download(
        initial: AppUpdateDownloadState(
          release: _release,
          status: AppUpdateDownloadStatus.failed,
          failure: AppUpdateDownloadFailure.checksumMismatch,
        ),
      );
      final context = await _pump(tester, notifier);
      final dialog = showAppUpdateDownloadDialog(
        context: context,
        release: _release,
        startDownload: false,
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('app-update-install')), findsNothing);
      expect(find.textContaining('校验失败'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.byKey(const ValueKey('app-update-download-retry')));
      await tester.pump();
      expect(notifier.downloads, 1);
      expect(notifier.installs, 0);
      await tester.tap(find.byKey(const ValueKey('app-update-download-close')));
      await tester.pumpAndSettle();
      await dialog;
    },
  );

  testWidgets(
    'installer opening failure retries opening without a new download',
    (tester) async {
      final notifier = _Download(
        initial: AppUpdateDownloadState(
          release: _release,
          status: AppUpdateDownloadStatus.failed,
          failure: AppUpdateDownloadFailure.launchFailed,
          filePath: '/tmp/FengWo.exe',
        ),
      );
      final context = await _pump(tester, notifier);
      final dialog = showAppUpdateDownloadDialog(
        context: context,
        release: _release,
        startDownload: false,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('app-update-download-retry')));
      await tester.pump();
      expect(notifier.installs, 1);
      expect(notifier.downloads, 0);
      await tester.tap(find.byKey(const ValueKey('app-update-download-close')));
      await tester.pumpAndSettle();
      await dialog;
    },
  );
}

Future<BuildContext> _pump(WidgetTester tester, _Download notifier) async {
  final container = ProviderContainer(
    overrides: [appUpdateDownloadProvider.overrideWith(() => notifier)],
  );
  addTearDown(container.dispose);
  late BuildContext context;
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        locale: const Locale('zh', 'CN'),
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.delegate.supportedLocales,
        home: Builder(
          builder: (value) {
            context = value;
            return const Scaffold(body: SizedBox());
          },
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return context;
}

class _Download extends AppUpdateDownload {
  _Download({this.initial = const AppUpdateDownloadState()});
  final AppUpdateDownloadState initial;
  int downloads = 0;
  int cancels = 0;
  int installs = 0;

  @override
  AppUpdateDownloadState build() => initial;

  void emit(AppUpdateDownloadState value) => state = value;

  @override
  Future<void> download(AppUpdateRelease release) async {
    downloads++;
    state = AppUpdateDownloadState(
      release: release,
      status: AppUpdateDownloadStatus.downloading,
    );
  }

  @override
  void cancel() {
    cancels++;
    state = AppUpdateDownloadState(
      release: state.release,
      status: AppUpdateDownloadStatus.cancelled,
    );
  }

  @override
  Future<void> install() async {
    installs++;
    state = AppUpdateDownloadState(
      release: state.release,
      status: AppUpdateDownloadStatus.installing,
    );
  }
}

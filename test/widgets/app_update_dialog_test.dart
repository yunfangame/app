import 'package:fl_clash/common/app_update.dart';
import 'package:fl_clash/l10n/l10n.dart';
import 'package:fl_clash/widgets/app_update_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final release = AppUpdateRelease(
    packageKey: 'macos-arm64',
    version: '1.0.5+105',
    downloadUri: Uri.parse('https://house.example/fengwo.pkg'),
    releaseNotesHtml: '<h3>重要更新</h3><ul><li>修复校园网模式</li></ul>',
    title: '蜂窝加速器更新',
  );

  testWidgets('renders HTML notes and returns ignore-version decision', (
    tester,
  ) async {
    AppUpdateDecision? decision;
    await tester.pumpWidget(
      _TestApp(release: release, onDecision: (value) => decision = value),
    );

    await tester.tap(find.text('show'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('app-update-dialog')), findsOneWidget);
    expect(find.text('蜂窝加速器更新'), findsOneWidget);
    expect(find.text('重要更新'), findsOneWidget);
    expect(find.text('修复校园网模式'), findsOneWidget);
    expect(find.text('当前 v1.0.4  →  最新 v1.0.5'), findsOneWidget);
    expect(find.textContaining('+'), findsNothing);

    await tester.tap(find.text('不再提示此版本'));
    await tester.pumpAndSettle();
    expect(decision, AppUpdateDecision.ignoreVersion);
  });

  testWidgets('supports updating later', (tester) async {
    AppUpdateDecision? decision;
    await tester.pumpWidget(
      _TestApp(release: release, onDecision: (value) => decision = value),
    );
    await tester.tap(find.text('show'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('app-update-later')));
    await tester.pumpAndSettle();
    expect(decision, AppUpdateDecision.later);
  });

  testWidgets('labels the primary action as downloading the update', (
    tester,
  ) async {
    AppUpdateDecision? decision;
    await tester.pumpWidget(
      _TestApp(release: release, onDecision: (value) => decision = value),
    );
    await tester.tap(find.text('show'));
    await tester.pumpAndSettle();
    expect(find.text('立即更新'), findsNothing);
    await tester.tap(find.text('下载更新'));
    await tester.pumpAndSettle();
    expect(decision, AppUpdateDecision.update);
  });

  testWidgets('localizes the default title and all actions in English', (
    tester,
  ) async {
    await tester.pumpWidget(
      _TestApp(
        locale: const Locale('en'),
        release: AppUpdateRelease(
          packageKey: release.packageKey,
          version: 'v1.0.5+105',
          downloadUri: release.downloadUri,
          releaseNotesHtml: '<p>Improved update downloads.</p>',
        ),
      ),
    );
    await tester.tap(find.text('show'));
    await tester.pumpAndSettle();
    expect(find.text('Discover the new version'), findsOneWidget);
    expect(find.text('Current v1.0.4  →  Latest v1.0.5'), findsOneWidget);
    expect(find.text('Download update'), findsOneWidget);
    expect(find.text('Skip this version'), findsOneWidget);
    expect(find.text('Remind me later'), findsOneWidget);
    expect(
      tester
          .widget<IconButton>(find.byKey(const ValueKey('app-update-close')))
          .tooltip,
      'Remind me later',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'keeps update actions reachable with long notes in a narrow view',
    (tester) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      AppUpdateDecision? decision;
      await tester.pumpWidget(
        _TestApp(
          locale: const Locale('ru'),
          release: AppUpdateRelease(
            packageKey: release.packageKey,
            version: release.version,
            downloadUri: release.downloadUri,
            releaseNotesHtml: List.generate(
              30,
              (index) => '<p>Улучшение приложения ${index + 1}</p>',
            ).join(),
          ),
          onDecision: (value) => decision = value,
        ),
      );
      await tester.tap(find.text('show'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.drag(
        find.byKey(const ValueKey('app-update-html-scroll')),
        const Offset(0, -400),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('app-update-confirm')));
      await tester.pumpAndSettle();
      expect(decision, AppUpdateDecision.update);
      expect(tester.takeException(), isNull);
    },
  );
}

class _TestApp extends StatelessWidget {
  const _TestApp({
    required this.release,
    this.locale = const Locale('zh', 'CN'),
    this.onDecision,
  });

  final AppUpdateRelease release;
  final Locale locale;
  final ValueChanged<AppUpdateDecision?>? onDecision;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      locale: locale,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.delegate.supportedLocales,
      home: Scaffold(
        body: Builder(
          builder: (context) => FilledButton(
            onPressed: () async {
              final decision = await showAppUpdateDialog(
                context: context,
                release: release,
                currentVersion: 'v1.0.4+104',
              );
              onDecision?.call(decision);
            },
            child: const Text('show'),
          ),
        ),
      ),
    );
  }
}

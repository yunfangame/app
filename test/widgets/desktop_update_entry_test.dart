import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/common/theme.dart';
import 'package:fl_clash/l10n/l10n.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/state.dart';
import 'package:fl_clash/views/about.dart';
import 'package:fl_clash/views/application_setting.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';

void main() {
  setUpAll(() {
    globalState.packageInfo = PackageInfo(
      appName: 'FengWo',
      packageName: 'com.fengwo.app',
      version: '1.0.4',
      buildNumber: '104',
    );
  });

  testWidgets(
    'desktop About keeps product information without a second update entry',
    (tester) async {
      await _pumpView(tester, const AboutView());
      final l10n = tester.element(find.byType(AboutView)).appLocalizations;

      expect(find.text('1.0.4'), findsOneWidget);
      expect(find.text('Telegram'), findsOneWidget);
      expect(find.text(l10n.project), findsOneWidget);
      expect(find.text(l10n.core), findsOneWidget);
      expect(find.text(l10n.checkUpdate), findsNothing);
      expect(tester.takeException(), isNull);
    },
    skip: !system.isDesktop,
  );

  testWidgets(
    'desktop application settings omit the legacy automatic-update switch',
    (tester) async {
      final container = await _pumpView(tester, const ApplicationSettingView());
      final l10n = tester
          .element(find.byType(ApplicationSettingView))
          .appLocalizations;

      expect(find.byType(AutoLaunchItem), findsOneWidget);
      expect(find.byType(UsageItem), findsOneWidget);
      expect(find.byType(AutoCheckUpdateItem), findsNothing);
      expect(find.text(l10n.autoCheckUpdate), findsNothing);
      expect(container.read(appSettingProvider).autoCheckUpdate, isTrue);
      expect(tester.takeException(), isNull);
    },
    skip: !system.isDesktop,
  );
}

Future<ProviderContainer> _pumpView(WidgetTester tester, Widget child) async {
  const size = Size(1200, 1400);
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  var updateRequests = 0;
  final service = AppUpdateService(
    mainConfigLoader: () async {
      updateRequests++;
      throw StateError('Unexpected update request');
    },
  );
  final container = ProviderContainer(
    overrides: [
      appSettingProvider.overrideWithBuild(
        (_, _) => const AppSettingProps(autoCheckUpdate: true),
      ),
      viewSizeProvider.overrideWithBuild((_, _) => size),
      appUpdateServiceProvider.overrideWithValue(service),
    ],
  );
  globalState.container = container;
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    container.dispose();
    service.close();
    expect(updateRequests, 0);
  });
  await tester.pumpWidget(
    UncontrolledProviderScope(
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
        builder: (context, child) {
          globalState.measure = Measure.of(context, 1);
          globalState.theme = CommonTheme.of(context, 1);
          return child!;
        },
        home: child,
      ),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

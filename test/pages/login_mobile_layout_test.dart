import 'package:fl_clash/common/api_health.dart';
import 'package:fl_clash/l10n/l10n.dart';
import 'package:fl_clash/pages/login.dart';
import 'package:fl_clash/widgets/brand_logo.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('mobile login shows the brand and login without scrolling', (
    tester,
  ) async {
    _useSize(tester, const Size(390, 844));
    await tester.pumpWidget(_testApp());
    await tester.pumpAndSettle();

    final brand = find.byKey(const Key('login-mobile-brand-lockup'));
    expect(brand, findsOneWidget);
    expect(tester.widget(brand), isA<FengWoBrandLockup>());
    expect(brand.hitTestable(), findsOneWidget);
    expect(
      find.byKey(const Key('fengwo-brand-logo')).hitTestable(),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);

    final submit = find.byKey(const Key('login-submit-button'));
    expect(submit.hitTestable(), findsOneWidget);
    expect(tester.widget<FilledButton>(submit).onPressed, isNotNull);
    final scrollable = find.ancestor(
      of: submit,
      matching: find.byType(Scrollable),
    );
    expect(scrollable, findsOneWidget);
    final position = tester.state<ScrollableState>(scrollable).position;
    expect(position.pixels, 0);
    expect(position.maxScrollExtent, lessThanOrEqualTo(8));
    expect(tester.takeException(), isNull);
  });

  testWidgets('small login scrolls with large text and an open keyboard', (
    tester,
  ) async {
    _useSize(tester, const Size(320, 568));
    await tester.pumpWidget(_testApp(textScale: 1.4));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    final password = find.byKey(const Key('login-password-field'));
    await tester.ensureVisible(password);
    await tester.showKeyboard(password);
    tester.view.viewInsets = const FakeViewPadding(bottom: 240);
    addTearDown(tester.view.resetViewInsets);
    await tester.pumpAndSettle();
    await tester.ensureVisible(password);
    await tester.pumpAndSettle();

    expect(password.hitTestable(), findsOneWidget);
    expect(find.byKey(const Key('login-mobile-brand-lockup')), findsNothing);
    expect(tester.takeException(), isNull);

    final submit = find.byKey(const Key('login-submit-button'));
    final scrollable = find.ancestor(
      of: submit,
      matching: find.byType(Scrollable),
    );
    expect(scrollable, findsWidgets);
    final position = tester.state<ScrollableState>(scrollable.first).position;
    expect(position.maxScrollExtent, greaterThan(0));

    await tester.ensureVisible(submit);
    await tester.pumpAndSettle();

    expect(position.pixels, greaterThan(0));
    expect(submit.hitTestable(), findsOneWidget);
    final buttonBounds = tester.getRect(submit);
    expect(buttonBounds.top, greaterThanOrEqualTo(0));
    expect(buttonBounds.bottom, lessThanOrEqualTo(568 - 240));
    for (final tooltip in ['语言', '主题', '在线客服']) {
      expect(find.byTooltip(tooltip).hitTestable(), findsOneWidget);
    }
    expect(
      find.byKey(const Key('api-health-status-button')).hitTestable(),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'mobile toolbar keeps all callbacks accessible on a narrow screen',
    (tester) async {
      _useSize(tester, const Size(320, 568));
      final calls = <String>[];
      await tester.pumpWidget(
        _testApp(
          textScale: 1.4,
          onLanguagePressed: (_) => calls.add('language'),
          onThemePressed: (_) => calls.add('theme'),
          onSupportPressed: (_) => calls.add('support'),
        ),
      );
      await tester.pumpAndSettle();

      for (final tooltip in ['语言', '主题', '在线客服']) {
        final button = find.byTooltip(tooltip);
        expect(button.hitTestable(), findsOneWidget);
        await tester.tap(button);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      }

      expect(calls, ['language', 'theme', 'support']);
      expect(
        find.byKey(const Key('api-health-status-button')).hitTestable(),
        findsOneWidget,
      );
    },
  );
}

Widget _testApp({
  double textScale = 1,
  ValueChanged<BuildContext>? onLanguagePressed,
  ValueChanged<BuildContext>? onThemePressed,
  ValueChanged<BuildContext>? onSupportPressed,
}) {
  return MaterialApp(
    theme: ThemeData(platform: TargetPlatform.android),
    locale: const Locale('zh', 'CN'),
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
    ],
    supportedLocales: AppLocalizations.delegate.supportedLocales,
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(
        context,
      ).copyWith(textScaler: TextScaler.linear(textScale)),
      child: child!,
    ),
    home: LoginPage(
      onLogin: () {},
      onLanguagePressed: onLanguagePressed ?? (_) {},
      onThemePressed: onThemePressed ?? (_) {},
      onSupportPressed: onSupportPressed ?? (_) {},
      appVersion: '1.0.6',
      apiHealthService: ApiHealthService(configUrl: ''),
    ),
  );
}

void _useSize(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

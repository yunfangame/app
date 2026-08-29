import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/l10n/l10n.dart';
import 'package:fl_clash/state.dart';
import 'package:fl_clash/widgets/subscription_status_indicator.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime(2026, 8, 29, 12);

  test('evaluates low traffic and finite expiry independently', () {
    final lowTraffic = evaluateSubscriptionStatus(
      _subscription(remainingGigabytes: 9),
      now: now,
    );
    expect(lowTraffic.lowTraffic, isTrue);
    expect(lowTraffic.expiringSoon, isFalse);
    expect(lowTraffic.hasWarning, isTrue);

    final expiring = evaluateSubscriptionStatus(
      _subscription(
        remainingGigabytes: 20,
        expiresAt: now.add(const Duration(days: 2)),
      ),
      now: now,
    );
    expect(expiring.lowTraffic, isFalse);
    expect(expiring.expiringSoon, isTrue);
    expect(expiring.hasWarning, isTrue);

    final boundary = evaluateSubscriptionStatus(
      _subscription(
        remainingGigabytes: 10,
        expiresAt: now.add(const Duration(days: 3)),
      ),
      now: now,
    );
    expect(boundary.hasWarning, isFalse);

    final expired = evaluateSubscriptionStatus(
      _subscription(
        remainingGigabytes: 20,
        expiresAt: now.subtract(const Duration(hours: 1)),
      ),
      now: now,
    );
    expect(expired.expired, isTrue);
    expect(expired.hasWarning, isTrue);
  });

  testWidgets('warning light rotates and lists every matching reason', (
    tester,
  ) async {
    await tester.pumpWidget(
      _TestApp(
        child: SubscriptionStatusIndicator(
          subscription: _subscription(
            remainingGigabytes: 9,
            expiresAt: now.add(const Duration(days: 2)),
          ),
          now: now,
        ),
      ),
    );
    await tester.pump();

    final light = find.byKey(const ValueKey('subscription-status-light'));
    final transform = find.descendant(
      of: light,
      matching: find.byType(Transform),
    );
    final before = tester
        .widget<Transform>(transform)
        .transform
        .storage
        .toList();
    await tester.pump(const Duration(milliseconds: 275));
    final after = tester
        .widget<Transform>(transform)
        .transform
        .storage
        .toList();
    expect(after, isNot(equals(before)));
    expect(before.first, greaterThan(0.98));
    expect(after.first, greaterThan(0.98));

    await tester.tap(
      find.byKey(const ValueKey('subscription-status-indicator')),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('subscription-status-dialog')),
      findsOneWidget,
    );
    expect(find.text('套餐预警'), findsOneWidget);
    expect(find.textContaining('不足 10 GB'), findsOneWidget);
    expect(find.textContaining('剩余不足 3 天'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('subscription-status-confirm')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('subscription-status-close')),
      findsOneWidget,
    );
    final renewPosition = tester.getTopLeft(
      find.byKey(const ValueKey('subscription-renew-button')),
    );
    final upgradePosition = tester.getTopLeft(
      find.byKey(const ValueKey('subscription-change-plan-button')),
    );
    final resetPosition = tester.getTopLeft(
      find.byKey(const ValueKey('subscription-reset-traffic-button')),
    );
    expect(renewPosition.dx, lessThan(upgradePosition.dx));
    expect(upgradePosition.dx, lessThan(resetPosition.dx));
    expect(tester.takeException(), isNull);
  });

  testWidgets('normal light stays static in a narrow Russian dark theme', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      _TestApp(
        locale: const Locale('ru'),
        themeMode: ThemeMode.dark,
        child: SubscriptionStatusIndicator(
          subscription: _subscription(remainingGigabytes: 20),
          now: now,
        ),
      ),
    );
    await tester.pumpAndSettle();

    final light = find.byKey(const ValueKey('subscription-status-light'));
    final transform = find.descendant(
      of: light,
      matching: find.byType(Transform),
    );
    final before = tester
        .widget<Transform>(transform)
        .transform
        .storage
        .toList();
    await tester.pump(const Duration(milliseconds: 400));
    final after = tester
        .widget<Transform>(transform)
        .transform
        .storage
        .toList();
    expect(after, equals(before));

    await tester.tap(
      find.byKey(const ValueKey('subscription-status-indicator')),
    );
    await tester.pumpAndSettle();
    expect(find.text('Тариф в норме'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('subscription-status-close')),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey('subscription-status-close')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('subscription-status-dialog')),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('warning actions fit a narrow Russian dark dialog', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      _TestApp(
        locale: const Locale('ru'),
        themeMode: ThemeMode.dark,
        child: SubscriptionStatusIndicator(
          subscription: _subscription(remainingGigabytes: 9),
          now: now,
        ),
      ),
    );
    await tester.pump();
    await tester.tap(
      find.byKey(const ValueKey('subscription-status-indicator')),
    );
    await tester.pumpAndSettle();

    expect(find.text('Продлить'), findsOneWidget);
    expect(find.text('Сбросить трафик'), findsOneWidget);
    expect(find.text('Улучшить тариф'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('subscription-status-close')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('reset action creates a reset-price order in the app', (
    tester,
  ) async {
    final periods = <String>[];
    final subscription = _subscription(remainingGigabytes: 9);
    globalState
      ..setOfflineMode(false)
      ..xboardSession = _session(subscription);
    addTearDown(globalState.clearXboardSession);
    addTearDown(() => globalState.setOfflineMode(false));

    await tester.pumpWidget(
      _TestApp(
        child: SubscriptionStatusIndicator(
          subscription: subscription,
          authService: _paymentService(periods),
          now: now,
        ),
      ),
    );
    await tester.pump();
    await tester.tap(
      find.byKey(const ValueKey('subscription-status-indicator')),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('subscription-renew-button')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('subscription-reset-traffic-button')),
      findsOneWidget,
    );
    await tester.tap(
      find.byKey(const ValueKey('subscription-reset-traffic-button')),
    );
    await _pumpDialogTransition(tester);

    expect(find.byKey(const ValueKey('payment-ready')), findsOneWidget);
    expect(find.text('重置'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('create-payment-qr')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    expect(periods, ['reset_price']);
    expect(find.byKey(const ValueKey('payment-qr-code')), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('change plan opens the plan catalog action', (tester) async {
    var changedPlan = false;
    await tester.pumpWidget(
      _TestApp(
        child: SubscriptionStatusIndicator(
          subscription: _subscription(remainingGigabytes: 9),
          onChangePlan: () => changedPlan = true,
          now: now,
        ),
      ),
    );
    await tester.pump();
    await tester.tap(
      find.byKey(const ValueKey('subscription-status-indicator')),
    );
    await tester.pumpAndSettle();

    final changePlanButton = find.byKey(
      const ValueKey('subscription-change-plan-button'),
    );
    expect(changePlanButton, findsOneWidget);
    expect(find.text('升级'), findsOneWidget);
    await tester.tap(changePlanButton);
    await _pumpDialogTransition(tester);

    expect(changedPlan, isTrue);
    expect(
      find.byKey(const ValueKey('subscription-status-dialog')),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('renewal explains traffic behavior before creating the order', (
    tester,
  ) async {
    final periods = <String>[];
    final subscription = _subscription(remainingGigabytes: 9);
    globalState
      ..setOfflineMode(false)
      ..xboardSession = _session(subscription);
    addTearDown(globalState.clearXboardSession);
    addTearDown(() => globalState.setOfflineMode(false));

    await tester.pumpWidget(
      _TestApp(
        child: SubscriptionStatusIndicator(
          subscription: subscription,
          authService: _paymentService(periods),
          now: now,
        ),
      ),
    );
    await tester.pump();
    await tester.tap(
      find.byKey(const ValueKey('subscription-status-indicator')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('subscription-renew-button')));
    await _pumpDialogTransition(tester);

    expect(
      find.byKey(const ValueKey('subscription-renewal-period-dialog')),
      findsOneWidget,
    );
    expect(find.textContaining('不会重置当前已使用流量'), findsOneWidget);
    await tester.tap(
      find.byKey(const ValueKey('subscription-renewal-period-month_price')),
    );
    await _pumpDialogTransition(tester);

    expect(find.byKey(const ValueKey('payment-ready')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('create-payment-qr')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    expect(periods, ['month_price']);
    expect(find.byKey(const ValueKey('payment-qr-code')), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('unlimited subscription omits renewal and keeps upgrade reset', (
    tester,
  ) async {
    await tester.pumpWidget(
      _TestApp(
        child: SubscriptionStatusIndicator(
          subscription: _subscription(remainingGigabytes: 9, unlimited: true),
          now: now,
        ),
      ),
    );
    await tester.pump();
    await tester.tap(
      find.byKey(const ValueKey('subscription-status-indicator')),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('subscription-renew-button')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('subscription-change-plan-button')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('subscription-reset-traffic-button')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
}

Future<void> _pumpDialogTransition(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 600));
  await tester.pump();
}

XboardSubscriptionData _subscription({
  required int remainingGigabytes,
  DateTime? expiresAt,
  bool unlimited = false,
}) {
  final endpoint = Uri.parse('https://api.example.com');
  const usedBytes = bytesPerGigabyte;
  return XboardSubscriptionData(
    endpoint: endpoint,
    subscribeUrl: Uri.parse('https://subscribe.example.com/client/token'),
    uploadBytes: usedBytes,
    downloadBytes: 0,
    transferEnableBytes: usedBytes + remainingGigabytes * bytesPerGigabyte,
    planId: 1,
    plan: const XboardPlanData(id: 1, name: '蜂窝月付套餐', rawData: {}),
    expiredAtEpochSeconds: unlimited
        ? null
        : (expiresAt ?? DateTime(2027, 8, 29)).millisecondsSinceEpoch ~/ 1000,
    rawData: const {},
  );
}

XboardLoginResult _session(XboardSubscriptionData subscription) {
  return XboardLoginResult(
    endpoint: subscription.endpoint,
    token: 'subscription-token',
    authData: 'Bearer subscription-token',
    isAdmin: false,
    subscription: subscription,
  );
}

XboardAuthService _paymentService(List<String> periods) {
  return XboardAuthService(
    plansRequester: (endpoint, authData) async {
      expect(endpoint.queryParameters['id'], '1');
      return const XboardLoginResponse(
        statusCode: 200,
        data: {
          'data': {
            'id': 1,
            'name': '蜂窝月付套餐',
            'content': '<p>高速专线</p>',
            'transfer_enable': 60,
            'month_price': 1000,
            'reset_price': 300,
            'sell': 1,
            'renew': 1,
          },
        },
      );
    },
    paymentMethodsRequester: (endpoint, authData) async =>
        const XboardLoginResponse(
          statusCode: 200,
          data: {
            'data': [
              {
                'id': 8,
                'name': '支付宝',
                'payment': 'AlipayF2F',
                'handling_fee_fixed': 0,
                'handling_fee_percent': 0,
              },
            ],
          },
        ),
    orderSaveRequester: (endpoint, authData, planId, period) async {
      periods.add(period);
      return XboardLoginResponse(
        statusCode: 200,
        data: {'data': 'ORDER-$period'},
      );
    },
    orderCheckoutRequester: (endpoint, authData, tradeNo, methodId) async =>
        XboardLoginResponse(
          statusCode: 200,
          data: {'type': 0, 'data': 'https://pay.example.com/$tradeNo'},
        ),
    orderCheckRequester: (endpoint, authData, tradeNo) async =>
        const XboardLoginResponse(statusCode: 200, data: {'data': 0}),
  );
}

class _TestApp extends StatelessWidget {
  const _TestApp({
    required this.child,
    this.locale = const Locale('zh', 'CN'),
    this.themeMode = ThemeMode.light,
  });

  final Widget child;
  final Locale locale;
  final ThemeMode themeMode;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      locale: locale,
      themeMode: themeMode,
      theme: ThemeData(colorSchemeSeed: const Color(0xFF1B6CF2)),
      darkTheme: ThemeData(
        brightness: Brightness.dark,
        colorSchemeSeed: const Color(0xFF7B8CFF),
      ),
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.delegate.supportedLocales,
      home: Scaffold(body: Center(child: child)),
    );
  }
}

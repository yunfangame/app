import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/l10n/l10n.dart';
import 'package:fl_clash/state.dart';
import 'package:fl_clash/views/plans/fengwo_purchase_plans.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('plan store filters real XBoard plans and renders HTML content', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(globalState.clearXboardSession);
    globalState.xboardSession = _testSession(planId: 1);

    await tester.pumpWidget(
      _TestApp(child: FengWoPurchasePlansView(authService: _testPlanService())),
    );
    await tester.pumpAndSettle();

    final l10n = tester
        .element(find.byType(FengWoPurchasePlansView))
        .appLocalizations;
    expect(find.byKey(const ValueKey('fengwo-plan-type-filter')), findsOne);
    expect(find.byKey(const ValueKey('fengwo-plan-1')), findsOne);
    expect(find.byKey(const ValueKey('fengwo-plan-2')), findsOne);
    expect(find.text(l10n.currentPlanLabel), findsOne);
    expect(find.text('高速专线'), findsOne);
    expect(find.text('流媒体解锁'), findsOne);

    await tester.tap(find.text(l10n.recurringPlans));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('fengwo-plan-1')), findsOne);
    expect(find.byKey(const ValueKey('fengwo-plan-2')), findsNothing);

    await tester.tap(find.text(l10n.oneTimePlans));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('fengwo-plan-1')), findsNothing);
    expect(find.byKey(const ValueKey('fengwo-plan-2')), findsOne);
    expect(tester.takeException(), isNull);
  });

  testWidgets('plan store remains stable on a narrow dark viewport', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(globalState.clearXboardSession);
    globalState.xboardSession = _testSession(planId: 1);

    await tester.pumpWidget(
      _TestApp(
        themeMode: ThemeMode.dark,
        child: FengWoPurchasePlansView(authService: _testPlanService()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('fengwo-plan-store-scroll')), findsOne);
    expect(find.byKey(const ValueKey('fengwo-plan-1')), findsOne);
    expect(tester.takeException(), isNull);
  });

  testWidgets('purchase stays in app and renders the checkout QR code', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1100, 850);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(globalState.clearXboardSession);
    globalState.xboardSession = _testSession(planId: 1);

    await tester.pumpWidget(
      _TestApp(
        child: FengWoPurchasePlansView(authService: _testPaymentService()),
      ),
    );
    await tester.pumpAndSettle();
    final l10n = tester
        .element(find.byType(FengWoPurchasePlansView))
        .appLocalizations;

    await tester.tap(find.text(l10n.buyNow).first);
    await tester.pumpAndSettle();

    expect(find.text(l10n.inAppPayment), findsOne);
    expect(find.text('支付宝'), findsOne);
    expect(find.byKey(const ValueKey('payment-ready')), findsOne);

    await tester.tap(find.byKey(const ValueKey('create-payment-qr')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    expect(find.byKey(const ValueKey('payment-qr')), findsOne);
    expect(find.byKey(const ValueKey('payment-qr-code')), findsOne);
    expect(find.text(l10n.waitingForPayment), findsOne);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('successful payment refreshes the active subscription once', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1100, 850);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(globalState.clearXboardSession);
    addTearDown(() => globalState.refreshXboardSubscription = null);
    globalState.xboardSession = _testSession(planId: 1);
    var refreshes = 0;
    globalState.refreshXboardSubscription = () async {
      refreshes++;
      return true;
    };

    await tester.pumpWidget(
      _TestApp(
        child: FengWoPurchasePlansView(
          authService: _testPaymentService(orderStatus: 1),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final l10n = tester
        .element(find.byType(FengWoPurchasePlansView))
        .appLocalizations;

    await tester.tap(find.text(l10n.buyNow).first);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('create-payment-qr')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    await tester.tap(find.text(l10n.iHavePaid));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('payment-success')), findsOneWidget);
    expect(refreshes, 1);
    expect(tester.takeException(), isNull);
  });
}

XboardAuthService _testPlanService() {
  return XboardAuthService(
    plansRequester: (endpoint, authData) async {
      return const XboardLoginResponse(
        statusCode: 200,
        data: {
          'data': [
            {
              'id': 1,
              'name': '白银套餐',
              'content': '<p><strong>高速专线</strong></p><ul><li>流媒体解锁</li></ul>',
              'transfer_enable': 1000,
              'speed_limit': null,
              'device_limit': null,
              'month_price': 10000,
              'quarter_price': 28000,
              'year_price': 100000,
              'sell': 1,
              'renew': 1,
              'capacity_limit': 100,
            },
            {
              'id': 2,
              'name': '一次性套餐 200G',
              'content': '<p>一次购买，长期有效</p>',
              'transfer_enable': 200,
              'speed_limit': null,
              'device_limit': 5,
              'onetime_price': 1000,
              'sell': 1,
              'renew': 0,
              'capacity_limit': 100,
            },
          ],
        },
      );
    },
  );
}

XboardAuthService _testPaymentService({int orderStatus = 0}) {
  return XboardAuthService(
    plansRequester: _testPlanServiceRequester,
    paymentMethodsRequester: (endpoint, authData) async {
      return const XboardLoginResponse(
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
      );
    },
    orderSaveRequester: (endpoint, authData, planId, period) async {
      return const XboardLoginResponse(
        statusCode: 200,
        data: {'data': 'TEST-ORDER-001'},
      );
    },
    orderCheckoutRequester: (endpoint, authData, tradeNo, methodId) async {
      return const XboardLoginResponse(
        statusCode: 200,
        data: {'type': 0, 'data': 'https://pay.example.com/qr/TEST-ORDER-001'},
      );
    },
    orderCheckRequester: (endpoint, authData, tradeNo) async {
      return XboardLoginResponse(statusCode: 200, data: {'data': orderStatus});
    },
  );
}

Future<XboardLoginResponse> _testPlanServiceRequester(
  Uri endpoint,
  String authData,
) async {
  return const XboardLoginResponse(
    statusCode: 200,
    data: {
      'data': [
        {
          'id': 1,
          'name': '白银套餐',
          'content': '<p><strong>高速专线</strong></p>',
          'transfer_enable': 1000,
          'speed_limit': null,
          'device_limit': null,
          'month_price': 10000,
          'sell': 1,
          'renew': 1,
          'capacity_limit': 100,
        },
      ],
    },
  );
}

XboardLoginResult _testSession({required int planId}) {
  final endpoint = Uri.parse('https://api.example.com');
  return XboardLoginResult(
    endpoint: endpoint,
    token: 'subscription-token',
    authData: 'Bearer plan-token',
    isAdmin: false,
    subscription: XboardSubscriptionData(
      endpoint: endpoint,
      subscribeUrl: Uri.parse('https://api.example.com/subscribe'),
      uploadBytes: 0,
      downloadBytes: 0,
      transferEnableBytes: bytesPerGigabyte * 1000,
      planId: planId,
      rawData: const {},
    ),
  );
}

class _TestApp extends StatelessWidget {
  final Widget child;
  final ThemeMode themeMode;

  const _TestApp({required this.child, this.themeMode = ThemeMode.light});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF2468E8)),
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF78A7FF),
          brightness: Brightness.dark,
        ),
      ),
      themeMode: themeMode,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.delegate.supportedLocales,
      home: child,
    );
  }
}

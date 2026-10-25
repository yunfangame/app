import 'dart:async';

import 'package:fl_clash/common/api_request_router.dart';
import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/common/xboard_catalog_cache.dart';
import 'package:fl_clash/l10n/l10n.dart';
import 'package:fl_clash/state.dart';
import 'package:fl_clash/views/plans/fengwo_purchase_plans.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/account_view_test_scope.dart';
import '../support/api_health_fixture.dart';

void main() {
  accountViewReadTest(
    'pending initial window validation and hide send no methods request until verified active',
    (tester) async {
      final rig = _MethodRig();
      await rig.mount(tester);
      final visible = Completer<bool>();
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('window_manager'),
        (call) async => switch (call.method) {
          'isVisible' => visible.future,
          'isMinimized' => false,
          'isFocused' => true,
          _ => null,
        },
      );
      await tester.tap(find.byKey(const ValueKey('open-payment')));
      await flushAccountReads(tester);
      expect(rig.methodReads, 0);
      await accountViewWindowEvent(tester, 'hide');
      visible.complete(false);
      await flushAccountReads(tester);
      expect(rig.methodReads, 0);
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('window_manager'),
        (call) async => switch (call.method) {
          'isVisible' || 'isFocused' => true,
          'isMinimized' => false,
          _ => null,
        },
      );
      await accountViewWindowEvent(tester, 'show');
      await accountViewWindowEvent(tester, 'focus');
      await tester.pumpAndSettle();
      expect(rig.methodReads, 1);
      expect(find.byKey(const ValueKey('payment-ready')), findsOneWidget);
    },
    platform: TargetPlatform.windows,
  );

  accountViewReadTest(
    'permanent window query errors retain an explicit retry that can still pay',
    (tester) async {
      final rig = _MethodRig();
      await rig.mount(tester);
      accountViewWindowQueryFails = true;
      await rig.open(tester);
      expect(rig.methodReads, 0);
      expect(find.byKey(const ValueKey('payment-failure')), findsOneWidget);
      for (final seconds in [1, 3, 6, 12]) {
        await tester.pump(Duration(seconds: seconds));
        await flushAccountReads(tester);
      }
      final calls = accountViewWindowCalls;
      await tester.pump(const Duration(minutes: 1));
      expect(accountViewWindowCalls, calls);
      final l10n = tester.element(find.byType(Dialog)).appLocalizations;
      await tester.tap(find.text(l10n.retry));
      await tester.pumpAndSettle();
      expect(rig.methodReads, 1);
      await rig.submit(tester);
      expect(rig.methodReads, 2);
      expect(rig.orderSaves, 1);
      expect(rig.checkoutMethods, [8]);
      expect(find.byKey(const ValueKey('payment-qr')), findsOneWidget);
    },
    platform: TargetPlatform.windows,
  );

  accountViewReadTest(
    'payment dialog reuses display methods but submission validates fresh methods once',
    (tester) async {
      final rig = _MethodRig();
      await rig.mount(tester);
      await rig.open(tester);
      expect(rig.methodReads, 1);
      await tester.tap(find.byIcon(Icons.close_rounded));
      await tester.pumpAndSettle();
      await rig.open(tester);
      expect(rig.methodReads, 1);
      await rig.submit(tester);
      expect(rig.methodReads, 2);
      expect(rig.planReads, 1);
      expect(rig.orderSaves, 1);
      expect(rig.checkoutMethods, [8]);
    },
  );

  for (final change in ['fee', 'channel', 'removed']) {
    accountViewReadTest(
      '$change changes require confirmation before using fresh payment methods',
      (tester) async {
        final rig = _MethodRig();
        await rig.mount(tester);
        await rig.open(tester);
        if (change == 'fee') rig.fee = 300;
        if (change == 'channel') rig.channel = 'NewChannel';
        if (change == 'removed') rig.methodId = 9;
        await rig.submit(tester);
        expect(rig.orderSaves, 0);
        expect(find.byKey(const ValueKey('payment-ready')), findsOneWidget);
        final l10n = tester.element(find.byType(Dialog)).appLocalizations;
        expect(
          find.descendant(
            of: find.byKey(const ValueKey('create-payment-qr')),
            matching: find.text(l10n.confirm),
          ),
          findsOneWidget,
        );
        if (change == 'fee') expect(find.textContaining('¥3'), findsOneWidget);
        await rig.submit(tester);
        expect(rig.methodReads, 3);
        expect(rig.orderSaves, 1);
        expect(rig.checkoutMethods, [change == 'removed' ? 9 : 8]);
      },
    );
  }

  accountViewReadTest(
    'unavailable payment methods prevent order creation and retry bypasses the display cache',
    (tester) async {
      final rig = _MethodRig();
      await rig.mount(tester);
      await rig.open(tester);
      rig.empty = true;
      await rig.submit(tester);
      expect(find.byKey(const ValueKey('payment-failure')), findsOneWidget);
      expect(rig.orderSaves, 0);
      rig.empty = false;
      rig.methodId = 9;
      final l10n = tester.element(find.byType(Dialog)).appLocalizations;
      await tester.tap(find.text(l10n.retry));
      await tester.pumpAndSettle();
      expect(rig.methodReads, 3);
      expect(find.byKey(const ValueKey('payment-method-9')), findsOneWidget);
      await rig.submit(tester);
      expect(rig.checkoutMethods, [9]);
    },
  );

  accountViewReadTest(
    'an existing order can recover when methods disappear then return',
    (tester) async {
      final rig = _MethodRig()..checkoutFails = true;
      await rig.mount(tester);
      await rig.open(tester);
      await rig.submit(tester);
      expect(rig.orderSaves, 1);
      expect(find.byKey(const ValueKey('payment-failure')), findsOneWidget);
      final l10n = tester.element(find.byType(Dialog)).appLocalizations;
      rig.empty = true;
      await tester.tap(find.text(l10n.retry));
      await flushAccountReads(tester);
      await tester.pump(const Duration(milliseconds: 250));
      expect(find.byKey(const ValueKey('payment-failure')), findsOneWidget);
      rig.empty = false;
      rig.checkoutFails = false;
      await tester.tap(find.text(l10n.retry));
      await flushAccountReads(tester);
      await tester.pump(const Duration(milliseconds: 250));
      expect(find.byKey(const ValueKey('payment-ready')), findsOneWidget);
      await rig.submit(tester);
      expect(rig.orderSaves, 1);
      expect(rig.checkoutMethods, [8, 8]);
      expect(find.byKey(const ValueKey('payment-qr')), findsOneWidget);
    },
  );

  accountViewReadTest(
    'concurrent display reads single-flight and an explicit refresh supersedes their old result',
    (tester) async {
      final rig = _MethodRig();
      await rig.mount(tester);
      final pending = Completer<XboardLoginResponse>();
      rig.pending = pending;
      final old = loadXboardPaymentMethodCatalog(
        authService: rig.service,
        session: rig.session,
      );
      final joined = loadXboardPaymentMethodCatalog(
        authService: rig.service,
        session: rig.session,
      );
      expect(old, same(joined));
      await flushAccountReads(tester);
      expect(rig.methodReads, 1);
      rig.pending = null;
      rig.methodId = 9;
      final fresh = await loadXboardPaymentMethodCatalog(
        authService: rig.service,
        session: rig.session,
        forceRefresh: true,
      );
      pending.complete(_methods(8, 0, 'AlipayF2F'));
      expect((await old).single.id, 9);
      expect(fresh.single.id, 9);
      expect(rig.methodReads, 2);
    },
  );

  accountViewReadTest(
    'a late pre-checkout catalog response cannot create an order after account replacement',
    (tester) async {
      final rig = _MethodRig();
      await rig.mount(tester);
      await rig.open(tester);
      final pending = Completer<XboardLoginResponse>();
      rig.pending = pending;
      await tester.tap(find.byKey(const ValueKey('create-payment-qr')));
      await flushAccountReads(tester);
      globalState.clearXboardSession();
      globalState.activateXboardSession(rig.session);
      pending.complete(_methods(8, 0, 'AlipayF2F'));
      await tester.pumpAndSettle();
      expect(rig.orderSaves, 0);
      expect(find.byType(Dialog), findsNothing);
    },
  );

  accountViewReadTest(
    'closing during method validation prevents a late order',
    (tester) async {
      final rig = _MethodRig();
      await rig.mount(tester);
      await rig.open(tester);
      final pending = Completer<XboardLoginResponse>();
      rig.pending = pending;
      await tester.tap(find.byKey(const ValueKey('create-payment-qr')));
      await flushAccountReads(tester);
      await tester.tap(find.byIcon(Icons.close_rounded));
      await tester.pumpAndSettle();
      pending.complete(_methods(8, 0, 'AlipayF2F'));
      await flushAccountReads(tester);
      expect(rig.orderSaves, 0);
    },
  );

  accountViewReadTest(
    'paid completion invalidates methods for the next dialog',
    (tester) async {
      final rig = _MethodRig()..freeCheckout = true;
      await rig.mount(tester);
      await rig.open(tester);
      await rig.submit(tester);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('payment-success')), findsOneWidget);
      expect(rig.methodReads, 2);
      await tester.tap(find.byIcon(Icons.close_rounded));
      await tester.pumpAndSettle();
      rig.methodId = 9;
      await rig.open(tester);
      expect(rig.methodReads, 3);
      expect(find.byKey(const ValueKey('payment-method-9')), findsOneWidget);
    },
  );

  accountViewReadTest(
    'initial payment method read waits until the app resumes',
    (tester) async {
      final rig = _MethodRig();
      await rig.mount(tester);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.tap(find.byKey(const ValueKey('open-payment')));
      await flushAccountReads(tester);
      expect(rig.methodReads, 0);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(rig.methodReads, 1);
    },
  );

  accountViewReadTest(
    'paused method failure does not fail over or poison the resumed read',
    (tester) async {
      final rig = _MethodRig(
        candidates: [
          Uri.parse('https://api.example.com'),
          Uri.parse('https://backup.example.com'),
        ],
      );
      await rig.mount(tester);
      final pending = Completer<XboardLoginResponse>();
      rig.pending = pending;
      await tester.tap(find.byKey(const ValueKey('open-payment')));
      await flushAccountReads(tester);
      expect(rig.methodReads, 1);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await flushAccountReads(tester);
      rig.pending = null;
      pending.completeError(TimeoutException('controlled outage'));
      await tester.pumpAndSettle();
      expect(rig.methodReads, 2);
      expect(rig.methodHosts, ['api.example.com', 'api.example.com']);
      expect(find.byKey(const ValueKey('payment-ready')), findsOneWidget);
      expect(find.byKey(const ValueKey('payment-failure')), findsNothing);
    },
  );

  accountViewReadTest(
    'paused payment checks resume once without increasing failure backoff',
    (tester) async {
      final rig = _MethodRig(
        candidates: [
          Uri.parse('https://api.example.com'),
          Uri.parse('https://backup.example.com'),
        ],
      );
      await rig.mount(tester);
      await rig.open(tester);
      await rig.submit(tester);
      final pending = Completer<XboardLoginResponse>();
      rig.pendingStatus = pending;
      await tester.pump(const Duration(seconds: 3));
      await flushAccountReads(tester);
      expect(rig.statusHosts, ['api.example.com']);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await flushAccountReads(tester);
      rig.pendingStatus = null;
      pending.completeError(TimeoutException('controlled outage'));
      await flushAccountReads(tester);
      await flushAccountReads(tester);
      expect(rig.statusHosts, ['api.example.com', 'api.example.com']);
      await tester.pump(const Duration(seconds: 3));
      await flushAccountReads(tester);
      expect(rig.statusHosts, hasLength(3));
      expect(find.byKey(const ValueKey('payment-failure')), findsNothing);
    },
  );
}

class _MethodRig {
  _MethodRig({this.candidates});

  final List<Uri>? candidates;
  final session = _session();
  int methodReads = 0;
  int planReads = 0;
  int orderSaves = 0;
  final checkoutMethods = <int>[];
  int methodId = 8;
  int fee = 0;
  String channel = 'AlipayF2F';
  bool empty = false;
  bool freeCheckout = false;
  bool checkoutFails = false;
  Completer<XboardLoginResponse>? pending;
  Completer<XboardLoginResponse>? pendingStatus;
  final methodHosts = <String>[];
  final statusHosts = <String>[];

  late final service = XboardAuthService(
    requestRouter: ApiRequestRouter(),
    apiHealthService: ApiHealthFixture(Uri.parse('https://api.example.com')),
    endpointLoader: candidates == null ? null : () async => candidates!,
    plansRequester: (_, _) async {
      planReads++;
      return const XboardLoginResponse(
        statusCode: 200,
        data: {
          'data': [
            {
              'id': 1,
              'name': 'Plan',
              'month_price': 1000,
              'sell': 1,
              'renew': 1,
            },
          ],
        },
      );
    },
    paymentMethodsRequester: (endpoint, _) async {
      methodReads++;
      methodHosts.add(endpoint.host);
      return pending?.future ??
          (empty
              ? const XboardLoginResponse(statusCode: 200, data: {'data': []})
              : _methods(methodId, fee, channel));
    },
    orderSaveRequester: (_, _, _, _) async {
      orderSaves++;
      return const XboardLoginResponse(
        statusCode: 200,
        data: {'data': 'METHOD-ORDER'},
      );
    },
    orderCheckoutRequester: (_, _, _, method) async {
      checkoutMethods.add(method);
      if (checkoutFails) throw StateError('checkout unavailable');
      return XboardLoginResponse(
        statusCode: 200,
        data: {
          'type': freeCheckout ? -1 : 0,
          'data': 'https://pay.example.com/qr',
        },
      );
    },
    orderCheckRequester: (endpoint, _, _) async {
      statusHosts.add(endpoint.host);
      return pendingStatus?.future ??
          const XboardLoginResponse(statusCode: 200, data: {'data': 0});
    },
  );

  Future<void> mount(WidgetTester tester) async {
    globalState.activateXboardSession(session);
    globalState.refreshXboardSubscription = () async => true;
    addTearDown(() => globalState.refreshXboardSubscription = null);
    await mountAccountView(
      tester,
      Builder(
        builder: (context) => TextButton(
          key: const ValueKey('open-payment'),
          onPressed: () => showXboardPaymentDialog(
            context: context,
            authService: service,
            session: session,
            plan: _plan,
            period: 'month_price',
          ),
          child: const Text('Open'),
        ),
      ),
      _app,
    );
  }

  Future<void> open(WidgetTester tester) async {
    await tester.tap(find.byKey(const ValueKey('open-payment')));
    await tester.pumpAndSettle();
  }

  Future<void> submit(WidgetTester tester) async {
    await tester.tap(find.byKey(const ValueKey('create-payment-qr')));
    await flushAccountReads(tester);
    await tester.pump(const Duration(milliseconds: 250));
  }
}

const _plan = XboardAvailablePlan(
  id: 1,
  name: 'Plan',
  tags: [],
  content: '',
  transferEnableGb: 100,
  speedLimit: null,
  deviceLimit: null,
  prices: {'month_price': 1000},
  sell: true,
  renew: true,
  isSoldOut: false,
  rawData: {},
);

XboardLoginResponse _methods(int id, int fee, String channel) =>
    XboardLoginResponse(
      statusCode: 200,
      data: {
        'data': [
          {
            'id': id,
            'name': 'Method $id',
            'payment': channel,
            'handling_fee_fixed': fee,
            'handling_fee_percent': 0,
          },
        ],
      },
    );

XboardLoginResult _session() {
  final endpoint = Uri.parse('https://api.example.com');
  return XboardLoginResult(
    endpoint: endpoint,
    token: 'subscription-token',
    authData: 'method-account',
    isAdmin: false,
    subscription: XboardSubscriptionData(
      endpoint: endpoint,
      subscribeUrl: endpoint.resolve('/subscribe'),
      uploadBytes: 0,
      downloadBytes: 0,
      transferEnableBytes: 0,
      rawData: const {},
    ),
  );
}

Widget _app(Widget child) => MaterialApp(
  localizationsDelegates: const [
    AppLocalizations.delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
  ],
  supportedLocales: AppLocalizations.delegate.supportedLocales,
  home: Scaffold(body: child),
);

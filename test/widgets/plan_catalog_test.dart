import 'dart:async';

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/common/xboard_catalog_cache.dart';
import 'package:fl_clash/l10n/l10n.dart';
import 'package:fl_clash/state.dart';
import 'package:fl_clash/views/plans/fengwo_purchase_plans.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/account_view_test_scope.dart';
import '../support/api_health_fixture.dart';

void main() {
  for (final platform in [TargetPlatform.android, TargetPlatform.windows]) {
    accountViewReadTest(
      'plan catalog gates hidden, lifecycle and offline reads on $platform',
      (tester) async {
        final rig = _CatalogRig();
        globalState.activateXboardSession(_session());
        final activity = await mountAccountView(
          tester,
          FengWoPurchasePlansView(authService: rig.service),
          _app,
          active: false,
        );
        expect(rig.planReads, 0);
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.inactive,
        );
        activity.value = true;
        await flushAccountReads(tester);
        expect(rig.planReads, 0);
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        globalState.setOfflineMode(true);
        await flushAccountReads(tester);
        expect(rig.planReads, 0);
        globalState.setOfflineMode(false);
        await tester.pumpAndSettle();
        expect(rig.planReads, 1);
        activity.value = false;
        await flushAccountReads(tester);
        activity.value = true;
        await tester.pumpAndSettle();
        expect(rig.planReads, 1);
        if (platform == TargetPlatform.android) {
          expect(accountViewWindowCalls, 0);
        }
      },
      platform: platform,
    );
  }

  accountViewReadTest(
    'desktop hidden window defers the initial catalog read',
    (tester) async {
      accountViewWindowVisible = false;
      final rig = _CatalogRig();
      globalState.activateXboardSession(_session());
      await mountAccountView(
        tester,
        FengWoPurchasePlansView(authService: rig.service),
        _app,
      );
      expect(rig.planReads, 0);
      accountViewWindowVisible = true;
      await accountViewWindowEvent(tester, 'show');
      await tester.pumpAndSettle();
      expect(rig.planReads, 1);
    },
    platform: TargetPlatform.windows,
  );

  accountViewReadTest(
    'manual catalog refresh remains usable when the window query fails',
    (tester) async {
      accountViewWindowQueryFails = true;
      final rig = _CatalogRig();
      globalState.activateXboardSession(_session());
      await mountAccountView(
        tester,
        FengWoPurchasePlansView(authService: rig.service),
        _app,
      );
      expect(rig.planReads, 0);
      await tester.tap(find.byIcon(Icons.refresh_rounded));
      await tester.pumpAndSettle();
      expect(rig.planReads, 1);
      expect(find.text('Catalog plan'), findsOneWidget);
    },
    platform: TargetPlatform.windows,
  );

  accountViewReadTest(
    'plan display and subscription lookup share a catalog but manual refresh is fresh',
    (tester) async {
      final rig = _CatalogRig();
      final session = _session();
      globalState.activateXboardSession(session);
      await mountAccountView(
        tester,
        FengWoPurchasePlansView(authService: rig.service),
        _app,
      );
      await tester.pumpAndSettle();
      expect(rig.planReads, 1);
      final plan = await findXboardCatalogPlan(
        authService: rig.service,
        session: session,
        planId: 1,
      );
      expect(plan?.id, 1);
      expect(rig.planReads, 1);
      rig.price = 2000;
      await tester.tap(find.byIcon(Icons.refresh_rounded));
      await tester.pumpAndSettle();
      expect(rig.planReads, 2);
      expect(find.text('20'), findsWidgets);
    },
  );

  accountViewReadTest(
    'late automatic catalog cannot cover a newer manual refresh',
    (tester) async {
      final rig = _CatalogRig();
      final pending = Completer<XboardLoginResponse>();
      rig.pending = pending;
      globalState.activateXboardSession(_session());
      await mountAccountView(
        tester,
        FengWoPurchasePlansView(authService: rig.service),
        _app,
      );
      expect(rig.planReads, 1);
      rig.pending = null;
      rig.price = 2000;
      await tester.tap(find.byIcon(Icons.refresh_rounded));
      await tester.pumpAndSettle();
      expect(rig.planReads, 2);
      pending.complete(_plans(1000));
      await tester.pumpAndSettle();
      expect(find.text('20'), findsWidgets);
      expect(find.text('10'), findsNothing);
    },
  );

  accountViewReadTest('account changes discard a late catalog result', (
    tester,
  ) async {
    final rig = _CatalogRig();
    final pending = Completer<XboardLoginResponse>();
    rig.pending = pending;
    globalState.activateXboardSession(_session());
    await mountAccountView(
      tester,
      FengWoPurchasePlansView(authService: rig.service),
      _app,
    );
    rig.pending = null;
    rig.price = 2000;
    globalState.activateXboardSession(_session(auth: 'other-account'));
    await tester.pumpAndSettle();
    pending.complete(_plans(1000));
    await tester.pumpAndSettle();
    expect(find.text('20'), findsWidgets);
    expect(find.text('10'), findsNothing);
  });

  accountViewReadTest(
    'changed server price requires another confirmation before saving an order',
    (tester) async {
      final rig = _CatalogRig();
      globalState.activateXboardSession(_session());
      await mountAccountView(
        tester,
        FengWoPurchasePlansView(authService: rig.service),
        _app,
      );
      await tester.pumpAndSettle();
      final l10n = tester
          .element(find.byType(FengWoPurchasePlansView))
          .appLocalizations;
      await tester.tap(find.text(l10n.buyNow).first);
      await tester.pumpAndSettle();
      rig.price = 2000;
      await tester.tap(find.byKey(const ValueKey('create-payment-qr')));
      await tester.pumpAndSettle();
      expect(rig.orderSaves, 0);
      expect(find.byKey(const ValueKey('payment-ready')), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('create-payment-qr')),
          matching: find.text(l10n.confirm),
        ),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('create-payment-qr')));
      await flushAccountReads(tester);
      await tester.pump(const Duration(milliseconds: 250));
      expect(rig.orderSaves, 1);
      expect(rig.planReads, 3);
    },
  );
}

class _CatalogRig {
  int planReads = 0;
  int orderSaves = 0;
  int price = 1000;
  Completer<XboardLoginResponse>? pending;

  late final service = XboardAuthService(
    apiHealthService: ApiHealthFixture(Uri.parse('https://api.example.com')),
    plansRequester: (_, _) async {
      planReads++;
      return pending?.future ?? _plans(price);
    },
    paymentMethodsRequester: (_, _) async => const XboardLoginResponse(
      statusCode: 200,
      data: {
        'data': [
          {'id': 8, 'name': 'Alipay', 'payment': 'AlipayF2F'},
        ],
      },
    ),
    orderCheckRequester: (_, _, _) async =>
        const XboardLoginResponse(statusCode: 200, data: {'data': 0}),
    orderSaveRequester: (_, _, _, _) async {
      orderSaves++;
      return const XboardLoginResponse(
        statusCode: 200,
        data: {'data': 'CATALOG-ORDER'},
      );
    },
    orderCheckoutRequester: (_, _, _, _) async => const XboardLoginResponse(
      statusCode: 200,
      data: {'type': 0, 'data': 'https://pay.example.com/qr'},
    ),
  );
}

XboardLoginResponse _plans(int price) => XboardLoginResponse(
  statusCode: 200,
  data: {
    'data': [
      {
        'id': 1,
        'name': 'Catalog plan',
        'month_price': price,
        'sell': 1,
        'renew': 1,
      },
    ],
  },
);

XboardLoginResult _session({String auth = 'catalog-account'}) {
  final endpoint = Uri.parse('https://api.example.com');
  return XboardLoginResult(
    endpoint: endpoint,
    token: 'subscription-token',
    authData: auth,
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
  home: child,
);

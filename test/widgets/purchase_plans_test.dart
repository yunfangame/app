import 'dart:async';

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/common/xboard_order_changes.dart';
import 'package:fl_clash/l10n/l10n.dart';
import 'package:fl_clash/state.dart';
import 'package:fl_clash/views/plans/fengwo_purchase_plans.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/api_health_fixture.dart';

bool _windowVisible = true;
bool _windowMinimized = false;
bool _windowFocused = true;
bool _windowQueryFails = false;
bool _rejectDesktopCalls = false;
int _desktopCalls = 0;

void _paymentTestWidgets(String description, WidgetTesterCallback callback) {
  testWidgets(description, (tester) async {
    final previous = debugDefaultTargetPlatformOverride;
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    try {
      await callback(tester);
    } finally {
      await tester.pumpWidget(const SizedBox());
      debugDefaultTargetPlatformOverride = previous;
    }
  });
}

void main() {
  setUp(() {
    final binding = TestWidgetsFlutterBinding.ensureInitialized();
    binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    _windowVisible = true;
    _windowMinimized = false;
    _windowFocused = true;
    _windowQueryFails = false;
    _rejectDesktopCalls = false;
    _desktopCalls = 0;
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('window_manager'),
      (call) async {
        _desktopCalls++;
        if (_rejectDesktopCalls) {
          throw PlatformException(
            code: 'android_must_not_query_desktop_window',
          );
        }
        if (_windowQueryFails) {
          throw PlatformException(code: 'fixture_window_unavailable');
        }
        return switch (call.method) {
          'isVisible' => _windowVisible,
          'isMinimized' => _windowMinimized,
          'isFocused' => _windowFocused,
          _ => null,
        };
      },
    );
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('window_ext'),
      (call) async {
        _desktopCalls++;
        if (_rejectDesktopCalls) {
          throw PlatformException(code: 'android_must_not_call_window_ext');
        }
        return null;
      },
    );
  });

  tearDown(() {
    globalState.setOfflineMode(false);
    globalState.refreshXboardSubscription = null;
    final binding = TestWidgetsFlutterBinding.ensureInitialized();
    binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('window_manager'),
      null,
    );
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('window_ext'),
      null,
    );
  });

  for (final free in [false, true]) {
    _paymentTestWidgets(
      'a successful payment invalidates orders once, free=$free',
      (tester) async {
        final changes = <XboardOrderChange>[];
        void changed() {
          final change = xboardOrderChanges.value;
          if (change != null) changes.add(change);
        }

        xboardOrderChanges.addListener(changed);
        addTearDown(() => xboardOrderChanges.removeListener(changed));
        final rig = _PaymentRig(check: (_) async => 1, freeCheckout: free);
        await rig.open(tester);
        if (!free) await tester.pump(const Duration(seconds: 3));
        await _flushPaymentEvents(tester);
        expect(find.byKey(const ValueKey('payment-success')), findsOneWidget);
        expect(changes, hasLength(1));
        expect(changes.single.matches(globalState.xboardSession), isTrue);
        await tester.pump(const Duration(minutes: 10));
        expect(changes, hasLength(1));
      },
    );
  }

  for (final state in [
    AppLifecycleState.inactive,
    AppLifecycleState.paused,
    AppLifecycleState.hidden,
  ]) {
    _paymentTestWidgets('Android payment pauses in $state and resumes once', (
      tester,
    ) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      _rejectDesktopCalls = true;
      final rig = _PaymentRig();
      await rig.open(tester, mobile: true);
      tester.binding.handleAppLifecycleStateChanged(state);
      await tester.pump(const Duration(hours: 1));
      expect(rig.checks, 0);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await _flushPaymentEvents(tester);
      expect(rig.checks, 1);
      await tester.pump(const Duration(seconds: 3));
      expect(rig.checks, 2);
      expect(_desktopCalls, 0);
    });
  }

  _paymentTestWidgets(
    'Android external payment retains paid until returning to app',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      _rejectDesktopCalls = true;
      final pending = Completer<int>();
      final rig = _PaymentRig(check: (_) => pending.future);
      await rig.open(tester, mobile: true);
      await tester.pump(const Duration(seconds: 3));
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      pending.complete(1);
      await _flushPaymentEvents(tester);
      expect(find.byKey(const ValueKey('payment-success')), findsOneWidget);
      expect(rig.refreshes, 0);
      await tester.pump(const Duration(minutes: 10));
      expect(rig.checks, 1);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await _flushPaymentEvents(tester);
      expect(rig.refreshes, 1);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump(const Duration(minutes: 10));
      expect(rig.refreshes, 1);
      expect(rig.checks, 1);
      expect(_desktopCalls, 0);
    },
  );

  _paymentTestWidgets(
    'Android resume cannot overlap an in-flight order check',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      _rejectDesktopCalls = true;
      final pending = Completer<int>();
      final rig = _PaymentRig(check: (_) => pending.future);
      await rig.open(tester, mobile: true);
      await tester.pump(const Duration(seconds: 3));
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump(const Duration(seconds: 5));
      expect(rig.checks, 1);
      pending.complete(0);
      await _flushPaymentEvents(tester);
      await tester.pump(const Duration(seconds: 2));
      expect(rig.checks, 1);
      await tester.pump(const Duration(seconds: 1));
      expect(rig.checks, 2);
      expect(_desktopCalls, 0);
    },
  );

  _paymentTestWidgets(
    'Android payment backs off and unpaid resets the interval',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      _rejectDesktopCalls = true;
      final rig = _PaymentRig(
        check: (call) async {
          if (call <= 5) throw StateError('controlled_payment_outage');
          return 0;
        },
      );
      await rig.open(tester, mobile: true);
      for (final seconds in [3, 6, 12, 24, 30, 30]) {
        final previous = rig.checks;
        await tester.pump(Duration(seconds: seconds - 1));
        expect(rig.checks, previous);
        await tester.pump(const Duration(seconds: 1));
        expect(rig.checks, previous + 1);
      }
      await tester.pump(const Duration(seconds: 3));
      expect(rig.checks, 7);
      expect(_desktopCalls, 0);
    },
  );

  _paymentTestWidgets('Android offline mode pauses payment until online', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    _rejectDesktopCalls = true;
    final rig = _PaymentRig();
    await rig.open(tester, mobile: true);
    globalState.setOfflineMode(true);
    await tester.pump(const Duration(hours: 1));
    expect(rig.checks, 0);
    globalState.setOfflineMode(false);
    await _flushPaymentEvents(tester);
    expect(rig.checks, 1);
    expect(_desktopCalls, 0);
  });

  _paymentTestWidgets(
    'payment failures back off and an unpaid response resets cadence',
    (tester) async {
      final rig = _PaymentRig(
        check: (call) async {
          if (call <= 5) throw StateError('fixture_network_failure');
          return 0;
        },
      );
      await rig.open(tester);
      for (final seconds in [3, 6, 12, 24, 30, 30]) {
        final previous = rig.checks;
        await tester.pump(Duration(seconds: seconds - 1));
        expect(rig.checks, previous);
        await tester.pump(const Duration(seconds: 1));
        expect(rig.checks, previous + 1);
      }
      await tester.pump(const Duration(seconds: 2));
      expect(rig.checks, 6);
      await tester.pump(const Duration(seconds: 1));
      expect(rig.checks, 7);
      expect(find.byKey(const ValueKey('payment-qr')), findsOneWidget);
    },
  );

  _paymentTestWidgets(
    'payment schedules after completion and coalesces recovery events',
    (tester) async {
      final pending = Completer<int>();
      final rig = _PaymentRig(check: (_) => pending.future);
      await rig.open(tester);
      await tester.pump(const Duration(seconds: 3));
      expect(rig.checks, 1);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await _windowEvent(tester, 'focus');
      await _windowEvent(tester, 'restore');
      await _windowEvent(tester, 'show');
      await tester.pump(const Duration(seconds: 5));
      expect(rig.checks, 1);
      pending.complete(0);
      await _flushPaymentEvents(tester);
      await tester.pump(const Duration(seconds: 2));
      expect(rig.checks, 1);
      await tester.pump(const Duration(seconds: 1));
      expect(rig.checks, 2);
    },
  );

  for (final state in [AppLifecycleState.inactive, AppLifecycleState.paused]) {
    _paymentTestWidgets(
      'payment pauses in $state and resumes with one status check',
      (tester) async {
        final rig = _PaymentRig();
        await rig.open(tester);
        tester.binding.handleAppLifecycleStateChanged(state);
        await tester.pump(const Duration(hours: 1));
        expect(rig.checks, 0);
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await _flushPaymentEvents(tester);
        expect(rig.checks, 1);
        await tester.pump(const Duration(seconds: 3));
        expect(rig.checks, 2);
      },
    );
  }

  for (final event in ['hide', 'minimize', 'blur']) {
    _paymentTestWidgets(
      'payment pauses on window $event until a verified recovery',
      (tester) async {
        final rig = _PaymentRig();
        await rig.open(tester);
        if (event == 'hide') _windowVisible = false;
        if (event == 'minimize') _windowMinimized = true;
        if (event == 'blur') _windowFocused = false;
        await _windowEvent(tester, event);
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.inactive,
        );
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await tester.pump(const Duration(hours: 1));
        expect(rig.checks, 0);
        _windowVisible = true;
        _windowMinimized = false;
        _windowFocused = true;
        await _windowEvent(tester, 'show');
        await _windowEvent(tester, 'restore');
        await _windowEvent(tester, 'focus');
        await _flushPaymentEvents(tester);
        expect(rig.checks, 1);
      },
    );
  }

  _paymentTestWidgets(
    'offline payment pauses and checks once when online again',
    (tester) async {
      final rig = _PaymentRig();
      await rig.open(tester);
      globalState.setOfflineMode(true);
      await tester.pump(const Duration(hours: 1));
      expect(rig.checks, 0);
      globalState.setOfflineMode(false);
      await _flushPaymentEvents(tester);
      expect(rig.checks, 1);
    },
  );

  _paymentTestWidgets(
    'an in-flight paid result is retained while refresh waits for focus',
    (tester) async {
      final pending = Completer<int>();
      final rig = _PaymentRig(check: (_) => pending.future);
      await rig.open(tester);
      await tester.pump(const Duration(seconds: 3));
      _windowFocused = false;
      await _windowEvent(tester, 'blur');
      pending.complete(1);
      await _flushPaymentEvents(tester);
      expect(find.byKey(const ValueKey('payment-success')), findsOneWidget);
      expect(rig.refreshes, 0);
      await tester.pump(const Duration(minutes: 10));
      expect(rig.checks, 1);
      expect(rig.refreshes, 0);
      _windowFocused = true;
      await _windowEvent(tester, 'focus');
      await _windowEvent(tester, 'show');
      await _flushPaymentEvents(tester);
      expect(rig.refreshes, 1);
      await tester.pump(const Duration(minutes: 10));
      expect(rig.refreshes, 1);
      expect(rig.checks, 1);
    },
  );

  _paymentTestWidgets('closing a payment ignores its late paid result', (
    tester,
  ) async {
    final pending = Completer<int>();
    final rig = _PaymentRig(check: (_) => pending.future);
    await rig.open(tester);
    await tester.pump(const Duration(seconds: 3));
    await tester.tap(find.byIcon(Icons.close_rounded));
    await _flushPaymentEvents(tester);
    pending.complete(1);
    await tester.pumpAndSettle();
    await tester.pump(const Duration(hours: 1));
    expect(rig.checks, 1);
    expect(rig.refreshes, 0);
    expect(find.byKey(const ValueKey('payment-success')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  _paymentTestWidgets(
    'a late paid result cannot bypass unverified background state',
    (tester) async {
      final pending = Completer<int>();
      final rig = _PaymentRig(check: (_) => pending.future);
      await rig.open(tester);
      await tester.pump(const Duration(seconds: 3));
      _windowFocused = false;
      await _windowEvent(tester, 'blur');
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      _windowQueryFails = true;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await _flushPaymentEvents(tester);
      pending.complete(1);
      await _flushPaymentEvents(tester);
      expect(find.byKey(const ValueKey('payment-success')), findsOneWidget);
      expect(rig.refreshes, 0);
      await tester.pump(const Duration(seconds: 1));
      await _flushPaymentEvents(tester);
      expect(rig.refreshes, 0);
      expect(rig.checks, 1);
      _windowQueryFails = false;
      _windowFocused = true;
      await _windowEvent(tester, 'focus');
      await _flushPaymentEvents(tester);
      expect(rig.refreshes, 1);
      await _windowEvent(tester, 'show');
      await _flushPaymentEvents(tester);
      await tester.pump(const Duration(minutes: 10));
      expect(rig.refreshes, 1);
      expect(rig.checks, 1);
    },
  );

  _paymentTestWidgets(
    'a deferred subscription refresh retries unavailable window state',
    (tester) async {
      final pending = Completer<int>();
      final rig = _PaymentRig(check: (_) => pending.future);
      await rig.open(tester);
      await tester.pump(const Duration(seconds: 3));
      _windowFocused = false;
      await _windowEvent(tester, 'blur');
      pending.complete(1);
      await _flushPaymentEvents(tester);
      expect(rig.refreshes, 0);
      _windowFocused = true;
      _windowQueryFails = true;
      await _windowEvent(tester, 'focus');
      await _flushPaymentEvents(tester);
      expect(rig.refreshes, 0);
      _windowQueryFails = false;
      await tester.pump(const Duration(seconds: 1));
      await _flushPaymentEvents(tester);
      expect(rig.refreshes, 1);
      await tester.pump(const Duration(minutes: 10));
      expect(rig.refreshes, 1);
      expect(rig.checks, 1);
    },
  );

  _paymentTestWidgets(
    'logging out and back in cannot accept an old paid result',
    (tester) async {
      final pending = Completer<int>();
      final rig = _PaymentRig(check: (_) => pending.future);
      await rig.open(tester);
      await tester.pump(const Duration(seconds: 3));
      globalState.clearXboardSession();
      globalState.activateXboardSession(_testSession(planId: 1));
      await _flushPaymentEvents(tester);
      pending.complete(3);
      await tester.pumpAndSettle();
      await tester.pump(const Duration(minutes: 10));
      expect(rig.checks, 1);
      expect(rig.refreshes, 0);
      expect(find.byType(Dialog), findsNothing);
    },
  );

  _paymentTestWidgets(
    'closing a confirmed payment preserves its pending refresh',
    (tester) async {
      final pending = Completer<int>();
      final rig = _PaymentRig(check: (_) => pending.future);
      await rig.open(tester);
      await tester.pump(const Duration(seconds: 3));
      _windowFocused = false;
      await _windowEvent(tester, 'blur');
      pending.complete(1);
      await _flushPaymentEvents(tester);
      expect(rig.refreshes, 0);
      _windowFocused = true;
      _windowQueryFails = true;
      await _windowEvent(tester, 'focus');
      await _flushPaymentEvents(tester);
      expect(rig.refreshes, 0);
      await tester.tap(find.byIcon(Icons.close_rounded));
      await tester.pumpAndSettle();
      expect(rig.refreshes, 1);
      expect(find.byType(Dialog), findsNothing);
      await tester.pump(const Duration(minutes: 10));
      expect(rig.checks, 1);
      expect(rig.refreshes, 1);
    },
  );

  _paymentTestWidgets(
    'same-auth subscription updates preserve the waiting payment',
    (tester) async {
      final rig = _PaymentRig(check: (_) async => 1);
      await rig.open(tester);
      globalState.activateXboardSession(_testSession(planId: 2));
      await _flushPaymentEvents(tester);
      expect(find.byKey(const ValueKey('payment-qr')), findsOneWidget);
      await tester.pump(const Duration(seconds: 3));
      expect(find.byKey(const ValueKey('payment-success')), findsOneWidget);
      expect(rig.refreshes, 1);
    },
  );

  _paymentTestWidgets(
    'account changes while creating an order prevent its checkout',
    (tester) async {
      final pending = Completer<XboardLoginResponse>();
      var checkouts = 0;
      final rig = _PaymentRig(
        saveOrder: () => pending.future,
        checkoutOrder: () async {
          checkouts++;
          return const XboardLoginResponse(statusCode: 200, data: {'type': -1});
        },
      );
      await rig.open(tester);
      globalState.activateXboardSession(
        _testSession(planId: 2, authData: 'Bearer another-account'),
      );
      pending.complete(
        const XboardLoginResponse(statusCode: 200, data: {'data': 'OLD-ORDER'}),
      );
      await tester.pumpAndSettle();
      expect(checkouts, 0);
      expect(rig.refreshes, 0);
      expect(find.byType(Dialog), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  _paymentTestWidgets(
    'free orders finish once without starting status polling',
    (tester) async {
      final rig = _PaymentRig(freeCheckout: true);
      await rig.open(tester);
      expect(find.byKey(const ValueKey('payment-success')), findsOneWidget);
      expect(rig.refreshes, 1);
      await tester.pump(const Duration(minutes: 10));
      expect(rig.checks, 0);
      expect(rig.refreshes, 1);
    },
  );

  _paymentTestWidgets('cancelled orders stop status polling', (tester) async {
    final rig = _PaymentRig(check: (_) async => 2);
    await rig.open(tester);
    await tester.pump(const Duration(seconds: 3));
    expect(find.byKey(const ValueKey('payment-failure')), findsOneWidget);
    await tester.pump(const Duration(minutes: 10));
    expect(rig.checks, 1);
    expect(rig.refreshes, 0);
  });

  _paymentTestWidgets(
    'window-state failures retry and recover automatic checks',
    (tester) async {
      final rig = _PaymentRig();
      await rig.open(tester);
      _windowQueryFails = true;
      await _windowEvent(tester, 'focus');
      await _flushPaymentEvents(tester);
      expect(rig.checks, 0);
      _windowQueryFails = false;
      await tester.pump(const Duration(seconds: 1));
      await _flushPaymentEvents(tester);
      expect(rig.checks, 1);
    },
  );

  _paymentTestWidgets(
    'explicit payment and confirmation survive unavailable window RPCs',
    (tester) async {
      _windowQueryFails = true;
      final rig = _PaymentRig(check: (_) async => 1);
      await rig.open(tester);
      expect(find.byKey(const ValueKey('payment-qr')), findsOneWidget);
      final l10n = tester.element(find.byType(Dialog)).appLocalizations;
      await tester.tap(find.text(l10n.iHavePaid));
      await tester.pumpAndSettle();
      expect(rig.checks, 1);
      expect(find.byKey(const ValueKey('payment-success')), findsOneWidget);
      expect(rig.refreshes, 0);
      await tester.tap(find.byIcon(Icons.close_rounded));
      await tester.pumpAndSettle();
      expect(rig.refreshes, 1);
    },
  );

  for (final expired in [false, true]) {
    for (final mobile in [false, true]) {
      _paymentTestWidgets(
        'billing stays accessible for expired=$expired mobile=$mobile',
        (tester) async {
          tester.view.physicalSize = mobile
              ? const Size(390, 844)
              : const Size(1100, 850);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          addTearDown(globalState.clearXboardSession);
          globalState
            ..setOfflineMode(false)
            ..xboardSession = _testSession(
              planId: expired ? 1 : null,
              expiredAt: expired ? 1 : null,
            );
          try {
            await tester.pumpWidget(
              _TestApp(
                child: FengWoPurchasePlansView(
                  authService: _testPaymentService(),
                ),
              ),
            );
            await tester.pumpAndSettle();
            final l10n = tester
                .element(find.byType(FengWoPurchasePlansView))
                .appLocalizations;
            await tester.ensureVisible(find.text(l10n.buyNow).first);
            await tester.tap(find.text(l10n.buyNow).first);
            await tester.pumpAndSettle();
            expect(find.byKey(const ValueKey('payment-ready')), findsOneWidget);
            expect(find.text('支付宝'), findsOneWidget);
            expect(globalState.xboardSession?.authData, 'Bearer plan-token');
            expect(tester.takeException(), isNull);
          } finally {
            await tester.pumpWidget(const SizedBox.shrink());
          }
        },
      );
    }
  }

  _paymentTestWidgets(
    'plan store filters real XBoard plans and renders HTML content',
    (tester) async {
      tester.view.physicalSize = const Size(1440, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(globalState.clearXboardSession);
      globalState.xboardSession = _testSession(planId: 1);

      await tester.pumpWidget(
        _TestApp(
          child: FengWoPurchasePlansView(authService: _testPlanService()),
        ),
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
    },
  );

  _paymentTestWidgets('plan store remains stable on a narrow dark viewport', (
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

  _paymentTestWidgets(
    'purchase stays in app and renders the checkout QR code',
    (tester) async {
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
      await _flushPaymentEvents(tester);
      await tester.pump(const Duration(milliseconds: 250));

      expect(find.byKey(const ValueKey('payment-qr')), findsOne);
      expect(find.byKey(const ValueKey('payment-qr-code')), findsOne);
      expect(find.text(l10n.waitingForPayment), findsOne);
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  _paymentTestWidgets(
    'successful payment refreshes the active subscription once',
    (tester) async {
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
      await _flushPaymentEvents(tester);
      await tester.pump(const Duration(milliseconds: 250));
      await tester.tap(find.text(l10n.iHavePaid));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('payment-success')), findsOneWidget);
      expect(refreshes, 1);
      expect(tester.takeException(), isNull);
    },
  );
}

class _PaymentRig {
  final Future<int> Function(int call)? check;
  final bool freeCheckout;
  final Future<XboardLoginResponse> Function()? saveOrder;
  final Future<XboardLoginResponse> Function()? checkoutOrder;
  int checks = 0;
  int refreshes = 0;

  _PaymentRig({
    this.check,
    this.freeCheckout = false,
    this.saveOrder,
    this.checkoutOrder,
  });

  Future<void> open(WidgetTester tester, {bool mobile = false}) async {
    tester.view.physicalSize = mobile
        ? const Size(390, 844)
        : const Size(1100, 850);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox());
      globalState.clearXboardSession();
    });
    globalState.activateXboardSession(_testSession(planId: 1));
    globalState.refreshXboardSubscription = () async {
      refreshes++;
      return true;
    };
    await tester.pumpWidget(
      _TestApp(
        child: FengWoPurchasePlansView(
          authService: _testPaymentService(
            checkOrder: () async {
              checks++;
              return await check?.call(checks) ?? 0;
            },
            freeCheckout: freeCheckout,
            saveOrder: saveOrder,
            checkoutOrder: checkoutOrder,
          ),
        ),
      ),
    );
    if (_windowQueryFails) {
      await _flushPaymentEvents(tester);
      await tester.tap(find.byIcon(Icons.refresh_rounded));
    }
    await tester.pumpAndSettle();
    final l10n = tester
        .element(find.byType(FengWoPurchasePlansView))
        .appLocalizations;
    await tester.ensureVisible(find.text(l10n.buyNow).first);
    await tester.tap(find.text(l10n.buyNow).first);
    await tester.pumpAndSettle();
    if (_windowQueryFails) {
      await tester.tap(find.text(l10n.retry));
      await tester.pumpAndSettle();
    }
    await tester.tap(find.byKey(const ValueKey('create-payment-qr')));
    await _flushPaymentEvents(tester);
    await tester.pump(const Duration(milliseconds: 250));
  }
}

Future<void> _flushPaymentEvents(WidgetTester tester) async {
  await tester.pump(Duration.zero);
  await tester.pump(Duration.zero);
}

Future<void> _windowEvent(WidgetTester tester, String event) async {
  await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
    'window_manager',
    const StandardMethodCodec().encodeMethodCall(
      MethodCall('onEvent', {'eventName': event}),
    ),
    (_) {},
  );
}

XboardAuthService _testPlanService() {
  return XboardAuthService(
    apiHealthService: ApiHealthFixture(Uri.parse('https://api.example.com')),
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

XboardAuthService _testPaymentService({
  int orderStatus = 0,
  Future<int> Function()? checkOrder,
  bool freeCheckout = false,
  Future<XboardLoginResponse> Function()? saveOrder,
  Future<XboardLoginResponse> Function()? checkoutOrder,
}) {
  return XboardAuthService(
    apiHealthService: ApiHealthFixture(Uri.parse('https://api.example.com')),
    plansRequester: (endpoint, authData) => _testPlanServiceRequester(
      endpoint,
      authData,
      price: freeCheckout ? 0 : 10000,
    ),
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
      if (saveOrder != null) return saveOrder();
      return const XboardLoginResponse(
        statusCode: 200,
        data: {'data': 'TEST-ORDER-001'},
      );
    },
    orderCheckoutRequester: (endpoint, authData, tradeNo, methodId) async {
      if (checkoutOrder != null) return checkoutOrder();
      return XboardLoginResponse(
        statusCode: 200,
        data: {
          'type': freeCheckout ? -1 : 0,
          'data': 'https://pay.example.com/qr/TEST-ORDER-001',
        },
      );
    },
    orderCheckRequester: (endpoint, authData, tradeNo) async {
      return XboardLoginResponse(
        statusCode: 200,
        data: {'data': await checkOrder?.call() ?? orderStatus},
      );
    },
  );
}

Future<XboardLoginResponse> _testPlanServiceRequester(
  Uri endpoint,
  String authData, {
  int price = 10000,
}) async {
  return XboardLoginResponse(
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
          'month_price': price,
          'sell': 1,
          'renew': 1,
          'capacity_limit': 100,
        },
      ],
    },
  );
}

XboardLoginResult _testSession({
  required int? planId,
  int? expiredAt,
  String authData = 'Bearer plan-token',
}) {
  final endpoint = Uri.parse('https://api.example.com');
  return XboardLoginResult(
    endpoint: endpoint,
    token: 'subscription-token',
    authData: authData,
    isAdmin: false,
    subscription: XboardSubscriptionData(
      endpoint: endpoint,
      subscribeUrl: Uri.parse('https://api.example.com/subscribe'),
      uploadBytes: 0,
      downloadBytes: 0,
      transferEnableBytes: planId == null ? 0 : bytesPerGigabyte * 1000,
      planId: planId,
      expiredAtEpochSeconds: expiredAt,
      rawData: {
        'plan_id': planId,
        'expired_at': expiredAt,
        'transfer_enable': planId == null ? 0 : bytesPerGigabyte * 1000,
      },
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

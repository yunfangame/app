import 'dart:async';

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
        expiresAt: now.add(const Duration(days: 7)),
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
    expect(find.textContaining('剩余不足 7 天'), findsOneWidget);
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

    expect(find.text('Продлить'), findsNothing);
    expect(find.text('Сбросить трафик'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('subscription-change-plan-button')),
      findsOneWidget,
    );
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
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('subscription-reset-traffic-button')),
      findsOneWidget,
    );
    await tester.tap(
      find.byKey(const ValueKey('subscription-reset-traffic-button')),
    );
    await _pumpDialogTransition(tester);

    expect(periods, isEmpty);
    expect(
      find.byKey(const ValueKey('subscription-reset-notice-dialog')),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey('subscription-reset-continue')));
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
    expect(find.text('升级套餐'), findsOneWidget);
    await tester.tap(changePlanButton);
    await _pumpDialogTransition(tester);

    expect(changedPlan, isFalse);
    await tester.tap(
      find.byKey(const ValueKey('subscription-upgrade-confirm')),
    );
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
    final subscription = _subscription(
      remainingGigabytes: 9,
      expiresAt: now.add(const Duration(days: 6)),
    );
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

  testWidgets('unlimited subscription only keeps low-traffic reset', (
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
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('subscription-reset-traffic-button')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  test('actions use strict seven-day and ten-GB boundaries', () {
    final boundary = _subscription(
      remainingGigabytes: 10,
      expiresAt: now.add(const Duration(days: 7)),
    );
    expect(subscriptionPlanActions(boundary, now: now), isEmpty);
    expect(
      subscriptionPlanActions(
        boundary,
        now: now.add(const Duration(microseconds: 1)),
      ),
      [SubscriptionPlanAction.renew],
    );
    expect(
      subscriptionPlanActions(_subscription(remainingGigabytes: 9), now: now),
      [SubscriptionPlanAction.upgrade, SubscriptionPlanAction.reset],
    );
    expect(
      subscriptionPlanActions(
        _subscription(remainingGigabytes: 10, expiresAt: now),
        now: now,
      ),
      [SubscriptionPlanAction.renew],
    );
    expect(subscriptionPlanActions(null, now: now), isEmpty);
    expect(
      subscriptionPlanActions(
        _subscription(remainingGigabytes: 9, expiresAt: now),
        now: now,
      ),
      [SubscriptionPlanAction.renew],
    );
    expect(
      subscriptionPlanActions(
        _subscription(remainingGigabytes: 9, unlimited: true, hasPlan: false),
        now: now,
      ),
      isEmpty,
    );
    expect(
      subscriptionPlanActions(
        _subscription(
          remainingGigabytes: 10,
          remainingBytes: subscriptionLowTrafficThresholdBytes - 1,
          unlimited: true,
        ),
        now: now,
      ),
      [SubscriptionPlanAction.reset],
    );
  });

  for (final sample
      in <
        ({
          String name,
          XboardSubscriptionData? subscription,
          bool upgrade,
          bool empty,
        })
      >[
        (name: 'null', subscription: null, upgrade: false, empty: true),
        (
          name: 'unlimited low traffic',
          subscription: _subscription(remainingGigabytes: 9, unlimited: true),
          upgrade: false,
          empty: false,
        ),
        (
          name: 'expired low traffic',
          subscription: _subscription(remainingGigabytes: 9, expiresAt: now),
          upgrade: false,
          empty: false,
        ),
        (
          name: 'exactly ten GB',
          subscription: _subscription(remainingGigabytes: 10),
          upgrade: false,
          empty: true,
        ),
        (
          name: 'one byte above ten GB',
          subscription: _subscription(
            remainingGigabytes: 10,
            remainingBytes: subscriptionLowTrafficThresholdBytes + 1,
          ),
          upgrade: false,
          empty: true,
        ),
        (
          name: 'one byte below ten GB',
          subscription: _subscription(
            remainingGigabytes: 10,
            remainingBytes: subscriptionLowTrafficThresholdBytes - 1,
          ),
          upgrade: true,
          empty: false,
        ),
      ]) {
    testWidgets(
      'upgrade eligibility is shared across both entries: ${sample.name}',
      (tester) async {
        await tester.pumpWidget(
          _TestApp(
            child: SubscriptionPlanActionBar(
              subscription: sample.subscription,
              embedded: true,
              now: now,
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('traffic-upgrade-plan')),
          sample.upgrade ? findsOneWidget : findsNothing,
        );
        expect(
          find.byKey(const ValueKey('subscription-plan-actions')),
          sample.empty ? findsNothing : findsOneWidget,
        );
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(
          _TestApp(
            child: SubscriptionStatusIndicator(
              subscription: sample.subscription,
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
          find.byKey(const ValueKey('subscription-change-plan-button')),
          sample.upgrade ? findsOneWidget : findsNothing,
        );
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }

  testWidgets('unlimited low traffic opens reset payment without countdown', (
    tester,
  ) async {
    final subscription = _subscription(remainingGigabytes: 9, unlimited: true);
    final periods = <String>[];
    globalState
      ..setOfflineMode(false)
      ..xboardSession = _session(subscription);
    addTearDown(globalState.clearXboardSession);
    await tester.pumpWidget(
      _TestApp(
        child: SubscriptionPlanActionBar(
          subscription: subscription,
          authService: _paymentService(periods),
          now: now,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('traffic-reset-plan')));
    await _pumpDialogTransition(tester);
    expect(
      find.byKey(const ValueKey('subscription-reset-notice-dialog')),
      findsNothing,
    );
    expect(find.textContaining('下次流量重置'), findsNothing);
    expect(find.byKey(const ValueKey('payment-ready')), findsOneWidget);
    expect(periods, isEmpty);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'active low-traffic subscription upgrades only after confirmation',
    (tester) async {
      var navigations = 0;
      await tester.pumpWidget(
        _TestApp(
          child: SubscriptionPlanActionBar(
            subscription: _subscription(remainingGigabytes: 9),
            embedded: true,
            now: now,
            onUpgrade: () => navigations++,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('traffic-renew-plan')), findsNothing);
      expect(find.byKey(const ValueKey('traffic-reset-plan')), findsOneWidget);
      final upgrade = find.byKey(const ValueKey('traffic-upgrade-plan'));
      final callback = tester.widget<FilledButton>(upgrade).onPressed!;
      callback();
      callback();
      await _pumpDialogTransition(tester);
      expect(
        find.byKey(const ValueKey('subscription-upgrade-confirm-dialog')),
        findsOneWidget,
      );
      expect(navigations, 0);
      await tester.tap(
        find.byKey(const ValueKey('subscription-upgrade-cancel')),
      );
      await tester.pumpAndSettle();
      expect(navigations, 0);
      expect(tester.widget<FilledButton>(upgrade).onPressed, isNotNull);
      await tester.tap(upgrade);
      await _pumpDialogTransition(tester);
      await tester.tap(
        find.byKey(const ValueKey('subscription-upgrade-confirm')),
      );
      await tester.pumpAndSettle();
      expect(navigations, 1);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  for (final locale in [const Locale('zh', 'CN'), const Locale('ru')]) {
    testWidgets(
      'embedded actions wrap at narrow width and large text $locale',
      (tester) async {
        tester.view.physicalSize = const Size(320, 1000);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(
          _TestApp(
            locale: locale,
            textScale: 2,
            child: SizedBox(
              width: 250,
              child: SubscriptionPlanActionBar(
                subscription: _subscription(
                  remainingGigabytes: 9,
                  expiresAt: now.add(const Duration(days: 2)),
                ),
                now: now,
                embedded: true,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final container = tester.widget<Container>(
          find.byKey(const ValueKey('subscription-plan-actions')),
        );
        expect(container.decoration, isNull);
        expect(find.byType(FittedBox), findsNothing);
        expect(
          find.byKey(const ValueKey('traffic-renew-plan')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('traffic-reset-plan')),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }

  for (final testCase
      in <
        ({
          Duration? resetIn,
          bool unlimited,
          bool expired,
          String expected,
          bool forfeiture,
        })
      >[
        (
          resetIn: const Duration(days: 2, hours: 1),
          unlimited: false,
          expired: false,
          expected: '还有 3 天',
          forfeiture: true,
        ),
        (
          resetIn: const Duration(days: 1),
          unlimited: false,
          expired: false,
          expected: '还有 1 天',
          forfeiture: true,
        ),
        (
          resetIn: const Duration(hours: 23),
          unlimited: false,
          expired: false,
          expected: '不足 1 天',
          forfeiture: true,
        ),
        (
          resetIn: null,
          unlimited: false,
          expired: false,
          expected: '暂未获取有效',
          forfeiture: false,
        ),
        (
          resetIn: Duration.zero,
          unlimited: false,
          expired: false,
          expected: '暂未获取有效',
          forfeiture: false,
        ),
        (
          resetIn: const Duration(days: -1),
          unlimited: false,
          expired: false,
          expected: '暂未获取有效',
          forfeiture: false,
        ),
        (
          resetIn: const Duration(days: 20),
          unlimited: false,
          expired: false,
          expected: '暂未获取有效',
          forfeiture: false,
        ),
        (
          resetIn: const Duration(days: 21),
          unlimited: false,
          expired: false,
          expected: '暂未获取有效',
          forfeiture: false,
        ),
      ]) {
    testWidgets('reset notice is accurate for $testCase', (tester) async {
      final periods = <String>[];
      await tester.pumpWidget(
        _TestApp(
          child: SubscriptionPlanActionBar(
            subscription: _subscription(
              remainingGigabytes: 9,
              expiresAt: testCase.expired
                  ? now
                  : now.add(const Duration(days: 20)),
              unlimited: testCase.unlimited,
              nextResetAt: testCase.resetIn == null
                  ? null
                  : now.add(testCase.resetIn!),
            ),
            authService: _paymentService(periods),
            now: now,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('traffic-reset-plan')));
      await _pumpDialogTransition(tester);
      expect(find.textContaining(testCase.expected), findsOneWidget);
      expect(
        find.textContaining('不结转'),
        testCase.forfeiture ? findsOneWidget : findsNothing,
      );
      expect(periods, isEmpty);
      await tester.tap(find.byKey(const ValueKey('subscription-reset-cancel')));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<OutlinedButton>(
              find.byKey(const ValueKey('traffic-reset-plan')),
            )
            .onPressed,
        isNotNull,
      );
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  testWidgets('expired renewal selects a period without traffic promises', (
    tester,
  ) async {
    final periods = <String>[];
    final subscription = _subscription(remainingGigabytes: 20, expiresAt: now);
    globalState
      ..setOfflineMode(false)
      ..xboardSession = _session(subscription);
    addTearDown(globalState.clearXboardSession);
    await tester.pumpWidget(
      _TestApp(
        child: SubscriptionPlanActionBar(
          subscription: subscription,
          authService: _paymentService(periods),
          now: now,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('traffic-renew-plan')));
    await _pumpDialogTransition(tester);
    expect(
      find.byKey(const ValueKey('subscription-renewal-period-dialog')),
      findsOneWidget,
    );
    expect(find.textContaining('不会重置'), findsNothing);
    expect(
      find.byKey(const ValueKey('subscription-renewal-period-month_price')),
      findsOneWidget,
    );
    expect(periods, isEmpty);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('switching accounts during reset confirmation aborts lookup', (
    tester,
  ) async {
    var lookups = 0;
    final subscription = _subscription(remainingGigabytes: 9);
    globalState
      ..setOfflineMode(false)
      ..xboardSession = _session(subscription);
    addTearDown(globalState.clearXboardSession);
    final service = XboardAuthService(
      plansRequester: (_, _) async {
        lookups++;
        throw StateError('must not look up');
      },
    );
    await tester.pumpWidget(
      _TestApp(
        child: SubscriptionPlanActionBar(
          subscription: subscription,
          authService: service,
          now: now,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('traffic-reset-plan')));
    await _pumpDialogTransition(tester);
    globalState.xboardSession = _session(subscription);
    await tester.tap(find.byKey(const ValueKey('subscription-reset-continue')));
    await tester.pumpAndSettle();
    expect(lookups, 0);
    expect(find.byKey(const ValueKey('payment-ready')), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('failed plan lookup re-enables actions and disposal is safe', (
    tester,
  ) async {
    final subscription = _subscription(
      remainingGigabytes: 9,
      expiresAt: now.add(const Duration(days: 2)),
    );
    globalState
      ..setOfflineMode(false)
      ..xboardSession = _session(subscription);
    addTearDown(globalState.clearXboardSession);
    final pending = Completer<XboardLoginResponse>();
    final service = XboardAuthService(plansRequester: (_, _) => pending.future);
    await tester.pumpWidget(
      _TestApp(
        child: SubscriptionPlanActionBar(
          subscription: subscription,
          authService: service,
          now: now,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('traffic-renew-plan')));
    await tester.pump();
    expect(
      tester
          .widget<FilledButton>(
            find.byKey(const ValueKey('traffic-upgrade-plan')),
          )
          .onPressed,
      isNull,
    );
    pending.completeError(StateError('catalog unavailable'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<FilledButton>(
            find.byKey(const ValueKey('traffic-renew-plan')),
          )
          .onPressed,
      isNotNull,
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'fixed clock updates action boundary and timers dispose on resume',
    (tester) async {
      final subscription = _subscription(
        remainingGigabytes: 20,
        expiresAt: now.add(const Duration(days: 7)),
      );
      Widget app(DateTime? time) => _TestApp(
        child: SubscriptionPlanActionBar(
          subscription: subscription,
          now: time,
          embedded: true,
        ),
      );
      await tester.pumpWidget(app(now));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('traffic-renew-plan')), findsNothing);
      await tester.pumpWidget(app(now.add(const Duration(seconds: 1))));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('traffic-renew-plan')), findsOneWidget);
      await tester.pumpWidget(app(null));
      await tester.pumpAndSettle();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump(const Duration(minutes: 1));
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(minutes: 2));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('late plan lookup after disposal cannot open payment', (
    tester,
  ) async {
    final subscription = _subscription(
      remainingGigabytes: 9,
      expiresAt: now.add(const Duration(days: 2)),
    );
    globalState
      ..setOfflineMode(false)
      ..xboardSession = _session(subscription);
    addTearDown(globalState.clearXboardSession);
    final pending = Completer<XboardLoginResponse>();
    final service = XboardAuthService(plansRequester: (_, _) => pending.future);
    await tester.pumpWidget(
      _TestApp(
        child: SubscriptionPlanActionBar(
          subscription: subscription,
          authService: service,
          now: now,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('traffic-renew-plan')));
    await tester.pump();
    await tester.pumpWidget(const SizedBox.shrink());
    pending.complete(
      const XboardLoginResponse(
        statusCode: 200,
        data: {
          'data': {'id': 1, 'name': 'test', 'month_price': 1000, 'renew': 1},
        },
      ),
    );
    await tester.pump();
    expect(find.byKey(const ValueKey('payment-ready')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('failed upgrade navigation releases busy state', (tester) async {
    await tester.pumpWidget(
      _TestApp(
        child: SubscriptionPlanActionBar(
          subscription: _subscription(remainingGigabytes: 9),
          now: now,
          onUpgrade: () => throw StateError('navigation failed'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('traffic-upgrade-plan')));
    await _pumpDialogTransition(tester);
    await tester.tap(
      find.byKey(const ValueKey('subscription-upgrade-confirm')),
    );
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<FilledButton>(
            find.byKey(const ValueKey('traffic-upgrade-plan')),
          )
          .onPressed,
      isNotNull,
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
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
  DateTime? nextResetAt,
  bool hasPlan = true,
  int? remainingBytes,
}) {
  final endpoint = Uri.parse('https://api.example.com');
  const usedBytes = bytesPerGigabyte;
  return XboardSubscriptionData(
    endpoint: endpoint,
    subscribeUrl: Uri.parse('https://subscribe.example.com/client/token'),
    uploadBytes: usedBytes,
    downloadBytes: 0,
    transferEnableBytes:
        usedBytes + (remainingBytes ?? remainingGigabytes * bytesPerGigabyte),
    planId: hasPlan ? 1 : null,
    plan: hasPlan
        ? const XboardPlanData(id: 1, name: '蜂窝月付套餐', rawData: {})
        : null,
    expiredAtEpochSeconds: unlimited
        ? null
        : (expiresAt ?? DateTime(2027, 8, 29)).millisecondsSinceEpoch ~/ 1000,
    nextResetAtEpochSeconds: nextResetAt == null
        ? null
        : nextResetAt.millisecondsSinceEpoch ~/ 1000,
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
    this.textScale = 1,
  });

  final Widget child;
  final Locale locale;
  final ThemeMode themeMode;
  final double textScale;

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
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: Scaffold(body: Center(child: child)),
    );
  }
}

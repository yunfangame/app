import 'dart:async';

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/l10n/l10n.dart';
import 'package:fl_clash/state.dart';
import 'package:fl_clash/views/traffic/fengwo_traffic_details.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/api_health_fixture.dart';
import '../support/account_view_test_scope.dart';

void main() {
  accountViewReadTest(
    'traffic reuses automatic logs but manual refresh stays fresh',
    (tester) async {
      globalState.activateXboardSession(
        _testSession(),
        subscriptionFresh: true,
      );
      var logs = 0;
      var summaries = 0;
      final activity = await mountAccountView(
        tester,
        FengWoTrafficDetailsView(
          authService: _testService(
            onTrafficRequested: () => logs++,
            onSubscriptionRequested: () => summaries++,
          ),
        ),
        (child) => _TestApp(child: child),
        size: const Size(390, 844),
      );
      expect(logs, 1);
      activity.value = false;
      await tester.pump();
      activity.value = true;
      await tester.pumpAndSettle();
      expect(logs, 1);
      expect(summaries, 0);
      await tester
          .widget<RefreshIndicator>(find.byType(RefreshIndicator))
          .onRefresh();
      await tester.pumpAndSettle();
      expect(logs, 2);
      expect(summaries, 1);
      expect(globalState.xboardSubscription?.remainingGb, 1400);
      activity.value = false;
      await tester.pump();
      activity.value = true;
      await tester.pumpAndSettle();
      expect(logs, 2);
      expect(summaries, 1);
      expect(accountViewWindowCalls, 0);
    },
  );

  accountViewReadTest(
    'traffic initial reads wait for page and app availability',
    (tester) async {
      globalState.activateXboardSession(_testSession());
      var logs = 0;
      final activity = await mountAccountView(
        tester,
        FengWoTrafficDetailsView(
          authService: _testService(onTrafficRequested: () => logs++),
        ),
        (child) => _TestApp(child: child),
        active: false,
      );
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      activity.value = true;
      await tester.pump(const Duration(hours: 1));
      expect(logs, 0);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(logs, 1);
      expect(accountViewWindowCalls, 0);
    },
  );

  accountViewReadTest(
    'manual traffic refresh supersedes its initial in-flight logs',
    (tester) async {
      globalState.activateXboardSession(_testSession());
      final pending = Completer<XboardLoginResponse>();
      late XboardLoginResponse old;
      var logs = 0;
      var summaries = 0;
      await mountAccountView(
        tester,
        FengWoTrafficDetailsView(
          authService: _testService(
            onTrafficRequested: () => logs++,
            onSubscriptionRequested: () => summaries++,
            logsResponse: (call, value) {
              if (call == 1) {
                old = value;
                return pending.future;
              }
              return Future.value(
                const XboardLoginResponse(statusCode: 200, data: {'data': []}),
              );
            },
          ),
        ),
        (child) => _TestApp(child: child),
      );
      await tester
          .widget<RefreshIndicator>(find.byType(RefreshIndicator))
          .onRefresh();
      expect(logs, 2);
      expect(summaries, 1);
      pending.complete(old);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('traffic-record-0')), findsNothing);
      expect(globalState.xboardSubscription?.remainingGb, 1400);
    },
  );

  accountViewReadTest(
    'offline clears traffic reuse and rejects a prior reply',
    (tester) async {
      globalState.activateXboardSession(_testSession());
      final pending = Completer<XboardLoginResponse>();
      late XboardLoginResponse old;
      var logs = 0;
      await mountAccountView(
        tester,
        FengWoTrafficDetailsView(
          authService: _testService(
            onTrafficRequested: () => logs++,
            logsResponse: (call, value) {
              if (call == 1) {
                old = value;
                return pending.future;
              }
              return Future.value(
                const XboardLoginResponse(statusCode: 200, data: {'data': []}),
              );
            },
          ),
        ),
        (child) => _TestApp(child: child),
      );
      globalState.setOfflineMode(true);
      await tester.pump(const Duration(minutes: 10));
      expect(logs, 1);
      globalState.setOfflineMode(false);
      await flushAccountReads(tester);
      expect(logs, 2);
      pending.complete(old);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('traffic-record-0')), findsNothing);
    },
  );

  accountViewReadTest(
    'disposing traffic reads prevents future lifecycle work',
    (tester) async {
      globalState.activateXboardSession(_testSession());
      final pending = Completer<XboardLoginResponse>();
      late XboardLoginResponse old;
      var logs = 0;
      await mountAccountView(
        tester,
        FengWoTrafficDetailsView(
          authService: _testService(
            onTrafficRequested: () => logs++,
            logsResponse: (_, value) {
              old = value;
              return pending.future;
            },
          ),
        ),
        (child) => _TestApp(child: child),
      );
      await tester.pumpWidget(const SizedBox());
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      pending.complete(old);
      await tester.pumpAndSettle();
      expect(logs, 1);
      expect(tester.takeException(), isNull);
    },
  );

  for (final relogin in [false, true]) {
    testWidgets(
      'late traffic refresh cannot replace a newer session ($relogin)',
      (tester) async {
        globalState.setOfflineMode(false);
        globalState.activateXboardSession(_testSession());
        addTearDown(globalState.clearXboardSession);
        final service = _DelayedTrafficAuth();
        await tester.pumpWidget(
          _TestApp(child: FengWoTrafficDetailsView(authService: service)),
        );
        await tester.pumpAndSettle();
        final button = find.byKey(const ValueKey('refresh-traffic-data'));
        await tester.ensureVisible(button);
        await tester.tap(button);
        await tester.pump();
        await tester.pump();
        expect(service.summaryCalls, 1);
        final current = _testSession(unlimited: true);
        if (relogin) globalState.clearXboardSession();
        globalState.activateXboardSession(current, subscriptionFresh: true);
        service.delayedLogs.complete(const []);
        await tester.pumpAndSettle();
        expect(globalState.xboardSession, same(current));
        expect(globalState.xboardSubscription, same(current.subscription));
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('traffic details renders XBoard totals, rates, and refreshes', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(globalState.clearXboardSession);
    globalState.activateXboardSession(_testSession(), subscriptionFresh: true);
    var trafficRequests = 0;
    var subscriptionRequests = 0;
    final service = _testService(
      onTrafficRequested: () => trafficRequests++,
      onSubscriptionRequested: () => subscriptionRequests++,
    );

    await tester.pumpWidget(
      _TestApp(child: FengWoTrafficDetailsView(authService: service)),
    );
    await tester.pumpAndSettle();

    final l10n = tester
        .element(find.byType(FengWoTrafficDetailsView))
        .appLocalizations;
    expect(find.text(l10n.trafficDetails), findsOne);
    expect(find.byKey(const ValueKey('traffic-summary-today')), findsOne);
    expect(find.byKey(const ValueKey('traffic-summary-month')), findsOne);
    expect(find.byKey(const ValueKey('traffic-summary-remaining')), findsOne);
    expect(find.byKey(const ValueKey('traffic-summary-total')), findsOne);
    expect(
      find.byKey(const ValueKey('subscription-plan-actions')),
      findsNothing,
    );
    expect(find.byKey(const ValueKey('traffic-renew-plan')), findsNothing);
    expect(find.byKey(const ValueKey('traffic-upgrade-plan')), findsNothing);
    expect(find.byKey(const ValueKey('traffic-reset-plan')), findsNothing);
    expect(find.text('9 MB'), findsNWidgets(2));
    expect(find.text('1500 GB'), findsOne);
    expect(find.text('2000 GB'), findsOne);
    expect(find.text('2x'), findsOne);
    expect(find.text('4 MB'), findsNWidgets(2));
    expect(trafficRequests, 1);
    expect(subscriptionRequests, 0);

    await tester.tap(find.byKey(const ValueKey('refresh-traffic-data')));
    await tester.pumpAndSettle();

    expect(trafficRequests, 2);
    expect(subscriptionRequests, 1);
    expect(globalState.xboardSubscription?.remainingGb, 1400);
    final displayed = globalState.xboardSubscription;
    final automatic = await globalState.loadXboardSubscriptionSnapshot(
      service,
      globalState.xboardSession!,
    );
    expect(automatic, same(displayed));
    expect(automatic.remainingGb, 1400);
    expect(subscriptionRequests, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('traffic details adapts to a narrow dark mobile viewport', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(globalState.clearXboardSession);
    globalState.xboardSession = _testSession();

    await tester.pumpWidget(
      _TestApp(
        themeMode: ThemeMode.dark,
        child: FengWoTrafficDetailsView(authService: _testService()),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('fengwo-traffic-details-scroll')),
      findsOne,
    );
    expect(find.byKey(const ValueKey('traffic-record-0')), findsOne);
    expect(find.byKey(const ValueKey('traffic-record-1')), findsOne);
    expect(find.byKey(const ValueKey('traffic-summary-total')), findsOne);
    expect(tester.takeException(), isNull);
  });

  testWidgets('unlimited traffic view hides upgrade and ample reset', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(globalState.clearXboardSession);
    globalState.xboardSession = _testSession(unlimited: true);
    await tester.pumpWidget(
      _TestApp(child: FengWoTrafficDetailsView(authService: _testService())),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('traffic-renew-plan')), findsNothing);
    expect(find.byKey(const ValueKey('traffic-upgrade-plan')), findsNothing);
    expect(find.byKey(const ValueKey('traffic-reset-plan')), findsNothing);
    expect(tester.takeException(), isNull);
  });
}

class _DelayedTrafficAuth extends XboardAuthService {
  int logCalls = 0;
  int summaryCalls = 0;
  final delayedLogs = Completer<List<XboardTrafficLog>>();

  @override
  Future<List<XboardTrafficLog>> fetchTrafficLogs({
    required Uri endpoint,
    required String authData,
  }) {
    logCalls++;
    return logCalls == 1 ? Future.value(const []) : delayedLogs.future;
  }

  @override
  Future<XboardSubscriptionData> fetchSubscription({
    required Uri endpoint,
    required String authData,
    String? userToken,
    bool secureSubscription = false,
  }) async {
    summaryCalls++;
    return _testSession().subscription;
  }
}

XboardAuthService _testService({
  VoidCallback? onTrafficRequested,
  VoidCallback? onSubscriptionRequested,
  Future<XboardLoginResponse> Function(int, XboardLoginResponse)? logsResponse,
}) {
  var logs = 0;
  return XboardAuthService(
    apiHealthService: ApiHealthFixture(Uri.parse('https://api.example.com')),
    trafficLogsRequester: (endpoint, authData) async {
      logs++;
      onTrafficRequested?.call();
      final today = DateTime.now();
      final recordAt =
          DateTime(
            today.year,
            today.month,
            today.day,
            12,
          ).millisecondsSinceEpoch ~/
          1000;
      final response = XboardLoginResponse(
        statusCode: 200,
        data: {
          'data': [
            {
              'd': 4 * 1024 * 1024,
              'u': 1024 * 1024,
              'record_at': recordAt,
              'server_rate': 1,
            },
            {
              'd': 2 * 1024 * 1024,
              'u': 0,
              'record_at': recordAt - 60,
              'server_rate': 2,
            },
          ],
        },
      );
      return logsResponse?.call(logs, response) ?? response;
    },
    subscriptionRequester: (endpoint, authData) async {
      onSubscriptionRequested?.call();
      return const XboardLoginResponse(
        statusCode: 200,
        data: {
          'data': {
            'plan_id': 7,
            'expired_at': 1819497600,
            'subscribe_url': 'https://api.example.com/subscribe',
            'u': bytesPerGigabyte * 250,
            'd': bytesPerGigabyte * 350,
            'transfer_enable': bytesPerGigabyte * 2000,
            'email': 'member@example.com',
            'plan': {'id': 7, 'name': '会员套餐'},
          },
        },
      );
    },
  );
}

XboardLoginResult _testSession({bool unlimited = false}) {
  final endpoint = Uri.parse('https://api.example.com');
  return XboardLoginResult(
    endpoint: endpoint,
    token: 'subscription-token',
    authData: 'Bearer account-token',
    isAdmin: false,
    subscription: XboardSubscriptionData(
      endpoint: endpoint,
      subscribeUrl: Uri.parse('https://api.example.com/subscribe'),
      uploadBytes: bytesPerGigabyte * 200,
      downloadBytes: bytesPerGigabyte * 300,
      transferEnableBytes: bytesPerGigabyte * 2000,
      planId: 7,
      email: 'member@example.com',
      expiredAtEpochSeconds: unlimited
          ? null
          : DateTime.now()
                    .add(const Duration(days: 30))
                    .millisecondsSinceEpoch ~/
                1000,
      plan: const XboardPlanData(id: 7, name: '会员套餐', rawData: {}),
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

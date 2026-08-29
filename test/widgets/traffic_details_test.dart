import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/l10n/l10n.dart';
import 'package:fl_clash/state.dart';
import 'package:fl_clash/views/traffic/fengwo_traffic_details.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('traffic details renders XBoard totals, rates, and refreshes', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(globalState.clearXboardSession);
    globalState.xboardSession = _testSession();
    var trafficRequests = 0;
    var subscriptionRequests = 0;

    await tester.pumpWidget(
      _TestApp(
        child: FengWoTrafficDetailsView(
          authService: _testService(
            onTrafficRequested: () => trafficRequests++,
            onSubscriptionRequested: () => subscriptionRequests++,
          ),
        ),
      ),
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
    expect(find.byKey(const ValueKey('subscription-plan-actions')), findsOne);
    expect(find.byKey(const ValueKey('traffic-renew-plan')), findsOne);
    expect(find.byKey(const ValueKey('traffic-upgrade-plan')), findsOne);
    expect(find.byKey(const ValueKey('traffic-reset-plan')), findsOne);
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

  testWidgets('unlimited traffic view only offers upgrade and reset', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(globalState.clearXboardSession);
    globalState.xboardSession = _testSession(unlimited: true);
    var upgraded = false;

    await tester.pumpWidget(
      _TestApp(
        child: FengWoTrafficDetailsView(
          authService: _testService(),
          onUpgradePlan: () => upgraded = true,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('traffic-renew-plan')), findsNothing);
    expect(find.byKey(const ValueKey('traffic-upgrade-plan')), findsOne);
    expect(find.byKey(const ValueKey('traffic-reset-plan')), findsOne);
    await tester.tap(find.byKey(const ValueKey('traffic-upgrade-plan')));
    await tester.pump();
    expect(upgraded, isTrue);
    expect(tester.takeException(), isNull);
  });
}

XboardAuthService _testService({
  VoidCallback? onTrafficRequested,
  VoidCallback? onSubscriptionRequested,
}) {
  return XboardAuthService(
    trafficLogsRequester: (endpoint, authData) async {
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
      return XboardLoginResponse(
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
      expiredAtEpochSeconds: unlimited ? null : 1819497600,
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

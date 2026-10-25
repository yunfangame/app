import 'dart:async';

import 'package:fl_clash/common/xboard_auth.dart';
import 'package:fl_clash/l10n/l10n.dart';
import 'package:fl_clash/state.dart';
import 'package:fl_clash/views/dashboard/widgets/dashboard_subscription_refresh_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('manual summary refresh forces the full path and merges taps', (
    tester,
  ) async {
    globalState.setOfflineMode(false);
    globalState.activateXboardSession(
      XboardLoginResult(
        endpoint: Uri.https('manual-refresh.example'),
        authData: 'auth',
        token: 'token',
        isAdmin: false,
        subscription: XboardSubscriptionData(
          endpoint: Uri.https('manual-refresh.example'),
          subscribeUrl: null,
          uploadBytes: 0,
          downloadBytes: 0,
          transferEnableBytes: 100,
          rawData: const {},
        ),
      ),
    );
    addTearDown(() {
      globalState.clearXboardSession();
      globalState.refreshXboardSubscriptionView = null;
      globalState.refreshXboardSubscription = null;
    });
    final pending = Completer<bool>();
    var forced = 0;
    var legacy = 0;
    globalState.refreshXboardSubscription = () async {
      legacy++;
      return true;
    };
    globalState.refreshXboardSubscriptionView = ({bool forceRefresh = false}) {
      expect(forceRefresh, isTrue);
      forced++;
      return pending.future;
    };
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh', 'CN'),
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.delegate.supportedLocales,
        home: const Scaffold(body: DashboardSubscriptionRefreshButton()),
      ),
    );
    final button = find.byKey(
      const ValueKey('fengwo-dashboard-traffic-refresh'),
    );
    await tester.tap(button);
    await tester.pump();
    await tester.tap(button);
    expect(forced, 1);
    expect(legacy, 0);
    pending.complete(true);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/l10n/l10n.dart';
import 'package:fl_clash/state.dart';
import 'package:fl_clash/widgets/fengwo_global_account_header.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('monthly subscription shows its next traffic reset time', (
    tester,
  ) async {
    await tester.pumpWidget(
      _TestApp(
        themeMode: ThemeMode.dark,
        child: SizedBox(
          width: 1100,
          child: FengWoGlobalAccountHeader(
            subscription: _subscription(monthly: true),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(
      find.byKey(const ValueKey('fengwo-global-next-plan-reset')),
      findsOneWidget,
    );
    expect(find.textContaining('下次套餐重置时间'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('unlimited subscription hides the next traffic reset time', (
    tester,
  ) async {
    await tester.pumpWidget(
      _TestApp(
        child: SizedBox(
          width: 1100,
          child: FengWoGlobalAccountHeader(
            subscription: _subscription(monthly: false),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(
      find.byKey(const ValueKey('fengwo-global-next-plan-reset')),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('notification bell opens the global announcement center', (
    tester,
  ) async {
    var requested = false;
    globalState.showXboardAnnouncements = ({required automatic}) {
      requested = !automatic;
    };
    addTearDown(() => globalState.showXboardAnnouncements = null);

    await tester.pumpWidget(
      _TestApp(
        child: SizedBox(
          width: 1100,
          child: FengWoGlobalAccountHeader(
            subscription: _subscription(monthly: true),
          ),
        ),
      ),
    );

    await tester.tap(find.byTooltip('查看公告'));
    await tester.pump();

    expect(requested, isTrue);
  });
}

XboardSubscriptionData _subscription({required bool monthly}) {
  final endpoint = Uri.parse('https://api.example.com');
  return XboardSubscriptionData(
    endpoint: endpoint,
    subscribeUrl: Uri.parse('https://api.example.com/subscribe'),
    uploadBytes: bytesPerGigabyte,
    downloadBytes: bytesPerGigabyte,
    transferEnableBytes: bytesPerGigabyte * 60,
    email: 'member@example.com',
    expiredAtEpochSeconds: monthly ? 1819497600 : null,
    nextResetAtEpochSeconds: 1800000000,
    plan: const XboardPlanData(id: 7, name: '会员套餐', rawData: {}),
    rawData: const {},
  );
}

class _TestApp extends StatelessWidget {
  const _TestApp({required this.child, this.themeMode = ThemeMode.light});

  final Widget child;
  final ThemeMode themeMode;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      locale: const Locale('zh', 'CN'),
      theme: ThemeData(colorSchemeSeed: const Color(0xFF2468E8)),
      darkTheme: ThemeData(
        brightness: Brightness.dark,
        colorSchemeSeed: const Color(0xFF78A7FF),
      ),
      themeMode: themeMode,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.delegate.supportedLocales,
      home: Scaffold(
        body: Align(alignment: Alignment.topCenter, child: child),
      ),
    );
  }
}

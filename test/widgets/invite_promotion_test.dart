import 'dart:async';

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/l10n/l10n.dart';
import 'package:fl_clash/state.dart';
import 'package:fl_clash/views/invite/fengwo_invite_promotion.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('copies the configured invite link and reloads it on each tap', (
    tester,
  ) async {
    final copied = <String>[];
    _recordClipboard(tester, copied);
    final config = Completer<Object?>();
    var loads = 0;
    await _pumpInvitePage(tester, () {
      loads++;
      return loads == 1
          ? config.future
          : Future.value({
              'InviteLink': 'https://new.example.com#/register?code=',
            });
    });
    final button = find.byKey(const ValueKey('copy-invite-SIQU5wev'));
    final l10n = tester.element(button).appLocalizations;
    expect(find.text(l10n.copyInviteLink), findsOneWidget);
    final tap = tester.widget<TextButton>(button).onPressed!;
    tap();
    tap();
    await tester.pump();
    expect(loads, 1);
    expect(tester.widget<TextButton>(button).onPressed, isNull);
    expect(copied, isEmpty);

    config.complete({
      'InviteLink': 'https://share.fengwo.live#/register?code=',
    });
    await tester.pumpAndSettle();
    expect(copied, ['https://share.fengwo.live#/register?code=SIQU5wev']);
    expect(find.text(l10n.inviteLinkCopied), findsOneWidget);
    expect(tester.widget<TextButton>(button).onPressed, isNotNull);

    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(loads, 2);
    expect(copied.last, 'https://new.example.com#/register?code=SIQU5wev');
    expect(tester.takeException(), isNull);
  });

  for (final failure in [
    'missing config',
    'load failure',
    'clipboard failure',
  ]) {
    testWidgets('invite link reports $failure and allows retry', (
      tester,
    ) async {
      final copied = <String>[];
      var fail = true;
      _recordClipboard(
        tester,
        copied,
        shouldFail: () => fail && failure == 'clipboard failure',
      );
      await _pumpInvitePage(tester, () async {
        if (fail && failure == 'load failure') {
          throw StateError('Configuration unavailable');
        }
        if (fail && failure == 'missing config') return {};
        return {'InviteLink': 'https://share.example.com#/register?code='};
      });
      final button = find.byKey(const ValueKey('copy-invite-SIQU5wev'));
      final l10n = tester.element(button).appLocalizations;
      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(copied, isEmpty);
      expect(find.text(l10n.inviteLinkCopyFailed), findsOneWidget);
      expect(find.text(l10n.inviteLinkCopied), findsNothing);
      expect(tester.widget<TextButton>(button).onPressed, isNotNull);

      fail = false;
      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(copied, ['https://share.example.com#/register?code=SIQU5wev']);
      expect(find.text(l10n.inviteLinkCopied), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('leaving the page during loading does not copy or update UI', (
    tester,
  ) async {
    final copied = <String>[];
    _recordClipboard(tester, copied);
    final config = Completer<Object?>();
    await _pumpInvitePage(tester, () => config.future);
    await tester.tap(find.byKey(const ValueKey('copy-invite-SIQU5wev')));
    await tester.pump();
    await tester.pumpWidget(const SizedBox.shrink());
    config.complete({
      'InviteLink': 'https://share.example.com#/register?code=',
    });
    await tester.pumpAndSettle();
    expect(copied, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'invite page renders desktop layout and submits withdrawal ticket',
    (tester) async {
      tester.view.physicalSize = const Size(840, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(globalState.clearXboardSession);
      globalState.xboardSession = _testSession();
      var ticketSubject = '';
      var ticketMessage = '';

      await tester.pumpWidget(
        _TestApp(
          child: FengWoInvitePromotionView(
            authService: _testService(
              commissionRecordCount: 18,
              onTicketSubmitted: (subject, message) {
                ticketSubject = subject;
                ticketMessage = message;
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final l10n = tester
          .element(find.byType(FengWoInvitePromotionView))
          .appLocalizations;
      expect(find.byKey(const ValueKey('invite-hero')), findsOne);
      expect(find.byKey(const ValueKey('invite-stats')), findsOne);
      expect(find.byKey(const ValueKey('invite-rewards-hero-image')), findsOne);
      expect(find.text('SIQU5wev'), findsOne);
      expect(find.text('¥10.00'), findsWidgets);
      final codesPosition = tester.getTopLeft(
        find.byKey(const ValueKey('invite-codes-panel')),
      );
      final commissionPosition = tester.getTopLeft(
        find.byKey(const ValueKey('invite-commission-panel')),
      );
      expect(codesPosition.dx, lessThan(commissionPosition.dx));
      expect((codesPosition.dy - commissionPosition.dy).abs(), lessThan(1));
      final codesSize = tester.getSize(
        find.byKey(const ValueKey('invite-codes-panel')),
      );
      final commissionSize = tester.getSize(
        find.byKey(const ValueKey('invite-commission-panel')),
      );
      expect((codesSize.height - commissionSize.height).abs(), lessThan(1));
      final recordsList = find.byKey(
        const ValueKey('invite-commission-records-scroll'),
      );
      expect(recordsList, findsOneWidget);
      final recordsScrollable = find.descendant(
        of: recordsList,
        matching: find.byType(Scrollable),
      );
      expect(
        tester
            .state<ScrollableState>(recordsScrollable)
            .position
            .maxScrollExtent,
        greaterThan(0),
      );

      await tester.tap(find.byKey(const ValueKey('invite-withdraw-button')));
      await tester.pumpAndSettle();
      expect(find.text(l10n.withdrawalRequestTitle), findsOne);

      await tester.tap(find.byKey(const ValueKey('withdrawal-method-field')));
      await tester.pumpAndSettle();
      await tester.tap(find.text(l10n.withdrawalMethodUsdt).last);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('withdrawal-amount-field')),
        '50',
      );
      await tester.enterText(
        find.byKey(const ValueKey('withdrawal-account-field')),
        'TRX-test-address',
      );
      await tester.tap(
        find.byKey(const ValueKey('submit-withdrawal-ticket-button')),
      );
      await tester.pumpAndSettle();

      expect(ticketSubject, l10n.withdrawalRequestTitle);
      expect(ticketMessage, contains(l10n.withdrawalMethodUsdt));
      expect(ticketMessage, contains('50.00 CNY'));
      expect(ticketMessage, contains('TRX-test-address'));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('invite page stacks panels on a narrow dark mobile viewport', (
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
        child: FengWoInvitePromotionView(authService: _testService()),
      ),
    );
    await tester.pumpAndSettle();

    final codesPosition = tester.getTopLeft(
      find.byKey(const ValueKey('invite-codes-panel')),
    );
    final commissionPosition = tester.getTopLeft(
      find.byKey(const ValueKey('invite-commission-panel')),
    );
    expect(
      find.byKey(const ValueKey('fengwo-invite-promotion-scroll')),
      findsOne,
    );
    expect(codesPosition.dy, lessThan(commissionPosition.dy));
    expect((codesPosition.dx - commissionPosition.dx).abs(), lessThan(1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('desktop commission empty state matches invite panel height', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(840, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(globalState.clearXboardSession);
    globalState.xboardSession = _testSession();

    await tester.pumpWidget(
      _TestApp(
        child: FengWoInvitePromotionView(
          authService: _testService(commissionRecordCount: 0),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final codesSize = tester.getSize(
      find.byKey(const ValueKey('invite-codes-panel')),
    );
    final commissionSize = tester.getSize(
      find.byKey(const ValueKey('invite-commission-panel')),
    );
    expect((codesSize.height - commissionSize.height).abs(), lessThan(1));
    expect(
      find.byKey(const ValueKey('invite-commission-records-scroll')),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });
}

Future<void> _pumpInvitePage(
  WidgetTester tester,
  Future<Object?> Function() configLoader,
) async {
  tester.view.physicalSize = const Size(1000, 1200);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(globalState.clearXboardSession);
  globalState.xboardSession = _testSession();
  await tester.pumpWidget(
    _TestApp(
      child: FengWoInvitePromotionView(
        authService: _testService(),
        inviteConfigLoader: configLoader,
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.ensureVisible(
    find.byKey(const ValueKey('copy-invite-SIQU5wev')),
  );
  await tester.pumpAndSettle();
}

void _recordClipboard(
  WidgetTester tester,
  List<String> copied, {
  bool Function()? shouldFail,
}) {
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    SystemChannels.platform,
    (call) async {
      if (call.method == 'Clipboard.setData') {
        if (shouldFail?.call() == true) {
          throw PlatformException(code: 'clipboard_unavailable');
        }
        copied.add((call.arguments as Map)['text'] as String);
      }
      return null;
    },
  );
  addTearDown(
    () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      null,
    ),
  );
}

XboardAuthService _testService({
  void Function(String subject, String message)? onTicketSubmitted,
  int commissionRecordCount = 1,
}) {
  return XboardAuthService(
    inviteFetchRequester: (endpoint, authData) async {
      return const XboardLoginResponse(
        statusCode: 200,
        data: {
          'data': {
            'codes': [
              {
                'code': 'SIQU5wev',
                'pv': 8,
                'status': 0,
                'created_at': 1787126400,
              },
            ],
            'stat': [3, 12500, 2300, 10, 8000],
          },
        },
      );
    },
    inviteDetailsRequester: (endpoint, authData) async {
      return XboardLoginResponse(
        statusCode: 200,
        data: {
          'data': List.generate(
            commissionRecordCount,
            (index) => {
              'id': index + 1,
              'order_amount': 10000,
              'trade_no': '20260829${index.toString().padLeft(3, '0')}',
              'get_amount': 1000,
              'created_at': 1787961600 - index * 86400,
            },
          ),
          'total': commissionRecordCount,
        },
      );
    },
    inviteSaveRequester: (endpoint, authData) async {
      return const XboardLoginResponse(statusCode: 200, data: {'data': true});
    },
    commissionTransferRequester: (endpoint, authData, amount) async {
      return const XboardLoginResponse(statusCode: 200, data: {'data': true});
    },
    ticketSaveRequester: (endpoint, authData, subject, level, message) async {
      onTicketSubmitted?.call(subject, message);
      return const XboardLoginResponse(statusCode: 200, data: {'data': true});
    },
  );
}

XboardLoginResult _testSession() {
  final endpoint = Uri.parse('https://api.example.com');
  return XboardLoginResult(
    endpoint: endpoint,
    token: 'subscription-token',
    authData: 'Bearer account-token',
    isAdmin: false,
    subscription: XboardSubscriptionData(
      endpoint: endpoint,
      subscribeUrl: Uri.parse('https://api.example.com/subscribe'),
      uploadBytes: 0,
      downloadBytes: 0,
      transferEnableBytes: bytesPerGigabyte * 100,
      email: 'member@example.com',
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
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.delegate.supportedLocales,
      home: Scaffold(body: child),
    );
  }
}

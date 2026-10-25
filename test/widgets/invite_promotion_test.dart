import 'dart:async';

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/l10n/l10n.dart';
import 'package:fl_clash/state.dart';
import 'package:fl_clash/views/invite/fengwo_invite_promotion.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/api_health_fixture.dart';
import '../support/account_view_test_scope.dart';

void main() {
  accountViewReadTest(
    'invite resumes only the details interrupted by app pause',
    (tester) async {
      globalState.activateXboardSession(_testSession());
      final pending = Completer<XboardLoginResponse>();
      late XboardLoginResponse old;
      var summaries = 0;
      var details = 0;
      await mountAccountView(
        tester,
        FengWoInvitePromotionView(
          authService: _testService(
            onSummaryRequested: () => summaries++,
            onDetailsRequested: () => details++,
            detailsResponse: (call, value) {
              if (call == 1) {
                old = value;
                return pending.future;
              }
              return Future.value(value);
            },
          ),
        ),
        (child) => _TestApp(child: child),
      );
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      pending.complete(old);
      await flushAccountReads(tester);
      expect(details, 1);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(summaries, 1);
      expect(details, 2);
      expect(tester.takeException(), isNull);
    },
  );

  accountViewReadTest(
    'background invite writes keep a full refresh after late generation',
    (tester) async {
      globalState.activateXboardSession(_testSession());
      final generated = Completer<XboardLoginResponse>();
      final transferred = Completer<XboardLoginResponse>();
      var summaries = 0;
      var details = 0;
      await mountAccountView(
        tester,
        FengWoInvitePromotionView(
          authService: _testService(
            onSummaryRequested: () => summaries++,
            onDetailsRequested: () => details++,
            generateResponse: () => generated.future,
            transferResponse: () => transferred.future,
          ),
        ),
        (child) => _TestApp(child: child),
      );
      tester
          .widget<FilledButton>(
            find.byKey(const ValueKey('generate-invite-code-button')),
          )
          .onPressed!();
      tester
          .widget<FilledButton>(
            find.byKey(const ValueKey('invite-transfer-button')),
          )
          .onPressed!();
      await tester.pump(const Duration(milliseconds: 250));
      final l10n = tester
          .element(find.byType(FengWoInvitePromotionView))
          .appLocalizations;
      await tester.tap(find.widgetWithText(FilledButton, l10n.confirm));
      await tester.pump();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      transferred.complete(
        const XboardLoginResponse(statusCode: 200, data: {'data': true}),
      );
      await flushAccountReads(tester);
      generated.complete(
        const XboardLoginResponse(statusCode: 200, data: {'data': true}),
      );
      await flushAccountReads(tester);
      expect(summaries, 1);
      expect(details, 1);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(summaries, 2);
      expect(details, 2);
      expect(accountViewWindowCalls, 0);
    },
  );

  accountViewReadTest(
    'invite initial reads wait for active foreground and online',
    (tester) async {
      globalState.activateXboardSession(_testSession());
      var summaries = 0;
      var details = 0;
      final activity = await mountAccountView(
        tester,
        FengWoInvitePromotionView(
          authService: _testService(
            onSummaryRequested: () => summaries++,
            onDetailsRequested: () => details++,
          ),
        ),
        (child) => _TestApp(child: child),
        active: false,
        size: const Size(390, 844),
      );
      expect(summaries, 0);
      expect(details, 0);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      activity.value = true;
      await tester.pump(const Duration(hours: 1));
      expect(summaries, 0);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(summaries, 1);
      expect(details, 1);
      globalState.setOfflineMode(true);
      await tester.pump(const Duration(minutes: 10));
      expect(summaries, 1);
      globalState.setOfflineMode(false);
      await tester.pumpAndSettle();
      expect(summaries, 2);
      expect(details, 2);
      expect(accountViewWindowCalls, 0);
    },
  );

  accountViewReadTest('repeated invite entry replaces each paused read', (
    tester,
  ) async {
    globalState.activateXboardSession(_testSession());
    final summary = Completer<XboardLoginResponse>();
    final detail = Completer<XboardLoginResponse>();
    late XboardLoginResponse summaryValue;
    late XboardLoginResponse detailValue;
    var summaries = 0;
    var details = 0;
    final activity = await mountAccountView(
      tester,
      FengWoInvitePromotionView(
        authService: _testService(
          onSummaryRequested: () => summaries++,
          onDetailsRequested: () => details++,
          summaryResponse: (_, value) {
            summaryValue = value;
            return summary.future;
          },
          detailsResponse: (_, value) {
            detailValue = value;
            return detail.future;
          },
        ),
      ),
      (child) => _TestApp(child: child),
    );
    activity.value = false;
    await tester.pump();
    activity.value = true;
    await flushAccountReads(tester);
    expect(summaries, 2);
    expect(details, 2);
    summary.complete(summaryValue);
    detail.complete(detailValue);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('copy-invite-SIQU5wev')), findsOneWidget);
  });

  for (final transfer in [false, true]) {
    accountViewReadTest(
      'invite mutation bypasses old reads, transfer=$transfer',
      (tester) async {
        globalState.activateXboardSession(_testSession());
        final summary = Completer<XboardLoginResponse>();
        final detail = Completer<XboardLoginResponse>();
        late XboardLoginResponse oldSummary;
        late XboardLoginResponse oldDetail;
        var summaries = 0;
        var details = 0;
        await mountAccountView(
          tester,
          FengWoInvitePromotionView(
            authService: _testService(
              onSummaryRequested: () => summaries++,
              onDetailsRequested: () => details++,
              summaryResponse: (call, value) {
                if (call == 2) {
                  oldSummary = value;
                  return summary.future;
                }
                return Future.value(
                  call == 3 ? _inviteSummaryResponse('UPDATED') : value,
                );
              },
              detailsResponse: (call, value) {
                if (call == 2) {
                  oldDetail = value;
                  return detail.future;
                }
                return Future.value(value);
              },
            ),
          ),
          (child) => _TestApp(child: child),
        );
        final refresh = tester
            .widget<RefreshIndicator>(find.byType(RefreshIndicator))
            .onRefresh();
        await flushAccountReads(tester);
        expect(summaries, 2);
        expect(details, 2);
        final key = transfer
            ? 'invite-transfer-button'
            : 'generate-invite-code-button';
        tester.widget<FilledButton>(find.byKey(ValueKey(key))).onPressed!();
        if (transfer) {
          await tester.pump(const Duration(milliseconds: 250));
          final l10n = tester
              .element(find.byType(FengWoInvitePromotionView))
              .appLocalizations;
          await tester.tap(find.widgetWithText(FilledButton, l10n.confirm));
        }
        await flushAccountReads(tester);
        expect(summaries, 3);
        expect(details, transfer ? 3 : 2);
        summary.complete(oldSummary);
        detail.complete(oldDetail);
        await refresh;
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('copy-invite-UPDATED')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('copy-invite-SIQU5wev')),
          findsNothing,
        );
      },
    );
  }

  accountViewReadTest(
    'a previous account invite reply cannot replace the new account',
    (tester) async {
      globalState.activateXboardSession(_testSession());
      final old = Completer<XboardLoginResponse>();
      late XboardLoginResponse value;
      var summaries = 0;
      await mountAccountView(
        tester,
        FengWoInvitePromotionView(
          authService: _testService(
            onSummaryRequested: () => summaries++,
            summaryResponse: (call, response) {
              if (call == 1) {
                value = response;
                return old.future;
              }
              return Future.value(_inviteSummaryResponse('CURRENT'));
            },
          ),
        ),
        (child) => _TestApp(child: child),
      );
      globalState.clearXboardSession();
      globalState.activateXboardSession(_testSession());
      await flushAccountReads(tester);
      expect(summaries, 2);
      old.complete(value);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('copy-invite-CURRENT')), findsOneWidget);
      expect(find.byKey(const ValueKey('copy-invite-SIQU5wev')), findsNothing);
    },
  );

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

XboardLoginResponse _inviteSummaryResponse(String code) => XboardLoginResponse(
  statusCode: 200,
  data: {
    'data': {
      'codes': [
        {'code': code, 'pv': 0, 'status': 0, 'created_at': 1787126400},
      ],
      'stat': [3, 12500, 2300, 10, 8000],
    },
  },
);

XboardAuthService _testService({
  void Function(String subject, String message)? onTicketSubmitted,
  int commissionRecordCount = 1,
  VoidCallback? onSummaryRequested,
  VoidCallback? onDetailsRequested,
  Future<XboardLoginResponse> Function(int, XboardLoginResponse)?
  summaryResponse,
  Future<XboardLoginResponse> Function(int, XboardLoginResponse)?
  detailsResponse,
  Future<XboardLoginResponse> Function()? generateResponse,
  Future<XboardLoginResponse> Function()? transferResponse,
}) {
  var summaries = 0;
  var details = 0;
  return XboardAuthService(
    apiHealthService: ApiHealthFixture(Uri.parse('https://api.example.com')),
    inviteFetchRequester: (endpoint, authData) async {
      summaries++;
      onSummaryRequested?.call();
      const response = XboardLoginResponse(
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
      return summaryResponse?.call(summaries, response) ?? response;
    },
    inviteDetailsRequester: (endpoint, authData) async {
      details++;
      onDetailsRequested?.call();
      final response = XboardLoginResponse(
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
      return detailsResponse?.call(details, response) ?? response;
    },
    inviteSaveRequester: (endpoint, authData) async {
      if (generateResponse != null) return generateResponse();
      return const XboardLoginResponse(statusCode: 200, data: {'data': true});
    },
    commissionTransferRequester: (endpoint, authData, amount) async {
      if (transferResponse != null) return transferResponse();
      return const XboardLoginResponse(statusCode: 200, data: {'data': true});
    },
    ticketSaveRequester: (endpoint, authData, subject, level, message) async {
      onTicketSubmitted?.call(subject, message);
      return const XboardLoginResponse(statusCode: 200, data: {'data': true});
    },
  );
}

XboardLoginResult _testSession({String authData = 'Bearer account-token'}) {
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

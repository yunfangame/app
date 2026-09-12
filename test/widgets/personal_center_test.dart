import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/common/xboard_tickets.dart';
import 'package:fl_clash/l10n/l10n.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/state.dart';
import 'package:fl_clash/views/account/fengwo_personal_center.dart';
import 'package:fl_clash/widgets/fengwo_account_avatar.dart';
import 'package:fl_clash/widgets/inherited.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/ticket_fixtures.dart';

void main() {
  testWidgets(
    'personal center renders account data and updates real controls',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(globalState.clearXboardSession);
      globalState.xboardSession = _testSession();
      var passwordChanged = false;
      final loginIpState = _LoginIpTestState();

      await tester.pumpWidget(
        _TestApp(
          child: FengWoPersonalCenterView(
            ticketController: _ticketController(),
            authService: _testService(
              onPasswordChanged: () => passwordChanged = true,
              loginIpState: loginIpState,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('account-profile-card')), findsOne);
      expect(find.byType(FengWoAccountAvatar), findsOne);
      final avatarImage = tester.widget<Image>(
        find.descendant(
          of: find.byType(FengWoAccountAvatar),
          matching: find.byType(Image),
        ),
      );
      expect(
        (avatarImage.image as AssetImage).assetName,
        fengWoAccountAvatarAsset,
      );
      expect(find.byKey(const ValueKey('account-wallet-card')), findsOne);
      expect(find.byKey(const ValueKey('account-password-card')), findsOne);
      expect(find.byKey(const ValueKey('account-login-ip-card')), findsOne);
      expect(
        find.byKey(const ValueKey('account-notifications-card')),
        findsNothing,
      );
      expect(find.byKey(const ValueKey('login-ip-17-app')), findsOne);
      expect(find.byKey(const ValueKey('login-ip-18-web')), findsOne);
      expect(find.byKey(const ValueKey('account-auto-renew-row')), findsOne);
      expect(
        find.byKey(const ValueKey('reset-subscription-card')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('reset-subscription-button')),
        findsNothing,
      );
      expect(find.byKey(const ValueKey('account-logout-button')), findsNothing);
      expect(find.text('member@example.com'), findsOne);
      expect(find.text('12.50'), findsOne);
      expect(find.text('蜂窝旗舰套餐'), findsOne);
      final profilePosition = tester.getTopLeft(
        find.byKey(const ValueKey('account-profile-card')),
      );
      final walletPosition = tester.getTopLeft(
        find.byKey(const ValueKey('account-wallet-card')),
      );
      expect(profilePosition.dx, lessThan(walletPosition.dx));
      expect((profilePosition.dy - walletPosition.dy).abs(), lessThan(1));
      final passwordPosition = tester.getTopLeft(
        find.byKey(const ValueKey('account-password-card')),
      );
      final loginIpPosition = tester.getTopLeft(
        find.byKey(const ValueKey('account-login-ip-card')),
      );
      expect(passwordPosition.dy, greaterThan(profilePosition.dy));
      expect(loginIpPosition.dy, greaterThan(passwordPosition.dy));
      final oldPasswordPosition = tester.getTopLeft(
        find.byKey(const ValueKey('old-password-field')),
      );
      final newPasswordPosition = tester.getTopLeft(
        find.byKey(const ValueKey('new-password-field')),
      );
      final confirmPasswordPosition = tester.getTopLeft(
        find.byKey(const ValueKey('confirm-password-field')),
      );
      expect(oldPasswordPosition.dy, lessThan(newPasswordPosition.dy));
      expect(newPasswordPosition.dy, lessThan(confirmPasswordPosition.dy));
      final ticketCard = find.byKey(const ValueKey('account-ticket-card'));
      expect(
        tester.getTopLeft(ticketCard).dx,
        greaterThan(passwordPosition.dx),
      );
      expect(
        (tester.getTopLeft(ticketCard).dy - passwordPosition.dy).abs(),
        lessThan(1),
      );
      expect(
        tester.getSize(ticketCard).height,
        tester
            .getSize(find.byKey(const ValueKey('account-password-card')))
            .height,
      );

      final autoRenewSwitch = find.descendant(
        of: find.byKey(const ValueKey('account-auto-renew-row')),
        matching: find.byType(Switch),
      );
      expect(tester.widget<Switch>(autoRenewSwitch).value, isFalse);
      expect(tester.widget<Switch>(autoRenewSwitch).onChanged, isNull);

      final blockButton = find.byKey(
        const ValueKey('block-login-ip-17-178.94.14.100'),
      );
      await tester.ensureVisible(blockButton);
      await tester.pumpAndSettle();
      await tester.tap(blockButton);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('block-login-ip-reason-field')),
        'not mine',
      );
      await tester.tap(
        find.byKey(const ValueKey('confirm-block-login-ip-button')),
      );
      await tester.pumpAndSettle();
      expect(loginIpState.blockedIp, '178.94.14.100');
      expect(loginIpState.blockReason, 'not mine');
      expect(loginIpState.firstIpBlocked, isTrue);

      await tester.enterText(
        find.descendant(
          of: find.byKey(const ValueKey('old-password-field')),
          matching: find.byType(TextFormField),
        ),
        'old-secret',
      );
      await tester.enterText(
        find.descendant(
          of: find.byKey(const ValueKey('new-password-field')),
          matching: find.byType(TextFormField),
        ),
        'new-secret',
      );
      await tester.enterText(
        find.descendant(
          of: find.byKey(const ValueKey('confirm-password-field')),
          matching: find.byType(TextFormField),
        ),
        'new-secret',
      );
      final savePasswordButton = find.byKey(
        const ValueKey('save-password-button'),
      );
      await tester.ensureVisible(savePasswordButton);
      await tester.pumpAndSettle();
      await tester.tap(savePasswordButton);
      await tester.pumpAndSettle();

      expect(passwordChanged, isTrue);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('personal center adapts to a narrow dark mobile viewport', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(globalState.clearXboardSession);
    addTearDown(() => globalState.logoutXboard = null);
    globalState.xboardSession = _testSession();
    var logoutCalled = false;
    globalState.logoutXboard = () async => logoutCalled = true;

    await tester.pumpWidget(
      _TestApp(
        themeMode: ThemeMode.dark,
        mobileLayout: true,
        child: FengWoPersonalCenterView(
          ticketController: _ticketController(),
          authService: _testService(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('fengwo-personal-center-scroll')),
      findsOne,
    );
    expect(find.byKey(const ValueKey('account-profile-card')), findsOne);
    expect(find.byKey(const ValueKey('account-wallet-card')), findsOne);
    expect(find.byKey(const ValueKey('account-auto-renew-row')), findsOne);
    expect(find.byKey(const ValueKey('account-login-ip-card')), findsOne);
    expect(find.byKey(const ValueKey('reset-subscription-card')), findsNothing);
    final logoutButton = find.byKey(const ValueKey('account-logout-button'));
    expect(logoutButton, findsOneWidget);
    expect(find.byKey(const ValueKey('telegram-status-card')), findsNothing);
    expect(
      tester.getTopLeft(find.byKey(const ValueKey('account-profile-card'))).dy,
      lessThan(
        tester.getTopLeft(find.byKey(const ValueKey('account-wallet-card'))).dy,
      ),
    );
    await tester.ensureVisible(logoutButton);
    await tester.pumpAndSettle();
    await tester.tap(logoutButton);
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsOneWidget);
    await tester.tap(
      find.byKey(const ValueKey('account-logout-confirm-button')),
    );
    await tester.pumpAndSettle();

    expect(logoutCalled, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('blocked login IP can be unblocked after confirmation', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(globalState.clearXboardSession);
    globalState.xboardSession = _testSession();
    final loginIpState = _LoginIpTestState();

    await tester.pumpWidget(
      _TestApp(
        mobileLayout: true,
        child: FengWoPersonalCenterView(
          ticketController: _ticketController(),
          authService: _testService(loginIpState: loginIpState),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final unblockButton = find.byKey(
      const ValueKey('unblock-login-ip-18-8.8.8.8'),
    );
    await tester.ensureVisible(unblockButton);
    await tester.pumpAndSettle();
    await tester.tap(unblockButton);
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('confirm-unblock-login-ip-button')),
    );
    await tester.pumpAndSettle();

    expect(loginIpState.unblockedIp, '8.8.8.8');
    expect(loginIpState.secondIpBlocked, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('login IP card exposes retry after an API failure', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(760, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(globalState.clearXboardSession);
    globalState.xboardSession = _testSession();
    final loginIpState = _LoginIpTestState()..failFetch = true;

    await tester.pumpWidget(
      _TestApp(
        child: FengWoPersonalCenterView(
          ticketController: _ticketController(),
          authService: _testService(loginIpState: loginIpState),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('login-ip-error-state')), findsOne);
    expect(find.byKey(const ValueKey('retry-login-ip-list-button')), findsOne);
    expect(tester.takeException(), isNull);
  });

  testWidgets('login IP card renders an empty state', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(globalState.clearXboardSession);
    globalState.xboardSession = _testSession();
    final loginIpState = _LoginIpTestState()..empty = true;

    await tester.pumpWidget(
      _TestApp(
        mobileLayout: true,
        child: FengWoPersonalCenterView(
          ticketController: _ticketController(),
          authService: _testService(loginIpState: loginIpState),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('login-ip-empty-state')), findsOne);
    expect(tester.takeException(), isNull);
  });

  testWidgets('medium desktop width falls back to a readable single column', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(760, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(globalState.clearXboardSession);
    globalState.xboardSession = _testSession();

    await tester.pumpWidget(
      _TestApp(
        child: FengWoPersonalCenterView(
          ticketController: _ticketController(),
          authService: _testService(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final profile = tester.getTopLeft(
      find.byKey(const ValueKey('account-profile-card')),
    );
    final wallet = tester.getTopLeft(
      find.byKey(const ValueKey('account-wallet-card')),
    );
    final password = tester.getTopLeft(
      find.byKey(const ValueKey('account-password-card')),
    );
    final loginIps = tester.getTopLeft(
      find.byKey(const ValueKey('account-login-ip-card')),
    );
    expect((profile.dx - wallet.dx).abs(), lessThan(1));
    expect(wallet.dy, greaterThan(profile.dy));
    expect(password.dy, greaterThan(wallet.dy));
    expect(loginIps.dy, greaterThan(password.dy));
    expect(tester.takeException(), isNull);
  });

  testWidgets('login IP card scrolls records beyond the first five', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(760, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(globalState.clearXboardSession);
    globalState.xboardSession = _testSession();
    final loginIpState = _LoginIpTestState()..recordCount = 7;

    await tester.pumpWidget(
      _TestApp(
        child: FengWoPersonalCenterView(
          ticketController: _ticketController(),
          authService: _testService(loginIpState: loginIpState),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final viewport = find.byKey(const ValueKey('login-ip-scroll-viewport'));
    final list = find.byKey(const ValueKey('login-ip-scroll-list'));
    expect(viewport, findsOne);
    expect(tester.getSize(viewport).height, lessThanOrEqualTo(360));
    final scrollable = tester.state<ScrollableState>(
      find.descendant(of: list, matching: find.byType(Scrollable)),
    );
    expect(scrollable.position.maxScrollExtent, greaterThan(0));

    scrollable.position.jumpTo(500);
    await tester.pumpAndSettle();

    expect(scrollable.position.pixels, greaterThan(0));
    expect(tester.takeException(), isNull);
  });

  for (final scenario in [
    (name: 'desktop', size: const Size(760, 1000), mobileLayout: false),
    (name: 'mobile', size: const Size(390, 844), mobileLayout: true),
  ]) {
    testWidgets(
      '${scenario.name} account balance refreshes when personal center becomes active',
      (tester) async {
        tester.view.physicalSize = scenario.size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(globalState.clearXboardSession);
        globalState.xboardSession = _testSession();
        final pageActive = ValueNotifier(true);
        addTearDown(pageActive.dispose);
        var userInfoRequests = 0;

        await tester.pumpWidget(
          _TestApp(
            mobileLayout: scenario.mobileLayout,
            child: ValueListenableBuilder<bool>(
              valueListenable: pageActive,
              child: FengWoPersonalCenterView(
                ticketController: _ticketController(),
                authService: _testService(
                  userBalance: () => userInfoRequests == 0 ? 1250 : 8800,
                  onUserInfoFetched: () => userInfoRequests++,
                ),
              ),
              builder: (context, isActive, child) =>
                  PageActivityScope(isActive: isActive, child: child!),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(userInfoRequests, 1);
        expect(find.text('12.50'), findsOneWidget);

        pageActive.value = false;
        await tester.pumpAndSettle();
        expect(userInfoRequests, 1);

        pageActive.value = true;
        await tester.pumpAndSettle();

        expect(userInfoRequests, 2);
        expect(find.text('88.00'), findsOneWidget);
        expect(find.text('12.50'), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }
}

XboardAuthService _testService({
  VoidCallback? onPasswordChanged,
  _LoginIpTestState? loginIpState,
  int Function()? userBalance,
  VoidCallback? onUserInfoFetched,
}) {
  final state = loginIpState ?? _LoginIpTestState();
  return XboardAuthService(
    userInfoRequester: (endpoint, authData) async {
      final balance = userBalance?.call() ?? 1250;
      onUserInfoFetched?.call();
      return XboardLoginResponse(
        statusCode: 200,
        data: {
          'data': {
            'email': 'member@example.com',
            'balance': balance,
            'commission_balance': 0,
            'remind_expire': 1,
            'remind_traffic': 0,
            'telegram_id': null,
            'plan_id': 7,
            'expired_at': 1788192000,
          },
        },
      );
    },
    loginIpFetchRequester: (endpoint, authData) async {
      if (state.failFetch) {
        return const XboardLoginResponse(
          statusCode: 503,
          data: {'message': 'temporary unavailable'},
        );
      }
      final records = <Map<String, Object?>>[
        {
          'id': 17,
          'ip': '178.94.14.100',
          'ip_version': 4,
          'client_type': 'app',
          'client_name': 'App',
          'location': '乌克兰',
          'user_agent': 'FlClash/0.8.96 Windows 11',
          'first_login_at': 1788693000,
          'last_login_at': 1788699000,
          'login_count': 4,
          'is_blocked': state.firstIpBlocked,
          'reason': state.firstIpBlocked ? state.blockReason : null,
          'denied_count': 0,
        },
        {
          'id': 18,
          'ip': '8.8.8.8',
          'ip_version': 4,
          'client_type': 'web',
          'client_name': '网页端',
          'location': '美国',
          'user_agent': 'Chrome 140 macOS',
          'first_login_at': 1788600000,
          'last_login_at': 1788680000,
          'login_count': 3,
          'is_blocked': state.secondIpBlocked,
          'reason': state.secondIpBlocked ? '非本人登录' : null,
          'denied_count': 1,
        },
        for (var index = 2; index < state.recordCount; index++)
          {
            'id': 17 + index,
            'ip': '10.0.0.${index + 1}',
            'ip_version': 4,
            'client_type': 'app',
            'client_name': 'App',
            'location': '测试地区',
            'user_agent': 'FlClash test client',
            'first_login_at': 1788600000 + index,
            'last_login_at': 1788680000 + index,
            'login_count': 1,
            'is_blocked': false,
            'denied_count': 0,
          },
      ];
      return XboardLoginResponse(
        statusCode: 200,
        data: {
          'data': {
            'items': state.empty ? const <Map<String, Object?>>[] : records,
            'summary': {
              'record_count': state.empty ? 0 : records.length,
              'unique_ip_count': state.empty ? 0 : records.length,
              'blocked_ip_count':
                  [
                    state.firstIpBlocked,
                    state.secondIpBlocked,
                  ].where((value) => value).length *
                  (state.empty ? 0 : 1),
              'total_login_count': state.empty ? 0 : 5 + records.length,
            },
          },
        },
      );
    },
    loginIpBlockRequester: (endpoint, authData, ip, reason) async {
      state.blockedIp = ip;
      state.blockReason = reason;
      if (ip == '178.94.14.100') state.firstIpBlocked = true;
      return const XboardLoginResponse(statusCode: 200, data: {'data': true});
    },
    loginIpUnblockRequester: (endpoint, authData, ip) async {
      state.unblockedIp = ip;
      if (ip == '8.8.8.8') state.secondIpBlocked = false;
      return const XboardLoginResponse(statusCode: 200, data: {'data': true});
    },
    changePasswordRequester:
        (endpoint, authData, oldPassword, newPassword) async {
          expect(oldPassword, 'old-secret');
          expect(newPassword, 'new-secret');
          onPasswordChanged?.call();
          return const XboardLoginResponse(
            statusCode: 200,
            data: {'data': true},
          );
        },
  );
}

class _LoginIpTestState {
  bool firstIpBlocked = false;
  bool secondIpBlocked = true;
  bool failFetch = false;
  bool empty = false;
  int recordCount = 2;
  String? blockedIp;
  String? blockReason;
  String? unblockedIp;
}

XboardLoginResult _testSession({bool secureSubscription = false}) {
  final endpoint = Uri.parse('https://api.example.com');
  return XboardLoginResult(
    endpoint: endpoint,
    token: 'subscription-token',
    authData: 'Bearer account-token',
    isAdmin: false,
    secureSubscription: secureSubscription,
    subscription: XboardSubscriptionData(
      endpoint: endpoint,
      subscribeUrl: Uri.parse('https://api.example.com/subscribe'),
      uploadBytes: bytesPerGigabyte * 200,
      downloadBytes: bytesPerGigabyte * 300,
      transferEnableBytes: bytesPerGigabyte * 2000,
      planId: 7,
      email: 'member@example.com',
      expiredAtEpochSeconds: 1788192000,
      plan: const XboardPlanData(
        id: 7,
        name: '蜂窝旗舰套餐',
        transferEnableBytes: bytesPerGigabyte * 2000,
        rawData: {},
      ),
      rawData: const {},
    ),
  );
}

class _TestApp extends StatelessWidget {
  final Widget child;
  final ThemeMode themeMode;
  final bool mobileLayout;

  const _TestApp({
    required this.child,
    this.themeMode = ThemeMode.light,
    this.mobileLayout = false,
  });

  @override
  Widget build(BuildContext context) {
    return ProviderScope(
      overrides: [isMobileViewProvider.overrideWithValue(mobileLayout)],
      child: MaterialApp(
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
      ),
    );
  }
}

XboardTicketController _ticketController() {
  final controller = TicketFixture().controller();
  addTearDown(controller.dispose);
  return controller;
}

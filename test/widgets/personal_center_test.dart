import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/l10n/l10n.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/state.dart';
import 'package:fl_clash/views/account/fengwo_personal_center.dart';
import 'package:fl_clash/widgets/fengwo_account_avatar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'personal center renders account data and updates real controls',
    (tester) async {
      tester.view.physicalSize = const Size(760, 1000);
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
      expect(find.byKey(const ValueKey('reset-subscription-card')), findsOne);
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
        child: FengWoPersonalCenterView(authService: _testService()),
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
    expect(find.byKey(const ValueKey('reset-subscription-card')), findsOne);
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
          authService: _testService(loginIpState: loginIpState),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('login-ip-empty-state')), findsOne);
    expect(tester.takeException(), isNull);
  });
}

XboardAuthService _testService({
  VoidCallback? onPasswordChanged,
  _LoginIpTestState? loginIpState,
}) {
  final state = loginIpState ?? _LoginIpTestState();
  return XboardAuthService(
    userInfoRequester: (endpoint, authData) async {
      return const XboardLoginResponse(
        statusCode: 200,
        data: {
          'data': {
            'email': 'member@example.com',
            'balance': 1250,
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
      return XboardLoginResponse(
        statusCode: 200,
        data: {
          'data': {
            'items': state.empty
                ? const <Map<String, Object?>>[]
                : [
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
                  ],
            'summary': {
              'record_count': state.empty ? 0 : 2,
              'unique_ip_count': state.empty ? 0 : 2,
              'blocked_ip_count':
                  [
                    state.firstIpBlocked,
                    state.secondIpBlocked,
                  ].where((value) => value).length *
                  (state.empty ? 0 : 1),
              'total_login_count': state.empty ? 0 : 7,
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

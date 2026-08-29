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
      var preferencesUpdated = false;
      var passwordChanged = false;

      await tester.pumpWidget(
        _TestApp(
          child: FengWoPersonalCenterView(
            authService: _testService(
              onPreferencesUpdated: () => preferencesUpdated = true,
              onPasswordChanged: () => passwordChanged = true,
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
      expect(
        find.byKey(const ValueKey('account-notifications-card')),
        findsOne,
      );
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

      final reminderSwitch = find
          .descendant(
            of: find.byKey(const ValueKey('account-notifications-card')),
            matching: find.byType(Switch),
          )
          .first;
      await tester.tap(reminderSwitch);
      await tester.pumpAndSettle();
      expect(preferencesUpdated, isTrue);

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
      await tester.tap(find.byKey(const ValueKey('save-password-button')));
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
    globalState.xboardSession = _testSession();

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
    expect(find.byKey(const ValueKey('reset-subscription-card')), findsOne);
    expect(find.byKey(const ValueKey('telegram-status-card')), findsNothing);
    expect(
      tester.getTopLeft(find.byKey(const ValueKey('account-profile-card'))).dy,
      lessThan(
        tester.getTopLeft(find.byKey(const ValueKey('account-wallet-card'))).dy,
      ),
    );
    expect(tester.takeException(), isNull);
  });
}

XboardAuthService _testService({
  VoidCallback? onPreferencesUpdated,
  VoidCallback? onPasswordChanged,
}) {
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
    userUpdateRequester:
        (endpoint, authData, remindExpire, remindTraffic) async {
          expect(remindExpire, isFalse);
          expect(remindTraffic, isFalse);
          onPreferencesUpdated?.call();
          return const XboardLoginResponse(
            statusCode: 200,
            data: {'data': true},
          );
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

import 'package:fl_clash/common/xboard_auth.dart';
import 'package:fl_clash/l10n/l10n.dart';
import 'package:fl_clash/pages/register.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('desktop registration page follows the two-panel design', (
    tester,
  ) async {
    _useDesktopSize(tester);
    await tester.pumpWidget(_testApp());
    await tester.pumpAndSettle();

    expect(find.text('创建账号'), findsOneWidget);
    expect(find.byKey(const Key('register-brand-lockup')), findsOneWidget);
    expect(find.text('更快，更稳，更实惠'), findsOneWidget);
    expect(find.text('注册'), findsOneWidget);
    expect(find.byKey(const Key('register-back-button')), findsOneWidget);
    expect(find.byType(TextFormField), findsNWidgets(5));
    expect(find.byType(SingleChildScrollView), findsNothing);
    expect(find.text('@qq.com'), findsOneWidget);
    final verificationFieldRect = tester.getRect(
      find.byKey(const Key('register-verification-field')),
    );
    final sendButtonRect = tester.getRect(
      find.byKey(const Key('register-send-code-button')),
    );
    expect(
      verificationFieldRect.right - sendButtonRect.right,
      lessThanOrEqualTo(8),
    );
    expect(
      tester
          .getTopLeft(find.byKey(const Key('register-verification-field')))
          .dy,
      lessThan(
        tester.getTopLeft(find.byKey(const Key('register-password-field'))).dy,
      ),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('mobile registration page stays usable without overflow', (
    tester,
  ) async {
    _useMobileSize(tester);
    var wentBack = false;
    await tester.pumpWidget(_testApp(onBack: () => wentBack = true));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('register-page-title')), findsOneWidget);
    expect(
      find.byKey(const Key('register-mobile-back-button')),
      findsOneWidget,
    );
    expect(find.byType(SingleChildScrollView), findsNothing);
    await tester.tap(find.byKey(const Key('register-mobile-back-button')));
    await tester.pump();

    expect(wentBack, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('verification callback receives the complete selected email', (
    tester,
  ) async {
    _useDesktopSize(tester);
    String? sentEmail;
    await tester.pumpWidget(
      _testApp(onSendVerificationCode: (email) async => sentEmail = email),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextFormField).at(0), 'fengwo');
    await tester.tap(find.byKey(const Key('register-email-domain-dropdown')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('@gmail.com').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('register-send-code-button')));
    await tester.pump();

    expect(sentEmail, 'fengwo@gmail.com');
    expect(find.text('60s'), findsOneWidget);
    expect(find.text('验证码已发送，如果未收到请检查垃圾邮箱'), findsWidgets);
    final sendButton = tester.widget<FilledButton>(
      find.byKey(const Key('register-send-code-button')),
    );
    expect(sendButton.onPressed, isNull);

    await tester.pump(const Duration(seconds: 1));
    expect(find.text('59s'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('registration callback receives every form value', (
    tester,
  ) async {
    _useDesktopSize(tester);
    RegisterFormData? submitted;
    await tester.pumpWidget(
      _testApp(onRegister: (data) async => submitted = data),
    );
    await tester.pumpAndSettle();

    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(0), 'fengwo');
    await tester.enterText(fields.at(1), '123456');
    await tester.enterText(fields.at(2), 'secret123');
    await tester.enterText(fields.at(3), 'secret123');
    await tester.enterText(fields.at(4), 'invite-code');
    await tester.tap(find.byKey(const Key('register-submit-button')));
    await tester.pumpAndSettle();

    expect(submitted?.email, 'fengwo@qq.com');
    expect(submitted?.password, 'secret123');
    expect(submitted?.invitationCode, 'invite-code');
    expect(submitted?.emailCode, '123456');
  });

  testWidgets('server config hides email verification when disabled', (
    tester,
  ) async {
    _useDesktopSize(tester);
    await tester.pumpWidget(
      _testApp(config: _guestConfig(isEmailVerify: false)),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('register-verification-field')), findsNothing);
    expect(find.byKey(const Key('register-send-code-button')), findsNothing);
    expect(find.byType(TextFormField), findsNWidgets(4));
  });

  testWidgets('server config can require an invitation code', (tester) async {
    _useDesktopSize(tester);
    await tester.pumpWidget(
      _testApp(config: _guestConfig(isInviteForce: true)),
    );
    await tester.pumpAndSettle();

    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(0), 'fengwo');
    await tester.enterText(fields.at(1), '123456');
    await tester.enterText(fields.at(2), 'secret123');
    await tester.enterText(fields.at(3), 'secret123');
    await tester.tap(find.byKey(const Key('register-submit-button')));
    await tester.pump();

    expect(find.text('请输入邀请码'), findsOneWidget);
  });

  testWidgets('registration is blocked when the two passwords differ', (
    tester,
  ) async {
    _useDesktopSize(tester);
    var registerCalls = 0;
    await tester.pumpWidget(_testApp(onRegister: (_) async => registerCalls++));
    await tester.pumpAndSettle();

    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(0), 'fengwo');
    await tester.enterText(fields.at(1), '123456');
    await tester.enterText(fields.at(2), 'secret123');
    await tester.enterText(fields.at(3), 'different123');
    await tester.tap(find.byKey(const Key('register-submit-button')));
    await tester.pump();

    expect(registerCalls, 0);
    expect(find.text('两次输入的密码不一致'), findsOneWidget);
  });

  testWidgets('successful registration pops the form data to the login route', (
    tester,
  ) async {
    _useDesktopSize(tester);
    RegisterFormData? routeResult;
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh', 'CN'),
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.delegate.supportedLocales,
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              routeResult = await Navigator.of(context).push<RegisterFormData>(
                MaterialPageRoute(
                  builder: (_) => RegisterPage(
                    config: _guestConfig(),
                    onRegister: (_) async {},
                  ),
                ),
              );
            },
            child: const Text('打开注册页'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('打开注册页'));
    await tester.pumpAndSettle();
    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(0), 'fengwo');
    await tester.enterText(fields.at(1), '123456');
    await tester.enterText(fields.at(2), 'secret123');
    await tester.enterText(fields.at(3), 'secret123');
    await tester.tap(find.byKey(const Key('register-submit-button')));
    await tester.pumpAndSettle();

    expect(find.text('打开注册页'), findsOneWidget);
    expect(routeResult?.email, 'fengwo@qq.com');
    expect(routeResult?.password, 'secret123');
  });
}

Widget _testApp({
  XboardGuestConfig? config,
  VoidCallback? onBack,
  Future<void> Function(RegisterFormData data)? onRegister,
  Future<void> Function(String email)? onSendVerificationCode,
}) {
  return MaterialApp(
    locale: const Locale('zh', 'CN'),
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
    ],
    supportedLocales: AppLocalizations.delegate.supportedLocales,
    home: RegisterPage(
      config: config ?? _guestConfig(),
      onBack: onBack,
      onRegister: onRegister,
      onSendVerificationCode: onSendVerificationCode,
    ),
  );
}

XboardGuestConfig _guestConfig({
  bool isEmailVerify = true,
  bool isInviteForce = false,
}) {
  return XboardGuestConfig(
    endpoint: Uri.parse('https://api.example.com/api/v1/guest/comm/config'),
    isEmailVerify: isEmailVerify,
    isInviteForce: isInviteForce,
    emailWhitelistSuffix: const ['qq.com', 'gmail.com'],
    rawData: const {},
  );
}

void _useDesktopSize(WidgetTester tester) {
  tester.view.physicalSize = const Size(1200, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void _useMobileSize(WidgetTester tester) {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

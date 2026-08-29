import 'package:fl_clash/common/xboard_auth.dart';
import 'package:fl_clash/l10n/l10n.dart';
import 'package:fl_clash/pages/forgot_password.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('desktop forgot-password page follows the two-panel design', (
    tester,
  ) async {
    _useDesktopSize(tester);
    await tester.pumpWidget(_testApp());
    await tester.pumpAndSettle();

    expect(find.text('找回密码'), findsOneWidget);
    expect(
      find.byKey(const Key('forgot-password-brand-lockup')),
      findsOneWidget,
    );
    expect(find.text('更快，更稳，更实惠'), findsOneWidget);
    expect(
      find.byKey(const Key('forgot-password-back-button')),
      findsOneWidget,
    );
    expect(find.byType(TextFormField), findsNWidgets(3));
    expect(find.byType(SingleChildScrollView), findsNothing);
    expect(find.text('重置密码'), findsOneWidget);
    final verificationFieldRect = tester.getRect(
      find.byKey(const Key('forgot-password-verification-field')),
    );
    final sendButtonRect = tester.getRect(
      find.byKey(const Key('forgot-password-send-code-button')),
    );
    expect(
      verificationFieldRect.right - sendButtonRect.right,
      lessThanOrEqualTo(8),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('mobile forgot-password page stays usable without overflow', (
    tester,
  ) async {
    _useMobileSize(tester);
    var wentBack = false;
    await tester.pumpWidget(_testApp(onBack: () => wentBack = true));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('forgot-password-mobile-back-button')),
      findsOneWidget,
    );
    expect(find.byType(SingleChildScrollView), findsNothing);
    await tester.tap(
      find.byKey(const Key('forgot-password-mobile-back-button')),
    );
    await tester.pump();

    expect(wentBack, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('verification callback receives a trimmed complete email', (
    tester,
  ) async {
    _useDesktopSize(tester);
    String? sentEmail;
    await tester.pumpWidget(
      _testApp(onSendVerificationCode: (email) async => sentEmail = email),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byType(TextFormField).first,
      ' user@example.com ',
    );
    await tester.tap(find.byKey(const Key('forgot-password-send-code-button')));
    await tester.pump();

    expect(sentEmail, 'user@example.com');
    expect(find.text('60s'), findsOneWidget);
    expect(find.text('验证码已发送，如果未收到请检查垃圾邮箱'), findsWidgets);
    final sendButton = tester.widget<FilledButton>(
      find.byKey(const Key('forgot-password-send-code-button')),
    );
    expect(sendButton.onPressed, isNull);

    await tester.pump(const Duration(seconds: 1));
    expect(find.text('59s'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('valid reset form submits all XBoard values', (tester) async {
    _useDesktopSize(tester);
    ForgotPasswordFormData? submitted;
    await tester.pumpWidget(
      _testApp(onResetPassword: (data) async => submitted = data),
    );
    await tester.pumpAndSettle();

    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(0), ' user@example.com ');
    await tester.enterText(fields.at(1), ' 123456 ');
    await tester.enterText(fields.at(2), 'new-secret');
    await tester.tap(find.byKey(const Key('forgot-password-submit-button')));
    await tester.pumpAndSettle();

    expect(submitted?.email, 'user@example.com');
    expect(submitted?.emailCode, '123456');
    expect(submitted?.password, 'new-secret');
  });

  testWidgets('empty and invalid reset fields show validation errors', (
    tester,
  ) async {
    _useDesktopSize(tester);
    await tester.pumpWidget(_testApp(onResetPassword: (_) async {}));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextFormField).first, 'invalid-email');
    await tester.enterText(find.byType(TextFormField).last, 'short');
    await tester.tap(find.byKey(const Key('forgot-password-submit-button')));
    await tester.pump();

    expect(find.text('请输入有效的邮箱地址'), findsOneWidget);
    expect(find.text('请输入邮箱验证码'), findsWidgets);
    expect(find.text('密码至少需要8位'), findsOneWidget);
  });

  testWidgets('server reset error is shown to the user', (tester) async {
    _useDesktopSize(tester);
    await tester.pumpWidget(
      _testApp(
        onResetPassword: (_) async => throw const XboardAuthException(
          failure: XboardAuthFailure.passwordResetRejected,
          message: '邮箱验证码错误',
        ),
      ),
    );
    await tester.pumpAndSettle();

    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(0), 'user@example.com');
    await tester.enterText(fields.at(1), '123456');
    await tester.enterText(fields.at(2), 'new-secret');
    await tester.tap(find.byKey(const Key('forgot-password-submit-button')));
    await tester.pumpAndSettle();

    expect(find.text('邮箱验证码错误'), findsOneWidget);
  });
}

Widget _testApp({
  VoidCallback? onBack,
  Future<void> Function(String email)? onSendVerificationCode,
  Future<void> Function(ForgotPasswordFormData data)? onResetPassword,
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
    home: ForgotPasswordPage(
      onBack: onBack,
      onSendVerificationCode: onSendVerificationCode,
      onResetPassword: onResetPassword,
    ),
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

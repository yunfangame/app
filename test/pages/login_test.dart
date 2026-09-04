import 'dart:async';

import 'package:fl_clash/common/api_health.dart';
import 'package:fl_clash/common/xboard_auth.dart';
import 'package:fl_clash/pages/login.dart';
import 'package:fl_clash/l10n/l10n.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final mobile in [false, true]) {
    testWidgets('remembered login waits for a click, mobile=$mobile', (
      tester,
    ) async {
      mobile ? _useMobileSize(tester) : _useDesktopSize(tester);
      var restores = 0;
      var navigated = false;
      var saved = false;
      await tester.pumpWidget(
        _testApp(
          onLogin: () => navigated = true,
          prefill: const LoginFormPrefill(
            email: 'user@example.com',
            password: '',
          ),
          initialRememberMe: true,
          rememberedEmail: 'user@example.com',
          restoreRemembered: (email) async {
            expect(email, 'user@example.com');
            restores++;
            return _testXboardSession();
          },
          authenticate: (_, _) async =>
              throw StateError('password login unexpected'),
          onAuthenticated: (_, email, remember, automatic) async {
            expect(email, 'user@example.com');
            expect(remember, isTrue);
            expect(automatic, isFalse);
            saved = true;
          },
        ),
      );
      await tester.pumpAndSettle();
      expect(restores, 0);
      expect(find.text('已记住，可直接登录'), findsOneWidget);
      await tester.ensureVisible(find.byKey(const Key('login-submit-button')));
      await tester.tap(find.byKey(const Key('login-submit-button')));
      await tester.pumpAndSettle();
      expect(restores, 1);
      expect(saved, isTrue);
      expect(navigated, isTrue);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('another email cannot use remembered credentials', (
    tester,
  ) async {
    _useDesktopSize(tester);
    var restores = 0;
    await tester.pumpWidget(
      _testApp(
        onLogin: () => fail('must not log in'),
        initialRememberMe: true,
        prefill: const LoginFormPrefill(
          email: 'user@example.com',
          password: '',
        ),
        rememberedEmail: 'user@example.com',
        restoreRemembered: (_) async {
          restores++;
          return _testXboardSession();
        },
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('login-email-field')),
      'other@example.com',
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('login-submit-button')));
    await tester.pumpAndSettle();
    expect(restores, 0);
    expect(find.text('已记住，可直接登录'), findsNothing);
    expect(find.text('请输入密码'), findsWidgets);
  });

  testWidgets('typed password uses normal authentication', (tester) async {
    _useDesktopSize(tester);
    var passwords = 0;
    await tester.pumpWidget(
      _testApp(
        onLogin: () {},
        initialRememberMe: true,
        prefill: const LoginFormPrefill(
          email: 'user@example.com',
          password: '',
        ),
        rememberedEmail: 'user@example.com',
        restoreRemembered: (_) async => throw StateError('restore unexpected'),
        authenticate: (email, password) async {
          expect(password, 'new-password');
          passwords++;
          return _testXboardSession();
        },
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('login-password-field')),
      'new-password',
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('login-submit-button')));
    await tester.pumpAndSettle();
    expect(passwords, 1);
  });

  for (final expired in [false, true]) {
    testWidgets('remembered login handles failure, expired=$expired', (
      tester,
    ) async {
      _useDesktopSize(tester);
      var restores = 0;
      var navigated = false;
      await tester.pumpWidget(
        _testApp(
          onLogin: () => navigated = true,
          initialRememberMe: true,
          prefill: const LoginFormPrefill(
            email: 'user@example.com',
            password: '',
          ),
          rememberedEmail: 'user@example.com',
          restoreRemembered: (_) async {
            restores++;
            if (restores == 1) {
              throw XboardAuthException(
                failure: expired
                    ? XboardAuthFailure.authenticationRejected
                    : XboardAuthFailure.unavailable,
                message: 'temporary failure',
              );
            }
            return _testXboardSession();
          },
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('login-submit-button')));
      await tester.pumpAndSettle();
      expect(navigated, isFalse);
      expect(find.text('已记住，可直接登录'), expired ? findsNothing : findsOneWidget);
      await tester.tap(find.byKey(const Key('login-submit-button')));
      await tester.pumpAndSettle();
      expect(restores, expired ? 1 : 2);
      expect(navigated, !expired);
    });
  }

  testWidgets('disabling remember me prevents token reuse after rechecking', (
    tester,
  ) async {
    _useDesktopSize(tester);
    var cleared = false;
    await tester.pumpWidget(
      _testApp(
        onLogin: () => fail('must not log in'),
        initialRememberMe: true,
        prefill: const LoginFormPrefill(
          email: 'user@example.com',
          password: '',
        ),
        rememberedEmail: 'user@example.com',
        restoreRemembered: (_) async => throw StateError('restore unexpected'),
        onRememberMeDisabled: () => cleared = true,
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('记住我'));
    await tester.pump();
    await tester.tap(find.text('记住我'));
    await tester.pump();
    await tester.tap(find.byKey(const Key('login-submit-button')));
    await tester.pumpAndSettle();
    expect(cleared, isTrue);
    expect(find.text('已记住，可直接登录'), findsNothing);
  });

  testWidgets('pending restore ignores duplicate submits and disposal', (
    tester,
  ) async {
    _useDesktopSize(tester);
    final result = Completer<XboardLoginResult>();
    var restores = 0;
    await tester.pumpWidget(
      _testApp(
        onLogin: () => fail('disposed page must not navigate'),
        onAuthenticated: (_, _, _, _) async =>
            fail('disposed page must not persist'),
        initialRememberMe: true,
        prefill: const LoginFormPrefill(
          email: 'user@example.com',
          password: '',
        ),
        rememberedEmail: 'user@example.com',
        restoreRemembered: (_) {
          restores++;
          return result.future;
        },
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('login-submit-button')));
    await tester.tap(find.byKey(const Key('login-submit-button')));
    await tester.pump();
    expect(restores, 1);
    expect(
      tester
          .widget<EditableText>(
            find.descendant(
              of: find.byKey(const Key('login-email-field')),
              matching: find.byType(EditableText),
            ),
          )
          .readOnly,
      isTrue,
    );
    await tester.pumpWidget(const SizedBox());
    result.complete(_testXboardSession());
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('desktop login uses the shared FengWo brand lockup', (
    tester,
  ) async {
    _useDesktopSize(tester);
    await tester.pumpWidget(_testApp(onLogin: () {}));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('login-brand-lockup')), findsOneWidget);
    expect(find.byKey(const Key('fengwo-brand-logo')), findsOneWidget);
    expect(find.text('更快，更稳，更实惠'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('shows validation errors for an empty submission', (
    tester,
  ) async {
    _useDesktopSize(tester);
    await tester.pumpWidget(_testApp(onLogin: () {}));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('login-submit-button')));
    await tester.pump();

    expect(find.text('请输入邮箱'), findsWidgets);
    expect(find.text('请输入密码'), findsWidgets);
  });

  testWidgets('submits valid credentials', (tester) async {
    _useDesktopSize(tester);
    var submitted = false;
    await tester.pumpWidget(_testApp(onLogin: () => submitted = true));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('login-email-field')),
      'demo@example.com',
    );
    await tester.enterText(
      find.byKey(const Key('login-password-field')),
      'password',
    );
    await tester.tap(find.byKey(const Key('login-submit-button')));
    await tester.pump();

    expect(submitted, isTrue);
  });

  testWidgets('new registration credentials refill the existing login form', (
    tester,
  ) async {
    _useDesktopSize(tester);
    await tester.pumpWidget(_testApp(onLogin: () {}));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('login-email-field')),
      'old@example.com',
    );
    await tester.enterText(
      find.byKey(const Key('login-password-field')),
      'old-password',
    );

    await tester.pumpWidget(
      _testApp(
        onLogin: () {},
        prefill: const LoginFormPrefill(
          email: 'new@qq.com',
          password: 'new-password',
        ),
      ),
    );
    await tester.pump();

    final emailField = tester.widget<TextFormField>(
      find.byKey(const Key('login-email-field')),
    );
    final passwordField = tester.widget<TextFormField>(
      find.byKey(const Key('login-password-field')),
    );
    expect(emailField.controller?.text, 'new@qq.com');
    expect(passwordField.controller?.text, 'new-password');
  });

  testWidgets('authenticates valid credentials before opening the app', (
    tester,
  ) async {
    _useDesktopSize(tester);
    var submitted = false;
    String? capturedEmail;
    String? capturedPassword;
    await tester.pumpWidget(
      _testApp(
        onLogin: () => submitted = true,
        authenticate: (email, password) async {
          capturedEmail = email;
          capturedPassword = password;
          return _testXboardSession();
        },
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('login-email-field')),
      '  demo@example.com  ',
    );
    await tester.enterText(
      find.byKey(const Key('login-password-field')),
      'password',
    );
    await tester.tap(find.byKey(const Key('login-submit-button')));
    await tester.pumpAndSettle();

    expect(capturedEmail, 'demo@example.com');
    expect(capturedPassword, 'password');
    expect(submitted, isTrue);
  });

  testWidgets('shows an API rejection without opening the app', (tester) async {
    _useDesktopSize(tester);
    var submitted = false;
    await tester.pumpWidget(
      _testApp(
        onLogin: () => submitted = true,
        authenticate: (email, password) async {
          throw const XboardAuthException(
            failure: XboardAuthFailure.authenticationRejected,
            message: '邮箱或密码错误',
            statusCode: 400,
          );
        },
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('login-email-field')),
      'demo@example.com',
    );
    await tester.enterText(
      find.byKey(const Key('login-password-field')),
      'wrong',
    );
    await tester.tap(find.byKey(const Key('login-submit-button')));
    await tester.pumpAndSettle();

    expect(find.text('邮箱或密码错误'), findsOneWidget);
    expect(submitted, isFalse);
  });

  testWidgets('auto login also enables remember me', (tester) async {
    _useDesktopSize(tester);
    await tester.pumpWidget(_testApp(onLogin: () {}));
    await tester.pumpAndSettle();

    await tester.tap(find.text('自动登录'));
    await tester.pump();

    final checkboxes = tester.widgetList<Checkbox>(find.byType(Checkbox));
    expect(checkboxes.map((checkbox) => checkbox.value), everyElement(isTrue));
  });

  testWidgets('stored login options initialize both controls', (tester) async {
    _useDesktopSize(tester);
    await tester.pumpWidget(
      _testApp(onLogin: () {}, initialRememberMe: true, initialAutoLogin: true),
    );
    await tester.pumpAndSettle();

    final checkboxes = tester.widgetList<Checkbox>(find.byType(Checkbox));
    expect(checkboxes.map((checkbox) => checkbox.value), everyElement(isTrue));
  });

  testWidgets('disabling remember me also disables automatic login', (
    tester,
  ) async {
    _useDesktopSize(tester);
    var clearedRememberedSession = false;
    await tester.pumpWidget(
      _testApp(
        onLogin: () {},
        initialRememberMe: true,
        initialAutoLogin: true,
        onRememberMeDisabled: () => clearedRememberedSession = true,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('记住我'));
    await tester.pump();

    final checkboxes = tester.widgetList<Checkbox>(find.byType(Checkbox));
    expect(checkboxes.map((checkbox) => checkbox.value), everyElement(isFalse));
    expect(clearedRememberedSession, isTrue);
  });

  testWidgets('disabling automatic login reports the setting change', (
    tester,
  ) async {
    _useDesktopSize(tester);
    var disabledAutomaticLogin = false;
    await tester.pumpWidget(
      _testApp(
        onLogin: () {},
        initialRememberMe: true,
        initialAutoLogin: true,
        onAutomaticLoginDisabled: () => disabledAutomaticLogin = true,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('自动登录'));
    await tester.pump();

    final checkboxes = tester.widgetList<Checkbox>(find.byType(Checkbox));
    expect(checkboxes.first.value, isTrue);
    expect(checkboxes.last.value, isFalse);
    expect(disabledAutomaticLogin, isTrue);
  });

  testWidgets('successful authentication reports persistence choices', (
    tester,
  ) async {
    _useDesktopSize(tester);
    String? savedEmail;
    bool? savedRememberMe;
    bool? savedAutoLogin;
    await tester.pumpWidget(
      _testApp(
        onLogin: () {},
        authenticate: (_, _) async => _testXboardSession(),
        onAuthenticated: (session, email, rememberMe, autoLogin) async {
          savedEmail = email;
          savedRememberMe = rememberMe;
          savedAutoLogin = autoLogin;
        },
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('login-email-field')),
      'user@example.com',
    );
    await tester.enterText(
      find.byKey(const Key('login-password-field')),
      'password',
    );
    await tester.tap(find.text('自动登录'));
    await tester.tap(find.byKey(const Key('login-submit-button')));
    await tester.pumpAndSettle();

    expect(savedEmail, 'user@example.com');
    expect(savedRememberMe, isTrue);
    expect(savedAutoLogin, isTrue);
  });

  testWidgets('language button uses the provided tools callback', (
    tester,
  ) async {
    _useDesktopSize(tester);
    var opened = false;
    await tester.pumpWidget(
      _testApp(onLogin: () {}, onLanguagePressed: (_) => opened = true),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('语言'));
    await tester.pump();

    expect(opened, isTrue);
  });

  testWidgets('fresh installs show the smaller default-language icon', (
    tester,
  ) async {
    _useDesktopSize(tester);
    await tester.pumpWidget(_testApp(onLogin: () {}));
    await tester.pumpAndSettle();

    final button = find.byKey(const Key('login-language-button'));
    final icon = tester.widget<Icon>(
      find.descendant(
        of: button,
        matching: find.byIcon(Icons.translate_rounded),
      ),
    );
    expect(icon.size, 24);
    expect(tester.getSize(button), const Size(58, 58));
    expect(
      find.descendant(of: button, matching: find.text('默认')),
      findsNothing,
    );
  });

  testWidgets('theme button uses the provided tools callback', (tester) async {
    _useDesktopSize(tester);
    var opened = false;
    await tester.pumpWidget(
      _testApp(onLogin: () {}, onThemePressed: (_) => opened = true),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('主题'));
    await tester.pump();

    expect(opened, isTrue);
  });

  testWidgets('support button uses the provided customer-service callback', (
    tester,
  ) async {
    _useDesktopSize(tester);
    var opened = false;
    await tester.pumpWidget(
      _testApp(onLogin: () {}, onSupportPressed: (_) => opened = true),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('在线客服'));
    await tester.pump();

    expect(opened, isTrue);
  });

  testWidgets('register account button uses the provided navigation callback', (
    tester,
  ) async {
    _useDesktopSize(tester);
    var opened = false;
    await tester.pumpWidget(
      _testApp(onLogin: () {}, onRegisterPressed: () => opened = true),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('注册账号'));
    await tester.pump();

    expect(opened, isTrue);
  });

  testWidgets('forgot-password button uses the provided navigation callback', (
    tester,
  ) async {
    _useDesktopSize(tester);
    var opened = false;
    await tester.pumpWidget(
      _testApp(onLogin: () {}, onForgotPasswordPressed: () => opened = true),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('忘记密码'));
    await tester.pump();

    expect(opened, isTrue);
  });

  testWidgets('API status control sits at the top right without refresh', (
    tester,
  ) async {
    _useDesktopSize(tester);
    await tester.pumpWidget(_testApp(onLogin: () {}));
    await tester.pumpAndSettle();

    final support = find.byTooltip('在线客服');
    final status = find.byKey(const Key('api-health-status-button'));
    expect(status, findsOneWidget);
    expect(find.byKey(const Key('api-health-refresh-button')), findsNothing);
    expect(tester.getCenter(status).dx, greaterThan(1000));
    expect(tester.getCenter(status).dy, lessThan(100));
    expect(
      tester.getCenter(status).dx,
      greaterThan(tester.getCenter(support).dx),
    );
  });

  testWidgets('mobile layout keeps all tools visible without overflow', (
    tester,
  ) async {
    _useMobileSize(tester);
    await tester.pumpWidget(_testApp(onLogin: () {}));
    await tester.pumpAndSettle();

    expect(find.byTooltip('语言'), findsOneWidget);
    expect(find.byTooltip('主题'), findsOneWidget);
    expect(find.byTooltip('在线客服'), findsOneWidget);
    expect(find.byKey(const Key('api-health-status-button')), findsOneWidget);
    expect(find.byKey(const Key('api-health-refresh-button')), findsNothing);
    expect(find.text('蜂窝加速器'), findsOneWidget);
    final title = tester.widget<Text>(
      find.byKey(const Key('login-page-title')),
    );
    expect(title.data, '蜂窝加速器');

    await tester.tap(find.byKey(const Key('login-submit-button')));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('offline entry is enabled only when valid cache exists', (
    tester,
  ) async {
    _useDesktopSize(tester);
    var opened = false;
    await tester.pumpWidget(
      _testApp(
        onLogin: () {},
        offlineAvailable: true,
        onOfflinePressed: () async => opened = true,
      ),
    );
    await tester.pumpAndSettle();

    final button = find.byKey(const Key('login-offline-button'));
    expect(button, findsOneWidget);
    expect(find.text('使用本地缓存进入'), findsOneWidget);
    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(opened, isTrue);
  });

  testWidgets('shows the packaged application version in the copyright', (
    tester,
  ) async {
    _useDesktopSize(tester);
    await tester.pumpWidget(_testApp(onLogin: () {}, appVersion: 'V2.2'));
    await tester.pumpAndSettle();

    expect(find.text('© 2026 蜂窝加速器 V2.2'), findsOneWidget);
  });
}

Widget _testApp({
  required VoidCallback onLogin,
  ValueChanged<BuildContext>? onLanguagePressed,
  ValueChanged<BuildContext>? onThemePressed,
  ValueChanged<BuildContext>? onSupportPressed,
  String appVersion = '0.8.96',
  String? configuredLocale,
  ApiHealthService? apiHealthService,
  Future<XboardLoginResult> Function(String email, String password)?
  authenticate,
  VoidCallback? onRegisterPressed,
  VoidCallback? onForgotPasswordPressed,
  LoginFormPrefill? prefill,
  LoginAuthenticatedCallback? onAuthenticated,
  bool initialRememberMe = false,
  bool initialAutoLogin = false,
  String? rememberedEmail,
  Future<XboardLoginResult> Function(String email)? restoreRemembered,
  VoidCallback? onRememberMeDisabled,
  VoidCallback? onAutomaticLoginDisabled,
  bool offlineAvailable = false,
  Future<void> Function()? onOfflinePressed,
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
    home: LoginPage(
      onLogin: onLogin,
      onLanguagePressed: onLanguagePressed ?? (_) {},
      onThemePressed: onThemePressed ?? (_) {},
      onSupportPressed: onSupportPressed ?? (_) {},
      appVersion: appVersion,
      configuredLocale: configuredLocale,
      apiHealthService: apiHealthService ?? ApiHealthService(configUrl: ''),
      authenticate: authenticate,
      onRegisterPressed: onRegisterPressed,
      onForgotPasswordPressed: onForgotPasswordPressed,
      prefill: prefill,
      onAuthenticated: onAuthenticated,
      initialRememberMe: initialRememberMe,
      initialAutoLogin: initialAutoLogin,
      rememberedEmail: rememberedEmail,
      restoreRemembered: restoreRemembered,
      onRememberMeDisabled: onRememberMeDisabled,
      onAutomaticLoginDisabled: onAutomaticLoginDisabled,
      offlineAvailable: offlineAvailable,
      onOfflinePressed: onOfflinePressed,
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

XboardLoginResult _testXboardSession() {
  final endpoint = Uri.parse('https://api.example.com');
  return XboardLoginResult(
    endpoint: endpoint,
    token: 'subscription-token',
    authData: 'Bearer login-token',
    isAdmin: false,
    subscription: XboardSubscriptionData(
      endpoint: endpoint,
      subscribeUrl: Uri.parse('https://subscribe.example.com/client/token'),
      uploadBytes: 0,
      downloadBytes: 0,
      transferEnableBytes: bytesPerGigabyte,
      rawData: const {},
    ),
  );
}

import 'package:fl_clash/common/api_health.dart';
import 'package:fl_clash/common/local_secret_store.dart';
import 'package:fl_clash/common/xboard_auth.dart';
import 'package:fl_clash/common/xboard_login_persistence.dart';
import 'package:fl_clash/common/xboard_session_storage.dart';
import 'package:fl_clash/l10n/l10n.dart';
import 'package:fl_clash/pages/login.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  for (final mobile in [false, true]) {
    testWidgets(
      'login logout and reconstructed login retain account, mobile=$mobile',
      (tester) async {
        _size(tester, mobile);
        final secrets = _SecretBoundary();
        final persistence = _persistence(secrets);
        await persistence.load();
        final harness = GlobalKey<_LoginFlowState>();
        try {
          await tester.pumpWidget(
            _app(_LoginFlow(key: harness, persistence: persistence)),
          );
          await tester.pumpAndSettle();
          await _enterCredentials(tester);
          await _tap(tester, find.text('记住我'));
          await _tap(tester, find.text('自动登录'));
          await _tap(tester, find.byKey(const Key('login-submit-button')));
          expect(find.byKey(const Key('flow-home')), findsOneWidget);
          expect(harness.currentState!.lastPersisted, isTrue);

          await _tap(tester, find.byKey(const Key('flow-logout')));
          _expectForm(tester, remembered: true);
          expect(_checkbox(tester, '自动登录').value, isFalse);
          expect(persistence.state.canRestore, isFalse);

          await tester.pumpWidget(const SizedBox());
          final restarted = _persistence(secrets);
          await restarted.load();
          await tester.pumpWidget(_app(_LoginFlow(persistence: restarted)));
          await tester.pumpAndSettle();
          _expectForm(tester, remembered: true);
          expect(_checkbox(tester, '自动登录').value, isFalse);
          expect(find.byKey(const Key('flow-home')), findsNothing);
          expect(tester.takeException(), isNull);
        } finally {
          await tester.pumpWidget(const SizedBox());
        }
      },
    );

    testWidgets('unchecking remember clears rebuilt form, mobile=$mobile', (
      tester,
    ) async {
      _size(tester, mobile);
      final secrets = _SecretBoundary();
      final persistence = _persistence(secrets);
      await _save(persistence);
      await persistence.prepareForLogout();
      try {
        await tester.pumpWidget(_app(_LoginFlow(persistence: persistence)));
        await tester.pumpAndSettle();
        _expectForm(tester, remembered: true);
        await _tap(tester, find.text('记住我'));
        expect(persistence.state.rememberMe, isFalse);
        expect(persistence.state.email, isNull);
        expect(persistence.state.password, isNull);

        await tester.pumpWidget(const SizedBox());
        final restarted = _persistence(secrets);
        await restarted.load();
        await tester.pumpWidget(_app(_LoginFlow(persistence: restarted)));
        await tester.pumpAndSettle();
        _expectForm(tester, remembered: false);
        expect(_checkbox(tester, '自动登录').value, isFalse);
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox());
      }
    });

    testWidgets(
      'account switch clears old prefilled password, mobile=$mobile',
      (tester) async {
        _size(tester, mobile);
        final persistence = _persistence(_SecretBoundary());
        await _save(persistence);
        await persistence.prepareForLogout();
        try {
          await tester.pumpWidget(_app(_LoginFlow(persistence: persistence)));
          await tester.pumpAndSettle();
          _expectForm(tester, remembered: true);
          await tester.enterText(
            find.byKey(const Key('login-email-field')),
            'other@example.com',
          );
          await tester.pump();
          expect(_field(tester, 'login-password-field').text, isEmpty);
          await tester.enterText(
            find.byKey(const Key('login-password-field')),
            'other-password',
          );
          await _tap(tester, find.byKey(const Key('login-submit-button')));
          await _tap(tester, find.byKey(const Key('flow-logout')));
          expect(_field(tester, 'login-email-field').text, 'other@example.com');
          expect(_field(tester, 'login-password-field').text, 'other-password');
          expect(_checkbox(tester, '记住我').value, isTrue);
          expect(tester.takeException(), isNull);
        } finally {
          await tester.pumpWidget(const SizedBox());
        }
      },
    );

    testWidgets('write failure retains current-session form, mobile=$mobile', (
      tester,
    ) async {
      _size(tester, mobile);
      final secrets = _SecretBoundary()..failWrites = true;
      final persistence = _persistence(secrets);
      await persistence.load();
      final harness = GlobalKey<_LoginFlowState>();
      try {
        await tester.pumpWidget(
          _app(_LoginFlow(key: harness, persistence: persistence)),
        );
        await tester.pumpAndSettle();
        await _enterCredentials(tester);
        await _tap(tester, find.text('记住我'));
        await _tap(tester, find.byKey(const Key('login-submit-button')));
        expect(harness.currentState!.lastPersisted, isFalse);
        expect(persistence.state.hasStorageError, isTrue);
        await _tap(tester, find.byKey(const Key('flow-logout')));
        _expectForm(tester, remembered: true);
        expect(_checkbox(tester, '自动登录').value, isFalse);
        expect(persistence.state.hasStorageError, isTrue);
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox());
      }
    });

    testWidgets('external prefill synchronizes both options, mobile=$mobile', (
      tester,
    ) async {
      _size(tester, mobile);
      try {
        await tester.pumpWidget(_app(_prefilledPage()));
        await tester.pumpAndSettle();
        expect(_checkbox(tester, '记住我').value, isFalse);
        await tester.pumpWidget(
          _app(
            _prefilledPage(
              prefill: const LoginFormPrefill(
                email: 'user@example.com',
                password: 'secret-password',
              ),
              rememberMe: true,
              autoLogin: true,
            ),
          ),
        );
        await tester.pumpAndSettle();
        _expectForm(tester, remembered: true);
        expect(_checkbox(tester, '自动登录').value, isTrue);
        await tester.pumpWidget(
          _app(
            _prefilledPage(
              prefill: const LoginFormPrefill(email: '', password: ''),
            ),
          ),
        );
        await tester.pumpAndSettle();
        _expectForm(tester, remembered: false);
        expect(_checkbox(tester, '自动登录').value, isFalse);
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox());
      }
    });
  }
}

XboardLoginPersistence _persistence(_SecretBoundary secrets) =>
    XboardLoginPersistence(storage: XboardSessionStorage(secretStore: secrets));

Future<bool> _save(XboardLoginPersistence persistence) =>
    persistence.saveAuthenticated(
      session: _session(),
      email: 'user@example.com',
      password: 'secret-password',
      rememberMe: true,
      autoLogin: false,
    );

class _LoginFlow extends StatefulWidget {
  const _LoginFlow({super.key, required this.persistence});

  final XboardLoginPersistence persistence;

  @override
  State<_LoginFlow> createState() => _LoginFlowState();
}

class _LoginFlowState extends State<_LoginFlow> {
  bool loggedIn = false;
  bool? lastPersisted;

  @override
  Widget build(BuildContext context) {
    if (loggedIn) {
      return Scaffold(
        key: const Key('flow-home'),
        body: TextButton(
          key: const Key('flow-logout'),
          onPressed: () async {
            await widget.persistence.prepareForLogout();
            if (mounted) setState(() => loggedIn = false);
          },
          child: const Text('退出登录'),
        ),
      );
    }
    final stored = widget.persistence.state;
    return LoginPage(
      onLogin: () => setState(() => loggedIn = true),
      onLanguagePressed: (_) {},
      onThemePressed: (_) {},
      onSupportPressed: (_) {},
      appVersion: '0.8.99-test',
      apiHealthService: ApiHealthService(configUrl: ''),
      prefill: LoginFormPrefill(
        email: stored.email ?? '',
        password: stored.password ?? '',
      ),
      initialRememberMe: stored.rememberMe,
      initialAutoLogin: stored.autoLogin,
      authenticate: (_, _) async => _session(),
      onAuthenticated: (session, email, password, remember, automatic) async {
        lastPersisted = await widget.persistence.saveAuthenticated(
          session: session,
          email: email,
          password: password,
          rememberMe: remember,
          autoLogin: automatic,
        );
      },
      onRememberMeDisabled: () async {
        await widget.persistence.forget();
      },
      onAutomaticLoginDisabled: () async {
        await widget.persistence.disableAutoLogin();
      },
    );
  }
}

LoginPage _prefilledPage({
  LoginFormPrefill? prefill,
  bool rememberMe = false,
  bool autoLogin = false,
}) => LoginPage(
  onLogin: () {},
  onLanguagePressed: (_) {},
  onThemePressed: (_) {},
  onSupportPressed: (_) {},
  appVersion: '0.8.99-test',
  apiHealthService: ApiHealthService(configUrl: ''),
  prefill: prefill,
  initialRememberMe: rememberMe,
  initialAutoLogin: autoLogin,
);

Widget _app(Widget home) => MaterialApp(
  locale: const Locale('zh', 'CN'),
  localizationsDelegates: const [
    AppLocalizations.delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
  ],
  supportedLocales: AppLocalizations.delegate.supportedLocales,
  home: home,
);

void _size(WidgetTester tester, bool mobile) {
  tester.view.physicalSize = mobile
      ? const Size(390, 844)
      : const Size(1200, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<void> _enterCredentials(WidgetTester tester) async {
  await tester.enterText(
    find.byKey(const Key('login-email-field')),
    'user@example.com',
  );
  await tester.enterText(
    find.byKey(const Key('login-password-field')),
    'secret-password',
  );
  await tester.pump();
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

TextEditingController _field(WidgetTester tester, String key) => tester
    .widget<EditableText>(
      find.descendant(
        of: find.byKey(Key(key)),
        matching: find.byType(EditableText),
      ),
    )
    .controller;

Checkbox _checkbox(WidgetTester tester, String label) =>
    tester.widget<Checkbox>(
      find.descendant(
        of: find
            .ancestor(of: find.text(label), matching: find.byType(Row))
            .first,
        matching: find.byType(Checkbox),
      ),
    );

void _expectForm(WidgetTester tester, {required bool remembered}) {
  expect(
    _field(tester, 'login-email-field').text,
    remembered ? 'user@example.com' : '',
  );
  expect(
    _field(tester, 'login-password-field').text,
    remembered ? 'secret-password' : '',
  );
  expect(_checkbox(tester, '记住我').value, remembered);
}

XboardLoginResult _session() {
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

class _SecretBoundary implements SecretStringStore {
  final values = <String, String>{};
  bool failWrites = false;

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async {
    if (failWrites) throw PlatformException(code: 'write_unavailable');
    values[key] = value;
  }

  @override
  Future<void> delete(String key) async => values.remove(key);
}

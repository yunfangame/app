import 'dart:async';

import 'package:fl_clash/common/api_health.dart';
import 'package:fl_clash/common/application_bootstrap.dart';
import 'package:fl_clash/common/xboard_auth.dart';
import 'package:fl_clash/l10n/l10n.dart';
import 'package:fl_clash/pages/login.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final mobile in [false, true]) {
    for (final action in [
      'input',
      'cleared',
      'remember-on',
      'remember-off',
      'auto-on',
      'auto-off',
      'invalid-submit',
    ]) {
      testWidgets(
        'same-frame $action survives completed background restore, mobile=$mobile',
        (tester) async {
          _size(tester, mobile);
          final controller = AuthenticationBootstrapController();
          addTearDown(controller.dispose);
          final revision = controller.begin(
            timeout: const Duration(seconds: 60),
            onTimeout: (_) => fail('authentication already completed'),
          );
          final initiallyRemembered =
              action == 'cleared' || action.endsWith('-off');
          final initiallyAutomatic = action == 'auto-off';
          final prefill = ValueNotifier<LoginFormPrefill?>(
            action == 'cleared' ? _rememberedPrefill : null,
          );
          addTearDown(prefill.dispose);
          var interactions = 0;
          try {
            await tester.pumpWidget(
              _app(
                onUserInteraction: () {},
                home: ValueListenableBuilder<LoginFormPrefill?>(
                  valueListenable: prefill,
                  builder: (_, value, _) {
                    final background = value?.preserveUserInput == true;
                    return LoginPage(
                      onLogin: () => fail('invalid form cannot log in'),
                      onLanguagePressed: (_) {},
                      onThemePressed: (_) {},
                      onSupportPressed: (_) {},
                      appVersion: '1.0.2-test',
                      apiHealthService: ApiHealthService(configUrl: ''),
                      prefill: value,
                      initialRememberMe: background
                          ? !initiallyRemembered
                          : initiallyRemembered,
                      initialAutoLogin: background
                          ? !action.endsWith('-on')
                          : initiallyAutomatic,
                      onUserInteraction: () {
                        interactions++;
                        if (controller.hasPendingWork) controller.cancel();
                      },
                    );
                  },
                ),
              ),
            );
            await tester.pumpAndSettle();
            expect(interactions, 0);
            expect(controller.complete(revision), isTrue);
            prefill.value = _backgroundPrefill;

            switch (action) {
              case 'input':
                _field(tester, 'login-email-field').text = 'new@example.com';
                _field(tester, 'login-password-field').text = 'new-password';
              case 'cleared':
                _field(tester, 'login-email-field').clear();
                _field(tester, 'login-password-field').clear();
              case 'remember-on':
                _checkbox(tester, '记住我').onChanged!(true);
              case 'remember-off':
                _checkbox(tester, '记住我').onChanged!(false);
              case 'auto-on':
                _checkbox(tester, '自动登录').onChanged!(true);
              case 'auto-off':
                _checkbox(tester, '自动登录').onChanged!(false);
              case 'invalid-submit':
                tester
                    .widget<FilledButton>(
                      find.byKey(const Key('login-submit-button')),
                    )
                    .onPressed!();
            }
            expect(interactions, greaterThan(0));
            expect(controller.hasPendingWork, isFalse);
            await tester.pumpAndSettle();
            expect(
              _field(tester, 'login-email-field').text,
              action == 'input' ? 'new@example.com' : '',
            );
            expect(
              _field(tester, 'login-password-field').text,
              action == 'input' ? 'new-password' : '',
            );
            expect(
              _checkbox(tester, '记住我').value,
              const {
                'cleared',
                'remember-on',
                'auto-on',
                'auto-off',
              }.contains(action),
            );
            expect(_checkbox(tester, '自动登录').value, action == 'auto-on');
            expect(tester.takeException(), isNull);
          } finally {
            await tester.pumpWidget(const SizedBox());
          }
        },
      );
    }

    testWidgets(
      'background prefill applies without user intent, mobile=$mobile',
      (tester) async {
        _size(tester, mobile);
        var interactions = 0;
        try {
          await tester.pumpWidget(
            _app(
              onUserInteraction: () => interactions++,
              prefill: _backgroundPrefill,
              initialRememberMe: true,
              initialAutoLogin: true,
            ),
          );
          await tester.pumpAndSettle();
          expect(
            _field(tester, 'login-email-field').text,
            'stored@example.com',
          );
          expect(
            _field(tester, 'login-password-field').text,
            'stored-password',
          );
          expect(_checkbox(tester, '自动登录').value, isTrue);

          await tester.pumpWidget(
            _app(
              onUserInteraction: () => interactions++,
              prefill: const LoginFormPrefill(
                email: 'later@example.com',
                password: 'later-password',
                preserveUserInput: true,
              ),
              initialRememberMe: true,
            ),
          );
          await tester.pumpAndSettle();
          expect(_field(tester, 'login-email-field').text, 'later@example.com');
          expect(_field(tester, 'login-password-field').text, 'later-password');
          expect(_checkbox(tester, '记住我').value, isTrue);
          expect(_checkbox(tester, '自动登录').value, isFalse);
          expect(interactions, 0);
        } finally {
          await tester.pumpWidget(const SizedBox());
        }
      },
    );

    testWidgets(
      'empty background prefill is ignored but explicit prefill applies, mobile=$mobile',
      (tester) async {
        _size(tester, mobile);
        try {
          await tester.pumpWidget(_app(onUserInteraction: () {}));
          await tester.pumpAndSettle();
          await tester.enterText(
            find.byKey(const Key('login-email-field')),
            'typed@example.com',
          );
          await tester.enterText(
            find.byKey(const Key('login-password-field')),
            'typed-password',
          );
          await tester.pumpWidget(
            _app(
              onUserInteraction: () {},
              prefill: const LoginFormPrefill(
                email: '',
                password: '',
                preserveUserInput: true,
              ),
              initialRememberMe: true,
              initialAutoLogin: true,
            ),
          );
          await tester.pumpAndSettle();
          expect(_field(tester, 'login-email-field').text, 'typed@example.com');
          expect(_field(tester, 'login-password-field').text, 'typed-password');
          expect(_checkbox(tester, '记住我').value, isFalse);
          expect(_checkbox(tester, '自动登录').value, isFalse);

          await tester.pumpWidget(
            _app(
              onUserInteraction: () {},
              prefill: _rememberedPrefill,
              initialRememberMe: true,
            ),
          );
          await tester.pumpAndSettle();
          expect(_field(tester, 'login-email-field').text, 'user@example.com');
          expect(_field(tester, 'login-password-field').text, 'test-password');
          expect(_checkbox(tester, '记住我').value, isTrue);
          expect(_checkbox(tester, '自动登录').value, isFalse);
          expect(tester.takeException(), isNull);
        } finally {
          await tester.pumpWidget(const SizedBox());
        }
      },
    );

    testWidgets('prefill is not user intent, mobile=$mobile', (tester) async {
      _size(tester, mobile);
      var interactions = 0;
      try {
        await tester.pumpWidget(_app(onUserInteraction: () => interactions++));
        await tester.pumpAndSettle();
        expect(interactions, 0);

        await tester.pumpWidget(
          _app(
            onUserInteraction: () => interactions++,
            prefill: _rememberedPrefill,
            initialRememberMe: true,
            initialAutoLogin: true,
          ),
        );
        await tester.pumpAndSettle();
        expect(interactions, 0);
        expect(_field(tester, 'login-email-field').text, 'user@example.com');
        expect(_field(tester, 'login-password-field').text, 'test-password');

        await tester.enterText(
          find.byKey(const Key('login-email-field')),
          'other@example.com',
        );
        await tester.pump();
        expect(interactions, greaterThan(0));
        expect(_field(tester, 'login-password-field').text, isEmpty);

        interactions = 0;
        await tester.enterText(
          find.byKey(const Key('login-password-field')),
          'another-password',
        );
        await tester.pump();
        expect(interactions, greaterThan(0));

        interactions = 0;
        await tester.enterText(
          find.byKey(const Key('login-password-field')),
          '',
        );
        await tester.pump();
        expect(interactions, greaterThan(0));
      } finally {
        await tester.pumpWidget(const SizedBox());
      }
    });

    for (final valid in [false, true]) {
      testWidgets(
        'submission reports intent first, valid=$valid mobile=$mobile',
        (tester) async {
          _size(tester, mobile);
          final calls = <String>[];
          try {
            await tester.pumpWidget(
              _app(
                onUserInteraction: () => calls.add('interaction'),
                onLogin: () => calls.add('login'),
                prefill: valid ? _rememberedPrefill : null,
              ),
            );
            await tester.pumpAndSettle();
            expect(calls, isEmpty);

            await _tap(tester, find.byKey(const Key('login-submit-button')));
            expect(calls.first, 'interaction');
            expect(calls.contains('login'), valid);
            if (valid) expect(calls.last, 'login');
            expect(tester.takeException(), isNull);
          } finally {
            await tester.pumpWidget(const SizedBox());
          }
        },
      );
    }

    for (final option in ['记住我', '自动登录']) {
      testWidgets('$option reports enabling and disabling, mobile=$mobile', (
        tester,
      ) async {
        _size(tester, mobile);
        final calls = <String>[];
        try {
          await tester.pumpWidget(
            _app(
              onUserInteraction: () => calls.add('interaction'),
              onRememberMeDisabled: () => calls.add('remember-disabled'),
              onAutomaticLoginDisabled: () => calls.add('automatic-disabled'),
            ),
          );
          await tester.pumpAndSettle();
          await _tap(tester, find.text(option));
          expect(calls, ['interaction']);
          expect(_checkbox(tester, option).value, isTrue);

          calls.clear();
          await _tap(tester, find.text(option));
          expect(calls, [
            'interaction',
            option == '记住我' ? 'remember-disabled' : 'automatic-disabled',
          ]);
          expect(_checkbox(tester, option).value, isFalse);
        } finally {
          await tester.pumpWidget(const SizedBox());
        }
      });
    }

    testWidgets(
      'offline entry reports intent before awaiting, mobile=$mobile',
      (tester) async {
        _size(tester, mobile);
        final pending = Completer<void>();
        final calls = <String>[];
        try {
          await tester.pumpWidget(
            _app(
              onUserInteraction: () => calls.add('interaction'),
              offlineAvailable: true,
              onOfflinePressed: () {
                calls.add('offline');
                return pending.future;
              },
            ),
          );
          await tester.pumpAndSettle();
          final button = find.byKey(const Key('login-offline-button'));
          await tester.ensureVisible(button);
          await tester.tap(button);
          await tester.pump();
          expect(calls, ['interaction', 'offline']);
          expect(tester.widget<OutlinedButton>(button).onPressed, isNull);
        } finally {
          pending.complete();
          await tester.pump();
          await tester.pumpWidget(const SizedBox());
        }
      },
    );

    for (final action in [
      'register',
      'forgot',
      'language',
      'theme',
      'support',
    ]) {
      testWidgets('$action reports intent before opening, mobile=$mobile', (
        tester,
      ) async {
        _size(tester, mobile);
        final calls = <String>[];
        try {
          await tester.pumpWidget(
            _app(
              onUserInteraction: () => calls.add('interaction'),
              onRegisterPressed: () => calls.add('register'),
              onForgotPasswordPressed: () => calls.add('forgot'),
              onLanguagePressed: (_) => calls.add('language'),
              onThemePressed: (_) => calls.add('theme'),
              onSupportPressed: (_) => calls.add('support'),
            ),
          );
          await tester.pumpAndSettle();
          await _tap(tester, switch (action) {
            'register' => find.text('注册账号'),
            'forgot' => find.text('忘记密码'),
            'language' => find.byTooltip('语言'),
            'theme' => find.byTooltip('主题'),
            _ => find.byTooltip('在线客服'),
          });
          expect(calls, ['interaction', action]);
        } finally {
          await tester.pumpWidget(const SizedBox());
        }
      });
    }

    for (final keyboard in [false, true]) {
      testWidgets(
        'API dialog reports intent, keyboard=$keyboard mobile=$mobile',
        (tester) async {
          _size(tester, mobile);
          final calls = <String>[];
          try {
            await tester.pumpWidget(
              _app(
                onUserInteraction: () {
                  expect(
                    find.byKey(const Key('api-health-dialog')),
                    findsNothing,
                  );
                  calls.add('interaction');
                },
              ),
            );
            await tester.pumpAndSettle();
            expect(calls, isEmpty);
            if (keyboard) {
              Focus.of(
                tester.element(find.byIcon(Icons.dns_outlined)),
              ).requestFocus();
              await tester.pump();
              await tester.sendKeyEvent(LogicalKeyboardKey.enter);
              await tester.pumpAndSettle();
            } else {
              await _tap(
                tester,
                find.byKey(const Key('api-health-status-button')),
              );
            }
            expect(calls, ['interaction']);
            expect(find.byKey(const Key('api-health-dialog')), findsOneWidget);
            expect(tester.takeException(), isNull);
          } finally {
            await tester.pumpWidget(const SizedBox());
          }
        },
      );
    }
  }

  testWidgets('login failure diagnostics and log export report user intent', (
    tester,
  ) async {
    _size(tester, false);
    final calls = <String>[];
    try {
      await tester.pumpWidget(
        _app(
          onUserInteraction: () => calls.add('interaction'),
          prefill: _rememberedPrefill,
          authenticate: (_, _) async => throw const XboardAuthException(
            failure: XboardAuthFailure.noAvailableHost,
            message: 'unavailable',
          ),
          onExportLogs: () async {
            calls.add('export');
            return false;
          },
        ),
      );
      await tester.pumpAndSettle();
      await _tap(tester, find.byKey(const Key('login-submit-button')));
      expect(find.byKey(const Key('login-network-failure')), findsOneWidget);

      calls.clear();
      await _tap(tester, find.byKey(const Key('login-export-logs')));
      expect(calls, ['interaction', 'export']);

      calls.clear();
      await _tap(tester, find.byKey(const Key('login-api-diagnostics')));
      expect(calls, ['interaction']);
      expect(find.byKey(const Key('api-health-dialog')), findsOneWidget);
      expect(tester.takeException(), isNull);
    } finally {
      await tester.pumpWidget(const SizedBox());
    }
  });
}

const _rememberedPrefill = LoginFormPrefill(
  email: 'user@example.com',
  password: 'test-password',
);

const _backgroundPrefill = LoginFormPrefill(
  email: 'stored@example.com',
  password: 'stored-password',
  preserveUserInput: true,
);

Widget _app({
  required VoidCallback onUserInteraction,
  VoidCallback? onLogin,
  LoginFormPrefill? prefill,
  bool initialRememberMe = false,
  bool initialAutoLogin = false,
  VoidCallback? onRememberMeDisabled,
  VoidCallback? onAutomaticLoginDisabled,
  bool offlineAvailable = false,
  Future<void> Function()? onOfflinePressed,
  VoidCallback? onRegisterPressed,
  VoidCallback? onForgotPasswordPressed,
  ValueChanged<BuildContext>? onLanguagePressed,
  ValueChanged<BuildContext>? onThemePressed,
  ValueChanged<BuildContext>? onSupportPressed,
  Future<bool> Function()? onExportLogs,
  Future<XboardLoginResult> Function(String, String)? authenticate,
  Widget? home,
}) => MaterialApp(
  locale: const Locale('zh', 'CN'),
  localizationsDelegates: const [
    AppLocalizations.delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
  ],
  supportedLocales: AppLocalizations.delegate.supportedLocales,
  home:
      home ??
      LoginPage(
        onLogin: onLogin ?? () {},
        onLanguagePressed: onLanguagePressed ?? (_) {},
        onThemePressed: onThemePressed ?? (_) {},
        onSupportPressed: onSupportPressed ?? (_) {},
        appVersion: '1.0.2-test',
        apiHealthService: ApiHealthService(configUrl: ''),
        onUserInteraction: onUserInteraction,
        prefill: prefill,
        initialRememberMe: initialRememberMe,
        initialAutoLogin: initialAutoLogin,
        onRememberMeDisabled: onRememberMeDisabled,
        onAutomaticLoginDisabled: onAutomaticLoginDisabled,
        offlineAvailable: offlineAvailable,
        onOfflinePressed: onOfflinePressed,
        onRegisterPressed: onRegisterPressed,
        onForgotPasswordPressed: onForgotPasswordPressed,
        onExportLogs: onExportLogs,
        authenticate: authenticate,
      ),
);

void _size(WidgetTester tester, bool mobile) {
  tester.view.physicalSize = mobile
      ? const Size(390, 844)
      : const Size(1200, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
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

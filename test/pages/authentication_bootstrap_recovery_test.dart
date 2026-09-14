import 'dart:async';

import 'package:fl_clash/common/api_health.dart';
import 'package:fl_clash/common/application_bootstrap.dart';
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

  testWidgets('late unlock resumes the original read with a fresh deadline', (
    tester,
  ) async {
    final secrets = await _seed();
    final locked = secrets.lockNextRead();
    final restored = Completer<void>();
    final flow = await _mount(tester, secrets, restore: () => restored.future);
    try {
      await tester.pump(const Duration(seconds: 59));
      expect(find.byKey(const Key('bootstrap-loading')), findsOneWidget);
      await tester.pump(const Duration(seconds: 1));
      _expectFields(tester, email: '', password: '');
      expect(flow.currentState!.controller.hasPendingWork, isTrue);
      expect(secrets.reads, {'xboard.credentials_v2': 1});

      locked.complete();
      await tester.pumpAndSettle();
      expect(flow.currentState!.restoreCalls, 1);
      expect(flow.currentState!.resumed, isTrue);
      expect(flow.currentState!.userInteractions, 0);
      expect(find.byKey(const Key('bootstrap-loading')), findsOneWidget);
      await tester.pump(const Duration(seconds: 59));
      expect(find.byKey(const Key('bootstrap-loading')), findsOneWidget);

      restored.complete();
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('bootstrap-home')), findsOneWidget);
      expect(flow.currentState!.controller.hasPendingWork, isFalse);
      _expectOneCredentialRead(secrets);
      expect(secrets.writes, isEmpty);
      expect(secrets.deletes, isEmpty);
      expect(tester.takeException(), isNull);
    } finally {
      await tester.pumpWidget(const SizedBox());
    }
  });

  testWidgets('late remembered credentials only prefill without auto-login', (
    tester,
  ) async {
    final secrets = await _seed(autoLogin: false);
    final locked = secrets.lockNextRead();
    final flow = await _mount(tester, secrets);
    try {
      await tester.pump(const Duration(seconds: 60));
      locked.complete();
      await tester.pumpAndSettle();

      _expectFields(tester);
      expect(_checkbox(tester, '记住我').value, isTrue);
      expect(_checkbox(tester, '自动登录').value, isFalse);
      expect(flow.currentState!.restoreCalls, 0);
      expect(flow.currentState!.userInteractions, 0);
      expect(flow.currentState!.resumed, isTrue);
      expect(flow.currentState!.controller.hasPendingWork, isFalse);
      _expectOneCredentialRead(secrets);
      expect(tester.takeException(), isNull);
    } finally {
      await tester.pumpWidget(const SizedBox());
    }
  });

  testWidgets('late keyring failure keeps secrets and disables restoration', (
    tester,
  ) async {
    final secrets = await _seed();
    final original = Map<String, String>.of(secrets.values);
    final locked = secrets.lockNextRead();
    final flow = await _mount(tester, secrets);
    try {
      await tester.pump(const Duration(seconds: 60));
      locked.completeError(PlatformException(code: 'access_denied'));
      await tester.pumpAndSettle();

      _expectFields(tester, password: '');
      expect(_checkbox(tester, '记住我').value, isTrue);
      expect(_checkbox(tester, '自动登录').value, isFalse);
      expect(
        flow.currentState!.widget.persistence.state.hasStorageError,
        isTrue,
      );
      expect(flow.currentState!.restoreCalls, 0);
      expect(flow.currentState!.controller.hasPendingWork, isFalse);
      expect(secrets.values, original);
      expect(secrets.writes, isEmpty);
      expect(secrets.deletes, isEmpty);
      _expectOneCredentialRead(secrets);
      expect(tester.takeException(), isNull);
    } finally {
      await tester.pumpWidget(const SizedBox());
    }
  });

  for (final action in _UserIntent.values) {
    testWidgets('late credentials cannot override ${action.name}', (
      tester,
    ) async {
      final secrets = await _seed();
      final locked = secrets.lockNextRead();
      final flow = await _mount(tester, secrets);
      try {
        await tester.pump(const Duration(seconds: 60));
        switch (action) {
          case _UserIntent.typedThenClearedEmail:
            await tester.enterText(
              find.byKey(const Key('login-email-field')),
              'other@example.com',
            );
            await tester.enterText(
              find.byKey(const Key('login-email-field')),
              '',
            );
          case _UserIntent.typedThenClearedPassword:
            await tester.enterText(
              find.byKey(const Key('login-password-field')),
              'other-password',
            );
            await tester.enterText(
              find.byKey(const Key('login-password-field')),
              '',
            );
          case _UserIntent.invalidLoginSubmission:
            await _tap(tester, find.byKey(const Key('login-submit-button')));
          case _UserIntent.rememberSelection:
            await _tap(tester, find.text('记住我'));
          case _UserIntent.automaticLoginSelection:
            await _tap(tester, find.text('自动登录'));
        }
        expect(flow.currentState!.userInteractions, greaterThan(0));
        expect(flow.currentState!.controller.hasPendingWork, isFalse);
        locked.complete();
        await tester.pumpAndSettle();

        _expectFields(tester, email: '', password: '');
        expect(flow.currentState!.discarded, isTrue);
        expect(flow.currentState!.restoreCalls, 0);
        expect(flow.currentState!.manualLoginCalls, 0);
        expect(
          _checkbox(tester, '记住我').value,
          action == _UserIntent.rememberSelection ||
              action == _UserIntent.automaticLoginSelection,
        );
        expect(
          _checkbox(tester, '自动登录').value,
          action == _UserIntent.automaticLoginSelection,
        );
        _expectOneCredentialRead(secrets);
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox());
      }
    });
  }

  for (final clearInput in [false, true]) {
    testWidgets(
      'editing the outgoing login form cancels resumed recovery, clear=$clearInput',
      (tester) async {
        final secrets = await _seed();
        final locked = secrets.lockNextRead();
        final flow = await _mount(tester, secrets);
        try {
          await tester.pump(const Duration(seconds: 60));
          final loginState = tester.state(find.byType(LoginPage));
          final input = tester.state<EditableTextState>(
            find.descendant(
              of: find.byKey(const Key('login-email-field')),
              matching: find.byType(EditableText),
            ),
          );
          locked.complete();
          await tester.idle();
          expect(flow.currentState!.resumed, isTrue);
          expect(flow.currentState!.loading, isTrue);
          expect(flow.currentState!.prefill, isNull);
          expect(flow.currentState!.restoreCalls, 0);
          expect(find.byType(LoginPage), findsOneWidget);
          expect(
            identical(tester.state(find.byType(LoginPage)), loginState),
            isTrue,
          );

          input.updateEditingValue(
            const TextEditingValue(
              text: 'other@example.com',
              selection: TextSelection.collapsed(offset: 17),
            ),
          );
          if (clearInput) {
            input.updateEditingValue(
              const TextEditingValue(
                selection: TextSelection.collapsed(offset: 0),
              ),
            );
          }
          expect(flow.currentState!.userInteractions, greaterThan(0));
          expect(flow.currentState!.controller.hasPendingWork, isFalse);
          expect(flow.currentState!.loading, isFalse);
          await tester.pumpAndSettle();

          expect(
            identical(tester.state(find.byType(LoginPage)), loginState),
            isTrue,
          );
          _expectFields(
            tester,
            email: clearInput ? '' : 'other@example.com',
            password: '',
          );
          expect(flow.currentState!.discarded, isTrue);
          expect(flow.currentState!.prefill, isNull);
          expect(flow.currentState!.restoreCalls, 0);
          _expectOneCredentialRead(secrets);
          expect(tester.takeException(), isNull);
        } finally {
          await tester.pumpWidget(const SizedBox());
        }
      },
    );
  }

  testWidgets('unmounted recovery ignores the pending keyring result', (
    tester,
  ) async {
    final secrets = await _seed();
    final locked = secrets.lockNextRead();
    final flow = await _mount(tester, secrets);
    final state = flow.currentState!;
    try {
      await tester.pump(const Duration(seconds: 60));
      await tester.pumpWidget(const SizedBox());
      locked.complete();
      await tester.pumpAndSettle();
      expect(state.controller.hasPendingWork, isFalse);
      expect(state.restoreCalls, 0);
      expect(tester.takeException(), isNull);
    } finally {
      await tester.pumpWidget(const SizedBox());
    }
  });

  for (final intent in _PersistenceIntent.values) {
    test('pending load cannot replace newer ${intent.name} intent', () async {
      final secrets = await _seed();
      final persistence = _persistence(secrets);
      final locked = secrets.lockNextRead();
      final pendingLoad = persistence.load();
      await secrets.readStarted!.future;
      final mutation = switch (intent) {
        _PersistenceIntent.forget => persistence.forget(),
        _PersistenceIntent.newAccount => _save(
          persistence,
          email: 'other@example.com',
          password: 'other-password',
        ),
        _PersistenceIntent.logout => persistence.prepareForLogout(),
      };
      final pendingState = persistence.state;
      expect(pendingState.canAutoLogin, isFalse);
      if (intent == _PersistenceIntent.newAccount) {
        expect(pendingState.email, 'other@example.com');
        expect(pendingState.password, 'other-password');
      } else {
        expect(pendingState.email, isNull);
        expect(pendingState.password, isNull);
      }

      locked.complete();
      final loaded = await pendingLoad;
      expect(identical(loaded, pendingState), isTrue);
      await mutation;
      final reopened = await _persistence(secrets).load();
      switch (intent) {
        case _PersistenceIntent.forget:
          expect(reopened.rememberMe, isFalse);
          expect(reopened.email, isNull);
          expect(reopened.password, isNull);
          expect(reopened.canRestore, isFalse);
          expect(secrets.values, isEmpty);
        case _PersistenceIntent.newAccount:
          expect(reopened.email, 'other@example.com');
          expect(reopened.password, 'other-password');
          expect(reopened.canAutoLogin, isTrue);
        case _PersistenceIntent.logout:
          expect(reopened.email, 'user@example.com');
          expect(reopened.password, 'secret-password');
          expect(reopened.rememberMe, isTrue);
          expect(reopened.canRestore, isFalse);
          expect(reopened.autoLogin, isFalse);
          expect(reopened.token, isNull);
          expect(reopened.authData, isNull);
      }
    });
  }
}

enum _UserIntent {
  typedThenClearedEmail,
  typedThenClearedPassword,
  invalidLoginSubmission,
  rememberSelection,
  automaticLoginSelection,
}

enum _PersistenceIntent { forget, newAccount, logout }

class _BootstrapFlow extends StatefulWidget {
  const _BootstrapFlow({super.key, required this.persistence, this.restore});

  final XboardLoginPersistence persistence;
  final Future<void> Function()? restore;

  @override
  State<_BootstrapFlow> createState() => _BootstrapFlowState();
}

class _BootstrapFlowState extends State<_BootstrapFlow> {
  final controller = AuthenticationBootstrapController();
  static const timeout = Duration(seconds: 60);
  bool loading = true;
  bool home = false;
  bool resumed = false;
  bool discarded = false;
  int restoreCalls = 0;
  int manualLoginCalls = 0;
  int userInteractions = 0;
  LoginFormPrefill? prefill;
  XboardStoredSession accepted = const XboardStoredSession(
    rememberMe: false,
    autoLogin: false,
  );

  @override
  void initState() {
    super.initState();
    final revision = controller.begin(timeout: timeout, onTimeout: _onTimeout);
    unawaited(_load(revision));
  }

  void _onTimeout(int revision) {
    if (!mounted) return;
    if (!controller.deferForCredentials(revision)) {
      controller.complete(revision);
    }
    setState(() => loading = false);
  }

  Future<void> _load(int revision) async {
    final loaded = await controller.loadCredentials(
      revision,
      load: widget.persistence.load,
      timeout: timeout,
      onTimeout: _onTimeout,
    );
    if (loaded == null || !mounted) {
      discarded = true;
      return;
    }
    resumed = loaded.resumed;
    if (resumed) {
      setState(() => loading = true);
      await WidgetsBinding.instance.endOfFrame;
    }
    if (!mounted || !controller.isCurrent(loaded.revision)) {
      discarded = true;
      return;
    }
    accepted = loaded.value;
    prefill = LoginFormPrefill(
      email: accepted.email ?? '',
      password: accepted.password ?? '',
    );
    if (accepted.canAutoLogin) {
      setState(() => loading = true);
      restoreCalls++;
      await widget.restore?.call();
      if (!mounted || !controller.complete(loaded.revision)) return;
      setState(() {
        home = true;
        loading = false;
      });
      return;
    }
    if (controller.complete(loaded.revision)) {
      setState(() => loading = false);
    }
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (loading) return const SizedBox(key: Key('bootstrap-loading'));
    if (home) return const SizedBox(key: Key('bootstrap-home'));
    return LoginPage(
      onLogin: () => setState(() => home = true),
      onLanguagePressed: (_) {},
      onThemePressed: (_) {},
      onSupportPressed: (_) {},
      appVersion: '1.0.2-test',
      apiHealthService: ApiHealthService(configUrl: ''),
      prefill: prefill,
      initialRememberMe: accepted.rememberMe,
      initialAutoLogin: accepted.autoLogin,
      onUserInteraction: () {
        userInteractions++;
        controller.cancel();
        if (loading) setState(() => loading = false);
      },
      authenticate: (_, _) async {
        manualLoginCalls++;
        return _session();
      },
      onRememberMeDisabled: () => unawaited(widget.persistence.forget()),
      onAutomaticLoginDisabled: () =>
          unawaited(widget.persistence.disableAutoLogin()),
    );
  }
}

Future<GlobalKey<_BootstrapFlowState>> _mount(
  WidgetTester tester,
  _SecretBoundary secrets, {
  Future<void> Function()? restore,
}) async {
  tester.view.physicalSize = const Size(1200, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final key = GlobalKey<_BootstrapFlowState>();
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
      home: _BootstrapFlow(
        key: key,
        persistence: _persistence(secrets),
        restore: restore,
      ),
    ),
  );
  await tester.pump();
  expect(secrets.readStarted!.isCompleted, isTrue);
  return key;
}

void _expectFields(
  WidgetTester tester, {
  String email = 'user@example.com',
  String password = 'secret-password',
}) {
  for (final entry in {'email': email, 'password': password}.entries) {
    final field = tester.widget<EditableText>(
      find.descendant(
        of: find.byKey(Key('login-${entry.key}-field')),
        matching: find.byType(EditableText),
      ),
    );
    expect(field.controller.text, entry.value);
  }
}

Checkbox _checkbox(WidgetTester tester, String label) =>
    tester.widget<Checkbox>(
      find.descendant(
        of: find
            .ancestor(of: find.text(label), matching: find.byType(Row))
            .first,
        matching: find.byType(Checkbox),
      ),
    );

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

void _expectOneCredentialRead(_SecretBoundary secrets) {
  expect(secrets.reads, {
    'xboard.credentials_v2': 1,
    'xboard.token': 1,
    'xboard.auth_data': 1,
  });
}

XboardLoginPersistence _persistence(_SecretBoundary secrets) =>
    XboardLoginPersistence(storage: XboardSessionStorage(secretStore: secrets));

Future<_SecretBoundary> _seed({bool autoLogin = true}) async {
  final secrets = _SecretBoundary();
  expect(await _save(_persistence(secrets), autoLogin: autoLogin), isTrue);
  secrets.reads.clear();
  secrets.writes.clear();
  secrets.deletes.clear();
  return secrets;
}

Future<bool> _save(
  XboardLoginPersistence persistence, {
  bool autoLogin = true,
  String email = 'user@example.com',
  String password = 'secret-password',
}) => persistence.saveAuthenticated(
  session: _session(),
  email: email,
  password: password,
  rememberMe: true,
  autoLogin: autoLogin,
);

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
  final reads = <String, int>{};
  final writes = <String>[];
  final deletes = <String>[];
  Completer<void>? readStarted;
  Completer<void>? _lockedRead;

  Completer<void> lockNextRead() {
    readStarted = Completer<void>();
    return _lockedRead = Completer<void>();
  }

  @override
  Future<String?> read(String key) async {
    reads.update(key, (count) => count + 1, ifAbsent: () => 1);
    final value = values[key];
    if (key == 'xboard.credentials_v2' && _lockedRead != null) {
      final locked = _lockedRead!;
      _lockedRead = null;
      readStarted!.complete();
      await locked.future;
    }
    return value;
  }

  @override
  Future<void> write(String key, String value) async {
    writes.add(key);
    values[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    deletes.add(key);
    values.remove(key);
  }
}

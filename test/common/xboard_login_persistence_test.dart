import 'dart:async';

import 'package:fl_clash/common/local_secret_store.dart';
import 'package:fl_clash/common/xboard_auth.dart';
import 'package:fl_clash/common/xboard_login_persistence.dart';
import 'package:fl_clash/common/xboard_session_storage.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('remembered credentials survive logout and a new controller', () async {
    final secrets = _SecretBoundary();
    final persistence = _persistence(secrets);
    expect(await _save(persistence, autoLogin: true), isTrue);
    expect(persistence.state.canAutoLogin, isTrue);

    final loggedOut = await persistence.prepareForLogout();
    _expectRemembered(loggedOut);
    expect(loggedOut.autoLogin, isFalse);
    expect(loggedOut.canRestore, isFalse);
    expect(loggedOut.token, isNull);
    expect(loggedOut.authData, isNull);

    final reopened = await _persistence(secrets).load();
    _expectRemembered(reopened);
    expect(reopened.autoLogin, isFalse);
    expect(reopened.canRestore, isFalse);
    expect(reopened.hasStorageError, isFalse);
  });

  test(
    'forget deletes saved account, password and remember selection',
    () async {
      final secrets = _SecretBoundary();
      final persistence = _persistence(secrets);
      await _save(persistence);
      expect(await persistence.forget(), isTrue);
      _expectForgotten(persistence.state);
      _expectForgotten(await _persistence(secrets).load());
      expect(secrets.values.values, isNot(contains('secret-password')));
    },
  );

  test('login without remember does not retain previous account', () async {
    final secrets = _SecretBoundary();
    final persistence = _persistence(secrets);
    await _save(persistence);
    expect(
      await _save(
        persistence,
        email: 'other@example.com',
        password: 'other-password',
        rememberMe: false,
      ),
      isTrue,
    );
    _expectForgotten(await persistence.prepareForLogout());
    _expectForgotten(await _persistence(secrets).load());
  });

  test(
    'switching remembered accounts binds password to the new email',
    () async {
      final secrets = _SecretBoundary();
      final persistence = _persistence(secrets);
      await _save(persistence);
      await _save(
        persistence,
        email: 'other@example.com',
        password: 'other-password',
      );
      final stored = await persistence.prepareForLogout();
      expect(stored.email, 'other@example.com');
      expect(stored.password, 'other-password');
      expect(stored.canRestoreForEmail('user@example.com'), isFalse);
      final reopened = await _persistence(secrets).load();
      expect(reopened.email, 'other@example.com');
      expect(reopened.password, 'other-password');
    },
  );

  test('new account with empty password never reuses old password', () async {
    final secrets = _SecretBoundary();
    final persistence = _persistence(secrets);
    await _save(persistence);
    await _save(persistence, email: 'other@example.com', password: '');
    expect(persistence.state.email, 'other@example.com');
    expect(persistence.state.password, isNot('secret-password'));
    expect(
      (await persistence.prepareForLogout()).password,
      isNot('secret-password'),
    );
    expect(
      (await _persistence(secrets).load()).password,
      isNot('secret-password'),
    );
  });

  test(
    'diagnostic callback failure cannot interrupt successful persistence',
    () async {
      final persistence = _persistence(
        _SecretBoundary(),
        onDiagnostic: (_, _) => throw StateError('diagnostic_unavailable'),
      );

      _expectForgotten(await persistence.load());
      expect(await _save(persistence), isTrue);
      _expectRemembered(persistence.state);
      _expectRemembered(await persistence.prepareForLogout());
      expect(persistence.state.hasStorageError, isFalse);
      expect(await persistence.forget(), isTrue);
      _expectForgotten(persistence.state);
    },
  );

  test(
    'diagnostic callback failure cannot replace a storage failure result',
    () async {
      final secrets = _SecretBoundary()..failWrites = true;
      final persistence = _persistence(
        secrets,
        onDiagnostic: (_, _) => throw StateError('diagnostic_unavailable'),
      );

      expect(await _save(persistence), isFalse);
      _expectRemembered(persistence.state);
      expect(persistence.state.hasStorageError, isTrue);
      _expectRemembered(await persistence.prepareForLogout());
      secrets.deleteFailures.add('xboard.credentials_v2');
      expect(await persistence.forget(), isFalse);
      _expectForgotten(persistence.state);
      expect(persistence.state.hasStorageError, isTrue);
    },
  );

  for (final failPreferences in [false, true]) {
    test(
      'failed password replacement retains newest session password, preferences=$failPreferences',
      () async {
        final secrets = _SecretBoundary();
        var failNextPreferencesLoad = false;
        final persistence = XboardLoginPersistence(
          storage: XboardSessionStorage(
            secretStore: secrets,
            preferencesLoader: () async {
              if (failNextPreferencesLoad) {
                failNextPreferencesLoad = false;
                throw PlatformException(code: 'preferences_unavailable');
              }
              return SharedPreferences.getInstance();
            },
          ),
        );
        expect(await _save(persistence), isTrue);
        if (failPreferences) {
          failNextPreferencesLoad = true;
        } else {
          secrets.failWrites = true;
        }

        expect(
          await _save(persistence, password: 'newly-authenticated-password'),
          isFalse,
        );
        expect(persistence.state.password, 'newly-authenticated-password');
        final loggedOut = await persistence.prepareForLogout();
        expect(loggedOut.email, 'user@example.com');
        expect(loggedOut.password, 'newly-authenticated-password');
        expect(loggedOut.rememberMe, isTrue);
        expect(loggedOut.autoLogin, isFalse);
        expect(loggedOut.hasStorageError, isTrue);
        final restarted = await _persistence(secrets).load();
        expect(restarted.password, isNot('newly-authenticated-password'));
      },
    );
  }

  test(
    'secret write failure keeps selection and reports unsafe persistence',
    () async {
      final secrets = _SecretBoundary()..failWrites = true;
      final diagnostics = <Map<String, Object?>>[];
      final persistence = _persistence(
        secrets,
        onDiagnostic: (event, fields) =>
            diagnostics.add({'event': event, ...fields}),
      );

      expect(await _save(persistence), isFalse);
      _expectRemembered(persistence.state);
      expect(persistence.state.hasStorageError, isTrue);
      expect(persistence.state.canAutoLogin, isFalse);
      final loggedOut = await persistence.prepareForLogout();
      _expectRemembered(loggedOut);
      expect(loggedOut.hasStorageError, isTrue);
      final preferences = await SharedPreferences.getInstance();
      expect(preferences.getString('xboard.email'), 'user@example.com');
      expect(preferences.getBool('xboard.remember_me'), isTrue);
      expect(diagnostics, isNotEmpty);
      final diagnosticText = diagnostics.toString();
      expect(diagnosticText, isNot(contains('secret-password')));
      expect(diagnosticText, isNot(contains('subscription-token')));
      expect(diagnosticText, isNot(contains('Bearer login-token')));
    },
  );

  test(
    'token read failure does not hide independently saved password',
    () async {
      final secrets = _SecretBoundary();
      await _save(_persistence(secrets));
      secrets.readFailures.add('xboard.token');

      final stored = await _persistence(secrets).load();
      _expectRemembered(stored);
      expect(stored.hasStorageError, isTrue);
      expect(stored.canAutoLogin, isFalse);
    },
  );

  test(
    'transient password read failure preserves known same-account memory',
    () async {
      final secrets = _SecretBoundary();
      final persistence = _persistence(secrets);
      await _save(persistence);
      secrets.readFailures.add('xboard.credentials_v2');

      final stored = await persistence.load();
      _expectRemembered(stored);
      expect(stored.hasStorageError, isTrue);
      expect(stored.canRestore, isFalse);
      secrets.readFailures.clear();
      _expectRemembered(await persistence.load());
      expect(persistence.state.hasStorageError, isFalse);
    },
  );

  test(
    'loading unavailable preferences retains previously verified memory',
    () async {
      final secrets = _SecretBoundary();
      var preferencesUnavailable = false;
      final persistence = XboardLoginPersistence(
        storage: XboardSessionStorage(
          secretStore: secrets,
          preferencesLoader: () async {
            if (preferencesUnavailable) {
              throw PlatformException(code: 'preferences_unavailable');
            }
            return SharedPreferences.getInstance();
          },
        ),
      );
      await _save(persistence);
      preferencesUnavailable = true;

      final stored = await persistence.load();
      _expectRemembered(stored);
      expect(stored.hasStorageError, isTrue);
      expect(stored.canRestore, isFalse);
    },
  );

  test(
    'initial unavailable storage exposes error without inventing credentials',
    () async {
      final persistence = XboardLoginPersistence(
        storage: XboardSessionStorage(
          secretStore: _SecretBoundary(),
          preferencesLoader: () async =>
              throw PlatformException(code: 'preferences_unavailable'),
        ),
      );

      final stored = await persistence.load();
      _expectForgotten(stored);
      expect(stored.hasStorageError, isTrue);
    },
  );

  test(
    'failed credential deletion stays forgotten and reports cleanup error',
    () async {
      final secrets = _SecretBoundary();
      final persistence = _persistence(secrets);
      await _save(persistence);
      secrets.deleteFailures.add('xboard.credentials_v2');

      expect(await persistence.forget(), isFalse);
      _expectForgotten(persistence.state);
      expect(persistence.state.hasStorageError, isTrue);
      final reopened = await _persistence(secrets).load();
      _expectForgotten(reopened);
      expect(reopened.hasStorageError, isTrue);
    },
  );

  test(
    'failed forget preferences cannot restore same-controller memory',
    () async {
      final secrets = _SecretBoundary();
      var preferencesUnavailable = false;
      final persistence = XboardLoginPersistence(
        storage: XboardSessionStorage(
          secretStore: secrets,
          preferencesLoader: () async {
            if (preferencesUnavailable) {
              throw PlatformException(code: 'preferences_unavailable');
            }
            return SharedPreferences.getInstance();
          },
        ),
      );
      await _save(persistence);
      preferencesUnavailable = true;

      expect(await persistence.forget(), isFalse);
      _expectForgotten(persistence.state);
      expect(persistence.state.hasStorageError, isTrue);
      _expectForgotten(await persistence.load());
      preferencesUnavailable = false;
      _expectForgotten(await persistence.load());
    },
  );

  test('password read failure does not silently claim no account', () async {
    final secrets = _SecretBoundary();
    await _save(_persistence(secrets));
    secrets.readFailures.addAll({'xboard.credentials_v2', 'xboard.password'});

    final stored = await _persistence(secrets).load();
    expect(stored.email, 'user@example.com');
    expect(stored.rememberMe, isTrue);
    expect(stored.password, isNull);
    expect(stored.hasStorageError, isTrue);
    expect(secrets.deletions, isNot(contains('xboard.credentials_v2')));
  });

  test(
    'logout preference failure preserves this session credentials',
    () async {
      final secrets = _SecretBoundary();
      var preferencesUnavailable = false;
      final persistence = XboardLoginPersistence(
        storage: XboardSessionStorage(
          secretStore: secrets,
          preferencesLoader: () async {
            if (preferencesUnavailable) {
              throw PlatformException(code: 'preferences_unavailable');
            }
            return SharedPreferences.getInstance();
          },
        ),
      );
      await _save(persistence, autoLogin: true);
      secrets.deletions.clear();
      preferencesUnavailable = true;

      final loggedOut = await persistence.prepareForLogout();
      _expectRemembered(loggedOut);
      expect(loggedOut.autoLogin, isFalse);
      expect(loggedOut.canRestore, isFalse);
      expect(loggedOut.hasStorageError, isTrue);
      expect(secrets.deletions, isNot(contains('xboard.credentials_v2')));
      expect(secrets.deletions, isNot(contains('xboard.password')));
    },
  );

  test('failed session deletion never erases remembered credentials', () async {
    final secrets = _SecretBoundary();
    final persistence = _persistence(secrets);
    await _save(persistence, autoLogin: true);
    secrets.deletions.clear();
    secrets.deleteFailures.add('xboard.token');

    final loggedOut = await persistence.prepareForLogout();
    _expectRemembered(loggedOut);
    expect(loggedOut.canAutoLogin, isFalse);
    expect(loggedOut.hasStorageError, isTrue);
    expect(secrets.deletions, isNot(contains('xboard.credentials_v2')));
    _expectRemembered(await _persistence(secrets).load());
  });

  test(
    'disable automatic login leaves remembered password untouched',
    () async {
      final secrets = _SecretBoundary();
      final persistence = _persistence(secrets);
      await _save(persistence, autoLogin: true);
      expect(await persistence.disableAutoLogin(), isTrue);
      _expectRemembered(persistence.state);
      expect(persistence.state.autoLogin, isFalse);
      final reopened = await _persistence(secrets).load();
      _expectRemembered(reopened);
      expect(reopened.autoLogin, isFalse);
    },
  );

  test('authentication invalidation clears session but not password', () async {
    final secrets = _SecretBoundary();
    final persistence = _persistence(secrets);
    await _save(persistence, autoLogin: true);
    expect(await persistence.invalidateSession(), isTrue);
    _expectRemembered(persistence.state);
    expect(persistence.state.canRestore, isFalse);
    _expectRemembered(await _persistence(secrets).load());
  });

  test('forget requested during pending save wins over stale save', () async {
    final secrets = _SecretBoundary()
      ..writeEntered = Completer<void>()
      ..writeRelease = Completer<void>();
    final persistence = _persistence(secrets);
    final pendingSave = _save(persistence);
    await secrets.writeEntered!.future;
    final pendingForget = persistence.forget();
    secrets.writeRelease!.complete();
    await pendingSave;
    expect(await pendingForget, isTrue);
    _expectForgotten(persistence.state);
    _expectForgotten(await _persistence(secrets).load());
  });

  test(
    'logout requested during pending save waits and disables session',
    () async {
      final secrets = _SecretBoundary()
        ..writeEntered = Completer<void>()
        ..writeRelease = Completer<void>();
      final persistence = _persistence(secrets);
      final pendingSave = _save(persistence, autoLogin: true);
      await secrets.writeEntered!.future;
      final pendingLogout = persistence.prepareForLogout();
      secrets.writeRelease!.complete();
      await pendingSave;
      final loggedOut = await pendingLogout;
      _expectRemembered(loggedOut);
      expect(loggedOut.autoLogin, isFalse);
      expect(loggedOut.canRestore, isFalse);
      final reopened = await _persistence(secrets).load();
      _expectRemembered(reopened);
      expect(reopened.canRestore, isFalse);
    },
  );

  test('failed new-account save cannot fallback to previous account', () async {
    final secrets = _SecretBoundary();
    final persistence = _persistence(secrets);
    await _save(persistence);
    secrets.failWrites = true;

    expect(
      await _save(
        persistence,
        email: 'other@example.com',
        password: 'other-password',
      ),
      isFalse,
    );
    final loggedOut = await persistence.prepareForLogout();
    expect(loggedOut.email, 'other@example.com');
    expect(loggedOut.password, 'other-password');
    final reopened = await _persistence(secrets).load();
    expect(reopened.email, 'other@example.com');
    expect(reopened.password, isNot('secret-password'));
    expect(reopened.hasStorageError, isTrue);
  });
}

XboardLoginPersistence _persistence(
  _SecretBoundary secrets, {
  void Function(String, Map<String, Object?>)? onDiagnostic,
}) => XboardLoginPersistence(
  storage: XboardSessionStorage(secretStore: secrets),
  onDiagnostic: onDiagnostic,
);

Future<bool> _save(
  XboardLoginPersistence persistence, {
  String email = 'user@example.com',
  String password = 'secret-password',
  bool rememberMe = true,
  bool autoLogin = false,
}) => persistence.saveAuthenticated(
  session: _session(),
  email: email,
  password: password,
  rememberMe: rememberMe,
  autoLogin: autoLogin,
);

void _expectRemembered(XboardStoredSession stored) {
  expect(stored.rememberMe, isTrue);
  expect(stored.email, 'user@example.com');
  expect(stored.password, 'secret-password');
}

void _expectForgotten(XboardStoredSession stored) {
  expect(stored.rememberMe, isFalse);
  expect(stored.autoLogin, isFalse);
  expect(stored.email, isNull);
  expect(stored.password, isNull);
  expect(stored.token, isNull);
  expect(stored.authData, isNull);
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
  final readFailures = <String>{};
  final deleteFailures = <String>{};
  final deletions = <String>[];
  bool failWrites = false;
  Completer<void>? writeEntered;
  Completer<void>? writeRelease;

  @override
  Future<String?> read(String key) async {
    if (readFailures.contains(key)) {
      throw PlatformException(code: 'read_unavailable');
    }
    return values[key];
  }

  @override
  Future<void> write(String key, String value) async {
    if (failWrites) throw PlatformException(code: 'write_unavailable');
    if (writeEntered?.isCompleted == false) writeEntered!.complete();
    await writeRelease?.future;
    values[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    deletions.add(key);
    if (deleteFailures.contains(key)) {
      throw PlatformException(code: 'delete_unavailable');
    }
    values.remove(key);
  }
}

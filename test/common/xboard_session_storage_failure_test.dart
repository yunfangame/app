import 'dart:async';
import 'dart:convert';

import 'package:fl_clash/common/local_secret_store.dart';
import 'package:fl_clash/common/xboard_session_storage.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _SecretStore implements SecretStringStore {
  final values = <String, String>{};
  final failReads = <String>{};
  final failWrites = <String>{};
  final failDeletes = <String>{};
  final ignoredWrites = <String>{};
  final ignoredDeletes = <String>{};
  final writtenKeys = <String>[];
  Completer<void>? writeStarted;
  Completer<void>? writeRelease;
  String? pausedKey;

  @override
  Future<String?> read(String key) async {
    if (failReads.contains(key)) {
      throw PlatformException(
        code: 'storage_error',
        message: 'user@example.com private-password private-token',
      );
    }
    return values[key];
  }

  @override
  Future<void> write(String key, String value) async {
    writtenKeys.add(key);
    if (key == pausedKey) {
      writeStarted?.complete();
      await writeRelease?.future;
    }
    if (failWrites.contains(key)) {
      throw StateError('user@example.com private-password private-token');
    }
    if (!ignoredWrites.contains(key)) values[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    if (failDeletes.contains(key)) throw StateError('private-password');
    if (!ignoredDeletes.contains(key)) values.remove(key);
  }
}

class _RejectingPreferences extends Fake implements SharedPreferences {
  _RejectingPreferences(this.inner);

  final SharedPreferences inner;
  final rejected = <String>{};

  @override
  bool? getBool(String key) => inner.getBool(key);

  @override
  String? getString(String key) => inner.getString(key);

  @override
  int? getInt(String key) => inner.getInt(key);

  @override
  Future<bool> setBool(String key, bool value) async =>
      !rejected.contains(key) && await inner.setBool(key, value);

  @override
  Future<bool> setInt(String key, int value) async =>
      !rejected.contains(key) && await inner.setInt(key, value);

  @override
  Future<bool> setString(String key, String value) async =>
      !rejected.contains(key) && await inner.setString(key, value);

  @override
  Future<bool> remove(String key) async =>
      !rejected.contains(key) && await inner.remove(key);
}

Future<void> _save(
  XboardSessionStorage storage, {
  String email = 'user@example.com',
  String password = 'private-password',
  String token = 'private-token',
  bool rememberMe = true,
}) => storage.save(
  email: email,
  password: password,
  rememberMe: rememberMe,
  autoLogin: true,
  endpoint: Uri.parse('https://api.example.com'),
  token: token,
  authData: 'Bearer private-auth',
  isAdmin: false,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _SecretStore secrets;
  late XboardSessionStorage storage;
  late List<Map<String, Object?>> diagnostics;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    secrets = _SecretStore();
    diagnostics = [];
    storage = XboardSessionStorage(
      secretStore: secrets,
      onDiagnostic: (event, fields) =>
          diagnostics.add({'event': event, ...fields}),
    );
  });

  test(
    'successful save verifies secrets and never stores a password in preferences',
    () async {
      await _save(storage);
      final preferences = await SharedPreferences.getInstance();
      final values = preferences.getKeys().map(preferences.get).toList();
      expect(values.join(), isNot(contains('private-password')));
      expect(secrets.values['xboard.password'], isNull);
      final credential = jsonDecode(secrets.values['xboard.credentials_v2']!);
      expect(credential, {
        'email': 'user@example.com',
        'password': 'private-password',
      });
      expect((await storage.load()).hasStorageError, isFalse);
    },
  );

  for (final failedKey in ['xboard.token', 'xboard.auth_data']) {
    test(
      '$failedKey write failure keeps independently saved account and password after restart',
      () async {
        secrets.failWrites.add(failedKey);
        await expectLater(
          _save(storage),
          throwsA(isA<XboardStorageException>()),
        );
        final restarted = XboardSessionStorage(secretStore: secrets);
        final stored = await restarted.load();
        expect(stored.rememberMe, isTrue);
        expect(stored.email, 'user@example.com');
        expect(stored.password, 'private-password');
        expect(stored.autoLogin, isFalse);
        expect(stored.canRestore, isFalse);
      },
    );

    test(
      '$failedKey read failure does not erase the password or the other secret',
      () async {
        await _save(storage);
        secrets.failReads.add(failedKey);
        final stored = await storage.load();
        expect(stored.password, 'private-password');
        expect(stored.email, 'user@example.com');
        expect(stored.hasStorageError, isTrue);
        expect(stored.canRestore, isFalse);
        expect(stored.canAutoLogin, isFalse);
        if (failedKey == 'xboard.token') {
          expect(stored.authData, 'Bearer private-auth');
        } else {
          expect(stored.token, 'private-token');
        }
      },
    );
  }

  test(
    'password storage failure retains email and requested remember choice',
    () async {
      secrets.failWrites.add('xboard.credentials_v2');
      await expectLater(_save(storage), throwsA(isA<XboardStorageException>()));
      final stored = await XboardSessionStorage(secretStore: secrets).load();
      expect(stored.rememberMe, isTrue);
      expect(stored.email, 'user@example.com');
      expect(stored.password, isNull);
      expect(stored.canRestore, isFalse);
    },
  );

  test(
    'a new remember request after forget keeps metadata even if password saving fails',
    () async {
      await storage.clear();
      secrets.failWrites.add('xboard.credentials_v2');
      await expectLater(_save(storage), throwsA(isA<XboardStorageException>()));
      final stored = await storage.load();
      expect(stored.rememberMe, isTrue);
      expect(stored.email, 'user@example.com');
      expect(stored.password, isNull);
      expect(stored.hasStorageError, isTrue);
    },
  );

  test(
    'password read error is distinguished from a missing password',
    () async {
      await _save(storage);
      secrets.failReads.add('xboard.credentials_v2');
      final failed = await storage.load();
      expect(failed.hasStorageError, isTrue);
      expect(failed.password, isNull);
      expect(failed.token, 'private-token');
      secrets.failReads.clear();
      secrets.values.remove('xboard.credentials_v2');
      final missing = await storage.load();
      expect(missing.hasStorageError, isFalse);
      expect(missing.password, isNull);
    },
  );

  for (final key in [
    'xboard.credentials_v2',
    'xboard.token',
    'xboard.auth_data',
  ]) {
    test('silent $key write failure is rejected by actual readback', () async {
      secrets.ignoredWrites.add(key);
      await expectLater(
        _save(storage),
        throwsA(
          isA<XboardStorageException>().having(
            (error) => error.errorCode,
            'errorCode',
            'readback_mismatch',
          ),
        ),
      );
      expect((await storage.load()).canRestore, isFalse);
      expect(
        diagnostics.any((event) => event['error_code'] == 'readback_mismatch'),
        isTrue,
      );
    });
  }

  test('legacy password is migrated without changing its whitespace', () async {
    SharedPreferences.setMockInitialValues({
      'xboard.remember_me': true,
      'xboard.email': 'user@example.com',
    });
    secrets.values['xboard.password'] = ' private-password ';
    final stored = await storage.load();
    expect(stored.password, ' private-password ');
    expect(stored.hasStorageError, isFalse);
    expect(secrets.values['xboard.password'], isNull);
    expect(secrets.values['xboard.credentials_v2'], isNotNull);
    expect(
      (await XboardSessionStorage(secretStore: secrets).load()).password,
      ' private-password ',
    );
  });

  test(
    'failed legacy migration preserves the legacy password and exposes its failure',
    () async {
      SharedPreferences.setMockInitialValues({
        'xboard.remember_me': true,
        'xboard.email': 'user@example.com',
      });
      secrets.values['xboard.password'] = 'private-password';
      secrets.failWrites.add('xboard.credentials_v2');
      final stored = await storage.load();
      expect(stored.password, 'private-password');
      expect(stored.hasStorageError, isTrue);
      expect(secrets.values['xboard.password'], 'private-password');
    },
  );

  test(
    'failed new-format read never falls back to an obsolete legacy password',
    () async {
      await _save(storage);
      secrets.values['xboard.password'] = 'obsolete-password';
      secrets.failReads.add('xboard.credentials_v2');
      expect((await storage.load()).password, isNull);
    },
  );

  test(
    'corrupt credentials are reported without deleting the original',
    () async {
      await _save(storage);
      secrets.values['xboard.credentials_v2'] = '{bad json';
      final stored = await storage.load();
      expect(stored.hasStorageError, isTrue);
      expect(stored.password, isNull);
      expect(secrets.values['xboard.credentials_v2'], '{bad json');
    },
  );

  test(
    'same account token login preserves the password case-insensitively',
    () async {
      await _save(storage);
      await _save(
        storage,
        email: ' USER@example.com ',
        password: '',
        token: 'refreshed',
      );
      expect((await storage.load()).password, 'private-password');
    },
  );

  test('another account token login never inherits the old password', () async {
    await _save(storage);
    await _save(storage, email: 'other@example.com', password: '');
    final stored = await storage.load();
    expect(stored.email, 'other@example.com');
    expect(stored.password, isNull);
    expect(stored.canRestoreForEmail('user@example.com'), isFalse);
    expect(stored.canRestoreForEmail('other@example.com'), isTrue);
  });

  test(
    'token login with unreadable credentials never overwrites the stored password',
    () async {
      await _save(storage);
      final original = secrets.values['xboard.credentials_v2'];
      secrets.failReads.add('xboard.credentials_v2');
      await expectLater(
        _save(storage, password: '', token: 'refreshed'),
        throwsA(isA<XboardStorageException>()),
      );
      expect(secrets.values['xboard.credentials_v2'], original);
      secrets.failReads.clear();
      expect((await storage.load()).password, 'private-password');
    },
  );

  test(
    'failed account switch cannot pair the new email with the old password',
    () async {
      await _save(storage);
      secrets.failWrites.add('xboard.credentials_v2');
      await expectLater(
        _save(storage, email: 'other@example.com', password: 'other-password'),
        throwsA(isA<XboardStorageException>()),
      );
      final stored = await XboardSessionStorage(secretStore: secrets).load();
      expect(stored.email, 'other@example.com');
      expect(stored.password, isNull);
      expect(stored.canRestore, isFalse);
    },
  );

  test(
    'same account password write failure keeps the previously verified password after restart',
    () async {
      await _save(storage);
      secrets.failWrites.add('xboard.credentials_v2');
      await expectLater(
        _save(storage, password: 'new-password'),
        throwsA(isA<XboardStorageException>()),
      );
      final restarted = await XboardSessionStorage(secretStore: secrets).load();
      expect(restarted.email, 'user@example.com');
      expect(restarted.password, 'private-password');
      expect(restarted.hasStorageError, isTrue);
      expect(restarted.canRestore, isFalse);
    },
  );

  test(
    'a failed save after explicit forget cannot recover the forgotten password',
    () async {
      await _save(storage);
      secrets.failDeletes.add('xboard.credentials_v2');
      await expectLater(
        storage.clear(),
        throwsA(isA<XboardStorageException>()),
      );
      secrets.failWrites.add('xboard.credentials_v2');
      await expectLater(
        _save(storage, password: 'new-password'),
        throwsA(isA<XboardStorageException>()),
      );
      final restarted = await XboardSessionStorage(secretStore: secrets).load();
      expect(restarted.password, isNull);
      expect(restarted.hasStorageError, isTrue);
    },
  );

  test(
    'preferences email failure cannot attach a new password to the previous email',
    () async {
      await _save(storage);
      final preferences = _RejectingPreferences(
        await SharedPreferences.getInstance(),
      );
      preferences.rejected.add('xboard.email');
      final failing = XboardSessionStorage(
        secretStore: secrets,
        preferencesLoader: () async => preferences,
      );
      await expectLater(
        _save(failing, email: 'other@example.com', password: 'other-password'),
        throwsA(
          isA<XboardStorageException>().having(
            (error) => error.errorCode,
            'errorCode',
            'write_rejected',
          ),
        ),
      );
      final stored = await failing.load();
      expect(stored.email, 'user@example.com');
      expect(stored.password, isNull);
      expect(stored.canRestore, isFalse);
    },
  );

  test(
    'preferences false result while enabling auto login revokes session reuse',
    () async {
      final preferences = _RejectingPreferences(
        await SharedPreferences.getInstance(),
      );
      preferences.rejected.add('xboard.auto_login');
      final failing = XboardSessionStorage(
        secretStore: secrets,
        preferencesLoader: () async => preferences,
      );
      await expectLater(_save(failing), throwsA(isA<XboardStorageException>()));
      final stored = await XboardSessionStorage(secretStore: secrets).load();
      expect(stored.email, 'user@example.com');
      expect(stored.password, 'private-password');
      expect(stored.canRestore, isFalse);
    },
  );

  for (final silent in [false, true]) {
    test(
      'logout with ${silent ? 'silent' : 'throwing'} delete failure blocks stale tokens after restart',
      () async {
        await _save(storage);
        final failures = silent ? secrets.ignoredDeletes : secrets.failDeletes;
        failures.addAll(['xboard.token', 'xboard.auth_data']);
        final remembered = await storage.prepareForLogout();
        expect(remembered.password, 'private-password');
        expect(remembered.hasStorageError, isTrue);
        final restarted = XboardSessionStorage(secretStore: secrets);
        final stored = await restarted.load();
        expect(stored.password, 'private-password');
        expect(stored.rememberMe, isTrue);
        expect(stored.canRestore, isFalse);
        expect(stored.token, isNull);
        await restarted.updateStoredToken(
          'late',
          email: 'user@example.com',
          expectedToken: 'private-token',
        );
        expect(secrets.values['xboard.token'], 'private-token');
        failures.clear();
        final retried = await restarted.prepareForLogout();
        expect(retried.hasStorageError, isFalse);
        expect(secrets.values['xboard.token'], isNull);
      },
    );
  }

  test(
    'logout never deletes password when reading credentials fails',
    () async {
      await _save(storage);
      final original = secrets.values['xboard.credentials_v2'];
      secrets.failReads.add('xboard.credentials_v2');
      final remembered = await storage.prepareForLogout();
      expect(remembered.hasStorageError, isTrue);
      expect(remembered.rememberMe, isTrue);
      expect(remembered.email, 'user@example.com');
      expect(secrets.values['xboard.credentials_v2'], original);
      secrets.failReads.clear();
      expect((await storage.load()).password, 'private-password');
    },
  );

  test(
    'explicit forget failure hides old credentials across restart and can be retried',
    () async {
      await _save(storage);
      secrets.failDeletes.addAll([
        'xboard.credentials_v2',
        'xboard.token',
        'xboard.auth_data',
      ]);
      await expectLater(
        storage.clear(),
        throwsA(isA<XboardStorageException>()),
      );
      final restarted = XboardSessionStorage(secretStore: secrets);
      final forgotten = await restarted.load();
      expect(forgotten.rememberMe, isFalse);
      expect(forgotten.email, isNull);
      expect(forgotten.password, isNull);
      expect(forgotten.canRestore, isFalse);
      expect(forgotten.hasStorageError, isTrue);
      secrets.failDeletes.clear();
      await restarted.clear();
      expect(secrets.values, isEmpty);
      expect((await restarted.load()).hasStorageError, isFalse);
    },
  );

  test(
    'preferences failure while forgetting still deletes the secrets',
    () async {
      await _save(storage);
      final preferences = _RejectingPreferences(
        await SharedPreferences.getInstance(),
      );
      preferences.rejected.add('xboard.remember_me');
      final failing = XboardSessionStorage(
        secretStore: secrets,
        preferencesLoader: () async => preferences,
      );
      await expectLater(
        failing.clear(),
        throwsA(isA<XboardStorageException>()),
      );
      expect((await failing.load()).rememberMe, isFalse);
      expect(secrets.values, isEmpty);
      final restarted = await XboardSessionStorage(secretStore: secrets).load();
      expect(restarted.rememberMe, isFalse);
      expect(restarted.password, isNull);
      expect(restarted.canRestore, isFalse);
    },
  );

  test(
    'token refresh requires the same account and the expected current token',
    () async {
      await _save(storage);
      await storage.updateStoredToken(
        'wrong-account',
        email: 'other@example.com',
        expectedToken: 'private-token',
      );
      await storage.updateStoredToken(
        'stale-token',
        email: 'user@example.com',
        expectedToken: 'older-token',
      );
      expect((await storage.load()).token, 'private-token');
      await storage.updateStoredToken(
        'accepted-token',
        email: 'user@example.com',
        expectedToken: 'private-token',
      );
      expect((await storage.load()).token, 'accepted-token');
    },
  );

  test(
    'logout supersedes a concurrent save session without forgetting its password',
    () async {
      secrets.pausedKey = 'xboard.credentials_v2';
      secrets.writeStarted = Completer<void>();
      secrets.writeRelease = Completer<void>();
      final saving = _save(storage);
      final saveResult = expectLater(
        saving,
        throwsA(isA<XboardStorageException>()),
      );
      await secrets.writeStarted!.future;
      final logout = storage.prepareForLogout();
      secrets.writeRelease!.complete();
      await saveResult;
      final remembered = await logout;
      expect(remembered.password, 'private-password');
      final restarted = await XboardSessionStorage(secretStore: secrets).load();
      expect(restarted.password, 'private-password');
      expect(restarted.canRestore, isFalse);
    },
  );

  test(
    'forget supersedes a concurrent save and removes every persisted credential',
    () async {
      secrets.pausedKey = 'xboard.credentials_v2';
      secrets.writeStarted = Completer<void>();
      secrets.writeRelease = Completer<void>();
      final saving = _save(storage);
      final saveResult = expectLater(
        saving,
        throwsA(isA<XboardStorageException>()),
      );
      await secrets.writeStarted!.future;
      final clearing = storage.clear();
      secrets.writeRelease!.complete();
      await saveResult;
      await clearing;
      expect(secrets.values, isEmpty);
      final restarted = await XboardSessionStorage(secretStore: secrets).load();
      expect(restarted.rememberMe, isFalse);
      expect(restarted.password, isNull);
      expect(restarted.canRestore, isFalse);
    },
  );

  test(
    'diagnostics and thrown errors never contain account or secret values',
    () async {
      secrets.failWrites.add('xboard.credentials_v2');
      Object? failure;
      try {
        await _save(storage);
      } catch (error) {
        failure = error;
      }
      final output = '${jsonEncode(diagnostics)} $failure';
      for (final forbidden in [
        'user@example.com',
        'private-password',
        'private-token',
        'private-auth',
      ]) {
        expect(output, isNot(contains(forbidden)));
      }
      expect(output, contains('write_credentials'));
      expect(output, contains('error_type'));
    },
  );

  test(
    'preference loader errors are reported without leaking error messages',
    () async {
      final failing = XboardSessionStorage(
        secretStore: secrets,
        preferencesLoader: () async => throw StateError('private-password'),
        onDiagnostic: (event, fields) => diagnostics.add(fields),
      );
      final stored = await failing.load();
      expect(stored.hasStorageError, isTrue);
      expect(stored.password, isNull);
      expect(jsonEncode(diagnostics), isNot(contains('private-password')));
      final logout = await failing.prepareForLogout();
      expect(logout.hasStorageError, isTrue);
    },
  );
}

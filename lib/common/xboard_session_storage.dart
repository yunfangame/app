import 'dart:convert';

import 'package:fl_clash/common/xboard_auth.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'local_secret_store.dart';

const xboardOfflineGracePeriod = Duration(days: 3);

class XboardOfflineCache {
  const XboardOfflineCache({
    required this.verifiedAt,
    required this.subscription,
    required this.nodes,
    required this.isAdmin,
    this.secureSubscription = false,
  });

  final DateTime verifiedAt;
  final XboardSubscriptionData subscription;
  final List<XboardNodeData> nodes;
  final bool isAdmin;
  final bool secureSubscription;

  bool isUsableAt(DateTime now) {
    final expiresAt = subscription.expiresAt;
    if (expiresAt != null && !expiresAt.isAfter(now)) return false;
    final age = now.toUtc().difference(verifiedAt.toUtc());
    return !age.isNegative && age <= xboardOfflineGracePeriod;
  }

  XboardLoginResult toSession() {
    return XboardLoginResult(
      endpoint: subscription.endpoint,
      token: '',
      authData: '',
      isAdmin: isAdmin,
      subscription: subscription,
      secureSubscription: secureSubscription,
    );
  }
}

class XboardStoredSession {
  const XboardStoredSession({
    required this.rememberMe,
    required this.autoLogin,
    this.email,
    this.password,
    this.endpoint,
    this.token,
    this.authData,
    this.isAdmin = false,
    this.secureSubscription = false,
    this.hasStorageError = false,
  });

  final bool rememberMe;
  final bool autoLogin;
  final String? email;
  final String? password;
  final Uri? endpoint;
  final String? token;
  final String? authData;
  final bool isAdmin;
  final bool secureSubscription;
  final bool hasStorageError;

  bool get canAutoLogin => autoLogin && canRestore;

  bool get canRestore =>
      !hasStorageError &&
      rememberMe &&
      endpoint != null &&
      (token?.trim().isNotEmpty ?? false) &&
      (authData?.trim().isNotEmpty ?? false);

  bool canRestoreForEmail(String candidate) =>
      canRestore &&
      (email?.trim().isNotEmpty ?? false) &&
      email!.trim().toLowerCase() == candidate.trim().toLowerCase();
}

class XboardStorageException implements Exception {
  const XboardStorageException(this.stage, this.errorCode);

  final String stage;
  final String errorCode;

  @override
  String toString() => 'XboardStorageException($stage, $errorCode)';
}

class XboardSessionStorage {
  XboardSessionStorage({
    FlutterSecureStorage? secureStorage,
    SecretStringStore? secretStore,
    Future<SharedPreferences> Function()? preferencesLoader,
    this.useLocalDebugStorage = false,
    this.onDiagnostic,
  }) : _secureStorage = secureStorage ?? const FlutterSecureStorage(),
       _secretStore = secretStore,
       _preferencesLoader = preferencesLoader ?? SharedPreferences.getInstance;

  static const _rememberMeKey = 'xboard.remember_me';
  static const _autoLoginKey = 'xboard.auto_login';
  static const _emailKey = 'xboard.email';
  static const _endpointKey = 'xboard.endpoint';
  static const _isAdminKey = 'xboard.is_admin';
  static const _secureSubscriptionKey = 'xboard.secure_subscription';
  static const _tokenKey = 'xboard.token';
  static const _authDataKey = 'xboard.auth_data';
  static const _passwordKey = 'xboard.password';
  static const _credentialsKey = 'xboard.credentials_v2';
  static const _credentialsVersionKey = 'xboard.credentials_version';
  static const _credentialsEnabledKey = 'xboard.credentials_enabled';
  static const _sessionEnabledKey = 'xboard.session_enabled';
  static const _sessionAccountKey = 'xboard.session_account';
  static const _cleanupPendingKey = 'xboard.cleanup_pending';
  static const _savePendingKey = 'xboard.save_pending';
  static const _forgetRequestedKey = 'xboard.forget_requested';
  static const _localDebugTokenKey = 'xboard.debug.token';
  static const _localDebugAuthDataKey = 'xboard.debug.auth_data';
  static const _localDebugPasswordKey = 'xboard.debug.password';
  static const _offlineModeKey = 'xboard.offline_mode';
  static const _offlineCacheKey = 'xboard.offline_cache';
  static const _managedProfileUrlKey = 'xboard.managed_profile_url';

  final FlutterSecureStorage _secureStorage;
  final SecretStringStore? _secretStore;
  final Future<SharedPreferences> Function() _preferencesLoader;
  final bool useLocalDebugStorage;
  final void Function(String event, Map<String, Object?> fields)? onDiagnostic;
  Future<void> _queue = Future<void>.value();
  int _revision = 0;
  int _credentialRevision = 0;
  bool _sessionDisabled = false;
  bool _credentialsDisabled = false;

  Future<XboardStoredSession> load() => _serialize(_load);

  Future<XboardStoredSession> _load() async {
    final failures = <XboardStorageException>[];
    SharedPreferences? loadedPreferences;
    await _attempt('load_preferences', failures, () async {
      loadedPreferences = await _preferencesLoader();
    });
    final preferences = loadedPreferences;
    if (preferences == null) {
      return const XboardStoredSession(
        rememberMe: false,
        autoLogin: false,
        hasStorageError: true,
      );
    }
    final rememberMe =
        !_credentialsDisabled &&
        preferences.getBool(_forgetRequestedKey) != true &&
        preferences.getBool(_rememberMeKey) == true;
    final email = rememberMe
        ? _nonEmpty(preferences.getString(_emailKey))
        : null;
    final password = rememberMe && email != null
        ? await _readPassword(preferences, email, failures)
        : null;
    final sessionAccount = preferences.getString(_sessionAccountKey) ?? email;
    final sessionAllowed =
        rememberMe &&
        !_sessionDisabled &&
        preferences.getBool(_sessionEnabledKey) != false &&
        email != null &&
        _sameAccount(sessionAccount, email);
    String? token;
    String? authData;
    if (sessionAllowed) {
      await _attempt('read_token', failures, () async {
        token = _nonEmpty(await _readSecret(preferences, _tokenKey));
      });
      await _attempt('read_auth_data', failures, () async {
        authData = _nonEmpty(await _readSecret(preferences, _authDataKey));
      });
    }
    final endpoint = Uri.tryParse(preferences.getString(_endpointKey) ?? '');
    final validEndpoint =
        sessionAllowed &&
            endpoint != null &&
            {'http', 'https'}.contains(endpoint.scheme) &&
            endpoint.host.isNotEmpty
        ? endpoint
        : null;
    final hasStorageError =
        failures.isNotEmpty ||
        preferences.getBool(_cleanupPendingKey) == true ||
        preferences.getBool(_savePendingKey) == true;
    final autoLogin =
        !hasStorageError &&
        preferences.getBool(_autoLoginKey) == true &&
        rememberMe &&
        validEndpoint != null &&
        token != null &&
        authData != null;
    final stored = XboardStoredSession(
      rememberMe: rememberMe,
      autoLogin: autoLogin,
      email: email,
      password: password,
      endpoint: validEndpoint,
      token: token,
      authData: authData,
      isAdmin: preferences.getBool(_isAdminKey) ?? false,
      secureSubscription: preferences.getBool(_secureSubscriptionKey) ?? false,
      hasStorageError: hasStorageError,
    );
    _diagnostic('credentials_load', {
      'has_error': stored.hasStorageError,
      'remember_me': stored.rememberMe,
      'auto_login': stored.autoLogin,
      'has_email': stored.email != null,
      'has_password': stored.password != null,
      'has_session': stored.canRestore,
    });
    return stored;
  }

  Future<void> save({
    required String email,
    required String password,
    required bool rememberMe,
    required bool autoLogin,
    required Uri endpoint,
    required String token,
    required String authData,
    required bool isAdmin,
    bool secureSubscription = false,
  }) {
    if (!rememberMe) {
      return clear();
    }
    final revision = ++_revision;
    final credentialRevision = ++_credentialRevision;
    _sessionDisabled = true;
    return _serialize(() async {
      final failures = <XboardStorageException>[];
      final preferences = await _preferences('save_preferences');
      await _attempt('mark_save_pending', failures, () async {
        await _checkPreference(preferences.setBool(_savePendingKey, true));
      });
      _diagnostic('credentials_save_requested', {
        'remember_me': rememberMe,
        'auto_login': autoLogin,
        'has_email': email.trim().isNotEmpty,
        'has_password': password.isNotEmpty,
      });
      final allowExistingCredentials =
          !_credentialsDisabled &&
          preferences.getBool(_forgetRequestedKey) != true &&
          preferences.getBool(_rememberMeKey) == true &&
          preferences.getBool(_credentialsEnabledKey) != false &&
          _sameAccount(preferences.getString(_emailKey), email);
      var savedPassword = password.isEmpty ? null : password;
      var preserveUnreadableCredentials = false;
      if (savedPassword == null &&
          preferences.getBool(_rememberMeKey) == true &&
          _sameAccount(preferences.getString(_emailKey), email)) {
        final failuresBeforeRead = failures.length;
        savedPassword = await _readPassword(preferences, email, failures);
        preserveUnreadableCredentials =
            savedPassword == null && failures.length > failuresBeforeRead;
      }
      await _disableSession(preferences, failures);
      var metadataSaved = await _attempt('save_email', failures, () async {
        await _checkPreference(preferences.setString(_emailKey, email.trim()));
      });
      metadataSaved =
          await _attempt('save_remember_me', failures, () async {
            await _checkPreference(preferences.setBool(_rememberMeKey, true));
          }) &&
          metadataSaved;
      metadataSaved =
          await _attempt('save_remember_intent', failures, () async {
            await _checkPreference(
              preferences.setBool(_forgetRequestedKey, false),
            );
          }) &&
          metadataSaved;
      if (metadataSaved && credentialRevision == _credentialRevision) {
        _credentialsDisabled = false;
      }
      var credentialSaved = false;
      if (!preserveUnreadableCredentials) {
        await _attempt('disable_credentials', failures, () async {
          await _checkPreference(
            preferences.setBool(_credentialsEnabledKey, false),
          );
        });
        final versionSaved = await _attempt(
          'save_credentials_version',
          failures,
          () async {
            await _checkPreference(
              preferences.setInt(_credentialsVersionKey, 2),
            );
          },
        );
        credentialSaved = await _attempt(
          'write_credentials',
          failures,
          () async {
            await _writeVerifiedSecret(
              preferences,
              _credentialsKey,
              jsonEncode({'email': email.trim(), 'password': savedPassword}),
            );
          },
        );
        if (metadataSaved &&
            versionSaved &&
            credentialSaved &&
            credentialRevision == _credentialRevision) {
          final enabled = await _attempt(
            'enable_credentials',
            failures,
            () async {
              await _checkPreference(
                preferences.setBool(_credentialsEnabledKey, true),
              );
            },
          );
          if (enabled) _credentialsDisabled = false;
          await _attempt('delete_legacy_password', failures, () async {
            await _deleteVerifiedSecret(preferences, _passwordKey);
          });
        } else if (!credentialSaved &&
            allowExistingCredentials &&
            metadataSaved &&
            versionSaved &&
            credentialRevision == _credentialRevision) {
          await _attempt('recover_account_credentials', failures, () async {
            final source = await _readSecret(preferences, _credentialsKey);
            if (source == null) return;
            final decoded = jsonDecode(source);
            if (decoded is! Map<String, dynamic> ||
                decoded['email'] is! String ||
                !_sameAccount(decoded['email'] as String, email) ||
                decoded['password'] is! String ||
                (decoded['password'] as String).isEmpty) {
              return;
            }
            await _checkPreference(
              preferences.setBool(_credentialsEnabledKey, true),
            );
          });
        }
      }
      await _attempt('write_token', failures, () async {
        await _writeVerifiedSecret(preferences, _tokenKey, token);
      });
      await _attempt('write_auth_data', failures, () async {
        await _writeVerifiedSecret(preferences, _authDataKey, authData);
      });
      await _attempt('save_session_metadata', failures, () async {
        await _checkPreference(
          preferences.setString(_sessionAccountKey, email.trim()),
        );
        await _checkPreference(
          preferences.setString(_endpointKey, endpoint.toString()),
        );
        await _checkPreference(preferences.setBool(_isAdminKey, isAdmin));
        await _checkPreference(
          preferences.setBool(_secureSubscriptionKey, secureSubscription),
        );
      });
      if (failures.isEmpty && revision == _revision) {
        await _attempt('enable_session', failures, () async {
          await _checkPreference(
            preferences.setBool(_cleanupPendingKey, false),
          );
          await _checkPreference(preferences.setBool(_savePendingKey, false));
          await _checkPreference(preferences.setBool(_sessionEnabledKey, true));
          await _checkPreference(preferences.setBool(_autoLoginKey, autoLogin));
        });
      }
      if (failures.isNotEmpty || revision != _revision) {
        await _disableSession(preferences, failures);
        await _attempt('record_save_failure', failures, () async {
          await _checkPreference(preferences.setBool(_savePendingKey, true));
        });
        if (failures.isEmpty) {
          failures.add(const XboardStorageException('save', 'superseded'));
        }
      } else {
        _sessionDisabled = false;
      }
      _diagnostic('credentials_save_completed', {
        'has_error': failures.isNotEmpty,
        'has_password': savedPassword != null && credentialSaved,
        'has_session': !_sessionDisabled,
      });
      _throwFirst(failures);
    });
  }

  Future<void> clearInvalidSession() {
    ++_revision;
    _sessionDisabled = true;
    return _serialize(() async {
      final failures = <XboardStorageException>[];
      final preferences = await _preferences('revoke_preferences');
      await _revokeSession(preferences, failures);
      _throwFirst(failures);
    });
  }

  Future<XboardStoredSession> prepareForLogout() {
    ++_revision;
    _sessionDisabled = true;
    return _serialize(() async {
      final failures = <XboardStorageException>[];
      await _attempt('logout_cleanup', failures, () async {
        final preferences = await _preferences('logout_preferences');
        await _revokeSession(preferences, failures);
      });
      final stored = await _load();
      final result = XboardStoredSession(
        rememberMe: stored.rememberMe,
        autoLogin: false,
        email: stored.email,
        password: stored.password,
        hasStorageError: failures.isNotEmpty || stored.hasStorageError,
      );
      _diagnostic('credentials_logout_completed', {
        'has_error': result.hasStorageError,
        'remember_me': result.rememberMe,
        'has_email': result.email != null,
        'has_password': result.password != null,
      });
      return result;
    });
  }

  Future<void> disableAutoLogin() => _serialize(() async {
    final preferences = await _preferences('disable_auto_login_preferences');
    final failures = <XboardStorageException>[];
    await _attempt('disable_auto_login', failures, () async {
      await _checkPreference(preferences.setBool(_autoLoginKey, false));
    });
    _throwFirst(failures);
  });

  Future<void> updateStoredToken(
    String token, {
    required String email,
    required String expectedToken,
  }) {
    final revision = _revision;
    return _serialize(() async {
      if (revision != _revision || _sessionDisabled || token.trim().isEmpty) {
        return;
      }
      final stored = await _load();
      if (revision != _revision ||
          _sessionDisabled ||
          !stored.canRestoreForEmail(email) ||
          stored.token != expectedToken) {
        _diagnostic('credentials_token_refresh_skipped', {
          'reason': 'session_changed',
        });
        return;
      }
      final preferences = await _preferences('refresh_preferences');
      final failures = <XboardStorageException>[];
      await _attempt('refresh_token', failures, () async {
        await _writeVerifiedSecret(preferences, _tokenKey, token.trim());
      });
      if (failures.isNotEmpty) {
        _sessionDisabled = true;
        await _disableSession(preferences, failures);
      }
      _throwFirst(failures);
    });
  }

  Future<bool> loadOfflineMode() async {
    final preferences = await _preferencesLoader();
    return preferences.getBool(_offlineModeKey) ?? false;
  }

  Future<void> setOfflineMode(bool value) async {
    final preferences = await _preferencesLoader();
    await _checkPreference(preferences.setBool(_offlineModeKey, value));
  }

  Future<void> saveOfflineCache({
    required XboardLoginResult session,
    required List<XboardNodeData> nodes,
    DateTime? verifiedAt,
  }) async {
    final preferences = await _preferencesLoader();
    final payload = <String, Object?>{
      'verified_at': (verifiedAt ?? DateTime.now()).toUtc().toIso8601String(),
      'is_admin': session.isAdmin,
      'secure_subscription': session.secureSubscription,
      'subscription': _subscriptionToJson(session.subscription),
      'nodes': nodes.map(_nodeToJson).toList(growable: false),
    };
    await _checkPreference(
      preferences.setString(_offlineCacheKey, jsonEncode(payload)),
    );
  }

  Future<XboardOfflineCache?> loadOfflineCache() async {
    final preferences = await _preferencesLoader();
    final source = preferences.getString(_offlineCacheKey);
    if (source == null || source.isEmpty) return null;
    try {
      final decoded = jsonDecode(source);
      if (decoded is! Map) return null;
      final data = decoded.map((key, value) => MapEntry(key.toString(), value));
      final verifiedAt = DateTime.tryParse(
        data['verified_at']?.toString() ?? '',
      );
      final subscription = _subscriptionFromJson(data['subscription']);
      if (verifiedAt == null || subscription == null) return null;
      final rawNodes = data['nodes'];
      final nodes = rawNodes is List
          ? rawNodes.map(_nodeFromJson).whereType<XboardNodeData>().toList()
          : <XboardNodeData>[];
      return XboardOfflineCache(
        verifiedAt: verifiedAt,
        subscription: subscription,
        nodes: List.unmodifiable(nodes),
        isAdmin: data['is_admin'] == true,
        secureSubscription: data['secure_subscription'] == true,
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> clearOfflineCache() async {
    final preferences = await _preferencesLoader();
    await _checkPreference(preferences.remove(_offlineModeKey));
    await _checkPreference(preferences.remove(_offlineCacheKey));
  }

  Future<String?> loadManagedProfileUrl() async {
    final preferences = await _preferencesLoader();
    return _nonEmpty(preferences.getString(_managedProfileUrlKey));
  }

  Future<void> setManagedProfileUrl(String url) async {
    final preferences = await _preferencesLoader();
    await _checkPreference(preferences.setString(_managedProfileUrlKey, url));
  }

  Future<void> clearManagedProfileUrl() async {
    final preferences = await _preferencesLoader();
    await _checkPreference(preferences.remove(_managedProfileUrlKey));
  }

  Future<void> clear() {
    ++_revision;
    ++_credentialRevision;
    _credentialsDisabled = true;
    _sessionDisabled = true;
    return _serialize(() async {
      final failures = <XboardStorageException>[];
      final preferences = await _preferences('forget_preferences');
      await _attempt('forget_intent', failures, () async {
        await _checkPreference(preferences.setBool(_forgetRequestedKey, true));
      });
      await _attempt('forget_remember_me', failures, () async {
        await _checkPreference(preferences.setBool(_rememberMeKey, false));
      });
      await _attempt('forget_credentials', failures, () async {
        await _checkPreference(
          preferences.setBool(_credentialsEnabledKey, false),
        );
      });
      await _attempt('forget_legacy_migration', failures, () async {
        await _checkPreference(preferences.setInt(_credentialsVersionKey, 2));
      });
      await _attempt('forget_email', failures, () async {
        await _checkPreference(preferences.remove(_emailKey));
      });
      await _attempt('forget_save_state', failures, () async {
        await _checkPreference(preferences.setBool(_savePendingKey, false));
      });
      await _revokeSession(preferences, failures);
      for (final key in [_credentialsKey, _passwordKey]) {
        await _attempt('forget_secret', failures, () async {
          await _deleteVerifiedSecret(preferences, key);
        });
      }
      await _recordCleanupPending(preferences, failures);
      _diagnostic('credentials_forget_completed', {
        'has_error': failures.isNotEmpty,
      });
      _throwFirst(failures);
    });
  }

  Future<void> _disableSession(
    SharedPreferences preferences,
    List<XboardStorageException> failures,
  ) async {
    await _attempt('disable_session', failures, () async {
      await _checkPreference(preferences.setBool(_sessionEnabledKey, false));
    });
    await _attempt('disable_auto_login', failures, () async {
      await _checkPreference(preferences.setBool(_autoLoginKey, false));
    });
  }

  Future<void> _revokeSession(
    SharedPreferences preferences,
    List<XboardStorageException> failures,
  ) async {
    await _disableSession(preferences, failures);
    for (final key in [
      _endpointKey,
      _sessionAccountKey,
      _isAdminKey,
      _secureSubscriptionKey,
    ]) {
      await _attempt('revoke_session_metadata', failures, () async {
        await _checkPreference(preferences.remove(key));
      });
    }
    for (final key in [_tokenKey, _authDataKey]) {
      await _attempt('revoke_session_secret', failures, () async {
        await _deleteVerifiedSecret(preferences, key);
      });
    }
    await _recordCleanupPending(preferences, failures);
  }

  Future<void> _recordCleanupPending(
    SharedPreferences preferences,
    List<XboardStorageException> failures,
  ) async {
    await _attempt('record_cleanup_result', failures, () async {
      await _checkPreference(
        preferences.setBool(_cleanupPendingKey, failures.isNotEmpty),
      );
    });
  }

  Future<String?> _readPassword(
    SharedPreferences preferences,
    String email,
    List<XboardStorageException> failures,
  ) async {
    if (preferences.getBool(_credentialsEnabledKey) == false) return null;
    String? source;
    final read = await _attempt('read_credentials', failures, () async {
      source = await _readSecret(preferences, _credentialsKey);
    });
    if (!read) return null;
    if (source != null) {
      String? password;
      await _attempt('decode_credentials', failures, () async {
        final decoded = jsonDecode(source!);
        if (decoded is! Map<String, dynamic> ||
            decoded['email'] is! String ||
            (decoded['password'] != null && decoded['password'] is! String)) {
          throw const XboardStorageException(
            'decode_credentials',
            'invalid_format',
          );
        }
        if (!_sameAccount(decoded['email'] as String, email)) return;
        final saved = decoded['password'] as String?;
        password = saved == null || saved.isEmpty ? null : saved;
      });
      return password;
    }
    if (preferences.getInt(_credentialsVersionKey) == 2) return null;
    String? legacyPassword;
    await _attempt('read_legacy_password', failures, () async {
      legacyPassword = await _readSecret(preferences, _passwordKey);
    });
    if (legacyPassword == null || legacyPassword!.isEmpty) return null;
    final migrated = await _attempt('migrate_credentials', failures, () async {
      await _writeVerifiedSecret(
        preferences,
        _credentialsKey,
        jsonEncode({'email': email.trim(), 'password': legacyPassword}),
      );
      await _checkPreference(preferences.setInt(_credentialsVersionKey, 2));
      await _checkPreference(preferences.setBool(_credentialsEnabledKey, true));
    });
    if (migrated) {
      await _attempt('delete_legacy_password', failures, () async {
        await _deleteVerifiedSecret(preferences, _passwordKey);
      });
    }
    return legacyPassword;
  }

  Future<void> _writeVerifiedSecret(
    SharedPreferences preferences,
    String key,
    String value,
  ) async {
    await _writeSecret(preferences, key, value);
    if (await _readSecret(preferences, key) != value) {
      throw const XboardStorageException('verify_write', 'readback_mismatch');
    }
  }

  Future<void> _deleteVerifiedSecret(
    SharedPreferences preferences,
    String key,
  ) async {
    await _deleteSecret(preferences, key);
    if (await _readSecret(preferences, key) != null) {
      throw const XboardStorageException('verify_delete', 'readback_mismatch');
    }
  }

  Future<SharedPreferences> _preferences(String stage) async {
    try {
      return await _preferencesLoader();
    } catch (error) {
      final failure = _storageFailure(stage, error);
      _reportFailure(failure, error);
      throw failure;
    }
  }

  Future<void> _checkPreference(Future<bool> operation) async {
    if (!await operation) {
      throw const XboardStorageException('write_preferences', 'write_rejected');
    }
  }

  Future<bool> _attempt(
    String stage,
    List<XboardStorageException> failures,
    Future<void> Function() operation,
  ) async {
    try {
      await operation();
      return true;
    } catch (error) {
      final failure = _storageFailure(stage, error);
      failures.add(failure);
      _reportFailure(failure, error);
      return false;
    }
  }

  XboardStorageException _storageFailure(String stage, Object error) {
    final code = error is XboardStorageException
        ? error.errorCode
        : error is PlatformException &&
              (RegExp(r'^-?\d{1,10}$').hasMatch(error.code) ||
                  const {
                    'storage_error',
                    'read_error',
                    'write_error',
                    'delete_error',
                    'read_failed',
                    'write_failed',
                    'delete_failed',
                    'access_denied',
                    'not_available',
                    'not_found',
                    'keychain_error',
                    'Error',
                  }.contains(error.code))
        ? error.code
        : 'storage_unavailable';
    return XboardStorageException(stage, code);
  }

  void _reportFailure(XboardStorageException failure, Object error) {
    _diagnostic('credentials_storage_error', {
      'stage': failure.stage,
      'error_code': failure.errorCode,
      'error_type': error.runtimeType.toString(),
    });
  }

  void _diagnostic(String event, Map<String, Object?> fields) {
    try {
      onDiagnostic?.call(event, fields);
    } catch (_) {}
  }

  void _throwFirst(List<XboardStorageException> failures) {
    if (failures.isNotEmpty) throw failures.first;
  }

  Future<T> _serialize<T>(Future<T> Function() operation) {
    final result = _queue.then((_) => operation());
    _queue = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }

  bool _sameAccount(String? left, String right) =>
      left != null && left.trim().toLowerCase() == right.trim().toLowerCase();

  Future<String?> _readSecret(SharedPreferences preferences, String key) {
    if (_secretStore != null) return _secretStore.read(key);
    if (useLocalDebugStorage) {
      return Future.value(preferences.getString(_localDebugKey(key)));
    }
    return _secureStorage.read(key: key);
  }

  Future<void> _writeSecret(
    SharedPreferences preferences,
    String key,
    String value,
  ) async {
    if (_secretStore != null) {
      await _secretStore.write(key, value);
      return;
    }
    if (useLocalDebugStorage) {
      await _checkPreference(preferences.setString(_localDebugKey(key), value));
      return;
    }
    await _secureStorage.write(key: key, value: value);
  }

  Future<void> _deleteSecret(SharedPreferences preferences, String key) async {
    if (_secretStore != null) {
      await _secretStore.delete(key);
      return;
    }
    if (useLocalDebugStorage) {
      await _checkPreference(preferences.remove(_localDebugKey(key)));
      return;
    }
    await _secureStorage.delete(key: key);
  }

  String _localDebugKey(String key) => switch (key) {
    _tokenKey => _localDebugTokenKey,
    _authDataKey => _localDebugAuthDataKey,
    _passwordKey => _localDebugPasswordKey,
    _credentialsKey => 'xboard.debug.credentials_v2',
    _ => throw ArgumentError.value(key, 'key'),
  };
}

Map<String, Object?> _subscriptionToJson(XboardSubscriptionData value) {
  return {
    'endpoint': value.endpoint.toString(),
    'subscribe_url': value.subscribeUrl?.toString(),
    'u': value.uploadBytes,
    'd': value.downloadBytes,
    'transfer_enable': value.transferEnableBytes,
    'plan_id': value.planId,
    'token': value.token,
    'email': value.email,
    'uuid': value.uuid,
    'expired_at': value.expiredAtEpochSeconds,
    'device_limit': value.deviceLimit,
    'speed_limit': value.speedLimit,
    'next_reset_at': value.nextResetAtEpochSeconds,
    'reset_day': value.resetDay,
    'plan': value.plan == null
        ? null
        : {
            'id': value.plan!.id,
            'name': value.plan!.name,
            'transfer_enable': value.plan!.transferEnableBytes,
          },
  };
}

XboardSubscriptionData? _subscriptionFromJson(Object? source) {
  if (source is! Map) return null;
  final data = source.map((key, value) => MapEntry(key.toString(), value));
  final endpoint = Uri.tryParse(data['endpoint']?.toString() ?? '');
  final subscribeUrlText = data['subscribe_url']?.toString() ?? '';
  final subscribeUrl = subscribeUrlText.isEmpty
      ? null
      : Uri.tryParse(subscribeUrlText);
  if (endpoint == null ||
      (subscribeUrlText.isNotEmpty && subscribeUrl == null)) {
    return null;
  }
  final rawPlan = data['plan'];
  final planData = rawPlan is Map
      ? rawPlan.map((key, value) => MapEntry(key.toString(), value))
      : null;
  return XboardSubscriptionData(
    endpoint: endpoint,
    subscribeUrl: subscribeUrl,
    uploadBytes: _asInt(data['u']) ?? 0,
    downloadBytes: _asInt(data['d']) ?? 0,
    transferEnableBytes: _asInt(data['transfer_enable']) ?? 0,
    planId: _asInt(data['plan_id']),
    token: _nonEmpty(data['token']?.toString()),
    email: _nonEmpty(data['email']?.toString()),
    uuid: _nonEmpty(data['uuid']?.toString()),
    expiredAtEpochSeconds: _asInt(data['expired_at']),
    deviceLimit: _asInt(data['device_limit']),
    speedLimit: _asInt(data['speed_limit']),
    nextResetAtEpochSeconds: _asInt(data['next_reset_at']),
    resetDay: _asInt(data['reset_day']),
    plan: planData == null
        ? null
        : XboardPlanData(
            id: _asInt(planData['id']),
            name: _nonEmpty(planData['name']?.toString()),
            transferEnableBytes: _asInt(planData['transfer_enable']),
            rawData: const {},
          ),
    rawData: const {},
  );
}

Map<String, Object?> _nodeToJson(XboardNodeData value) {
  return {
    'id': value.id,
    'name': value.name,
    'type': value.type,
    'rate': value.rate,
    'tags': value.tags,
    'online': value.isOnline,
  };
}

XboardNodeData? _nodeFromJson(Object? source) {
  if (source is! Map) return null;
  final data = source.map((key, value) => MapEntry(key.toString(), value));
  final name = _nonEmpty(data['name']?.toString());
  final type = _nonEmpty(data['type']?.toString());
  if (name == null || type == null) return null;
  final rawTags = data['tags'];
  return XboardNodeData(
    id: _asInt(data['id']),
    name: name,
    type: type,
    rate: data['rate'] is num ? (data['rate'] as num).toDouble() : 1,
    tags: rawTags is List
        ? rawTags.map((value) => value.toString()).toList(growable: false)
        : const [],
    isOnline: data['online'] != false,
    rawData: const {},
  );
}

int? _asInt(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '');
}

String? _nonEmpty(String? value) {
  final normalized = value?.trim() ?? '';
  return normalized.isEmpty ? null : normalized;
}

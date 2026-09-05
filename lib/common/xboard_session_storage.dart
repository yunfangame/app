import 'dart:convert';

import 'package:fl_clash/common/xboard_auth.dart';
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

  bool get canAutoLogin => autoLogin && canRestore;

  bool get canRestore =>
      rememberMe &&
      endpoint != null &&
      (token?.trim().isNotEmpty ?? false) &&
      (authData?.trim().isNotEmpty ?? false);

  bool canRestoreForEmail(String candidate) =>
      canRestore &&
      (email?.trim().isNotEmpty ?? false) &&
      email!.trim().toLowerCase() == candidate.trim().toLowerCase();
}

class XboardSessionStorage {
  XboardSessionStorage({
    FlutterSecureStorage? secureStorage,
    SecretStringStore? secretStore,
    Future<SharedPreferences> Function()? preferencesLoader,
    this.useLocalDebugStorage = false,
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

  Future<XboardStoredSession> load() async {
    final preferences = await _preferencesLoader();
    final rememberMe = preferences.getBool(_rememberMeKey) ?? false;
    final requestedAutoLogin = preferences.getBool(_autoLoginKey) ?? false;
    String? token;
    String? authData;
    String? password;
    try {
      final secrets = await Future.wait([
        _readSecret(preferences, _tokenKey),
        _readSecret(preferences, _authDataKey),
        _readSecret(preferences, _passwordKey),
      ]);
      token = _nonEmpty(secrets[0]);
      authData = _nonEmpty(secrets[1]);
      password = secrets[2]?.isEmpty ?? true ? null : secrets[2];
    } catch (_) {
      token = null;
      authData = null;
      password = null;
    }
    final endpoint = Uri.tryParse(preferences.getString(_endpointKey) ?? '');
    final validEndpoint =
        endpoint != null &&
            {'http', 'https'}.contains(endpoint.scheme) &&
            endpoint.host.isNotEmpty
        ? endpoint
        : null;
    final autoLogin =
        requestedAutoLogin &&
        rememberMe &&
        validEndpoint != null &&
        token != null &&
        authData != null;
    return XboardStoredSession(
      rememberMe: rememberMe,
      autoLogin: autoLogin,
      email: _nonEmpty(preferences.getString(_emailKey)),
      password: password,
      endpoint: validEndpoint,
      token: token,
      authData: authData,
      isAdmin: preferences.getBool(_isAdminKey) ?? false,
      secureSubscription: preferences.getBool(_secureSubscriptionKey) ?? false,
    );
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
  }) async {
    if (!rememberMe) {
      await clear();
      return;
    }
    final preferences = await _preferencesLoader();
    await preferences.setBool(_autoLoginKey, false);
    await _writeSecret(preferences, _tokenKey, token);
    await _writeSecret(preferences, _authDataKey, authData);
    if (password.isNotEmpty) {
      await _writeSecret(preferences, _passwordKey, password);
    }
    await preferences.setString(_emailKey, email.trim());
    await preferences.setString(_endpointKey, endpoint.toString());
    await preferences.setBool(_isAdminKey, isAdmin);
    await preferences.setBool(_secureSubscriptionKey, secureSubscription);
    await preferences.setBool(_rememberMeKey, true);
    await preferences.setBool(_autoLoginKey, autoLogin);
  }

  Future<void> clearInvalidSession() async {
    await _deleteSessionSecretsBestEffort();
    final preferences = await _preferencesLoader();
    await preferences.setBool(_autoLoginKey, false);
    await preferences.remove(_endpointKey);
    await preferences.remove(_isAdminKey);
    await preferences.remove(_secureSubscriptionKey);
  }

  Future<XboardStoredSession> prepareForLogout() async {
    final stored = await load();
    if (!stored.rememberMe) {
      await clear();
      return const XboardStoredSession(rememberMe: false, autoLogin: false);
    }
    await clearInvalidSession();
    return XboardStoredSession(
      rememberMe: true,
      autoLogin: false,
      email: stored.email,
      password: stored.password,
    );
  }

  Future<void> disableAutoLogin() async {
    final preferences = await _preferencesLoader();
    await preferences.setBool(_autoLoginKey, false);
  }

  Future<void> updateStoredToken(String token) async {
    final preferences = await _preferencesLoader();
    if (preferences.getBool(_rememberMeKey) != true || token.trim().isEmpty) {
      return;
    }
    await _writeSecret(preferences, _tokenKey, token.trim());
  }

  Future<bool> loadOfflineMode() async {
    final preferences = await _preferencesLoader();
    return preferences.getBool(_offlineModeKey) ?? false;
  }

  Future<void> setOfflineMode(bool value) async {
    final preferences = await _preferencesLoader();
    await preferences.setBool(_offlineModeKey, value);
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
    await preferences.setString(_offlineCacheKey, jsonEncode(payload));
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
    await preferences.remove(_offlineModeKey);
    await preferences.remove(_offlineCacheKey);
  }

  Future<String?> loadManagedProfileUrl() async {
    final preferences = await _preferencesLoader();
    return _nonEmpty(preferences.getString(_managedProfileUrlKey));
  }

  Future<void> setManagedProfileUrl(String url) async {
    final preferences = await _preferencesLoader();
    await preferences.setString(_managedProfileUrlKey, url);
  }

  Future<void> clearManagedProfileUrl() async {
    final preferences = await _preferencesLoader();
    await preferences.remove(_managedProfileUrlKey);
  }

  Future<void> clear() async {
    await _deleteSessionSecretsBestEffort();
    final preferences = await _preferencesLoader();
    try {
      await _deleteSecret(preferences, _passwordKey);
    } catch (_) {}
    await preferences.remove(_rememberMeKey);
    await preferences.remove(_autoLoginKey);
    await preferences.remove(_emailKey);
    await preferences.remove(_endpointKey);
    await preferences.remove(_isAdminKey);
    await preferences.remove(_secureSubscriptionKey);
  }

  Future<void> _deleteSessionSecretsBestEffort() async {
    final preferences = await _preferencesLoader();
    try {
      await _deleteSecret(preferences, _tokenKey);
    } catch (_) {}
    try {
      await _deleteSecret(preferences, _authDataKey);
    } catch (_) {}
  }

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
      await preferences.setString(_localDebugKey(key), value);
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
      await preferences.remove(_localDebugKey(key));
      return;
    }
    await _secureStorage.delete(key: key);
  }

  String _localDebugKey(String key) => switch (key) {
    _tokenKey => _localDebugTokenKey,
    _authDataKey => _localDebugAuthDataKey,
    _passwordKey => _localDebugPasswordKey,
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

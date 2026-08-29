import 'dart:convert';

import 'package:fl_clash/common/xboard_auth.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

const xboardOfflineGracePeriod = Duration(days: 3);

class XboardOfflineCache {
  const XboardOfflineCache({
    required this.verifiedAt,
    required this.subscription,
    required this.nodes,
    required this.isAdmin,
  });

  final DateTime verifiedAt;
  final XboardSubscriptionData subscription;
  final List<XboardNodeData> nodes;
  final bool isAdmin;

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
    );
  }
}

class XboardStoredSession {
  const XboardStoredSession({
    required this.rememberMe,
    required this.autoLogin,
    this.email,
    this.endpoint,
    this.token,
    this.authData,
    this.isAdmin = false,
  });

  final bool rememberMe;
  final bool autoLogin;
  final String? email;
  final Uri? endpoint;
  final String? token;
  final String? authData;
  final bool isAdmin;

  bool get canAutoLogin =>
      rememberMe &&
      autoLogin &&
      endpoint != null &&
      token != null &&
      authData != null;

  bool get canRestore =>
      rememberMe && endpoint != null && token != null && authData != null;
}

class XboardSessionStorage {
  XboardSessionStorage({
    FlutterSecureStorage? secureStorage,
    Future<SharedPreferences> Function()? preferencesLoader,
  }) : _secureStorage = secureStorage ?? const FlutterSecureStorage(),
       _preferencesLoader = preferencesLoader ?? SharedPreferences.getInstance;

  static const _rememberMeKey = 'xboard.remember_me';
  static const _autoLoginKey = 'xboard.auto_login';
  static const _emailKey = 'xboard.email';
  static const _endpointKey = 'xboard.endpoint';
  static const _isAdminKey = 'xboard.is_admin';
  static const _tokenKey = 'xboard.token';
  static const _authDataKey = 'xboard.auth_data';
  static const _offlineModeKey = 'xboard.offline_mode';
  static const _offlineCacheKey = 'xboard.offline_cache';
  static const _managedProfileUrlKey = 'xboard.managed_profile_url';

  final FlutterSecureStorage _secureStorage;
  final Future<SharedPreferences> Function() _preferencesLoader;

  Future<XboardStoredSession> load() async {
    final preferences = await _preferencesLoader();
    final rememberMe = preferences.getBool(_rememberMeKey) ?? false;
    final requestedAutoLogin = preferences.getBool(_autoLoginKey) ?? false;
    String? token;
    String? authData;
    try {
      final secrets = await Future.wait([
        _secureStorage.read(key: _tokenKey),
        _secureStorage.read(key: _authDataKey),
      ]);
      token = _nonEmpty(secrets[0]);
      authData = _nonEmpty(secrets[1]);
    } catch (_) {
      token = null;
      authData = null;
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
      endpoint: validEndpoint,
      token: token,
      authData: authData,
      isAdmin: preferences.getBool(_isAdminKey) ?? false,
    );
  }

  Future<void> save({
    required String email,
    required bool rememberMe,
    required bool autoLogin,
    required Uri endpoint,
    required String token,
    required String authData,
    required bool isAdmin,
  }) async {
    if (!rememberMe) {
      await clear();
      return;
    }
    final preferences = await _preferencesLoader();
    await preferences.setBool(_autoLoginKey, false);
    await _secureStorage.write(key: _tokenKey, value: token);
    await _secureStorage.write(key: _authDataKey, value: authData);
    await preferences.setString(_emailKey, email.trim());
    await preferences.setString(_endpointKey, endpoint.toString());
    await preferences.setBool(_isAdminKey, isAdmin);
    await preferences.setBool(_rememberMeKey, true);
    await preferences.setBool(_autoLoginKey, autoLogin);
  }

  Future<void> clearInvalidSession() async {
    await _deleteSecretsBestEffort();
    final preferences = await _preferencesLoader();
    await preferences.setBool(_autoLoginKey, false);
    await preferences.remove(_endpointKey);
    await preferences.remove(_isAdminKey);
  }

  Future<void> disableAutoLogin() async {
    final preferences = await _preferencesLoader();
    await preferences.setBool(_autoLoginKey, false);
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
    await _deleteSecretsBestEffort();
    final preferences = await _preferencesLoader();
    await preferences.remove(_rememberMeKey);
    await preferences.remove(_autoLoginKey);
    await preferences.remove(_emailKey);
    await preferences.remove(_endpointKey);
    await preferences.remove(_isAdminKey);
  }

  Future<void> _deleteSecretsBestEffort() async {
    try {
      await _secureStorage.delete(key: _tokenKey);
    } catch (_) {}
    try {
      await _secureStorage.delete(key: _authDataKey);
    } catch (_) {}
  }
}

Map<String, Object?> _subscriptionToJson(XboardSubscriptionData value) {
  return {
    'endpoint': value.endpoint.toString(),
    'subscribe_url': value.subscribeUrl.toString(),
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
  final subscribeUrl = Uri.tryParse(data['subscribe_url']?.toString() ?? '');
  if (endpoint == null || subscribeUrl == null) return null;
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

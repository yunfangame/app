import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class ApiRemoteConfigCacheStore {
  ApiRemoteConfigCacheStore({
    Future<SharedPreferences> Function()? preferencesLoader,
    String? namespace,
    bool allowLegacyFallback = false,
    bool clearInvalidOnLoad = true,
  }) : _preferencesLoader = preferencesLoader ?? SharedPreferences.getInstance,
       _namespace = namespace,
       _allowLegacyFallback = allowLegacyFallback,
       _clearInvalidOnLoad = clearInvalidOnLoad;

  static const _cacheKey = 'xboard.remote_config.encrypted.v1';
  static const _cacheVersion = 1;

  final Future<SharedPreferences> Function() _preferencesLoader;
  final String? _namespace;
  final bool _allowLegacyFallback;
  final bool _clearInvalidOnLoad;

  String get _key => _namespace == null ? _cacheKey : '$_cacheKey.$_namespace';

  Future<Object?> load() async {
    final preferences = await _preferencesLoader();
    var key = _key;
    var raw = preferences.getString(key);
    if (raw == null && _allowLegacyFallback) {
      key = _cacheKey;
      raw = preferences.getString(key);
    }
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map ||
          decoded['version'] != _cacheVersion ||
          decoded['candidateCount'] is! int ||
          (decoded['candidateCount'] as int) <= 0 ||
          decoded['encryptedConfig'] is! String ||
          (decoded['encryptedConfig'] as String).isEmpty) {
        throw const FormatException('Invalid remote config cache');
      }
      return decoded['encryptedConfig'];
    } catch (_) {
      if (_clearInvalidOnLoad) await preferences.remove(key);
      return null;
    }
  }

  Future<void> save({
    required Object? encryptedConfig,
    required int candidateCount,
  }) async {
    final serializedConfig = switch (encryptedConfig) {
      final String value => value,
      final List<int> value => utf8.decode(value),
      _ => jsonEncode(encryptedConfig),
    };
    if (serializedConfig.trim().isEmpty || candidateCount <= 0) {
      throw const FormatException('Invalid verified remote config cache');
    }
    final preferences = await _preferencesLoader();
    final saved = await preferences.setString(
      _key,
      jsonEncode({
        'version': _cacheVersion,
        'verifiedAt': DateTime.now().toUtc().toIso8601String(),
        'candidateCount': candidateCount,
        'encryptedConfig': serializedConfig,
      }),
    );
    if (!saved) {
      throw StateError('Remote config cache write failed');
    }
  }

  Future<void> clear() async {
    final preferences = await _preferencesLoader();
    await preferences.remove(_key);
  }
}

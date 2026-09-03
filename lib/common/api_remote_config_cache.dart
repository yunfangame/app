import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class ApiRemoteConfigCacheStore {
  ApiRemoteConfigCacheStore({
    Future<SharedPreferences> Function()? preferencesLoader,
  }) : _preferencesLoader = preferencesLoader ?? SharedPreferences.getInstance;

  static const _cacheKey = 'xboard.remote_config.encrypted.v1';
  static const _cacheVersion = 1;

  final Future<SharedPreferences> Function() _preferencesLoader;

  Future<Object?> load() async {
    final preferences = await _preferencesLoader();
    final raw = preferences.getString(_cacheKey);
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
      await preferences.remove(_cacheKey);
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
      _cacheKey,
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
    await preferences.remove(_cacheKey);
  }
}

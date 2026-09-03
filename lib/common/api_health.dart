import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:fl_clash/common/api_endpoint_preference.dart';
import 'package:fl_clash/common/api_remote_config_cache.dart';
import 'package:fl_clash/common/remote_config_cipher.dart';
import 'package:flutter/services.dart';

const apiHealthConfigUrl = String.fromEnvironment(
  'API_HEALTH_CONFIG_URL',
  defaultValue: 'https://house.zryc.tech/ConFigOss4.json',
);

const apiHealthBackupConfigUrl = String.fromEnvironment(
  'API_HEALTH_CONFIG_BACKUP_URL',
  defaultValue: 'https://zryc.oss-cn-beijing.aliyuncs.com/ConFigOss4.json',
);

const apiHealthEmergencyConfigAsset = 'assets/config/ConFigOss4.emergency.json';

const apiHealthConfigAuthentication = 'FengWo';

enum ApiHealthLevel { unavailable, critical, warning, healthy }

enum ApiRemoteConfigFailure {
  dns,
  timeout,
  http,
  decrypt,
  signature,
  endpointsEmpty,
  configuration,
}

extension ApiRemoteConfigFailureDetails on ApiRemoteConfigFailure {
  String get code => switch (this) {
    ApiRemoteConfigFailure.dns => 'config_dns_failed',
    ApiRemoteConfigFailure.timeout => 'config_timeout',
    ApiRemoteConfigFailure.http => 'config_http_failed',
    ApiRemoteConfigFailure.decrypt => 'config_decrypt_failed',
    ApiRemoteConfigFailure.signature => 'config_signature_failed',
    ApiRemoteConfigFailure.endpointsEmpty => 'api_endpoints_empty',
    ApiRemoteConfigFailure.configuration => 'config_not_configured',
  };

  String get userMessage => switch (this) {
    ApiRemoteConfigFailure.dns => 'API 配置域名解析失败，请检查网络或 DNS',
    ApiRemoteConfigFailure.timeout => 'API 配置连接超时，请稍后重试',
    ApiRemoteConfigFailure.http => 'API 配置服务返回异常，请稍后重试',
    ApiRemoteConfigFailure.decrypt => 'API 配置文件解密失败',
    ApiRemoteConfigFailure.signature => 'API 配置文件签名校验失败',
    ApiRemoteConfigFailure.endpointsEmpty => 'API 配置中没有可用地址',
    ApiRemoteConfigFailure.configuration => 'API 配置地址未设置',
  };
}

class ApiRemoteConfigException implements Exception {
  const ApiRemoteConfigException({
    required this.failure,
    this.source,
    this.statusCode,
    this.cause,
  });

  final ApiRemoteConfigFailure failure;
  final Uri? source;
  final int? statusCode;
  final Object? cause;

  String get code => failure.code;
  String get userMessage => failure.userMessage;

  @override
  String toString() => 'ApiRemoteConfigException($code, $statusCode)';
}

class ApiEndpointHealth {
  const ApiEndpointHealth({
    required this.endpoint,
    required this.reachable,
    required this.latency,
  });

  final Uri endpoint;
  final bool reachable;
  final Duration latency;
}

class ApiHealthSnapshot {
  const ApiHealthSnapshot({
    required this.endpoints,
    required this.checkedAt,
    this.error,
  });

  factory ApiHealthSnapshot.unavailable(String error) => ApiHealthSnapshot(
    endpoints: const [],
    checkedAt: DateTime.now(),
    error: error,
  );

  final List<ApiEndpointHealth> endpoints;
  final DateTime checkedAt;
  final String? error;

  int get total => endpoints.length;

  int get reachableCount =>
      endpoints.where((endpoint) => endpoint.reachable).length;

  int get percentage => total == 0 ? 0 : (reachableCount * 100 / total).round();

  ApiHealthLevel get level {
    if (total == 0) return ApiHealthLevel.unavailable;
    if (percentage >= 80) return ApiHealthLevel.healthy;
    if (percentage >= 50) return ApiHealthLevel.warning;
    return ApiHealthLevel.critical;
  }

  bool get shouldPulse => total > 0 && reachableCount == 0;
}

typedef ApiRemoteConfigLoader = Future<Object?> Function(Uri configUri);
typedef ApiEmergencyConfigLoader = Future<Object?> Function();
typedef ApiEndpointProbe = Future<bool> Function(Uri endpoint);

class ApiHealthService {
  ApiHealthService({
    String configUrl = apiHealthConfigUrl,
    List<String>? backupConfigUrls,
    ApiRemoteConfigLoader? configLoader,
    ApiEmergencyConfigLoader? emergencyConfigLoader,
    ApiRemoteConfigCacheStore? configCacheStore,
    ApiEndpointProbe? endpointProbe,
    ApiEndpointPreferenceStore? preferenceStore,
    String aesKey = remoteConfigAesKey,
    String signingPublicKey = remoteConfigSigningPublicKey,
    this.probeTimeout = const Duration(seconds: 3),
    this.initialRemoteWait = const Duration(seconds: 2),
    this.configRetryDelays = const [
      Duration.zero,
      Duration(milliseconds: 250),
      Duration(milliseconds: 750),
    ],
  }) : _configUris = _buildConfigUris(configUrl, backupConfigUrls),
       _configLoader = configLoader,
       _emergencyConfigLoader = emergencyConfigLoader,
       _configCacheStore = configCacheStore ?? ApiRemoteConfigCacheStore(),
       _endpointProbe = endpointProbe,
       _preferenceStore = preferenceStore ?? ApiEndpointPreferenceStore(),
       _aesKey = aesKey,
       _signingPublicKey = signingPublicKey;

  final List<Uri> _configUris;
  final ApiRemoteConfigLoader? _configLoader;
  final ApiEmergencyConfigLoader? _emergencyConfigLoader;
  final ApiRemoteConfigCacheStore _configCacheStore;
  final ApiEndpointProbe? _endpointProbe;
  final ApiEndpointPreferenceStore _preferenceStore;
  final String _aesKey;
  final String _signingPublicKey;
  final Duration probeTimeout;
  final Duration initialRemoteWait;
  final List<Duration> configRetryDelays;
  Future<void>? _backgroundRefresh;

  static List<Uri> _buildConfigUris(
    String configUrl,
    List<String>? backupConfigUrls,
  ) {
    final backups =
        backupConfigUrls ??
        (configUrl == apiHealthConfigUrl
            ? const [apiHealthBackupConfigUrl]
            : const <String>[]);
    final values = [configUrl, ...backups];
    final uris = <Uri>[];
    final seen = <String>{};
    for (final value in values) {
      final uri = _parseConfigUri(value);
      if (uri != null && seen.add(uri.toString())) uris.add(uri);
    }
    return List.unmodifiable(uris);
  }

  static Uri? _parseConfigUri(String value) {
    final uri = Uri.tryParse(value.trim());
    if (uri == null ||
        !{'http', 'https'}.contains(uri.scheme) ||
        uri.host.isEmpty) {
      return null;
    }
    return uri;
  }

  Future<ApiHealthSnapshot> check() async {
    if (_configUris.isEmpty) {
      return ApiHealthSnapshot.unavailable('config_not_configured');
    }

    try {
      final verified = await _loadRemoteConfigWithRetries(
        requireEndpoints: true,
      );
      await _saveVerifiedCache(verified);

      final results = await Future.wait(verified.endpoints.map(probeEndpoint));
      return ApiHealthSnapshot(endpoints: results, checkedAt: DateTime.now());
    } on ApiRemoteConfigException catch (error) {
      return ApiHealthSnapshot.unavailable(error.code);
    } catch (_) {
      return ApiHealthSnapshot.unavailable('config_http_failed');
    }
  }

  Future<Object?> loadConfig() async {
    final verified = await _loadRemoteConfigWithRetries();
    if (verified.endpoints.isNotEmpty) await _saveVerifiedCache(verified);
    return verified.config;
  }

  Future<ApiEndpointHealth> probeEndpoint(Uri endpoint) async {
    final stopwatch = Stopwatch()..start();
    var reachable = false;
    try {
      reachable = await (_endpointProbe ?? _probeEndpoint)(
        endpoint,
      ).timeout(probeTimeout, onTimeout: () => false);
    } catch (_) {
      reachable = false;
    }
    stopwatch.stop();
    return ApiEndpointHealth(
      endpoint: endpoint,
      reachable: reachable,
      latency: stopwatch.elapsed,
    );
  }

  Future<Uri?> loadPreferredEndpoint() => _preferenceStore.load();

  Future<List<Uri>> loadCandidateEndpoints() async {
    Uri? preferred;
    try {
      preferred = await loadPreferredEndpoint();
    } catch (_) {}
    final cached = await _loadVerifiedCache();
    if (cached != null) {
      _refreshRemoteConfigInBackground();
      return _prioritizePreferred(cached.endpoints, preferred);
    }

    ApiRemoteConfigException? remoteFailure;
    final remoteLoad = _loadRemoteConfigWithRetries(requireEndpoints: true);
    try {
      final remote = await remoteLoad.timeout(initialRemoteWait);
      await _saveVerifiedCache(remote);
      return _prioritizePreferred(remote.endpoints, preferred);
    } on ApiRemoteConfigException catch (error) {
      remoteFailure = error;
    } on TimeoutException catch (error) {
      remoteFailure = ApiRemoteConfigException(
        failure: ApiRemoteConfigFailure.timeout,
        cause: error,
      );
      unawaited(remoteLoad.then(_saveVerifiedCache).catchError((Object _) {}));
    }

    try {
      final emergency = await _loadVerifiedEmergencyConfig();
      await _saveVerifiedCache(emergency);
      return _prioritizePreferred(emergency.endpoints, preferred);
    } on ApiRemoteConfigException catch (emergencyFailure) {
      if (preferred != null) return List.unmodifiable([preferred]);
      throw _moreImportantFailure(remoteFailure, emergencyFailure);
    }
  }

  List<Uri> _prioritizePreferred(List<Uri> values, Uri? preferred) {
    final endpoints = values.toList();
    if (preferred == null) return List.unmodifiable(endpoints);
    final preferredIndex = endpoints.indexWhere(
      (endpoint) => isSameApiEndpoint(endpoint, preferred),
    );
    if (preferredIndex > 0) {
      final selected = endpoints.removeAt(preferredIndex);
      endpoints.insert(0, selected);
    }
    return List.unmodifiable(endpoints);
  }

  Future<void> savePreferredEndpoint(Uri endpoint) =>
      _preferenceStore.save(endpoint);

  Future<List<ApiEndpointHealth>> orderedReachableEndpoints(
    ApiHealthSnapshot snapshot,
  ) async {
    final endpoints =
        snapshot.endpoints.where((endpoint) => endpoint.reachable).toList()
          ..sort((left, right) => left.latency.compareTo(right.latency));
    final preferred = await loadPreferredEndpoint();
    if (preferred == null) return List.unmodifiable(endpoints);
    final preferredIndex = endpoints.indexWhere(
      (endpoint) => isSameApiEndpoint(endpoint.endpoint, preferred),
    );
    if (preferredIndex > 0) {
      final selected = endpoints.removeAt(preferredIndex);
      endpoints.insert(0, selected);
    }
    return List.unmodifiable(endpoints);
  }

  Future<_VerifiedRemoteConfig> _loadRemoteConfigWithRetries({
    bool requireEndpoints = false,
  }) async {
    if (_configUris.isEmpty) {
      throw const ApiRemoteConfigException(
        failure: ApiRemoteConfigFailure.configuration,
      );
    }
    final retryDelays = configRetryDelays.isEmpty
        ? const [Duration.zero]
        : configRetryDelays;
    ApiRemoteConfigException? lastFailure;
    for (final delay in retryDelays) {
      if (delay > Duration.zero) await Future<void>.delayed(delay);
      try {
        return await _loadRemoteConfigRound(requireEndpoints: requireEndpoints);
      } on ApiRemoteConfigException catch (error) {
        lastFailure = lastFailure == null
            ? error
            : _moreImportantFailure(lastFailure, error);
      }
    }
    throw lastFailure ??
        const ApiRemoteConfigException(failure: ApiRemoteConfigFailure.http);
  }

  Future<_VerifiedRemoteConfig> _loadRemoteConfigRound({
    required bool requireEndpoints,
  }) {
    final completer = Completer<_VerifiedRemoteConfig>();
    final failures = <ApiRemoteConfigException>[];
    var remaining = _configUris.length;
    for (final configUri in _configUris) {
      unawaited(() async {
        try {
          final verified = await _loadVerifiedRemoteConfig(
            configUri,
            requireEndpoints: requireEndpoints,
          );
          if (!completer.isCompleted) completer.complete(verified);
        } catch (error) {
          failures.add(_classifyRemoteError(error, configUri));
          remaining--;
          if (remaining == 0 && !completer.isCompleted) {
            var selected = failures.first;
            for (final failure in failures.skip(1)) {
              selected = _moreImportantFailure(selected, failure);
            }
            completer.completeError(selected);
          }
        }
      }());
    }
    return completer.future;
  }

  Future<_VerifiedRemoteConfig> _loadVerifiedRemoteConfig(
    Uri configUri, {
    required bool requireEndpoints,
  }) async {
    try {
      final payload = await (_configLoader ?? _loadRemoteConfig)(configUri);
      return await _verifyPayload(
        payload,
        source: configUri,
        requireEndpoints: requireEndpoints,
      );
    } catch (error) {
      throw _classifyRemoteError(error, configUri);
    }
  }

  Future<_VerifiedRemoteConfig?> _loadVerifiedCache() async {
    try {
      final payload = await _configCacheStore.load();
      if (payload == null) return null;
      return await _verifyPayload(payload, requireEndpoints: true);
    } catch (_) {
      try {
        await _configCacheStore.clear();
      } catch (_) {}
      return null;
    }
  }

  Future<_VerifiedRemoteConfig> _loadVerifiedEmergencyConfig() async {
    try {
      final payload =
          await (_emergencyConfigLoader ??
              () => rootBundle.loadString(apiHealthEmergencyConfigAsset))();
      return await _verifyPayload(payload, requireEndpoints: true);
    } catch (error) {
      throw _classifyRemoteError(error, null);
    }
  }

  Future<_VerifiedRemoteConfig> _verifyPayload(
    Object? payload, {
    Uri? source,
    bool requireEndpoints = false,
  }) async {
    final hasAesKey = _aesKey.isNotEmpty;
    final hasSigningKey = _signingPublicKey.isNotEmpty;
    if (hasAesKey != hasSigningKey) {
      throw ApiRemoteConfigException(
        failure: ApiRemoteConfigFailure.decrypt,
        source: source,
      );
    }
    try {
      final decoded = hasAesKey
          ? await decodeEncryptedRemoteConfig(
              payload,
              aesKey: _aesKey,
              signingPublicKey: _signingPublicKey,
            )
          : payload;
      final config = decodeApiHealthConfig(decoded);
      final endpoints = parseApiEndpoints(config);
      if (requireEndpoints && endpoints.isEmpty) {
        throw ApiRemoteConfigException(
          failure: ApiRemoteConfigFailure.endpointsEmpty,
          source: source,
        );
      }
      return _VerifiedRemoteConfig(
        config: config,
        encryptedPayload: payload,
        endpoints: endpoints,
      );
    } on ApiRemoteConfigException {
      rethrow;
    } on RemoteConfigCipherException catch (error) {
      throw ApiRemoteConfigException(
        failure: switch (error.failure) {
          RemoteConfigCipherFailure.keyMismatch ||
          RemoteConfigCipherFailure.signature =>
            ApiRemoteConfigFailure.signature,
          _ => ApiRemoteConfigFailure.decrypt,
        },
        source: source,
        cause: error,
      );
    } catch (error) {
      throw ApiRemoteConfigException(
        failure: ApiRemoteConfigFailure.decrypt,
        source: source,
        cause: error,
      );
    }
  }

  Future<void> _saveVerifiedCache(_VerifiedRemoteConfig verified) async {
    try {
      await _configCacheStore.save(
        encryptedConfig: verified.encryptedPayload,
        candidateCount: verified.endpoints.length,
      );
    } catch (_) {}
  }

  void _refreshRemoteConfigInBackground() {
    if (_backgroundRefresh != null) return;
    final refresh = () async {
      try {
        final verified = await _loadRemoteConfigWithRetries(
          requireEndpoints: true,
        );
        await _saveVerifiedCache(verified);
      } catch (_) {}
    }();
    _backgroundRefresh = refresh;
    unawaited(refresh.whenComplete(() => _backgroundRefresh = null));
  }

  ApiRemoteConfigException _classifyRemoteError(Object error, Uri? source) {
    if (error is ApiRemoteConfigException) return error;
    if (error is TimeoutException) {
      return ApiRemoteConfigException(
        failure: ApiRemoteConfigFailure.timeout,
        source: source,
        cause: error,
      );
    }
    if (error is DioException) {
      if (const {
        DioExceptionType.connectionTimeout,
        DioExceptionType.sendTimeout,
        DioExceptionType.receiveTimeout,
      }.contains(error.type)) {
        return ApiRemoteConfigException(
          failure: ApiRemoteConfigFailure.timeout,
          source: source,
          cause: error,
        );
      }
      final socketError = error.error;
      if (socketError is SocketException && _isDnsFailure(socketError)) {
        return ApiRemoteConfigException(
          failure: ApiRemoteConfigFailure.dns,
          source: source,
          cause: error,
        );
      }
      return ApiRemoteConfigException(
        failure: ApiRemoteConfigFailure.http,
        source: source,
        statusCode: error.response?.statusCode,
        cause: error,
      );
    }
    if (error is SocketException && _isDnsFailure(error)) {
      return ApiRemoteConfigException(
        failure: ApiRemoteConfigFailure.dns,
        source: source,
        cause: error,
      );
    }
    if (error is RemoteConfigCipherException) {
      return ApiRemoteConfigException(
        failure: switch (error.failure) {
          RemoteConfigCipherFailure.keyMismatch ||
          RemoteConfigCipherFailure.signature =>
            ApiRemoteConfigFailure.signature,
          _ => ApiRemoteConfigFailure.decrypt,
        },
        source: source,
        cause: error,
      );
    }
    return ApiRemoteConfigException(
      failure: ApiRemoteConfigFailure.http,
      source: source,
      cause: error,
    );
  }

  bool _isDnsFailure(SocketException error) {
    final message = error.message.toLowerCase();
    return message.contains('failed host lookup') ||
        message.contains('name or service not known') ||
        message.contains('nodename nor servname');
  }

  ApiRemoteConfigException _moreImportantFailure(
    ApiRemoteConfigException left,
    ApiRemoteConfigException right,
  ) {
    const priority = {
      ApiRemoteConfigFailure.configuration: 0,
      ApiRemoteConfigFailure.http: 1,
      ApiRemoteConfigFailure.timeout: 2,
      ApiRemoteConfigFailure.dns: 3,
      ApiRemoteConfigFailure.endpointsEmpty: 4,
      ApiRemoteConfigFailure.decrypt: 5,
      ApiRemoteConfigFailure.signature: 6,
    };
    return priority[right.failure]! > priority[left.failure]! ? right : left;
  }

  Future<Object?> _loadRemoteConfig(Uri configUri) async {
    final dio = Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 5),
        receiveTimeout: const Duration(seconds: 5),
        responseType: ResponseType.bytes,
      ),
    );
    dio.httpClientAdapter = IOHttpClientAdapter(
      createHttpClient: () {
        final client = HttpClient();
        client.findProxy = (_) => 'DIRECT';
        return client;
      },
    );
    try {
      final response = await dio.getUri<List<int>>(
        configUri,
        options: Options(
          validateStatus: (status) =>
              status != null && status >= 200 && status < 300,
        ),
      );
      final bytes = response.data;
      if (bytes == null || bytes.isEmpty) {
        throw const FormatException('Empty remote config');
      }
      return utf8.decode(bytes);
    } finally {
      dio.close(force: true);
    }
  }

  Future<bool> _probeEndpoint(Uri endpoint) async {
    final dio = Dio(
      BaseOptions(
        connectTimeout: probeTimeout,
        sendTimeout: probeTimeout,
        receiveTimeout: probeTimeout,
      ),
    );
    await dio.headUri<Object?>(
      endpoint,
      options: Options(
        responseType: ResponseType.stream,
        validateStatus: (status) => status != null,
      ),
    );
    return true;
  }
}

class _VerifiedRemoteConfig {
  const _VerifiedRemoteConfig({
    required this.config,
    required this.encryptedPayload,
    required this.endpoints,
  });

  final Object? config;
  final Object? encryptedPayload;
  final List<Uri> endpoints;
}

List<Uri> parseApiEndpoints(Object? config) {
  Object? rawEndpoints;
  if (config is List) {
    rawEndpoints = config;
  } else if (config is Map) {
    rawEndpoints = config['hosts'];
  }

  if (rawEndpoints is! List) return const [];
  final endpoints = <Uri>[];
  final seen = <String>{};
  for (final entry in rawEndpoints) {
    final value = switch (entry) {
      final String text => text,
      final Map map => map['url'] ?? map['domain'] ?? map['endpoint'],
      _ => null,
    };
    if (value is! String) continue;
    final normalized = value.trim();
    if (normalized.isEmpty) continue;
    final uri = Uri.tryParse(
      normalized.contains('://') ? normalized : 'https://$normalized',
    );
    if (uri == null ||
        !{'http', 'https'}.contains(uri.scheme) ||
        uri.host.isEmpty ||
        !seen.add(uri.toString())) {
      continue;
    }
    endpoints.add(uri);
  }
  return List.unmodifiable(endpoints);
}

Object? decodeApiHealthConfig(Object? payload) {
  Object? decoded = payload;
  if (payload is String) {
    final value = payload.trim();
    if (value.isEmpty) throw const FormatException('Empty remote config');
    try {
      decoded = jsonDecode(value);
    } on FormatException {
      final bytes = base64Decode(base64.normalize(value));
      decoded = jsonDecode(utf8.decode(bytes));
    }
  }
  if (decoded is! Map && decoded is! List) {
    throw const FormatException('Invalid remote config payload');
  }
  if (decoded is Map &&
      decoded['Authentication'] != apiHealthConfigAuthentication) {
    throw const FormatException('Remote config authentication failed');
  }
  return decoded;
}

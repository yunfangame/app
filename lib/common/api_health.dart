import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:fl_clash/common/api_endpoint_preference.dart';
import 'package:fl_clash/common/remote_config_cipher.dart';

const apiHealthConfigUrl = String.fromEnvironment(
  'API_HEALTH_CONFIG_URL',
  defaultValue: 'https://house.zryc.tech/ConFigOss4.json',
);

const apiHealthConfigAuthentication = 'FengWo';

enum ApiHealthLevel { unavailable, critical, warning, healthy }

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
typedef ApiEndpointProbe = Future<bool> Function(Uri endpoint);

class ApiHealthService {
  ApiHealthService({
    String configUrl = apiHealthConfigUrl,
    ApiRemoteConfigLoader? configLoader,
    ApiEndpointProbe? endpointProbe,
    ApiEndpointPreferenceStore? preferenceStore,
    this.probeTimeout = const Duration(seconds: 3),
  }) : _configUri = _parseConfigUri(configUrl),
       _configLoader = configLoader,
       _endpointProbe = endpointProbe,
       _preferenceStore = preferenceStore ?? ApiEndpointPreferenceStore();

  final Uri? _configUri;
  final ApiRemoteConfigLoader? _configLoader;
  final ApiEndpointProbe? _endpointProbe;
  final ApiEndpointPreferenceStore _preferenceStore;
  final Duration probeTimeout;

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
    if (_configUri == null) {
      return ApiHealthSnapshot.unavailable('config_not_configured');
    }

    try {
      final config = await loadConfig();
      final endpoints = parseApiEndpoints(config);
      if (endpoints.isEmpty) {
        return ApiHealthSnapshot.unavailable('api_endpoints_empty');
      }

      final results = await Future.wait(endpoints.map(probeEndpoint));
      return ApiHealthSnapshot(endpoints: results, checkedAt: DateTime.now());
    } catch (_) {
      return ApiHealthSnapshot.unavailable('config_load_failed');
    }
  }

  Future<Object?> loadConfig() async {
    final configUri = _configUri;
    if (configUri == null) {
      throw const FormatException('Remote config is not configured');
    }
    final payload = await (_configLoader ?? _loadRemoteConfig)(configUri);
    final hasAesKey = remoteConfigAesKey.isNotEmpty;
    final hasSigningKey = remoteConfigSigningPublicKey.isNotEmpty;
    if (hasAesKey != hasSigningKey) {
      throw const FormatException('Incomplete remote config build keys');
    }
    if (hasAesKey) {
      final decoded = await decodeEncryptedRemoteConfig(
        payload,
        aesKey: remoteConfigAesKey,
        signingPublicKey: remoteConfigSigningPublicKey,
      );
      return decodeApiHealthConfig(decoded);
    }
    return decodeApiHealthConfig(payload);
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

  Future<Object?> _loadRemoteConfig(Uri configUri) async {
    final dio = Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 5),
        receiveTimeout: const Duration(seconds: 5),
        responseType: ResponseType.bytes,
      ),
    );
    final response = await dio.getUri<List<int>>(
      configUri,
      options: Options(
        validateStatus: (status) =>
            status != null && status >= 200 && status < 300,
      ),
    );
    final bytes = response.data;
    if (bytes == null) throw const FormatException('Empty remote config');
    return utf8.decode(bytes);
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

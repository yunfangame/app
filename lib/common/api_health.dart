import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:fl_clash/common/api_endpoint_preference.dart';
import 'package:fl_clash/common/api_network_diagnostic.dart';
import 'package:fl_clash/common/api_remote_config_cache.dart';
import 'package:fl_clash/common/remote_config_cipher.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'api_health_snapshot_cache.dart';

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
const _apiEndpointHealthPath = '/api/v1/guest/comm/config';

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
    this.diagnostic,
  });

  final ApiRemoteConfigFailure failure;
  final Uri? source;
  final int? statusCode;
  final Object? cause;
  final ApiNetworkDiagnostic? diagnostic;

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
    this.diagnostic,
  });

  final Uri endpoint;
  final bool reachable;
  final Duration latency;
  final ApiNetworkDiagnostic? diagnostic;
}

class ApiHealthSnapshot {
  const ApiHealthSnapshot({
    required this.endpoints,
    required this.checkedAt,
    this.error,
    this.diagnostic,
  });

  factory ApiHealthSnapshot.unavailable(
    String error, {
    ApiNetworkDiagnostic? diagnostic,
  }) => ApiHealthSnapshot(
    endpoints: const [],
    checkedAt: DateTime.now(),
    error: error,
    diagnostic: diagnostic,
  );

  final List<ApiEndpointHealth> endpoints;
  final DateTime checkedAt;
  final String? error;
  final ApiNetworkDiagnostic? diagnostic;

  bool get isDeferred => error == 'check_deferred';

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

class ApiRemoteConfigMemoryCache {
  static int _sequence = 0;
  final Map<String, _RemoteConfigCacheState> _domains = {};
  final String _namespace =
      '${DateTime.now().microsecondsSinceEpoch}-${_sequence++}';
}

class ApiRemoteConfigActivity extends ChangeNotifier {
  bool _appForeground = true;
  bool _windowForeground = true;
  bool _offline = false;
  bool _networkAvailable = true;
  int _networkRevision = 0;
  final Map<Object, void Function()> _pending = {};

  bool get isForeground => _appForeground && _windowForeground;
  bool get isAvailable => isForeground && !_offline && _networkAvailable;
  int get networkRevision => _networkRevision;

  void setAppForeground(bool value) {
    final before = isAvailable;
    _appForeground = value;
    _resume();
    if (before != isAvailable) notifyListeners();
  }

  void setWindowForeground(bool value) {
    final before = isAvailable;
    _windowForeground = value;
    _resume();
    if (before != isAvailable) notifyListeners();
  }

  void setOffline(bool value) {
    final before = isAvailable;
    _offline = value;
    _resume();
    if (before != isAvailable) notifyListeners();
  }

  void networkChanged({bool available = true}) {
    _networkAvailable = available;
    _networkRevision++;
    _resume();
    notifyListeners();
  }

  void _defer(Object key, void Function() refresh) => _pending[key] = refresh;

  void _resume() {
    if (!isAvailable || _pending.isEmpty) return;
    final pending = _pending.values.toList();
    _pending.clear();
    for (final refresh in pending) {
      refresh();
    }
  }
}

class _RemoteConfigCacheState {
  _VerifiedRemoteConfig? verified;
  DateTime? verifiedAt;
  ApiRemoteConfigException? failure;
  DateTime? failedAt;
  DateTime? retryAfter;
  int failures = 0;
  int revision = 0;
  int verifiedRevision = 0;
  bool deferredRequireEndpoints = false;
  _RemoteConfigRequest? normal;
  _RemoteConfigRequest? forced;
  Future<void> persistence = Future.value();
}

class _RemoteConfigRequest {
  _RemoteConfigRequest({
    required this.revision,
    required this.requireEndpoints,
  });

  final int revision;
  final bool requireEndpoints;
  final completer = Completer<_VerifiedRemoteConfig>();

  Future<_VerifiedRemoteConfig> get future => completer.future;
}

class _RemoteConfigRefreshDeferred implements Exception {
  const _RemoteConfigRefreshDeferred(this.verified);

  final _VerifiedRemoteConfig verified;
}

class ApiHealthService {
  ApiHealthService({
    String configUrl = apiHealthConfigUrl,
    List<String>? backupConfigUrls,
    ApiRemoteConfigLoader? configLoader,
    ApiEmergencyConfigLoader? emergencyConfigLoader,
    ApiRemoteConfigCacheStore? configCacheStore,
    ApiEndpointProbe? endpointProbe,
    ApiEndpointPreferenceStore? preferenceStore,
    ApiDiagnosticRecorder? diagnosticRecorder,
    ApiRemoteConfigMemoryCache? memoryCache,
    ApiHealthSnapshotCache? healthCache,
    ApiRemoteConfigActivity? activity,
    DateTime Function()? now,
    String aesKey = remoteConfigAesKey,
    String signingPublicKey = remoteConfigSigningPublicKey,
    this.probeTimeout = const Duration(seconds: 3),
    this.initialRemoteWait = const Duration(seconds: 2),
    this.configCacheTtl = const Duration(minutes: 5),
    this.configRetryDelays = const [
      Duration.zero,
      Duration(milliseconds: 250),
      Duration(milliseconds: 750),
    ],
  }) : _configUris = _buildConfigUris(configUrl, backupConfigUrls),
       _configLoader = configLoader,
       _emergencyConfigLoader = emergencyConfigLoader,
       _endpointProbe = endpointProbe,
       _preferenceStore = preferenceStore ?? ApiEndpointPreferenceStore(),
       _diagnosticRecorder = diagnosticRecorder ?? recordApiDiagnosticEvent,
       _aesKey = aesKey,
       _signingPublicKey = signingPublicKey,
       _activity = activity ?? _sharedActivity,
       _now = now ?? DateTime.now {
    final domain = _configTrustDomain(_configUris, aesKey, signingPublicKey);
    final usesDefaultSources =
        configLoader == null &&
        emergencyConfigLoader == null &&
        configCacheStore == null &&
        activity == null &&
        now == null;
    final pool =
        memoryCache ??
        (usesDefaultSources
            ? _sharedMemoryCache
            : ApiRemoteConfigMemoryCache());
    _healthCache =
        healthCache ??
        (usesDefaultSources && endpointProbe == null
            ? _sharedHealthCache
            : ApiHealthSnapshotCache(now: _now));
    _healthScope = '$domain.${probeTimeout.inMicroseconds}';
    _cacheState = pool._domains.putIfAbsent(
      domain,
      _RemoteConfigCacheState.new,
    );
    _configCacheStore =
        configCacheStore ??
        ApiRemoteConfigCacheStore(
          namespace: usesDefaultSources ? domain : '$domain.${pool._namespace}',
          clearInvalidOnLoad: false,
          allowLegacyFallback:
              usesDefaultSources &&
              domain ==
                  _configTrustDomain(
                    _buildConfigUris(apiHealthConfigUrl, null),
                    remoteConfigAesKey,
                    remoteConfigSigningPublicKey,
                  ),
        );
  }

  final List<Uri> _configUris;
  final ApiRemoteConfigLoader? _configLoader;
  final ApiEmergencyConfigLoader? _emergencyConfigLoader;
  late final ApiRemoteConfigCacheStore _configCacheStore;
  final ApiEndpointProbe? _endpointProbe;
  final ApiEndpointPreferenceStore _preferenceStore;
  final ApiDiagnosticRecorder _diagnosticRecorder;
  final String _aesKey;
  final String _signingPublicKey;
  final Duration probeTimeout;
  final Duration initialRemoteWait;
  final Duration configCacheTtl;
  final List<Duration> configRetryDelays;
  final DateTime Function() _now;
  final ApiRemoteConfigActivity _activity;
  late final _RemoteConfigCacheState _cacheState;
  late final ApiHealthSnapshotCache _healthCache;
  late final String _healthScope;
  static final _sharedHealthCache = ApiHealthSnapshotCache();
  static final _sharedMemoryCache = ApiRemoteConfigMemoryCache();
  static final _sharedActivity = ApiRemoteConfigActivity();
  static int _configRefreshSequence = 0;

  static void setAppForeground(bool foreground) =>
      _sharedActivity.setAppForeground(foreground);

  static void setWindowForeground(bool foreground) =>
      _sharedActivity.setWindowForeground(foreground);

  static bool get automaticRequestsAvailable => _sharedActivity.isAvailable;

  static void setOffline(bool offline) => _sharedActivity.setOffline(offline);

  static void networkChanged({bool available = true}) =>
      _sharedActivity.networkChanged(available: available);

  bool get canAutomaticallyCheck => _activity.isAvailable;

  void addAvailabilityListener(VoidCallback listener) =>
      _activity.addListener(listener);

  void removeAvailabilityListener(VoidCallback listener) =>
      _activity.removeListener(listener);

  static String _configTrustDomain(
    List<Uri> sources,
    String aesKey,
    String signingPublicKey,
  ) => sha256
      .convert(
        utf8.encode(
          jsonEncode([
            sources.map((source) => source.toString()).toList(),
            aesKey,
            signingPublicKey,
          ]),
        ),
      )
      .toString();

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

  Future<ApiHealthSnapshot> check({bool forceRefresh = true}) {
    final revision = _activity.networkRevision;
    final scope = '$_healthScope.$revision';
    if (!forceRefresh && !canAutomaticallyCheck) {
      return Future.value(
        _healthCache.peek(scope) ??
            ApiHealthSnapshot.unavailable('check_deferred'),
      );
    }
    return _healthCache.load(
      scope: scope,
      forceRefresh: forceRefresh,
      loader: () =>
          _performCheck(forceRefresh: forceRefresh, revision: revision),
    );
  }

  Future<ApiHealthSnapshot> _performCheck({
    required bool forceRefresh,
    required int revision,
  }) async {
    if (_configUris.isEmpty) {
      return ApiHealthSnapshot.unavailable(
        'config_not_configured',
        diagnostic: const ApiNetworkDiagnostic(
          failure: ApiNetworkFailure.configuration,
          stage: 'remote_config',
        ),
      );
    }

    try {
      final verified = await _loadRemoteConfigWithRetries(
        requireEndpoints: true,
        forceRefresh: forceRefresh,
      );

      if (!forceRefresh &&
          (!canAutomaticallyCheck || revision != _activity.networkRevision)) {
        return ApiHealthSnapshot.unavailable('check_deferred');
      }
      final results = await Future.wait(verified.endpoints.map(probeEndpoint));
      if (!forceRefresh &&
          (!canAutomaticallyCheck || revision != _activity.networkRevision)) {
        return ApiHealthSnapshot.unavailable('check_deferred');
      }
      return ApiHealthSnapshot(
        endpoints: List.unmodifiable(results),
        checkedAt: _now(),
      );
    } on ApiRemoteConfigException catch (error) {
      if (!forceRefresh &&
          (!canAutomaticallyCheck || revision != _activity.networkRevision)) {
        return ApiHealthSnapshot.unavailable('check_deferred');
      }
      return ApiHealthSnapshot.unavailable(
        error.code,
        diagnostic: error.diagnostic,
      );
    } catch (error) {
      if (!forceRefresh &&
          (!canAutomaticallyCheck || revision != _activity.networkRevision)) {
        return ApiHealthSnapshot.unavailable('check_deferred');
      }
      return ApiHealthSnapshot.unavailable(
        'config_http_failed',
        diagnostic: classifyApiNetworkFailure(error, stage: 'remote_config'),
      );
    }
  }

  Future<Object?> loadConfig({bool forceRefresh = false}) async {
    final verified = await _loadRemoteConfigWithRetries(
      forceRefresh: forceRefresh,
    );
    return _copyConfigValue(verified.config);
  }

  Future<ApiEndpointHealth> probeEndpoint(Uri endpoint) async {
    final stopwatch = Stopwatch()..start();
    final attemptId = newApiDiagnosticAttemptId();
    var reachable = false;
    ApiNetworkDiagnostic? diagnostic;
    try {
      reachable = await (_endpointProbe ?? _probeEndpoint)(
        endpoint,
      ).timeout(probeTimeout);
      if (!reachable) {
        diagnostic = classifyApiNetworkFailure(
          const SocketException('Probe unavailable'),
          stage: 'api_probe',
          endpoint: endpoint,
          elapsedMilliseconds: stopwatch.elapsedMilliseconds,
          attemptId: attemptId,
        );
      }
    } catch (error) {
      diagnostic = classifyApiNetworkFailure(
        error,
        stage: 'api_probe',
        endpoint: endpoint,
        elapsedMilliseconds: stopwatch.elapsedMilliseconds,
        attemptId: attemptId,
      );
    }
    stopwatch.stop();
    emitApiDiagnosticEvent(_diagnosticRecorder, 'api.probe.completed', {
      'reachable': reachable,
      'stage': 'api_probe',
      'attempt_id': attemptId,
      'endpoint_ref': apiDiagnosticEndpointRef(endpoint),
      'elapsed_ms': stopwatch.elapsedMilliseconds,
      ...?diagnostic?.toDiagnosticFields(),
    });
    return ApiEndpointHealth(
      endpoint: endpoint,
      reachable: reachable,
      latency: stopwatch.elapsed,
      diagnostic: diagnostic,
    );
  }

  Future<Uri?> loadLastSuccessfulEndpoint() => _preferenceStore.load();

  Future<List<Uri>> loadCandidateEndpoints() =>
      _loadCandidateEndpoints(allowLastSuccessfulFallback: true);

  Future<List<Uri>> loadVerifiedCandidateEndpoints() =>
      _loadCandidateEndpoints(allowLastSuccessfulFallback: false);

  Future<List<Uri>> _loadCandidateEndpoints({
    required bool allowLastSuccessfulFallback,
  }) async {
    Uri? lastSuccessful;
    try {
      lastSuccessful = await loadLastSuccessfulEndpoint().timeout(
        const Duration(seconds: 1),
      );
    } catch (_) {}
    final fresh = _freshConfig(requireEndpoints: true);
    if (fresh != null) {
      return _prioritizeLastSuccessful(fresh.endpoints, lastSuccessful);
    }
    final revision = _cacheState.revision;
    final memory = _cacheState.verified;
    final stored = memory != null && memory.endpoints.isNotEmpty
        ? memory
        : await _loadVerifiedCache();
    final latest = _cacheState.verified;
    final cached = latest != null && latest.endpoints.isNotEmpty
        ? latest
        : stored;
    if (cached != null) {
      if (_cacheState.revision == revision && _cacheState.verified == null) {
        _cacheState.verified = cached;
      }
      emitApiDiagnosticEvent(_diagnosticRecorder, 'api.config.fallback', {
        'source': 'verified_cache',
        'candidate_count': cached.endpoints.length,
      });
      _refreshRemoteConfigInBackground();
      return _prioritizeLastSuccessful(cached.endpoints, lastSuccessful);
    }

    ApiRemoteConfigException? remoteFailure;
    final remoteLoad = _loadRemoteConfigWithRetries(requireEndpoints: true);
    final remoteRevision = _cacheState.revision;
    try {
      final remote = await remoteLoad.timeout(initialRemoteWait);
      return _prioritizeLastSuccessful(remote.endpoints, lastSuccessful);
    } on ApiRemoteConfigException catch (error) {
      remoteFailure = error;
    } on TimeoutException catch (error) {
      remoteFailure = ApiRemoteConfigException(
        failure: ApiRemoteConfigFailure.timeout,
        cause: error,
        diagnostic: classifyApiNetworkFailure(error, stage: 'remote_config'),
      );
    }

    try {
      final emergency = await _loadVerifiedEmergencyConfig();
      emitApiDiagnosticEvent(_diagnosticRecorder, 'api.config.fallback', {
        'source': 'verified_emergency',
        'candidate_count': emergency.endpoints.length,
      });
      final latest = _cacheState.verified;
      if (latest != null && latest.endpoints.isNotEmpty) {
        return _prioritizeLastSuccessful(latest.endpoints, lastSuccessful);
      }
      if (_cacheState.revision == remoteRevision) {
        _cacheState.verified = emergency;
        await _saveVerifiedCache(emergency, revision: remoteRevision);
      }
      return _prioritizeLastSuccessful(emergency.endpoints, lastSuccessful);
    } on ApiRemoteConfigException catch (emergencyFailure) {
      if (allowLastSuccessfulFallback && lastSuccessful != null) {
        emitApiDiagnosticEvent(_diagnosticRecorder, 'api.config.fallback', {
          'source': 'last_successful_endpoint',
          'candidate_count': 1,
        });
        return List.unmodifiable([lastSuccessful]);
      }
      throw _moreImportantFailure(remoteFailure, emergencyFailure);
    }
  }

  List<Uri> _prioritizeLastSuccessful(List<Uri> values, Uri? lastSuccessful) {
    final endpoints = values.toList();
    if (lastSuccessful == null) return List.unmodifiable(endpoints);
    final lastSuccessfulIndex = endpoints.indexWhere(
      (endpoint) => isSameApiEndpoint(endpoint, lastSuccessful),
    );
    if (lastSuccessfulIndex > 0) {
      final endpoint = endpoints.removeAt(lastSuccessfulIndex);
      endpoints.insert(0, endpoint);
    }
    return List.unmodifiable(endpoints);
  }

  Future<void> rememberSuccessfulEndpoint(Uri endpoint) =>
      _preferenceStore.save(endpoint);

  Future<_VerifiedRemoteConfig> _loadRemoteConfigWithRetries({
    bool requireEndpoints = false,
    bool forceRefresh = false,
  }) {
    final forced = _cacheState.forced;
    if (forced != null) {
      return _joinConfigRequest(
        forced,
        requireEndpoints: requireEndpoints,
        forceRefresh: true,
      );
    }
    if (!forceRefresh) {
      final fresh = _freshConfig(requireEndpoints: requireEndpoints);
      if (fresh != null) return Future.value(fresh);
      final verified = _cacheState.verified;
      if (!_activity.isAvailable &&
          verified != null &&
          (!requireEndpoints || verified.endpoints.isNotEmpty)) {
        _deferConfigRefresh(requireEndpoints: requireEndpoints);
        return Future.value(verified);
      }
      final normal = _cacheState.normal;
      if (normal != null) {
        return _joinConfigRequest(normal, requireEndpoints: requireEndpoints);
      }
      final failure = _cacheState.failure;
      final failedAt = _cacheState.failedAt;
      final retryAfter = _cacheState.retryAfter;
      final now = _now();
      if (failure != null &&
          failedAt != null &&
          retryAfter != null &&
          !now.isBefore(failedAt) &&
          now.isBefore(retryAfter)) {
        return Future.error(failure);
      }
    }
    final request = _RemoteConfigRequest(
      revision: ++_cacheState.revision,
      requireEndpoints: requireEndpoints,
    );
    if (forceRefresh) {
      _cacheState.forced = request;
      _cacheState.normal = null;
    } else {
      _cacheState.normal = request;
    }
    unawaited(_completeConfigRequest(request, forceRefresh: forceRefresh));
    return request.future;
  }

  _VerifiedRemoteConfig? _freshConfig({required bool requireEndpoints}) {
    final verified = _cacheState.verified;
    final verifiedAt = _cacheState.verifiedAt;
    if (verified == null ||
        verifiedAt == null ||
        (requireEndpoints && verified.endpoints.isEmpty)) {
      return null;
    }
    final age = _now().difference(verifiedAt);
    return !age.isNegative && age < configCacheTtl ? verified : null;
  }

  Future<_VerifiedRemoteConfig> _joinConfigRequest(
    _RemoteConfigRequest request, {
    required bool requireEndpoints,
    bool forceRefresh = false,
  }) async {
    final verified = await request.future;
    if (requireEndpoints && verified.endpoints.isEmpty) {
      return _loadRemoteConfigWithRetries(
        requireEndpoints: true,
        forceRefresh: forceRefresh,
      );
    }
    return verified;
  }

  Future<void> _completeConfigRequest(
    _RemoteConfigRequest request, {
    required bool forceRefresh,
  }) async {
    try {
      final verified = await _downloadRemoteConfigWithRetries(
        requireEndpoints: request.requireEndpoints,
        forceRefresh: forceRefresh,
      );
      if (_cacheState.revision == request.revision) {
        _cacheState.verified = verified;
        _cacheState.verifiedAt = _now();
        _cacheState.verifiedRevision = request.revision;
        _cacheState.failure = null;
        _cacheState.failedAt = null;
        _cacheState.retryAfter = null;
        _cacheState.failures = 0;
        if (verified.endpoints.isNotEmpty) {
          await _saveVerifiedCache(verified, revision: request.revision);
        }
      }
      final latest = _cacheState.verified;
      request.completer.complete(
        latest != null &&
                _cacheState.verifiedRevision > request.revision &&
                (!request.requireEndpoints || latest.endpoints.isNotEmpty)
            ? latest
            : verified,
      );
    } on _RemoteConfigRefreshDeferred catch (deferred) {
      final latest = _cacheState.verified;
      request.completer.complete(
        latest != null &&
                _cacheState.verifiedRevision > request.revision &&
                (!request.requireEndpoints || latest.endpoints.isNotEmpty)
            ? latest
            : deferred.verified,
      );
    } on ApiRemoteConfigException catch (error, stackTrace) {
      if (_cacheState.revision == request.revision) {
        const delays = [30, 60, 120, 240, 300];
        _cacheState.failures++;
        final delay = delays[(_cacheState.failures - 1).clamp(0, 4)];
        final now = _now();
        _cacheState.failure = error;
        _cacheState.failedAt = now;
        _cacheState.retryAfter = now.add(Duration(seconds: delay));
      }
      request.completer.completeError(error, stackTrace);
    } catch (error, stackTrace) {
      request.completer.completeError(error, stackTrace);
    } finally {
      if (identical(_cacheState.forced, request)) _cacheState.forced = null;
      if (identical(_cacheState.normal, request)) _cacheState.normal = null;
    }
  }

  Future<_VerifiedRemoteConfig> _downloadRemoteConfigWithRetries({
    bool requireEndpoints = false,
    bool forceRefresh = false,
  }) async {
    if (_configUris.isEmpty) {
      throw const ApiRemoteConfigException(
        failure: ApiRemoteConfigFailure.configuration,
        diagnostic: ApiNetworkDiagnostic(
          failure: ApiNetworkFailure.configuration,
          stage: 'remote_config',
        ),
      );
    }
    final refreshNonce = forceRefresh
        ? '${DateTime.now().microsecondsSinceEpoch}-${++_configRefreshSequence}'
        : null;
    final retryDelays = configRetryDelays.isEmpty
        ? const [Duration.zero]
        : configRetryDelays;
    ApiRemoteConfigException? lastFailure;
    for (final delay in retryDelays) {
      if (delay > Duration.zero) await Future<void>.delayed(delay);
      final verified = _cacheState.verified;
      if (!forceRefresh &&
          !_activity.isAvailable &&
          verified != null &&
          (!requireEndpoints || verified.endpoints.isNotEmpty)) {
        _deferConfigRefresh(requireEndpoints: requireEndpoints);
        throw _RemoteConfigRefreshDeferred(verified);
      }
      try {
        return await _loadRemoteConfigRound(
          requireEndpoints: requireEndpoints,
          refreshNonce: refreshNonce,
        );
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
    String? refreshNonce,
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
            refreshNonce: refreshNonce,
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
    String? refreshNonce,
  }) async {
    final stopwatch = Stopwatch()..start();
    final attemptId = newApiDiagnosticAttemptId();
    try {
      final requestUri = refreshNonce == null
          ? configUri
          : configUri.replace(
              queryParameters: {
                ...configUri.queryParametersAll,
                '_fengwo_refresh': refreshNonce,
              },
            );
      final payload = _configLoader != null
          ? await _configLoader(requestUri)
          : await _loadRemoteConfig(
              requestUri,
              forceRefresh: refreshNonce != null,
            );
      final verified = await _verifyPayload(
        payload,
        source: configUri,
        requireEndpoints: requireEndpoints,
      );
      emitApiDiagnosticEvent(
        _diagnosticRecorder,
        'api.config.attempt.succeeded',
        {
          'stage': 'remote_config',
          'attempt_id': attemptId,
          'endpoint_ref': apiDiagnosticEndpointRef(configUri),
          'elapsed_ms': stopwatch.elapsedMilliseconds,
          'candidate_count': verified.endpoints.length,
        },
      );
      return verified;
    } catch (error) {
      final classified = _classifyRemoteError(
        error,
        configUri,
        elapsedMilliseconds: stopwatch.elapsedMilliseconds,
        attemptId: attemptId,
      );
      emitApiDiagnosticEvent(
        _diagnosticRecorder,
        'api.config.attempt.failed',
        classified.diagnostic?.toDiagnosticFields() ?? const {},
      );
      throw classified;
    } finally {
      stopwatch.stop();
    }
  }

  Future<_VerifiedRemoteConfig?> _loadVerifiedCache() async {
    final revision = _cacheState.revision;
    try {
      final payload = await _configCacheStore.load().timeout(
        const Duration(seconds: 1),
      );
      if (payload == null) return null;
      return await _verifyPayload(payload, requireEndpoints: true);
    } on TimeoutException {
      return null;
    } catch (_) {
      await _persistConfig(revision, _configCacheStore.clear);
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
        config: _freezeConfigValue(config),
        encryptedPayload: payload is List<int>
            ? List<int>.unmodifiable(payload)
            : _freezeConfigValue(payload),
        endpoints: List.unmodifiable(endpoints),
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

  Future<void> _saveVerifiedCache(
    _VerifiedRemoteConfig verified, {
    required int revision,
  }) => _persistConfig(
    revision,
    () => _configCacheStore.save(
      encryptedConfig: verified.encryptedPayload,
      candidateCount: verified.endpoints.length,
    ),
  );

  Future<void> _persistConfig(
    int revision,
    Future<void> Function() operation,
  ) async {
    final pending = _cacheState.persistence
        .then((_) async {
          if (_cacheState.revision != revision) return;
          await operation();
        })
        .catchError((Object _) {});
    _cacheState.persistence = pending;
    try {
      await pending.timeout(const Duration(seconds: 1));
    } catch (_) {}
  }

  void _refreshRemoteConfigInBackground({bool requireEndpoints = true}) {
    if (!_activity.isAvailable) {
      _deferConfigRefresh(requireEndpoints: requireEndpoints);
      return;
    }
    final refresh = () async {
      try {
        await _loadRemoteConfigWithRetries(requireEndpoints: requireEndpoints);
      } catch (_) {}
    }();
    unawaited(refresh);
  }

  void _deferConfigRefresh({required bool requireEndpoints}) {
    _cacheState.deferredRequireEndpoints |= requireEndpoints;
    _activity._defer(_cacheState, () {
      final requireEndpoints = _cacheState.deferredRequireEndpoints;
      _cacheState.deferredRequireEndpoints = false;
      _refreshRemoteConfigInBackground(requireEndpoints: requireEndpoints);
    });
  }

  ApiRemoteConfigException _classifyRemoteError(
    Object error,
    Uri? source, {
    int? elapsedMilliseconds,
    String? attemptId,
  }) {
    if (error is ApiRemoteConfigException && error.diagnostic != null) {
      return error;
    }
    final transport = classifyApiNetworkFailure(
      error is ApiRemoteConfigException ? error.cause ?? error : error,
      stage: 'remote_config',
      endpoint: source,
      statusCode: error is ApiRemoteConfigException ? error.statusCode : null,
      elapsedMilliseconds: elapsedMilliseconds,
      attemptId: attemptId,
    );
    final failure = switch (error) {
      ApiRemoteConfigException() => error.failure,
      RemoteConfigCipherException() => switch (error.failure) {
        RemoteConfigCipherFailure.keyMismatch ||
        RemoteConfigCipherFailure.signature => ApiRemoteConfigFailure.signature,
        _ => ApiRemoteConfigFailure.decrypt,
      },
      _ => switch (transport.failure) {
        ApiNetworkFailure.timeout => ApiRemoteConfigFailure.timeout,
        ApiNetworkFailure.dns => ApiRemoteConfigFailure.dns,
        _ => ApiRemoteConfigFailure.http,
      },
    };
    return ApiRemoteConfigException(
      failure: failure,
      source: source,
      statusCode: transport.statusCode,
      cause: error,
      diagnostic: ApiNetworkDiagnostic(
        failure: switch (failure) {
          ApiRemoteConfigFailure.decrypt => ApiNetworkFailure.configDecrypt,
          ApiRemoteConfigFailure.signature => ApiNetworkFailure.configSignature,
          ApiRemoteConfigFailure.configuration =>
            ApiNetworkFailure.configuration,
          ApiRemoteConfigFailure.endpointsEmpty =>
            ApiNetworkFailure.noEndpoints,
          ApiRemoteConfigFailure.dns => ApiNetworkFailure.dns,
          ApiRemoteConfigFailure.timeout => ApiNetworkFailure.timeout,
          _ => transport.failure,
        },
        stage: transport.stage,
        statusCode: transport.statusCode,
        osErrorCode: transport.osErrorCode,
        endpointRef: transport.endpointRef,
        elapsedMilliseconds: elapsedMilliseconds,
        attemptId: attemptId,
      ),
    );
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

  Future<Object?> _loadRemoteConfig(
    Uri configUri, {
    bool forceRefresh = false,
  }) async {
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
          headers: forceRefresh
              ? const {
                  'Cache-Control': 'no-cache, no-store, max-age=0',
                  'Pragma': 'no-cache',
                }
              : null,
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
    try {
      final origin = endpoint.replace(path: '/', query: null, fragment: null);
      final response = await dio
          .getUri<Object?>(
            origin.resolve(_apiEndpointHealthPath),
            options: Options(
              responseType: ResponseType.json,
              headers: const {
                'Accept': 'application/json',
                'Cache-Control': 'no-cache',
              },
              validateStatus: (status) =>
                  status != null && status >= 200 && status < 300,
            ),
          )
          .timeout(probeTimeout);
      final body = response.data;
      return body is Map &&
          body['status']?.toString().toLowerCase() == 'success' &&
          body['data'] is Map;
    } finally {
      dio.close(force: true);
    }
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

Object? _freezeConfigValue(Object? value) => switch (value) {
  final Map value => Map.unmodifiable(
    value.map((key, value) => MapEntry(key, _freezeConfigValue(value))),
  ),
  final List value => List.unmodifiable(value.map(_freezeConfigValue)),
  _ => value,
};

Object? _copyConfigValue(Object? value) => switch (value) {
  final Map value => value.map(
    (key, value) => MapEntry(key, _copyConfigValue(value)),
  ),
  final List value => value.map(_copyConfigValue).toList(),
  _ => value,
};

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

import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';

import 'api_network_diagnostic.dart';

class ApiRequestRouter {
  ApiRequestRouter({
    DateTime Function()? now,
    this.initialCooldown = const Duration(seconds: 15),
    this.maximumCooldown = const Duration(minutes: 2),
    this.recoveryProbeLease = const Duration(seconds: 45),
  }) : _now = now ?? DateTime.now;

  static final shared = ApiRequestRouter();
  static const Object _unspecifiedProbeToken = Object();

  final DateTime Function() _now;
  final Duration initialCooldown;
  final Duration maximumCooldown;
  final Duration recoveryProbeLease;
  final Map<String, Map<String, _ApiEndpointHealth>> _scopes = {};

  List<Uri> orderCandidates(
    Iterable<Uri> candidates, {
    Uri? preferred,
    Iterable<Uri>? eligibleCandidates,
    bool reserveRecoveryProbe = false,
  }) {
    final fullPool = _validCandidates(candidates);
    final eligibleOrigins = eligibleCandidates == null
        ? null
        : _validCandidates(eligibleCandidates).map(_origin).toSet();
    final values = fullPool
        .where(
          (endpoint) =>
              eligibleOrigins == null ||
              eligibleOrigins.contains(_origin(endpoint)),
        )
        .toList();
    final scope = _scopes[_scopeKey(fullPool)];
    final now = _now();
    bool probeReserved(_ApiEndpointHealth? health) =>
        health?.probeUntil != null && now.isBefore(health!.probeUntil!);
    if (reserveRecoveryProbe) {
      values.removeWhere(
        (endpoint) => probeReserved(scope?[_origin(endpoint)]),
      );
    }
    final positions = <Uri, int>{
      for (var index = 0; index < values.length; index++) values[index]: index,
    };
    int rank(Uri endpoint) {
      final health = scope?[_origin(endpoint)];
      if (health?.retryAt != null) {
        return probeReserved(health) || now.isBefore(health!.retryAt!) ? 3 : 0;
      }
      if (health?.succeededAt != null) return 1;
      return 2;
    }

    values.sort((left, right) {
      if (left == right) return 0;
      final leftRank = rank(left);
      final rightRank = rank(right);
      if (leftRank != rightRank) return leftRank.compareTo(rightRank);
      final leftHealth = scope?[_origin(left)];
      final rightHealth = scope?[_origin(right)];
      if (leftRank == 3 || leftRank == 0) {
        final timeOrder = leftHealth!.retryAt!.compareTo(rightHealth!.retryAt!);
        if (timeOrder != 0) return timeOrder;
      }
      if (leftRank == 1) {
        final timeOrder = rightHealth!.succeededAt!.compareTo(
          leftHealth!.succeededAt!,
        );
        if (timeOrder != 0) return timeOrder;
      }
      final preferredOrigin = preferred == null ? null : _origin(preferred);
      if (_origin(left) == preferredOrigin) return -1;
      if (_origin(right) == preferredOrigin) return 1;
      return positions[left]!.compareTo(positions[right]!);
    });
    if (reserveRecoveryProbe && values.isNotEmpty && rank(values.first) == 0) {
      final health = scope![_origin(values.first)]!;
      health.probeUntil = now.add(recoveryProbeLease);
      health.probeToken = Object();
    }
    return List.unmodifiable(values);
  }

  Object? recoveryProbeToken(
    Uri endpoint, {
    required Iterable<Uri> candidates,
  }) {
    final scope = _scopes[_scopeKey(_validCandidates(candidates))];
    return scope?[_origin(endpoint)]?.probeToken;
  }

  void recordSuccess(
    Uri endpoint, {
    required Iterable<Uri> candidates,
    Object? probeToken = _unspecifiedProbeToken,
  }) {
    final health = _healthFor(endpoint, candidates);
    if (health == null) return;
    health.failures = 0;
    health.retryAt = null;
    releaseRecoveryProbe(
      endpoint,
      candidates: candidates,
      probeToken: probeToken,
    );
    health.succeededAt = _now();
  }

  bool recordFailure(
    Uri endpoint, {
    required Iterable<Uri> candidates,
    Object? error,
    int? statusCode,
    Object? probeToken = _unspecifiedProbeToken,
  }) {
    if (!isRecoverableFailure(error: error, statusCode: statusCode)) {
      releaseRecoveryProbe(
        endpoint,
        candidates: candidates,
        probeToken: probeToken,
      );
      return false;
    }
    final health = _healthFor(endpoint, candidates);
    if (health == null) return false;
    health.failures = (health.failures + 1).clamp(1, 8);
    final milliseconds =
        (initialCooldown.inMilliseconds * (1 << (health.failures - 1))).clamp(
          0,
          maximumCooldown.inMilliseconds,
        );
    health.retryAt = _now().add(Duration(milliseconds: milliseconds));
    releaseRecoveryProbe(
      endpoint,
      candidates: candidates,
      probeToken: probeToken,
    );
    return true;
  }

  void releaseRecoveryProbe(
    Uri endpoint, {
    required Iterable<Uri> candidates,
    Object? probeToken = _unspecifiedProbeToken,
  }) {
    final scope = _scopes[_scopeKey(_validCandidates(candidates))];
    final health = scope?[_origin(endpoint)];
    if (health == null ||
        (!identical(probeToken, _unspecifiedProbeToken) &&
            !identical(probeToken, health.probeToken))) {
      return;
    }
    health.probeUntil = null;
    health.probeToken = null;
  }

  void clear() => _scopes.clear();

  static bool isRecoverableFailure({Object? error, int? statusCode}) {
    if (error is ApiNetworkDiagnostic &&
        {
          ApiNetworkFailure.tls,
          ApiNetworkFailure.cancelled,
        }.contains(error.failure)) {
      return false;
    }
    if (error is DioException &&
        {
          DioExceptionType.badCertificate,
          DioExceptionType.cancel,
        }.contains(error.type)) {
      return false;
    }
    statusCode ??= error is ApiNetworkDiagnostic ? error.statusCode : null;
    statusCode ??= error is DioException ? error.response?.statusCode : null;
    if (statusCode != null) return {502, 503, 504}.contains(statusCode);
    if (error is! ApiNetworkDiagnostic &&
        error is! DioException &&
        error is! SocketException &&
        error is! TimeoutException) {
      return false;
    }
    if (error is DioException && error.type == DioExceptionType.unknown) {
      return error.error != null &&
          !identical(error.error, error) &&
          isRecoverableFailure(error: error.error);
    }
    final failure = error is ApiNetworkDiagnostic
        ? error.failure
        : classifyApiNetworkFailure(error!, stage: 'api_request').failure;
    return {
      ApiNetworkFailure.dns,
      ApiNetworkFailure.timeout,
      ApiNetworkFailure.connectionRefused,
      ApiNetworkFailure.connectionReset,
      ApiNetworkFailure.network,
    }.contains(failure);
  }

  _ApiEndpointHealth? _healthFor(Uri endpoint, Iterable<Uri> candidates) {
    final values = _validCandidates(candidates);
    final origin = _origin(endpoint);
    if (!values.any((value) => _origin(value) == origin)) return null;
    final key = _scopeKey(values);
    if (!_scopes.containsKey(key) && _scopes.length >= 32) {
      _scopes.remove(_scopes.keys.first);
    }
    final scope = _scopes.putIfAbsent(key, () => {});
    return scope.putIfAbsent(origin, _ApiEndpointHealth.new);
  }

  static List<Uri> _validCandidates(Iterable<Uri> candidates) {
    final origins = <String>{};
    return candidates
        .where(
          (endpoint) =>
              {'http', 'https'}.contains(endpoint.scheme) &&
              endpoint.host.isNotEmpty &&
              endpoint.userInfo.isEmpty &&
              origins.add(_origin(endpoint)),
        )
        .toList();
  }

  static String _origin(Uri endpoint) =>
      '${endpoint.scheme.toLowerCase()}://${endpoint.host.toLowerCase()}:${endpoint.port}';

  static String _scopeKey(Iterable<Uri> candidates) =>
      (candidates.map(_origin).toList()..sort()).join('|');
}

class _ApiEndpointHealth {
  int failures = 0;
  DateTime? retryAt;
  DateTime? probeUntil;
  Object? probeToken;
  DateTime? succeededAt;
}

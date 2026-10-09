import 'dart:async';

import 'package:dio/dio.dart';

import 'api_health.dart';
import 'api_request_router.dart';

class XboardApiRequestExecutor {
  XboardApiRequestExecutor({
    ApiHealthService? apiHealthService,
    ApiRequestRouter? router,
    Future<Object?> Function()? configLoader,
    this.singleEndpointSimulation = false,
    this.requestTimeout = const Duration(seconds: 20),
    this.operationTimeout = const Duration(seconds: 45),
  }) : assert(requestTimeout > Duration.zero),
       assert(operationTimeout > Duration.zero),
       _loadCandidates = configLoader != null
           ? (() async => parseApiEndpoints(await configLoader()))
           : (apiHealthService ?? ApiHealthService())
                 .loadVerifiedCandidateEndpoints,
       _router = router ?? ApiRequestRouter.shared;

  final Future<List<Uri>> Function() _loadCandidates;
  final ApiRequestRouter _router;
  final bool singleEndpointSimulation;
  final Duration requestTimeout;
  final Duration operationTimeout;

  Future<T> run<T>({
    required Uri endpoint,
    required bool allowRetry,
    required Future<T> Function(Uri endpoint, CancelToken cancelToken) request,
  }) async {
    if (!{'http', 'https'}.contains(endpoint.scheme) ||
        endpoint.host.isEmpty ||
        endpoint.userInfo.isNotEmpty) {
      throw const FormatException('Invalid API endpoint');
    }
    final scope = _XboardApiRequestScope(operationTimeout);
    try {
      return await _run(
        endpoint: endpoint,
        allowRetry: allowRetry,
        request: request,
        scope: scope,
      ).timeout(
        operationTimeout,
        onTimeout: () {
          scope.cancel();
          throw TimeoutException('api_operation_timeout', operationTimeout);
        },
      );
    } finally {
      scope.cancel();
    }
  }

  Future<T> _run<T>({
    required Uri endpoint,
    required bool allowRetry,
    required Future<T> Function(Uri endpoint, CancelToken cancelToken) request,
    required _XboardApiRequestScope scope,
  }) async {
    final origins = <String>{};
    final candidates = singleEndpointSimulation
        ? [endpoint]
        : (await _loadCandidates())
              .where(
                (candidate) =>
                    {'http', 'https'}.contains(candidate.scheme) &&
                    candidate.host.isNotEmpty &&
                    candidate.userInfo.isEmpty &&
                    origins.add(candidate.origin),
              )
              .toList(growable: false);
    scope.ensureActive();
    final eligible = candidates
        .where(
          (candidate) =>
              endpoint.scheme != 'https' || candidate.scheme == 'https',
        )
        .toList(growable: false);
    if (eligible.isEmpty) {
      throw const FormatException('No trusted API endpoints');
    }
    final tried = <String>{};
    while (tried.length < eligible.length) {
      scope.ensureActive();
      final candidate = _router
          .orderCandidates(
            candidates,
            preferred: endpoint,
            eligibleCandidates: eligible.where(
              (candidate) => !tried.contains(candidate.origin),
            ),
            reserveRecoveryProbe: true,
          )
          .firstOrNull;
      if (candidate == null) break;
      final probeToken = _router.recoveryProbeToken(
        candidate,
        candidates: candidates,
      );
      tried.add(candidate.origin);
      final available = scope.remaining;
      final timeout = available < requestTimeout ? available : requestTimeout;
      final target = endpoint.replace(
        scheme: candidate.scheme,
        host: candidate.host,
        port: candidate.port,
      );
      final cancelToken = CancelToken();
      scope.activeRequest = cancelToken;
      try {
        final result = await Future<T>.sync(() => request(target, cancelToken))
            .timeout(
              timeout,
              onTimeout: () {
                cancelToken.cancel('api_request_timeout');
                throw TimeoutException('api_request_timeout', timeout);
              },
            );
        scope.ensureActive();
        _router.recordSuccess(
          candidate,
          candidates: candidates,
          probeToken: probeToken,
        );
        return result;
      } catch (error, stackTrace) {
        final recoverable =
            scope.active &&
            _router.recordFailure(
              candidate,
              candidates: candidates,
              error: error,
              probeToken: probeToken,
            );
        if (!scope.active ||
            !allowRetry ||
            !recoverable ||
            tried.length == eligible.length) {
          Error.throwWithStackTrace(error, stackTrace);
        }
      } finally {
        if (scope.active) {
          _router.releaseRecoveryProbe(
            candidate,
            candidates: candidates,
            probeToken: probeToken,
          );
        }
        if (identical(scope.activeRequest, cancelToken)) {
          scope.activeRequest = null;
        }
      }
    }
    throw const FormatException('No API request candidates');
  }
}

class _XboardApiRequestScope {
  _XboardApiRequestScope(this.timeout);

  final Duration timeout;
  final Stopwatch _stopwatch = Stopwatch()..start();
  bool active = true;
  CancelToken? activeRequest;

  Duration get remaining => timeout - _stopwatch.elapsed;

  void ensureActive() {
    if (!active || remaining <= Duration.zero) {
      throw TimeoutException('api_operation_timeout', timeout);
    }
  }

  void cancel() {
    active = false;
    activeRequest?.cancel('api_operation_finished');
  }
}

import 'dart:async';

import 'package:dio/dio.dart';

import 'api_health.dart';
import 'api_request_router.dart';

class XboardApiRequestDeferred implements Exception {
  const XboardApiRequestDeferred();

  @override
  String toString() => 'XboardApiRequestDeferred';
}

void ensureXboardApiRequestAllowed(bool Function()? canRequest) {
  if (canRequest?.call() == false) throw const XboardApiRequestDeferred();
}

class XboardApiRequestConsumers {
  final _consumers = <XboardApiRequestConsumer>[];
  bool _closed = false;

  bool get isClosed => _closed;

  bool get aggregateAllowed {
    if (_closed) return false;
    if (_consumers.any((consumer) => consumer.allowed)) return true;
    _closed = true;
    return false;
  }

  XboardApiRequestConsumer add(bool Function()? canRequest) {
    final consumer = XboardApiRequestConsumer._(canRequest);
    _consumers.add(consumer);
    return consumer;
  }

  void inherit(XboardApiRequestConsumers other) {
    _consumers.addAll(other._consumers.where((consumer) => consumer.allowed));
  }

  void close() => _closed = true;
}

class XboardApiRequestConsumer {
  XboardApiRequestConsumer._(this._canRequest);

  final bool Function()? _canRequest;
  bool _allowed = true;

  bool get allowed {
    if (_allowed && _canRequest?.call() == false) _allowed = false;
    return _allowed;
  }

  Future<T> wait<T>(Future<T> future) =>
      _canRequest == null ? future : _wait(future);

  Future<T> _wait<T>(Future<T> future) async {
    if (!allowed) {
      future.ignore();
      throw const XboardApiRequestDeferred();
    }
    try {
      final value = await future;
      ensureXboardApiRequestAllowed(() => allowed);
      return value;
    } catch (_) {
      ensureXboardApiRequestAllowed(() => allowed);
      rethrow;
    }
  }
}

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
    bool Function()? canRequest,
    required Future<T> Function(Uri endpoint, CancelToken cancelToken) request,
  }) async {
    if (!{'http', 'https'}.contains(endpoint.scheme) ||
        endpoint.host.isEmpty ||
        endpoint.userInfo.isNotEmpty) {
      throw const FormatException('Invalid API endpoint');
    }
    ensureXboardApiRequestAllowed(canRequest);
    final scope = _XboardApiRequestScope(operationTimeout);
    try {
      return await _run(
        endpoint: endpoint,
        allowRetry: allowRetry,
        canRequest: canRequest,
        request: request,
        scope: scope,
      ).timeout(
        operationTimeout,
        onTimeout: () {
          scope.cancel();
          throw TimeoutException('api_operation_timeout', operationTimeout);
        },
      );
    } catch (error) {
      if (error is XboardApiRequestDeferred) rethrow;
      ensureXboardApiRequestAllowed(canRequest);
      rethrow;
    } finally {
      scope.cancel();
    }
  }

  Future<T> _run<T>({
    required Uri endpoint,
    required bool allowRetry,
    required bool Function()? canRequest,
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
    ensureXboardApiRequestAllowed(canRequest);
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
      ensureXboardApiRequestAllowed(canRequest);
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
      void releaseProbe() => _router.releaseRecoveryProbe(
        candidate,
        candidates: candidates,
        probeToken: probeToken,
      );
      scope.releaseProbe = releaseProbe;
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
        ensureXboardApiRequestAllowed(canRequest);
        final result = await Future<T>.sync(() => request(target, cancelToken))
            .timeout(
              timeout,
              onTimeout: () {
                cancelToken.cancel('api_request_timeout');
                throw TimeoutException('api_request_timeout', timeout);
              },
            );
        scope.ensureActive();
        ensureXboardApiRequestAllowed(canRequest);
        _router.recordSuccess(
          candidate,
          candidates: candidates,
          probeToken: probeToken,
        );
        return result;
      } catch (error, stackTrace) {
        if (error is XboardApiRequestDeferred) rethrow;
        ensureXboardApiRequestAllowed(canRequest);
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
        releaseProbe();
        if (identical(scope.releaseProbe, releaseProbe)) {
          scope.releaseProbe = null;
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
  void Function()? releaseProbe;

  Duration get remaining => timeout - _stopwatch.elapsed;

  void ensureActive() {
    if (!active || remaining <= Duration.zero) {
      throw TimeoutException('api_operation_timeout', timeout);
    }
  }

  void cancel() {
    active = false;
    activeRequest?.cancel('api_operation_finished');
    releaseProbe?.call();
    releaseProbe = null;
  }
}

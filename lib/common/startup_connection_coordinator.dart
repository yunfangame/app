import 'dart:async';

class StartupConnectionAttempt {
  StartupConnectionAttempt._(this._enabled, this._isSessionCurrent);

  final bool _enabled;
  final bool Function() _isSessionCurrent;
  final _cancelled = Completer<void>();
  Future<void>? _execution;

  void _cancel() {
    if (!_cancelled.isCompleted) _cancelled.complete();
  }
}

class StartupConnectionCoordinator {
  StartupConnectionCoordinator({
    Duration probeTimeout = const Duration(seconds: 8),
  }) : _probeTimeout = probeTimeout;

  final Duration _probeTimeout;
  StartupConnectionAttempt? _active;
  bool _disposed = false;

  StartupConnectionAttempt begin({
    required bool enabled,
    required bool Function() isCurrent,
  }) {
    if (_disposed) throw StateError('startup_connection_disposed');
    cancel();
    return _active = StartupConnectionAttempt._(enabled, isCurrent);
  }

  bool _isCurrent(StartupConnectionAttempt attempt) {
    if (_disposed ||
        !identical(attempt, _active) ||
        !attempt._enabled ||
        attempt._cancelled.isCompleted) {
      return false;
    }
    if (!attempt._isSessionCurrent()) {
      attempt._cancel();
      return false;
    }
    return true;
  }

  Future<void> run(
    StartupConnectionAttempt attempt, {
    required bool authenticated,
    required bool routingReady,
    required bool Function() canProceed,
    required Future<void> Function(bool Function() isCurrent) testLatency,
    required bool Function() isConnected,
    required Future<void> Function() connect,
    required void Function(Object error) onProbeError,
    required void Function(Object error) onConnectionError,
  }) {
    if (!_isCurrent(attempt) || !authenticated || !routingReady) {
      return Future<void>.value();
    }
    final pending = attempt._execution;
    if (pending != null) return pending;
    final completion = Completer<void>();
    attempt._execution = completion.future;
    completion.complete(
      _run(
        attempt,
        canProceed: canProceed,
        testLatency: testLatency,
        isConnected: isConnected,
        connect: connect,
        onProbeError: onProbeError,
        onConnectionError: onConnectionError,
      ),
    );
    return completion.future;
  }

  Future<void> _run(
    StartupConnectionAttempt attempt, {
    required bool Function() canProceed,
    required Future<void> Function(bool Function() isCurrent) testLatency,
    required bool Function() isConnected,
    required Future<void> Function() connect,
    required void Function(Object error) onProbeError,
    required void Function(Object error) onConnectionError,
  }) async {
    bool canContinue() {
      if (!_isCurrent(attempt)) return false;
      if (!canProceed()) {
        attempt._cancel();
        return false;
      }
      return true;
    }

    if (!canContinue()) return;
    var probeActive = true;
    bool probeIsCurrent() => probeActive && canContinue();
    Object? probeError;
    try {
      await Future.any<void>([
        Future<void>.sync(() => testLatency(probeIsCurrent)).whenComplete(() {
          probeActive = false;
        }),
        attempt._cancelled.future,
      ]).timeout(
        _probeTimeout,
        onTimeout: () {
          probeActive = false;
          throw TimeoutException('startup_latency_timeout', _probeTimeout);
        },
      );
    } catch (error) {
      probeError = error;
    } finally {
      probeActive = false;
    }
    if (!canContinue()) return;
    if (probeError != null) onProbeError(probeError);
    if (!canContinue() || isConnected()) return;
    try {
      await connect();
    } catch (error) {
      if (canContinue()) onConnectionError(error);
    }
  }

  void cancel() {
    _active?._cancel();
    _active = null;
  }

  void dispose() {
    if (_disposed) return;
    cancel();
    _disposed = true;
  }
}

import 'dart:async';

typedef ExitStep = Future<void> Function();

final class NetworkCleanupException implements Exception {
  final String message;

  const NetworkCleanupException(this.message);

  @override
  String toString() => message;
}

final class SystemExitCoordinator {
  final Duration watchdogDuration;
  final ExitStep closeWindow;
  final ExitStep closeCore;
  final ExitStep exitApplication;
  final ExitStep? prepareExit;
  final Duration preparationTimeout;
  final void Function(String phase)? onPhase;

  Future<void>? _operation;
  Future<void>? _applicationExitOperation;

  SystemExitCoordinator({
    required this.watchdogDuration,
    required this.closeWindow,
    required this.closeCore,
    required this.exitApplication,
    this.prepareExit,
    this.preparationTimeout = const Duration(seconds: 30),
    this.onPhase,
  });

  bool get applicationExitRequested => _applicationExitOperation != null;

  Future<void> exit({required ExitStep cleanup}) {
    final activeOperation = _operation;
    if (activeOperation != null) {
      return activeOperation;
    }
    late final Future<void> operation;
    operation = _run(cleanup).whenComplete(() {
      if (identical(_operation, operation) && !applicationExitRequested) {
        _operation = null;
      }
    });
    _operation = operation;
    return operation;
  }

  Future<void> _run(ExitStep cleanup) async {
    onPhase?.call('prepare');
    try {
      final prepare = prepareExit;
      if (prepare != null) await prepare().timeout(preparationTimeout);
    } catch (_) {
      onPhase?.call('prepare_failed');
      rethrow;
    }
    onPhase?.call('prepared');
    Object? firstError;
    StackTrace? firstStackTrace;

    Future<void> runStep(ExitStep step) async {
      try {
        await step();
      } catch (error, stackTrace) {
        firstError ??= error;
        firstStackTrace ??= stackTrace;
      }
    }

    final watchdog = Timer(watchdogDuration, () {
      onPhase?.call('watchdog');
      unawaited(_exitApplicationOnce().catchError((_) {}));
    });
    try {
      onPhase?.call('cleanup');
      await runStep(cleanup);
      onPhase?.call('window');
      await runStep(closeWindow);
      onPhase?.call('core');
      await runStep(closeCore);
    } finally {
      watchdog.cancel();
      await runStep(_exitApplicationOnce);
    }
    final error = firstError;
    if (error != null) {
      Error.throwWithStackTrace(error, firstStackTrace!);
    }
  }

  Future<void> _exitApplicationOnce() {
    final activeOperation = _applicationExitOperation;
    if (activeOperation != null) {
      return activeOperation;
    }
    final operation = Future<void>.sync(exitApplication);
    _applicationExitOperation = operation;
    return operation;
  }
}

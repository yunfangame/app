import 'dart:async';

class PostLoginProfileSyncCoordinator {
  int? _revision;
  Object? _attempt;
  Future<bool>? _pending;
  bool Function()? _isCurrent;

  Future<bool> run({
    required int sessionRevision,
    required bool Function() isCurrent,
    required void Function() enterOnline,
    required Future<bool> Function(bool Function() isCurrent) sync,
    void Function()? onStarted,
    Future<void> Function()? onSettled,
    void Function(String reason)? onDiagnostic,
  }) {
    if (!isCurrent()) {
      onDiagnostic?.call('inactive');
      return Future.value(false);
    }
    if (_revision == sessionRevision &&
        _pending != null &&
        _isCurrent?.call() == true) {
      onDiagnostic?.call('coalesced');
      return _pending!;
    }
    final attempt = Object();
    final completer = Completer<bool>();
    _revision = sessionRevision;
    _attempt = attempt;
    _pending = completer.future;
    bool current() => identical(_attempt, attempt) && isCurrent();
    _isCurrent = current;
    onDiagnostic?.call('started');
    unawaited(() async {
      try {
        var started = false;
        var completed = false;
        try {
          enterOnline();
          if (current()) {
            started = true;
            onStarted?.call();
            completed = await sync(current);
          }
        } finally {
          if (started && identical(_attempt, attempt)) {
            await onSettled?.call();
          }
        }
        final stillCurrent = current();
        final accepted = stillCurrent && completed;
        if (!accepted && identical(_attempt, attempt)) cancel();
        onDiagnostic?.call(
          !stillCurrent
              ? 'superseded'
              : accepted
              ? 'completed'
              : 'not_completed',
        );
        completer.complete(accepted);
      } catch (error, stackTrace) {
        if (identical(_attempt, attempt)) cancel();
        onDiagnostic?.call('failed');
        completer.completeError(error, stackTrace);
      }
    }());
    return completer.future;
  }

  void cancel() {
    _revision = null;
    _attempt = null;
    _pending = null;
    _isCurrent = null;
  }
}

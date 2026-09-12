import 'dart:async';

enum ApplicationReadiness { pending, ready, failed, timedOut, disposed }

void runPostAuthenticationTask({
  required Future<void> Function() task,
  required void Function(Object error, StackTrace stackTrace) onError,
}) {
  unawaited(() async {
    try {
      await task();
    } catch (error, stackTrace) {
      onError(error, stackTrace);
    }
  }());
}

class AuthenticationBootstrapController {
  Timer? _timer;
  int _revision = 0;
  bool _active = false;
  bool _disposed = false;

  int begin({
    required Duration timeout,
    required void Function(int revision) onTimeout,
  }) {
    if (_disposed) throw StateError('authentication_bootstrap_disposed');
    _timer?.cancel();
    final revision = ++_revision;
    _active = true;
    _timer = Timer(timeout, () {
      if (!isCurrent(revision)) return;
      onTimeout(revision);
    });
    return revision;
  }

  bool isCurrent(int revision) {
    return !_disposed && _active && revision == _revision;
  }

  bool complete(int revision) {
    if (!isCurrent(revision)) return false;
    _active = false;
    _timer?.cancel();
    _timer = null;
    return true;
  }

  void cancel() {
    _revision++;
    _active = false;
    _timer?.cancel();
    _timer = null;
  }

  void dispose() {
    if (_disposed) return;
    cancel();
    _disposed = true;
  }
}

class ApplicationReadinessGate {
  final Completer<ApplicationReadiness> _initialOutcome = Completer();
  Timer? _timer;
  ApplicationReadiness _status = ApplicationReadiness.pending;

  ApplicationReadiness get status => _status;

  Future<ApplicationReadiness> wait() {
    if (_status != ApplicationReadiness.pending) {
      return Future.value(_status);
    }
    return _initialOutcome.future;
  }

  void startTimeout({
    required Duration timeout,
    required void Function() onTimeout,
  }) {
    if (_status != ApplicationReadiness.pending || _timer != null) return;
    _timer = Timer(timeout, () {
      if (!_settle(ApplicationReadiness.timedOut)) return;
      onTimeout();
    });
  }

  bool ready() {
    if (_status == ApplicationReadiness.timedOut) {
      _status = ApplicationReadiness.ready;
      _timer?.cancel();
      _timer = null;
      return true;
    }
    return _settle(ApplicationReadiness.ready);
  }

  bool fail() {
    if (_status == ApplicationReadiness.timedOut) {
      _status = ApplicationReadiness.failed;
      _timer?.cancel();
      _timer = null;
      return true;
    }
    return _settle(ApplicationReadiness.failed);
  }

  bool _settle(ApplicationReadiness outcome) {
    if (_status != ApplicationReadiness.pending) return false;
    _status = outcome;
    _timer?.cancel();
    _timer = null;
    _initialOutcome.complete(outcome);
    return true;
  }

  void dispose() {
    if (_status == ApplicationReadiness.disposed) return;
    if (_status == ApplicationReadiness.pending) {
      _settle(ApplicationReadiness.disposed);
      return;
    }
    _timer?.cancel();
    _timer = null;
    _status = ApplicationReadiness.disposed;
  }
}

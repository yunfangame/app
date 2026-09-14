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

class AuthenticationBootstrapCredentials<T> {
  const AuthenticationBootstrapCredentials({
    required this.revision,
    required this.value,
    required this.resumed,
  });

  final int revision;
  final T value;
  final bool resumed;
}

class AuthenticationBootstrapController {
  Timer? _timer;
  int _revision = 0;
  bool _active = false;
  bool _disposed = false;
  int? _credentialsRevision;
  int? _deferredCredentialsRevision;

  bool get hasPendingWork => _active || _deferredCredentialsRevision != null;

  int begin({
    required Duration timeout,
    required void Function(int revision) onTimeout,
  }) {
    if (_disposed) throw StateError('authentication_bootstrap_disposed');
    _timer?.cancel();
    _credentialsRevision = null;
    _deferredCredentialsRevision = null;
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

  Future<AuthenticationBootstrapCredentials<T>?> loadCredentials<T>(
    int revision, {
    required Future<T> Function() load,
    required Duration timeout,
    required void Function(int revision) onTimeout,
  }) async {
    if (!isCurrent(revision) || _credentialsRevision != null) return null;
    _credentialsRevision = revision;
    try {
      final value = await load();
      if (_credentialsRevision != revision) return null;
      _credentialsRevision = null;
      final resumed = _deferredCredentialsRevision == revision;
      if (resumed) {
        final nextRevision = begin(timeout: timeout, onTimeout: onTimeout);
        return AuthenticationBootstrapCredentials(
          revision: nextRevision,
          value: value,
          resumed: true,
        );
      }
      if (!isCurrent(revision)) return null;
      return AuthenticationBootstrapCredentials(
        revision: revision,
        value: value,
        resumed: false,
      );
    } catch (_) {
      if (_deferredCredentialsRevision == revision) cancel();
      rethrow;
    } finally {
      if (_credentialsRevision == revision) _credentialsRevision = null;
    }
  }

  bool deferForCredentials(int revision) {
    if (!isCurrent(revision) || _credentialsRevision != revision) {
      return false;
    }
    _active = false;
    _deferredCredentialsRevision = revision;
    _timer?.cancel();
    _timer = null;
    return true;
  }

  bool complete(int revision) {
    if (!isCurrent(revision)) return false;
    _active = false;
    _credentialsRevision = null;
    _deferredCredentialsRevision = null;
    _timer?.cancel();
    _timer = null;
    return true;
  }

  void cancel() {
    _revision++;
    _active = false;
    _credentialsRevision = null;
    _deferredCredentialsRevision = null;
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

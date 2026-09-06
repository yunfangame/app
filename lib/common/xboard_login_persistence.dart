import 'diagnostic_log.dart';
import 'function.dart';
import 'xboard_auth.dart';
import 'xboard_session_storage.dart';

class XboardLoginPersistence {
  XboardLoginPersistence({
    required XboardSessionStorage storage,
    void Function(String, Map<String, Object?>)? onDiagnostic,
  }) : _storage = storage,
       _onDiagnostic = onDiagnostic;

  final XboardSessionStorage _storage;
  final void Function(String, Map<String, Object?>)? _onDiagnostic;
  final _scheduler = SerialTaskScheduler();
  XboardStoredSession _state = const XboardStoredSession(
    rememberMe: false,
    autoLogin: false,
  );
  int _revision = 0;

  XboardStoredSession get state => _state;

  Future<XboardStoredSession> load() {
    final revision = _revision;
    return _scheduler.run(() async {
      try {
        final stored = await _storage.load();
        if (revision == _revision) {
          _state = stored.hasStorageError
              ? _mergeCredentials(stored, _state)
              : stored;
        }
      } catch (error) {
        if (revision == _revision) {
          _state = _credentialsOnly(_state, hasStorageError: true);
        }
        _error('load', error);
      }
      _record('auth.credentials.loaded');
      return _state;
    });
  }

  Future<bool> saveAuthenticated({
    required XboardLoginResult session,
    required String email,
    required String password,
    required bool rememberMe,
    required bool autoLogin,
  }) {
    final revision = ++_revision;
    final previous = _state;
    final memory = XboardStoredSession(
      rememberMe: rememberMe,
      autoLogin: false,
      email: rememberMe ? email.trim() : null,
      password: !rememberMe
          ? null
          : password.isNotEmpty
          ? password
          : _sameAccount(previous.email, email)
          ? previous.password
          : null,
    );
    _state = memory;
    _emit('auth.credentials.save.requested', {
      'account_ref': diagnosticFingerprint(email),
      'remember_requested': rememberMe,
      'auto_login_requested': autoLogin,
      'password_provided': password.isNotEmpty,
    });
    return _scheduler.run(() async {
      try {
        await _storage.save(
          email: email,
          password: password,
          rememberMe: rememberMe,
          autoLogin: autoLogin,
          endpoint: session.endpoint,
          token: session.token,
          authData: session.authData,
          isAdmin: session.isAdmin,
          secureSubscription: session.secureSubscription,
        );
        final stored = await _storage.load();
        if (stored.hasStorageError ||
            stored.rememberMe != rememberMe ||
            (rememberMe && !_sameAccount(stored.email, email)) ||
            (rememberMe &&
                password.isNotEmpty &&
                stored.password != password)) {
          throw StateError('credential_readback_failed');
        }
        if (revision != _revision) return false;
        _state = stored;
        _record('auth.credentials.save.verified');
        return true;
      } catch (error) {
        if (revision == _revision) {
          _state = _credentialsOnly(memory, hasStorageError: true);
        }
        _error('save', error);
        return false;
      }
    });
  }

  Future<XboardStoredSession> prepareForLogout() {
    final revision = ++_revision;
    final fallback = _credentialsOnly(_state);
    _state = fallback;
    return _scheduler.run(() async {
      try {
        final stored = await _storage.prepareForLogout();
        if (revision == _revision) {
          _state = _credentialsOnly(
            stored.hasStorageError || fallback.hasStorageError
                ? _mergeCredentials(stored, fallback)
                : stored,
          );
        }
      } catch (error) {
        if (revision == _revision) {
          _state = _credentialsOnly(fallback, hasStorageError: true);
        }
        _error('logout', error);
      }
      _record('auth.credentials.logout.prefill');
      return _state;
    });
  }

  Future<bool> forget() {
    final revision = ++_revision;
    _state = const XboardStoredSession(rememberMe: false, autoLogin: false);
    return _scheduler.run(() async {
      try {
        await _storage.clear();
        _record('auth.credentials.forget.completed');
        return true;
      } catch (error) {
        if (revision == _revision) {
          _state = _credentialsOnly(_state, hasStorageError: true);
        }
        _error('forget', error);
        return false;
      }
    });
  }

  Future<bool> disableAutoLogin() {
    ++_revision;
    final stored = _state;
    _state = XboardStoredSession(
      rememberMe: stored.rememberMe,
      autoLogin: false,
      email: stored.email,
      password: stored.password,
      endpoint: stored.endpoint,
      token: stored.token,
      authData: stored.authData,
      isAdmin: stored.isAdmin,
      secureSubscription: stored.secureSubscription,
      hasStorageError: stored.hasStorageError,
    );
    return _scheduler.run(() async {
      try {
        await _storage.disableAutoLogin();
        _record('auth.credentials.auto_login.disabled');
        return true;
      } catch (error) {
        _error('disable_auto_login', error);
        return false;
      }
    });
  }

  Future<bool> invalidateSession() {
    ++_revision;
    _state = _credentialsOnly(_state);
    return _scheduler.run(() async {
      try {
        await _storage.clearInvalidSession();
        _record('auth.credentials.session.invalidated');
        return true;
      } catch (error) {
        _error('invalidate_session', error);
        return false;
      }
    });
  }

  XboardStoredSession _mergeCredentials(
    XboardStoredSession stored,
    XboardStoredSession fallback,
  ) {
    final canUseFallback =
        fallback.rememberMe &&
        (stored.email == null || _sameAccount(stored.email, fallback.email));
    final preferFallbackPassword =
        canUseFallback &&
        fallback.hasStorageError &&
        (fallback.password?.isNotEmpty ?? false);
    return XboardStoredSession(
      rememberMe: stored.rememberMe || canUseFallback,
      autoLogin: false,
      email: stored.email ?? (canUseFallback ? fallback.email : null),
      password: preferFallbackPassword
          ? fallback.password
          : stored.password ?? (canUseFallback ? fallback.password : null),
      hasStorageError: stored.hasStorageError || fallback.hasStorageError,
    );
  }

  XboardStoredSession _credentialsOnly(
    XboardStoredSession stored, {
    bool? hasStorageError,
  }) => XboardStoredSession(
    rememberMe: stored.rememberMe,
    autoLogin: false,
    email: stored.rememberMe ? stored.email : null,
    password: stored.rememberMe ? stored.password : null,
    hasStorageError: hasStorageError ?? stored.hasStorageError,
  );

  bool _sameAccount(String? left, String? right) =>
      left != null &&
      right != null &&
      left.trim().toLowerCase() == right.trim().toLowerCase();

  void _record(String event) {
    _emit(event, {
      'remember_requested': _state.rememberMe,
      'auto_login_enabled': _state.autoLogin,
      'email_present': _state.email?.isNotEmpty ?? false,
      'password_present': _state.password?.isNotEmpty ?? false,
      'storage_error': _state.hasStorageError,
    });
  }

  void _error(String stage, Object error) {
    _emit('auth.credentials.$stage.failed', {
      'error_type': error.runtimeType.toString(),
    });
  }

  void _emit(String event, Map<String, Object?> fields) {
    try {
      _onDiagnostic?.call(event, fields);
    } catch (_) {}
  }
}

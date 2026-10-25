import 'dart:async';

import 'package:fl_clash/state.dart';
import 'package:fl_clash/widgets/inherited.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:window_manager/window_manager.dart';

import 'xboard_auth.dart';
import 'xboard_api_request.dart';

class XboardAccountViewRead<T> {
  XboardAccountViewRead({this.ttl = Duration.zero, DateTime Function()? now})
    : _now = now ?? DateTime.now;

  final Duration ttl;
  final DateTime Function() _now;
  _AccountViewRequest<T>? _normal;
  _AccountViewRequest<T>? _forced;
  T? _value;
  DateTime? _at;
  int _revision = 0;

  int get revision => _revision;

  Future<T> load(
    Future<T> Function() loader, {
    bool forceRefresh = false,
    bool Function()? canRequest,
  }) => loadGuarded(
    (_) => loader(),
    forceRefresh: forceRefresh,
    canRequest: canRequest,
  );

  Future<T> loadGuarded(
    Future<T> Function(bool Function() canRequest) loader, {
    bool forceRefresh = false,
    bool Function()? canRequest,
  }) {
    final forced = _forced;
    if (forced != null && forced.consumers.aggregateAllowed) {
      return forced.consumers.add(canRequest).wait(forced.future);
    }
    if (!forceRefresh) {
      final at = _at;
      if (_value != null && at != null) {
        final age = _now().difference(at);
        if (!age.isNegative && age < ttl) {
          if (canRequest?.call() == false) {
            return Future.error(const XboardApiRequestDeferred());
          }
          return Future.value(_value);
        }
      }
      final normal = _normal;
      if (normal != null && normal.consumers.aggregateAllowed) {
        return normal.consumers.add(canRequest).wait(normal.future);
      }
    }
    final request = _AccountViewRequest<T>(_revision + 1);
    final consumer = request.consumers.add(canRequest);
    if (!consumer.allowed) {
      return Future.error(const XboardApiRequestDeferred());
    }
    _revision = request.revision;
    if (forceRefresh) {
      if (_normal != null) {
        request.consumers.inherit(_normal!.consumers);
        _normal!.consumers.close();
      }
      _forced = request;
      _normal = null;
    } else {
      _normal = request;
    }
    bool requestAllowed() =>
        _revision == request.revision && request.consumers.aggregateAllowed;
    unawaited(() async {
      try {
        ensureXboardApiRequestAllowed(requestAllowed);
        final value = await loader(requestAllowed);
        if (_revision == request.revision) {
          ensureXboardApiRequestAllowed(requestAllowed);
          _value = value;
          _at = _now();
        }
        request.completer.complete(value);
      } catch (error, stackTrace) {
        request.completer.completeError(
          error is XboardApiRequestDeferred ||
                  !request.consumers.aggregateAllowed
              ? const XboardApiRequestDeferred()
              : error,
          stackTrace,
        );
      } finally {
        if (identical(_normal, request)) _normal = null;
        if (identical(_forced, request)) _forced = null;
      }
    }());
    return consumer.wait(request.future);
  }

  void invalidate() {
    _revision++;
    _normal?.consumers.close();
    _forced?.consumers.close();
    _normal = null;
    _forced = null;
    _value = null;
    _at = null;
  }
}

class _AccountViewRequest<T> {
  _AccountViewRequest(this.revision);
  final int revision;
  final consumers = XboardApiRequestConsumers();
  final completer = Completer<T>();
  Future<T> get future => completer.future;
}

mixin XboardAccountViewActivity<T extends StatefulWidget> on State<T> {
  final bool _desktop = switch (defaultTargetPlatform) {
    TargetPlatform.windows ||
    TargetPlatform.macOS ||
    TargetPlatform.linux => true,
    _ => false,
  };
  late final _AccountViewObserver _observer;
  XboardLoginResult? _viewSession;
  bool _pageActive = true;
  bool _foreground = true;
  late bool _windowAvailable = !_desktop;
  bool _windowKnownBackground = false;
  bool _requested = true;
  bool _queued = false;
  int _epoch = 0;
  int _activityRevision = 0;
  int _windowRevision = 0;
  int _windowRetries = 0;
  Timer? _windowRetry;

  XboardLoginResult? get accountViewSession =>
      _sameAccount(_viewSession, globalState.xboardSession)
      ? globalState.xboardSession
      : _viewSession;
  int get accountViewEpoch => _epoch;
  int get accountViewActivityRevision => _activityRevision;

  bool Function() createAccountViewReadGuard({bool automatic = true}) {
    final session = accountViewSession;
    final epoch = _epoch;
    final activity = _activityRevision;
    return () =>
        session != null &&
        isCurrentAccountView(session, epoch) &&
        (!automatic || activity == _activityRevision) &&
        (automatic ? canReadAccountView : canUseAccountViewActions);
  }

  bool get accountViewIsForeground => _foreground;
  bool get canReadAccountView => canUseAccountViewActions && _windowAvailable;
  bool get canUseAccountViewActions =>
      mounted &&
      _pageActive &&
      _foreground &&
      !globalState.isOfflineMode &&
      !_windowKnownBackground &&
      _viewSession != null &&
      _sameAccount(_viewSession, globalState.xboardSession);

  void onAccountViewReady();
  void onAccountViewReset();

  bool isCurrentAccountView(XboardLoginResult session, int epoch) =>
      mounted &&
      epoch == _epoch &&
      !globalState.isOfflineMode &&
      _sameAccount(session, _viewSession) &&
      _sameAccount(session, globalState.xboardSession);

  bool _sameAccount(XboardLoginResult? left, XboardLoginResult? right) =>
      left?.endpoint == right?.endpoint && left?.authData == right?.authData;

  @override
  void initState() {
    super.initState();
    _viewSession = globalState.xboardSession;
    final state = WidgetsBinding.instance.lifecycleState;
    _foreground = state == null || state == AppLifecycleState.resumed;
    _observer = _AccountViewObserver(_appChanged, _pauseWindow, _resumeWindow);
    WidgetsBinding.instance.addObserver(_observer);
    globalState.xboardSessionRevisionNotifier.addListener(_sessionChanged);
    globalState.offlineModeNotifier.addListener(_offlineChanged);
    if (_desktop) {
      windowManager.addListener(_observer);
      unawaited(_readWindow());
    }
    _scheduleRead();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final active = PageActivityScope.isActiveOf(context);
    if (_pageActive == active) return;
    _pageActive = active;
    if (!active) _activityRevision++;
    if (active) {
      requestAccountViewRead();
      if (_desktop && !_windowAvailable) _resumeWindow();
    } else {
      _windowRetry?.cancel();
    }
  }

  void requestAccountViewRead() {
    _requested = true;
    _scheduleRead();
  }

  void _scheduleRead() {
    if (!mounted || _queued || !_requested) return;
    _queued = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _queued = false;
      if (!canReadAccountView || !_requested) return;
      _requested = false;
      onAccountViewReady();
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  void _sessionChanged() {
    final session = globalState.xboardSession;
    if (_sameAccount(session, _viewSession)) {
      _viewSession = session;
      return;
    }
    _viewSession = session;
    _epoch++;
    _activityRevision++;
    onAccountViewReset();
    requestAccountViewRead();
  }

  void _offlineChanged() {
    _epoch++;
    _activityRevision++;
    onAccountViewReset();
    requestAccountViewRead();
    if (globalState.isOfflineMode) {
      _windowRevision++;
      _windowRetry?.cancel();
    } else if (_desktop) {
      _resumeWindow();
    }
  }

  void _appChanged(AppLifecycleState state) {
    final foreground = state == AppLifecycleState.resumed;
    if (_foreground == foreground) return;
    _foreground = foreground;
    if (!foreground) _activityRevision++;
    if (!foreground) {
      _windowRevision++;
      _windowRetry?.cancel();
    } else if (_desktop) {
      _resumeWindow();
    } else {
      _scheduleRead();
    }
  }

  void _pauseWindow() {
    _activityRevision++;
    _windowRevision++;
    _windowAvailable = false;
    _windowKnownBackground = true;
    _windowRetry?.cancel();
  }

  void _resumeWindow() {
    _windowKnownBackground = false;
    _windowRetry?.cancel();
    _windowRetries = 0;
    unawaited(_readWindow());
  }

  Future<void> _readWindow() async {
    if (!_desktop ||
        !mounted ||
        !_pageActive ||
        !_foreground ||
        globalState.isOfflineMode) {
      return;
    }
    final revision = ++_windowRevision;
    _windowAvailable = false;
    try {
      final values = await Future.wait([
        windowManager.isVisible(),
        windowManager.isMinimized(),
        windowManager.isFocused(),
      ]).timeout(const Duration(seconds: 2));
      if (!mounted || revision != _windowRevision) return;
      _windowAvailable = values[0] && !values[1] && values[2];
      _windowKnownBackground = !_windowAvailable;
      if (!_windowAvailable) _activityRevision++;
      _windowRetries = 0;
      _scheduleRead();
    } catch (_) {
      if (!mounted || revision != _windowRevision) return;
      if (_pageActive &&
          _foreground &&
          !globalState.isOfflineMode &&
          _windowRetries < 3) {
        final seconds = const [1, 3, 6][_windowRetries++];
        _windowRetry = Timer(Duration(seconds: seconds), () {
          unawaited(_readWindow());
        });
      }
    }
  }

  @override
  void dispose() {
    _epoch++;
    _activityRevision++;
    _windowRevision++;
    _windowRetry?.cancel();
    globalState.xboardSessionRevisionNotifier.removeListener(_sessionChanged);
    globalState.offlineModeNotifier.removeListener(_offlineChanged);
    WidgetsBinding.instance.removeObserver(_observer);
    if (_desktop) windowManager.removeListener(_observer);
    super.dispose();
  }
}

class _AccountViewObserver extends WidgetsBindingObserver with WindowListener {
  _AccountViewObserver(this.appChanged, this.pauseWindow, this.resumeWindow);

  final void Function(AppLifecycleState) appChanged;
  final VoidCallback pauseWindow;
  final VoidCallback resumeWindow;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) => appChanged(state);

  @override
  void onWindowEvent(String eventName) {
    if (eventName == 'hide') pauseWindow();
    if (eventName == 'show') resumeWindow();
  }

  @override
  void onWindowBlur() => pauseWindow();

  @override
  void onWindowMinimize() => pauseWindow();

  @override
  void onWindowFocus() => resumeWindow();

  @override
  void onWindowRestore() => resumeWindow();
}

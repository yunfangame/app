import 'dart:async';

import 'package:fl_clash/state.dart';
import 'package:fl_clash/widgets/inherited.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:window_manager/window_manager.dart';

import 'xboard_auth.dart';

class XboardAccountViewRead<T> {
  XboardAccountViewRead({this.ttl = Duration.zero, DateTime Function()? now})
    : _now = now ?? DateTime.now;

  final Duration ttl;
  final DateTime Function() _now;
  Future<T>? _normal;
  Future<T>? _forced;
  T? _value;
  DateTime? _at;
  int _revision = 0;

  int get revision => _revision;

  Future<T> load(Future<T> Function() loader, {bool forceRefresh = false}) {
    if (_forced != null) return _forced!;
    if (!forceRefresh) {
      final at = _at;
      if (_value != null && at != null) {
        final age = _now().difference(at);
        if (!age.isNegative && age < ttl) return Future.value(_value);
      }
      if (_normal != null) return _normal!;
    }
    final revision = ++_revision;
    final request = Completer<T>();
    if (forceRefresh) {
      _forced = request.future;
      _normal = null;
    } else {
      _normal = request.future;
    }
    unawaited(() async {
      try {
        final value = await loader();
        if (_revision == revision) {
          _value = value;
          _at = _now();
        }
        request.complete(value);
      } catch (error, stackTrace) {
        request.completeError(error, stackTrace);
      } finally {
        if (identical(_normal, request.future)) _normal = null;
        if (identical(_forced, request.future)) _forced = null;
      }
    }());
    return request.future;
  }

  void invalidate() {
    _revision++;
    _normal = null;
    _forced = null;
    _value = null;
    _at = null;
  }
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
  int _windowRevision = 0;
  int _windowRetries = 0;
  Timer? _windowRetry;

  XboardLoginResult? get accountViewSession =>
      _sameAccount(_viewSession, globalState.xboardSession)
      ? globalState.xboardSession
      : _viewSession;
  int get accountViewEpoch => _epoch;
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
    onAccountViewReset();
    requestAccountViewRead();
  }

  void _offlineChanged() {
    _epoch++;
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

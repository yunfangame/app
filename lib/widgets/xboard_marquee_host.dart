import 'dart:async';

import 'package:fl_clash/common/xboard_marquee.dart';
import 'package:fl_clash/state.dart';
import 'package:flutter/widgets.dart';

class XboardMarqueeHost extends StatefulWidget {
  const XboardMarqueeHost({super.key, required this.child});

  final Widget child;

  @override
  State<XboardMarqueeHost> createState() => _XboardMarqueeHostState();
}

class _XboardMarqueeHostState extends State<XboardMarqueeHost>
    with WidgetsBindingObserver {
  Timer? _timer;
  var _foreground = true;

  XboardMarqueeController get _controller =>
      globalState.xboardMarqueeController;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    _foreground = lifecycle == null || lifecycle == AppLifecycleState.resumed;
    globalState.xboardSessionRevisionNotifier.addListener(_sessionChanged);
    globalState.offlineModeNotifier.addListener(_offlineModeChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _sessionChanged();
    });
  }

  void _sessionChanged() {
    unawaited(
      _controller.updateSession(
        globalState.xboardSession,
        offline: globalState.isOfflineMode,
      ),
    );
    _restartTimer();
  }

  void _offlineModeChanged() {
    if (!globalState.isOfflineMode && _foreground) {
      unawaited(_controller.refresh(force: true));
    }
    _restartTimer();
  }

  void _restartTimer() {
    _timer?.cancel();
    _timer = null;
    if (!_foreground ||
        globalState.isOfflineMode ||
        globalState.xboardSession == null) {
      return;
    }
    _timer = Timer.periodic(xboardMarqueeRefreshInterval, (_) {
      unawaited(_controller.refresh());
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final foreground = state == AppLifecycleState.resumed;
    if (_foreground == foreground) return;
    _foreground = foreground;
    if (foreground && !globalState.isOfflineMode) {
      unawaited(_controller.refresh());
    }
    _restartTimer();
  }

  @override
  void dispose() {
    _timer?.cancel();
    globalState.xboardSessionRevisionNotifier.removeListener(_sessionChanged);
    globalState.offlineModeNotifier.removeListener(_offlineModeChanged);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

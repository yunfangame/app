import 'dart:async';

import 'package:fl_clash/common/xboard_marquee.dart';
import 'package:fl_clash/state.dart';
import 'package:flutter/widgets.dart';

class XboardMarqueeHost extends StatefulWidget {
  const XboardMarqueeHost({super.key, this.controller, required this.child});

  @visibleForTesting
  final XboardMarqueeController? controller;
  final Widget child;

  @override
  State<XboardMarqueeHost> createState() => _XboardMarqueeHostState();
}

class _XboardMarqueeHostState extends State<XboardMarqueeHost>
    with WidgetsBindingObserver {
  late final XboardMarqueeController _controller;

  @override
  void initState() {
    super.initState();
    _controller = widget.controller ?? globalState.xboardMarqueeController;
    WidgetsBinding.instance.addObserver(this);
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    _controller.startPolling(
      foreground: lifecycle == null || lifecycle == AppLifecycleState.resumed,
      offline: globalState.isOfflineMode,
    );
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
  }

  void _offlineModeChanged() {
    _controller.setOffline(globalState.isOfflineMode);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _controller.setForeground(state == AppLifecycleState.resumed);
  }

  @override
  void dispose() {
    _controller.setForeground(false);
    _controller.stopPolling();
    globalState.xboardSessionRevisionNotifier.removeListener(_sessionChanged);
    globalState.offlineModeNotifier.removeListener(_offlineModeChanged);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

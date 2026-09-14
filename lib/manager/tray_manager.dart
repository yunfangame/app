import 'dart:async';

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/providers/action.dart';
import 'package:fl_clash/providers/state.dart';
import 'package:fl_clash/state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:tray/tray.dart' as native_tray;

class TrayManager extends ConsumerStatefulWidget {
  final Widget child;

  const TrayManager({super.key, required this.child});

  @override
  ConsumerState<TrayManager> createState() => _TrayContainerState();
}

class _TrayContainerState extends ConsumerState<TrayManager> with TrayListener {
  StreamSubscription<native_tray.TrayEvent>? _linuxEvents;

  void _syncAuthenticationTray() {
    unawaited(ref.read(systemActionProvider.notifier).updateTray());
  }

  @override
  void initState() {
    super.initState();
    if (system.isLinux) {
      _linuxEvents = native_tray.Tray.instance.events.listen((event) {
        if (event is native_tray.TrayMenuItemSelected) render?.active();
      });
    } else {
      trayManager.addListener(this);
    }
    globalState.xboardSessionRevisionNotifier.addListener(
      _syncAuthenticationTray,
    );
    ref.listenManual(trayStateProvider, (prev, next) {
      if (prev != next) {
        ref.read(systemActionProvider.notifier).updateTray();
      }
    });
    if (system.isMacOS) {
      ref.listenManual(trayTitleStateProvider, (prev, next) {
        if (prev != next) {
          tray?.updateTrayTitle(
            showTrayTitle: next.showTrayTitle,
            traffic: next.traffic,
          );
        }
      });
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _syncAuthenticationTray();
    });
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }

  @override
  void onTrayIconRightMouseDown() {
    // ignore: deprecated_member_use
    trayManager.popUpContextMenu(bringAppToFront: true);
  }

  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    render?.active();
    super.onTrayMenuItemClick(menuItem);
  }

  @override
  void onTrayIconMouseDown() {
    window?.show();
  }

  @override
  void dispose() {
    globalState.xboardSessionRevisionNotifier.removeListener(
      _syncAuthenticationTray,
    );
    unawaited(_linuxEvents?.cancel());
    if (!system.isLinux) trayManager.removeListener(this);
    super.dispose();
  }
}

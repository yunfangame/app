import 'dart:async';
import 'dart:io';

import 'package:proxy/proxy.dart';

typedef WindowsProxyInspector =
    Future<ProxyOperationResult> Function(int expectedPort);
typedef WindowsProxyStopper =
    Future<ProxyOperationResult> Function(int expectedPort);
typedef WindowsProxyPortProbe = Future<bool> Function(int port);

enum WindowsProxyRepairStatus {
  cancelled,
  notOwned,
  active,
  cleaned,
  cleanupFailed,
}

class WindowsProxyRepairResult {
  const WindowsProxyRepairResult({
    required this.status,
    required this.inspection,
    this.cleanup,
  });

  final WindowsProxyRepairStatus status;
  final ProxyOperationResult inspection;
  final ProxyOperationResult? cleanup;
}

class WindowsProxyGuard {
  WindowsProxyGuard({
    required WindowsProxyInspector inspector,
    required WindowsProxyStopper stopper,
    WindowsProxyPortProbe? portProbe,
    this.readyTimeout = const Duration(seconds: 5),
    this.retryInterval = const Duration(milliseconds: 200),
  }) : _inspector = inspector,
       _stopper = stopper,
       _portProbe = portProbe ?? _probeLoopbackPort;

  final WindowsProxyInspector _inspector;
  final WindowsProxyStopper _stopper;
  final WindowsProxyPortProbe _portProbe;
  final Duration readyTimeout;
  final Duration retryInterval;

  Future<bool> waitUntilReady(int port, {bool Function()? isCancelled}) async {
    final deadline = DateTime.now().add(readyTimeout);
    do {
      if (isCancelled?.call() == true) return false;
      if (await _portProbe(port)) return true;
      if (!DateTime.now().isBefore(deadline)) return false;
      await Future<void>.delayed(retryInterval);
    } while (true);
  }

  Future<WindowsProxyRepairResult> repairStale(
    int port, {
    bool Function()? isCancelled,
  }) async {
    final inspection = await _inspector(port);
    if (isCancelled?.call() == true) {
      return WindowsProxyRepairResult(
        status: WindowsProxyRepairStatus.cancelled,
        inspection: inspection,
      );
    }
    final expectedServer = '127.0.0.1:$port';
    if (inspection.enabled != true || inspection.server != expectedServer) {
      return WindowsProxyRepairResult(
        status: WindowsProxyRepairStatus.notOwned,
        inspection: inspection,
      );
    }
    final portActive = await _portProbe(port);
    if (isCancelled?.call() == true) {
      return WindowsProxyRepairResult(
        status: WindowsProxyRepairStatus.cancelled,
        inspection: inspection,
      );
    }
    if (portActive) {
      return WindowsProxyRepairResult(
        status: WindowsProxyRepairStatus.active,
        inspection: inspection,
      );
    }
    final cleanup = await _stopper(port);
    return WindowsProxyRepairResult(
      status: cleanup.success
          ? WindowsProxyRepairStatus.cleaned
          : WindowsProxyRepairStatus.cleanupFailed,
      inspection: inspection,
      cleanup: cleanup,
    );
  }

  static Future<bool> _probeLoopbackPort(int port) async {
    Socket? socket;
    try {
      socket = await Socket.connect(
        InternetAddress.loopbackIPv4,
        port,
        timeout: const Duration(milliseconds: 350),
      );
      return true;
    } catch (_) {
      return false;
    } finally {
      socket?.destroy();
    }
  }
}

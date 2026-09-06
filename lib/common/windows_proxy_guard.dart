import 'dart:async';
import 'dart:io';

import 'package:proxy/proxy.dart';

typedef WindowsProxyInspector =
    Future<ProxyOperationResult> Function(int expectedPort);
typedef WindowsProxyStopper =
    Future<ProxyOperationResult> Function(int expectedPort);
typedef WindowsProxyPortProbe = Future<bool> Function(int port);

enum WindowsProxyReadinessStatus { ready, timedOut, cancelled, invalidPort }

class WindowsProxyReadinessResult {
  const WindowsProxyReadinessResult({
    required this.status,
    required this.port,
    required this.attempts,
    required this.elapsed,
    this.lastErrorType,
    this.lastOsErrorCode,
  });

  final WindowsProxyReadinessStatus status;
  final int port;
  final int attempts;
  final Duration elapsed;
  final String? lastErrorType;
  final int? lastOsErrorCode;

  bool get ready => status == WindowsProxyReadinessStatus.ready;

  Map<String, Object?> toDiagnosticData() => {
    'address': '127.0.0.1',
    'target': 'ipv4_loopback',
    'protocol': 'tcp',
    'port': port,
    'status': status.name,
    'attempts': attempts,
    'elapsed_ms': elapsed.inMilliseconds,
    if (lastErrorType != null) 'last_error_type': lastErrorType,
    if (lastOsErrorCode != null) 'last_os_error_code': lastOsErrorCode,
  };
}

class _WindowsProxyPortProbeResult {
  const _WindowsProxyPortProbeResult({
    required this.available,
    this.errorType,
    this.osErrorCode,
  });

  final bool available;
  final String? errorType;
  final int? osErrorCode;
}

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
    this.probeTimeout = const Duration(milliseconds: 350),
    this.retryInterval = const Duration(milliseconds: 200),
    this.verificationDelay = const Duration(milliseconds: 300),
  }) : _inspector = inspector,
       _stopper = stopper,
       _portProbe = portProbe ?? _probeLoopbackPort;

  final WindowsProxyInspector _inspector;
  final WindowsProxyStopper _stopper;
  final WindowsProxyPortProbe _portProbe;
  final Duration readyTimeout;
  final Duration probeTimeout;
  final Duration retryInterval;
  final Duration verificationDelay;

  Future<ProxyOperationResult?> verifyAfterApply(
    int port, {
    bool Function()? isCancelled,
  }) async {
    if (isCancelled?.call() == true) return null;
    await Future<void>.delayed(verificationDelay);
    if (isCancelled?.call() == true) return null;
    final result = await _inspector(port);
    return isCancelled?.call() == true ? null : result;
  }

  Future<bool> waitUntilReady(int port, {bool Function()? isCancelled}) async {
    return (await waitUntilReadyDetailed(port, isCancelled: isCancelled)).ready;
  }

  Future<WindowsProxyReadinessResult> waitUntilReadyDetailed(
    int port, {
    bool Function()? isCancelled,
  }) async {
    final watch = Stopwatch()..start();
    var attempts = 0;
    String? lastErrorType;
    int? lastOsErrorCode;

    WindowsProxyReadinessResult finish(WindowsProxyReadinessStatus status) {
      watch.stop();
      return WindowsProxyReadinessResult(
        status: status,
        port: port,
        attempts: attempts,
        elapsed: watch.elapsed,
        lastErrorType: lastErrorType,
        lastOsErrorCode: lastOsErrorCode,
      );
    }

    while (true) {
      if (isCancelled?.call() == true) {
        return finish(WindowsProxyReadinessStatus.cancelled);
      }
      if (port < 1 || port > 65535) {
        return finish(WindowsProxyReadinessStatus.invalidPort);
      }
      final remaining = readyTimeout - watch.elapsed;
      if (remaining <= Duration.zero) {
        return finish(WindowsProxyReadinessStatus.timedOut);
      }
      attempts++;
      final result = await _probePort(
        port,
        timeout: remaining < probeTimeout ? remaining : probeTimeout,
      );
      if (!result.available) {
        lastErrorType = result.errorType;
        lastOsErrorCode = result.osErrorCode;
      }
      if (isCancelled?.call() == true) {
        return finish(WindowsProxyReadinessStatus.cancelled);
      }
      if (watch.elapsed >= readyTimeout) {
        return finish(WindowsProxyReadinessStatus.timedOut);
      }
      if (result.available) {
        return finish(WindowsProxyReadinessStatus.ready);
      }
      final retryBudget = readyTimeout - watch.elapsed;
      await Future<void>.delayed(
        retryInterval < retryBudget ? retryInterval : retryBudget,
      );
    }
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
    final portResult = await _probePort(port, timeout: probeTimeout);
    if (isCancelled?.call() == true) {
      return WindowsProxyRepairResult(
        status: WindowsProxyRepairStatus.cancelled,
        inspection: inspection,
      );
    }
    if (portResult.available) {
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

  Future<_WindowsProxyPortProbeResult> _probePort(
    int port, {
    required Duration timeout,
  }) async {
    try {
      final available = await _portProbe(port).timeout(timeout);
      return _WindowsProxyPortProbeResult(
        available: available,
        errorType: available ? null : 'unavailable',
      );
    } on SocketException catch (error) {
      return _WindowsProxyPortProbeResult(
        available: false,
        errorType: 'socket_exception',
        osErrorCode: error.osError?.errorCode,
      );
    } on TimeoutException {
      return const _WindowsProxyPortProbeResult(
        available: false,
        errorType: 'timeout',
      );
    } catch (_) {
      return const _WindowsProxyPortProbeResult(
        available: false,
        errorType: 'probe_error',
      );
    }
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
    } finally {
      socket?.destroy();
    }
  }
}

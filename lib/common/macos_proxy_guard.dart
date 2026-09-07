import 'dart:async';
import 'dart:io';

import 'package:proxy/proxy.dart';

typedef MacOSProxyInspector =
    Future<ProxyOperationResult> Function(int expectedPort);
typedef MacOSProxyStarter =
    Future<ProxyOperationResult> Function(int port, List<String> bypassDomains);
typedef MacOSProxyStopper =
    Future<ProxyOperationResult> Function(int expectedPort);
typedef MacOSProxyPortProbe = Future<bool> Function(int port);

enum MacOSProxyReadinessStatus { ready, timedOut, cancelled, invalidPort }

class MacOSProxyReadinessResult {
  const MacOSProxyReadinessResult({
    required this.status,
    required this.port,
    required this.attempts,
    required this.elapsed,
    this.lastErrorType,
    this.lastOsErrorCode,
  });

  final MacOSProxyReadinessStatus status;
  final int port;
  final int attempts;
  final Duration elapsed;
  final String? lastErrorType;
  final int? lastOsErrorCode;

  bool get ready => status == MacOSProxyReadinessStatus.ready;

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

class _MacOSProxyPortProbeResult {
  const _MacOSProxyPortProbeResult({
    required this.available,
    this.errorType,
    this.osErrorCode,
  });

  final bool available;
  final String? errorType;
  final int? osErrorCode;
}

enum MacOSProxyRepairStatus {
  cancelled,
  notOwned,
  active,
  cleaned,
  cleanupFailed,
}

class MacOSProxyRepairResult {
  const MacOSProxyRepairResult({
    required this.status,
    required this.inspection,
    this.cleanup,
  });

  final MacOSProxyRepairStatus status;
  final ProxyOperationResult inspection;
  final ProxyOperationResult? cleanup;
}

class MacOSProxyReconcileResult {
  const MacOSProxyReconcileResult({
    required this.inspection,
    this.repair,
    this.readiness,
  });

  final ProxyOperationResult inspection;
  final ProxyOperationResult? repair;
  final MacOSProxyReadinessResult? readiness;

  bool get repaired => repair?.success == true;
}

class MacOSProxyGuard {
  MacOSProxyGuard({
    required MacOSProxyInspector inspector,
    required MacOSProxyStarter starter,
    required MacOSProxyStopper stopper,
    MacOSProxyPortProbe? portProbe,
    this.readyTimeout = const Duration(seconds: 5),
    this.probeTimeout = const Duration(milliseconds: 350),
    this.retryInterval = const Duration(milliseconds: 200),
    this.verificationDelay = const Duration(milliseconds: 300),
  }) : _inspector = inspector,
       _starter = starter,
       _stopper = stopper,
       _portProbe = portProbe ?? _probeLoopbackPort;

  final MacOSProxyInspector _inspector;
  final MacOSProxyStarter _starter;
  final MacOSProxyStopper _stopper;
  final MacOSProxyPortProbe _portProbe;
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

  Future<MacOSProxyReadinessResult> waitUntilReadyDetailed(
    int port, {
    bool Function()? isCancelled,
  }) async {
    final watch = Stopwatch()..start();
    var attempts = 0;
    String? lastErrorType;
    int? lastOsErrorCode;

    MacOSProxyReadinessResult finish(MacOSProxyReadinessStatus status) {
      watch.stop();
      return MacOSProxyReadinessResult(
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
        return finish(MacOSProxyReadinessStatus.cancelled);
      }
      if (port < 1 || port > 65535) {
        return finish(MacOSProxyReadinessStatus.invalidPort);
      }
      final remaining = readyTimeout - watch.elapsed;
      if (remaining <= Duration.zero) {
        return finish(MacOSProxyReadinessStatus.timedOut);
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
        return finish(MacOSProxyReadinessStatus.cancelled);
      }
      if (watch.elapsed >= readyTimeout) {
        return finish(MacOSProxyReadinessStatus.timedOut);
      }
      if (result.available) {
        return finish(MacOSProxyReadinessStatus.ready);
      }
      final retryBudget = readyTimeout - watch.elapsed;
      await Future<void>.delayed(
        retryInterval < retryBudget ? retryInterval : retryBudget,
      );
    }
  }

  Future<MacOSProxyReconcileResult?> reconcile(
    int port,
    List<String> bypassDomains, {
    bool Function()? isCancelled,
  }) async {
    if (isCancelled?.call() == true) return null;
    final inspection = await _inspector(port);
    if (isCancelled?.call() == true) return null;
    if (inspection.success) {
      return MacOSProxyReconcileResult(inspection: inspection);
    }
    final readiness = await waitUntilReadyDetailed(
      port,
      isCancelled: isCancelled,
    );
    if (!readiness.ready || isCancelled?.call() == true) {
      return MacOSProxyReconcileResult(
        inspection: inspection,
        readiness: readiness,
      );
    }
    final repair = await _starter(port, bypassDomains);
    if (isCancelled?.call() == true) return null;
    return MacOSProxyReconcileResult(
      inspection: inspection,
      repair: repair,
      readiness: readiness,
    );
  }

  Future<MacOSProxyRepairResult> repairStale(
    int port, {
    bool Function()? isCancelled,
  }) async {
    final inspection = await _inspector(port);
    if (isCancelled?.call() == true) {
      return MacOSProxyRepairResult(
        status: MacOSProxyRepairStatus.cancelled,
        inspection: inspection,
      );
    }
    if (inspection.enabled != true || inspection.server != '127.0.0.1:$port') {
      return MacOSProxyRepairResult(
        status: MacOSProxyRepairStatus.notOwned,
        inspection: inspection,
      );
    }
    final portResult = await _probePort(port, timeout: probeTimeout);
    if (isCancelled?.call() == true) {
      return MacOSProxyRepairResult(
        status: MacOSProxyRepairStatus.cancelled,
        inspection: inspection,
      );
    }
    if (portResult.available) {
      return MacOSProxyRepairResult(
        status: MacOSProxyRepairStatus.active,
        inspection: inspection,
      );
    }
    final cleanup = await _stopper(port);
    return MacOSProxyRepairResult(
      status: cleanup.success
          ? MacOSProxyRepairStatus.cleaned
          : MacOSProxyRepairStatus.cleanupFailed,
      inspection: inspection,
      cleanup: cleanup,
    );
  }

  Future<_MacOSProxyPortProbeResult> _probePort(
    int port, {
    required Duration timeout,
  }) async {
    try {
      final available = await _portProbe(port).timeout(timeout);
      return _MacOSProxyPortProbeResult(
        available: available,
        errorType: available ? null : 'unavailable',
      );
    } on SocketException catch (error) {
      return _MacOSProxyPortProbeResult(
        available: false,
        errorType: 'socket_exception',
        osErrorCode: error.osError?.errorCode,
      );
    } on TimeoutException {
      return const _MacOSProxyPortProbeResult(
        available: false,
        errorType: 'timeout',
      );
    } catch (_) {
      return const _MacOSProxyPortProbeResult(
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

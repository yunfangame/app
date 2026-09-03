import 'package:fl_clash/common/windows_proxy_guard.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:proxy/proxy.dart';

void main() {
  const owned = ProxyOperationResult(
    success: true,
    operation: 'inspect',
    stage: 'verified',
    enabled: true,
    server: '127.0.0.1:7890',
  );
  const foreign = ProxyOperationResult(
    success: false,
    operation: 'inspect',
    stage: 'readback_mismatch',
    enabled: true,
    server: '127.0.0.1:8080',
  );
  const cleaned = ProxyOperationResult(
    success: true,
    operation: 'stop',
    stage: 'verified',
    enabled: false,
  );

  test('waits until the local mixed port is listening', () async {
    var probes = 0;
    final guard = WindowsProxyGuard(
      inspector: (_) async => owned,
      stopper: (_) async => cleaned,
      portProbe: (_) async => ++probes >= 3,
      readyTimeout: const Duration(seconds: 1),
      retryInterval: Duration.zero,
    );

    expect(await guard.waitUntilReady(7890), isTrue);
    expect(probes, 3);
  });

  test('stops waiting when a newer request cancels startup', () async {
    var cancelled = false;
    final guard = WindowsProxyGuard(
      inspector: (_) async => owned,
      stopper: (_) async => cleaned,
      portProbe: (_) async {
        cancelled = true;
        return false;
      },
      readyTimeout: const Duration(seconds: 1),
      retryInterval: Duration.zero,
    );

    expect(
      await guard.waitUntilReady(7890, isCancelled: () => cancelled),
      isFalse,
    );
  });

  test('preserves a system proxy that is not owned by this port', () async {
    var stopCalls = 0;
    final guard = WindowsProxyGuard(
      inspector: (_) async => foreign,
      stopper: (_) async {
        stopCalls++;
        return cleaned;
      },
      portProbe: (_) async => false,
    );

    final result = await guard.repairStale(7890);

    expect(result.status, WindowsProxyRepairStatus.notOwned);
    expect(stopCalls, 0);
  });

  test('preserves an owned proxy while its port is listening', () async {
    var stopCalls = 0;
    final guard = WindowsProxyGuard(
      inspector: (_) async => owned,
      stopper: (_) async {
        stopCalls++;
        return cleaned;
      },
      portProbe: (_) async => true,
    );

    final result = await guard.repairStale(7890);

    expect(result.status, WindowsProxyRepairStatus.active);
    expect(stopCalls, 0);
  });

  test('clears an owned proxy whose port is no longer listening', () async {
    var stoppedPort = 0;
    final guard = WindowsProxyGuard(
      inspector: (_) async => owned,
      stopper: (port) async {
        stoppedPort = port;
        return cleaned;
      },
      portProbe: (_) async => false,
    );

    final result = await guard.repairStale(7890);

    expect(result.status, WindowsProxyRepairStatus.cleaned);
    expect(stoppedPort, 7890);
    expect(result.cleanup?.success, isTrue);
  });
}

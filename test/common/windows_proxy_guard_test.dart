import 'dart:async';
import 'dart:io';

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
  const changed = ProxyOperationResult(
    success: false,
    operation: 'inspect',
    stage: 'readback_mismatch',
    enabled: false,
  );
  const repaired = ProxyOperationResult(
    success: true,
    operation: 'start',
    stage: 'verified',
    enabled: true,
    server: '127.0.0.1:7890',
  );

  test('does not rewrite an effective proxy during reconciliation', () async {
    var starts = 0;
    final guard = WindowsProxyGuard(
      inspector: (_) async => owned,
      starter: (_, _) async {
        starts++;
        return repaired;
      },
      stopper: (_) async => cleaned,
      portProbe: (_) async => true,
    );

    final result = await guard.reconcile(7890, const ['localhost']);

    expect(result?.inspection.success, isTrue);
    expect(result?.repair, isNull);
    expect(starts, 0);
  });

  test(
    'reapplies and verifies a changed proxy after network restore',
    () async {
      var starts = 0;
      var inspections = 0;
      final guard = WindowsProxyGuard(
        inspector: (_) async => ++inspections == 1 ? changed : owned,
        starter: (port, bypassDomains) async {
          starts++;
          expect(port, 7890);
          expect(bypassDomains, ['localhost']);
          return repaired;
        },
        stopper: (_) async => cleaned,
        portProbe: (_) async => true,
        verificationDelay: Duration.zero,
      );

      final result = await guard.reconcile(7890, const ['localhost']);

      expect(result?.repaired, isTrue);
      expect(result?.readiness?.ready, isTrue);
      expect(result?.verification?.success, isTrue);
      expect(starts, 1);
      expect(inspections, 2);
    },
  );

  test('does not rewrite when the local listener is unavailable', () async {
    var starts = 0;
    final guard = WindowsProxyGuard(
      inspector: (_) async => changed,
      starter: (_, _) async {
        starts++;
        return repaired;
      },
      stopper: (_) async => cleaned,
      portProbe: (_) async => false,
      readyTimeout: Duration.zero,
    );

    final result = await guard.reconcile(7890, const []);

    expect(result?.readiness?.status, WindowsProxyReadinessStatus.timedOut);
    expect(result?.repair, isNull);
    expect(starts, 0);
  });

  test('failed readback is not reported as a successful repair', () async {
    final guard = WindowsProxyGuard(
      inspector: (_) async => changed,
      starter: (_, _) async => repaired,
      stopper: (_) async => cleaned,
      portProbe: (_) async => true,
      verificationDelay: Duration.zero,
    );

    final result = await guard.reconcile(7890, const []);

    expect(result?.repair?.success, isTrue);
    expect(result?.verification?.success, isFalse);
    expect(result?.repaired, isFalse);
  });

  test('delayed verification reports changed proxy without writing', () async {
    final guard = WindowsProxyGuard(
      inspector: (_) async => foreign,
      stopper: (_) async => throw StateError('must not write'),
      verificationDelay: Duration.zero,
    );
    final result = await guard.verifyAfterApply(7890);
    expect(result?.success, isFalse);
    expect(result?.server, '127.0.0.1:8080');
  });

  test('cancelled delayed verification does not inspect', () async {
    final guard = WindowsProxyGuard(
      inspector: (_) async => throw StateError('must not inspect'),
      stopper: (_) async => cleaned,
      verificationDelay: Duration.zero,
    );
    expect(await guard.verifyAfterApply(7890, isCancelled: () => true), isNull);
  });

  test('discards verification superseded while reading', () async {
    var cancelled = false;
    final guard = WindowsProxyGuard(
      inspector: (_) async {
        cancelled = true;
        return owned;
      },
      stopper: (_) async => cleaned,
      verificationDelay: Duration.zero,
    );
    expect(
      await guard.verifyAfterApply(7890, isCancelled: () => cancelled),
      isNull,
    );
  });

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

  test('detailed readiness records attempts and loopback endpoint', () async {
    var probes = 0;
    final guard = WindowsProxyGuard(
      inspector: (_) async => owned,
      stopper: (_) async => cleaned,
      portProbe: (_) async => ++probes >= 3,
      retryInterval: Duration.zero,
    );

    final result = await guard.waitUntilReadyDetailed(7890);

    expect(result.status, WindowsProxyReadinessStatus.ready);
    expect(result.ready, isTrue);
    expect(result.attempts, 3);
    expect(result.elapsed, greaterThanOrEqualTo(Duration.zero));
    expect(result.toDiagnosticData(), containsPair('address', '127.0.0.1'));
    expect(result.toDiagnosticData(), containsPair('port', 7890));
    expect(result.toDiagnosticData(), containsPair('attempts', 3));
  });

  test('native loopback probe reaches an available TCP listener', () async {
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final subscription = server.listen((socket) => socket.destroy());
    final guard = WindowsProxyGuard(
      inspector: (_) async => owned,
      stopper: (_) async => cleaned,
    );

    try {
      final result = await guard.waitUntilReadyDetailed(server.port);

      expect(result.status, WindowsProxyReadinessStatus.ready);
      expect(result.attempts, 1);
      expect(result.lastErrorType, isNull);
      expect(result.lastOsErrorCode, isNull);
    } finally {
      await subscription.cancel();
      await server.close();
    }
  });

  test('preserves numeric refusal error without exception contents', () async {
    final guard = WindowsProxyGuard(
      inspector: (_) async => owned,
      stopper: (_) async => cleaned,
      portProbe: (_) async => throw const SocketException(
        'private-account@example.com',
        osError: OSError('private exception text', 10061),
      ),
      readyTimeout: const Duration(milliseconds: 20),
      retryInterval: const Duration(seconds: 1),
    );

    final result = await guard.waitUntilReadyDetailed(7890);

    expect(result.status, WindowsProxyReadinessStatus.timedOut);
    expect(result.attempts, 1);
    expect(result.lastErrorType, 'socket_exception');
    expect(result.lastOsErrorCode, 10061);
    expect(
      result.toDiagnosticData(),
      containsPair('last_os_error_code', 10061),
    );
    expect(result.toDiagnosticData().toString(), isNot(contains('private')));
  });

  test('slow startup succeeds within the total readiness budget', () async {
    var probes = 0;
    final guard = WindowsProxyGuard(
      inspector: (_) async => owned,
      stopper: (_) async => cleaned,
      portProbe: (_) async {
        await Future<void>.delayed(const Duration(milliseconds: 10));
        return ++probes >= 3;
      },
      readyTimeout: const Duration(seconds: 1),
      retryInterval: const Duration(milliseconds: 1),
    );

    final result = await guard.waitUntilReadyDetailed(7890);

    expect(result.status, WindowsProxyReadinessStatus.ready);
    expect(result.attempts, 3);
  });

  test('a hanging probe cannot exceed the total readiness budget', () async {
    final neverCompletes = Completer<bool>();
    final guard = WindowsProxyGuard(
      inspector: (_) async => owned,
      stopper: (_) async => cleaned,
      portProbe: (_) => neverCompletes.future,
      readyTimeout: const Duration(milliseconds: 20),
      probeTimeout: const Duration(seconds: 1),
      retryInterval: const Duration(seconds: 1),
    );

    final result = await guard
        .waitUntilReadyDetailed(7890)
        .timeout(const Duration(seconds: 1));

    expect(result.status, WindowsProxyReadinessStatus.timedOut);
    expect(result.attempts, 1);
    expect(result.lastErrorType, 'timeout');
    expect(result.lastOsErrorCode, isNull);
  });

  test('a per-attempt timeout still permits later startup success', () async {
    var probes = 0;
    final neverCompletes = Completer<bool>();
    final guard = WindowsProxyGuard(
      inspector: (_) async => owned,
      stopper: (_) async => cleaned,
      portProbe: (_) {
        probes++;
        return probes == 1 ? neverCompletes.future : Future.value(true);
      },
      readyTimeout: const Duration(seconds: 1),
      probeTimeout: const Duration(milliseconds: 10),
      retryInterval: Duration.zero,
    );

    final result = await guard.waitUntilReadyDetailed(7890);

    expect(result.status, WindowsProxyReadinessStatus.ready);
    expect(result.attempts, 2);
    expect(result.lastErrorType, 'timeout');
  });

  test('invalid and expired requests never initiate a port probe', () async {
    final guard = WindowsProxyGuard(
      inspector: (_) async => owned,
      stopper: (_) async => cleaned,
      portProbe: (_) async => throw StateError('must not probe'),
      readyTimeout: Duration.zero,
    );

    final invalid = await guard.waitUntilReadyDetailed(65536);
    final expired = await guard.waitUntilReadyDetailed(7890);

    expect(invalid.status, WindowsProxyReadinessStatus.invalidPort);
    expect(invalid.attempts, 0);
    expect(expired.status, WindowsProxyReadinessStatus.timedOut);
    expect(expired.attempts, 0);
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

  test('already cancelled readiness does not initiate a probe', () async {
    final guard = WindowsProxyGuard(
      inspector: (_) async => owned,
      stopper: (_) async => cleaned,
      portProbe: (_) async => throw StateError('must not probe'),
    );

    final result = await guard.waitUntilReadyDetailed(
      7890,
      isCancelled: () => true,
    );

    expect(result.status, WindowsProxyReadinessStatus.cancelled);
    expect(result.attempts, 0);
  });

  test('discards successful probe superseded while connecting', () async {
    var cancelled = false;
    final probe = Completer<bool>();
    final started = Completer<void>();
    final guard = WindowsProxyGuard(
      inspector: (_) async => owned,
      stopper: (_) async => cleaned,
      portProbe: (_) {
        started.complete();
        return probe.future;
      },
    );

    final pending = guard.waitUntilReadyDetailed(
      7890,
      isCancelled: () => cancelled,
    );
    await started.future;
    cancelled = true;
    probe.complete(true);
    final result = await pending;

    expect(result.status, WindowsProxyReadinessStatus.cancelled);
    expect(result.ready, isFalse);
    expect(result.attempts, 1);
  });

  test('cancellation during retry prevents another probe', () async {
    var cancelled = false;
    var probes = 0;
    final guard = WindowsProxyGuard(
      inspector: (_) async => owned,
      stopper: (_) async => cleaned,
      portProbe: (_) async {
        probes++;
        Timer.run(() => cancelled = true);
        return false;
      },
      retryInterval: const Duration(milliseconds: 10),
    );

    final result = await guard.waitUntilReadyDetailed(
      7890,
      isCancelled: () => cancelled,
    );

    expect(result.status, WindowsProxyReadinessStatus.cancelled);
    expect(probes, 1);
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

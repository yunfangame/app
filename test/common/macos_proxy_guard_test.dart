import 'dart:async';

import 'package:fl_clash/common/macos_proxy_guard.dart';
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
  const stopped = ProxyOperationResult(
    success: true,
    operation: 'stop',
    stage: 'verified',
    enabled: false,
  );

  for (final inspection in <String, ProxyOperationResult>{
    'external enabled endpoint': const ProxyOperationResult(
      success: false,
      operation: 'inspect',
      stage: 'readback_mismatch',
      enabled: true,
      server: '127.0.0.1:17890',
    ),
    'unknown enabled endpoint': const ProxyOperationResult(
      success: false,
      operation: 'inspect',
      stage: 'readback_mismatch',
      enabled: true,
    ),
    'unknown enable state': const ProxyOperationResult(
      success: false,
      operation: 'inspect',
      stage: 'readback_mismatch',
    ),
    'failed read with default disabled field': const ProxyOperationResult(
      success: false,
      operation: 'inspect',
      stage: 'readback',
      enabled: false,
      errorCode: 5,
    ),
  }.entries) {
    test('guard preserves ${inspection.key}', () async {
      final guard = MacOSProxyGuard(
        inspector: (_) async => inspection.value,
        starter: (_, _) async => throw StateError('must not rewrite'),
        stopper: (_) async => throw StateError('must not stop'),
        portProbe: (_) async => throw StateError('must not probe'),
      );
      final result = await guard.reconcile(7890, const ['localhost']);
      expect(result?.inspection, same(inspection.value));
      expect(result?.repair, isNull);
      expect(result?.readiness, isNull);
    });
  }

  for (final entry in {
    'skipped_active_listener': MacOSProxyRepairStatus.active,
    'skipped_foreign_or_restored': MacOSProxyRepairStatus.notOwned,
    'already_restored': MacOSProxyRepairStatus.notOwned,
  }.entries) {
    test('native stale repair respects ${entry.key}', () async {
      final guard = MacOSProxyGuard(
        inspector: (_) async => owned,
        starter: (_, _) async => throw StateError('must not start'),
        stopper: (_) async => ProxyOperationResult(
          success: true,
          operation: 'stop',
          stage: entry.key,
          writeSkipped: true,
        ),
        portProbe: (_) async => false,
      );
      final result = await guard.repairStale(7890);
      expect(result.status, entry.value);
    });
  }

  test('does not rewrite an effective proxy', () async {
    var starts = 0;
    final guard = MacOSProxyGuard(
      inspector: (_) async => owned,
      starter: (_, _) async {
        starts++;
        return repaired;
      },
      stopper: (_) async => stopped,
      portProbe: (_) async => true,
    );

    final result = await guard.reconcile(7890, const ['localhost']);

    expect(result?.inspection.success, isTrue);
    expect(result?.repair, isNull);
    expect(starts, 0);
  });

  test('reapplies a changed proxy after checking the local listener', () async {
    var starts = 0;
    final guard = MacOSProxyGuard(
      inspector: (_) async => changed,
      starter: (port, bypassDomains) async {
        starts++;
        expect(port, 7890);
        expect(bypassDomains, ['localhost']);
        return repaired;
      },
      stopper: (_) async => stopped,
      portProbe: (_) async => true,
      retryInterval: Duration.zero,
    );

    final result = await guard.reconcile(7890, const ['localhost']);

    expect(result?.repaired, isTrue);
    expect(result?.readiness?.ready, isTrue);
    expect(starts, 1);
  });

  test('does not write when the local listener is unavailable', () async {
    var starts = 0;
    final guard = MacOSProxyGuard(
      inspector: (_) async => changed,
      starter: (_, _) async {
        starts++;
        return repaired;
      },
      stopper: (_) async => stopped,
      portProbe: (_) async => false,
      readyTimeout: Duration.zero,
    );

    final result = await guard.reconcile(7890, const []);

    expect(result?.readiness?.status, MacOSProxyReadinessStatus.timedOut);
    expect(result?.repair, isNull);
    expect(starts, 0);
  });

  test('cancellation after inspection prevents a repair', () async {
    var cancelled = false;
    var starts = 0;
    final guard = MacOSProxyGuard(
      inspector: (_) async {
        cancelled = true;
        return changed;
      },
      starter: (_, _) async {
        starts++;
        return repaired;
      },
      stopper: (_) async => stopped,
      portProbe: (_) async => true,
    );

    final result = await guard.reconcile(
      7890,
      const [],
      isCancelled: () => cancelled,
    );

    expect(result, isNull);
    expect(starts, 0);
  });

  test('cleans an owned stale proxy when its listener is gone', () async {
    var stops = 0;
    final guard = MacOSProxyGuard(
      inspector: (_) async => owned,
      starter: (_, _) async => repaired,
      stopper: (port) async {
        stops++;
        expect(port, 7890);
        return stopped;
      },
      portProbe: (_) async => false,
    );

    final result = await guard.repairStale(7890);

    expect(result.status, MacOSProxyRepairStatus.cleaned);
    expect(stops, 1);
  });

  test('a hanging readiness probe respects the total timeout', () async {
    final neverCompletes = Completer<bool>();
    final guard = MacOSProxyGuard(
      inspector: (_) async => changed,
      starter: (_, _) async => repaired,
      stopper: (_) async => stopped,
      portProbe: (_) => neverCompletes.future,
      readyTimeout: const Duration(milliseconds: 20),
      probeTimeout: const Duration(seconds: 1),
      retryInterval: Duration.zero,
    );

    final result = await guard
        .waitUntilReadyDetailed(7890)
        .timeout(const Duration(seconds: 1));

    expect(result.status, MacOSProxyReadinessStatus.timedOut);
    expect(result.lastErrorType, 'timeout');
  });
}

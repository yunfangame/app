import 'dart:async';

import 'package:fl_clash/common/application_bootstrap.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'post-authentication work does not block and reports failures',
    () async {
      final pending = Completer<void>();
      var started = false;
      Object? reportedError;

      runPostAuthenticationTask(
        task: () async {
          started = true;
          await pending.future;
          throw StateError('profile_sync_failed');
        },
        onError: (error, _) => reportedError = error,
      );

      expect(started, isTrue);
      expect(reportedError, isNull);
      pending.complete();
      await Future<void>.delayed(Duration.zero);
      expect(reportedError, isA<StateError>());
    },
  );

  testWidgets('authentication timeout invalidates its late result', (
    tester,
  ) async {
    final controller = AuthenticationBootstrapController();
    var timeoutRevision = 0;
    final revision = controller.begin(
      timeout: const Duration(seconds: 1),
      onTimeout: (value) {
        timeoutRevision = value;
        controller.complete(value);
      },
    );

    expect(controller.isCurrent(revision), isTrue);
    await tester.pump(const Duration(seconds: 1));

    expect(timeoutRevision, revision);
    expect(controller.isCurrent(revision), isFalse);
    expect(controller.complete(revision), isFalse);
    controller.dispose();
  });

  testWidgets('completed authentication cancels its timeout', (tester) async {
    final controller = AuthenticationBootstrapController();
    var timedOut = false;
    final revision = controller.begin(
      timeout: const Duration(seconds: 1),
      onTimeout: (_) => timedOut = true,
    );

    expect(controller.complete(revision), isTrue);
    await tester.pump(const Duration(seconds: 2));

    expect(timedOut, isFalse);
    controller.dispose();
  });

  testWidgets('readiness timeout releases waiters and accepts late readiness', (
    tester,
  ) async {
    final gate = ApplicationReadinessGate();
    var timedOut = false;
    gate.startTimeout(
      timeout: const Duration(seconds: 1),
      onTimeout: () => timedOut = true,
    );
    final initialWait = gate.wait();

    await tester.pump(const Duration(seconds: 1));

    expect(timedOut, isTrue);
    expect(await initialWait, ApplicationReadiness.timedOut);
    expect(gate.ready(), isTrue);
    expect(gate.status, ApplicationReadiness.ready);
    expect(await gate.wait(), ApplicationReadiness.ready);
    gate.dispose();
  });

  test('readiness failure and disposal settle pending waiters', () async {
    final failedGate = ApplicationReadinessGate();
    final failedWait = failedGate.wait();
    expect(failedGate.fail(), isTrue);
    expect(await failedWait, ApplicationReadiness.failed);

    final disposedGate = ApplicationReadinessGate();
    final disposedWait = disposedGate.wait();
    disposedGate.dispose();
    expect(await disposedWait, ApplicationReadiness.disposed);
    failedGate.dispose();
  });
}

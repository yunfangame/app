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

  testWidgets(
    'credential completion preserves the original authentication budget',
    (tester) async {
      final controller = AuthenticationBootstrapController();
      addTearDown(controller.dispose);
      final timeouts = <int>[];
      var credentialsDeferred = false;
      void onTimeout(int revision) {
        timeouts.add(revision);
        credentialsDeferred = controller.deferForCredentials(revision);
        controller.complete(revision);
      }

      final revision = controller.begin(
        timeout: const Duration(seconds: 60),
        onTimeout: onTimeout,
      );
      await tester.pump(const Duration(seconds: 45));
      var loads = 0;
      final result = await controller.loadCredentials(
        revision,
        load: () async {
          loads++;
          return 'stored-session';
        },
        timeout: const Duration(seconds: 60),
        onTimeout: onTimeout,
      );

      expect(result?.value, 'stored-session');
      expect(result?.revision, revision);
      expect(result?.resumed, isFalse);
      expect(loads, 1);
      await tester.pump(const Duration(seconds: 14));
      expect(controller.isCurrent(revision), isTrue);
      await tester.pump(const Duration(seconds: 1));
      expect(timeouts, [revision]);
      expect(credentialsDeferred, isFalse);
      expect(controller.hasPendingWork, isFalse);
    },
  );

  testWidgets(
    'a 120 second keyring wait resumes once with a bounded network budget',
    (tester) async {
      final controller = AuthenticationBootstrapController();
      addTearDown(controller.dispose);
      final pending = Completer<String>();
      final deferred = <int>[];
      final networkTimeouts = <int>[];
      var loads = 0;
      void onTimeout(int revision) {
        if (controller.deferForCredentials(revision)) {
          deferred.add(revision);
        } else {
          networkTimeouts.add(revision);
          controller.complete(revision);
        }
      }

      final revision = controller.begin(
        timeout: const Duration(seconds: 60),
        onTimeout: onTimeout,
      );
      final loading = controller.loadCredentials(
        revision,
        load: () {
          loads++;
          return pending.future;
        },
        timeout: const Duration(seconds: 60),
        onTimeout: onTimeout,
      );
      var returned = false;
      unawaited(loading.then((_) => returned = true));
      await tester.pump(const Duration(seconds: 60));
      expect(deferred, [revision]);
      expect(controller.isCurrent(revision), isFalse);
      expect(controller.hasPendingWork, isTrue);
      expect(returned, isFalse);
      await tester.pump(const Duration(seconds: 60));
      expect(deferred, [revision]);
      expect(networkTimeouts, isEmpty);
      expect(loads, 1);

      pending.complete('unlocked-session');
      await tester.pump();
      final result = await loading;
      expect(result, isNotNull);
      expect(result!.value, 'unlocked-session');
      expect(result.resumed, isTrue);
      expect(result.revision, greaterThan(revision));
      expect(controller.isCurrent(result.revision), isTrue);
      expect(controller.isCurrent(revision), isFalse);
      expect(controller.deferForCredentials(result.revision), isFalse);
      await tester.pump(const Duration(seconds: 59));
      expect(controller.isCurrent(result.revision), isTrue);
      await tester.pump(const Duration(seconds: 1));
      expect(networkTimeouts, [result.revision]);
      expect(controller.hasPendingWork, isFalse);
      expect(loads, 1);
      await tester.pump(const Duration(minutes: 2));
      expect(deferred, [revision]);
      expect(networkTimeouts, [result.revision]);
    },
  );

  testWidgets('reentrant keyring reads do not create another load', (
    tester,
  ) async {
    final controller = AuthenticationBootstrapController();
    addTearDown(controller.dispose);
    final pending = Completer<String>();
    var loads = 0;
    var credentialsDeferred = false;
    void onTimeout(int revision) {
      credentialsDeferred = controller.deferForCredentials(revision);
    }

    final revision = controller.begin(
      timeout: const Duration(seconds: 60),
      onTimeout: onTimeout,
    );
    Future<AuthenticationBootstrapCredentials<String>?> load() {
      return controller.loadCredentials(
        revision,
        load: () {
          loads++;
          return pending.future;
        },
        timeout: const Duration(seconds: 60),
        onTimeout: onTimeout,
      );
    }

    final first = load();
    expect(await load(), isNull);
    await tester.pump(const Duration(seconds: 60));
    expect(credentialsDeferred, isTrue);
    expect(await load(), isNull);
    expect(loads, 1);
    pending.complete('stored-session');
    await tester.pump();
    final result = await first;
    expect(result?.value, 'stored-session');
    expect(result?.resumed, isTrue);
    expect(controller.complete(result!.revision), isTrue);
    expect(controller.hasPendingWork, isFalse);
  });

  for (final deferred in [false, true]) {
    for (final operation in ['cancel', 'complete', 'begin', 'dispose']) {
      if (deferred && operation == 'complete') continue;
      testWidgets(
        '$operation discards a late credential result when deferred=$deferred',
        (tester) async {
          final controller = AuthenticationBootstrapController();
          addTearDown(controller.dispose);
          final pending = Completer<String>();
          var timeouts = 0;
          void onTimeout(int revision) {
            timeouts++;
            if (!controller.deferForCredentials(revision)) {
              controller.complete(revision);
            }
          }

          final revision = controller.begin(
            timeout: const Duration(seconds: 60),
            onTimeout: onTimeout,
          );
          final loading = controller.loadCredentials(
            revision,
            load: () => pending.future,
            timeout: const Duration(seconds: 60),
            onTimeout: onTimeout,
          );
          if (deferred) {
            await tester.pump(const Duration(seconds: 60));
            expect(controller.hasPendingWork, isTrue);
          }
          int? replacementRevision;
          switch (operation) {
            case 'cancel':
              controller.cancel();
            case 'complete':
              expect(controller.complete(revision), isTrue);
            case 'begin':
              replacementRevision = controller.begin(
                timeout: const Duration(seconds: 60),
                onTimeout: onTimeout,
              );
            case 'dispose':
              controller.dispose();
          }
          expect(controller.isCurrent(revision), isFalse);
          pending.complete('stale-session');
          await tester.pump();
          expect(await loading, isNull);
          if (replacementRevision != null) {
            expect(controller.isCurrent(replacementRevision), isTrue);
            expect(controller.complete(replacementRevision), isTrue);
          }
          expect(controller.hasPendingWork, isFalse);
          await tester.pump(const Duration(minutes: 2));
          expect(timeouts, deferred ? 1 : 0);
        },
      );
    }
  }

  testWidgets(
    'completion cannot authorize a deferred authentication revision',
    (tester) async {
      final controller = AuthenticationBootstrapController();
      addTearDown(controller.dispose);
      final pending = Completer<String>();
      var credentialsDeferred = false;
      void onTimeout(int revision) {
        credentialsDeferred = controller.deferForCredentials(revision);
      }

      final revision = controller.begin(
        timeout: const Duration(seconds: 60),
        onTimeout: onTimeout,
      );
      final loading = controller.loadCredentials(
        revision,
        load: () => pending.future,
        timeout: const Duration(seconds: 60),
        onTimeout: onTimeout,
      );
      await tester.pump(const Duration(seconds: 60));
      expect(credentialsDeferred, isTrue);
      expect(controller.complete(revision), isFalse);
      expect(controller.isCurrent(revision), isFalse);
      expect(controller.hasPendingWork, isTrue);
      controller.cancel();
      pending.complete('stale-session');
      await tester.pump();
      expect(await loading, isNull);
      expect(controller.hasPendingWork, isFalse);
    },
  );

  for (final deferred in [false, true]) {
    testWidgets(
      'credential read failures clear pending work when deferred=$deferred',
      (tester) async {
        final controller = AuthenticationBootstrapController();
        addTearDown(controller.dispose);
        final pending = Completer<String>();
        var timeouts = 0;
        var credentialsDeferred = false;
        var completed = false;
        void onTimeout(int revision) {
          timeouts++;
          credentialsDeferred = controller.deferForCredentials(revision);
        }

        final revision = controller.begin(
          timeout: const Duration(seconds: 60),
          onTimeout: onTimeout,
        );
        final loading = controller.loadCredentials(
          revision,
          load: () => pending.future,
          timeout: const Duration(seconds: 60),
          onTimeout: onTimeout,
        );
        final failure = StateError('keyring_read_failed');
        final handled = loading.catchError((Object error) {
          if (!deferred) completed = controller.complete(revision);
          throw error;
        });
        final failed = expectLater(handled, throwsA(same(failure)));
        if (deferred) await tester.pump(const Duration(seconds: 60));
        pending.completeError(failure);
        await tester.pump();
        await failed;
        expect(completed, !deferred);
        expect(credentialsDeferred, deferred);
        expect(controller.isCurrent(revision), isFalse);
        expect(controller.hasPendingWork, isFalse);
        await tester.pump(const Duration(minutes: 2));
        expect(timeouts, deferred ? 1 : 0);
      },
    );
  }

  testWidgets('a synchronous credential loader failure cancels its timer', (
    tester,
  ) async {
    final controller = AuthenticationBootstrapController();
    addTearDown(controller.dispose);
    var timedOut = false;
    var completed = false;
    void onTimeout(int _) => timedOut = true;
    final revision = controller.begin(
      timeout: const Duration(seconds: 60),
      onTimeout: onTimeout,
    );
    final failure = StateError('keyring_unavailable');
    await expectLater(
      controller
          .loadCredentials<String>(
            revision,
            load: () => throw failure,
            timeout: const Duration(seconds: 60),
            onTimeout: onTimeout,
          )
          .catchError((Object error) {
            completed = controller.complete(revision);
            throw error;
          }),
      throwsA(same(failure)),
    );
    expect(completed, isTrue);
    expect(controller.hasPendingWork, isFalse);
    await tester.pump(const Duration(minutes: 2));
    expect(timedOut, isFalse);
  });

  testWidgets(
    'a stale credential failure cannot cancel a replacement authentication',
    (tester) async {
      final controller = AuthenticationBootstrapController();
      addTearDown(controller.dispose);
      final pending = Completer<String>();
      void onTimeout(int revision) {
        if (!controller.deferForCredentials(revision)) {
          controller.complete(revision);
        }
      }

      final firstRevision = controller.begin(
        timeout: const Duration(seconds: 60),
        onTimeout: onTimeout,
      );
      final loading = controller.loadCredentials(
        firstRevision,
        load: () => pending.future,
        timeout: const Duration(seconds: 60),
        onTimeout: onTimeout,
      );
      final failure = StateError('stale_keyring_failure');
      final failed = expectLater(loading, throwsA(same(failure)));
      await tester.pump(const Duration(seconds: 60));
      final secondRevision = controller.begin(
        timeout: const Duration(seconds: 60),
        onTimeout: onTimeout,
      );
      pending.completeError(failure);
      await tester.pump();
      await failed;
      expect(controller.isCurrent(secondRevision), isTrue);
      expect(controller.complete(secondRevision), isTrue);
      expect(controller.hasPendingWork, isFalse);
    },
  );

  for (final readCompletesFirst in [false, true]) {
    testWidgets(
      'credential and timeout boundary is ordered when readCompletesFirst=$readCompletesFirst',
      (tester) async {
        final controller = AuthenticationBootstrapController();
        addTearDown(controller.dispose);
        final pending = Completer<String>();
        final deferrals = <int>[];
        void onTimeout(int revision) {
          if (controller.deferForCredentials(revision)) {
            deferrals.add(revision);
          } else {
            controller.complete(revision);
          }
        }

        if (readCompletesFirst) {
          Timer(const Duration(seconds: 60), () => pending.complete('session'));
        }
        final revision = controller.begin(
          timeout: const Duration(seconds: 60),
          onTimeout: onTimeout,
        );
        final loading = controller.loadCredentials(
          revision,
          load: () => pending.future,
          timeout: const Duration(seconds: 60),
          onTimeout: onTimeout,
        );
        if (!readCompletesFirst) {
          Timer(const Duration(seconds: 60), () => pending.complete('session'));
        }
        await tester.pump(const Duration(seconds: 60));
        final result = await loading;
        expect(result?.value, 'session');
        expect(result?.resumed, !readCompletesFirst);
        if (readCompletesFirst) {
          expect(result?.revision, revision);
          expect(deferrals, isEmpty);
          expect(controller.hasPendingWork, isFalse);
        } else {
          expect(result!.revision, greaterThan(revision));
          expect(deferrals, [revision]);
          expect(controller.complete(result.revision), isTrue);
        }
      },
    );
  }

  test('disposed authentication does not begin or load credentials', () async {
    final controller = AuthenticationBootstrapController();
    controller.dispose();
    var loaded = false;
    void onTimeout(int _) {}
    expect(
      () => controller.begin(
        timeout: const Duration(seconds: 60),
        onTimeout: onTimeout,
      ),
      throwsStateError,
    );
    expect(
      await controller.loadCredentials(
        0,
        load: () async {
          loaded = true;
          return 'session';
        },
        timeout: const Duration(seconds: 60),
        onTimeout: onTimeout,
      ),
      isNull,
    );
    expect(loaded, isFalse);
    expect(controller.hasPendingWork, isFalse);
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

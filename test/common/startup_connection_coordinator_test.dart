import 'dart:async';

import 'package:fl_clash/common/startup_connection_coordinator.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final authenticatedFirst in [true, false]) {
    test(
      'waits for ${authenticatedFirst ? 'routing after authentication' : 'authentication after routing'}',
      () async {
        final harness = _Harness();
        final attempt = harness.begin();
        await harness.run(attempt, authenticated: false, routingReady: false);
        await harness.run(
          attempt,
          authenticated: authenticatedFirst,
          routingReady: !authenticatedFirst,
        );
        expect(harness.events, isEmpty);

        await harness.run(attempt);

        expect(harness.events, ['probe', 'connect']);
        harness.coordinator.dispose();
      },
    );
  }

  test('disabled startup does not probe or connect', () async {
    final harness = _Harness();
    final attempt = harness.begin(enabled: false);

    await harness.run(attempt);
    await harness.run(attempt);

    expect(harness.events, isEmpty);
    harness.coordinator.dispose();
  });

  test(
    'concurrent and completed calls share one probe and connection',
    () async {
      final harness = _Harness();
      final latency = Completer<void>();
      final connection = Completer<void>();
      final attempt = harness.begin();
      final first = harness.run(
        attempt,
        latency: latency.future,
        connection: connection.future,
      );
      final second = harness.run(attempt);

      expect(identical(first, second), isTrue);
      expect(harness.events, ['probe']);
      expect(harness.probeIsCurrent!(), isTrue);
      latency.complete();
      await harness.connectionEntered.future;
      final third = harness.run(attempt);

      expect(identical(first, third), isTrue);
      expect(harness.probeIsCurrent!(), isFalse);
      expect(harness.events, ['probe', 'connect']);
      connection.complete();
      await Future.wait([first, second, third]);
      await harness.run(attempt);

      expect(harness.events, ['probe', 'connect']);
      harness.coordinator.dispose();
    },
  );

  test('a reentrant readiness event does not start another probe', () async {
    final harness = _Harness();
    final attempt = harness.begin();
    Future<void>? repeated;
    harness.onProbe = () => repeated = harness.run(attempt);

    final pending = harness.run(attempt);
    await pending;
    await repeated;

    expect(identical(pending, repeated), isTrue);
    expect(harness.events, ['probe', 'connect']);
    harness.coordinator.dispose();
  });

  test('synchronous probe failure still connects the selected node', () async {
    final harness = _Harness();
    final failure = StateError('probe_unavailable');
    harness.onProbe = () => throw failure;

    await harness.run(harness.begin());

    expect(harness.events, ['probe', 'probe_error', 'connect']);
    expect(harness.probeErrors, [failure]);
    expect(harness.probeIsCurrent!(), isFalse);
    harness.coordinator.dispose();
  });

  test('asynchronous probe failure still connects the selected node', () async {
    final harness = _Harness();
    final latency = Completer<void>();
    final failure = StateError('probe_unavailable');
    final pending = harness.run(harness.begin(), latency: latency.future);

    latency.completeError(failure);
    await pending;

    expect(harness.events, ['probe', 'probe_error', 'connect']);
    expect(harness.probeErrors, [failure]);
    harness.coordinator.dispose();
  });

  testWidgets('the default timeout connects once at eight seconds', (
    tester,
  ) async {
    final harness = _Harness();
    final latency = Completer<void>();
    final attempt = harness.begin();
    final pending = harness.run(attempt, latency: latency.future);

    await tester.pump(const Duration(seconds: 7));
    expect(harness.events, ['probe']);
    expect(harness.probeIsCurrent!(), isTrue);
    await tester.pump(const Duration(seconds: 1));
    await pending;
    await harness.run(attempt);

    expect(harness.events, ['probe', 'probe_error', 'connect']);
    expect(harness.probeErrors, [isA<TimeoutException>()]);
    expect(harness.probeIsCurrent!(), isFalse);
    latency.completeError(StateError('late_probe_failure'));
    await tester.pump();

    expect(harness.probeErrors, hasLength(1));
    harness.coordinator.dispose();
  });

  test('configurable timeout invalidates late probe writes', () async {
    final harness = _Harness(probeTimeout: const Duration(milliseconds: 1));
    final latency = Completer<void>();
    var resultWrites = 0;
    final lateResult = latency.future.then((_) {
      if (harness.probeIsCurrent!()) resultWrites++;
    });
    final pending = harness.run(harness.begin(), latency: lateResult);

    await pending;
    latency.complete();
    await lateResult;

    expect(resultWrites, 0);
    expect(harness.events, ['probe', 'probe_error', 'connect']);
    harness.coordinator.dispose();
  });

  test('cancellation releases a probe and absorbs its late failure', () async {
    final harness = _Harness();
    final latency = Completer<void>();
    final attempt = harness.begin();
    final pending = harness.run(attempt, latency: latency.future);

    harness.coordinator.cancel();
    expect(harness.probeIsCurrent!(), isFalse);
    await pending;
    latency.completeError(StateError('cancelled_probe_failure'));
    await Future<void>.delayed(Duration.zero);
    await harness.run(attempt);

    expect(harness.events, ['probe']);
    expect(harness.probeErrors, isEmpty);
    harness.coordinator.dispose();
  });

  test('a new session supersedes the old probe', () async {
    final harness = _Harness();
    final latency = Completer<void>();
    final first = harness.run(harness.begin(), latency: latency.future);
    final oldProbeIsCurrent = harness.probeIsCurrent!;
    final secondAttempt = harness.begin();

    expect(oldProbeIsCurrent(), isFalse);
    await first;
    await harness.run(secondAttempt);
    latency.complete();
    await latency.future;

    expect(harness.events, ['probe', 'probe', 'connect']);
    harness.coordinator.dispose();
  });

  test('a disabled session cancels a previous enabled attempt', () async {
    final harness = _Harness();
    final latency = Completer<void>();
    final pending = harness.run(harness.begin(), latency: latency.future);
    final disabledAttempt = harness.begin(enabled: false);

    await pending;
    await harness.run(disabledAttempt);
    latency.complete();
    await latency.future;

    expect(harness.events, ['probe']);
    harness.coordinator.dispose();
  });

  test(
    'an obsolete session suppresses probe failures and connection',
    () async {
      final harness = _Harness();
      final latency = Completer<void>();
      final pending = harness.run(harness.begin(), latency: latency.future);

      harness.sessionCurrent = false;
      latency.completeError(StateError('obsolete_probe_failure'));
      await pending;

      expect(harness.events, ['probe']);
      expect(harness.probeIsCurrent!(), isFalse);
      harness.coordinator.dispose();
    },
  );

  test('manual guard rejection consumes the attempt before probing', () async {
    final harness = _Harness();
    final attempt = harness.begin();
    harness.canProceed = false;

    await harness.run(attempt);
    harness.canProceed = true;
    await harness.run(attempt);

    expect(harness.events, isEmpty);
    harness.coordinator.dispose();
  });

  test(
    'manual intent during probing prevents a later automatic start',
    () async {
      final harness = _Harness();
      final latency = Completer<void>();
      final attempt = harness.begin();
      final pending = harness.run(attempt, latency: latency.future);

      harness.canProceed = false;
      latency.complete();
      await pending;
      harness.canProceed = true;
      await harness.run(attempt);

      expect(harness.events, ['probe']);
      harness.coordinator.dispose();
    },
  );

  test(
    'a rejected live probe guard remains cancelled after readiness returns',
    () async {
      final harness = _Harness();
      final latency = Completer<void>();
      final attempt = harness.begin();
      final pending = harness.run(attempt, latency: latency.future);

      harness.canProceed = false;
      expect(harness.probeIsCurrent!(), isFalse);
      harness.canProceed = true;
      expect(harness.probeIsCurrent!(), isFalse);
      await pending;
      latency.complete();
      await harness.run(attempt);

      expect(harness.events, ['probe']);
      harness.coordinator.dispose();
    },
  );

  test('an existing VPN is probed without restarting its connection', () async {
    final harness = _Harness()..connected = true;
    final attempt = harness.begin();

    await harness.run(attempt);
    await harness.run(attempt);

    expect(harness.events, ['probe']);
    harness.coordinator.dispose();
  });

  test('a connection established during the probe is preserved', () async {
    final harness = _Harness();
    final latency = Completer<void>();
    final pending = harness.run(harness.begin(), latency: latency.future);

    harness.connected = true;
    latency.complete();
    await pending;

    expect(harness.events, ['probe']);
    harness.coordinator.dispose();
  });

  test('a failed automatic connection reports once without retrying', () async {
    final harness = _Harness();
    final connection = Completer<void>();
    final attempt = harness.begin();
    final failure = StateError('connection_failed');
    final pending = harness.run(attempt, connection: connection.future);
    await harness.connectionEntered.future;

    connection.completeError(failure);
    await pending;
    await harness.run(attempt);

    expect(harness.events, ['probe', 'connect', 'connection_error']);
    expect(harness.connectionErrors, [failure]);
    harness.coordinator.dispose();
  });

  test('cancellation suppresses errors from an in-flight connection', () async {
    final harness = _Harness();
    final connection = Completer<void>();
    final pending = harness.run(harness.begin(), connection: connection.future);
    await harness.connectionEntered.future;

    harness.coordinator.cancel();
    connection.completeError(StateError('stale_connection_failure'));
    await pending;

    expect(harness.events, ['probe', 'connect']);
    expect(harness.connectionErrors, isEmpty);
    harness.coordinator.dispose();
  });

  test('disposal cancels pending work and prevents new attempts', () async {
    final harness = _Harness();
    final latency = Completer<void>();
    final attempt = harness.begin();
    final pending = harness.run(attempt, latency: latency.future);

    harness.coordinator.dispose();
    harness.coordinator.dispose();
    await pending;
    expect(harness.probeIsCurrent!(), isFalse);
    latency.completeError(StateError('disposed_probe_failure'));
    await Future<void>.delayed(Duration.zero);
    await harness.run(attempt);

    expect(harness.events, ['probe']);
    expect(harness.begin, throwsStateError);
  });
}

class _Harness {
  _Harness({Duration probeTimeout = const Duration(seconds: 8)})
    : coordinator = StartupConnectionCoordinator(probeTimeout: probeTimeout);

  final StartupConnectionCoordinator coordinator;
  final events = <String>[];
  final probeErrors = <Object>[];
  final connectionErrors = <Object>[];
  final connectionEntered = Completer<void>();
  bool sessionCurrent = true;
  bool canProceed = true;
  bool connected = false;
  bool Function()? probeIsCurrent;
  void Function()? onProbe;

  StartupConnectionAttempt begin({bool enabled = true}) =>
      coordinator.begin(enabled: enabled, isCurrent: () => sessionCurrent);

  Future<void> run(
    StartupConnectionAttempt attempt, {
    bool authenticated = true,
    bool routingReady = true,
    Future<void>? latency,
    Future<void>? connection,
  }) => coordinator.run(
    attempt,
    authenticated: authenticated,
    routingReady: routingReady,
    canProceed: () => canProceed,
    testLatency: (isCurrent) {
      events.add('probe');
      probeIsCurrent = isCurrent;
      onProbe?.call();
      return latency ?? Future<void>.value();
    },
    isConnected: () => connected,
    connect: () {
      events.add('connect');
      if (!connectionEntered.isCompleted) connectionEntered.complete();
      return connection ?? Future<void>.value();
    },
    onProbeError: (error) {
      events.add('probe_error');
      probeErrors.add(error);
    },
    onConnectionError: (error) {
      events.add('connection_error');
      connectionErrors.add(error);
    },
  );
}

import 'dart:async';

import 'package:fl_clash/common/login_routing_coordinator.dart';
import 'package:fl_clash/models/profile.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('login routing profile identity', () {
    final saved = Profile(
      id: 7,
      url: 'https://example.invalid/subscription',
      label: 'same plan',
      lastUpdateDate: DateTime.utc(2026, 9, 7),
      autoUpdateDuration: const Duration(hours: 1),
      currentGroupName: 'proxy',
      selectedMap: const {'proxy': '香港 1'},
    );

    test('normalized labels and display ordering preserve identity', () {
      final normalized = [
        saved.copyWith(id: 8),
      ].optimizeLabel(saved).copyWith(order: 3, unfoldSet: {'proxy'});

      expect(normalized.label, isNot(saved.label));
      expect(saved == normalized, isFalse);
      expect(loginRoutingProfileMatches(saved, normalized), isTrue);
    });

    test(
      'different profile or subscription cannot reuse a login selection',
      () {
        expect(
          loginRoutingProfileMatches(saved, saved.copyWith(id: 8)),
          isFalse,
        );
        expect(
          loginRoutingProfileMatches(saved, saved.copyWith(url: 'other')),
          isFalse,
        );
        expect(loginRoutingProfileMatches(saved, null), isFalse);
        expect(loginRoutingProfileMatches(null, saved), isFalse);
        expect(loginRoutingProfileMatches(null, null), isTrue);
      },
    );

    test('online identity rejects a newer subscription content revision', () {
      final refreshed = saved.copyWith(
        lastUpdateDate: DateTime.utc(2026, 9, 8),
      );

      expect(loginRoutingProfileMatches(saved, refreshed), isFalse);
    });

    test(
      'offline apply may refresh missing profile content and normalize label',
      () {
        final applied = saved.copyWith(
          label: 'same plan (2)',
          lastUpdateDate: DateTime.utc(2026, 9, 8),
          subscriptionInfo: const SubscriptionInfo(download: 10),
        );

        expect(
          loginRoutingProfileMatches(saved, applied, allowContentRefresh: true),
          isTrue,
        );
      },
    );

    test('offline refresh still rejects selection and script changes', () {
      for (final changed in [
        saved.copyWith(selectedMap: {'proxy': '香港 2'}),
        saved.copyWith(currentGroupName: 'other'),
        saved.copyWith(scriptId: 9),
        saved.copyWith(id: 8),
        saved.copyWith(url: 'other'),
      ]) {
        expect(
          loginRoutingProfileMatches(saved, changed, allowContentRefresh: true),
          isFalse,
        );
      }
    });

    test(
      'normalized current profile can become the strict pending snapshot',
      () async {
        final harness = _Harness();
        final current = saved.copyWith(label: 'same plan (2)', order: 3);
        expect(loginRoutingProfileMatches(saved, current), isTrue);
        final snapshot = current;
        harness.canStart = current == snapshot;
        await harness.route(harness.begin());

        expect(harness.events.last, 'result:selected');
        harness.coordinator.dispose();
      },
    );

    test(
      'offline preparation captures the updated applied snapshot before selection',
      () async {
        final harness = _Harness();
        final ready = Completer<void>();
        var current = saved;
        var snapshot = current;
        final applied = saved.copyWith(
          label: 'same plan (2)',
          lastUpdateDate: DateTime.utc(2026, 9, 8),
        );
        Profile? selectedSnapshot;
        final pending = harness.coordinator.select<Profile>(
          harness.begin(),
          prepare: () async {
            await ready.future;
            current = applied;
            if (loginRoutingProfileMatches(
              snapshot,
              current,
              allowContentRefresh: true,
            )) {
              snapshot = current;
            }
          },
          canStart: () => current == snapshot,
          select: (_) async => snapshot,
          onResult: (result) => selectedSnapshot = result,
          onError: harness.errors.add,
        );
        expect(selectedSnapshot, isNull);
        ready.complete();
        await pending;

        expect(selectedSnapshot, applied);
        expect(selectedSnapshot!.lastUpdateDate, isNot(saved.lastUpdateDate));
        expect(harness.errors, isEmpty);
        harness.coordinator.dispose();
      },
    );
  });

  test(
    'each authenticated entry cancels previous selection and resets rule',
    () {
      final harness = _Harness();
      final first = harness.begin();
      final second = harness.begin();

      expect(harness.events, ['cancel', 'rule', 'cancel', 'rule']);
      expect(harness.coordinator.isCurrent(first), isFalse);
      expect(harness.coordinator.isCurrent(second), isTrue);
      harness.coordinator.dispose();
    },
  );

  test(
    'selection waits for profile and core preparation without blocking begin',
    () async {
      final harness = _Harness();
      final preparation = Completer<void>();
      final attempt = harness.begin();
      final pending = harness.route(attempt, preparation: preparation.future);

      expect(harness.events, ['cancel', 'rule', 'prepare']);
      expect(harness.coordinator.isCurrent(attempt), isTrue);
      preparation.complete();
      await pending;

      expect(harness.events, [
        'cancel',
        'rule',
        'prepare',
        'select',
        'result:selected',
      ]);
      harness.coordinator.dispose();
    },
  );

  test(
    'manual mode node or profile change before preparation prevents selection',
    () async {
      final harness = _Harness();
      final preparation = Completer<void>();
      final pending = harness.route(
        harness.begin(),
        preparation: preparation.future,
      );
      harness.canStart = false;
      preparation.complete();
      await pending;

      expect(harness.events, ['cancel', 'rule', 'prepare']);
      harness.coordinator.dispose();
    },
  );

  test(
    'session revision changing during preparation prevents selection',
    () async {
      final harness = _Harness();
      final preparation = Completer<void>();
      final pending = harness.route(
        harness.begin(),
        preparation: preparation.future,
      );
      harness.sessionCurrent = false;
      preparation.complete();
      await pending;

      expect(harness.events, ['cancel', 'rule', 'prepare']);
      harness.coordinator.dispose();
    },
  );

  test(
    'logout releases pending preparation and discards its later completion',
    () async {
      final harness = _Harness();
      final preparation = Completer<void>();
      final attempt = harness.begin();
      final pending = harness.route(attempt, preparation: preparation.future);
      harness.coordinator.cancel();
      await pending;

      expect(harness.coordinator.isCurrent(attempt), isFalse);
      expect(harness.events, ['cancel', 'rule', 'prepare', 'cancel']);
      preparation.complete();
      await preparation.future;
      expect(harness.events.where((event) => event == 'select'), isEmpty);
      harness.coordinator.dispose();
    },
  );

  test(
    'a new authenticated entry cancels an old pending preparation',
    () async {
      final harness = _Harness();
      final preparation = Completer<void>();
      final old = harness.begin();
      final pending = harness.route(old, preparation: preparation.future);
      final current = harness.begin();
      await pending;
      await harness.route(current);
      preparation.complete();
      await preparation.future;

      expect(harness.events.where((event) => event == 'select'), hasLength(1));
      expect(
        harness.events.where((event) => event == 'result:selected'),
        hasLength(1),
      );
      harness.coordinator.dispose();
    },
  );

  test(
    'selection receives live cancellation and a late result is not shown',
    () async {
      final harness = _Harness();
      final selection = Completer<String>();
      final pending = harness.route(
        harness.begin(),
        selection: selection.future,
      );
      await harness.selectionEntered.future;
      expect(harness.selectionIsCancelled!(), isFalse);

      harness.coordinator.cancel();
      expect(harness.selectionIsCancelled!(), isTrue);
      selection.complete('unavailable');
      await pending;

      expect(
        harness.events.where((event) => event.startsWith('result:')),
        isEmpty,
      );
      expect(harness.errors, isEmpty);
      harness.coordinator.dispose();
    },
  );

  test('a stale session cannot display a failed selection result', () async {
    final harness = _Harness();
    final selection = Completer<String>();
    final pending = harness.route(harness.begin(), selection: selection.future);
    await harness.selectionEntered.future;
    harness.sessionCurrent = false;
    selection.complete('failed');
    await pending;

    expect(harness.selectionIsCancelled!(), isTrue);
    expect(
      harness.events.where((event) => event.startsWith('result:')),
      isEmpty,
    );
    harness.coordinator.dispose();
  });

  test(
    'unavailable nodes remain a selection result rather than an auth error',
    () async {
      final harness = _Harness();
      await harness.route(
        harness.begin(),
        selection: Future.value('unavailable'),
      );

      expect(harness.events.last, 'result:unavailable');
      expect(harness.errors, isEmpty);
      harness.coordinator.dispose();
    },
  );

  test(
    'preparation failure is reported without failing authentication',
    () async {
      final harness = _Harness();
      final preparation = Completer<void>();
      final pending = harness.route(
        harness.begin(),
        preparation: preparation.future,
      );
      preparation.completeError(StateError('core_unavailable'));
      await expectLater(pending, completes);

      expect(harness.errors, [isA<StateError>()]);
      expect(harness.events.where((event) => event == 'select'), isEmpty);
      harness.coordinator.dispose();
    },
  );

  test(
    'selection failure is reported without failing authentication',
    () async {
      final harness = _Harness();
      final selection = Completer<String>();
      final pending = harness.route(
        harness.begin(),
        selection: selection.future,
      );
      await harness.selectionEntered.future;
      selection.completeError(StateError('probe_failure'));
      await expectLater(pending, completes);

      expect(harness.errors, [isA<StateError>()]);
      harness.coordinator.dispose();
    },
  );

  test('disposal suppresses late selection errors and is idempotent', () async {
    final harness = _Harness();
    final selection = Completer<String>();
    final pending = harness.route(harness.begin(), selection: selection.future);
    await harness.selectionEntered.future;
    harness.coordinator.dispose();
    harness.coordinator.dispose();
    selection.completeError(StateError('late_probe_failure'));
    await expectLater(pending, completes);

    expect(harness.errors, isEmpty);
    expect(harness.events.where((event) => event == 'cancel'), hasLength(2));
    expect(harness.begin, throwsStateError);
  });

  test(
    'disposal releases pending readiness and absorbs late preparation errors',
    () async {
      final harness = _Harness();
      final preparation = Completer<void>();
      final pending = harness.route(
        harness.begin(),
        preparation: preparation.future,
      );
      harness.coordinator.dispose();
      await pending;
      final observed = expectLater(preparation.future, throwsStateError);
      preparation.completeError(StateError('late_prepare_failure'));
      await observed;

      expect(harness.errors, isEmpty);
      expect(harness.events.where((event) => event == 'select'), isEmpty);
    },
  );

  test('an already obsolete attempt performs no preparation', () async {
    final harness = _Harness();
    final attempt = harness.begin();
    harness.sessionCurrent = false;
    await harness.route(attempt);

    expect(harness.events, ['cancel', 'rule']);
    harness.coordinator.dispose();
  });

  test(
    'manual intent during subscription sync cancels pending login routing',
    () async {
      final harness = _Harness();
      final preparation = Completer<void>();
      final attempt = harness.begin();
      final pending = harness.route(attempt, preparation: preparation.future);
      harness.manualSelectionRevision++;
      preparation.complete();
      await pending;

      expect(harness.coordinator.isCurrent(attempt), isFalse);
      expect(harness.events.where((event) => event == 'select'), isEmpty);
      harness.coordinator.dispose();
    },
  );

  test(
    'manual intent invalidates a running probe and its notification',
    () async {
      final harness = _Harness();
      final selection = Completer<String>();
      final pending = harness.route(
        harness.begin(),
        selection: selection.future,
      );
      await harness.selectionEntered.future;
      harness.manualSelectionRevision++;
      expect(harness.selectionIsCancelled!(), isTrue);
      selection.complete('unavailable');
      await pending;

      expect(
        harness.events.where((event) => event.startsWith('result:')),
        isEmpty,
      );
      harness.coordinator.dispose();
    },
  );
}

class _Harness {
  _Harness() {
    coordinator = LoginRoutingCoordinator(
      resetToRule: () {
        manualSelectionRevision++;
        events.add('rule');
      },
      cancelSelection: () => events.add('cancel'),
    );
  }

  late final LoginRoutingCoordinator coordinator;
  final events = <String>[];
  final errors = <Object>[];
  final selectionEntered = Completer<void>();
  bool sessionCurrent = true;
  bool canStart = true;
  int manualSelectionRevision = 0;
  bool Function()? selectionIsCancelled;

  LoginRoutingAttempt begin() {
    late final int expectedManualRevision;
    final attempt = coordinator.begin(
      isSessionCurrent: () =>
          sessionCurrent && manualSelectionRevision == expectedManualRevision,
    );
    expectedManualRevision = manualSelectionRevision;
    return attempt;
  }

  Future<void> route(
    LoginRoutingAttempt attempt, {
    Future<void>? preparation,
    Future<String>? selection,
  }) => coordinator.select<String>(
    attempt,
    prepare: () {
      events.add('prepare');
      return preparation ?? Future.value();
    },
    canStart: () => canStart,
    select: (isCancelled) {
      events.add('select');
      selectionIsCancelled = isCancelled;
      if (!selectionEntered.isCompleted) selectionEntered.complete();
      return selection ?? Future.value('selected');
    },
    onResult: (result) => events.add('result:$result'),
    onError: errors.add,
  );
}

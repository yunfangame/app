import 'dart:async';

import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/database.dart';
import 'package:fl_clash/state.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:riverpod/riverpod.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  group('withRollback', () {
    test('rolls back with snapshot and rethrows async errors', () async {
      final error = StateError('write failed');
      final previous = [1, 2, 3];
      List<int>? rolledBack;

      await expectLater(
        withRollback(
          snapshot: previous,
          action: () async {
            throw error;
          },
          rollback: (value) => rolledBack = value,
        ),
        throwsA(same(error)),
      );

      expect(rolledBack, previous);
    });

    test('does not roll back when action succeeds', () async {
      var rollbackCalled = false;

      await withRollback(
        snapshot: [1, 2, 3],
        action: () async {},
        rollback: (_) => rollbackCalled = true,
      );

      expect(rollbackCalled, false);
    });
  });

  group('Profiles durable writes', () {
    const initial = Profile(
      id: 1,
      label: 'Original',
      url: 'fengwo-v2://fixture/original',
      autoUpdateDuration: Duration(days: 1),
    );
    late ProviderContainer container;
    late _ControlledProfiles profiles;

    setUp(() {
      profiles = _ControlledProfiles([initial]);
      container = ProviderContainer(
        overrides: [profilesProvider.overrideWith(() => profiles)],
      );
      container.read(profilesProvider);
    });

    tearDown(() {
      container.dispose();
    });

    test('durable completion waits for persistence', () async {
      final release = Completer<void>();
      profiles.persist = (_) => release.future;
      var completed = false;
      final saved = profiles
          .putDurable(initial.copyWith(label: 'Updated'))
          .then((_) => completed = true);
      await Future<void>.delayed(Duration.zero);
      expect(completed, isFalse);
      release.complete();
      await saved;
      expect(completed, isTrue);
    });

    test('a current failed write restores its prior value', () async {
      final error = StateError('write failed');
      profiles.persist = (_) => Future.error(error);
      await expectLater(
        profiles.putDurable(initial.copyWith(label: 'Failed')),
        throwsA(same(error)),
      );
      expect(container.read(profilesProvider), [initial]);
    });

    for (final migrateSource in [false, true]) {
      test('late failure preserves a newer write ($migrateSource)', () async {
        final failure = Completer<void>();
        var writes = 0;
        profiles.persist = (_) =>
            ++writes == 1 ? failure.future : Future.value();
        final stale = profiles.putDurable(initial.copyWith(label: 'Stale'));
        final rejected = expectLater(stale, throwsA(isA<StateError>()));
        final latest = initial.copyWith(
          label: 'Latest',
          url: migrateSource ? 'fengwo-v2://fixture/replacement' : initial.url,
        );
        await profiles.putDurable(latest);
        failure.completeError(StateError('late write failed'));
        await rejected;
        expect(container.read(profilesProvider), [latest]);
      });
    }

    test('late failure preserves a newer legacy put', () async {
      final failure = Completer<void>();
      var writes = 0;
      profiles.persist = (_) => ++writes == 1 ? failure.future : Future.value();
      final stale = profiles.putDurable(initial.copyWith(label: 'Stale'));
      final rejected = expectLater(stale, throwsA(isA<StateError>()));
      final latest = initial.copyWith(label: 'Latest');
      profiles.put(latest);
      await Future<void>.delayed(Duration.zero);
      failure.completeError(StateError('late write failed'));
      await rejected;
      expect(container.read(profilesProvider), [latest]);
    });

    test('failed row rollback preserves another profile write', () async {
      final failure = Completer<void>();
      var writes = 0;
      profiles.persist = (_) => ++writes == 1 ? failure.future : Future.value();
      final stale = profiles.putDurable(initial.copyWith(label: 'Stale'));
      final rejected = expectLater(stale, throwsA(isA<StateError>()));
      final other = initial.copyWith(id: 2, label: 'Other');
      await profiles.putDurable(other);
      failure.completeError(StateError('late write failed'));
      await rejected;
      expect(container.read(profilesProvider), [other, initial]);
    });

    test('late failure cannot restore state across account revision', () async {
      final failure = Completer<void>();
      profiles.persist = (_) => failure.future;
      final stale = profiles.putDurable(initial.copyWith(label: 'Stale'));
      final rejected = expectLater(stale, throwsA(isA<StateError>()));
      globalState.clearXboardSession();
      final current = container.read(profilesProvider);
      failure.completeError(StateError('late write failed'));
      await rejected;
      expect(container.read(profilesProvider), current);
    });

    test('late failure cannot restore externally migrated source', () async {
      final failure = Completer<void>();
      profiles.persist = (_) => failure.future;
      final stale = profiles.putDurable(initial.copyWith(label: 'Stale'));
      final rejected = expectLater(stale, throwsA(isA<StateError>()));
      final latest = initial.copyWith(url: 'fengwo-v2://fixture/current');
      profiles.replace([latest]);
      failure.completeError(StateError('late write failed'));
      await rejected;
      expect(container.read(profilesProvider), [latest]);
    });
  });
}

class _ControlledProfiles extends Profiles {
  _ControlledProfiles(this.initial);
  final List<Profile> initial;
  Future<void> Function(Profile) persist = (_) async {};

  @override
  List<Profile> build() => initial;

  @override
  Future<void> persistProfile(Profile profile) => persist(profile);

  void replace(List<Profile> profiles) => state = profiles;
}

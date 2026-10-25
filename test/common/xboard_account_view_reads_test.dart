import 'dart:async';

import 'package:fl_clash/common/xboard_account_view_reads.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('financial reads merge only concurrent requests', () async {
    final read = XboardAccountViewRead<int>();
    final pending = Completer<int>();
    var calls = 0;
    Future<int> load() {
      calls++;
      return pending.future;
    }

    final first = read.load(load);
    expect(read.load(load), same(first));
    pending.complete(1);
    expect(await first, 1);
    expect(await read.load(load), 1);
    expect(calls, 2);
  });

  test(
    'automatic reuse expires at fifteen seconds and on clock rollback',
    () async {
      var now = DateTime.utc(2026, 10, 25);
      final read = XboardAccountViewRead<int>(
        ttl: const Duration(seconds: 15),
        now: () => now,
      );
      var calls = 0;
      Future<int> load() async => ++calls;
      expect(await read.load(load), 1);
      now = now.add(const Duration(seconds: 14));
      expect(await read.load(load), 1);
      now = now.add(const Duration(seconds: 1));
      expect(await read.load(load), 2);
      now = now.subtract(const Duration(seconds: 1));
      expect(await read.load(load), 3);
      expect(await read.load(load, forceRefresh: true), 4);
    },
  );

  test(
    'manual refresh bypasses normal and simultaneous manual reads merge',
    () async {
      final read = XboardAccountViewRead<int>(ttl: const Duration(seconds: 15));
      final normal = Completer<int>();
      final forced = Completer<int>();
      final old = read.load(() => normal.future);
      final before = read.revision;
      final fresh = read.load(() => forced.future, forceRefresh: true);
      expect(read.revision, greaterThan(before));
      expect(read.load(() async => 99, forceRefresh: true), same(fresh));
      forced.complete(2);
      expect(await fresh, 2);
      normal.complete(1);
      expect(await old, 1);
      expect(await read.load(() async => 99), 2);
    },
  );

  test(
    'mutation invalidation never joins a pre-mutation forced request',
    () async {
      final read = XboardAccountViewRead<int>(ttl: const Duration(seconds: 15));
      final pending = Completer<int>();
      final old = read.load(() => pending.future, forceRefresh: true);
      read.invalidate();
      expect(await read.load(() async => 2, forceRefresh: true), 2);
      pending.complete(1);
      await old;
      expect(await read.load(() async => 99), 2);
    },
  );

  test(
    'failed force does not let later readers join the superseded normal',
    () async {
      final read = XboardAccountViewRead<int>();
      final pending = Completer<int>();
      final old = read.load(() => pending.future);
      await expectLater(
        read.load(() async => throw StateError('failure'), forceRefresh: true),
        throwsStateError,
      );
      expect(await read.load(() async => 3), 3);
      pending.complete(1);
      await old;
    },
  );

  test('failures are not cached as successful data', () async {
    final read = XboardAccountViewRead<int>(ttl: const Duration(seconds: 15));
    await expectLater(
      read.load(() async => throw StateError('failure')),
      throwsStateError,
    );
    expect(await read.load(() async => 2), 2);
  });
}

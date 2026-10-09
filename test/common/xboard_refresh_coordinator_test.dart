import 'dart:async';

import 'package:fl_clash/common/xboard_refresh_coordinator.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'desktop budget permits fallback beyond the old 30 second limit',
    (tester) async {
      final response = Completer<String>();
      Object? failure;
      String? result;
      bool Function()? current;
      runBoundedXboardProfileSync(
        timeout: const Duration(minutes: 2),
        isCurrent: () => true,
        sync: (isCurrent) {
          current = isCurrent;
          return response.future;
        },
      ).then<void>(
        (value) => result = value,
        onError: (Object error) => failure = error,
      );
      await tester.pump(const Duration(seconds: 90));
      expect(current!(), isTrue);
      expect(failure, isNull);
      response.complete('fallback profile');
      await tester.pump();
      expect(result, 'fallback profile');
      expect(current!(), isFalse);
    },
  );

  testWidgets('desktop hard deadline rejects late profile adoption', (
    tester,
  ) async {
    final response = Completer<String>();
    Object? failure;
    var adopted = false;
    bool Function()? current;
    runBoundedXboardProfileSync(
      timeout: const Duration(minutes: 2),
      isCurrent: () => true,
      sync: (isCurrent) {
        current = isCurrent;
        return response.future.then((value) {
          if (isCurrent()) adopted = true;
          return value;
        });
      },
    ).then<void>((_) {}, onError: (Object error) => failure = error);
    await tester.pump(const Duration(minutes: 2));
    expect(failure, isA<TimeoutException>());
    expect(current!(), isFalse);
    response.complete('late profile');
    await tester.pump();
    expect(adopted, isFalse);
  });

  testWidgets('account replacement invalidates a profile before its deadline', (
    tester,
  ) async {
    final response = Completer<String>();
    var activeAccount = true;
    var adopted = false;
    runBoundedXboardProfileSync(
      timeout: const Duration(minutes: 2),
      isCurrent: () => activeAccount,
      sync: (isCurrent) => response.future.then((value) {
        if (isCurrent()) adopted = true;
        return value;
      }),
    ).then<void>((_) {});
    await tester.pump(const Duration(seconds: 15));
    activeAccount = false;
    response.complete('old account profile');
    await tester.pump();
    expect(adopted, isFalse);
  });

  test('slow optional nodes do not delay usable profile or routing', () async {
    final nodes = Completer<void>();
    final profile = Completer<String>();
    final events = <String>[];
    final result = syncXboardProfileFirst(
      isCurrent: () => true,
      syncProfile: () {
        events.add('profile');
        return profile.future;
      },
      refreshMetadata: () {
        events.add('nodes');
        return nodes.future;
      },
      prepareRouting: (value) async => events.add('routing:$value'),
    );
    expect(events, ['profile', 'nodes']);
    profile.complete('usable');
    expect(await result, 'usable');
    expect(events, ['profile', 'nodes', 'routing:usable']);
    expect(nodes.isCompleted, isFalse);
    nodes.complete();
  });

  test('optional metadata errors preserve profile readiness', () async {
    final failed = Completer<void>();
    final errors = <Object>[];
    var routed = false;
    final result = syncXboardProfileFirst(
      isCurrent: () => true,
      syncProfile: () async => 'usable',
      refreshMetadata: () => failed.future,
      onMetadataError: (error, _) => errors.add(error),
      prepareRouting: (_) async => routed = true,
    );
    failed.completeError(StateError('nodes_unavailable'));
    expect(await result, 'usable');
    expect(routed, isTrue);
    expect(errors.single, isStateError);
  });

  test('logout before profile response cannot select its node', () async {
    var current = true;
    var routed = false;
    final profile = Completer<String>();
    final result = syncXboardProfileFirst(
      isCurrent: () => current,
      syncProfile: () => profile.future,
      prepareRouting: (_) async => routed = true,
    );
    final rejected = expectLater(result, throwsStateError);
    current = false;
    profile.complete('old account');
    await rejected;
    expect(routed, isFalse);
  });

  test(
    'session replaced during routing cannot complete old readiness',
    () async {
      var current = true;
      final result = syncXboardProfileFirst(
        isCurrent: () => current,
        syncProfile: () async => 'old account',
        prepareRouting: (_) async => current = false,
      );
      await expectLater(result, throwsStateError);
    },
  );

  test(
    'configuration failure never reports ready despite optional nodes',
    () async {
      var routed = false;
      final nodes = Completer<void>();
      final result = syncXboardProfileFirst<String>(
        isCurrent: () => true,
        syncProfile: () async => throw StateError('configuration_failed'),
        refreshMetadata: () => nodes.future,
        prepareRouting: (_) async => routed = true,
      );
      await expectLater(result, throwsStateError);
      expect(routed, isFalse);
      nodes.complete();
    },
  );

  test('overlapping same session refresh shares one request', () async {
    final coordinator = XboardRefreshCoordinator<String>();
    final response = Completer<String>();
    var calls = 0;
    Future<String> refresh(XboardRefreshAttempt<String> _) {
      calls++;
      return response.future;
    }

    final first = coordinator.run(isCurrent: () => true, refresh: refresh);
    final second = coordinator.run(isCurrent: () => true, refresh: refresh);
    expect(identical(first, second), isTrue);
    expect(calls, 1);
    response.complete('profile');
    expect(await first, 'profile');
    expect(await second, 'profile');
  });

  test(
    'joining node refresh upgrades intent once without new downloads',
    () async {
      final coordinator = XboardRefreshCoordinator<bool>();
      final response = Completer<bool>();
      var metadataRequests = 0;
      var calls = 0;
      final first = coordinator.run(
        isCurrent: () => true,
        refresh: (attempt) {
          calls++;
          attempt.onMetadataRequested = () => metadataRequests++;
          return response.future;
        },
      );
      final second = coordinator.run(
        isCurrent: () => true,
        refreshMetadata: true,
        refresh: (_) async => false,
      );
      final third = coordinator.run(
        isCurrent: () => true,
        refreshMetadata: true,
        refresh: (_) async => false,
      );
      expect(calls, 1);
      expect(metadataRequests, 1);
      expect(identical(first, second), isTrue);
      expect(identical(first, third), isTrue);
      response.complete(true);
      expect(await first, isTrue);
    },
  );

  test(
    'plan refresh joining node refresh retains delayed recheck intent',
    () async {
      final coordinator = XboardRefreshCoordinator<bool>();
      final response = Completer<void>();
      var requests = 0;
      XboardRefreshAttempt<bool>? pending;
      final first = coordinator.run(
        isCurrent: () => true,
        refreshMetadata: true,
        refresh: (attempt) async {
          requests++;
          pending = attempt;
          await response.future;
          return attempt.retryWhenUnchanged;
        },
      );
      expect(pending!.retryWhenUnchanged, isFalse);
      final second = coordinator.run(
        isCurrent: () => true,
        retryWhenUnchanged: true,
        refresh: (_) async => false,
      );
      final third = coordinator.run(
        isCurrent: () => true,
        refreshMetadata: true,
        refresh: (_) async => false,
      );
      expect(identical(first, second), isTrue);
      expect(identical(first, third), isTrue);
      expect(pending!.retryWhenUnchanged, isTrue);
      expect(pending!.refreshMetadata, isTrue);
      expect(requests, 1);
      response.complete();
      expect(await first, isTrue);
    },
  );

  test('node refresh joining plan refresh cannot disable rechecks', () async {
    final coordinator = XboardRefreshCoordinator<bool>();
    final response = Completer<void>();
    final first = coordinator.run(
      isCurrent: () => true,
      retryWhenUnchanged: true,
      refresh: (attempt) async {
        await response.future;
        return attempt.retryWhenUnchanged && attempt.refreshMetadata;
      },
    );
    final second = coordinator.run(
      isCurrent: () => true,
      refreshMetadata: true,
      refresh: (_) async => false,
    );
    expect(identical(first, second), isTrue);
    response.complete();
    expect(await first, isTrue);
  });

  test(
    'internal session replacement still shares its active refresh',
    () async {
      final coordinator = XboardRefreshCoordinator<String>();
      var activeRevision = 1;
      var refreshRevision = activeRevision;
      final response = Completer<String>();
      final first = coordinator.run(
        isCurrent: () => refreshRevision == activeRevision,
        refresh: (_) {
          activeRevision = 2;
          refreshRevision = 2;
          return response.future;
        },
      );
      final second = coordinator.run(
        isCurrent: () => activeRevision == 2,
        refresh: (_) async => 'duplicate',
      );
      expect(identical(first, second), isTrue);
      response.complete('current');
      expect(await second, 'current');
    },
  );

  test(
    'new account starts independently and old completion cannot clear it',
    () async {
      final coordinator = XboardRefreshCoordinator<String>();
      var oldCurrent = true;
      final old = Completer<String>();
      final latest = Completer<String>();
      final first = coordinator.run(
        isCurrent: () => oldCurrent,
        refresh: (_) => old.future,
      );
      oldCurrent = false;
      final second = coordinator.run(
        isCurrent: () => true,
        refresh: (_) => latest.future,
      );
      expect(identical(first, second), isFalse);
      old.complete('old');
      await first;
      final joined = coordinator.run(
        isCurrent: () => true,
        refresh: (_) async => 'duplicate',
      );
      expect(identical(second, joined), isTrue);
      latest.complete('new');
      expect(await joined, 'new');
    },
  );

  test(
    'failed request can be retried without retaining poisoned future',
    () async {
      final coordinator = XboardRefreshCoordinator<String>();
      await expectLater(
        coordinator.run(
          isCurrent: () => true,
          refresh: (_) async => throw StateError('network_failure'),
        ),
        throwsStateError,
      );
      expect(
        await coordinator.run(
          isCurrent: () => true,
          refresh: (_) async => 'recovered',
        ),
        'recovered',
      );
    },
  );
}

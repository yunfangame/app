import 'dart:async';

import 'package:fl_clash/common/xboard_auth.dart';
import 'package:fl_clash/common/xboard_subscription_snapshot.dart';
import 'package:fl_clash/state.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final session = _session();
  late DateTime now;
  late XboardSubscriptionSnapshotCache cache;

  setUp(() {
    now = DateTime.utc(2026, 10, 25, 12);
    cache = XboardSubscriptionSnapshotCache(now: () => now);
    globalState.clearXboardSession();
    globalState.setOfflineMode(false);
  });

  tearDown(() {
    globalState.clearXboardSession();
    globalState.setOfflineMode(false);
  });

  test(
    'automatic readers share the request and thirty second snapshot',
    () async {
      final pending = Completer<XboardSubscriptionData>();
      var requests = 0;
      Future<XboardSubscriptionData> load() {
        requests++;
        return pending.future;
      }

      final first = cache.load(session: session, loader: load);
      final second = cache.load(session: session, loader: load);
      expect(requests, 1);
      final value = _summary('first');
      pending.complete(value);
      expect(await first, same(value));
      expect(await second, same(value));
      now = now.add(const Duration(seconds: 29));
      expect(await cache.load(session: session, loader: load), same(value));
      expect(requests, 1);
      now = now.add(const Duration(seconds: 1));
      await cache.load(session: session, loader: load);
      expect(requests, 2);
    },
  );

  test(
    'identity includes origin auth token and secure subscription mode',
    () async {
      var calls = 0;
      for (final candidate in [
        session,
        _session(auth: 'other'),
        _session(host: 'other.example'),
        _session(token: 'other'),
        _session(secure: true),
      ]) {
        await cache.load(
          session: candidate,
          loader: () async => _summary('${++calls}'),
        );
      }
      expect(calls, 5);
    },
  );

  test(
    'forced refresh bypasses fresh values and merges simultaneous force',
    () async {
      await cache.load(session: session, loader: () async => _summary('old'));
      final pending = Completer<XboardSubscriptionData>();
      var calls = 0;
      Future<XboardSubscriptionData> load() {
        calls++;
        return pending.future;
      }

      final first = cache.load(
        session: session,
        loader: load,
        forceRefresh: true,
      );
      final second = cache.load(
        session: session,
        loader: load,
        forceRefresh: true,
      );
      final automatic = cache.load(session: session, loader: load);
      final value = _summary('paid');
      pending.complete(value);
      expect(await first, same(value));
      expect(await second, same(value));
      expect(await automatic, same(value));
      expect(calls, 1);
    },
  );

  for (final failOld in [false, true]) {
    test(
      'late normal response cannot replace force success ($failOld)',
      () async {
        final old = Completer<XboardSubscriptionData>();
        final first = cache.load(session: session, loader: () => old.future);
        final paid = _summary('paid');
        await cache.load(
          session: session,
          loader: () async => paid,
          forceRefresh: true,
        );
        if (failOld) {
          old.completeError(StateError('old network failure'));
        } else {
          old.complete(_summary('old'));
        }
        expect(await first, same(paid));
        expect(
          await cache.load(
            session: session,
            loader: () async => _summary('bad'),
          ),
          same(paid),
        );
      },
    );
  }

  test('normal readers await the newer pending forced request', () async {
    final normal = Completer<XboardSubscriptionData>();
    final forced = Completer<XboardSubscriptionData>();
    final first = cache.load(session: session, loader: () => normal.future);
    final second = cache.load(
      session: session,
      loader: () => forced.future,
      forceRefresh: true,
    );
    normal.complete(_summary('old'));
    final current = _summary('new');
    forced.complete(current);
    expect(await first, same(current));
    expect(await second, same(current));
  });

  test(
    'failed newer force cannot turn an expired value into success',
    () async {
      await cache.load(session: session, loader: () async => _summary('old'));
      now = now.add(const Duration(minutes: 1));
      final normal = Completer<XboardSubscriptionData>();
      final forced = Completer<XboardSubscriptionData>();
      final first = cache.load(session: session, loader: () => normal.future);
      final second = cache.load(
        session: session,
        loader: () => forced.future,
        forceRefresh: true,
      );
      final firstError = expectLater(first, throwsStateError);
      final secondError = expectLater(second, throwsStateError);
      normal.complete(_summary('outdated request'));
      await Future<void>.delayed(Duration.zero);
      forced.completeError(StateError('force failed'));
      await Future.wait([firstError, secondError]);
    },
  );

  for (final oldFails in [false, true]) {
    test(
      'earlier normal cannot mask a finished forced failure ($oldFails)',
      () async {
        final normal = Completer<XboardSubscriptionData>();
        final first = cache.load(session: session, loader: () => normal.future);
        final firstError = expectLater(first, throwsStateError);
        await expectLater(
          cache.load(
            session: session,
            forceRefresh: true,
            loader: () async => throw StateError('new force failure'),
          ),
          throwsStateError,
        );
        if (oldFails) {
          normal.completeError(ArgumentError('old failure'));
        } else {
          normal.complete(_summary('old response'));
        }
        await firstError;
      },
    );
  }

  test('a later failed force outranks an intermediate force success', () async {
    final normal = Completer<XboardSubscriptionData>();
    final first = cache.load(session: session, loader: () => normal.future);
    final rejected = expectLater(first, throwsStateError);
    await cache.load(
      session: session,
      forceRefresh: true,
      loader: () async => _summary('intermediate force'),
    );
    await expectLater(
      cache.load(
        session: session,
        forceRefresh: true,
        loader: () async => throw StateError('latest force failed'),
      ),
      throwsStateError,
    );
    normal.complete(_summary('old normal'));
    await rejected;
  });

  test(
    'automatic failures back off and a forced success resets cooldown',
    () async {
      var calls = 0;
      Future<XboardSubscriptionData> fail() async {
        calls++;
        throw StateError('network unavailable');
      }

      await expectLater(
        cache.load(session: session, loader: fail),
        throwsStateError,
      );
      now = now.add(const Duration(seconds: 29));
      await expectLater(
        cache.load(session: session, loader: fail),
        throwsStateError,
      );
      expect(calls, 1);
      now = now.add(const Duration(seconds: 1));
      await expectLater(
        cache.load(session: session, loader: fail),
        throwsStateError,
      );
      expect(calls, 2);
      now = now.add(const Duration(seconds: 59));
      await expectLater(
        cache.load(session: session, loader: fail),
        throwsStateError,
      );
      expect(calls, 2);
      final value = _summary('success');
      expect(
        await cache.load(
          session: session,
          loader: () async => value,
          forceRefresh: true,
        ),
        same(value),
      );
      expect(await cache.load(session: session, loader: fail), same(value));
      expect(calls, 2);
    },
  );

  test(
    'expiry and reset boundaries invalidate only the pre-boundary value',
    () async {
      for (final reset in [false, true]) {
        cache.clear();
        final boundary = now.add(const Duration(seconds: 10));
        var calls = 0;
        Future<XboardSubscriptionData> load() async => _summary(
          '${++calls}',
          expires: reset ? null : boundary.millisecondsSinceEpoch ~/ 1000,
          reset: reset ? boundary.millisecondsSinceEpoch ~/ 1000 : null,
        );
        await cache.load(session: session, loader: load);
        now = now.add(const Duration(seconds: 10));
        await cache.load(session: session, loader: load);
        expect(calls, 2);
        await cache.load(session: session, loader: load);
        expect(calls, 2);
      }
    },
  );

  test('clock rollback invalidates success and failure cooldown', () async {
    var calls = 0;
    Future<XboardSubscriptionData> load() async => _summary('${++calls}');
    await cache.load(session: session, loader: load);
    now = now.subtract(const Duration(seconds: 1));
    await cache.load(session: session, loader: load);
    expect(calls, 2);
    cache.clear();
    Future<XboardSubscriptionData> fail() async {
      calls++;
      throw StateError('failure');
    }

    await expectLater(
      cache.load(session: session, loader: fail),
      throwsStateError,
    );
    now = now.subtract(const Duration(seconds: 1));
    await expectLater(
      cache.load(session: session, loader: fail),
      throwsStateError,
    );
    expect(calls, 4);
  });

  test('logout invalidates in-flight publication and account reuse', () async {
    final pending = Completer<XboardSubscriptionData>();
    final first = cache.load(session: session, loader: () => pending.future);
    final rejected = expectLater(first, throwsStateError);
    cache.clear();
    pending.complete(_summary('old'));
    await rejected;
    final current = _summary('current');
    expect(
      await cache.load(session: session, loader: () async => current),
      same(current),
    );
  });

  test('verified login snapshot avoids an immediate duplicate fetch', () async {
    var calls = 0;
    final service = _Auth(() async {
      calls++;
      return _summary('network');
    });
    globalState.activateXboardSession(session, subscriptionFresh: true);
    expect(
      await globalState.loadXboardSubscriptionSnapshot(service, session),
      same(session.subscription),
    );
    expect(calls, 0);
    await globalState.loadXboardSubscriptionSnapshot(
      service,
      session,
      forceRefresh: true,
    );
    expect(calls, 1);
  });

  test('offline snapshot read cannot call the service', () async {
    globalState.activateXboardSession(session);
    globalState.setOfflineMode(true);
    var calls = 0;
    final service = _Auth(() async {
      calls++;
      return _summary('unexpected');
    });
    await expectLater(
      globalState.loadXboardSubscriptionSnapshot(service, session),
      throwsStateError,
    );
    expect(calls, 0);
  });
}

XboardLoginResult _session({
  String host = 'account.example',
  String auth = 'auth',
  String token = 'token',
  bool secure = false,
}) => XboardLoginResult(
  endpoint: Uri.https(host),
  authData: auth,
  token: token,
  isAdmin: false,
  secureSubscription: secure,
  subscription: _summary('login'),
);

XboardSubscriptionData _summary(String label, {int? expires, int? reset}) =>
    XboardSubscriptionData(
      endpoint: Uri.https('account.example'),
      subscribeUrl: Uri.https('account.example', '/subscription'),
      uploadBytes: 0,
      downloadBytes: 0,
      transferEnableBytes: 100,
      rawData: {'label': label},
      expiredAtEpochSeconds: expires,
      nextResetAtEpochSeconds: reset,
    );

class _Auth extends XboardAuthService {
  _Auth(this.loader);

  final Future<XboardSubscriptionData> Function() loader;

  @override
  Future<XboardSubscriptionData> fetchSubscription({
    required Uri endpoint,
    required String authData,
    String? userToken,
    bool secureSubscription = false,
  }) => loader();
}

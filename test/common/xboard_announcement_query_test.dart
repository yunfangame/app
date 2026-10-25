import 'dart:async';

import 'package:fl_clash/common/xboard_announcement_query.dart';
import 'package:fl_clash/common/xboard_auth.dart';
import 'package:fl_clash/common/xboard_api_request.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'pause between a loader error and cache handling stays deferred',
    () async {
      var available = true;
      final cache = XboardAnnouncementQueryCache();
      await expectLater(
        cache.load(
          session: _session(),
          canRequest: () => available,
          loader: () async {
            scheduleMicrotask(() => available = false);
            throw StateError('controlled foreground failure');
          },
        ),
        throwsA(isA<XboardApiRequestDeferred>()),
      );
      available = true;
      final replay = await cache.load(
        session: _session(),
        loader: () async => [_notice(2)],
      );
      expect(replay.single.id, 2);
    },
  );

  test(
    'cache admission is checked again before committing a complete response',
    () async {
      var available = true;
      final cache = XboardAnnouncementQueryCache();
      await expectLater(
        cache.load(
          session: _session(),
          canRequest: () => available,
          loader: () async {
            available = false;
            return [_notice(1)];
          },
        ),
        throwsA(isA<XboardApiRequestDeferred>()),
      );
      available = true;
      final replay = await cache.load(
        session: _session(),
        loader: () async => [_notice(2)],
      );
      expect(replay.single.id, 2);
    },
  );

  test(
    'deferred pagination preserves complete cache and permits immediate replay',
    () async {
      var now = DateTime.utc(2026, 10, 25);
      final cache = XboardAnnouncementQueryCache(now: () => now);
      await cache.load(session: _session(), loader: () async => [_notice(1)]);
      now = now.add(const Duration(minutes: 5));
      await expectLater(
        cache.load(
          session: _session(),
          loader: () async => throw const XboardApiRequestDeferred(),
        ),
        throwsA(isA<XboardApiRequestDeferred>()),
      );
      now = now.subtract(const Duration(minutes: 1));
      final cached = await cache.load(
        session: _session(),
        loader: () async => throw StateError('must keep complete cache'),
      );
      expect(cached.single.id, 1);
      now = now.add(const Duration(minutes: 1));
      final replay = await cache.load(
        session: _session(),
        loader: () async => [_notice(2)],
      );
      expect(replay.single.id, 2);
    },
  );

  test(
    'deferred manual attempt neither resets nor advances failure backoff',
    () async {
      var now = DateTime.utc(2026, 10, 25);
      final cache = XboardAnnouncementQueryCache(now: () => now);
      var calls = 0;
      Future<List<XboardNoticeData>> fail() async {
        calls++;
        throw StateError('controlled');
      }

      await expectLater(
        cache.load(session: _session(), loader: fail),
        throwsStateError,
      );
      await expectLater(
        cache.load(
          session: _session(),
          forceRefresh: true,
          loader: () async => throw const XboardApiRequestDeferred(),
        ),
        throwsA(isA<XboardApiRequestDeferred>()),
      );
      now = now.add(const Duration(seconds: 30));
      await expectLater(
        cache.load(session: _session(), loader: fail),
        throwsStateError,
      );
      expect(calls, 2);
      now = now.add(const Duration(seconds: 59));
      await expectLater(
        cache.load(session: _session(), loader: fail),
        throwsStateError,
      );
      expect(calls, 2);
      now = now.add(const Duration(seconds: 1));
      await expectLater(
        cache.load(session: _session(), loader: fail),
        throwsStateError,
      );
      expect(calls, 3);
    },
  );

  test(
    'positive and empty results have separate TTLs and stable auth keys',
    () async {
      var now = DateTime.utc(2026, 10, 25);
      final cache = XboardAnnouncementQueryCache(now: () => now);
      var calls = 0;
      var value = [_notice(1)];
      Future<List<XboardNoticeData>> load({String token = 'token'}) =>
          cache.load(
            session: _session(token: token),
            loader: () async {
              calls++;
              return value;
            },
          );
      await load();
      now = now.add(const Duration(minutes: 4, seconds: 59));
      await load(token: 'rotated');
      expect(calls, 1);
      now = now.add(const Duration(seconds: 1));
      value = [];
      await load();
      expect(calls, 2);
      now = now.add(const Duration(seconds: 59));
      await load();
      expect(calls, 2);
      now = now.add(const Duration(seconds: 1));
      await load();
      expect(calls, 3);
    },
  );

  test(
    'automatic requests coalesce and manual starts a newer request',
    () async {
      final cache = XboardAnnouncementQueryCache();
      final automatic = Completer<List<XboardNoticeData>>();
      final manual = Completer<List<XboardNoticeData>>();
      var calls = 0;
      Future<List<XboardNoticeData>> load(bool force) => cache.load(
        session: _session(),
        forceRefresh: force,
        loader: () => ++calls == 1 ? automatic.future : manual.future,
      );
      final first = load(false);
      expect(identical(first, load(false)), isTrue);
      final forced = load(true);
      expect(calls, 2);
      expect(identical(forced, load(true)), isTrue);
      automatic.complete([_notice(1)]);
      manual.complete([_notice(2)]);
      final values = await Future.wait([first, forced]);
      expect(values.map((value) => value.single.id), [2, 2]);
      expect((await load(false)).single.id, 2);
      expect(calls, 2);
    },
  );

  test(
    'late automatic success cannot replace a newer forced failure',
    () async {
      final cache = XboardAnnouncementQueryCache();
      final old = Completer<List<XboardNoticeData>>();
      final normal = cache.load(session: _session(), loader: () => old.future);
      final rejected = expectLater(normal, throwsStateError);
      await cache.load(
        session: _session(),
        forceRefresh: true,
        loader: () async => [_notice(2)],
      );
      await expectLater(
        cache.load(
          session: _session(),
          forceRefresh: true,
          loader: () async => throw StateError('newest_failure'),
        ),
        throwsStateError,
      );
      old.complete([_notice(1)]);
      await rejected;
    },
  );

  test(
    'automatic failures back off while manual bypasses and resets them',
    () async {
      var now = DateTime.utc(2026, 10, 25);
      final cache = XboardAnnouncementQueryCache(now: () => now);
      var calls = 0;
      var failing = true;
      Future<List<XboardNoticeData>> load({bool force = false}) => cache.load(
        session: _session(),
        forceRefresh: force,
        loader: () async {
          calls++;
          if (failing) throw StateError('controlled_outage');
          return [_notice(1)];
        },
      );
      await expectLater(load(), throwsStateError);
      for (final seconds in [30, 60, 120, 300, 300]) {
        final previous = calls;
        now = now.add(Duration(seconds: seconds - 1));
        await expectLater(load(), throwsStateError);
        expect(calls, previous);
        now = now.add(const Duration(seconds: 1));
        await expectLater(load(), throwsStateError);
        expect(calls, previous + 1);
      }
      failing = false;
      await load(force: true);
      expect(calls, 7);
      failing = true;
      now = now.add(const Duration(minutes: 5));
      await expectLater(load(), throwsStateError);
      now = now.add(const Duration(seconds: 30));
      await expectLater(load(), throwsStateError);
      expect(calls, 9);
    },
  );

  test(
    'different origin or authentication never shares cache values',
    () async {
      final cache = XboardAnnouncementQueryCache();
      for (final session in [
        _session(),
        _session(auth: 'other'),
        _session(origin: 'https://other.example'),
      ]) {
        final result = await cache.load(
          session: session,
          loader: () async => [_notice(3)],
        );
        expect(result.single.id, 3);
      }
      expect(
        XboardAnnouncementQueryCache.accountKey(_session()),
        isNot(XboardAnnouncementQueryCache.accountKey(_session(auth: 'other'))),
      );
    },
  );

  test(
    'clear isolates late requests even after returning to the same account',
    () async {
      final cache = XboardAnnouncementQueryCache();
      final pending = Completer<List<XboardNoticeData>>();
      final old = cache.load(session: _session(), loader: () => pending.future);
      final rejected = expectLater(old, throwsStateError);
      cache.clear();
      await cache.load(session: _session(), loader: () async => [_notice(2)]);
      pending.complete([_notice(1)]);
      await rejected;
      expect(
        (await cache.load(
          session: _session(),
          loader: () async => [_notice(99)],
        )).single.id,
        2,
      );
    },
  );

  test(
    'all fetched notices survive caching without truncation or list mutation',
    () async {
      final cache = XboardAnnouncementQueryCache();
      final notices = List.generate(250, _notice);
      final result = await cache.load(
        session: _session(),
        loader: () async => notices,
      );
      expect(result, hasLength(250));
      expect(() => result.clear(), throwsUnsupportedError);
      notices.clear();
      expect(result, hasLength(250));
    },
  );

  test(
    'clock rollback expires success and failure state rather than stalling',
    () async {
      var now = DateTime.utc(2026, 10, 25);
      final cache = XboardAnnouncementQueryCache(now: () => now);
      var calls = 0;
      Future<List<XboardNoticeData>> load() => cache.load(
        session: _session(),
        loader: () async {
          calls++;
          return [_notice(calls)];
        },
      );
      await load();
      now = now.subtract(const Duration(seconds: 1));
      expect((await load()).single.id, 2);
    },
  );
}

XboardNoticeData _notice(int id) => XboardNoticeData(
  id: id,
  title: 'Notice $id',
  content: '<p>$id</p>',
  tags: const ['弹窗'],
  createdAtEpochSeconds: null,
  updatedAtEpochSeconds: null,
  rawData: const {},
);

XboardLoginResult _session({
  String origin = 'https://api.example',
  String auth = 'Bearer account',
  String token = 'token',
}) {
  final endpoint = Uri.parse(origin);
  return XboardLoginResult(
    endpoint: endpoint,
    token: token,
    authData: auth,
    isAdmin: false,
    subscription: XboardSubscriptionData(
      endpoint: endpoint,
      subscribeUrl: null,
      uploadBytes: 0,
      downloadBytes: 0,
      transferEnableBytes: 100,
      rawData: const {},
    ),
  );
}

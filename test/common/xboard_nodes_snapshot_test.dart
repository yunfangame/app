import 'dart:async';

import 'package:fl_clash/common/xboard_auth.dart';
import 'package:fl_clash/common/xboard_nodes_snapshot.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'automatic readers share requests and success expires without sliding TTL',
    () async {
      var now = DateTime.utc(2026, 10, 25);
      final cache = XboardNodesSnapshotCache(now: () => now);
      final session = _session();
      final pending = Completer<List<XboardNodeData>>();
      var calls = 0;
      Future<List<XboardNodeData>> load() {
        calls++;
        return pending.future;
      }

      final first = cache.load(session: session, epoch: 1, loader: load);
      final second = cache.load(session: session, epoch: 1, loader: load);
      expect(identical(first, second), isTrue);
      pending.complete([_node('first')]);
      await first;
      now = now.add(const Duration(seconds: 29));
      expect(
        (await cache.load(
          session: session,
          epoch: 1,
          loader: load,
        )).single.name,
        'first',
      );
      expect(calls, 1);
      now = now.add(const Duration(seconds: 1));
      final nodes = await cache.load(
        session: session,
        epoch: 1,
        loader: () async {
          calls++;
          return [_node('second')];
        },
      );
      expect(nodes.single.name, 'second');
      expect(calls, 2);
    },
  );

  test(
    'successful empty lists are cached and manual bypasses a fresh result',
    () async {
      final cache = XboardNodesSnapshotCache();
      final session = _session();
      var calls = 0;
      Future<List<XboardNodeData>> load() async {
        calls++;
        return const [];
      }

      await cache.load(session: session, epoch: 1, loader: load);
      await cache.load(session: session, epoch: 1, loader: load);
      expect(calls, 1);
      await cache.load(
        session: session,
        epoch: 1,
        loader: load,
        forceRefresh: true,
      );
      expect(calls, 2);
    },
  );

  for (final lateFailure in [false, true]) {
    test(
      'manual request takes over automatic waiters before old transport ends ($lateFailure)',
      () async {
        final cache = XboardNodesSnapshotCache();
        final session = _session();
        final automatic = Completer<List<XboardNodeData>>();
        final manual = Completer<List<XboardNodeData>>();
        final old = cache.load(
          session: session,
          epoch: 1,
          loader: () => automatic.future,
        );
        final fresh = cache.load(
          session: session,
          epoch: 1,
          loader: () => manual.future,
          forceRefresh: true,
        );
        final joined = cache.load(
          session: session,
          epoch: 1,
          loader: () async => throw StateError('duplicate force'),
          forceRefresh: true,
        );
        expect(identical(joined, fresh), isTrue);
        manual.complete([_node('manual')]);
        expect((await fresh).single.name, 'manual');
        expect((await old).single.name, 'manual');
        if (lateFailure) {
          automatic.completeError(StateError('late outage'));
        } else {
          automatic.complete([_node('automatic')]);
        }
        await Future<void>.delayed(Duration.zero);
        final cached = await cache.load(
          session: session,
          epoch: 1,
          loader: () async => throw StateError('should reuse manual'),
        );
        expect(cached.single.name, 'manual');
      },
    );
  }

  test(
    'manual failure reaches superseded automatic waiters and old success cannot cache',
    () async {
      final cache = XboardNodesSnapshotCache();
      final session = _session();
      final automatic = Completer<List<XboardNodeData>>();
      final manual = Completer<List<XboardNodeData>>();
      final old = cache.load(
        session: session,
        epoch: 1,
        loader: () => automatic.future,
      );
      final fresh = cache.load(
        session: session,
        epoch: 1,
        loader: () => manual.future,
        forceRefresh: true,
      );
      final oldError = expectLater(old, throwsStateError);
      final freshError = expectLater(fresh, throwsStateError);
      manual.completeError(StateError('manual outage'));
      await Future.wait([oldError, freshError]);
      automatic.complete([_node('stale')]);
      await Future<void>.delayed(Duration.zero);
      final recovered = await cache.load(
        session: session,
        epoch: 1,
        loader: () async => [_node('recovered')],
      );
      expect(recovered.single.name, 'recovered');
    },
  );

  test(
    'clear invalidates waiting callers immediately and late results stay discarded',
    () async {
      final cache = XboardNodesSnapshotCache();
      final session = _session();
      final response = Completer<List<XboardNodeData>>();
      final old = cache.load(
        session: session,
        epoch: 1,
        loader: () => response.future,
      );
      final error = expectLater(old, throwsStateError);
      cache.clear();
      await error;
      final latest = await cache.load(
        session: session,
        epoch: 1,
        loader: () async => [_node('latest')],
      );
      response.complete([_node('old')]);
      await Future<void>.delayed(Duration.zero);
      expect(
        await cache.load(
          session: session,
          epoch: 1,
          loader: () async => const [],
        ),
        same(latest),
      );
    },
  );

  test(
    'new epochs isolate the same credentials and old epochs cannot evict new state',
    () async {
      final cache = XboardNodesSnapshotCache();
      final session = _session();
      final response = Completer<List<XboardNodeData>>();
      final old = cache.load(
        session: session,
        epoch: 1,
        loader: () => response.future,
      );
      final error = expectLater(old, throwsStateError);
      final latest = await cache.load(
        session: session,
        epoch: 2,
        loader: () async => [_node('new epoch')],
      );
      await error;
      await expectLater(
        cache.load(
          session: session,
          epoch: 1,
          loader: () async => [_node('old epoch')],
        ),
        throwsStateError,
      );
      response.complete([_node('late')]);
      await Future<void>.delayed(Duration.zero);
      expect(
        await cache.load(
          session: session,
          epoch: 2,
          loader: () async => const [],
        ),
        same(latest),
      );
    },
  );

  for (final session in [
    _session(endpoint: 'https://other.example/api/login'),
    _session(auth: 'other-auth'),
    _session(token: 'other-token'),
    _session(secure: true),
    _session(email: 'other@example.com'),
    _session(uuid: 'other-uuid'),
  ]) {
    test(
      'cache isolates trust and account identity ${XboardNodesSnapshotCache.accountKey(session)}',
      () async {
        final cache = XboardNodesSnapshotCache();
        final original = _session();
        await cache.load(
          session: original,
          epoch: 1,
          loader: () async => [_node('original')],
        );
        final isolated = await cache.load(
          session: session,
          epoch: 1,
          loader: () async => [_node('isolated')],
        );
        expect(isolated.single.name, 'isolated');
        expect(
          (await cache.load(
            session: original,
            epoch: 1,
            loader: () async => const [],
          )).single.name,
          'original',
        );
      },
    );
  }

  test(
    'remember is authoritative and safely completes earlier in-flight readers',
    () async {
      var now = DateTime.utc(2026, 10, 25);
      final cache = XboardNodesSnapshotCache(now: () => now);
      final session = _session();
      final response = Completer<List<XboardNodeData>>();
      final old = cache.load(
        session: session,
        epoch: 1,
        loader: () => response.future,
      );
      cache.remember(session, [_node('verified')], epoch: 1);
      expect((await old).single.name, 'verified');
      response.complete([_node('old')]);
      await Future<void>.delayed(Duration.zero);
      now = now.add(const Duration(seconds: 30));
      expect(
        (await cache.load(
          session: session,
          epoch: 1,
          loader: () async => [_node('new')],
        )).single.name,
        'new',
      );
    },
  );

  test('cached node fields are copied and deeply immutable', () async {
    final cache = XboardNodesSnapshotCache();
    final session = _session();
    final tags = ['HK'];
    final nested = <String, Object?>{
      'items': <Object?>['original'],
    };
    final raw = <String, Object?>{'nested': nested};
    final input = [_node('node', tags: tags, raw: raw)];
    final value = await cache.load(
      session: session,
      epoch: 1,
      loader: () async => input,
    );
    tags.add('US');
    (nested['items'] as List).clear();
    input.clear();
    expect(value.single.tags, ['HK']);
    expect(((value.single.rawData['nested'] as Map)['items'] as List), [
      'original',
    ]);
    expect(() => value.clear(), throwsUnsupportedError);
    expect(() => value.single.tags.clear(), throwsUnsupportedError);
    expect(() => value.single.rawData.clear(), throwsUnsupportedError);
    expect(
      () => ((value.single.rawData['nested'] as Map)['items'] as List).clear(),
      throwsUnsupportedError,
    );
  });

  test('clock rollback expires cached nodes', () async {
    var now = DateTime.utc(2026, 10, 25);
    final cache = XboardNodesSnapshotCache(now: () => now);
    final session = _session();
    await cache.load(
      session: session,
      epoch: 1,
      loader: () async => [_node('old')],
    );
    now = now.subtract(const Duration(seconds: 1));
    expect(
      (await cache.load(
        session: session,
        epoch: 1,
        loader: () async => [_node('new')],
      )).single.name,
      'new',
    );
  });
}

XboardLoginResult _session({
  String endpoint = 'https://api.example/api/login',
  String auth = 'auth',
  String token = 'token',
  bool secure = false,
  String email = 'account@example.com',
  String uuid = 'uuid',
}) {
  final uri = Uri.parse(endpoint);
  return XboardLoginResult(
    endpoint: uri,
    token: token,
    authData: auth,
    secureSubscription: secure,
    isAdmin: false,
    subscription: XboardSubscriptionData(
      endpoint: uri,
      subscribeUrl: uri.resolve('/subscription'),
      uploadBytes: 0,
      downloadBytes: 0,
      transferEnableBytes: 1,
      email: email,
      uuid: uuid,
      rawData: const {},
    ),
  );
}

XboardNodeData _node(
  String name, {
  List<String> tags = const [],
  Map<String, Object?> raw = const {},
}) => XboardNodeData(
  name: name,
  type: 'ss',
  rate: 1,
  tags: tags,
  isOnline: true,
  rawData: raw,
);

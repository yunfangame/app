import 'dart:async';

import 'package:fl_clash/common/xboard_auth.dart';
import 'package:fl_clash/common/xboard_catalog_cache.dart';
import 'package:fl_clash/state.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/api_health_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late XboardLoginResult session;
  late XboardCatalogCache<int> cache;
  late DateTime now;

  setUp(() {
    globalState.setOfflineMode(false);
    session = _session();
    globalState.activateXboardSession(session);
    now = DateTime(2026, 10, 25);
    cache = XboardCatalogCache(now: () => now);
  });

  tearDown(() {
    globalState.clearXboardSession();
    globalState.setOfflineMode(false);
  });

  test(
    'catalog coalesces normal and forced reads and expires at 60 seconds',
    () async {
      final pending = Completer<int>();
      var calls = 0;
      Future<int> load() {
        calls++;
        return pending.future;
      }

      final first = cache.load(session, load);
      final second = cache.load(session, load);
      expect(first, same(second));
      pending.complete(1);
      expect(await first, 1);
      now = now.add(const Duration(seconds: 59));
      expect(await cache.load(session, () async => ++calls), 1);
      expect(calls, 1);
      now = now.add(const Duration(seconds: 1));
      expect(await cache.load(session, () async => ++calls), 2);
      final forced = Completer<int>();
      final manual = cache.load(
        session,
        () => forced.future,
        forceRefresh: true,
      );
      expect(
        cache.load(session, () async => 9, forceRefresh: true),
        same(manual),
      );
      expect(cache.load(session, () async => 9), same(manual));
      forced.complete(3);
      expect(await manual, 3);
    },
  );

  for (final oldFails in [false, true]) {
    test(
      'old automatic response adopts newer manual result ($oldFails)',
      () async {
        final pending = Completer<int>();
        final automatic = cache.load(session, () => pending.future);
        expect(await cache.load(session, () async => 2, forceRefresh: true), 2);
        if (oldFails) {
          pending.completeError(StateError('old response failed'));
        } else {
          pending.complete(1);
        }
        expect(await automatic, 2);
        expect(await cache.load(session, () async => 3), 2);
      },
    );
  }

  test('failed force cannot be replaced by late automatic success', () async {
    final pending = Completer<int>();
    final automatic = cache.load(session, () => pending.future);
    final automaticError = expectLater(automatic, throwsStateError);
    await expectLater(
      cache.load(
        session,
        () async => throw StateError('manual failed'),
        forceRefresh: true,
      ),
      throwsStateError,
    );
    pending.complete(1);
    await automaticError;
    expect(cache.peek(session), isNull);
    expect(await cache.load(session, () async => 3), 3);
  });

  test(
    'metadata and subscription token updates preserve the same account cache',
    () async {
      expect(await cache.load(session, () async => 1), 1);
      globalState.activateXboardSession(
        _session(token: 'updated-subscription-token'),
      );
      expect(await cache.load(globalState.xboardSession!, () async => 2), 1);
    },
  );

  for (final boundary in [
    'logout',
    'account',
    'origin',
    'offline',
    'invalidate',
  ]) {
    test('$boundary isolates pending catalog responses', () async {
      final pending = Completer<int>();
      final old = cache.load(session, () => pending.future);
      final oldError = expectLater(old, throwsStateError);
      switch (boundary) {
        case 'logout':
          globalState.clearXboardSession();
          globalState.activateXboardSession(session);
        case 'account':
          session = _session(auth: 'other-account');
          globalState.activateXboardSession(session);
        case 'origin':
          session = _session(origin: 'https://other.example.com');
          globalState.activateXboardSession(session);
        case 'offline':
          globalState.setOfflineMode(true);
          globalState.setOfflineMode(false);
        case 'invalidate':
          cache.invalidate(session);
      }
      expect(await cache.load(session, () async => 2), 2);
      pending.complete(1);
      await oldError;
      expect(cache.peek(session), 2);
    });
  }

  test('clock rollback does not reuse a future-dated cached value', () async {
    expect(await cache.load(session, () async => 1), 1);
    now = now.subtract(const Duration(seconds: 1));
    expect(await cache.load(session, () async => 2), 2);
  });

  for (final containsId in [false, true]) {
    test(
      'automatic ID joins the full catalog and only falls back for a missing ID ($containsId)',
      () async {
        final pending = Completer<XboardLoginResponse>();
        final entered = Completer<void>();
        final calls = <String>[];
        final service = XboardAuthService(
          apiHealthService: ApiHealthFixture(session.endpoint),
          plansRequester: (endpoint, _) async {
            final id = endpoint.queryParameters['id'];
            calls.add(id ?? 'all');
            if (id != null) return _plans(int.parse(id));
            entered.complete();
            return pending.future;
          },
        );
        final all = loadXboardPlanCatalog(
          authService: service,
          session: session,
        );
        await entered.future;
        final target = containsId ? 1 : 2;
        final selected = loadXboardPlanCatalog(
          authService: service,
          session: session,
          planId: target,
        );
        await Future<void>.delayed(Duration.zero);
        expect(calls, ['all']);
        pending.complete(_plans(1));
        await all;
        expect((await selected).single.id, target);
        expect(calls, containsId ? ['all'] : ['all', '2']);
      },
    );
  }

  test('forced ID lookup bypasses an older full-catalog request', () async {
    final pending = Completer<XboardLoginResponse>();
    final entered = Completer<void>();
    final calls = <String>[];
    final service = XboardAuthService(
      apiHealthService: ApiHealthFixture(session.endpoint),
      plansRequester: (endpoint, _) async {
        final id = endpoint.queryParameters['id'];
        calls.add(id ?? 'all');
        if (id != null) return _plans(int.parse(id));
        entered.complete();
        return pending.future;
      },
    );
    final all = loadXboardPlanCatalog(authService: service, session: session);
    await entered.future;
    final selected = await loadXboardPlanCatalog(
      authService: service,
      session: session,
      planId: 1,
      forceRefresh: true,
    );
    expect(selected.single.id, 1);
    expect(calls, ['all', '1']);
    pending.complete(_plans(1));
    await all;
  });

  test(
    'an ID waiting for the full catalog cannot fall back after logout and same-account login',
    () async {
      final pending = Completer<XboardLoginResponse>();
      final entered = Completer<void>();
      final calls = <String>[];
      final service = XboardAuthService(
        apiHealthService: ApiHealthFixture(session.endpoint),
        plansRequester: (endpoint, _) async {
          calls.add(endpoint.queryParameters['id'] ?? 'all');
          entered.complete();
          return pending.future;
        },
      );
      final all = loadXboardPlanCatalog(authService: service, session: session);
      await entered.future;
      final selected = loadXboardPlanCatalog(
        authService: service,
        session: session,
        planId: 2,
      );
      final allError = expectLater(all, throwsStateError);
      final selectedError = expectLater(selected, throwsStateError);
      globalState.clearXboardSession();
      globalState.activateXboardSession(session);
      pending.complete(_plans(1));
      await Future.wait([allError, selectedError]);
      expect(calls, ['all']);
    },
  );
}

XboardLoginResponse _plans(int id) => XboardLoginResponse(
  statusCode: 200,
  data: {
    'data': [
      {
        'id': id,
        'name': 'Plan $id',
        'month_price': 1000,
        'sell': 1,
        'renew': 1,
      },
    ],
  },
);

XboardLoginResult _session({
  String origin = 'https://api.example.com',
  String auth = 'catalog-auth',
  String token = 'subscription-token',
}) {
  final endpoint = Uri.parse(origin);
  return XboardLoginResult(
    endpoint: endpoint,
    token: token,
    authData: auth,
    isAdmin: false,
    subscription: XboardSubscriptionData(
      endpoint: endpoint,
      subscribeUrl: endpoint.resolve('/subscribe'),
      uploadBytes: 0,
      downloadBytes: 0,
      transferEnableBytes: 0,
      rawData: const {},
    ),
  );
}

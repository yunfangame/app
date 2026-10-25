import 'dart:async';

import 'package:fl_clash/common/api_health.dart';
import 'package:fl_clash/common/api_health_snapshot_cache.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'automatic probes reuse results, manual checks and single tests stay fresh',
    () async {
      var now = DateTime(2026);
      var probes = 0;
      var loads = 0;
      final service = ApiHealthService(
        configUrl: 'https://config.example.com/app.json',
        configLoader: (_) async {
          loads++;
          return _config;
        },
        endpointProbe: (_) async {
          probes++;
          return true;
        },
        now: () => now,
      );
      await service.check(forceRefresh: false);
      now = now.add(const Duration(seconds: 29));
      await service.check(forceRefresh: false);
      expect(probes, 1);
      now = now.add(const Duration(seconds: 1));
      await service.check(forceRefresh: false);
      expect(probes, 2);
      expect(loads, 1);
      await service.check();
      await service.probeEndpoint(Uri.parse('https://api.example.com'));
      expect(probes, 4);
      expect(loads, 2);
    },
  );

  test('failure cooldown grows and manual bypasses it', () async {
    var now = DateTime(2026);
    var probes = 0;
    final service = ApiHealthService(
      configLoader: (_) async => _config,
      endpointProbe: (_) async {
        probes++;
        return false;
      },
      now: () => now,
    );
    for (final seconds in [30, 60, 120, 300]) {
      await service.check(forceRefresh: false);
      final before = probes;
      now = now.add(Duration(seconds: seconds - 1));
      await service.check(forceRefresh: false);
      expect(probes, before);
      now = now.add(const Duration(seconds: 1));
    }
    await service.check();
    expect(probes, 5);
  });

  test(
    'background, offline and no network pause automatic probes only',
    () async {
      final activity = ApiRemoteConfigActivity()..setAppForeground(false);
      var probes = 0;
      final service = ApiHealthService(
        activity: activity,
        configLoader: (_) async => _config,
        endpointProbe: (_) async {
          probes++;
          return true;
        },
      );
      expect((await service.check(forceRefresh: false)).isDeferred, isTrue);
      activity.setAppForeground(true);
      activity.setOffline(true);
      expect((await service.check(forceRefresh: false)).isDeferred, isTrue);
      activity.setOffline(false);
      activity.networkChanged(available: false);
      expect((await service.check(forceRefresh: false)).isDeferred, isTrue);
      expect(probes, 0);
      await service.check();
      expect(probes, 1);
      activity.networkChanged();
      await service.check(forceRefresh: false);
      expect(probes, 2);
    },
  );

  test(
    'automatic check rechecks activity after configuration completes',
    () async {
      final activity = ApiRemoteConfigActivity();
      final config = Completer<Object?>();
      var probes = 0;
      final service = ApiHealthService(
        activity: activity,
        configLoader: (_) => config.future,
        endpointProbe: (_) async {
          probes++;
          return true;
        },
      );
      final pending = service.check(forceRefresh: false);
      activity.setWindowForeground(false);
      config.complete(_config);
      expect((await pending).isDeferred, isTrue);
      expect(probes, 0);
      activity.setWindowForeground(true);
      await service.check(forceRefresh: false);
      expect(probes, 1);
    },
  );

  test(
    'manual supersedes normal and all old waiters observe latest manual',
    () async {
      final cache = ApiHealthSnapshotCache();
      final old = Completer<ApiHealthSnapshot>();
      final fresh = Completer<ApiHealthSnapshot>();
      final normal = cache.load(
        scope: 'a',
        loader: () => old.future,
        forceRefresh: false,
      );
      final joined = cache.load(
        scope: 'a',
        loader: () async => throw StateError('duplicate'),
        forceRefresh: false,
      );
      expect(identical(normal, joined), isTrue);
      final forced = cache.load(
        scope: 'a',
        loader: () => fresh.future,
        forceRefresh: true,
      );
      final latest = _snapshot(true);
      fresh.complete(latest);
      expect(await forced, same(latest));
      expect(await normal, same(latest));
      old.complete(_snapshot(false));
      expect(await joined, same(latest));
      expect(cache.peek('a'), same(latest));
    },
  );

  test('scopes isolate results and rollback expires automatic cache', () async {
    var now = DateTime(2026);
    final cache = ApiHealthSnapshotCache(now: () => now);
    var loads = 0;
    Future<ApiHealthSnapshot> load(String scope) => cache.load(
      scope: scope,
      forceRefresh: false,
      loader: () async {
        loads++;
        return _snapshot(true);
      },
    );
    await load('a');
    await load('a');
    await load('b');
    expect(loads, 2);
    now = now.subtract(const Duration(seconds: 1));
    await load('a');
    expect(loads, 3);
  });

  test(
    'trust domains and network changes cannot share stale results',
    () async {
      final cache = ApiHealthSnapshotCache();
      final activity = ApiRemoteConfigActivity();
      var probes = 0;
      ApiHealthService service(String url) => ApiHealthService(
        configUrl: url,
        activity: activity,
        healthCache: cache,
        configLoader: (_) async => _config,
        endpointProbe: (_) async {
          probes++;
          return true;
        },
      );
      final first = service('https://one.example.com/config');
      await first.check(forceRefresh: false);
      await service(
        'https://one.example.com/config',
      ).check(forceRefresh: false);
      expect(probes, 1);
      await service(
        'https://two.example.com/config',
      ).check(forceRefresh: false);
      expect(probes, 2);
      activity.networkChanged();
      await first.check(forceRefresh: false);
      expect(probes, 3);
    },
  );
}

const _config = {
  'Authentication': 'FengWo',
  'hosts': ['https://api.example.com'],
};

ApiHealthSnapshot _snapshot(bool reachable) => ApiHealthSnapshot(
  endpoints: [
    ApiEndpointHealth(
      endpoint: Uri.parse('https://api.example.com'),
      reachable: reachable,
      latency: Duration.zero,
    ),
  ],
  checkedAt: DateTime(2026),
);

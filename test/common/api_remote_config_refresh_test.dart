import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:fl_clash/common/api_health.dart';
import 'package:fl_clash/common/api_remote_config_cache.dart';
import 'package:fl_clash/common/remote_config_cipher.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'default services share one request and fresh verified config',
    () async {
      final response = Completer<void>();
      final requested = Completer<void>();
      var requests = 0;
      final server = await _server((request) async {
        requests++;
        if (!requested.isCompleted) requested.complete();
        await response.future;
        await _respond(request, _config('shared.example.com'));
      });
      final url = _url(server);
      final first = ApiHealthService(configUrl: url);
      final second = ApiHealthService(configUrl: url);
      final results = Future.wait([
        first.loadConfig(),
        second.loadConfig(),
        second.loadVerifiedCandidateEndpoints(),
      ]);
      await requested.future;
      response.complete();
      await results;

      expect(requests, 1);
      final next = await ApiHealthService(configUrl: url).loadConfig();
      expect(parseApiEndpoints(next).single.host, 'shared.example.com');
      expect(requests, 1);
    },
  );

  test('TTL boundary fetches updated config and candidates share it', () async {
    final clock = _Clock();
    final pool = ApiRemoteConfigMemoryCache();
    var requests = 0;
    Future<Object?> loader(Uri _) async =>
        _config(++requests == 1 ? 'old.example.com' : 'new.example.com');
    ApiHealthService service() => ApiHealthService(
      configUrl: 'https://ttl.example/config',
      configLoader: loader,
      memoryCache: pool,
      now: clock.now,
    );

    await service().loadConfig();
    clock.advance(const Duration(minutes: 5) - const Duration(milliseconds: 1));
    expect(
      parseApiEndpoints(await service().loadConfig()).single.host,
      'old.example.com',
    );
    expect(requests, 1);
    clock.advance(const Duration(milliseconds: 1));
    expect(
      parseApiEndpoints(await service().loadConfig()).single.host,
      'new.example.com',
    );
    expect(
      (await service().loadVerifiedCandidateEndpoints()).single.host,
      'new.example.com',
    );
    expect(requests, 2);
  });

  test('clock rollback never keeps a remote result fresh', () async {
    final clock = _Clock();
    var requests = 0;
    final service = ApiHealthService(
      configUrl: 'https://rollback.example/config',
      configLoader: (_) async {
        requests++;
        return _config('api.example.com');
      },
      now: clock.now,
    );
    await service.loadConfig();
    clock.advance(const Duration(seconds: -1));
    await service.loadConfig();
    expect(requests, 2);
  });

  test(
    'loader and caller mutations cannot change shared verified data',
    () async {
      final payload = _config('verified.example.com')
        ..['nested'] = {
          'values': ['original'],
        };
      var requests = 0;
      final service = ApiHealthService(
        configUrl: 'https://mutation.example/config',
        configLoader: (_) async {
          requests++;
          return payload;
        },
      );
      final first = await service.loadConfig() as Map;
      (first['hosts'] as List).clear();
      ((first['nested'] as Map)['values'] as List)[0] = 'caller-changed';
      (payload['hosts'] as List)[0] = 'https://loader-changed.example.com';
      ((payload['nested'] as Map)['values'] as List)[0] = 'loader-changed';

      final next = await service.loadConfig() as Map;
      expect(parseApiEndpoints(next).single.host, 'verified.example.com');
      expect((next['nested'] as Map)['values'], ['original']);
      expect(requests, 1);
    },
  );

  test(
    'forced requests coalesce and supersede late normal responses',
    () async {
      final ordinary = Completer<Object?>();
      final forced = Completer<Object?>();
      final store = _Store();
      final requests = <Uri>[];
      final service = ApiHealthService(
        configUrl: 'https://force.example/config?source=primary',
        configCacheStore: store,
        configLoader: (uri) {
          requests.add(uri);
          return uri.queryParameters.containsKey('_fengwo_refresh')
              ? forced.future
              : ordinary.future;
        },
      );
      final normal = service.loadConfig();
      await _until(() => requests.length == 1);
      final firstForce = service.loadConfig(forceRefresh: true);
      final secondForce = service.loadConfig(forceRefresh: true);
      await _until(() => requests.length == 2);
      forced.complete(_config('forced.example.com'));
      await Future.wait([firstForce, secondForce]);
      ordinary.complete(_config('late.example.com'));
      expect(parseApiEndpoints(await normal).single.host, 'forced.example.com');

      expect(requests, hasLength(2));
      expect(requests.last.queryParameters['source'], 'primary');
      expect(requests.last.queryParameters['_fengwo_refresh'], isNotEmpty);
      expect(
        parseApiEndpoints(await service.loadConfig()).single.host,
        'forced.example.com',
      );
      expect(
        parseApiEndpoints(store.payload).single.host,
        'forced.example.com',
      );
      expect(store.writes, 1);
    },
  );

  test('late normal failure cannot cool down a forced success', () async {
    final clock = _Clock();
    final ordinary = Completer<Object?>();
    var requests = 0;
    final service = ApiHealthService(
      configUrl: 'https://late-failure.example/config',
      configRetryDelays: const [Duration.zero],
      now: clock.now,
      configLoader: (uri) {
        requests++;
        if (requests == 1) return ordinary.future;
        return Future.value(_config('current.example.com'));
      },
    );
    final pending = service.loadConfig();
    final failed = expectLater(
      pending,
      throwsA(isA<ApiRemoteConfigException>()),
    );
    await service.loadConfig(forceRefresh: true);
    ordinary.completeError(StateError('late outage'));
    await failed;
    clock.advance(const Duration(minutes: 5));
    await service.loadConfig();
    expect(requests, 3);
  });

  test(
    'strict candidate loads cannot accept a cached empty host list',
    () async {
      var requests = 0;
      final service = ApiHealthService(
        configUrl: 'https://strict.example/config',
        configLoader: (_) async => ++requests == 1
            ? {'Authentication': 'FengWo', 'hosts': <String>[]}
            : _config('strict.example.com'),
      );
      final loose = service.loadConfig();
      final strict = service.loadVerifiedCandidateEndpoints();

      expect(parseApiEndpoints(await loose), isEmpty);
      expect((await strict).single.host, 'strict.example.com');
      expect(requests, 2);
    },
  );

  test(
    'a newer update-only force cannot empty an older strict request',
    () async {
      final strict = Completer<Object?>();
      var requests = 0;
      final service = ApiHealthService(
        configUrl: 'https://strict-force.example/config',
        configLoader: (uri) {
          requests++;
          return uri.queryParameters.containsKey('_fengwo_refresh')
              ? Future.value({'Authentication': 'FengWo', 'hosts': <String>[]})
              : strict.future;
        },
      );
      final candidates = service.loadVerifiedCandidateEndpoints();
      await _until(() => requests == 1);
      expect(
        parseApiEndpoints(await service.loadConfig(forceRefresh: true)),
        isEmpty,
      );
      strict.complete(_config('strict.example.com'));
      expect((await candidates).single.host, 'strict.example.com');
      expect(requests, 2);
    },
  );

  test(
    'diagnostic checks refresh while optional normal checks reuse TTL',
    () async {
      var requests = 0;
      var probes = 0;
      final service = ApiHealthService(
        configUrl: 'https://check.example/config',
        configLoader: (_) async {
          requests++;
          return _config('api.example.com');
        },
        endpointProbe: (_) async {
          probes++;
          return true;
        },
      );
      await service.loadConfig();
      await service.check();
      await service.check();
      await service.check(forceRefresh: false);
      expect(requests, 3);
      expect(probes, 2);
    },
  );

  test(
    'failures back off up to five minutes without inventing config',
    () async {
      final clock = _Clock();
      var requests = 0;
      final service = ApiHealthService(
        configUrl: 'https://outage.example/config',
        configRetryDelays: const [Duration.zero],
        now: clock.now,
        configLoader: (_) async {
          requests++;
          throw StateError('offline');
        },
      );
      Future<void> fails() => expectLater(
        service.loadConfig(),
        throwsA(isA<ApiRemoteConfigException>()),
      );
      await fails();
      var expected = 1;
      for (final seconds in [30, 60, 120, 240, 300, 300]) {
        clock.advance(
          Duration(seconds: seconds) - const Duration(milliseconds: 1),
        );
        await fails();
        expect(requests, expected);
        clock.advance(const Duration(milliseconds: 1));
        await fails();
        expect(requests, ++expected);
      }
    },
  );

  test('force bypasses failure cooldown and success resets backoff', () async {
    final clock = _Clock();
    var available = false;
    var requests = 0;
    final service = ApiHealthService(
      configUrl: 'https://recover.example/config',
      configRetryDelays: const [Duration.zero],
      now: clock.now,
      configLoader: (_) async {
        requests++;
        if (!available) throw StateError('offline');
        return _config('recovered.example.com');
      },
    );
    await expectLater(
      service.loadConfig(),
      throwsA(isA<ApiRemoteConfigException>()),
    );
    available = true;
    await service.loadConfig(forceRefresh: true);
    expect(requests, 2);
    clock.advance(const Duration(minutes: 5));
    available = false;
    await expectLater(
      service.loadConfig(),
      throwsA(isA<ApiRemoteConfigException>()),
    );
    clock.advance(const Duration(seconds: 30));
    available = true;
    await service.loadConfig();
    expect(requests, 4);
  });

  test(
    'verified stale candidates survive backoff and recover on expiry',
    () async {
      final clock = _Clock();
      var available = true;
      var requests = 0;
      final service = ApiHealthService(
        configUrl: 'https://stale.example/config',
        configRetryDelays: const [Duration.zero],
        now: clock.now,
        configLoader: (_) async {
          requests++;
          if (!available) throw StateError('offline');
          return _config(requests == 1 ? 'old.example.com' : 'new.example.com');
        },
      );
      await service.loadConfig();
      clock.advance(const Duration(minutes: 5));
      available = false;
      expect(
        (await service.loadVerifiedCandidateEndpoints()).single.host,
        'old.example.com',
      );
      await _until(() => requests == 2);
      await Future<void>.delayed(Duration.zero);
      await service.loadVerifiedCandidateEndpoints();
      expect(requests, 2);
      clock.advance(const Duration(seconds: 30));
      available = true;
      await service.loadVerifiedCandidateEndpoints();
      expect(
        parseApiEndpoints(await service.loadConfig()).single.host,
        'new.example.com',
      );
      expect(requests, 3);
    },
  );

  test(
    'custom loaders are isolated unless a memory pool is supplied',
    () async {
      var requests = 0;
      ApiHealthService service(String host) => ApiHealthService(
        configUrl: 'https://isolated.example/config',
        configLoader: (_) async {
          requests++;
          return _config(host);
        },
      );
      await service('first.example.com').loadConfig();
      expect(
        (await service(
          'second.example.com',
        ).loadVerifiedCandidateEndpoints()).single.host,
        'second.example.com',
      );
      expect(requests, 2);
    },
  );

  test(
    'injected stores and clocks isolate otherwise default HTTP clients',
    () async {
      var requests = 0;
      final server = await _server((request) async {
        requests++;
        await _respond(request, _config('api-$requests.example.com'));
      });
      final url = _url(server);
      await ApiHealthService(
        configUrl: url,
        configCacheStore: _Store(),
      ).loadConfig();
      await ApiHealthService(
        configUrl: url,
        configCacheStore: _Store(),
      ).loadConfig();
      final clock = _Clock();
      await ApiHealthService(configUrl: url, now: clock.now).loadConfig();
      await ApiHealthService(configUrl: url, now: clock.now).loadConfig();
      expect(requests, 4);
    },
  );

  test(
    'source domains isolate memory and persistent verified caches',
    () async {
      final pool = ApiRemoteConfigMemoryCache();
      var requests = 0;
      ApiHealthService service(String source, String host) => ApiHealthService(
        configUrl: 'https://$source.example/config',
        memoryCache: pool,
        configLoader: (_) async {
          requests++;
          return _config(host);
        },
      );
      await service('first', 'first.example.com').loadConfig();
      final second = await service(
        'second',
        'second.example.com',
      ).loadVerifiedCandidateEndpoints();
      expect(second.single.host, 'second.example.com');
      expect(requests, 2);
    },
  );

  test(
    'AES and signing identities isolate shared memory and reject invalid signatures',
    () async {
      final fixture = await _encryptedConfig();
      final pool = ApiRemoteConfigMemoryCache();
      var requests = 0;
      ApiHealthService service({
        String? aesKey,
        String? signingKey,
        Object? payload,
      }) => ApiHealthService(
        configUrl: 'https://signed.example/config',
        configRetryDelays: const [Duration.zero],
        memoryCache: pool,
        aesKey: aesKey ?? fixture.aesKey,
        signingPublicKey: signingKey ?? fixture.signingKey,
        configLoader: (_) async {
          requests++;
          return payload ?? fixture.payload;
        },
      );
      await service().loadConfig();
      await expectLater(
        service(
          aesKey: encodeRemoteConfigBase64(List.filled(32, 0)),
        ).loadConfig(),
        throwsA(isA<ApiRemoteConfigException>()),
      );
      await expectLater(
        service(
          signingKey: encodeRemoteConfigBase64(List.filled(32, 1)),
        ).loadConfig(),
        throwsA(isA<ApiRemoteConfigException>()),
      );
      final forged = Map<String, Object?>.from(fixture.payload)
        ..['signature'] = encodeRemoteConfigBase64(List.filled(64, 0));
      await expectLater(
        service(payload: forged).loadConfig(forceRefresh: true),
        throwsA(isA<ApiRemoteConfigException>()),
      );
      expect(requests, 4);
      expect(
        parseApiEndpoints(await service().loadConfig()).single.host,
        'signed.example.com',
      );
      expect(requests, 4);
    },
  );

  test('late persistent writes finish before a newer forced write', () async {
    final gate = Completer<void>();
    final store = _Store(firstWriteGate: gate.future);
    var requests = 0;
    final service = ApiHealthService(
      configUrl: 'https://persist.example/config',
      configCacheStore: store,
      configLoader: (_) async =>
          _config(++requests == 1 ? 'old.example.com' : 'new.example.com'),
    );
    final first = service.loadConfig();
    await store.writeStarted.future;
    final forced = service.loadConfig(forceRefresh: true);
    await _until(() => requests == 2);
    await Future<void>.delayed(Duration.zero);
    expect(store.writes, 1);
    gate.complete();
    await Future.wait([first, forced]);
    expect(store.writes, 2);
    expect(parseApiEndpoints(store.payload).single.host, 'new.example.com');
  });

  test('a late invalid disk read cannot clear a forced result', () async {
    final read = Completer<Object?>();
    final store = _Store(readResponse: read.future);
    final service = ApiHealthService(
      configUrl: 'https://late-read.example/config',
      configCacheStore: store,
      configLoader: (_) async => _config('new.example.com'),
    );
    final candidates = service.loadVerifiedCandidateEndpoints();
    await store.readStarted.future;
    await service.loadConfig(forceRefresh: true);
    read.complete({
      'Authentication': 'Wrong',
      'hosts': ['https://untrusted.example'],
    });
    expect((await candidates).single.host, 'new.example.com');
    expect(store.clears, 0);
    expect(parseApiEndpoints(store.payload).single.host, 'new.example.com');
  });

  test('a late valid disk read returns the newer forced result', () async {
    final read = Completer<Object?>();
    final store = _Store(readResponse: read.future);
    final service = ApiHealthService(
      configUrl: 'https://late-valid-read.example/config',
      configCacheStore: store,
      configLoader: (_) async => _config('new.example.com'),
    );
    final candidates = service.loadVerifiedCandidateEndpoints();
    await store.readStarted.future;
    await service.loadConfig(forceRefresh: true);
    read.complete(_config('old.example.com'));
    expect((await candidates).single.host, 'new.example.com');
    expect(parseApiEndpoints(store.payload).single.host, 'new.example.com');
    expect(store.writes, 1);
  });

  test('a late emergency config cannot overwrite remote success', () async {
    final remote = Completer<Object?>();
    final emergency = Completer<Object?>();
    final emergencyStarted = Completer<void>();
    final store = _Store();
    final service = ApiHealthService(
      configUrl: 'https://late-emergency.example/config',
      configCacheStore: store,
      configLoader: (_) => remote.future,
      emergencyConfigLoader: () {
        emergencyStarted.complete();
        return emergency.future;
      },
      initialRemoteWait: Duration.zero,
    );
    final candidates = service.loadVerifiedCandidateEndpoints();
    await emergencyStarted.future;
    remote.complete(_config('remote.example.com'));
    await service.loadConfig();
    emergency.complete(_config('emergency.example.com'));
    expect((await candidates).single.host, 'remote.example.com');
    expect(parseApiEndpoints(store.payload).single.host, 'remote.example.com');
    expect(store.writes, 1);
  });

  test('background flags defer and coalesce automatic refreshes', () async {
    final activity = ApiRemoteConfigActivity();
    final clock = _Clock();
    var requests = 0;
    final service = ApiHealthService(
      configUrl: 'https://activity.example/config',
      activity: activity,
      now: clock.now,
      configLoader: (_) async =>
          _config(++requests == 1 ? 'old.example.com' : 'new.example.com'),
    );
    await service.loadConfig();
    clock.advance(const Duration(minutes: 5));
    activity.setAppForeground(false);
    activity.setWindowForeground(false);
    expect(
      parseApiEndpoints(await service.loadConfig()).single.host,
      'old.example.com',
    );
    expect(
      (await service.loadVerifiedCandidateEndpoints()).single.host,
      'old.example.com',
    );
    await service.loadConfig();
    expect(requests, 1);
    activity.setAppForeground(true);
    await Future<void>.delayed(Duration.zero);
    expect(requests, 1);
    activity.setWindowForeground(true);
    expect(
      parseApiEndpoints(await service.loadConfig()).single.host,
      'new.example.com',
    );
    activity.setWindowForeground(true);
    await Future<void>.delayed(Duration.zero);
    expect(requests, 2);
  });

  test('background force refresh bypasses pending automatic refresh', () async {
    final activity = ApiRemoteConfigActivity();
    final clock = _Clock();
    var requests = 0;
    final service = ApiHealthService(
      configUrl: 'https://background-force.example/config',
      activity: activity,
      now: clock.now,
      configLoader: (_) async => _config('api-${++requests}.example.com'),
    );
    await service.loadConfig();
    clock.advance(const Duration(minutes: 5));
    activity.setAppForeground(false);
    await service.loadConfig();
    expect(requests, 1);
    expect(
      parseApiEndpoints(
        await service.loadConfig(forceRefresh: true),
      ).single.host,
      'api-2.example.com',
    );
    activity.setAppForeground(true);
    await Future<void>.delayed(Duration.zero);
    expect(requests, 2);
  });

  test('resuming automatic refresh preserves failure cooldown', () async {
    final activity = ApiRemoteConfigActivity();
    final clock = _Clock();
    var requests = 0;
    final service = ApiHealthService(
      configUrl: 'https://resume-backoff.example/config',
      configRetryDelays: const [Duration.zero],
      activity: activity,
      now: clock.now,
      configLoader: (_) async {
        requests++;
        if (requests == 2) throw const SocketException('controlled outage');
        return _config('api.example.com');
      },
    );
    await service.loadConfig();
    clock.advance(const Duration(minutes: 5));
    await expectLater(
      service.loadConfig(),
      throwsA(isA<ApiRemoteConfigException>()),
    );
    activity.setWindowForeground(false);
    await service.loadConfig();
    activity.setWindowForeground(true);
    await Future<void>.delayed(Duration.zero);
    expect(requests, 2);
    clock.advance(const Duration(seconds: 30));
    await service.loadConfig();
    expect(requests, 3);
  });

  test('deferred update-only config remains valid without hosts', () async {
    final activity = ApiRemoteConfigActivity();
    final clock = _Clock();
    var requests = 0;
    final service = ApiHealthService(
      configUrl: 'https://update-only.example/config',
      activity: activity,
      now: clock.now,
      configLoader: (_) async => {
        'Authentication': 'FengWo',
        'UpdateUrl': 'https://update-${++requests}.example/version.json',
      },
    );
    await service.loadConfig();
    clock.advance(const Duration(minutes: 5));
    activity.setAppForeground(false);
    await service.loadConfig();
    expect(requests, 1);
    activity.setAppForeground(true);
    final updated = await service.loadConfig() as Map;
    expect(updated['UpdateUrl'], 'https://update-2.example/version.json');
    expect(requests, 2);
  });

  test('background cold loads still validate required hosts', () async {
    final activity = ApiRemoteConfigActivity()..setAppForeground(false);
    var requests = 0;
    final service = ApiHealthService(
      configUrl: 'https://background-cold.example/config',
      activity: activity,
      configLoader: (_) async => ++requests == 1
          ? {'Authentication': 'FengWo', 'hosts': <String>[]}
          : _config('strict.example.com'),
    );
    expect(parseApiEndpoints(await service.loadConfig()), isEmpty);
    expect(
      (await service.loadVerifiedCandidateEndpoints()).single.host,
      'strict.example.com',
    );
    expect(requests, 2);
  });

  test('background disk fallback refreshes only after resume', () async {
    final activity = ApiRemoteConfigActivity()..setWindowForeground(false);
    final store = _Store()..payload = _config('disk.example.com');
    var requests = 0;
    final service = ApiHealthService(
      configUrl: 'https://background-disk.example/config',
      configCacheStore: store,
      activity: activity,
      configLoader: (_) async {
        requests++;
        return _config('new.example.com');
      },
    );
    expect(
      (await service.loadVerifiedCandidateEndpoints()).single.host,
      'disk.example.com',
    );
    expect(requests, 0);
    activity.setWindowForeground(true);
    expect(
      parseApiEndpoints(await service.loadConfig()).single.host,
      'new.example.com',
    );
    expect(requests, 1);
  });

  testWidgets('background pauses delayed retries without renewing cached TTL', (
    tester,
  ) async {
    final activity = ApiRemoteConfigActivity();
    final clock = _Clock();
    final failedRound = Completer<Object?>();
    final store = _Store();
    var requests = 0;
    final service = ApiHealthService(
      configUrl: 'https://retry-pause.example/config',
      configCacheStore: store,
      activity: activity,
      now: clock.now,
      configLoader: (_) {
        requests++;
        if (requests == 2) return failedRound.future;
        return Future.value(
          _config(requests == 1 ? 'old.example.com' : 'new.example.com'),
        );
      },
    );
    await service.loadConfig();
    clock.advance(const Duration(minutes: 5));
    final pending = service.loadConfig();
    failedRound.completeError(const SocketException('controlled outage'));
    await tester.pump();
    activity.setWindowForeground(false);
    await tester.pump(const Duration(minutes: 10));
    expect(requests, 2);
    expect(parseApiEndpoints(await pending).single.host, 'old.example.com');
    expect(store.writes, 1);
    activity.setWindowForeground(true);
    await tester.pump();
    expect(
      parseApiEndpoints(await service.loadConfig()).single.host,
      'new.example.com',
    );
    expect(requests, 3);
    expect(store.writes, 2);
  });

  testWidgets(
    'a delayed normal retry returns the newer background forced config',
    (tester) async {
      final activity = ApiRemoteConfigActivity();
      final clock = _Clock();
      var requests = 0;
      final service = ApiHealthService(
        configUrl: 'https://deferred-force.example/config',
        configCacheStore: _Store(),
        activity: activity,
        now: clock.now,
        configLoader: (_) async {
          requests++;
          if (requests == 2) throw const SocketException('controlled outage');
          return _config(
            requests == 1 ? 'old.example.com' : 'forced.example.com',
          );
        },
      );
      await service.loadConfig();
      clock.advance(const Duration(minutes: 5));
      final normal = service.loadConfig();
      await tester.pump();
      activity.setAppForeground(false);
      await service.loadConfig(forceRefresh: true);
      await tester.pump(const Duration(milliseconds: 250));
      expect(parseApiEndpoints(await normal).single.host, 'forced.example.com');
      activity.setAppForeground(true);
      await tester.pump();
      expect(requests, 3);
    },
  );

  testWidgets(
    'forced delayed retries continue while cached app is background',
    (tester) async {
      final activity = ApiRemoteConfigActivity();
      final store = _Store();
      var requests = 0;
      final service = ApiHealthService(
        configUrl: 'https://force-retry.example/config',
        configCacheStore: store,
        activity: activity,
        configLoader: (_) async {
          requests++;
          if (requests == 2) throw const SocketException('controlled outage');
          return _config(requests == 1 ? 'old.example.com' : 'new.example.com');
        },
      );
      await service.loadConfig();
      activity.setAppForeground(false);
      final forced = service.loadConfig(forceRefresh: true);
      await tester.pump();
      expect(requests, 2);
      await tester.pump(const Duration(milliseconds: 250));
      expect(parseApiEndpoints(await forced).single.host, 'new.example.com');
      expect(requests, 3);
    },
  );

  test(
    'default trust reads legacy cache offline while custom trust rejects it',
    () async {
      var attempts = 0;
      final previous = HttpOverrides.current;
      HttpOverrides.global = _BlockedHttpOverrides(() => attempts++);
      addTearDown(() => HttpOverrides.global = previous);
      await ApiRemoteConfigCacheStore().save(
        encryptedConfig: _config('legacy.example.com'),
        candidateCount: 1,
      );
      final service = ApiHealthService(
        memoryCache: ApiRemoteConfigMemoryCache(),
        configRetryDelays: const [Duration.zero],
      );
      expect(
        (await service.loadVerifiedCandidateEndpoints()).single.host,
        'legacy.example.com',
      );
      await _until(() => attempts >= 2);
      final custom = ApiHealthService(
        configUrl: 'https://unrelated.example/config',
        configRetryDelays: const [Duration.zero],
        configLoader: (_) async => throw const SocketException('offline'),
        emergencyConfigLoader: () async => {'Authentication': 'invalid'},
      );
      await expectLater(
        custom.loadVerifiedCandidateEndpoints(),
        throwsA(isA<ApiRemoteConfigException>()),
      );
      expect(
        await ApiRemoteConfigCacheStore().load(),
        contains('legacy.example.com'),
      );
    },
  );

  test(
    'namespaced persistence preserves legacy reads only when enabled',
    () async {
      final legacy = ApiRemoteConfigCacheStore();
      await legacy.save(
        encryptedConfig: _config('legacy.example.com'),
        candidateCount: 1,
      );
      expect(
        await ApiRemoteConfigCacheStore(namespace: 'custom').load(),
        isNull,
      );
      final compatible = ApiRemoteConfigCacheStore(
        namespace: 'production',
        allowLegacyFallback: true,
      );
      expect(await compatible.load(), contains('legacy.example.com'));
      await compatible.save(
        encryptedConfig: _config('new.example.com'),
        candidateCount: 1,
      );
      expect(await compatible.load(), contains('new.example.com'));
      expect(await legacy.load(), contains('legacy.example.com'));
    },
  );
}

Map<String, Object?> _config(String host) => {
  'Authentication': 'FengWo',
  'hosts': ['https://$host'],
};

class _Clock {
  DateTime value = DateTime.utc(2026, 10, 25);

  DateTime now() => value;

  void advance(Duration duration) => value = value.add(duration);
}

class _Store extends ApiRemoteConfigCacheStore {
  _Store({this.firstWriteGate, this.readResponse});

  final Future<void>? firstWriteGate;
  final Future<Object?>? readResponse;
  final writeStarted = Completer<void>();
  final readStarted = Completer<void>();
  Object? payload;
  int writes = 0;
  int clears = 0;

  @override
  Future<Object?> load() async {
    if (!readStarted.isCompleted) readStarted.complete();
    return readResponse ?? payload;
  }

  @override
  Future<void> save({
    required Object? encryptedConfig,
    required int candidateCount,
  }) async {
    writes++;
    if (!writeStarted.isCompleted) writeStarted.complete();
    if (writes == 1 && firstWriteGate != null) await firstWriteGate;
    payload = encryptedConfig;
  }

  @override
  Future<void> clear() async {
    clears++;
    payload = null;
  }
}

Future<HttpServer> _server(Future<void> Function(HttpRequest) handle) async {
  final previous = HttpOverrides.current;
  HttpOverrides.global = _DirectHttpOverrides();
  addTearDown(() => HttpOverrides.global = previous);
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  addTearDown(() => server.close(force: true));
  server.listen((request) => unawaited(handle(request)));
  return server;
}

class _DirectHttpOverrides extends HttpOverrides {}

class _BlockedHttpOverrides extends HttpOverrides {
  _BlockedHttpOverrides(this.onRequest);

  final void Function() onRequest;

  @override
  HttpClient createHttpClient(SecurityContext? context) =>
      super.createHttpClient(context)
        ..connectionFactory = (url, proxyHost, proxyPort) async {
          onRequest();
          throw const SocketException('controlled offline transport');
        };
}

String _url(HttpServer server) =>
    'http://${server.address.address}:${server.port}/config-${DateTime.now().microsecondsSinceEpoch}';

Future<void> _respond(HttpRequest request, Object config) async {
  request.response
    ..headers.contentType = ContentType.json
    ..write(jsonEncode(config));
  await request.response.close();
}

Future<void> _until(bool Function() condition) async {
  for (var attempt = 0; attempt < 100; attempt++) {
    if (condition()) return;
    await Future<void>.delayed(const Duration(milliseconds: 1));
  }
  fail('Asynchronous operation did not progress');
}

Future<({Map<String, Object?> payload, String aesKey, String signingKey})>
_encryptedConfig() async {
  final cipher = AesGcm.with256bits();
  final aes = await cipher.newSecretKey();
  final signing = await Ed25519().newKeyPair();
  final signingPublic = await signing.extractPublicKey();
  final payload = <String, Object?>{
    'format': remoteConfigFormat,
    'version': remoteConfigVersion,
    'alg': remoteConfigEncryptionAlgorithm,
    'sig': remoteConfigSignatureAlgorithm,
    'kid': remoteConfigKeyId(signingPublic.bytes),
  };
  final box = await cipher.encrypt(
    utf8.encode(jsonEncode(_config('signed.example.com'))),
    secretKey: aes,
    nonce: cipher.newNonce(),
    aad: remoteConfigAdditionalData(payload),
  );
  payload.addAll({
    'nonce': encodeRemoteConfigBase64(box.nonce),
    'ciphertext': encodeRemoteConfigBase64(box.cipherText),
    'tag': encodeRemoteConfigBase64(box.mac.bytes),
  });
  final signature = await Ed25519().sign(
    remoteConfigSignatureMessage(payload),
    keyPair: signing,
  );
  payload['signature'] = encodeRemoteConfigBase64(signature.bytes);
  return (
    payload: payload,
    aesKey: encodeRemoteConfigBase64(await aes.extractBytes()),
    signingKey: encodeRemoteConfigBase64(signingPublic.bytes),
  );
}

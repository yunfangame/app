import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:fl_clash/common/api_endpoint_preference.dart';
import 'package:fl_clash/common/api_health.dart';
import 'package:fl_clash/common/api_remote_config_cache.dart';
import 'package:fl_clash/common/remote_config_cipher.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('parses only hosts and normalizes domains', () {
    expect(
      parseApiEndpoints({
        'hosts': [
          'api-one.example.com',
          'https://api-two.example.com/health',
          {'domain': 'api-three.example.com'},
          'api-one.example.com',
          'ftp://invalid.example.com',
        ],
      }).map((endpoint) => endpoint.toString()),
      [
        'https://api-one.example.com',
        'https://api-two.example.com/health',
        'https://api-three.example.com',
      ],
    );

    expect(
      parseApiEndpoints({
        'api_domains': ['https://ignored.example.com'],
        'campusHosts': ['127.0.0.1 ignored.example.com'],
      }),
      isEmpty,
    );
  });

  test('decodes the agreed Base64 config and validates authentication', () {
    final encoded = base64Encode(
      utf8.encode(
        jsonEncode({
          'Authentication': 'FengWo',
          'hosts': ['https://api.example.com'],
        }),
      ),
    );

    final config = decodeApiHealthConfig(encoded);
    expect(parseApiEndpoints(config).single.host, 'api.example.com');
    expect(
      () => decodeApiHealthConfig(
        jsonEncode({'Authentication': 'Other', 'hosts': []}),
      ),
      throwsFormatException,
    );
  });

  test('maps connectivity percentages to the requested status levels', () {
    expect(_snapshot(5, 4).percentage, 80);
    expect(_snapshot(5, 4).level, ApiHealthLevel.healthy);
    expect(_snapshot(2, 1).percentage, 50);
    expect(_snapshot(2, 1).level, ApiHealthLevel.warning);
    expect(_snapshot(5, 2).level, ApiHealthLevel.critical);
    expect(_snapshot(5, 2).shouldPulse, isFalse);
    expect(_snapshot(5, 0).level, ApiHealthLevel.critical);
    expect(_snapshot(5, 0).shouldPulse, isTrue);
  });

  test('each check reloads config and probes all endpoints', () async {
    var configLoads = 0;
    var probes = 0;
    final service = ApiHealthService(
      configUrl: 'https://config.example.com/app.json',
      configLoader: (_) async {
        configLoads++;
        return {
          'Authentication': 'FengWo',
          'hosts': ['https://one.example.com', 'https://two.example.com'],
        };
      },
      endpointProbe: (endpoint) async {
        probes++;
        return endpoint.host == 'one.example.com';
      },
    );

    final first = await service.check();
    final second = await service.check();

    expect(configLoads, 2);
    expect(probes, 4);
    expect(first.percentage, 50);
    expect(second.percentage, 50);
  });

  test('missing config URL returns an unavailable snapshot', () async {
    final snapshot = await ApiHealthService(configUrl: '').check();

    expect(snapshot.level, ApiHealthLevel.unavailable);
    expect(snapshot.total, 0);
  });

  test('login candidates do not depend on health probes', () async {
    var probes = 0;
    final service = ApiHealthService(
      configUrl: 'https://config.example.com/app.json',
      configLoader: (_) async => {
        'Authentication': 'FengWo',
        'hosts': ['https://one.example.com', 'https://two.example.com'],
      },
      endpointProbe: (_) async {
        probes++;
        return false;
      },
    );

    final endpoints = await service.loadCandidateEndpoints();

    expect(endpoints.map((endpoint) => endpoint.host), [
      'one.example.com',
      'two.example.com',
    ]);
    expect(probes, 0);
  });

  test('login candidates retry a temporarily unavailable config', () async {
    var configLoads = 0;
    final service = ApiHealthService(
      configUrl: 'https://config.example.com/app.json',
      configRetryDelays: const [Duration.zero, Duration.zero, Duration.zero],
      configLoader: (_) async {
        configLoads++;
        if (configLoads < 3) throw StateError('temporary failure');
        return {
          'Authentication': 'FengWo',
          'hosts': ['https://api.example.com'],
        };
      },
    );

    final endpoints = await service.loadCandidateEndpoints();

    expect(configLoads, 3);
    expect(endpoints.single.host, 'api.example.com');
  });

  test('last successful endpoint backs up a failed config load', () async {
    final store = ApiEndpointPreferenceStore();
    await store.save(Uri.parse('https://last-good.example.com:15699'));
    final service = ApiHealthService(
      configUrl: 'https://config.example.com/app.json',
      configRetryDelays: const [Duration.zero, Duration.zero],
      preferenceStore: store,
      configLoader: (_) async => throw StateError('config unavailable'),
    );

    final endpoints = await service.loadCandidateEndpoints();

    expect(endpoints, [Uri.parse('https://last-good.example.com:15699')]);
  });

  test('persists and prioritizes the selected healthy endpoint', () async {
    final store = ApiEndpointPreferenceStore();
    final service = ApiHealthService(preferenceStore: store);
    await service.savePreferredEndpoint(
      Uri.parse('https://preferred.example.com/health?source=config'),
    );
    final snapshot = ApiHealthSnapshot(
      endpoints: [
        ApiEndpointHealth(
          endpoint: Uri.parse('https://fast.example.com'),
          reachable: true,
          latency: const Duration(milliseconds: 20),
        ),
        ApiEndpointHealth(
          endpoint: Uri.parse('https://preferred.example.com'),
          reachable: true,
          latency: const Duration(milliseconds: 200),
        ),
      ],
      checkedAt: DateTime(2026),
    );

    final ordered = await service.orderedReachableEndpoints(snapshot);

    expect(
      await service.loadPreferredEndpoint(),
      Uri.parse('https://preferred.example.com'),
    );
    expect(ordered.first.endpoint.host, 'preferred.example.com');
    expect(ordered.last.endpoint.host, 'fast.example.com');
  });

  test('persists verified candidates before any login succeeds', () async {
    final cache = ApiRemoteConfigCacheStore();
    final service = ApiHealthService(
      configUrl: 'https://config.example.com/app.json',
      configCacheStore: cache,
      configLoader: (_) async => {
        'Authentication': 'FengWo',
        'hosts': ['https://cached.example.com'],
      },
    );

    final endpoints = await service.loadCandidateEndpoints();

    expect(endpoints.single.host, 'cached.example.com');
    expect(await cache.load(), contains('cached.example.com'));
  });

  test('returns verified cache while refreshing it in background', () async {
    final cache = ApiRemoteConfigCacheStore();
    await ApiHealthService(
      configUrl: 'https://config.example.com/app.json',
      configCacheStore: cache,
      configLoader: (_) async => {
        'Authentication': 'FengWo',
        'hosts': ['https://old.example.com'],
      },
    ).loadCandidateEndpoints();
    final refreshStarted = Completer<void>();
    final refreshResponse = Completer<Object?>();
    final service = ApiHealthService(
      configUrl: 'https://config.example.com/app.json',
      configCacheStore: cache,
      configLoader: (_) {
        refreshStarted.complete();
        return refreshResponse.future;
      },
    );

    final endpoints = await service.loadCandidateEndpoints().timeout(
      const Duration(milliseconds: 200),
    );

    expect(endpoints.single.host, 'old.example.com');
    await refreshStarted.future;
    refreshResponse.complete({
      'Authentication': 'FengWo',
      'hosts': ['https://new.example.com'],
    });
    await _waitUntil(() async {
      final cached = await cache.load();
      return cached?.toString().contains('new.example.com') ?? false;
    });
  });

  test('uses a second remote source when primary sources fail', () async {
    final requested = <String>{};
    final service = ApiHealthService(
      configUrl: 'https://primary.example.com/config.json',
      backupConfigUrls: const [
        'https://backup-one.example.com/config.json',
        'https://backup-two.example.com/config.json',
      ],
      configRetryDelays: const [Duration.zero],
      configLoader: (uri) async {
        requested.add(uri.host);
        if (uri.host != 'backup-two.example.com') {
          throw StateError('unavailable');
        }
        return {
          'Authentication': 'FengWo',
          'hosts': ['https://api.example.com'],
        };
      },
    );

    final endpoints = await service.loadCandidateEndpoints();

    expect(endpoints.single.host, 'api.example.com');
    expect(requested, {
      'primary.example.com',
      'backup-one.example.com',
      'backup-two.example.com',
    });
  });

  test(
    'uses bundled emergency config when every remote source fails',
    () async {
      final service = ApiHealthService(
        configUrl: 'https://primary.example.com/config.json',
        backupConfigUrls: const ['https://backup.example.com/config.json'],
        configRetryDelays: const [Duration.zero],
        configLoader: (_) async => throw StateError('offline'),
        emergencyConfigLoader: () async => {
          'Authentication': 'FengWo',
          'hosts': ['https://emergency.example.com'],
        },
      );

      final endpoints = await service.loadCandidateEndpoints();

      expect(endpoints.single.host, 'emergency.example.com');
    },
  );

  test('does not block first launch on a stalled remote config', () async {
    final stalled = Completer<Object?>();
    final service = ApiHealthService(
      configUrl: 'https://primary.example.com/config.json',
      initialRemoteWait: const Duration(milliseconds: 10),
      configLoader: (_) => stalled.future,
      emergencyConfigLoader: () async => {
        'Authentication': 'FengWo',
        'hosts': ['https://emergency.example.com'],
      },
    );

    final endpoints = await service.loadCandidateEndpoints().timeout(
      const Duration(milliseconds: 200),
    );

    expect(endpoints.single.host, 'emergency.example.com');
  });

  test('classifies remote config failures precisely', () async {
    Future<String?> errorFor(Object error) async {
      final service = ApiHealthService(
        configUrl: 'https://config.example.com/app.json',
        configRetryDelays: const [Duration.zero],
        configLoader: (_) async => throw error,
      );
      return (await service.check()).error;
    }

    expect(
      await errorFor(
        DioException(
          requestOptions: RequestOptions(path: '/config'),
          type: DioExceptionType.connectionError,
          error: const SocketException('Failed host lookup'),
        ),
      ),
      'config_dns_failed',
    );
    expect(
      await errorFor(
        DioException(
          requestOptions: RequestOptions(path: '/config'),
          type: DioExceptionType.connectionTimeout,
        ),
      ),
      'config_timeout',
    );
    expect(
      await errorFor(
        DioException(
          requestOptions: RequestOptions(path: '/config'),
          type: DioExceptionType.badResponse,
          response: Response(
            requestOptions: RequestOptions(path: '/config'),
            statusCode: 503,
          ),
        ),
      ),
      'config_http_failed',
    );
    expect(
      await errorFor(
        const RemoteConfigCipherException(
          RemoteConfigCipherFailure.signature,
          'signature failed',
        ),
      ),
      'config_signature_failed',
    );

    final decryptSnapshot = await ApiHealthService(
      configUrl: 'https://config.example.com/app.json',
      configRetryDelays: const [Duration.zero],
      configLoader: (_) async => {
        'Authentication': 'Wrong',
        'hosts': ['https://api.example.com'],
      },
    ).check();
    expect(decryptSnapshot.error, 'config_decrypt_failed');

    final emptySnapshot = await ApiHealthService(
      configUrl: 'https://config.example.com/app.json',
      configRetryDelays: const [Duration.zero],
      configLoader: (_) async => {
        'Authentication': 'FengWo',
        'hosts': <String>[],
      },
    ).check();
    expect(emptySnapshot.error, 'api_endpoints_empty');
  });

  test('remote config download ignores the global proxy', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    unawaited(() async {
      await for (final request in server) {
        request.response
          ..headers.contentType = ContentType.json
          ..write(
            jsonEncode({
              'Authentication': 'FengWo',
              'hosts': ['https://api.example.com'],
            }),
          );
        await request.response.close();
      }
    }());
    final previous = HttpOverrides.current;
    HttpOverrides.global = _ProxyOnlyHttpOverrides();
    addTearDown(() => HttpOverrides.global = previous);
    final service = ApiHealthService(
      configUrl: 'http://${server.address.address}:${server.port}/config.json',
      configRetryDelays: const [Duration.zero],
    );

    final config = await service.loadConfig();

    expect(parseApiEndpoints(config).single.host, 'api.example.com');
  });
}

Future<void> _waitUntil(Future<bool> Function() condition) async {
  for (var attempt = 0; attempt < 50; attempt++) {
    if (await condition()) return;
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  fail('Timed out waiting for asynchronous condition');
}

class _ProxyOnlyHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    final client = super.createHttpClient(context);
    client.findProxy = (_) => 'PROXY 127.0.0.1:1';
    return client;
  }
}

ApiHealthSnapshot _snapshot(int total, int reachable) {
  return ApiHealthSnapshot(
    endpoints: List.generate(
      total,
      (index) => ApiEndpointHealth(
        endpoint: Uri.parse('https://api-$index.example.com'),
        reachable: index < reachable,
        latency: const Duration(milliseconds: 20),
      ),
    ),
    checkedAt: DateTime(2026),
  );
}

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:fl_clash/common/api_endpoint_preference.dart';
import 'package:fl_clash/common/api_health.dart';
import 'package:fl_clash/common/api_network_diagnostic.dart';
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

  test('real API probe GETs a valid XBoard guest config', () async {
    _useDirectHttpClient();
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    final requests = <String>[];
    unawaited(() async {
      await for (final request in server) {
        requests.add('${request.method} ${request.uri}');
        request.response
          ..headers.contentType = ContentType.json
          ..write(
            jsonEncode({'status': 'success', 'data': <String, Object?>{}}),
          );
        await request.response.close();
      }
    }());
    final endpoint = Uri.parse(
      'http://${server.address.address}:${server.port}/ignored?private=value',
    );

    final health = await ApiHealthService(
      configUrl: '',
    ).probeEndpoint(endpoint);

    expect(health.reachable, isTrue);
    expect(requests, ['GET /api/v1/guest/comm/config']);
  });

  test('root page success does not mask a failed API route', () async {
    _useDirectHttpClient();
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    unawaited(() async {
      await for (final request in server) {
        request.response.statusCode = request.uri.path == '/' ? 200 : 503;
        await request.response.close();
      }
    }());
    final endpoint = Uri.parse(
      'http://${server.address.address}:${server.port}/',
    );

    final health = await ApiHealthService(
      configUrl: '',
    ).probeEndpoint(endpoint);

    expect(health.reachable, isFalse);
    expect(health.diagnostic?.failure, ApiNetworkFailure.http);
    expect(health.diagnostic?.statusCode, 503);
  });

  test('API probe rejects a malformed successful envelope', () async {
    _useDirectHttpClient();
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    unawaited(() async {
      await for (final request in server) {
        request.response
          ..headers.contentType = ContentType.json
          ..write(jsonEncode({'status': 'success', 'data': <Object?>[]}));
        await request.response.close();
      }
    }());
    final endpoint = Uri.parse(
      'http://${server.address.address}:${server.port}/',
    );

    final health = await ApiHealthService(
      configUrl: '',
    ).probeEndpoint(endpoint);

    expect(health.reachable, isFalse);
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

  test(
    'authenticated routing rejects an unverified historical origin',
    () async {
      final store = ApiEndpointPreferenceStore();
      await store.save(Uri.parse('https://unlisted.example.com'));
      final service = ApiHealthService(
        configUrl: 'https://config.example.com/app.json',
        configRetryDelays: const [Duration.zero],
        preferenceStore: store,
        configLoader: (_) async => throw StateError('config unavailable'),
        emergencyConfigLoader: () async =>
            throw StateError('no verified backup'),
      );

      await expectLater(
        service.loadVerifiedCandidateEndpoints(),
        throwsA(isA<ApiRemoteConfigException>()),
      );
    },
  );

  test('authenticated routing keeps verified cache during an outage', () async {
    final cache = ApiRemoteConfigCacheStore();
    await ApiHealthService(
      configUrl: 'https://config.example.com/app.json',
      configCacheStore: cache,
      configLoader: (_) async => {
        'Authentication': 'FengWo',
        'hosts': ['https://cached.example.com'],
      },
    ).loadVerifiedCandidateEndpoints();
    final store = ApiEndpointPreferenceStore();
    await store.save(Uri.parse('https://unlisted.example.com'));
    final service = ApiHealthService(
      configUrl: 'https://config.example.com/app.json',
      configRetryDelays: const [Duration.zero],
      configCacheStore: cache,
      preferenceStore: store,
      configLoader: (_) async => throw StateError('config unavailable'),
      emergencyConfigLoader: () async => throw StateError('no verified backup'),
    );

    final candidates = await service.loadVerifiedCandidateEndpoints();

    expect(candidates, [Uri.parse('https://cached.example.com')]);
  });

  test('authenticated routing accepts only verified emergency hosts', () async {
    final store = ApiEndpointPreferenceStore();
    await store.save(Uri.parse('https://unlisted.example.com'));
    final service = ApiHealthService(
      configUrl: 'https://config.example.com/app.json',
      configRetryDelays: const [Duration.zero],
      preferenceStore: store,
      configLoader: (_) async => throw StateError('config unavailable'),
      emergencyConfigLoader: () async => {
        'Authentication': 'FengWo',
        'hosts': ['https://emergency.example.com'],
      },
    );

    final candidates = await service.loadVerifiedCandidateEndpoints();

    expect(candidates, [Uri.parse('https://emergency.example.com')]);
  });

  test('a stalled optional preference cannot block verified routing', () async {
    final preferenceResponse = Completer<SharedPreferences>();
    final cache = _ControlledConfigCache(
      payload: {
        'Authentication': 'FengWo',
        'hosts': ['https://cached.example.com'],
      },
    );
    final service = ApiHealthService(
      configUrl: 'https://config.example.com/app.json',
      configRetryDelays: const [Duration.zero],
      preferenceStore: ApiEndpointPreferenceStore(
        preferencesLoader: () => preferenceResponse.future,
      ),
      configCacheStore: cache,
      configLoader: (_) async => throw StateError('remote unavailable'),
    );

    final endpoints = await service.loadVerifiedCandidateEndpoints().timeout(
      const Duration(seconds: 3),
    );

    expect(endpoints.single.host, 'cached.example.com');
    expect(cache.clears, 0);
  });

  test('a stalled cache read falls back without clearing valid data', () async {
    final cacheResponse = Completer<Object?>();
    final cache = _ControlledConfigCache(readResponse: cacheResponse.future);
    final service = ApiHealthService(
      configUrl: 'https://config.example.com/app.json',
      configRetryDelays: const [Duration.zero],
      configCacheStore: cache,
      configLoader: (_) async => {
        'Authentication': 'FengWo',
        'hosts': ['https://remote.example.com'],
      },
    );

    final endpoints = await service.loadVerifiedCandidateEndpoints().timeout(
      const Duration(seconds: 3),
    );

    expect(endpoints.single.host, 'remote.example.com');
    expect(cache.clears, 0);
    cacheResponse.complete({
      'Authentication': 'FengWo',
      'hosts': ['https://old.example.com'],
    });
    await Future<void>.delayed(Duration.zero);
    expect(cache.clears, 0);
    expect(endpoints.single.host, 'remote.example.com');
  });

  test('a stalled cache write cannot block a verified remote config', () async {
    final cacheResponse = Completer<void>();
    final cache = _ControlledConfigCache(writeResponse: cacheResponse.future);
    final service = ApiHealthService(
      configUrl: 'https://config.example.com/app.json',
      configCacheStore: cache,
      configLoader: (_) async => {
        'Authentication': 'FengWo',
        'hosts': ['https://remote.example.com'],
      },
    );

    final config = await service.loadConfig().timeout(
      const Duration(seconds: 3),
    );

    expect(parseApiEndpoints(config).single.host, 'remote.example.com');
    expect(cache.writes, 1);
  });

  test('legacy manual API preference is ignored and removed', () async {
    SharedPreferences.setMockInitialValues({
      'xboard.preferred_api_endpoint': 'https://manual.example.com',
    });
    final store = ApiEndpointPreferenceStore();

    expect(await store.load(), isNull);
    final preferences = await SharedPreferences.getInstance();
    expect(preferences.containsKey('xboard.preferred_api_endpoint'), isFalse);
  });

  test('persists and prioritizes the last successful endpoint', () async {
    final store = ApiEndpointPreferenceStore();
    final service = ApiHealthService(
      configUrl: 'https://config.example.com/app.json',
      preferenceStore: store,
      configLoader: (_) async => {
        'Authentication': 'FengWo',
        'hosts': ['https://first.example.com', 'https://last-good.example.com'],
      },
    );
    await service.rememberSuccessfulEndpoint(
      Uri.parse('https://last-good.example.com/health?source=config'),
    );

    final candidates = await service.loadCandidateEndpoints();

    expect(
      await service.loadLastSuccessfulEndpoint(),
      Uri.parse('https://last-good.example.com'),
    );
    expect(candidates.first.host, 'last-good.example.com');
    expect(candidates.last.host, 'first.example.com');
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

  test('force refresh downloads new config with cache bypass headers', () async {
    _useDirectHttpClient();
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    final requests = <({Uri uri, String? cacheControl, String? pragma})>[];
    server.listen((request) async {
      requests.add((
        uri: request.uri,
        cacheControl: request.headers.value(HttpHeaders.cacheControlHeader),
        pragma: request.headers.value(HttpHeaders.pragmaHeader),
      ));
      request.response
        ..headers.contentType = ContentType.json
        ..headers.set(
          HttpHeaders.cacheControlHeader,
          'public, max-age=31536000',
        )
        ..write(
          jsonEncode({
            'Authentication': 'FengWo',
            'hosts': ['https://api.example.com'],
            'campusHostsByOperator': {
              'line_1': ['192.0.2.${requests.length} campus.example'],
            },
          }),
        );
      await request.response.close();
    });
    final service = ApiHealthService(
      configUrl:
          'http://${server.address.address}:${server.port}/config.json?source=campus&line=one&line=two',
      configRetryDelays: const [Duration.zero],
    );

    final initial = await service.loadConfig();
    final firstRefresh = await service.loadConfig(forceRefresh: true);
    final secondRefresh = await service.loadConfig(forceRefresh: true);

    expect(requests, hasLength(3));
    expect(requests.first.uri.queryParametersAll, {
      'source': ['campus'],
      'line': ['one', 'two'],
    });
    expect(requests.first.cacheControl, isNull);
    expect(requests.first.pragma, isNull);
    final firstNonce = requests[1].uri.queryParameters['_fengwo_refresh'];
    final secondNonce = requests[2].uri.queryParameters['_fengwo_refresh'];
    expect(firstNonce, isNotNull);
    expect(firstNonce, isNotEmpty);
    expect(secondNonce, isNot(firstNonce));
    for (final request in requests.skip(1)) {
      expect(request.uri.path, '/config.json');
      expect(request.uri.queryParametersAll['source'], ['campus']);
      expect(request.uri.queryParametersAll['line'], ['one', 'two']);
      expect(request.cacheControl, 'no-cache, no-store, max-age=0');
      expect(request.pragma, 'no-cache');
    }
    for (final (index, config) in [
      initial,
      firstRefresh,
      secondRefresh,
    ].indexed) {
      expect((config as Map)['campusHostsByOperator'], {
        'line_1': ['192.0.2.${index + 1} campus.example'],
      });
    }
  });

  test('force refresh bypasses primary and backup HTTP caches', () async {
    _useDirectHttpClient();
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    final requests = <({Uri uri, String? cacheControl, String? pragma})>[];
    final allRequested = Completer<void>();
    server.listen((request) async {
      requests.add((
        uri: request.uri,
        cacheControl: request.headers.value(HttpHeaders.cacheControlHeader),
        pragma: request.headers.value(HttpHeaders.pragmaHeader),
      ));
      if (requests.length == 2) allRequested.complete();
      await allRequested.future.timeout(const Duration(seconds: 2));
      request.response.headers.contentType = ContentType.json;
      if (request.uri.path == '/primary.json') {
        request.response.statusCode = HttpStatus.serviceUnavailable;
      } else {
        request.response.write(
          jsonEncode({
            'Authentication': 'FengWo',
            'hosts': ['https://backup-api.example.com'],
          }),
        );
      }
      await request.response.close();
    });
    final origin = 'http://${server.address.address}:${server.port}';
    final service = ApiHealthService(
      configUrl: '$origin/primary.json?source=primary',
      backupConfigUrls: ['$origin/backup.json?source=backup'],
      configRetryDelays: const [Duration.zero],
    );

    final config = await service.loadConfig(forceRefresh: true);

    expect(parseApiEndpoints(config).single.host, 'backup-api.example.com');
    expect(requests, hasLength(2));
    expect(
      requests.map((request) => request.uri.path),
      unorderedEquals(['/primary.json', '/backup.json']),
    );
    final nonces = <String>{};
    for (final request in requests) {
      final nonce = request.uri.queryParameters['_fengwo_refresh'];
      expect(nonce, isNotNull);
      expect(nonce, isNotEmpty);
      nonces.add(nonce!);
      expect(
        request.uri.queryParameters['source'],
        request.uri.path == '/primary.json' ? 'primary' : 'backup',
      );
      expect(request.cacheControl, 'no-cache, no-store, max-age=0');
      expect(request.pragma, 'no-cache');
    }
    expect(nonces, hasLength(1));
  });

  test(
    'failed forced refresh preserves but never returns verified cache',
    () async {
      final cache = ApiRemoteConfigCacheStore();
      await cache.save(
        encryptedConfig: {
          'Authentication': 'FengWo',
          'hosts': ['https://cached.example.com'],
        },
        candidateCount: 1,
      );
      final requested = <Uri>[];
      final service = ApiHealthService(
        configUrl: 'https://primary.example.com/config.json?source=primary',
        backupConfigUrls: const [
          'https://backup.example.com/config.json?source=backup',
        ],
        configRetryDelays: const [Duration.zero, Duration.zero],
        configCacheStore: cache,
        configLoader: (uri) async {
          requested.add(uri);
          throw StateError('remote unavailable');
        },
      );

      for (var attempt = 0; attempt < 2; attempt++) {
        await expectLater(
          service.loadConfig(forceRefresh: true),
          throwsA(isA<ApiRemoteConfigException>()),
        );
      }

      expect(requested, hasLength(8));
      expect(requested.map((uri) => uri.host).toSet(), {
        'primary.example.com',
        'backup.example.com',
      });
      for (final uri in requested) {
        expect(uri.queryParameters['_fengwo_refresh'], isNotEmpty);
        expect(
          uri.queryParameters['source'],
          uri.host == 'primary.example.com' ? 'primary' : 'backup',
        );
      }
      final firstNonces = requested
          .take(4)
          .map((uri) => uri.queryParameters['_fengwo_refresh'])
          .toSet();
      final secondNonces = requested
          .skip(4)
          .map((uri) => uri.queryParameters['_fengwo_refresh'])
          .toSet();
      expect(firstNonces, hasLength(1));
      expect(secondNonces, hasLength(1));
      expect(secondNonces.single, isNot(firstNonces.single));
      expect(await cache.load(), contains('cached.example.com'));
    },
  );

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

class _ControlledConfigCache extends ApiRemoteConfigCacheStore {
  _ControlledConfigCache({this.payload, this.readResponse, this.writeResponse});

  final Object? payload;
  final Future<Object?>? readResponse;
  final Future<void>? writeResponse;
  int clears = 0;
  int writes = 0;

  @override
  Future<Object?> load() async => readResponse ?? payload;

  @override
  Future<void> save({
    required Object? encryptedConfig,
    required int candidateCount,
  }) async {
    writes++;
    if (writeResponse case final response?) await response;
  }

  @override
  Future<void> clear() async {
    clears++;
  }
}

class _ProxyOnlyHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    final client = super.createHttpClient(context);
    client.findProxy = (_) => 'PROXY 127.0.0.1:1';
    return client;
  }
}

class _DirectHttpOverrides extends HttpOverrides {}

void _useDirectHttpClient() {
  final previous = HttpOverrides.current;
  HttpOverrides.global = _DirectHttpOverrides();
  addTearDown(() => HttpOverrides.global = previous);
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

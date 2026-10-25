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
  const primary = 'https://primary.example/config?source=primary';
  const backup = 'https://backup.example/config?source=backup';

  testWidgets(
    'fast verified primary prevents the delayed backup from starting',
    (tester) async {
      final requests = <Uri>[];
      final service = ApiHealthService(
        configUrl: primary,
        backupConfigUrls: const [backup],
        configCacheStore: _Store(),
        configLoader: (uri) async {
          requests.add(uri);
          return _config('primary-api.example');
        },
      );
      final response = service.loadConfig();
      await tester.pump();
      expect(
        parseApiEndpoints(await response).single.host,
        'primary-api.example',
      );
      await tester.pump(const Duration(seconds: 1));
      expect(requests.map((uri) => uri.host), ['primary.example']);
    },
  );

  testWidgets(
    'backup starts at 300ms and a late custom loader cannot replace its verified result',
    (tester) async {
      final pending = Completer<Object?>();
      final requests = <Uri>[];
      final service = ApiHealthService(
        configUrl: primary,
        backupConfigUrls: const [backup],
        configCacheStore: _Store(),
        configLoader: (uri) {
          requests.add(uri);
          return uri.host == 'primary.example'
              ? pending.future
              : Future.value(_config('backup-api.example'));
        },
      );
      final response = service.loadConfig();
      await tester.pump();
      expect(requests, hasLength(1));
      await tester.pump(const Duration(milliseconds: 299));
      expect(requests, hasLength(1));
      await tester.pump(const Duration(milliseconds: 1));
      expect(
        parseApiEndpoints(await response).single.host,
        'backup-api.example',
      );
      expect(pending.isCompleted, isFalse);
      pending.complete(_config('late-primary.example'));
      await tester.pump();
      final forced = service.loadConfig(forceRefresh: true);
      await tester.pump();
      expect(parseApiEndpoints(await forced).single.host, 'backup-api.example');
      expect(requests.map((uri) => uri.host), [
        'primary.example',
        'backup.example',
        'backup.example',
      ]);
      await tester.pump(const Duration(seconds: 1));
      expect(requests, hasLength(3));
    },
  );

  testWidgets(
    'a definite failure immediately starts the next source and preserves forced query parameters',
    (tester) async {
      final requests = <Uri>[];
      final service = ApiHealthService(
        configUrl: primary,
        backupConfigUrls: const [backup, 'https://unused.example/config'],
        configCacheStore: _Store(),
        configLoader: (uri) async {
          requests.add(uri);
          if (uri.host == 'primary.example') {
            throw const SocketException('controlled outage');
          }
          return _config('backup-api.example');
        },
      );
      final response = service.loadConfig(forceRefresh: true);
      await tester.pump();
      expect(
        parseApiEndpoints(await response).single.host,
        'backup-api.example',
      );
      expect(requests.map((uri) => uri.host), [
        'primary.example',
        'backup.example',
      ]);
      expect(requests.map((uri) => uri.queryParameters['source']), [
        'primary',
        'backup',
      ]);
      expect(
        requests.map((uri) => uri.queryParameters['_fengwo_refresh']),
        everyElement(isNotEmpty),
      );
      expect(
        requests.map((uri) => uri.queryParameters['_fengwo_refresh']).toSet(),
        hasLength(1),
      );
      await tester.pump(const Duration(seconds: 1));
      expect(requests, hasLength(2));
    },
  );

  testWidgets('strict candidates reject a fast source with no endpoints', (
    tester,
  ) async {
    final requests = <Uri>[];
    final service = ApiHealthService(
      configUrl: primary,
      backupConfigUrls: const [backup],
      configCacheStore: _Store(),
      configLoader: (uri) async {
        requests.add(uri);
        return uri.host == 'primary.example'
            ? {'Authentication': 'FengWo', 'hosts': <String>[]}
            : _config('backup-api.example');
      },
    );
    final response = service.loadVerifiedCandidateEndpoints();
    await tester.pump();
    expect((await response).single.host, 'backup-api.example');
    expect(requests.map((uri) => uri.host), [
      'primary.example',
      'backup.example',
    ]);
  });

  testWidgets('all sources still participate in all three failure rounds', (
    tester,
  ) async {
    final requests = <Uri>[];
    final service = ApiHealthService(
      configUrl: primary,
      backupConfigUrls: const [backup],
      configCacheStore: _Store(),
      configLoader: (uri) async {
        requests.add(uri);
        throw const SocketException('controlled outage');
      },
    );
    final response = service.loadConfig();
    final assertion = expectLater(
      response,
      throwsA(isA<ApiRemoteConfigException>()),
    );
    await tester.pump();
    expect(requests, hasLength(2));
    await tester.pump(const Duration(milliseconds: 249));
    expect(requests, hasLength(2));
    await tester.pump(const Duration(milliseconds: 1));
    expect(requests, hasLength(4));
    await tester.pump(const Duration(milliseconds: 749));
    expect(requests, hasLength(4));
    await tester.pump(const Duration(milliseconds: 1));
    await assertion;
    expect(requests.map((uri) => uri.host), [
      'primary.example',
      'backup.example',
      'primary.example',
      'backup.example',
      'primary.example',
      'backup.example',
    ]);
  });

  testWidgets(
    'preferred source is shared only through the same trust pool and expires after one hour',
    (tester) async {
      var now = DateTime.utc(2026, 10, 25);
      final pool = ApiRemoteConfigMemoryCache();
      final requests = <Uri>[];
      var primaryFails = true;
      ApiHealthService service({ApiRemoteConfigMemoryCache? memory}) =>
          ApiHealthService(
            configUrl: primary,
            backupConfigUrls: const [backup],
            memoryCache: memory,
            now: () => now,
            configCacheStore: _Store(),
            configLoader: (uri) async {
              requests.add(uri);
              if (primaryFails && uri.host == 'primary.example') {
                throw const SocketException('primary unavailable');
              }
              return _config('${uri.host}-api');
            },
          );
      final first = service(memory: pool).loadConfig();
      await tester.pump();
      await first;
      primaryFails = false;
      requests.clear();
      final preferred = service(memory: pool).loadConfig(forceRefresh: true);
      await tester.pump();
      await preferred;
      expect(requests.map((uri) => uri.host), ['backup.example']);
      requests.clear();
      final isolated = service().loadConfig();
      await tester.pump();
      await isolated;
      expect(requests.map((uri) => uri.host), ['primary.example']);
      requests.clear();
      now = now.add(const Duration(hours: 1));
      final expired = service(memory: pool).loadConfig(forceRefresh: true);
      await tester.pump();
      await expired;
      expect(requests.map((uri) => uri.host), ['primary.example']);
    },
  );

  testWidgets('clock rollback ignores a previously preferred backup', (
    tester,
  ) async {
    var now = DateTime.utc(2026, 10, 25);
    final requests = <Uri>[];
    var fail = true;
    final service = ApiHealthService(
      configUrl: primary,
      backupConfigUrls: const [backup],
      now: () => now,
      configCacheStore: _Store(),
      configLoader: (uri) async {
        requests.add(uri);
        if (fail && uri.host == 'primary.example') {
          throw const SocketException('outage');
        }
        return _config('api.example');
      },
    );
    final first = service.loadConfig();
    await tester.pump();
    await first;
    requests.clear();
    fail = false;
    now = now.subtract(const Duration(seconds: 1));
    final rollback = service.loadConfig(forceRefresh: true);
    await tester.pump();
    await rollback;
    expect(requests.map((uri) => uri.host), ['primary.example']);
  });

  testWidgets(
    'late normal success cannot change the forced preferred source or cache',
    (tester) async {
      final normal = Completer<Object?>();
      final requests = <Uri>[];
      final service = ApiHealthService(
        configUrl: primary,
        backupConfigUrls: const [backup],
        configCacheStore: _Store(),
        configLoader: (uri) async {
          requests.add(uri);
          if (!uri.queryParameters.containsKey('_fengwo_refresh')) {
            return normal.future;
          }
          if (uri.host == 'primary.example') {
            throw const SocketException('forced primary outage');
          }
          return _config('forced-api.example');
        },
      );
      final ordinary = service.loadConfig();
      await tester.pump();
      final forced = service.loadConfig(forceRefresh: true);
      await tester.pump();
      expect(parseApiEndpoints(await forced).single.host, 'forced-api.example');
      normal.complete(_config('old-api.example'));
      await tester.pump();
      expect(
        parseApiEndpoints(await ordinary).single.host,
        'forced-api.example',
      );
      expect(
        parseApiEndpoints(await service.loadConfig()).single.host,
        'forced-api.example',
      );
      final next = service.loadConfig(forceRefresh: true);
      await tester.pump();
      await next;
      expect(requests.map((uri) => uri.host), [
        'primary.example',
        'primary.example',
        'backup.example',
        'backup.example',
      ]);
    },
  );

  testWidgets(
    'pausing during hedge defers backup without refreshing cache age and resumes once',
    (tester) async {
      var now = DateTime.utc(2026, 10, 25);
      final activity = ApiRemoteConfigActivity();
      final obsolete = Completer<Object?>();
      final requests = <Uri>[];
      final events = <String>[];
      var phase = 0;
      final service = ApiHealthService(
        configUrl: primary,
        backupConfigUrls: const [backup],
        activity: activity,
        now: () => now,
        configCacheStore: _Store(),
        diagnosticRecorder: (event, _) => events.add(event),
        configLoader: (uri) {
          requests.add(uri);
          if (phase == 1) return obsolete.future;
          return Future.value(
            _config(phase == 0 ? 'old-api.example' : 'new-api.example'),
          );
        },
      );
      final seed = service.loadConfig();
      await tester.pump();
      await seed;
      phase = 1;
      now = now.add(const Duration(minutes: 5));
      final refresh = service.loadConfig();
      await tester.pump();
      expect(requests, hasLength(2));
      activity.setAppForeground(false);
      await tester.pump(const Duration(milliseconds: 300));
      expect(parseApiEndpoints(await refresh).single.host, 'old-api.example');
      await tester.pump(const Duration(seconds: 1));
      expect(requests, hasLength(2));
      expect(
        events.where((event) => event == 'api.config.attempt.failed'),
        isEmpty,
      );
      phase = 2;
      activity.setAppForeground(true);
      final joined = service.loadConfig();
      await tester.pump();
      expect(parseApiEndpoints(await joined).single.host, 'new-api.example');
      expect(requests, hasLength(3));
      obsolete.completeError(const SocketException('late discarded transport'));
      await tester.pump();
      expect(
        events.where((event) => event == 'api.config.attempt.failed'),
        isEmpty,
      );
      expect(requests.every((uri) => uri.host == 'primary.example'), isTrue);
    },
  );

  testWidgets(
    'force retains delayed fallback while a valid cache is backgrounded',
    (tester) async {
      final activity = ApiRemoteConfigActivity();
      final obsolete = Completer<Object?>();
      final requests = <Uri>[];
      var seeded = false;
      final service = ApiHealthService(
        configUrl: primary,
        backupConfigUrls: const [backup],
        activity: activity,
        configCacheStore: _Store(),
        configLoader: (uri) {
          requests.add(uri);
          if (!seeded) return Future.value(_config('old-api.example'));
          return uri.host == 'primary.example'
              ? obsolete.future
              : Future.value(_config('forced-api.example'));
        },
      );
      final seed = service.loadConfig();
      await tester.pump();
      await seed;
      seeded = true;
      activity.setAppForeground(false);
      final refresh = service.loadConfig(forceRefresh: true);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(
        parseApiEndpoints(await refresh).single.host,
        'forced-api.example',
      );
      expect(requests.map((uri) => uri.host), [
        'primary.example',
        'primary.example',
        'backup.example',
      ]);
      obsolete.complete(_config('late-api.example'));
      await tester.pump();
    },
  );

  testWidgets(
    'custom loser errors after a winner are discarded from diagnostics',
    (tester) async {
      final obsolete = Completer<Object?>();
      final events = <String>[];
      final service = ApiHealthService(
        configUrl: primary,
        backupConfigUrls: const [backup],
        configCacheStore: _Store(),
        diagnosticRecorder: (event, _) => events.add(event),
        configLoader: (uri) => uri.host == 'primary.example'
            ? obsolete.future
            : Future.value(_config('backup-api.example')),
      );
      final response = service.loadConfig();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await response;
      obsolete.completeError(const SocketException('discarded native failure'));
      await tester.pump();
      expect(
        events.where((event) => event == 'api.config.attempt.failed'),
        isEmpty,
      );
    },
  );

  test(
    'source preference stays isolated by signing identity in an explicit memory pool',
    () async {
      final pool = ApiRemoteConfigMemoryCache();
      final signed = await _signedConfig();
      final a = ApiHealthService(
        configUrl: primary,
        backupConfigUrls: const [backup],
        memoryCache: pool,
        configCacheStore: _Store(),
        configLoader: (uri) async {
          if (uri.host == 'primary.example') {
            throw const SocketException('primary unavailable');
          }
          return _config('unsigned-api.example');
        },
      );
      await a.loadConfig();
      final requests = <Uri>[];
      final b = ApiHealthService(
        configUrl: primary,
        backupConfigUrls: const [backup],
        memoryCache: pool,
        configCacheStore: _Store(),
        aesKey: signed.aesKey,
        signingPublicKey: signed.signingKey,
        configLoader: (uri) async {
          requests.add(uri);
          return signed.payload;
        },
      );
      expect(
        parseApiEndpoints(await b.loadConfig()).single.host,
        'signed-api.example',
      );
      expect(requests.map((uri) => uri.host), ['primary.example']);
    },
  );

  test('a forged response cannot win before a fully signed backup', () async {
    final signed = await _signedConfig();
    final forged = Map<String, Object?>.from(signed.payload)
      ..['signature'] = encodeRemoteConfigBase64(List.filled(64, 0));
    final requests = <Uri>[];
    final service = ApiHealthService(
      configUrl: primary,
      backupConfigUrls: const [backup],
      configHedgeDelay: const Duration(seconds: 30),
      configCacheStore: _Store(),
      aesKey: signed.aesKey,
      signingPublicKey: signed.signingKey,
      configLoader: (uri) async {
        requests.add(uri);
        return uri.host == 'primary.example' ? forged : signed.payload;
      },
    );
    final config = await service.loadConfig().timeout(
      const Duration(seconds: 5),
    );
    expect(parseApiEndpoints(config).single.host, 'signed-api.example');
    expect(requests.map((uri) => uri.host), [
      'primary.example',
      'backup.example',
    ]);
  });

  test('default Dart HTTP cancels an already started losing response', () async {
    final previous = HttpOverrides.current;
    HttpOverrides.global = _DirectHttpOverrides();
    addTearDown(() => HttpOverrides.global = previous);
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final sockets = <Socket>[];
    final loserClosed = Completer<void>();
    final requests = <String>[];
    addTearDown(() async {
      for (final socket in sockets) {
        socket.destroy();
      }
      await server.close();
    });
    server.listen((socket) {
      sockets.add(socket);
      var buffer = '';
      var handled = false;
      var loser = false;
      void closed() {
        if (loser && !loserClosed.isCompleted) loserClosed.complete();
      }

      socket.listen(
        (bytes) {
          buffer += utf8.decode(bytes);
          if (handled || !buffer.contains('\r\n\r\n')) return;
          handled = true;
          final uri = Uri.parse(buffer.split(' ')[1]);
          requests.add(uri.path);
          loser = uri.path == '/primary';
          if (loser) {
            socket.write(
              'HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: 99999\r\nConnection: close\r\n\r\n{"Authentication":',
            );
          } else {
            final body = utf8.encode(jsonEncode(_config('backup-api.example')));
            socket.add(
              utf8.encode(
                'HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: ${body.length}\r\nConnection: close\r\n\r\n',
              ),
            );
            socket.add(body);
            unawaited(socket.close());
          }
        },
        onDone: closed,
        onError: (Object _) => closed(),
      );
    });
    final origin = 'http://${server.address.address}:${server.port}';
    final service = ApiHealthService(
      configUrl: '$origin/primary',
      backupConfigUrls: ['$origin/backup'],
      configCacheStore: _Store(),
    );
    final result = await service.loadConfig().timeout(
      const Duration(seconds: 5),
    );
    expect(parseApiEndpoints(result).single.host, 'backup-api.example');
    await loserClosed.future.timeout(const Duration(seconds: 3));
    expect(requests, ['/primary', '/backup']);
    expect(
      parseApiEndpoints(
        await service.loadConfig(forceRefresh: true),
      ).single.host,
      'backup-api.example',
    );
    expect(requests, ['/primary', '/backup', '/backup']);
  });
}

Map<String, Object?> _config(String host) => {
  'Authentication': 'FengWo',
  'hosts': ['https://$host'],
};

class _Store extends ApiRemoteConfigCacheStore {
  @override
  Future<String?> load() async => null;
  @override
  Future<void> save({
    required Object? encryptedConfig,
    required int candidateCount,
  }) async {}
  @override
  Future<void> clear() async {}
}

class _DirectHttpOverrides extends HttpOverrides {}

Future<({Map<String, Object?> payload, String aesKey, String signingKey})>
_signedConfig() async {
  final key = List<int>.generate(32, (index) => index + 1);
  final cipher = AesGcm.with256bits();
  final signing = await Ed25519().newKeyPair();
  final public = await signing.extractPublicKey();
  final nonce = List<int>.generate(12, (index) => index + 2);
  final payload = <String, Object?>{
    'format': remoteConfigFormat,
    'version': remoteConfigVersion,
    'alg': remoteConfigEncryptionAlgorithm,
    'sig': remoteConfigSignatureAlgorithm,
    'kid': remoteConfigKeyId(public.bytes),
  };
  final encrypted = await cipher.encrypt(
    utf8.encode(jsonEncode(_config('signed-api.example'))),
    secretKey: SecretKey(key),
    nonce: nonce,
    aad: remoteConfigAdditionalData(payload),
  );
  payload.addAll({
    'nonce': encodeRemoteConfigBase64(nonce),
    'ciphertext': encodeRemoteConfigBase64(encrypted.cipherText),
    'tag': encodeRemoteConfigBase64(encrypted.mac.bytes),
  });
  final signature = await Ed25519().sign(
    remoteConfigSignatureMessage(payload),
    keyPair: signing,
  );
  payload['signature'] = encodeRemoteConfigBase64(signature.bytes);
  return (
    payload: payload,
    aesKey: encodeRemoteConfigBase64(key),
    signingKey: encodeRemoteConfigBase64(public.bytes),
  );
}

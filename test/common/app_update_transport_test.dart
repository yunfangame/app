import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:dio/dio.dart';
import 'package:fl_clash/common/app_update.dart';
import 'package:fl_clash/common/remote_config_cipher.dart';
import 'package:flutter_test/flutter_test.dart';

const _testedPackage = String.fromEnvironment(
  'UPDATE_TEST_PACKAGE',
  defaultValue: 'windows-x64',
);

void main() {
  final primary = Uri.parse(appUpdateTrustedManifestUrls.first);
  final backup = Uri.parse(appUpdateTrustedManifestUrls.last);
  final events = <({String name, Map<String, Object?> fields})>[];

  AppUpdateService service({
    required AppUpdateManifestLoader loader,
    String? url,
    Duration timeout = const Duration(seconds: 1),
  }) {
    final result = AppUpdateService(
      mainConfigLoader: () async => {'UpdateUrl': url ?? primary.toString()},
      manifestLoader: loader,
      packageKeyResolver: () => _testedPackage,
      diagnosticRecorder: (name, fields) =>
          events.add((name: name, fields: fields)),
      attemptTimeout: timeout,
      retryDelay: Duration.zero,
      aesKey: '',
      signingPublicKey: '',
    );
    addTearDown(result.close);
    return result;
  }

  setUp(events.clear);

  test('only the exact known source pair enables built-in failover', () {
    expect(appUpdateManifestUrisFromConfig({'UpdateUrl': '$primary'}), [
      primary,
      backup,
    ]);
    expect(appUpdateManifestUrisFromConfig({'UpdateUrl': '$backup'}), [
      backup,
      primary,
    ]);
    for (final value in [
      'https://custom.example/fengwoupdate.json',
      '$primary?token=private',
      'https://house.zryc.tech.evil.example/fengwoupdate.json',
      'https://house.zryc.tech/another.json',
    ]) {
      expect(appUpdateManifestUrisFromConfig({'UpdateUrl': value}), [
        Uri.parse(value),
      ]);
    }
    expect(
      appUpdateManifestUrisFromConfig({
        'UpdateUrl': 'http://house.zryc.tech/fengwoupdate.json',
      }),
      isEmpty,
    );
  });

  for (final error in [
    const SocketException('Failed host lookup: private.example'),
    TimeoutException('private-token'),
    const HandshakeException('TLS handshake failed'),
  ]) {
    test(
      'verified backup recovers ${error.runtimeType} on the primary',
      () async {
        final calls = <Uri>[];
        final checker = service(
          loader: (uri) async {
            calls.add(uri);
            if (uri == primary) throw error;
            return _manifest();
          },
        );
        expect(
          (await checker.discoverUpdate(currentVersion: '1.0.11')).status,
          AppUpdateCheckStatus.upToDate,
        );
        expect(calls, [primary, backup]);
        expect(
          events.where((event) => event.name == 'app.update.source.fallback'),
          hasLength(1),
        );
        expect(events.last.fields['status'], 'upToDate');
        final encoded = jsonEncode(
          events
              .map((event) => {'name': event.name, 'fields': event.fields})
              .toList(),
        );
        expect(encoded, isNot(contains('private.example')));
        expect(encoded, isNot(contains('private-token')));
        expect(encoded, isNot(contains('$primary')));
      },
    );
  }

  test('an unresponsive primary is bounded and falls back', () async {
    final calls = <Uri>[];
    final checker = service(
      timeout: const Duration(milliseconds: 20),
      loader: (uri) {
        calls.add(uri);
        return uri == primary
            ? Completer<Object?>().future
            : Future.value(_manifest());
      },
    );
    expect(
      (await checker.discoverUpdate(currentVersion: '1.0.10')).status,
      AppUpdateCheckStatus.available,
    );
    expect(calls, [primary, backup]);
    expect(
      events
          .where((event) => event.name == 'app.update.source.attempt.failed')
          .single
          .fields['reason'],
      'timeout',
    );
  });

  test('transient failures have only two rounds across the pair', () async {
    final calls = <Uri>[];
    final checker = service(
      loader: (uri) async {
        calls.add(uri);
        throw const SocketException('offline');
      },
    );
    await expectLater(
      checker.discoverUpdate(currentVersion: '1.0.11'),
      throwsA(isA<SocketException>()),
    );
    expect(calls, [primary, backup, primary, backup]);
    expect(
      events.where((event) => event.name == 'app.update.retry.scheduled'),
      hasLength(1),
    );
    expect(events.last.name, 'app.update.check.failed');
  });

  test('a transient second round can recover', () async {
    final calls = <Uri>[];
    final checker = service(
      loader: (uri) async {
        calls.add(uri);
        if (calls.length < 3) throw const SocketException('temporary');
        return _manifest();
      },
    );
    expect(
      (await checker.discoverUpdate(currentVersion: '1.0.11')).status,
      AppUpdateCheckStatus.upToDate,
    );
    expect(calls, [primary, backup, primary]);
  });

  for (final status in [404, 429, 503]) {
    test('HTTP $status respects bounded retry classification', () async {
      final calls = <Uri>[];
      final checker = service(
        loader: (uri) async {
          calls.add(uri);
          final request = RequestOptions(path: '$uri');
          throw DioException.badResponse(
            statusCode: status,
            requestOptions: request,
            response: Response(requestOptions: request, statusCode: status),
          );
        },
      );
      await expectLater(
        checker.discoverUpdate(currentVersion: '1.0.11'),
        throwsA(isA<DioException>()),
      );
      expect(
        calls,
        status == 404 ? [primary, backup] : [primary, backup, primary, backup],
      );
      expect(
        events
            .where((event) => event.name == 'app.update.source.attempt.failed')
            .first
            .fields['http_status'],
        status,
      );
    });
  }

  test('invalid manifests never become a successful latest result', () async {
    final calls = <Uri>[];
    final checker = service(
      loader: (uri) async {
        calls.add(uri);
        return {'format': 'not-an-update'};
      },
    );
    await expectLater(
      checker.discoverUpdate(currentVersion: '1.0.11'),
      throwsFormatException,
    );
    expect(calls, [primary, backup]);
    expect(
      events
          .where((event) => event.name == 'app.update.source.attempt.failed')
          .every((event) => event.fields['reason'] == 'manifest_format'),
      isTrue,
    );
  });

  test(
    'a signature error remains visible if the other source is offline',
    () async {
      final calls = <Uri>[];
      final checker = service(
        loader: (uri) async {
          calls.add(uri);
          if (uri == primary) {
            throw const RemoteConfigCipherException(
              RemoteConfigCipherFailure.signature,
              'private-signature-details',
            );
          }
          throw const SocketException('offline');
        },
      );
      await expectLater(
        checker.discoverUpdate(currentVersion: '1.0.11'),
        throwsA(isA<RemoteConfigCipherException>()),
      );
      expect(calls, [primary, backup, backup]);
      expect(events.last.fields['reason'], 'config_signature');
      expect(
        jsonEncode(events.map((event) => event.fields).toList()),
        isNot(contains('private-signature-details')),
      );
    },
  );

  for (final disabled in [false, true]) {
    test(
      'a valid ${disabled ? 'disabled' : 'current'} primary never consults backup',
      () async {
        final calls = <Uri>[];
        final checker = service(
          loader: (uri) async {
            calls.add(uri);
            return _manifest(enabled: !disabled);
          },
        );
        expect(
          (await checker.discoverUpdate(currentVersion: '1.0.11')).status,
          disabled
              ? AppUpdateCheckStatus.unavailable
              : AppUpdateCheckStatus.upToDate,
        );
        expect(calls, [primary]);
      },
    );
  }

  test('recorder errors cannot break a successful check', () async {
    final checker = AppUpdateService(
      mainConfigLoader: () async => {'UpdateUrl': '$primary'},
      manifestLoader: (_) async => _manifest(),
      packageKeyResolver: () => 'windows-arm64',
      diagnosticRecorder: (_, _) => throw StateError('log unavailable'),
      aesKey: '',
      signingPublicKey: '',
    );
    addTearDown(checker.close);
    expect(
      (await checker.discoverUpdate(currentVersion: '1.0.11')).status,
      AppUpdateCheckStatus.upToDate,
    );
  });

  test('closing during a request prevents failover and retry', () async {
    final pending = Completer<Object?>();
    final calls = <Uri>[];
    final checker = service(
      loader: (uri) {
        calls.add(uri);
        return pending.future;
      },
    );
    final operation = checker.discoverUpdate(currentVersion: '1.0.11');
    await Future<void>.delayed(Duration.zero);
    checker.close();
    pending.completeError(const SocketException('closed'));
    await expectLater(operation, throwsStateError);
    expect(calls, [primary]);
  });

  for (final unsignedBackup in [false, true]) {
    test(
      'tampered primary requires a verified backup ($unsignedBackup)',
      () async {
        final fixture = await _signedManifest();
        final tampered = Map<String, Object?>.of(fixture.envelope);
        final signature = decodeRemoteConfigBase64(
          tampered['signature'] as String,
        );
        signature[0] ^= 1;
        tampered['signature'] = encodeRemoteConfigBase64(signature);
        final calls = <Uri>[];
        final checker = AppUpdateService(
          mainConfigLoader: () async => {'UpdateUrl': '$primary'},
          manifestLoader: (uri) async {
            calls.add(uri);
            if (uri == primary) return tampered;
            return unsignedBackup ? _manifest() : fixture.envelope;
          },
          packageKeyResolver: () => _testedPackage,
          diagnosticRecorder: (name, fields) =>
              events.add((name: name, fields: fields)),
          retryDelay: Duration.zero,
          aesKey: fixture.aesKey,
          signingPublicKey: fixture.publicKey,
        );
        addTearDown(checker.close);
        if (unsignedBackup) {
          await expectLater(
            checker.discoverUpdate(currentVersion: '1.0.11'),
            throwsA(isA<RemoteConfigCipherException>()),
          );
          expect(events.last.name, 'app.update.check.failed');
          expect(events.last.fields['reason'], 'config_signature');
        } else {
          expect(
            (await checker.discoverUpdate(currentVersion: '1.0.11')).status,
            AppUpdateCheckStatus.upToDate,
          );
        }
        expect(calls, [primary, backup]);
        expect(
          events
              .where(
                (event) => event.name == 'app.update.source.attempt.failed',
              )
              .first
              .fields['reason'],
          'config_signature',
        );
      },
    );
  }

  for (final certificate in ['valid_a', 'valid_b', 'wrong_host', 'expired']) {
    test(
      'default HTTPS transport ignores global proxy and ${certificate == 'valid_a' ? 'accepts trusted TLS' : 'rejects untrusted TLS'}',
      () async {
        final context = SecurityContext(withTrustedRoots: false)
          ..useCertificateChain('test/fixtures/tls/$certificate.pem')
          ..usePrivateKey('test/fixtures/tls/${certificate}_test_key.pem');
        final server = await HttpServer.bindSecure(
          InternetAddress.loopbackIPv4,
          0,
          context,
        );
        addTearDown(() => server.close(force: true));
        final requests = <HttpRequest>[];
        final subscription = server.listen((request) {
          requests.add(request);
          request.response
            ..headers.contentType = ContentType.json
            ..write(jsonEncode(_manifest()));
          unawaited(request.response.close());
        }, onError: (Object _) {});
        addTearDown(subscription.cancel);
        final previous = HttpOverrides.current;
        final overrides = _ProxyHttpOverrides();
        HttpOverrides.global = overrides;
        addTearDown(() => HttpOverrides.global = previous);
        final checker = AppUpdateService(
          mainConfigLoader: () async => {
            'UpdateUrl': 'https://127.0.0.1:${server.port}/fengwoupdate.json',
          },
          packageKeyResolver: () => _testedPackage,
          diagnosticRecorder: (_, _) {},
          retryDelay: Duration.zero,
          aesKey: '',
          signingPublicKey: '',
        );
        addTearDown(checker.close);
        if (certificate == 'valid_a') {
          expect(
            (await checker.discoverUpdate(currentVersion: '1.0.11')).status,
            AppUpdateCheckStatus.upToDate,
          );
          expect(requests, hasLength(1));
          expect(requests.single.headers.value('cache-control'), 'no-cache');
        } else {
          await expectLater(
            checker.discoverUpdate(currentVersion: '1.0.11'),
            throwsA(isA<DioException>()),
          );
          expect(requests, isEmpty);
        }
        expect(overrides.proxyQueries, 0);
        expect(overrides.clients, greaterThan(0));
      },
    );
  }
}

Map<String, Object?> _manifest({bool enabled = true}) => {
  'Authentication': 'FengWo',
  'format': 'fengwo-update',
  'schemaVersion': 1,
  'packages': {
    for (final key in [
      'windows-x64',
      'windows-arm64',
      'android-arm64-v8a',
      'android-armeabi-v7a',
      'android-x86_64',
      'macos-arm64',
      'macos-x64',
    ])
      key: {
        'enabled': enabled,
        'version': '1.0.11',
        'downloadUrl': 'https://downloads.example/$key.exe',
      },
  },
};

class _ProxyHttpOverrides extends HttpOverrides {
  int proxyQueries = 0;
  int clients = 0;

  @override
  HttpClient createHttpClient(SecurityContext? context) {
    clients++;
    final der = File('test/fixtures/tls/root_a.der').readAsBytesSync();
    final trusted = SecurityContext(withTrustedRoots: false)
      ..setTrustedCertificatesBytes(
        utf8.encode(
          '-----BEGIN CERTIFICATE-----\n${base64Encode(der)}\n-----END CERTIFICATE-----\n',
        ),
      );
    final client = super.createHttpClient(trusted);
    client.findProxy = (_) {
      proxyQueries++;
      return 'PROXY 127.0.0.1:1';
    };
    return client;
  }
}

Future<({Map<String, Object?> envelope, String aesKey, String publicKey})>
_signedManifest() async {
  final cipher = AesGcm.with256bits();
  final key = await cipher.newSecretKey();
  final signingKey = await Ed25519().newKeyPair();
  final publicKey = await signingKey.extractPublicKey();
  final envelope = <String, Object?>{
    'format': remoteConfigFormat,
    'version': remoteConfigVersion,
    'alg': remoteConfigEncryptionAlgorithm,
    'sig': remoteConfigSignatureAlgorithm,
    'kid': remoteConfigKeyId(publicKey.bytes),
  };
  final encrypted = await cipher.encrypt(
    utf8.encode(jsonEncode(_manifest())),
    secretKey: key,
    aad: remoteConfigAdditionalData(envelope),
  );
  envelope.addAll({
    'nonce': encodeRemoteConfigBase64(encrypted.nonce),
    'ciphertext': encodeRemoteConfigBase64(encrypted.cipherText),
    'tag': encodeRemoteConfigBase64(encrypted.mac.bytes),
  });
  final signature = await Ed25519().sign(
    remoteConfigSignatureMessage(envelope),
    keyPair: signingKey,
  );
  envelope['signature'] = encodeRemoteConfigBase64(signature.bytes);
  return (
    envelope: envelope,
    aesKey: encodeRemoteConfigBase64(await key.extractBytes()),
    publicKey: encodeRemoteConfigBase64(publicKey.bytes),
  );
}

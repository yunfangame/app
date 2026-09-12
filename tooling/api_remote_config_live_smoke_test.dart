import 'dart:convert';
import 'dart:io';

import 'package:fl_clash/common/api_health.dart';
import 'package:fl_clash/common/api_remote_config_cache.dart';
import 'package:fl_clash/common/remote_config_cipher.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null;
  late String aesKey;
  late String signingPublicKey;

  setUpAll(() async {
    final keys =
        jsonDecode(await File('tooling/remote_config/keys.json').readAsString())
            as Map<String, dynamic>;
    aesKey = keys['aesKey'] as String;
    signingPublicKey = keys['signingPublicKey'] as String;
    expect(aesKey.isNotEmpty && signingPublicKey.isNotEmpty, isTrue);
  });

  setUp(() => SharedPreferences.setMockInitialValues({}));

  for (final source in {
    'primary': apiHealthConfigUrl,
    'backup': apiHealthBackupConfigUrl,
  }.entries) {
    test(
      '${source.key} live configuration decrypts and APIs respond',
      () async {
        final service = ApiHealthService(
          configUrl: source.value,
          backupConfigUrls: const [],
          aesKey: aesKey,
          signingPublicKey: signingPublicKey,
          diagnosticRecorder: (_, _) {},
        );
        final snapshot = await service.check();
        expect(snapshot.error, isNull);
        expect(snapshot.total, greaterThan(0));
        for (var index = 0; index < snapshot.total; index++) {
          expect(
            snapshot.endpoints[index].reachable,
            isTrue,
            reason:
                '${source.key} API ${index + 1} must return valid guest config',
          );
        }
        final payload = await ApiRemoteConfigCacheStore().load();
        expect(payload, isA<String>());
        final envelope = jsonDecode(payload! as String) as Map<String, dynamic>;
        expect(envelope['alg'], 'A256GCM');
        expect(envelope['sig'], 'Ed25519');
        final tampered = Map<String, dynamic>.of(envelope);
        final signature = decodeRemoteConfigBase64(
          envelope['signature'] as String,
        );
        signature[0] ^= 1;
        tampered['signature'] = encodeRemoteConfigBase64(signature);
        await expectLater(
          decodeEncryptedRemoteConfig(
            tampered,
            aesKey: aesKey,
            signingPublicKey: signingPublicKey,
          ),
          throwsA(
            isA<RemoteConfigCipherException>().having(
              (error) => error.failure,
              'failure',
              RemoteConfigCipherFailure.signature,
            ),
          ),
        );
        final wrongKey = decodeRemoteConfigBase64(aesKey);
        wrongKey[0] ^= 1;
        await expectLater(
          decodeEncryptedRemoteConfig(
            envelope,
            aesKey: encodeRemoteConfigBase64(wrongKey),
            signingPublicKey: signingPublicKey,
          ),
          throwsA(
            isA<RemoteConfigCipherException>().having(
              (error) => error.failure,
              'failure',
              RemoteConfigCipherFailure.decryption,
            ),
          ),
        );
        final offline = ApiHealthService(
          configLoader: (_) async => throw const SocketException('offline'),
          aesKey: aesKey,
          signingPublicKey: signingPublicKey,
          configRetryDelays: const [Duration.zero],
          diagnosticRecorder: (_, _) {},
        );
        expect(
          await offline.loadCandidateEndpoints(),
          hasLength(snapshot.total),
        );
        stdout.writeln(
          '${source.key}: signature/decryption/tamper/wrong-key/cache passed; APIs ${snapshot.reachableCount}/${snapshot.total}',
        );
      },
      timeout: const Timeout(Duration(minutes: 2)),
    );
  }

  test('bundled emergency configuration decrypts with release keys', () async {
    final payload = await File(apiHealthEmergencyConfigAsset).readAsString();
    final config = await decodeEncryptedRemoteConfig(
      payload,
      aesKey: aesKey,
      signingPublicKey: signingPublicKey,
    );
    expect(parseApiEndpoints(decodeApiHealthConfig(config)), isNotEmpty);
  });
}

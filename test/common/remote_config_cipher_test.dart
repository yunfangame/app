import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:fl_clash/common/remote_config_cipher.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('decrypts a signed AES-GCM remote config envelope', () async {
    final fixture = await _createFixture();

    final decoded = await decodeEncryptedRemoteConfig(
      jsonEncode(fixture.envelope),
      aesKey: fixture.aesKey,
      signingPublicKey: fixture.signingPublicKey,
    );

    expect(decoded, {
      'Authentication': 'FengWo',
      'hosts': ['https://api.example.com'],
    });
  });

  test('rejects a ciphertext changed after signing', () async {
    final fixture = await _createFixture();
    final ciphertext = fixture.envelope['ciphertext'] as String;
    fixture.envelope['ciphertext'] =
        '${ciphertext.substring(0, ciphertext.length - 1)}'
        '${ciphertext.endsWith('A') ? 'B' : 'A'}';

    expect(
      () => decodeEncryptedRemoteConfig(
        fixture.envelope,
        aesKey: fixture.aesKey,
        signingPublicKey: fixture.signingPublicKey,
      ),
      throwsA(
        isA<RemoteConfigCipherException>().having(
          (error) => error.failure,
          'failure',
          RemoteConfigCipherFailure.signature,
        ),
      ),
    );
  });

  test('rejects an envelope signed by another key', () async {
    final fixture = await _createFixture();
    final otherPublicKey = await Ed25519().newKeyPair().then(
      (keyPair) => keyPair.extractPublicKey(),
    );

    expect(
      () => decodeEncryptedRemoteConfig(
        fixture.envelope,
        aesKey: fixture.aesKey,
        signingPublicKey: encodeRemoteConfigBase64(otherPublicKey.bytes),
      ),
      throwsA(
        isA<RemoteConfigCipherException>().having(
          (error) => error.failure,
          'failure',
          RemoteConfigCipherFailure.keyMismatch,
        ),
      ),
    );
  });
}

Future<_CipherFixture> _createFixture() async {
  final algorithm = AesGcm.with256bits();
  final aesKey = await algorithm.newSecretKey();
  final aesKeyBytes = await aesKey.extractBytes();
  final signingKeyPair = await Ed25519().newKeyPair();
  final signingPublicKey = await signingKeyPair.extractPublicKey();
  final envelope = <String, Object?>{
    'format': remoteConfigFormat,
    'version': remoteConfigVersion,
    'alg': remoteConfigEncryptionAlgorithm,
    'sig': remoteConfigSignatureAlgorithm,
    'kid': remoteConfigKeyId(signingPublicKey.bytes),
  };
  final clearConfig = {
    'Authentication': 'FengWo',
    'hosts': ['https://api.example.com'],
  };
  final secretBox = await algorithm.encrypt(
    utf8.encode(jsonEncode(clearConfig)),
    secretKey: aesKey,
    nonce: algorithm.newNonce(),
    aad: remoteConfigAdditionalData(envelope),
  );
  envelope.addAll({
    'nonce': encodeRemoteConfigBase64(secretBox.nonce),
    'ciphertext': encodeRemoteConfigBase64(secretBox.cipherText),
    'tag': encodeRemoteConfigBase64(secretBox.mac.bytes),
  });
  final signature = await Ed25519().sign(
    remoteConfigSignatureMessage(envelope),
    keyPair: signingKeyPair,
  );
  envelope['signature'] = encodeRemoteConfigBase64(signature.bytes);
  return _CipherFixture(
    envelope: envelope,
    aesKey: encodeRemoteConfigBase64(aesKeyBytes),
    signingPublicKey: encodeRemoteConfigBase64(signingPublicKey.bytes),
  );
}

class _CipherFixture {
  const _CipherFixture({
    required this.envelope,
    required this.aesKey,
    required this.signingPublicKey,
  });

  final Map<String, Object?> envelope;
  final String aesKey;
  final String signingPublicKey;
}

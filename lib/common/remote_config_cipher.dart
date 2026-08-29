import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:cryptography/cryptography.dart';

const remoteConfigAesKey = String.fromEnvironment('REMOTE_CONFIG_AES_KEY');
const remoteConfigSigningPublicKey = String.fromEnvironment(
  'REMOTE_CONFIG_SIGNING_PUBLIC_KEY',
);

const remoteConfigFormat = 'fengwo-config';
const remoteConfigVersion = 1;
const remoteConfigEncryptionAlgorithm = 'A256GCM';
const remoteConfigSignatureAlgorithm = 'Ed25519';

Future<Object?> decodeEncryptedRemoteConfig(
  Object? payload, {
  required String aesKey,
  required String signingPublicKey,
}) async {
  final envelope = _decodeEnvelope(payload);
  _validateEnvelope(envelope);

  final keyBytes = decodeRemoteConfigBase64(aesKey);
  final publicKeyBytes = decodeRemoteConfigBase64(signingPublicKey);
  final nonce = decodeRemoteConfigBase64(envelope['nonce'] as String);
  final ciphertext = decodeRemoteConfigBase64(envelope['ciphertext'] as String);
  final tag = decodeRemoteConfigBase64(envelope['tag'] as String);
  final signatureBytes = decodeRemoteConfigBase64(
    envelope['signature'] as String,
  );

  if (keyBytes.length != 32 ||
      publicKeyBytes.length != 32 ||
      nonce.length != 12 ||
      tag.length != 16 ||
      signatureBytes.length != 64) {
    throw const FormatException('Invalid remote config key material');
  }

  final expectedKeyId = remoteConfigKeyId(publicKeyBytes);
  if (envelope['kid'] != expectedKeyId) {
    throw const FormatException('Remote config key ID mismatch');
  }

  final signatureMessage = remoteConfigSignatureMessage(envelope);
  final verified = await Ed25519().verify(
    signatureMessage,
    signature: Signature(
      signatureBytes,
      publicKey: SimplePublicKey(publicKeyBytes, type: KeyPairType.ed25519),
    ),
  );
  if (!verified) {
    throw const FormatException('Remote config signature verification failed');
  }

  final clearBytes = await AesGcm.with256bits().decrypt(
    SecretBox(ciphertext, nonce: nonce, mac: Mac(tag)),
    secretKey: SecretKey(keyBytes),
    aad: remoteConfigAdditionalData(envelope),
  );
  final decoded = jsonDecode(utf8.decode(clearBytes));
  if (decoded is! Map && decoded is! List) {
    throw const FormatException('Invalid decrypted remote config');
  }
  return decoded;
}

List<int> remoteConfigAdditionalData(Map<String, Object?> envelope) {
  return utf8.encode(
    '${envelope['format']}\n'
    '${envelope['version']}\n'
    '${envelope['alg']}\n'
    '${envelope['sig']}\n'
    '${envelope['kid']}',
  );
}

List<int> remoteConfigSignatureMessage(Map<String, Object?> envelope) {
  return utf8.encode(
    '${envelope['format']}\n'
    '${envelope['version']}\n'
    '${envelope['alg']}\n'
    '${envelope['sig']}\n'
    '${envelope['kid']}\n'
    '${envelope['nonce']}\n'
    '${envelope['ciphertext']}\n'
    '${envelope['tag']}',
  );
}

String remoteConfigKeyId(List<int> publicKeyBytes) {
  return sha256.convert(publicKeyBytes).toString().substring(0, 16);
}

String encodeRemoteConfigBase64(List<int> bytes) {
  return base64UrlEncode(bytes).replaceAll('=', '');
}

List<int> decodeRemoteConfigBase64(String value) {
  try {
    return base64Url.decode(base64Url.normalize(value.trim()));
  } on FormatException {
    throw const FormatException('Invalid remote config Base64URL value');
  }
}

Map<String, Object?> _decodeEnvelope(Object? payload) {
  Object? decoded = payload;
  if (payload is List<int>) {
    decoded = utf8.decode(payload);
  }
  if (decoded is String) {
    decoded = jsonDecode(decoded.trim());
  }
  if (decoded is! Map) {
    throw const FormatException('Invalid remote config envelope');
  }
  return decoded.map((key, value) => MapEntry(key.toString(), value));
}

void _validateEnvelope(Map<String, Object?> envelope) {
  if (envelope['format'] != remoteConfigFormat ||
      envelope['version'] != remoteConfigVersion ||
      envelope['alg'] != remoteConfigEncryptionAlgorithm ||
      envelope['sig'] != remoteConfigSignatureAlgorithm) {
    throw const FormatException('Unsupported remote config envelope');
  }
  for (final key in ['kid', 'nonce', 'ciphertext', 'tag', 'signature']) {
    if (envelope[key] is! String || (envelope[key] as String).isEmpty) {
      throw const FormatException('Incomplete remote config envelope');
    }
  }
}

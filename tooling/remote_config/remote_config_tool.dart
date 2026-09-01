import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:fl_clash/common/remote_config_cipher.dart';

const defaultKeysPath = 'tooling/remote_config/keys.json';
const defaultSourcePath = 'tooling/remote_config/ConFigOss4.source.json';
const defaultOutputPath = 'tooling/remote_config/ConFigOss4.json';

Future<void> main(List<String> arguments) async {
  if (arguments.isEmpty ||
      !{'keygen', 'seal', 'verify', 'merge-v2'}.contains(arguments[0])) {
    stderr.writeln(
      'Usage: dart run tooling/remote_config/remote_config_tool.dart '
      '<keygen|seal|verify|merge-v2> [path]',
    );
    exitCode = 64;
    return;
  }
  switch (arguments[0]) {
    case 'keygen':
      await _generateKeys(arguments.elementAtOrNull(1) ?? defaultKeysPath);
      return;
    case 'seal':
      await _seal(
        sourcePath: arguments.elementAtOrNull(1) ?? defaultSourcePath,
        outputPath: arguments.elementAtOrNull(2) ?? defaultOutputPath,
        keysPath: arguments.elementAtOrNull(3) ?? defaultKeysPath,
      );
      return;
    case 'verify':
      await _verify(
        inputPath: arguments.elementAtOrNull(1) ?? defaultOutputPath,
        keysPath: arguments.elementAtOrNull(2) ?? defaultKeysPath,
      );
      return;
    case 'merge-v2':
      await _mergeSubscriptionV2(
        sourcePath: arguments.elementAtOrNull(1) ?? defaultSourcePath,
        publicConfigPath: arguments.elementAtOrNull(2) ?? '',
        enabled: switch (arguments.elementAtOrNull(3)) {
          'true' => true,
          'false' => false,
          _ => null,
        },
      );
      return;
  }
}

Future<void> _mergeSubscriptionV2({
  required String sourcePath,
  required String publicConfigPath,
  required bool? enabled,
}) async {
  if (publicConfigPath.isEmpty) {
    throw const FormatException('V2 public config path is required');
  }
  final source = jsonDecode(await File(sourcePath).readAsString());
  final publicConfig = jsonDecode(await File(publicConfigPath).readAsString());
  if (source is! Map || publicConfig is! Map) {
    throw const FormatException('V2 config inputs must be JSON objects');
  }
  final gatewayPath = publicConfig['gatewayPath']?.toString() ?? '';
  final gateway = Uri.tryParse(gatewayPath);
  final keyId = publicConfig['keyId']?.toString() ?? '';
  final encryptionKey = decodeRemoteConfigBase64(
    publicConfig['serverEncryptionPublicKey']?.toString() ?? '',
  );
  final signingKey = decodeRemoteConfigBase64(
    publicConfig['serverSigningPublicKey']?.toString() ?? '',
  );
  if (gateway == null ||
      gateway.isAbsolute ||
      !gatewayPath.startsWith('/api/v2/') ||
      gateway.hasQuery ||
      gateway.hasFragment ||
      keyId.isEmpty ||
      encryptionKey.length != 32 ||
      signingKey.length != 32) {
    throw const FormatException('Invalid V2 public config');
  }
  final updated = Map<String, Object?>.from(
    source.map((key, value) => MapEntry(key.toString(), value)),
  );
  updated['subscriptionV2'] = <String, Object?>{
    'enabled': enabled ?? (publicConfig['enabled'] == true),
    'gatewayPath': gatewayPath,
    'keyId': keyId,
    'serverEncryptionPublicKey': publicConfig['serverEncryptionPublicKey'],
    'serverSigningPublicKey': publicConfig['serverSigningPublicKey'],
  };
  final sourceFile = File(sourcePath);
  final temporary = File('$sourcePath.subscription-v2.tmp');
  await temporary.writeAsString(
    '${const JsonEncoder.withIndent('  ').convert(updated)}\n',
    flush: true,
  );
  await temporary.rename(sourceFile.path);
  stdout.writeln('Updated V2 public config in $sourcePath');
}

Future<void> _generateKeys(String keysPath) async {
  final file = File(keysPath);
  if (await file.exists()) {
    throw StateError('Key file already exists: $keysPath');
  }
  await file.parent.create(recursive: true);
  final aesKey = await AesGcm.with256bits().newSecretKey();
  final signingKeyPair = await Ed25519().newKeyPair();
  final signingPublicKey = await signingKeyPair.extractPublicKey();
  final payload = {
    'aesKey': encodeRemoteConfigBase64(await aesKey.extractBytes()),
    'signingPrivateKey': encodeRemoteConfigBase64(
      await signingKeyPair.extractPrivateKeyBytes(),
    ),
    'signingPublicKey': encodeRemoteConfigBase64(signingPublicKey.bytes),
  };
  await file.writeAsString(
    '${const JsonEncoder.withIndent('  ').convert(payload)}\n',
    flush: true,
  );
  if (!Platform.isWindows) {
    await Process.run('chmod', ['600', file.path]);
  }
  stdout.writeln('Generated private key material at $keysPath');
}

Future<void> _seal({
  required String sourcePath,
  required String outputPath,
  required String keysPath,
}) async {
  final keys = await _readKeys(keysPath);
  final source = jsonDecode(await File(sourcePath).readAsString());
  if (source is! Map && source is! List) {
    throw const FormatException('Remote config source must be JSON');
  }
  final aesKeyBytes = decodeRemoteConfigBase64(keys.aesKey);
  final publicKeyBytes = decodeRemoteConfigBase64(keys.signingPublicKey);
  final nonce = AesGcm.with256bits().newNonce();
  final envelope = <String, Object?>{
    'format': remoteConfigFormat,
    'version': remoteConfigVersion,
    'alg': remoteConfigEncryptionAlgorithm,
    'sig': remoteConfigSignatureAlgorithm,
    'kid': remoteConfigKeyId(publicKeyBytes),
  };
  final secretBox = await AesGcm.with256bits().encrypt(
    utf8.encode(jsonEncode(source)),
    secretKey: SecretKey(aesKeyBytes),
    nonce: nonce,
    aad: remoteConfigAdditionalData(envelope),
  );
  envelope.addAll({
    'nonce': encodeRemoteConfigBase64(secretBox.nonce),
    'ciphertext': encodeRemoteConfigBase64(secretBox.cipherText),
    'tag': encodeRemoteConfigBase64(secretBox.mac.bytes),
  });
  final privateKeyBytes = decodeRemoteConfigBase64(keys.signingPrivateKey);
  final signingKeyPair = SimpleKeyPairData(
    privateKeyBytes,
    publicKey: SimplePublicKey(publicKeyBytes, type: KeyPairType.ed25519),
    type: KeyPairType.ed25519,
  );
  final signature = await Ed25519().sign(
    remoteConfigSignatureMessage(envelope),
    keyPair: signingKeyPair,
  );
  envelope['signature'] = encodeRemoteConfigBase64(signature.bytes);
  final output = File(outputPath);
  await output.parent.create(recursive: true);
  await output.writeAsString('${jsonEncode(envelope)}\n', flush: true);
  stdout.writeln('Generated encrypted config at $outputPath');
}

Future<void> _verify({
  required String inputPath,
  required String keysPath,
}) async {
  final keys = await _readKeys(keysPath);
  final decoded = await decodeEncryptedRemoteConfig(
    await File(inputPath).readAsString(),
    aesKey: keys.aesKey,
    signingPublicKey: keys.signingPublicKey,
  );
  if (decoded is! Map || decoded['Authentication'] != 'FengWo') {
    throw const FormatException('Decrypted config validation failed');
  }
  stdout.writeln('Verified encrypted config at $inputPath');
}

Future<_RemoteConfigKeys> _readKeys(String keysPath) async {
  final decoded = jsonDecode(await File(keysPath).readAsString());
  if (decoded is! Map ||
      decoded['aesKey'] is! String ||
      decoded['signingPrivateKey'] is! String ||
      decoded['signingPublicKey'] is! String) {
    throw const FormatException('Invalid remote config key file');
  }
  return _RemoteConfigKeys(
    aesKey: decoded['aesKey'] as String,
    signingPrivateKey: decoded['signingPrivateKey'] as String,
    signingPublicKey: decoded['signingPublicKey'] as String,
  );
}

class _RemoteConfigKeys {
  const _RemoteConfigKeys({
    required this.aesKey,
    required this.signingPrivateKey,
    required this.signingPublicKey,
  });

  final String aesKey;
  final String signingPrivateKey;
  final String signingPublicKey;
}

extension<T> on List<T> {
  T? elementAtOrNull(int index) => index < length ? this[index] : null;
}

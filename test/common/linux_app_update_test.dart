import 'dart:convert';
import 'dart:ffi';

import 'package:cryptography/cryptography.dart';
import 'package:fl_clash/common/app_update.dart';
import 'package:fl_clash/common/remote_config_cipher.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _manifestUrl = 'https://download.example/releases/fengwoupdate.json';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test(
    'Linux x64 loads main config and selects only its DEB package',
    () async {
      var mainConfigLoads = 0;
      final manifestRequests = <Uri>[];
      final manifest = _manifest();
      final service = AppUpdateService(
        mainConfigLoader: () async {
          mainConfigLoads++;
          return {'UpdateUrl': _manifestUrl};
        },
        manifestLoader: (uri) async {
          manifestRequests.add(uri);
          return manifest;
        },
        packageKeyResolver: () => appUpdatePackageKeyForAbi(Abi.linuxX64),
        aesKey: '',
        signingPublicKey: '',
      );

      final release = await service.checkForUpdate(currentVersion: '1.0.2');

      expect(mainConfigLoads, 1);
      expect(manifestRequests, [Uri.parse(_manifestUrl)]);
      expect(release, isNotNull);
      expect(release!.packageKey, 'linux-x64');
      expect(release.version, '1.0.3');
      expect(
        release.downloadUri.toString(),
        'https://download.example/releases/FlClash-1.0.3-linux-amd64.deb',
      );
      expect(release.title, 'Linux update');
      expect(release.releaseNotesHtml, '<p>Linux x64 update</p>');
      expect(release.sha256, 'a' * 64);
      expect(release.publishedAt, DateTime.utc(2026, 9, 15));
    },
  );

  for (final version in ['1.0.1', '1.0.2']) {
    test('Linux $version does not update installed 1.0.2', () async {
      final service = _service(manifest: _manifest(version: version));

      expect(await service.checkForUpdate(currentVersion: '1.0.2'), isNull);
    });
  }

  test(
    'a disabled Linux package never falls back to another platform',
    () async {
      final service = _service(manifest: _manifest(enabled: false));

      expect(await service.checkForUpdate(currentVersion: '1.0.2'), isNull);
    },
  );

  test(
    'a missing Linux package never falls back to another platform',
    () async {
      final service = _service(manifest: _manifest(includeLinux: false));

      expect(await service.checkForUpdate(currentVersion: '1.0.2'), isNull);
    },
  );

  test('Linux missing UpdateUrl reports the existing configuration error', () {
    final service = AppUpdateService(
      mainConfigLoader: () async => <String, Object?>{},
      manifestLoader: (_) async => fail('No manifest URL was configured'),
      packageKeyResolver: () => appUpdatePackageKeyForAbi(Abi.linuxX64),
      aesKey: '',
      signingPublicKey: '',
    );

    expect(
      () => service.checkForUpdate(currentVersion: '1.0.2'),
      throwsFormatException,
    );
  });

  for (final abi in [
    Abi.linuxArm,
    Abi.linuxArm64,
    Abi.linuxIA32,
    Abi.linuxRiscv32,
    Abi.linuxRiscv64,
  ]) {
    test('$abi remains unsupported and performs no update requests', () async {
      expect(appUpdatePackageKeyForAbi(abi), isNull);
      final service = AppUpdateService(
        mainConfigLoader: () async => fail('Unsupported ABI loaded config'),
        manifestLoader: (_) async => fail('Unsupported ABI loaded manifest'),
        packageKeyResolver: () => appUpdatePackageKeyForAbi(abi),
        aesKey: '',
        signingPublicKey: '',
      );

      expect(await service.checkForUpdate(currentVersion: '1.0.2'), isNull);
    });
  }

  test(
    'an ignored Linux version is skipped except for manual checks',
    () async {
      final service = _service(manifest: _manifest());
      final release = await service.checkForUpdate(currentVersion: '1.0.2');
      expect(release, isNotNull);

      await service.ignore(release!);

      expect(await service.checkForUpdate(currentVersion: '1.0.2'), isNull);
      final manualRelease = await service.checkForUpdate(
        currentVersion: '1.0.2',
        respectIgnored: false,
      );
      expect(manualRelease?.packageKey, 'linux-x64');
      expect(manualRelease?.version, '1.0.3');
      final nextVersionService = _service(
        manifest: _manifest(version: '1.0.4'),
      );
      expect(
        (await nextVersionService.checkForUpdate(
          currentVersion: '1.0.2',
        ))?.version,
        '1.0.4',
      );
    },
  );

  test(
    'ignoring the same version for another platform preserves Linux',
    () async {
      final preferences = AppUpdatePreferenceStore();
      await preferences.ignore('windows-x64', '1.0.3');
      await preferences.ignore('macos-x64', '1.0.3');
      final service = _service(manifest: _manifest());

      expect(
        (await service.checkForUpdate(currentVersion: '1.0.2'))?.packageKey,
        'linux-x64',
      );
    },
  );

  test('ignoring Linux leaves Windows updates available', () async {
    final preferences = AppUpdatePreferenceStore();
    await preferences.ignore('linux-x64', '9.0.0');
    final service = _service(manifest: _manifest(), abi: Abi.windowsX64);

    final release = await service.checkForUpdate(currentVersion: '1.0.2');
    expect(release?.packageKey, 'windows-x64');
    expect(release?.version, '9.0.0');
  });

  for (final encoding in ['map', 'json', 'bytes']) {
    test('Linux accepts a signed encrypted $encoding manifest', () async {
      final fixture = await _encryptManifest(_manifest());
      final Object payload = switch (encoding) {
        'json' => jsonEncode(fixture.envelope),
        'bytes' => utf8.encode(jsonEncode(fixture.envelope)),
        _ => fixture.envelope,
      };
      final service = _service(
        manifest: payload,
        aesKey: fixture.aesKey,
        signingPublicKey: fixture.signingPublicKey,
      );

      final release = await service.checkForUpdate(currentVersion: '1.0.2');

      expect(release?.packageKey, 'linux-x64');
      expect(release?.version, '1.0.3');
    });
  }

  test('Linux rejects a signed manifest modified after encryption', () async {
    final fixture = await _encryptManifest(_manifest());
    final ciphertext = decodeRemoteConfigBase64(
      fixture.envelope['ciphertext']! as String,
    );
    ciphertext[0] ^= 1;
    fixture.envelope['ciphertext'] = encodeRemoteConfigBase64(ciphertext);
    final service = _service(
      manifest: fixture.envelope,
      aesKey: fixture.aesKey,
      signingPublicKey: fixture.signingPublicKey,
    );

    expect(
      () => service.checkForUpdate(currentVersion: '1.0.2'),
      throwsA(
        isA<RemoteConfigCipherException>().having(
          (error) => error.failure,
          'failure',
          RemoteConfigCipherFailure.signature,
        ),
      ),
    );
  });

  test(
    'Linux rejects unsigned manifests when verification keys are configured',
    () async {
      final fixture = await _encryptManifest(_manifest());
      final service = _service(
        manifest: _manifest(),
        aesKey: fixture.aesKey,
        signingPublicKey: fixture.signingPublicKey,
      );

      expect(
        () => service.checkForUpdate(currentVersion: '1.0.2'),
        throwsFormatException,
      );
    },
  );
}

AppUpdateService _service({
  required Object manifest,
  Abi abi = Abi.linuxX64,
  String aesKey = '',
  String signingPublicKey = '',
}) {
  return AppUpdateService(
    mainConfigLoader: () async => {'UpdateUrl': _manifestUrl},
    manifestLoader: (_) async => manifest,
    packageKeyResolver: () => appUpdatePackageKeyForAbi(abi),
    aesKey: aesKey,
    signingPublicKey: signingPublicKey,
  );
}

Map<String, Object?> _manifest({
  String version = '1.0.3',
  bool enabled = true,
  bool includeLinux = true,
}) {
  return {
    'Authentication': 'FengWo',
    'format': appUpdateManifestFormat,
    'schemaVersion': appUpdateManifestVersion,
    'packages': <String, Object?>{
      if (includeLinux)
        'linux-x64': <String, Object?>{
          'enabled': enabled,
          'version': version,
          'title': 'Linux update',
          'downloadUrl': 'FlClash-$version-linux-amd64.deb',
          'releaseNotesHtml': '<p>Linux x64 update</p>',
          'sha256': 'a' * 64,
          'publishedAt': '2026-09-15T00:00:00Z',
        },
      for (final platform in ['macos-x64', 'windows-x64', 'android-x86_64'])
        platform: <String, Object?>{
          'enabled': true,
          'version': '9.0.0',
          'downloadUrl': 'https://download.example/$platform-9.0.0',
        },
    },
  };
}

Future<_CipherFixture> _encryptManifest(Map<String, Object?> manifest) async {
  final algorithm = AesGcm.with256bits();
  final aesKey = await algorithm.newSecretKey();
  final signingKeyPair = await Ed25519().newKeyPair();
  final signingPublicKey = await signingKeyPair.extractPublicKey();
  final envelope = <String, Object?>{
    'format': remoteConfigFormat,
    'version': remoteConfigVersion,
    'alg': remoteConfigEncryptionAlgorithm,
    'sig': remoteConfigSignatureAlgorithm,
    'kid': remoteConfigKeyId(signingPublicKey.bytes),
  };
  final secretBox = await algorithm.encrypt(
    utf8.encode(jsonEncode(manifest)),
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
    aesKey: encodeRemoteConfigBase64(await aesKey.extractBytes()),
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

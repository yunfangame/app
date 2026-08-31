import 'dart:ffi';

import 'package:fl_clash/common/app_update.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const manifestUrl = 'https://house.example/fengwoupdate.json';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('maps runtime ABIs to independent package keys', () {
    expect(appUpdatePackageKeyForAbi(Abi.androidArm64), 'android-arm64-v8a');
    expect(appUpdatePackageKeyForAbi(Abi.androidArm), 'android-armeabi-v7a');
    expect(appUpdatePackageKeyForAbi(Abi.androidX64), 'android-x86_64');
    expect(appUpdatePackageKeyForAbi(Abi.windowsX64), 'windows-x64');
    expect(appUpdatePackageKeyForAbi(Abi.macosArm64), 'macos-arm64');
    expect(appUpdatePackageKeyForAbi(Abi.macosX64), 'macos-x64');
  });

  test('compares semantic versions and build numbers', () {
    expect(compareAppUpdateVersions('0.8.97', '0.8.96+2026081701'), 1);
    expect(compareAppUpdateVersions('v1.2.0', '1.1.99'), 1);
    expect(compareAppUpdateVersions('1.2.0+2', '1.2.0+1'), 1);
    expect(compareAppUpdateVersions('1.2', '1.2.0'), 0);
  });

  test(
    'selects only the current package and requires a higher version',
    () async {
      final service = _service(
        packageKey: 'macos-arm64',
        manifest: _manifest(armVersion: '0.8.97', windowsVersion: '9.0.0'),
      );

      final release = await service.checkForUpdate(currentVersion: '0.8.96');
      expect(release, isNotNull);
      expect(release!.packageKey, 'macos-arm64');
      expect(release.version, '0.8.97');
      expect(release.releaseNotesHtml, contains('<strong>ARM</strong>'));

      final current = await service.checkForUpdate(currentVersion: '0.8.97');
      expect(current, isNull);
    },
  );

  test(
    'disabled package does not trigger even when another package is newer',
    () async {
      final manifest = _manifest(armVersion: '0.9.0', windowsVersion: '9.0.0');
      final packages = manifest['packages']! as Map<String, Object?>;
      packages['macos-arm64'] = {
        ...(packages['macos-arm64']! as Map<String, Object?>),
        'enabled': false,
      };
      final service = _service(packageKey: 'macos-arm64', manifest: manifest);
      expect(await service.checkForUpdate(currentVersion: '0.8.96'), isNull);
    },
  );

  test('ignore applies only to the selected package version', () async {
    final service = _service(
      packageKey: 'macos-arm64',
      manifest: _manifest(armVersion: '0.8.97', windowsVersion: '0.8.97'),
    );
    final release = await service.checkForUpdate(currentVersion: '0.8.96');
    await service.ignore(release!);

    expect(await service.checkForUpdate(currentVersion: '0.8.96'), isNull);
    expect(
      await service.checkForUpdate(
        currentVersion: '0.8.96',
        respectIgnored: false,
      ),
      isNotNull,
    );
  });

  test('requires HTTPS for manifest and installer URLs', () {
    expect(
      appUpdateManifestUriFromConfig({'UpdateUrl': 'http://example/update'}),
      isNull,
    );
    expect(
      () => parseAppUpdateRelease(
        _manifest(
          armVersion: '0.8.97',
          windowsVersion: '0.8.97',
          armUrl: 'http://example/app.dmg',
        ),
        packageKey: 'macos-arm64',
        manifestUri: Uri.parse(manifestUrl),
      ),
      throwsFormatException,
    );
  });
}

AppUpdateService _service({
  required String packageKey,
  required Map<String, Object?> manifest,
}) {
  return AppUpdateService(
    mainConfigLoader: () async => {'UpdateUrl': manifestUrl},
    manifestLoader: (_) async => manifest,
    packageKeyResolver: () => packageKey,
    aesKey: '',
    signingPublicKey: '',
  );
}

Map<String, Object?> _manifest({
  required String armVersion,
  required String windowsVersion,
  String armUrl = 'https://house.example/fengwo-arm.dmg',
}) {
  return {
    'Authentication': 'FengWo',
    'format': 'fengwo-update',
    'schemaVersion': 1,
    'packages': <String, Object?>{
      'macos-arm64': <String, Object?>{
        'enabled': true,
        'version': armVersion,
        'downloadUrl': armUrl,
        'releaseNotesHtml': '<p><strong>ARM</strong> update</p>',
      },
      'windows-x64': <String, Object?>{
        'enabled': true,
        'version': windowsVersion,
        'downloadUrl': 'https://house.example/fengwo.exe',
        'releaseNotesHtml': '<p>Windows update</p>',
      },
    },
  };
}

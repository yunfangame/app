import 'dart:io';

import 'package:build_tool/src/options.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory root;

  setUp(() {
    root = Directory.systemTemp.createTempSync('build_config_identity_test_');
  });

  tearDown(() => root.deleteSync(recursive: true));

  test('Windows output names are independent from other platform defaults', () {
    final config = BuildConfig.load(rootDir: root.path);

    expect(config.coreNameForPlatform('windows'), 'FengWoCore');
    expect(config.helperNameForPlatform('windows'), 'FengWoHelperService');
    for (final platform in ['darwin', 'linux', 'android']) {
      expect(config.coreNameForPlatform(platform), 'FlClashCore');
      expect(config.helperNameForPlatform(platform), 'FlClashHelperService');
    }
    expect(config.libName, 'libclash');
  });

  test('Legacy shared configuration cannot restore old Windows output names',
      () {
    File(p.join(root.path, 'build_config.yaml')).writeAsStringSync(
      'core_name: LegacyCore\nhelper_name: LegacyHelper\n',
    );
    final config = BuildConfig.load(rootDir: root.path);

    expect(config.coreNameForPlatform('windows'), 'FengWoCore');
    expect(config.helperNameForPlatform('windows'), 'FengWoHelperService');
    expect(config.coreNameForPlatform('darwin'), 'LegacyCore');
    expect(config.helperNameForPlatform('linux'), 'LegacyHelper');
  });

  test('Windows-specific configuration does not rename other platforms', () {
    File(p.join(root.path, 'build_config.yaml')).writeAsStringSync(
      'windows_core_name: CustomWindowsCore\n'
      'windows_helper_name: CustomWindowsHelper\n',
    );
    final config = BuildConfig.load(rootDir: root.path);

    expect(config.coreNameForPlatform('windows'), 'CustomWindowsCore');
    expect(config.helperNameForPlatform('windows'), 'CustomWindowsHelper');
    expect(config.coreNameForPlatform('darwin'), 'FlClashCore');
    expect(config.coreNameForPlatform('linux'), 'FlClashCore');
    expect(config.libName, 'libclash');
  });

  test('Windows output names are part of the build fingerprint', () {
    final previous = BuildConfig.load(rootDir: root.path).toFingerprintMap();
    File(p.join(root.path, 'build_config.yaml')).writeAsStringSync(
      'windows_core_name: CustomWindowsCore\n'
      'windows_helper_name: CustomWindowsHelper\n',
    );
    final current = BuildConfig.load(rootDir: root.path).toFingerprintMap();

    expect(previous['windows_core_name'], 'FengWoCore');
    expect(previous['windows_helper_name'], 'FengWoHelperService');
    expect(current['windows_core_name'], 'CustomWindowsCore');
    expect(current['windows_helper_name'], 'CustomWindowsHelper');
    expect(current, isNot(previous));
    expect(current['core_name'], previous['core_name']);
    expect(current['lib_name'], previous['lib_name']);
  });
}

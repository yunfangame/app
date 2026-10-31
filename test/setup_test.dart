import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:test/test.dart';

import '../setup.dart' as setup;

void main() {
  group('setup.dart', () {
    test('Windows Wi-Fi support loads wlanapi only when available', () {
      final source = File(
        'plugins/wifi_ssid/windows/wifi_ssid_plugin.cpp',
      ).readAsStringSync();
      final cmake = File(
        'plugins/wifi_ssid/windows/CMakeLists.txt',
      ).readAsStringSync();

      expect(source, contains('GetSystemDirectoryW'));
      expect(source, contains('LoadLibraryW'));
      expect(source, contains('GetProcAddress'));
      expect(source, contains('if (!api.is_available())'));
      expect(
        source,
        isNot(
          contains(
            RegExp(
              r'\bWlan(?:OpenHandle|CloseHandle|EnumInterfaces|QueryInterface|FreeMemory)\s*\(',
            ),
          ),
        ),
      );
      expect(cmake, isNot(contains(RegExp(r'\bwlanapi\b'))));
    });

    test('Linux DEB uses runtime libraries instead of build dependencies', () {
      final config = File(
        'linux/packaging/deb/make_config.yaml',
      ).readAsStringSync();

      expect(config, contains('fonts-noto-cjk'));
      expect(config, contains('gnome-keyring'));
      expect(config, contains('gstreamer1.0-plugins-bad'));
      expect(config, contains('libayatana-appindicator3-1'));
      expect(config, contains('libkeybinder-3.0-0'));
      expect(config, isNot(contains('libayatana-appindicator3-dev')));
      expect(config, isNot(contains('libkeybinder-3.0-dev')));
    });

    test('copies the Linux preflight script into dist', () async {
      final root = await Directory.systemTemp.createTemp(
        'flclash-linux-preflight-test-',
      );
      addTearDown(() => root.delete(recursive: true));
      final source = File(
        '${root.path}/tooling/linux/fengwo-linux-preflight.sh',
      );
      await source.parent.create(recursive: true);
      await source.writeAsString('#!/usr/bin/env bash\nexit 0\n');

      final output = await setup.copyLinuxPreflightScript(root.path);

      expect(output.path, '${root.path}/dist/fengwo-linux-preflight.sh');
      expect(await output.readAsString(), await source.readAsString());
    });

    test('Linux preflight script has valid Bash syntax', () async {
      final result = await Process.run('bash', [
        '-n',
        'tooling/linux/fengwo-linux-preflight.sh',
      ]);

      expect(result.exitCode, 0, reason: result.stderr.toString());
    });

    test('parses -v as verbose mode', () {
      final results = setup.createSetupArgParser().parse(['android', '-v']);

      expect(results['verbose'], isTrue);
      expect(results['env'], 'stable');
      expect(results.rest, ['android']);
    });

    test('accepts dev application environment', () {
      final results = setup.createSetupArgParser().parse([
        'android',
        '--env',
        'dev',
      ]);

      expect(results['env'], 'dev');
    });

    test(
      'parses Android universal mode and rejects conflicting selections',
      () {
        final results = setup.createSetupArgParser().parse([
          'android',
          '--universal',
        ]);
        expect(results['universal'], isTrue);
        expect(results['arch'], isNull);
        setup.validateAndroidBuildSelection(
          platform: 'android',
          androidUniversal: true,
        );
        for (final platform in ['android', 'windows', 'macos', 'linux']) {
          expect(
            () => setup.validateAndroidBuildSelection(
              platform: platform,
              androidArch: 'arm64',
              androidUniversal: true,
            ),
            throwsArgumentError,
          );
        }
        expect(
          () => setup.validateAndroidBuildSelection(
            platform: 'macos',
            androidUniversal: true,
          ),
          throwsArgumentError,
        );
      },
    );

    test('universal builds request all targets without splitting the APK', () {
      final args = setup.createFlutterBuildArgs(
        platform: 'android',
        verbose: false,
        androidDebugInfoDirectory: '/symbols/universal/dart',
        androidUniversal: true,
      );
      expect(args, [
        'dart-define-from-file=env.json',
        'release',
        'obfuscate',
        'split-debug-info=/symbols/universal/dart',
      ]);
      expect(
        setup.androidTargetPlatforms(androidUniversal: true),
        'android-arm,android-arm64,android-x64',
      );
      expect(
        setup.androidTargetPlatforms(androidArch: 'arm64'),
        'android-arm64',
      );
      expect(
        () => setup.androidTargetPlatforms(
          androidArch: 'arm64',
          androidUniversal: true,
        ),
        throwsArgumentError,
      );
      expect(setup.createPackagingEnvironment(platform: 'android'), {
        'ANDROID_ARCH': '',
      });
      expect(
        setup.createPackagingEnvironment(
          platform: 'android',
          androidArch: 'arm64',
        ),
        {'ANDROID_ARCH': 'arm64'},
      );
      expect(setup.createPackagingEnvironment(platform: 'windows'), isEmpty);
    });

    test('accepts unsigned macOS encrypted secret storage mode', () {
      final results = setup.createSetupArgParser().parse([
        'macos',
        '--macos-file-secret-storage',
      ]);

      expect(results['macos-file-secret-storage'], isTrue);
    });

    test('detects whether macOS packaging needs the DMG dependency', () {
      expect(setup.macosTargetsNeedAppDmg('pkg'), isFalse);
      expect(setup.macosTargetsNeedAppDmg('pkg,dmg'), isTrue);
    });

    test('requires both architectures for a Universal 2 build', () {
      expect(setup.hasUniversalMacosArchitectures('x86_64 arm64'), isTrue);
      expect(setup.hasUniversalMacosArchitectures('arm64'), isFalse);
      expect(setup.hasUniversalMacosArchitectures('x86_64'), isFalse);
    });

    test('Flutter build environment does not depend on Core SHA256', () {
      expect(setup.createBuildEnvironment('dev'), {'APP_ENV': 'dev'});
    });

    test(
      'loads public remote config build keys without the private key',
      () async {
        final root = await Directory.systemTemp.createTemp(
          'flclash-remote-config-test-',
        );
        addTearDown(() => root.delete(recursive: true));
        final keys = File('${root.path}/tooling/remote_config/keys.json');
        await keys.parent.create(recursive: true);
        await keys.writeAsString(
          jsonEncode({
            'aesKey': 'aes-key',
            'signingPrivateKey': 'private-key',
            'signingPublicKey': 'public-key',
          }),
        );

        expect(await setup.loadBuildEnvironment(root.path, 'stable'), {
          'APP_ENV': 'stable',
          'REMOTE_CONFIG_AES_KEY': 'aes-key',
          'REMOTE_CONFIG_SIGNING_PUBLIC_KEY': 'public-key',
        });
      },
    );

    test('rejects a build without remote config keys', () async {
      final root = await Directory.systemTemp.createTemp(
        'flclash-missing-remote-config-test-',
      );
      addTearDown(() => root.delete(recursive: true));

      expect(
        () => setup.loadBuildEnvironment(root.path, 'pre'),
        throwsFormatException,
      );
    });

    test('writes the complete Debug build environment', () async {
      final root = await Directory.systemTemp.createTemp(
        'flclash-debug-environment-test-',
      );
      addTearDown(() => root.delete(recursive: true));
      final keys = File('${root.path}/tooling/remote_config/keys.json');
      await keys.parent.create(recursive: true);
      await keys.writeAsString(
        jsonEncode({'aesKey': 'aes-key', 'signingPublicKey': 'public-key'}),
      );

      final file = await setup.writeBuildEnvironmentFile(root.path, 'pre');

      expect(jsonDecode(await file.readAsString()), {
        'APP_ENV': 'pre',
        'REMOTE_CONFIG_AES_KEY': 'aes-key',
        'REMOTE_CONFIG_SIGNING_PUBLIC_KEY': 'public-key',
      });
    });

    test('adds a validated encrypted config URL override', () async {
      final root = await Directory.systemTemp.createTemp(
        'flclash-debug-config-url-test-',
      );
      addTearDown(() => root.delete(recursive: true));
      final keys = File('${root.path}/tooling/remote_config/keys.json');
      await keys.parent.create(recursive: true);
      await keys.writeAsString(
        jsonEncode({'aesKey': 'aes-key', 'signingPublicKey': 'public-key'}),
      );

      final environment = await setup.loadBuildEnvironment(
        root.path,
        'pre',
        apiHealthConfigUrl: 'http://127.0.0.1:18996/ConFigOss4.json',
      );

      expect(
        environment['API_HEALTH_CONFIG_URL'],
        'http://127.0.0.1:18996/ConFigOss4.json',
      );
    });

    test('adds the unsigned macOS secret storage build define', () async {
      final root = await Directory.systemTemp.createTemp(
        'flclash-macos-secret-storage-test-',
      );
      addTearDown(() => root.delete(recursive: true));
      final keys = File('${root.path}/tooling/remote_config/keys.json');
      await keys.parent.create(recursive: true);
      await keys.writeAsString(
        jsonEncode({'aesKey': 'aes-key', 'signingPublicKey': 'public-key'}),
      );

      final environment = await setup.loadBuildEnvironment(
        root.path,
        'stable',
        macOsFileSecretStorage: true,
      );

      expect(environment['MACOS_FILE_SECRET_STORAGE'], 'true');
    });

    test('rejects an unsafe config URL override', () async {
      final root = await Directory.systemTemp.createTemp(
        'flclash-debug-invalid-config-url-test-',
      );
      addTearDown(() => root.delete(recursive: true));
      final keys = File('${root.path}/tooling/remote_config/keys.json');
      await keys.parent.create(recursive: true);
      await keys.writeAsString(
        jsonEncode({'aesKey': 'aes-key', 'signingPublicKey': 'public-key'}),
      );

      expect(
        () => setup.loadBuildEnvironment(
          root.path,
          'pre',
          apiHealthConfigUrl: 'file:///tmp/ConFigOss4.json',
        ),
        throwsFormatException,
      );
    });

    test('omits verbose from flutter build args by default', () {
      final args = setup.createFlutterBuildArgs(
        platform: 'android',
        verbose: false,
        androidDebugInfoDirectory: '/symbols/1.0.9+2026103118/arm64/dart',
      );

      expect(args, [
        'dart-define-from-file=env.json',
        'release',
        'split-per-abi',
        'obfuscate',
        'split-debug-info=/symbols/1.0.9+2026103118/arm64/dart',
      ]);
    });

    test('adds verbose to flutter build args with -v', () {
      final args = setup.createFlutterBuildArgs(
        platform: 'android',
        verbose: true,
        androidDebugInfoDirectory: '/symbols/1.0.9+2026103118/arm64/dart',
      );

      expect(args, [
        'verbose',
        'dart-define-from-file=env.json',
        'release',
        'split-per-abi',
        'obfuscate',
        'split-debug-info=/symbols/1.0.9+2026103118/arm64/dart',
      ]);
    });

    test('requires an unambiguous Android symbols directory', () {
      for (final directory in [null, '', '/symbols/invalid,path']) {
        expect(
          () => setup.createFlutterBuildArgs(
            platform: 'android',
            verbose: false,
            androidDebugInfoDirectory: directory,
          ),
          throwsArgumentError,
        );
      }
    });

    test('preserves desktop Flutter build arguments', () {
      for (final platform in ['macos', 'windows', 'linux']) {
        expect(
          setup.createFlutterBuildArgs(platform: platform, verbose: false),
          ['dart-define-from-file=env.json'],
        );
      }
    });

    test('rejects missing or incomplete Android release signing', () async {
      final root = await Directory.systemTemp.createTemp('android-signing-');
      addTearDown(() => root.delete(recursive: true));
      final store = File('${root.path}/android/app/keystore.jks');
      final properties = File('${root.path}/android/local.properties');
      await store.parent.create(recursive: true);
      await properties.writeAsString(
        'storePassword=fixture-store\nkeyAlias=fixture-alias\nkeyPassword=fixture-key\n',
      );
      await expectLater(
        setup.validateAndroidReleaseSigningInputs(root.path),
        throwsFormatException,
      );
      await store.writeAsString('fixture-keystore');
      await properties.writeAsString('storePassword=fixture-store\n');
      await expectLater(
        setup.validateAndroidReleaseSigningInputs(root.path),
        throwsFormatException,
      );
      await properties.writeAsString(
        'storePassword=fixture-store\nkeyAlias=fixture-alias\nkeyPassword=fixture-key\nkeyPassword=   \n',
      );
      await expectLater(
        setup.validateAndroidReleaseSigningInputs(root.path),
        throwsFormatException,
      );
    });

    test('accepts complete Android release signing inputs', () async {
      final root = await Directory.systemTemp.createTemp('android-signing-');
      addTearDown(() => root.delete(recursive: true));
      final store = File('${root.path}/android/app/keystore.jks');
      await store.parent.create(recursive: true);
      await store.writeAsString('fixture-keystore');
      await File('${root.path}/android/local.properties').writeAsString(
        '# fixture\nstorePassword=fixture-store\nkeyAlias: fixture-alias\nkeyPassword fixture-key\n',
      );

      await setup.validateAndroidReleaseSigningInputs(root.path);
    });

    test(
      'keeps symbols unique for version and selected architecture',
      () async {
        final root = await Directory.systemTemp.createTemp('android-symbols-');
        addTearDown(() => root.delete(recursive: true));
        await File(
          '${root.path}/pubspec.yaml',
        ).writeAsString('name: fl_clash\nversion: 1.0.9+2026103118\n');

        final first = await setup.prepareAndroidReleaseSymbols(
          root.path,
          androidArch: 'arm64',
        );
        final second = await setup.prepareAndroidReleaseSymbols(
          root.path,
          androidArch: 'arm64',
        );
        final all = await setup.prepareAndroidReleaseSymbols(root.path);

        expect(first.path, contains('/1.0.9+2026103118/arm64/build-'));
        expect(second.path, isNot(first.path));
        expect(all.path, contains('/1.0.9+2026103118/all-abis/build-'));
      },
    );

    test('rejects unsafe or unversioned Android symbols archives', () async {
      final root = await Directory.systemTemp.createTemp('android-symbols-');
      addTearDown(() => root.delete(recursive: true));
      for (final version in ['1.0.9', '../outside', '1.0.9+../../outside']) {
        await File(
          '${root.path}/pubspec.yaml',
        ).writeAsString('version: $version\n');
        await expectLater(
          setup.prepareAndroidReleaseSymbols(root.path),
          throwsFormatException,
        );
      }
      expect(await Directory('${root.path}/release-symbols').exists(), isFalse);
    });

    test('archives R8 mapping and binds Dart symbols to each APK', () async {
      final root = await Directory.systemTemp.createTemp('android-symbols-');
      addTearDown(() => root.delete(recursive: true));
      await File(
        '${root.path}/pubspec.yaml',
      ).writeAsString('name: fl_clash\nversion: 1.0.9+2026103118\n');
      final directory = await setup.prepareAndroidReleaseSymbols(root.path);
      final abis = {
        'android-arm': 'armeabi-v7a',
        'android-arm64': 'arm64-v8a',
        'android-x64': 'x86_64',
      };
      for (final entry in abis.entries) {
        final symbols = File('${directory.path}/dart/app.${entry.key}.symbols');
        await symbols.parent.create(recursive: true);
        await symbols.writeAsString('symbols-${entry.value}');
        await _writeAndroidApkFixture(root, entry.value);
      }
      final mapping = File(
        '${root.path}/build/app/outputs/mapping/release/mapping.txt',
      );
      await mapping.parent.create(recursive: true);
      await mapping.writeAsString('fixture.Model -> a:\n');

      final manifest = await setup.archiveAndroidReleaseSymbols(
        root.path,
        directory,
      );
      final record = jsonDecode(await manifest.readAsString()) as Map;

      expect(record['version'], '1.0.9+2026103118');
      expect(record['obfuscated'], isTrue);
      final artifacts = record['artifacts'] as List;
      expect(artifacts.map((row) => row['abi']).toSet(), abis.values.toSet());
      for (final row in artifacts) {
        expect(
          row['apk']['sha256'],
          sha256
              .convert(
                await File('${root.path}/${row['apk']['path']}').readAsBytes(),
              )
              .toString(),
        );
        expect(
          row['dart_symbols']['sha256'],
          sha256.convert(utf8.encode('symbols-${row['abi']}')).toString(),
        );
      }
      expect(
        (record['r8'] as List).single['path'],
        endsWith('/r8/mapping.txt'),
      );
      expect(
        await File('${directory.path}/r8/mapping.txt').readAsString(),
        await mapping.readAsString(),
      );
    });

    test(
      'rejects a successful build without its selected Dart symbols',
      () async {
        final root = await Directory.systemTemp.createTemp('android-symbols-');
        addTearDown(() => root.delete(recursive: true));
        await File(
          '${root.path}/pubspec.yaml',
        ).writeAsString('name: fl_clash\nversion: 1.0.9+2026103118\n');
        final directory = await setup.prepareAndroidReleaseSymbols(
          root.path,
          androidArch: 'arm64',
        );
        await _writeAndroidApkFixture(root, 'arm64-v8a');

        await expectLater(
          setup.archiveAndroidReleaseSymbols(
            root.path,
            directory,
            androidArch: 'arm64',
          ),
          throwsA(isA<FileSystemException>()),
        );
        expect(await File('${directory.path}/manifest.json').exists(), isFalse);
      },
    );

    test('rejects a successful build without its R8 mapping', () async {
      final root = await Directory.systemTemp.createTemp('android-symbols-');
      addTearDown(() => root.delete(recursive: true));
      await File(
        '${root.path}/pubspec.yaml',
      ).writeAsString('name: fl_clash\nversion: 1.0.9+2026103118\n');
      final directory = await setup.prepareAndroidReleaseSymbols(
        root.path,
        androidArch: 'arm64',
      );
      await _writeAndroidApkFixture(root, 'arm64-v8a');
      final symbols = File('${directory.path}/dart/app.android-arm64.symbols');
      await symbols.parent.create(recursive: true);
      await symbols.writeAsString('fixture-symbols');

      await expectLater(
        setup.archiveAndroidReleaseSymbols(
          root.path,
          directory,
          androidArch: 'arm64',
        ),
        throwsA(isA<FileSystemException>()),
      );
      expect(await File('${directory.path}/manifest.json').exists(), isFalse);
    });

    test('quarantines old ABI outputs before a single ARM64 build', () async {
      final root = await Directory.systemTemp.createTemp('android-old-abis-');
      addTearDown(() => root.delete(recursive: true));
      await File(
        '${root.path}/pubspec.yaml',
      ).writeAsString('name: fl_clash\nversion: 1.0.9+2026103118\n');
      for (final abi in ['armeabi-v7a', 'arm64-v8a', 'x86_64']) {
        await _writeAndroidApkFixture(root, abi, marker: 'old');
      }
      final unrelated = File('${root.path}/dist/user-package.apk');
      await unrelated.writeAsString('user-owned');
      final debug = File(
        '${root.path}/build/app/outputs/flutter-apk/app-debug.apk',
      );
      await debug.writeAsString('debug-build');
      final symbols = await setup.prepareAndroidReleaseSymbols(
        root.path,
        androidArch: 'arm64',
      );

      await setup.quarantineAndroidReleaseApks(root.path, symbols);

      final backups =
          jsonDecode(
                await File('${symbols.path}/previous-apks.json').readAsString(),
              )
              as List;
      expect(backups, hasLength(6));
      for (final row in backups) {
        expect(await File('${root.path}/${row['original']}').exists(), isFalse);
        expect(await File('${root.path}/${row['archived']}').exists(), isTrue);
      }
      final fresh = await _writeAndroidApkFixture(
        root,
        'arm64-v8a',
        marker: 'new',
      );
      final artifacts = await setup.verifyAndroidReleaseApks(
        root.path,
        androidArch: 'arm64',
      );

      expect(artifacts.single['abi'], 'arm64-v8a');
      expect(
        (artifacts.single['apk'] as Map)['sha256'],
        sha256.convert(await fresh.readAsBytes()).toString(),
      );
      expect(
        (artifacts.single['distributed_apk'] as Map)['sha256'],
        (artifacts.single['apk'] as Map)['sha256'],
      );
      expect(await unrelated.readAsString(), 'user-owned');
      expect(await debug.readAsString(), 'debug-build');
    });

    test(
      'preserves unknown release APKs and refuses to package them',
      () async {
        final root = await Directory.systemTemp.createTemp(
          'android-foreign-apk-',
        );
        addTearDown(() => root.delete(recursive: true));
        await File(
          '${root.path}/pubspec.yaml',
        ).writeAsString('name: fl_clash\nversion: 1.0.9+2026103118\n');
        final known = await _writeAndroidApkFixture(root, 'arm64-v8a');
        final foreign = File('${known.parent.path}/user-release.apk');
        await foreign.writeAsString('user-owned');
        final symbols = await setup.prepareAndroidReleaseSymbols(root.path);

        await expectLater(
          setup.quarantineAndroidReleaseApks(root.path, symbols),
          throwsA(isA<FileSystemException>()),
        );

        expect(await foreign.readAsString(), 'user-owned');
        expect(await known.exists(), isTrue);
      },
    );

    test('rejects stale ABI copies and modified distributed APKs', () async {
      final root = await Directory.systemTemp.createTemp('android-dist-apk-');
      addTearDown(() => root.delete(recursive: true));
      await File(
        '${root.path}/pubspec.yaml',
      ).writeAsString('name: fl_clash\nversion: 1.0.9+2026103118\n');
      await _writeAndroidApkFixture(root, 'arm64-v8a');
      final stale = File('${root.path}/dist/fl_clash-1.0.9-android-x86_64.apk');
      await stale.writeAsString('old-x86');
      await expectLater(
        setup.verifyAndroidReleaseApks(root.path, androidArch: 'arm64'),
        throwsFormatException,
      );
      await stale.delete();
      await File(
        '${root.path}/dist/fl_clash-1.0.9-android-arm64-v8a.apk',
      ).writeAsString('wrong-bytes');

      await expectLater(
        setup.verifyAndroidReleaseApks(root.path, androidArch: 'arm64'),
        throwsFormatException,
      );
    });

    test(
      'rejects native libraries with a different ABI than the filename',
      () async {
        final root = await Directory.systemTemp.createTemp('android-apk-abi-');
        addTearDown(() => root.delete(recursive: true));
        await File(
          '${root.path}/pubspec.yaml',
        ).writeAsString('name: fl_clash\nversion: 1.0.9+2026103118\n');
        final wrong = await _writeAndroidApkFixture(root, 'x86_64');
        await wrong.rename('${wrong.parent.path}/app-arm64-v8a-release.apk');
        final wrongDist = File(
          '${root.path}/dist/fl_clash-1.0.9-android-x86_64.apk',
        );
        await wrongDist.rename(
          '${root.path}/dist/fl_clash-1.0.9-android-arm64-v8a.apk',
        );

        await expectLater(
          setup.verifyAndroidReleaseApks(root.path, androidArch: 'arm64'),
          throwsFormatException,
        );
      },
    );
    test(
      'universal release replaces old split outputs and archives all symbols',
      () async {
        final root = await Directory.systemTemp.createTemp(
          'android-universal-',
        );
        addTearDown(() => root.delete(recursive: true));
        await File(
          '${root.path}/pubspec.yaml',
        ).writeAsString('name: fl_clash\nversion: 1.0.9+2026103118\n');
        for (final abi in ['armeabi-v7a', 'arm64-v8a', 'x86_64']) {
          await _writeAndroidApkFixture(root, abi, marker: 'old');
        }
        await _writeUniversalApkFixture(root, marker: 'old-universal');
        final symbols = await setup.prepareAndroidReleaseSymbols(
          root.path,
          androidUniversal: true,
        );
        expect(symbols.path, contains('/1.0.9+2026103118/universal/build-'));
        await setup.quarantineAndroidReleaseApks(root.path, symbols);
        final backup =
            jsonDecode(
                  await File(
                    '${symbols.path}/previous-apks.json',
                  ).readAsString(),
                )
                as List;
        expect(backup, hasLength(8));
        final apk = await _writeUniversalApkFixture(
          root,
          marker: 'new-universal',
        );
        for (final target in ['android-arm', 'android-arm64', 'android-x64']) {
          final file = File('${symbols.path}/dart/app.$target.symbols');
          await file.parent.create(recursive: true);
          await file.writeAsString('symbols-$target');
        }
        final mapping = File(
          '${root.path}/build/app/outputs/mapping/release/mapping.txt',
        );
        await mapping.parent.create(recursive: true);
        await mapping.writeAsString('fixture.Model -> a:\n');

        final manifest = await setup.archiveAndroidReleaseSymbols(
          root.path,
          symbols,
          androidUniversal: true,
        );
        final record = jsonDecode(await manifest.readAsString()) as Map;
        final artifact = (record['artifacts'] as List).single as Map;

        expect(record['universal'], isTrue);
        expect(artifact['abi'], 'universal');
        expect((artifact['abis'] as List).toSet(), {
          'armeabi-v7a',
          'arm64-v8a',
          'x86_64',
        });
        expect(
          artifact['apk']['sha256'],
          sha256.convert(await apk.readAsBytes()).toString(),
        );
        expect(
          artifact['distributed_apk']['sha256'],
          artifact['apk']['sha256'],
        );
        expect(
          (artifact['dart_symbols'] as List)
              .map((entry) => entry['abi'])
              .toSet(),
          {'armeabi-v7a', 'arm64-v8a', 'x86_64'},
        );
        expect(
          (record['r8'] as List).single['path'],
          endsWith('/r8/mapping.txt'),
        );
        final distApks = await Directory(
          '${root.path}/dist',
        ).list().where((file) => file.path.endsWith('.apk')).toList();
        expect(distApks, hasLength(1));
      },
    );

    test('rejects a single ABI relabelled as a universal APK', () async {
      final root = await Directory.systemTemp.createTemp('android-universal-');
      addTearDown(() => root.delete(recursive: true));
      await File(
        '${root.path}/pubspec.yaml',
      ).writeAsString('name: fl_clash\nversion: 1.0.9+2026103118\n');
      final apk = await _writeAndroidApkFixture(root, 'arm64-v8a');
      await apk.rename('${apk.parent.path}/app-release.apk');
      await File(
        '${root.path}/dist/fl_clash-1.0.9-android-arm64-v8a.apk',
      ).rename('${root.path}/dist/fl_clash-1.0.9-android.apk');

      await expectLater(
        setup.verifyAndroidReleaseApks(root.path, androidUniversal: true),
        throwsFormatException,
      );
    });

    test('rejects mixed universal and split distribution files', () async {
      final root = await Directory.systemTemp.createTemp('android-universal-');
      addTearDown(() => root.delete(recursive: true));
      await File(
        '${root.path}/pubspec.yaml',
      ).writeAsString('name: fl_clash\nversion: 1.0.9+2026103118\n');
      await _writeUniversalApkFixture(root);
      await File(
        '${root.path}/dist/fl_clash-1.0.9-android-arm64-v8a.apk',
      ).writeAsString('old-arm64');

      await expectLater(
        setup.verifyAndroidReleaseApks(root.path, androidUniversal: true),
        throwsFormatException,
      );
    });
  });
}

Future<File> _writeAndroidApkFixture(
  Directory root,
  String abi, {
  String marker = 'fixture',
}) async {
  final archive = Archive();
  for (final name in ['libapp.so', 'libflutter.so', 'libclash.so']) {
    final bytes = utf8.encode('$marker-$abi-$name');
    archive.addFile(ArchiveFile('lib/$abi/$name', bytes.length, bytes));
  }
  final apk = File(
    '${root.path}/build/app/outputs/flutter-apk/app-$abi-release.apk',
  );
  await apk.parent.create(recursive: true);
  await apk.writeAsBytes(ZipEncoder().encode(archive));
  final packaged = File('${root.path}/dist/fl_clash-1.0.9-android-$abi.apk');
  await packaged.parent.create(recursive: true);
  await apk.copy(packaged.path);
  return apk;
}

Future<File> _writeUniversalApkFixture(
  Directory root, {
  String marker = 'fixture',
}) async {
  final archive = Archive();
  for (final abi in ['armeabi-v7a', 'arm64-v8a', 'x86_64']) {
    for (final name in ['libapp.so', 'libflutter.so', 'libclash.so']) {
      final bytes = utf8.encode('$marker-$abi-$name');
      archive.addFile(ArchiveFile('lib/$abi/$name', bytes.length, bytes));
    }
  }
  final apk = File(
    '${root.path}/build/app/outputs/flutter-apk/app-release.apk',
  );
  await apk.parent.create(recursive: true);
  await apk.writeAsBytes(ZipEncoder().encode(archive));
  final packaged = File('${root.path}/dist/fl_clash-1.0.9-android.apk');
  await packaged.parent.create(recursive: true);
  await apk.copy(packaged.path);
  return apk;
}

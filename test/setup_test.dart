import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

import '../setup.dart' as setup;

void main() {
  group('setup.dart', () {
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

    test('accepts unsigned macOS encrypted secret storage mode', () {
      final results = setup.createSetupArgParser().parse([
        'macos',
        '--macos-file-secret-storage',
      ]);

      expect(results['macos-file-secret-storage'], isTrue);
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
      );

      expect(args, ['dart-define-from-file=env.json', 'split-per-abi']);
    });

    test('adds verbose to flutter build args with -v', () {
      final args = setup.createFlutterBuildArgs(
        platform: 'android',
        verbose: true,
      );

      expect(args, [
        'verbose',
        'dart-define-from-file=env.json',
        'split-per-abi',
      ]);
    });
  });
}

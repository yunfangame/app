import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

import '../setup.dart' as setup;

void main() {
  group('setup.dart', () {
    test('parses -v as verbose mode', () {
      final results = setup.createSetupArgParser().parse(['android', '-v']);

      expect(results['verbose'], isTrue);
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

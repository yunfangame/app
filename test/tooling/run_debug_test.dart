import 'package:flutter_test/flutter_test.dart';

import '../../tooling/run_debug.dart' as debug;

void main() {
  test('Debug launcher always injects the generated environment file', () {
    expect(debug.createFlutterRunArgs(device: 'macos'), [
      'run',
      '-d',
      'macos',
      '--debug',
      '--dart-define-from-file=env.json',
    ]);
  });

  test('Debug launcher preserves an explicit Flutter target', () {
    expect(
      debug.createFlutterRunArgs(
        device: 'emulator-5554',
        target: 'lib/main.dart',
      ),
      [
        'run',
        '-d',
        'emulator-5554',
        '--debug',
        '--dart-define-from-file=env.json',
        '-t',
        'lib/main.dart',
      ],
    );
  });
}

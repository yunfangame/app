import 'dart:io';

import 'package:args/args.dart';
import 'package:path/path.dart' as p;

import '../setup.dart' as setup;

Future<void> main(List<String> arguments) async {
  final parser = createDebugArgParser();
  if (arguments.contains('--help') || arguments.contains('-h')) {
    stdout.writeln(parser.usage);
    return;
  }

  final results = parser.parse(arguments);
  final rootDir = Directory.current.path;
  if (!await File(p.join(rootDir, 'pubspec.yaml')).exists()) {
    stderr.writeln('Run this command from the project root.');
    exitCode = 64;
    return;
  }

  try {
    await setup.writeBuildEnvironmentFile(
      rootDir,
      results['env'] as String,
      apiHealthConfigUrl: results['config-url'] as String?,
    );
  } on Object catch (error) {
    stderr.writeln('Unable to prepare encrypted remote config: $error');
    exitCode = 78;
    return;
  }

  final flutter = resolveFlutterExecutable(
    rootDir,
    results['flutter'] as String?,
  );
  final process = await Process.start(
    flutter,
    createFlutterRunArgs(
      device: results['device'] as String,
      target: results['target'] as String?,
    ),
    mode: ProcessStartMode.inheritStdio,
    runInShell: Platform.isWindows,
  );
  exitCode = await process.exitCode;
}

ArgParser createDebugArgParser() {
  return ArgParser()
    ..addOption(
      'device',
      abbr: 'd',
      defaultsTo: Platform.isMacOS ? 'macos' : null,
      mandatory: !Platform.isMacOS,
    )
    ..addOption('env', defaultsTo: 'pre', allowed: ['dev', 'pre', 'stable'])
    ..addOption('config-url')
    ..addOption('flutter')
    ..addOption('target');
}

List<String> createFlutterRunArgs({required String device, String? target}) {
  return [
    'run',
    '-d',
    device,
    '--debug',
    '--dart-define-from-file=env.json',
    if (target != null && target.trim().isNotEmpty) ...['-t', target],
  ];
}

String resolveFlutterExecutable(String rootDir, String? explicit) {
  final configured = explicit?.trim();
  if (configured != null && configured.isNotEmpty) return configured;

  final environment = Platform.environment['FLUTTER_BIN']?.trim();
  if (environment != null && environment.isNotEmpty) return environment;

  final toolchains = Directory('$rootDir-toolchains');
  if (toolchains.existsSync()) {
    final executables =
        toolchains
            .listSync()
            .whereType<Directory>()
            .map(
              (directory) => File(
                p.join(
                  directory.path,
                  'flutter',
                  'bin',
                  Platform.isWindows ? 'flutter.bat' : 'flutter',
                ),
              ),
            )
            .where((file) => file.existsSync())
            .map((file) => file.path)
            .toList()
          ..sort();
    if (executables.isNotEmpty) return executables.last;
  }

  return Platform.isWindows ? 'flutter.bat' : 'flutter';
}

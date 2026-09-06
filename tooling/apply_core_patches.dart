import 'dart:io';

Future<void> main(List<String> arguments) async {
  if (arguments.length > 1) {
    stderr.writeln(
      'Usage: dart tooling/apply_core_patches.dart [project-root]',
    );
    exitCode = 64;
    return;
  }
  final root = arguments.isEmpty
      ? Directory.fromUri(Platform.script.resolve('../'))
      : Directory(arguments.single);
  final buildTool = Directory.fromUri(
    root.absolute.uri.resolve('plugins/setup/buildkit/build_tool/'),
  );
  final process = await Process.start(
    Platform.resolvedExecutable,
    ['run', 'bin/apply_core_patches.dart', root.absolute.path],
    workingDirectory: buildTool.path,
    mode: ProcessStartMode.inheritStdio,
  );
  exitCode = await process.exitCode;
}

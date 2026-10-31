import 'dart:io';

import 'package:build_tool/src/core_patches.dart';

void main(List<String> arguments) {
  if (arguments.length != 1) {
    stderr.writeln('Usage: dart run bin/apply_core_patches.dart project-root');
    exitCode = 64;
    return;
  }
  try {
    final changed = applyRequiredCorePatches(Directory(arguments.single));
    stdout.writeln(
      changed ? 'Core patches applied' : 'Core patches already verified',
    );
  } on CorePatchException catch (error) {
    stderr.writeln(error);
    exitCode = 1;
  }
}

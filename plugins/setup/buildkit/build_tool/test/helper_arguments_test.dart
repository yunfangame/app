import 'package:build_tool/src/rust_builder.dart';
import 'package:build_tool/src/target.dart';
import 'package:test/test.dart';

void main() {
  test('Linux Helper builds with a locked release dependency graph', () {
    expect(RustBuilder.buildArguments(Target.linuxAmd64), [
      'build',
      '--locked',
      '--release',
    ]);
  });
  test('Windows Helper retains the service feature and release hardening', () {
    expect(RustBuilder.buildArguments(Target.windowsAmd64), [
      'build',
      '--locked',
      '--features',
      'windows-service',
      '--release',
    ]);
  });
}

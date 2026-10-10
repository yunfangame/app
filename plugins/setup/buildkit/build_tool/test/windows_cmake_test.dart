import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory root;
  late String buildkitPath;

  setUp(() {
    root = Directory.systemTemp.createTempSync('windows_buildkit_cmake_test_');
    buildkitPath =
        p.absolute('..', 'cmake', 'buildkit.cmake').replaceAll(r'\', '/');
    Directory(p.join(root.path, 'windows')).createSync();
  });

  tearDown(() => root.deleteSync(recursive: true));

  Future<ProcessResult> configure(
      {String? target, String? generatorArch}) async {
    final source = File(p.join(root.path, 'windows', 'CMakeLists.txt'));
    source.writeAsStringSync([
      'cmake_minimum_required(VERSION 3.15)',
      'project(WindowsBuildkitFixture NONE)',
      'set(WIN32 TRUE)',
      if (target != null) 'set(FLUTTER_TARGET_PLATFORM "$target")',
      if (generatorArch != null)
        'set(CMAKE_GENERATOR_PLATFORM "$generatorArch")',
      'include("$buildkitPath")',
      'apply_buildkit()',
    ].join('\n'));
    return Process.run('cmake', [
      '-S',
      source.parent.path,
      '-B',
      p.join(root.path, 'build'),
      '-G',
      'Ninja',
    ]);
  }

  for (final entry
      in {'windows-arm64': 'arm64', 'windows-x64': 'amd64'}.entries) {
    test('CMake propagates ${entry.key} to Go Core and Rust Helper', () async {
      final result = await configure(target: entry.key);

      expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
      final rules =
          File(p.join(root.path, 'build', 'build.ninja')).readAsStringSync();
      expect(rules, contains('windows --arch ${entry.value}'));
      expect(rules, contains('FlClashCore.exe'));
      expect(rules, contains('FlClashHelperService.exe'));
      expect(rules, contains('manifest.json'));
    });
  }

  test('CMake uses ARM64 generator only without a Flutter target', () async {
    final result = await configure(generatorArch: 'ARM64');

    expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
    final rules =
        File(p.join(root.path, 'build', 'build.ninja')).readAsStringSync();
    expect(rules, contains('windows --arch arm64'));
  });

  test(
      'unsupported Flutter target cannot silently choose the host architecture',
      () async {
    final result =
        await configure(target: 'windows-riscv64', generatorArch: 'ARM64');

    expect(result.exitCode, isNot(0));
    expect('${result.stdout}\n${result.stderr}',
        contains('Unsupported Windows Flutter target'));
  });

  test('missing target and generator architecture cannot silently choose x64',
      () async {
    final result = await configure();

    expect(result.exitCode, isNot(0));
    expect('${result.stdout}\n${result.stderr}',
        contains('Unsupported Windows Flutter target'));
  });
}

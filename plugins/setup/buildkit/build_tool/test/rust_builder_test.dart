import 'dart:io';

import 'package:build_tool/src/build_cache.dart';
import 'package:build_tool/src/error.dart';
import 'package:build_tool/src/options.dart';
import 'package:build_tool/src/rust_builder.dart';
import 'package:build_tool/src/target.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory root;
  late RustBuilder builder;
  late File output;
  late List<List<String>> builds;
  late List<Map<String, String>> buildEnvironments;
  late bool produceOutput;
  late bool failBuild;

  setUp(() {
    root = Directory.systemTemp.createTempSync('windows_helper_target_test_');
    final config = BuildConfig.load(rootDir: root.path);
    final helper = Directory(p.join(root.path, config.helperDir));
    helper.createSync(recursive: true);
    File(p.join(helper.path, 'Cargo.toml')).writeAsStringSync('fixture');
    final staleHost =
        File(p.join(helper.path, 'target', 'release', 'helper.exe'));
    staleHost.parent.createSync(recursive: true);
    staleHost.writeAsStringSync('stale host executable');
    output = File(
        p.join(root.path, 'libclash', 'windows', 'FlClashHelperService.exe'));
    builds = [];
    buildEnvironments = [];
    produceOutput = true;
    failBuild = false;
    builder = RustBuilder(
      rootDir: root.path,
      config: config,
      cache: BuildCache(rootDir: root.path),
      notice: BuildNotice(),
      commandRunner: (executable, arguments, {workingDirectory, environment}) {
        expect(workingDirectory, helper.path);
        expect(executable, anyOf('cargo', 'rustc'));
        return ProcessResult(1, 0, '$executable fixture version', '');
      },
      commandStreamRunner: (executable, arguments,
          {workingDirectory, environment}) async {
        expect(executable, 'cargo');
        expect(workingDirectory, helper.path);
        builds.add(List.of(arguments));
        buildEnvironments.add(Map.of(environment!));
        if (failBuild) throw StateError('cargo failed');
        if (!produceOutput) return;
        final triple = arguments[arguments.indexOf('--target') + 1];
        final targetDir = arguments[arguments.indexOf('--target-dir') + 1];
        final targetOutput =
            File(p.join(targetDir, triple, 'release', 'helper.exe'));
        targetOutput.parent.createSync(recursive: true);
        targetOutput.writeAsStringSync('$triple:${environment['CORE_SHA256']}');
      },
    );
  });

  tearDown(() => root.deleteSync(recursive: true));

  test('ARM64 build copies only the explicit ARM64 Helper output', () async {
    final result = await builder.build(Target.windowsArm64, 'core-a');

    expect(result.rebuilt, isTrue);
    expect(
        builds.single,
        containsAllInOrder([
          'build',
          '--features',
          'windows-service',
          '--release',
          '--target',
          'aarch64-pc-windows-msvc',
          '--target-dir',
        ]));
    expect(p.normalize(builds.single.last),
        p.join(root.path, 'services', 'helper', 'target'));
    expect(output.readAsStringSync(), 'aarch64-pc-windows-msvc:core-a');
    expect(buildEnvironments.single,
        {'CORE_SHA256': 'core-a', 'CORE_NAME': 'FlClashCore.exe'});
  });

  test('x64 build keeps the matching MSVC Helper target', () async {
    await builder.build(Target.windowsAmd64, 'core-a');

    expect(builds.single, contains('x86_64-pc-windows-msvc'));
    expect(output.readAsStringSync(), 'x86_64-pc-windows-msvc:core-a');
  });

  test('unchanged ARM64 build skips Cargo and the pre-build callback',
      () async {
    var preparations = 0;
    Future<void> prepare() async => preparations++;
    await builder.build(Target.windowsArm64, 'core-a', beforeBuild: prepare);
    final result = await builder.build(Target.windowsArm64, 'core-a',
        beforeBuild: prepare);

    expect(result.rebuilt, isFalse);
    expect(builds, hasLength(1));
    expect(preparations, 1);
  });

  test('switching architectures cannot reuse the other bundled Helper',
      () async {
    await builder.build(Target.windowsAmd64, 'core-a');
    await builder.build(Target.windowsArm64, 'core-a');
    final restoredX64 = await builder.build(Target.windowsAmd64, 'core-a');

    expect(restoredX64.rebuilt, isTrue);
    expect(builds, hasLength(3));
    expect(output.readAsStringSync(), 'x86_64-pc-windows-msvc:core-a');
    expect(
        (await builder.build(Target.windowsAmd64, 'core-a')).rebuilt, isFalse);
  });

  test('Core SHA changes rebuild the same architecture with the new SHA',
      () async {
    await builder.build(Target.windowsArm64, 'core-a');
    final result = await builder.build(Target.windowsArm64, 'core-b');

    expect(result.rebuilt, isTrue);
    expect(builds, hasLength(2));
    expect(buildEnvironments.last['CORE_SHA256'], 'core-b');
    expect(output.readAsStringSync(), 'aarch64-pc-windows-msvc:core-b');
  });

  test('missing ARM64 output fails instead of copying stale host output',
      () async {
    produceOutput = false;

    await expectLater(
      builder.build(Target.windowsArm64, 'core-a'),
      throwsA(isA<BuildException>()),
    );
    expect(output.existsSync(), isFalse);
    produceOutput = true;
    expect(
        (await builder.build(Target.windowsArm64, 'core-a')).rebuilt, isTrue);
    expect(builds, hasLength(2));
  });

  test('failed Cargo does not replace an existing bundle or mark a cache hit',
      () async {
    await builder.build(Target.windowsAmd64, 'core-a');
    failBuild = true;

    await expectLater(
        builder.build(Target.windowsArm64, 'core-a'), throwsStateError);
    expect(output.readAsStringSync(), 'x86_64-pc-windows-msvc:core-a');
    failBuild = false;
    expect(
        (await builder.build(Target.windowsArm64, 'core-a')).rebuilt, isTrue);
    expect(builds, hasLength(3));
  });

  test('non-Windows targets fail before invoking Cargo', () async {
    await expectLater(
      builder.build(Target.macosArm64, 'core-a'),
      throwsA(isA<BuildException>()),
    );
    expect(builds, isEmpty);
    expect(output.existsSync(), isFalse);
  });
}

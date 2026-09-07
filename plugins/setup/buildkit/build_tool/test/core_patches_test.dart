import 'dart:io';

import 'package:build_tool/src/core_patches.dart';
import 'package:test/test.dart';

void main() {
  late Directory root;
  late Directory submodule;
  late File target;
  late File unrelated;
  late File patch;
  late String revision;

  ProcessResult git(List<String> arguments) {
    final result = Process.runSync(
      'git',
      arguments,
      workingDirectory: submodule.path,
    );
    if (result.exitCode != 0) {
      throw StateError('${arguments.join(' ')}: ${result.stderr}');
    }
    return result;
  }

  CorePatchApplier applier({String? expectedRevision}) => CorePatchApplier(
        rootDirectory: root,
        expectedRevision: expectedRevision ?? revision,
      );

  setUp(() {
    root = Directory.systemTemp.createTempSync('core_patch_test_');
    submodule = Directory('${root.path}/core/Clash.Meta')
      ..createSync(recursive: true);
    target = File('${submodule.path}/listener.txt')
      ..writeAsStringSync('before\n');
    unrelated = File('${submodule.path}/unrelated.txt')
      ..writeAsStringSync('untouched\n');
    git(['init', '--quiet']);
    git(['config', 'user.name', 'Patch Test']);
    git(['config', 'user.email', 'patch-test@example.invalid']);
    git(['config', 'core.autocrlf', 'false']);
    git(['config', 'commit.gpgsign', 'false']);
    git(['add', '.']);
    git(['commit', '--quiet', '-m', 'fixture']);
    revision = git(['rev-parse', 'HEAD']).stdout.toString().trim();
    target.writeAsStringSync('after\n');
    final patchContent = git(['diff', '--binary']).stdout.toString();
    target.writeAsStringSync('before\n');
    patch = File('${root.path}/core/patches/mixed-listener-readiness.patch');
    patch.parent.createSync(recursive: true);
    patch.writeAsStringSync(patchContent);
  });

  tearDown(() {
    root.deleteSync(recursive: true);
  });

  test('applies a checked patch without modifying the index', () {
    final indexBefore = git(['ls-files', '--stage']).stdout;
    expect(applier().apply(), isTrue);
    expect(target.readAsStringSync(), 'after\n');
    expect(git(['ls-files', '--stage']).stdout, indexBefore);
  });

  test('accepts an exact already applied patch idempotently', () {
    expect(applier().apply(), isTrue);
    expect(applier().apply(), isFalse);
    expect(target.readAsStringSync(), 'after\n');
  });

  test('supports a Windows CRLF checkout with Git text conversion', () {
    git(['config', 'core.autocrlf', 'true']);
    target.writeAsStringSync('before\r\n');
    expect(applier().apply(), isTrue);
    expect(target.readAsStringSync().replaceAll('\r\n', '\n'), 'after\n');
    expect(applier().apply(), isFalse);
  });

  test('repository attributes keep patches LF with Windows Git conversion', () {
    var project = Directory.current.absolute;
    while (!File('${project.path}/.gitattributes').existsSync() ||
        !Directory('${project.path}/core/patches').existsSync()) {
      final parent = project.parent;
      if (parent.path == project.path) {
        throw StateError('Cannot locate repository patch attributes');
      }
      project = parent;
    }
    File('${root.path}/.gitattributes').writeAsStringSync(
      File('${project.path}/.gitattributes').readAsStringSync(),
    );
    ProcessResult rootGit(List<String> arguments) {
      final result = Process.runSync(
        'git',
        arguments,
        workingDirectory: root.path,
      );
      if (result.exitCode != 0) {
        throw StateError('${arguments.join(' ')}: ${result.stderr}');
      }
      return result;
    }

    rootGit(['init', '--quiet']);
    rootGit(['config', 'core.autocrlf', 'true']);
    rootGit([
      'add',
      '--',
      '.gitattributes',
      'core/patches/mixed-listener-readiness.patch',
    ]);
    patch.deleteSync();
    rootGit([
      'checkout-index',
      '--',
      'core/patches/mixed-listener-readiness.patch',
    ]);
    expect(patch.readAsBytesSync(), isNot(contains(13)));
    git(['config', 'core.autocrlf', 'true']);
    target.writeAsStringSync('before\r\n');
    final indexBefore = git(['ls-files', '--stage']).stdout;
    expect(applier().apply(), isTrue);
    expect(target.readAsStringSync().replaceAll('\r\n', '\n'), 'after\n');
    expect(applier().apply(), isFalse);
    expect(git(['ls-files', '--stage']).stdout, indexBefore);
  });

  test('preserves unrelated working tree and staged changes', () {
    unrelated.writeAsStringSync('staged user change\n');
    git(['add', 'unrelated.txt']);
    unrelated.writeAsStringSync('unstaged user change\n');
    final indexBefore = git(['ls-files', '--stage']).stdout;
    expect(applier().apply(), isTrue);
    expect(unrelated.readAsStringSync(), 'unstaged user change\n');
    expect(git(['ls-files', '--stage']).stdout, indexBefore);
    expect(applier().apply(), isFalse);
  });

  test('rejects an unexpected submodule revision without writing', () {
    expect(
      () => applier(
        expectedRevision: '0000000000000000000000000000000000000000',
      ).apply(),
      throwsA(isA<CorePatchException>()),
    );
    expect(target.readAsStringSync(), 'before\n');
  });

  test('rejects dirty overlap without discarding user content', () {
    target.writeAsStringSync('user change\n');
    expect(() => applier().apply(), throwsA(isA<CorePatchException>()));
    expect(target.readAsStringSync(), 'user change\n');
  });

  test('rejects extra edits in an already patched target', () {
    expect(applier().apply(), isTrue);
    target.writeAsStringSync('after\nextra user change\n');
    expect(() => applier().apply(), throwsA(isA<CorePatchException>()));
    expect(target.readAsStringSync(), 'after\nextra user change\n');
  });

  test('rejects a patch that does not apply to the pinned base', () {
    patch.writeAsStringSync(
      patch.readAsStringSync().replaceFirst('-before', '-other'),
    );
    expect(() => applier().apply(), throwsA(isA<CorePatchException>()));
    expect(target.readAsStringSync(), 'before\n');
  });

  test('rejects a missing required patch', () {
    patch.deleteSync();
    expect(() => applier().apply(), throwsA(isA<CorePatchException>()));
    expect(target.readAsStringSync(), 'before\n');
  });

  test('rejects an uninitialized submodule inheriting a parent repository', () {
    final emptyRoot = Directory('${submodule.path}/nested')..createSync();
    Directory('${emptyRoot.path}/core/Clash.Meta').createSync(recursive: true);
    final nestedPatch = File(
      '${emptyRoot.path}/core/patches/mixed-listener-readiness.patch',
    );
    nestedPatch.parent.createSync(recursive: true);
    patch.copySync(nestedPatch.path);
    expect(
      () => CorePatchApplier(
        rootDirectory: emptyRoot,
        expectedRevision: revision,
      ).apply(),
      throwsA(isA<CorePatchException>()),
    );
  });
}

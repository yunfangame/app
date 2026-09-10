import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../setup.dart' as setup;

void main() {
  test('Windows runtime preparation preserves spaced paths and target ABI', () {
    final root = p.join(Directory.systemTemp.path, 'Windows package test');
    for (final target in {
      'amd64': 'x64',
      'x64': 'x64',
      'arm64': 'arm64',
    }.entries) {
      final args = setup.windowsRuntimePreparationArgs(root, target.key);
      expect(args[args.indexOf('-Architecture') + 1], target.value);
      expect(
        args[args.indexOf('-File') + 1],
        p.join(root, 'tooling', 'windows', 'prepare_vc_runtime.ps1'),
      );
      expect(
        args[args.indexOf('-OutputDirectory') + 1],
        p.join(root, '.dart_tool', 'windows_runtime', target.value),
      );
    }
    expect(
      () => setup.windowsRuntimePreparationArgs(root, 'x86'),
      throwsArgumentError,
    );
  });

  Future<Directory> createFixture({String? missingLibrary}) async {
    final root = await Directory.systemTemp.createTemp('fengwo runtime cmake ');
    addTearDown(() => root.delete(recursive: true));
    Future<void> write(String relativePath, String content) async {
      final file = File(p.join(root.path, relativePath));
      await file.parent.create(recursive: true);
      await file.writeAsString(content);
    }

    await write(
      'windows/packaging/vc_runtime.cmake',
      await File('windows/packaging/vc_runtime.cmake').readAsString(),
    );
    await write('windows/packaging/exe/vc_runtime_code.iss', 'runtime logic');
    await write('.dart_tool/windows_runtime/x64/vc_runtime.iss', 'metadata');
    await write('.dart_tool/windows_runtime/x64/vc_redist.exe', 'installer');
    for (final name in [
      'vcruntime140.dll',
      'vcruntime140_1.dll',
      'msvcp140.dll',
    ]) {
      if (name != missingLibrary) await write('crt/$name', name);
    }
    await write('modules/InstallRequiredSystemLibraries.cmake', r'''
set(CMAKE_MSVC_ARCH x64)
if(DEFINED MSVC_REDIST_DIR)
  set(test_runtime_dir "${MSVC_REDIST_DIR}")
else()
  set(test_runtime_dir "${CMAKE_CURRENT_SOURCE_DIR}/crt")
endif()
set(CMAKE_INSTALL_SYSTEM_RUNTIME_LIBS
  "${test_runtime_dir}/vcruntime140.dll"
  "${test_runtime_dir}/vcruntime140_1.dll"
  "${test_runtime_dir}/msvcp140.dll")
''');
    await write('CMakeLists.txt', r'''
cmake_minimum_required(VERSION 3.14)
project(RuntimeBundleTest NONE)
set(CMAKE_MODULE_PATH "${CMAKE_CURRENT_SOURCE_DIR}/modules")
set(INSTALL_BUNDLE_LIB_DIR "${CMAKE_INSTALL_PREFIX}")
include(windows/packaging/vc_runtime.cmake)
''');
    return root;
  }

  Future<ProcessResult> configure(Directory root, String outputName) {
    return Process.run('cmake', [
      '-S',
      root.path,
      '-B',
      p.join(root.path, 'build-$outputName'),
      '-DCMAKE_INSTALL_PREFIX=${p.join(root.path, outputName)}',
      '-DMSVC_REDIST_DIR=${p.join(root.path, 'obsolete-crt')}',
    ]);
  }

  test(
    'CMake installs release CRT and offline prerequisites beside app',
    () async {
      final root = await createFixture();
      for (final config in ['Release', 'Debug']) {
        final configured = await configure(root, config);
        expect(configured.exitCode, 0, reason: configured.stderr.toString());
        final installed = await Process.run('cmake', [
          '--install',
          p.join(root.path, 'build-$config'),
          '--config',
          config,
          '--component',
          'Runtime',
        ]);
        expect(installed.exitCode, 0, reason: installed.stderr.toString());
        for (final relativePath in [
          'vcruntime140.dll',
          'vcruntime140_1.dll',
          'msvcp140.dll',
          'prerequisites/vc_redist.exe',
          'prerequisites/vc_runtime.iss',
          'prerequisites/vc_runtime_code.iss',
        ]) {
          expect(
            File(p.join(root.path, config, relativePath)).existsSync(),
            config == 'Release',
            reason: '$config: $relativePath',
          );
        }
      }
    },
  );

  for (final library in [
    'vcruntime140.dll',
    'vcruntime140_1.dll',
    'msvcp140.dll',
  ]) {
    test('CMake refuses incomplete redistribution without $library', () async {
      final root = await createFixture(missingLibrary: library);
      final result = await configure(root, 'Release');
      expect(result.exitCode, isNot(0));
      expect(result.stderr.toString(), contains(library));
    });
  }

  test('cached CMake build picks up newly prepared runtime payload', () async {
    final root = await createFixture();
    final cache = p.join(root.path, '.dart_tool', 'windows_runtime', 'x64');
    final payload = File(p.join(cache, 'vc_redist.exe'));
    final metadata = File(p.join(cache, 'vc_runtime.iss'));
    await payload.delete();
    await metadata.delete();
    final configured = await configure(root, 'Release');
    expect(configured.exitCode, 0, reason: configured.stderr.toString());
    await payload.writeAsString('new installer');
    await metadata.writeAsString('new metadata');
    final installed = await Process.run('cmake', [
      '--install',
      p.join(root.path, 'build-Release'),
      '--config',
      'Release',
      '--component',
      'Runtime',
    ]);
    expect(installed.exitCode, 0, reason: installed.stderr.toString());
    expect(
      await File(
        p.join(root.path, 'Release', 'prerequisites', 'vc_redist.exe'),
      ).readAsString(),
      'new installer',
    );
  });
}

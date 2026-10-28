import 'package:build_tool/src/error.dart';
import 'package:build_tool/src/target.dart';
import 'package:test/test.dart';

void main() {
  group('resolveWindowsTargets', () {
    test('uses the native host architecture without an override', () {
      expect(Target.resolveWindowsTargets(hostArch: 'arm64'),
          [Target.windowsArm64]);
      expect(Target.resolveWindowsTargets(hostArch: 'amd64'),
          [Target.windowsAmd64]);
    });

    test('uses an explicit Windows Core and Helper target', () {
      expect(
        Target.resolveWindowsTargets(archName: 'arm64', hostArch: 'amd64'),
        [Target.windowsArm64],
      );
      expect(
        Target.resolveWindowsTargets(archName: 'amd64', hostArch: 'arm64'),
        [Target.windowsAmd64],
      );
    });

    test('rejects unsupported Windows targets', () {
      for (final arch in ['arm', 'x86', 'riscv64']) {
        expect(
          () => Target.resolveWindowsTargets(archName: arch, hostArch: 'amd64'),
          throwsA(isA<BuildException>()),
        );
      }
    });

    test('resolves the matching MSVC target for the Windows Helper', () {
      expect(Target.windowsArm64.windowsRustTriple, 'aarch64-pc-windows-msvc');
      expect(Target.windowsAmd64.windowsRustTriple, 'x86_64-pc-windows-msvc');
      expect(
        () => Target.macosArm64.windowsRustTriple,
        throwsA(isA<BuildException>()),
      );
      expect(
        () => const Target(goos: 'windows', goarch: 'arm').windowsRustTriple,
        throwsA(isA<BuildException>()),
      );
    });
  });

  group('resolveAndroidTargets', () {
    test('defaults to all Android targets', () {
      final targets = Target.resolveAndroidTargets();

      expect(targets,
          [Target.androidArm, Target.androidArm64, Target.androidAmd64]);
    });

    test('maps a Flutter target platform to the matching Android target', () {
      final targets = Target.resolveAndroidTargets(
        flutterTargetPlatforms: 'android-arm64',
      );

      expect(targets, [Target.androidArm64]);
    });

    test('maps multiple Flutter target platforms in order', () {
      final targets = Target.resolveAndroidTargets(
        flutterTargetPlatforms: 'android-arm64,android-x64',
      );

      expect(targets, [Target.androidArm64, Target.androidAmd64]);
    });

    test('uses explicit arch when provided', () {
      final targets = Target.resolveAndroidTargets(archName: 'arm');

      expect(targets, [Target.androidArm]);
    });

    test('rejects unsupported Flutter target platforms', () {
      expect(
        () => Target.resolveAndroidTargets(
          flutterTargetPlatforms: 'android-riscv64',
        ),
        throwsA(isA<BuildException>()),
      );
    });
  });

  group('resolveMacosTargets', () {
    test('resolves a Universal 2 build to both macOS architectures', () {
      final targets = Target.resolveMacosTargets(
        archName: 'universal',
        hostArch: 'arm64',
      );

      expect(targets, [Target.macosArm64, Target.macosAmd64]);
    });

    test('uses the host architecture when no override is provided', () {
      final targets = Target.resolveMacosTargets(hostArch: 'amd64');

      expect(targets, [Target.macosAmd64]);
    });

    test('rejects unsupported macOS architectures', () {
      expect(
        () => Target.resolveMacosTargets(
          archName: 'riscv64',
          hostArch: 'arm64',
        ),
        throwsA(isA<BuildException>()),
      );
    });
  });
}

import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:path/path.dart' as p;

const _allTargets = <String, String>{
  'android': 'apk',
  'linux': 'deb',
  'macos': 'pkg',
  'windows': 'exe,zip',
};

const _androidFlutterTarget = {
  'arm': 'android-arm',
  'arm64': 'android-arm64',
  'amd64': 'android-x64',
};

const _hostPlatform = {
  'linux': 'linux',
  'macos': 'macos',
  'windows': 'windows',
};

Future<void> main(List<String> args) async {
  final parser = createSetupArgParser();

  if (args.contains('--help') || args.contains('-h')) {
    _showHelp(parser);
    exit(0);
  }

  final results = parser.parse(args);
  final rest = results.rest;

  final hostOs = Platform.operatingSystem;
  final host = _hostPlatform[hostOs];
  if (host == null) {
    stderr.writeln('Unsupported host platform: $hostOs');
    exit(1);
  }

  final platform = rest.isNotEmpty ? rest.first : host;

  if (platform != host && platform != 'android') {
    stderr.writeln(
      'Cannot build "$platform" on $hostOs. Allowed: $host, android',
    );
    _showHelp(parser);
    exit(1);
  }

  final env = results['env'] as String;
  final rootDir = Directory.current.path;
  final arch = _detectArch();
  final targets = _getTargets(platform, arch, results['targets']);
  final androidArch = results['arch'] as String?;
  final verbose = results['verbose'] as bool;
  final macOsFileSecretStorage = results['macos-file-secret-storage'] as bool;

  final exitCode = await _package(
    platform,
    env,
    targets,
    rootDir,
    arch,
    androidArch: androidArch,
    verbose: verbose,
    macOsFileSecretStorage: macOsFileSecretStorage,
  );
  exit(exitCode);
}

ArgParser createSetupArgParser() {
  return ArgParser()
    ..addOption(
      'env',
      defaultsTo: 'stable',
      allowed: ['dev', 'pre', 'stable'],
      help: 'Application environment',
    )
    ..addOption(
      'targets',
      valueHelp: 'exe,zip,pkg,apk,...',
      help: 'Package targets (default: all for platform)',
    )
    ..addOption(
      'arch',
      valueHelp: 'arm,arm64,amd64',
      allowed: ['arm', 'arm64', 'amd64'],
      help: 'Target architecture (Android only)',
    )
    ..addFlag(
      'verbose',
      abbr: 'v',
      negatable: false,
      help: 'Enable verbose Flutter build output',
    )
    ..addFlag(
      'macos-file-secret-storage',
      negatable: false,
      help: 'Use encrypted local secret storage for unsigned macOS builds',
    );
}

List<String> createFlutterBuildArgs({
  required String platform,
  required bool verbose,
}) {
  final flutterBuildArgs = <String>[
    if (verbose) 'verbose',
    'dart-define-from-file=env.json',
  ];
  if (platform == 'android') {
    flutterBuildArgs.add('split-per-abi');
  }
  return flutterBuildArgs;
}

Map<String, String> createBuildEnvironment(String env) {
  return {'APP_ENV': env};
}

Future<Map<String, String>> loadBuildEnvironment(
  String rootDir,
  String env, {
  String? apiHealthConfigUrl,
  bool macOsFileSecretStorage = false,
}) async {
  final environment = createBuildEnvironment(env);
  final keysFile = File(
    p.join(rootDir, 'tooling', 'remote_config', 'keys.json'),
  );
  if (!await keysFile.exists()) {
    throw const FormatException('Missing remote config build keys');
  }
  final decoded = jsonDecode(await keysFile.readAsString());
  if (decoded is! Map ||
      decoded['aesKey'] is! String ||
      decoded['signingPublicKey'] is! String ||
      (decoded['aesKey'] as String).trim().isEmpty ||
      (decoded['signingPublicKey'] as String).trim().isEmpty) {
    throw const FormatException('Invalid remote config build keys');
  }
  environment['REMOTE_CONFIG_AES_KEY'] = decoded['aesKey'] as String;
  environment['REMOTE_CONFIG_SIGNING_PUBLIC_KEY'] =
      decoded['signingPublicKey'] as String;
  final configUrl = apiHealthConfigUrl?.trim();
  if (configUrl != null && configUrl.isNotEmpty) {
    final uri = Uri.tryParse(configUrl);
    if (uri == null ||
        !uri.hasScheme ||
        !uri.hasAuthority ||
        (uri.scheme != 'http' && uri.scheme != 'https') ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty) {
      throw const FormatException('Invalid API health config URL');
    }
    environment['API_HEALTH_CONFIG_URL'] = uri.toString();
  }
  if (macOsFileSecretStorage) {
    environment['MACOS_FILE_SECRET_STORAGE'] = 'true';
  }
  return environment;
}

Future<File> writeBuildEnvironmentFile(
  String rootDir,
  String env, {
  String? apiHealthConfigUrl,
  bool macOsFileSecretStorage = false,
}) async {
  final file = File(p.join(rootDir, 'env.json'));
  await file.writeAsString(
    jsonEncode(
      await loadBuildEnvironment(
        rootDir,
        env,
        apiHealthConfigUrl: apiHealthConfigUrl,
        macOsFileSecretStorage: macOsFileSecretStorage,
      ),
    ),
  );
  return file;
}

String _getTargets(String platform, String arch, String? customTargets) {
  if (customTargets != null) return customTargets;
  if (platform == 'linux' && arch == 'amd64') return 'deb,appimage,rpm';
  return _allTargets[platform]!;
}

void _showHelp(ArgParser parser) {
  stderr.writeln('Usage: dart setup.dart [platform] [options]');
  stderr.writeln('Platform: current host platform (default) or android');
  stderr.writeln();
  stderr.writeln('Default package targets:');
  _allTargets.forEach((p, t) => stderr.writeln('  $p: $t'));
  stderr.writeln();
  stderr.writeln(parser.usage);
}

Future<int> _package(
  String platform,
  String env,
  String targets,
  String rootDir,
  String arch, {
  String? androidArch,
  required bool verbose,
  required bool macOsFileSecretStorage,
}) async {
  await writeBuildEnvironmentFile(
    rootDir,
    env,
    macOsFileSecretStorage: macOsFileSecretStorage,
  );

  final flutterBuildArgs = createFlutterBuildArgs(
    platform: platform,
    verbose: verbose,
  );
  final descriptionArgs = <String>[];
  if (platform != 'android') {
    descriptionArgs.addAll([
      '--description',
      platform == 'macos' ? 'universal' : arch,
    ]);
  }

  final depExit = await _ensureDependencies(platform, arch, targets);
  if (depExit != 0) return depExit;

  final globalPackages = await Process.run(Platform.resolvedExecutable, [
    'pub',
    'global',
    'list',
  ]);
  final distributorInstalled =
      globalPackages.exitCode == 0 &&
      globalPackages.stdout
          .toString()
          .split(RegExp(r'\r?\n'))
          .any((line) => line.startsWith('flutter_distributor '));
  if (!distributorInstalled) {
    final activateResult = await Process.run(Platform.resolvedExecutable, [
      'pub',
      'global',
      'activate',
      '-s',
      'git',
      'https://github.com/chen08209/flutter_distributor.git',
      '--git-ref',
      'FlClash',
      '--git-path',
      'packages/flutter_distributor',
    ]);
    if (activateResult.exitCode != 0) {
      stderr.write(activateResult.stderr);
      return activateResult.exitCode;
    }
  }

  final process = await Process.start(
    'flutter_distributor',
    [
      'package',
      '--skip-clean',
      '--platform',
      platform,
      '--targets',
      targets,
      if (androidArch != null)
        '--build-target-platform=${_androidFlutterTarget[androidArch]!}',
      if (flutterBuildArgs.isNotEmpty)
        '--flutter-build-args=${flutterBuildArgs.join(',')}',
      ...descriptionArgs,
    ],
    includeParentEnvironment: true,
    environment: {'ANDROID_ARCH': ?androidArch},
    runInShell: Platform.isWindows,
  );

  process.stdout.listen((data) {
    stdout.write(utf8.decode(data));
  });
  process.stderr.listen((data) {
    stderr.write(utf8.decode(data));
  });
  final exitCode = await process.exitCode;
  if (exitCode == 0 && platform == 'windows') {
    final runtimeArch = arch == 'arm64' ? 'arm64' : 'x64';
    final verification = await Process.start(
      'powershell.exe',
      [
        '-NoProfile',
        '-NonInteractive',
        '-ExecutionPolicy',
        'Bypass',
        '-File',
        p.join(rootDir, 'tooling', 'windows', 'verify_vc_runtime_bundle.ps1'),
        '-Architecture',
        runtimeArch,
        '-BundleDirectory',
        p.join(rootDir, 'build', 'windows', runtimeArch, 'runner', 'Release'),
      ],
      workingDirectory: rootDir,
      mode: ProcessStartMode.inheritStdio,
    );
    return verification.exitCode;
  }
  if (exitCode == 0 && platform == 'macos') {
    try {
      await verifyUniversalMacosBuild(rootDir);
    } on Object catch (error) {
      stderr.writeln(error);
      return 1;
    }
  }
  if (exitCode == 0 && platform == 'linux') {
    await copyLinuxPreflightScript(rootDir);
  }
  return exitCode;
}

Future<File> copyLinuxPreflightScript(String rootDir) async {
  final source = File(
    p.join(rootDir, 'tooling', 'linux', 'fengwo-linux-preflight.sh'),
  );
  if (!await source.exists()) {
    throw FileSystemException('Missing Linux preflight script', source.path);
  }
  final dist = Directory(p.join(rootDir, 'dist'));
  await dist.create(recursive: true);
  final output = await source.copy(
    p.join(dist.path, 'fengwo-linux-preflight.sh'),
  );
  if (!Platform.isWindows) {
    final chmod = await Process.run('chmod', ['0755', output.path]);
    if (chmod.exitCode != 0) {
      throw FileSystemException(
        'Unable to mark Linux preflight script executable',
        output.path,
      );
    }
  }
  return output;
}

String _detectArch() {
  if (Platform.isWindows) {
    final pa = Platform.environment['PROCESSOR_ARCHITECTURE'] ?? 'AMD64';
    return pa.toUpperCase() == 'ARM64' ? 'arm64' : 'amd64';
  }
  final result = Process.runSync('uname', ['-m']);
  final machine = (result.stdout as String).trim();
  if (machine == 'aarch64') return 'arm64';
  if (machine == 'x86_64') return 'amd64';
  return machine;
}

Future<bool> _hasCommand(String cmd) async {
  final which = Platform.isWindows ? 'where' : 'command';
  final args = Platform.isWindows ? [cmd] : ['-v', cmd];
  final result = await Process.run(which, args);
  return result.exitCode == 0;
}

Future<int> _ensureDependencies(
  String platform,
  String arch,
  String targets,
) async {
  switch (platform) {
    case 'macos':
      return _ensureMacosDependencies(targets);
    case 'linux':
      return _ensureLinuxDependencies(arch);
    case 'windows':
      return prepareWindowsRuntime(Directory.current.path, arch);
    default:
      return 0;
  }
}

List<String> windowsRuntimePreparationArgs(String rootDir, String arch) {
  final runtimeArch = switch (arch) {
    'amd64' || 'x64' => 'x64',
    'arm64' => 'arm64',
    _ => throw ArgumentError.value(arch, 'arch', 'Unsupported Windows target'),
  };
  return [
    '-NoProfile',
    '-NonInteractive',
    '-ExecutionPolicy',
    'Bypass',
    '-File',
    p.join(rootDir, 'tooling', 'windows', 'prepare_vc_runtime.ps1'),
    '-Architecture',
    runtimeArch,
    '-OutputDirectory',
    p.join(rootDir, '.dart_tool', 'windows_runtime', runtimeArch),
  ];
}

Future<int> prepareWindowsRuntime(String rootDir, String arch) async {
  final process = await Process.start(
    'powershell.exe',
    windowsRuntimePreparationArgs(rootDir, arch),
    workingDirectory: rootDir,
    mode: ProcessStartMode.inheritStdio,
  );
  return process.exitCode;
}

bool macosTargetsNeedAppDmg(String targets) {
  return targets.split(',').map((target) => target.trim()).contains('dmg');
}

Future<int> _ensureMacosDependencies(String targets) async {
  if (!macosTargetsNeedAppDmg(targets)) return 0;
  if (await _hasCommand('appdmg')) {
    stdout.writeln('appdmg already installed, skipping.');
    return 0;
  }
  stdout.writeln('Installing appdmg (DMG creator)...');
  final result = await Process.run('npm', ['install', '-g', 'appdmg']);
  if (result.exitCode != 0) {
    stderr.write(result.stderr);
  }
  return result.exitCode;
}

bool hasUniversalMacosArchitectures(String architectures) {
  final values = architectures.trim().split(RegExp(r'\s+')).toSet();
  return values.containsAll({'arm64', 'x86_64'});
}

Future<int> verifyUniversalMacosBuild(String rootDir) async {
  final releaseDirectory = Directory(
    p.join(rootDir, 'build', 'macos', 'Build', 'Products', 'Release'),
  );
  if (!await releaseDirectory.exists()) {
    throw FileSystemException(
      'Missing macOS Release build directory',
      releaseDirectory.path,
    );
  }
  final appBundles = await releaseDirectory
      .list(followLinks: false)
      .where((entity) => entity is Directory && entity.path.endsWith('.app'))
      .cast<Directory>()
      .toList();
  if (appBundles.length != 1) {
    throw StateError(
      'Expected one macOS Release app, found ${appBundles.length}',
    );
  }

  var binaryCount = 0;
  final incomplete = <String>[];
  await for (final entity in appBundles.single.list(
    recursive: true,
    followLinks: false,
  )) {
    if (entity is! File) continue;
    final fileResult = await Process.run('/usr/bin/file', ['-b', entity.path]);
    if (fileResult.exitCode != 0 ||
        !fileResult.stdout.toString().contains('Mach-O')) {
      continue;
    }
    binaryCount++;
    final lipoResult = await Process.run('xcrun', [
      'lipo',
      '-archs',
      entity.path,
    ]);
    if (lipoResult.exitCode != 0 ||
        !hasUniversalMacosArchitectures(lipoResult.stdout.toString())) {
      incomplete.add(p.relative(entity.path, from: appBundles.single.path));
    }
  }
  if (binaryCount == 0) {
    throw StateError('No Mach-O binaries found in ${appBundles.single.path}');
  }
  if (incomplete.isNotEmpty) {
    throw StateError(
      'macOS app is not Universal 2; incomplete binaries: '
      '${incomplete.join(', ')}',
    );
  }
  return binaryCount;
}

Future<int> _ensureLinuxDependencies(String arch) async {
  final pkgGroups = <List<String>>[
    ['ninja-build', 'libgtk-3-dev'],
    ['libayatana-appindicator3-dev'],
    ['libkeybinder-3.0-dev'],
    ['libsecret-1-dev'],
    ['locate'],
  ];
  if (arch == 'amd64') {
    pkgGroups.addAll([
      ['rpm', 'patchelf'],
      ['libfuse2'],
    ]);
  }

  final missingGroups = <List<String>>[];
  for (final group in pkgGroups) {
    final missingPkgs = <String>[];
    for (final pkg in group) {
      if (!await _isDebianPackageInstalled(pkg)) {
        missingPkgs.add(pkg);
      }
    }
    if (missingPkgs.isNotEmpty) {
      missingGroups.add(missingPkgs);
    }
  }

  if (missingGroups.isEmpty) {
    stdout.writeln('All Linux build dependencies already installed, skipping.');
  } else {
    stdout.writeln('Updating apt package lists...');
    final updateExit = await _runLinuxDependencyCommand([
      'apt-get',
      'update',
      '-y',
    ]);
    if (updateExit != 0) {
      stderr.writeln(
        'apt-get update exited with $updateExit; continuing and verifying '
        'dependency installation directly.',
      );
    }

    for (final missingPkgs in missingGroups) {
      stdout.writeln(
        'Installing Linux build dependencies: ${missingPkgs.join(', ')}...',
      );
      final installExit = await _installLinuxPackages(missingPkgs);
      if (installExit != 0) return installExit;
    }
  }

  if (arch == 'amd64') {
    const appimagetool = '/usr/local/bin/appimagetool';
    if (File(appimagetool).existsSync()) {
      stdout.writeln('appimagetool already installed, skipping.');
      return 0;
    }
    stdout.writeln('Downloading appimagetool...');
    final downloadName = arch == 'amd64' ? 'x86_64' : 'aarch64';
    final dlResult = await Process.run('wget', [
      '-O',
      appimagetool,
      'https://github.com/AppImage/AppImageKit/releases/download/continuous/appimagetool-$downloadName.AppImage',
    ]);
    if (dlResult.exitCode != 0) {
      stderr.write(dlResult.stderr);
      return dlResult.exitCode;
    }
    await Process.run('chmod', ['+x', appimagetool]);
  }

  return 0;
}

Future<bool> _isDebianPackageInstalled(String pkg) async {
  final result = await Process.run('dpkg', ['-s', pkg]);
  return result.exitCode == 0 &&
      (result.stdout as String).contains('Status: install ok installed');
}

Future<bool> _areDebianPackagesInstalled(List<String> pkgs) async {
  for (final pkg in pkgs) {
    if (!await _isDebianPackageInstalled(pkg)) {
      return false;
    }
  }
  return true;
}

Future<int> _installLinuxPackages(List<String> pkgs) async {
  final exitCode = await _runLinuxDependencyCommand([
    'apt-get',
    'install',
    '-y',
    ...pkgs,
  ]);
  if (exitCode == 0) return 0;

  if (await _areDebianPackagesInstalled(pkgs)) {
    stderr.writeln(
      'apt-get install exited with $exitCode, but all requested packages are '
      'installed; continuing.',
    );
    return 0;
  }

  return exitCode;
}

Future<int> _runLinuxDependencyCommand(List<String> command) async {
  final sudoCommand = [
    'env',
    'DEBIAN_FRONTEND=noninteractive',
    'NEEDRESTART_MODE=a',
    ...command,
  ];
  stdout.writeln('exec: sudo ${sudoCommand.join(' ')}');
  final result = await Process.start('sudo', sudoCommand);
  result.stdout.listen((data) {
    stdout.write(utf8.decode(data));
  });
  result.stderr.listen((data) {
    stderr.write(utf8.decode(data));
  });
  final exitCode = await result.exitCode;
  if (exitCode != 0) {
    stderr.writeln('Linux dependency command failed with exit code $exitCode.');
  }
  return exitCode;
}

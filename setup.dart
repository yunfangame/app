import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:args/args.dart';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

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

const _androidAbiByArch = {
  'arm': 'armeabi-v7a',
  'arm64': 'arm64-v8a',
  'amd64': 'x86_64',
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
  final androidUniversal = results['universal'] as bool;
  validateAndroidBuildSelection(
    platform: platform,
    androidArch: androidArch,
    androidUniversal: androidUniversal,
  );
  final verbose = results['verbose'] as bool;
  final macOsFileSecretStorage = results['macos-file-secret-storage'] as bool;

  final exitCode = await _package(
    platform,
    env,
    targets,
    rootDir,
    arch,
    androidArch: androidArch,
    androidUniversal: androidUniversal,
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
      'universal',
      negatable: false,
      help: 'Build one Android APK for all three architectures',
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
  String? androidDebugInfoDirectory,
  bool androidUniversal = false,
}) {
  final flutterBuildArgs = <String>[
    if (verbose) 'verbose',
    'dart-define-from-file=env.json',
  ];
  if (platform == 'android') {
    if (androidDebugInfoDirectory == null ||
        androidDebugInfoDirectory.trim().isEmpty ||
        androidDebugInfoDirectory.contains(',')) {
      throw ArgumentError('Android release symbols directory is required');
    }
    flutterBuildArgs.addAll([
      'release',
      if (!androidUniversal) 'split-per-abi',
      'obfuscate',
      'split-debug-info=$androidDebugInfoDirectory',
    ]);
  }
  return flutterBuildArgs;
}

void validateAndroidBuildSelection({
  required String platform,
  String? androidArch,
  bool androidUniversal = false,
}) {
  if (androidUniversal && (platform != 'android' || androidArch != null)) {
    throw ArgumentError(
      '--universal requires Android and cannot be combined with --arch',
    );
  }
  if (androidArch != null && !_androidFlutterTarget.containsKey(androidArch)) {
    throw ArgumentError('Unknown Android architecture');
  }
}

String androidTargetPlatforms({
  String? androidArch,
  bool androidUniversal = false,
}) {
  validateAndroidBuildSelection(
    platform: 'android',
    androidArch: androidArch,
    androidUniversal: androidUniversal,
  );
  return androidArch == null
      ? _androidFlutterTarget.values.join(',')
      : _androidFlutterTarget[androidArch]!;
}

Map<String, String> createPackagingEnvironment({
  required String platform,
  String? androidArch,
}) => {if (platform == 'android') 'ANDROID_ARCH': androidArch ?? ''};

Future<void> validateAndroidReleaseSigningInputs(String rootDir) async {
  final store = File(p.join(rootDir, 'android', 'app', 'keystore.jks'));
  final properties = File(p.join(rootDir, 'android', 'local.properties'));
  if (!await store.exists() ||
      await store.length() == 0 ||
      !await properties.exists()) {
    throw const FormatException('Android release signing inputs are missing');
  }
  final values = <String, String>{};
  final propertyPattern = RegExp(
    r'^\s*(storePassword|keyAlias|keyPassword)(?:\s*[=:]\s*|\s+)(.*)$',
  );
  for (final line in const LineSplitter().convert(
    await properties.readAsString(),
  )) {
    final match = propertyPattern.firstMatch(line);
    if (match != null) values[match.group(1)!] = match.group(2)!.trim();
  }
  if ([
    'storePassword',
    'keyAlias',
    'keyPassword',
  ].any((key) => values[key]?.isNotEmpty != true)) {
    throw const FormatException(
      'Android release signing inputs are incomplete',
    );
  }
}

Future<Directory> prepareAndroidReleaseSymbols(
  String rootDir, {
  String? androidArch,
  bool androidUniversal = false,
}) async {
  validateAndroidBuildSelection(
    platform: 'android',
    androidArch: androidArch,
    androidUniversal: androidUniversal,
  );
  final pubspec = loadYaml(
    await File(p.join(rootDir, 'pubspec.yaml')).readAsString(),
  );
  final version = pubspec is YamlMap ? pubspec['version'] : null;
  if (version is! String ||
      !RegExp(r'^\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?\+\d+$').hasMatch(version)) {
    throw const FormatException(
      'Android release version and build are required',
    );
  }
  if (androidArch != null && !_androidFlutterTarget.containsKey(androidArch)) {
    throw ArgumentError('Unknown Android architecture');
  }
  final parent = Directory(
    p.join(
      rootDir,
      'release-symbols',
      'android',
      version,
      androidUniversal ? 'universal' : androidArch ?? 'all-abis',
    ),
  );
  await parent.create(recursive: true);
  return parent.createTemp('build-');
}

Future<String> androidReleaseArtifactName(String rootDir) async {
  final pubspec =
      loadYaml(await File(p.join(rootDir, 'pubspec.yaml')).readAsString())
          as YamlMap;
  final optionsFile = File(p.join(rootDir, 'distribute_options.yaml'));
  final Map<Object?, Object?> options = await optionsFile.exists()
      ? loadYaml(await optionsFile.readAsString()) as YamlMap
      : <String, Object>{};
  final name = options['app_name'] ?? pubspec['name'];
  final output = options['output'] ?? 'dist/';
  final version = pubspec['version'];
  if (name is! String ||
      name.isEmpty ||
      name.contains(RegExp(r'[/\\]')) ||
      version is! String ||
      !RegExp(r'^\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?\+\d+$').hasMatch(version) ||
      output is! String ||
      p.normalize(output) != 'dist') {
    throw const FormatException('Unsupported Android package output layout');
  }
  return '$name-${version.split('+').first}-android.apk';
}

Future<void> _requireAndroidOutputDirectory(String rootDir, String path) async {
  var current = p.normalize(path);
  final root = p.normalize(rootDir);
  if (!p.isWithin(root, current)) {
    throw FileSystemException('Android output is outside the project', path);
  }
  while (current != root) {
    if (await FileSystemEntity.isLink(current)) {
      throw FileSystemException(
        'Android output must not be a symlink',
        current,
      );
    }
    current = p.dirname(current);
  }
}

Future<List<File>> _androidFlutterApks(String rootDir) async {
  final directory = Directory(
    p.join(rootDir, 'build', 'app', 'outputs', 'flutter-apk'),
  );
  await _requireAndroidOutputDirectory(rootDir, directory.path);
  if (!await directory.exists()) return [];
  final files = <File>[];
  await for (final entry in directory.list(
    recursive: true,
    followLinks: false,
  )) {
    if (!entry.path.endsWith('-release.apk')) continue;
    final relative = p.relative(entry.path, from: directory.path);
    final known = {
      'app-release.apk',
      for (final abi in _androidAbiByArch.values) 'app-$abi-release.apk',
    };
    if (entry is! File || !known.contains(relative)) {
      throw FileSystemException(
        'Unexpected Android release APK was preserved',
        entry.path,
      );
    }
    files.add(entry);
  }
  return files;
}

Future<void> quarantineAndroidReleaseApks(
  String rootDir,
  Directory symbolsDirectory,
) async {
  final artifact = await androidReleaseArtifactName(rootDir);
  final stem = p.basenameWithoutExtension(artifact);
  final flutterApks = await _androidFlutterApks(rootDir);
  final dist = Directory(p.join(rootDir, 'dist'));
  await _requireAndroidOutputDirectory(rootDir, dist.path);
  final candidates = [
    ...flutterApks,
    for (final filename in [
      artifact,
      for (final abi in _androidAbiByArch.values) '$stem-$abi.apk',
    ])
      File(p.join(dist.path, filename)),
  ];
  for (final file in candidates) {
    if (await FileSystemEntity.isLink(file.path)) {
      throw FileSystemException(
        'Android release APK must not be a symlink',
        file.path,
      );
    }
  }
  final records = <Map<String, Object>>[];
  for (final file in candidates) {
    if (!await file.exists()) continue;
    final relative = p.relative(file.path, from: rootDir);
    final archived = File(
      p.join(symbolsDirectory.path, 'previous-apks', relative),
    );
    await archived.parent.create(recursive: true);
    final hash = (await sha256.bind(file.openRead()).first).toString();
    await file.rename(archived.path);
    records.add({
      'original': relative,
      'archived': p.relative(archived.path, from: rootDir),
      'sha256': hash,
    });
  }
  await File(
    p.join(symbolsDirectory.path, 'previous-apks.json'),
  ).writeAsString('${const JsonEncoder.withIndent('  ').convert(records)}\n');
}

Future<Map<String, Object>> _androidFileRecord(
  String rootDir,
  File file,
) async {
  if (!await file.exists() || await file.length() == 0) {
    throw FileSystemException('Missing Android release artifact', file.path);
  }
  return {
    'path': p.relative(file.path, from: rootDir),
    'bytes': await file.length(),
    'sha256': (await sha256.bind(file.openRead()).first).toString(),
  };
}

Future<List<Map<String, Object>>> verifyAndroidReleaseApks(
  String rootDir, {
  String? androidArch,
  bool androidUniversal = false,
}) async {
  validateAndroidBuildSelection(
    platform: 'android',
    androidArch: androidArch,
    androidUniversal: androidUniversal,
  );
  final architectures = androidArch == null
      ? _androidFlutterTarget.keys.toList()
      : [androidArch];
  final expectedNames = {
    if (androidUniversal)
      'app-release.apk'
    else
      for (final arch in architectures)
        'app-${_androidAbiByArch[arch]!}-release.apk',
  };
  final flutterApks = await _androidFlutterApks(rootDir);
  if (flutterApks.length != expectedNames.length ||
      !flutterApks.every(
        (file) => expectedNames.contains(p.basename(file.path)),
      )) {
    throw const FormatException('Android build produced an unexpected ABI set');
  }
  final artifact = await androidReleaseArtifactName(rootDir);
  final stem = p.basenameWithoutExtension(artifact);
  final expectedDist = {
    if (androidUniversal)
      artifact
    else
      for (final arch in architectures) '$stem-${_androidAbiByArch[arch]}.apk',
  };
  final knownDist = {
    artifact,
    for (final abi in _androidAbiByArch.values) '$stem-$abi.apk',
  };
  final dist = Directory(p.join(rootDir, 'dist'));
  await _requireAndroidOutputDirectory(rootDir, dist.path);
  for (final filename in knownDist.difference(expectedDist)) {
    if (await FileSystemEntity.type(
          p.join(dist.path, filename),
          followLinks: false,
        ) !=
        FileSystemEntityType.notFound) {
      throw const FormatException(
        'Android distribution contains an unexpected ABI',
      );
    }
  }
  final records = <Map<String, Object>>[];
  final packages = androidUniversal
      ? ['universal']
      : architectures.map((arch) => _androidAbiByArch[arch]!).toList();
  for (final abi in packages) {
    final expectedAbis = androidUniversal
        ? _androidAbiByArch.values.toSet()
        : {abi};
    final apk = File(
      p.join(
        rootDir,
        'build',
        'app',
        'outputs',
        'flutter-apk',
        androidUniversal ? 'app-release.apk' : 'app-$abi-release.apk',
      ),
    );
    final input = InputFileStream(apk.path);
    try {
      final archive = ZipDecoder().decodeStream(input);
      final libraries = archive.files
          .where(
            (file) =>
                file.isFile &&
                file.name.startsWith('lib/') &&
                file.name.endsWith('.so'),
          )
          .map((file) => file.name)
          .toSet();
      final abis = libraries.map((name) => name.split('/')[1]).toSet();
      if (abis.length != expectedAbis.length ||
          !abis.containsAll(expectedAbis) ||
          !expectedAbis.every(
            (expectedAbi) => [
              'libapp.so',
              'libflutter.so',
              'libclash.so',
            ].every((name) => libraries.contains('lib/$expectedAbi/$name')),
          )) {
        throw const FormatException(
          'Android APK native libraries do not match its ABI',
        );
      }
    } finally {
      await input.close();
    }
    final packaged = File(
      p.join(dist.path, androidUniversal ? artifact : '$stem-$abi.apk'),
    );
    if (await FileSystemEntity.isLink(packaged.path)) {
      throw FileSystemException(
        'Android distribution APK must not be a symlink',
        packaged.path,
      );
    }
    final original = await _androidFileRecord(rootDir, apk);
    final distributed = await _androidFileRecord(rootDir, packaged);
    if (original['bytes'] != distributed['bytes'] ||
        original['sha256'] != distributed['sha256']) {
      throw const FormatException(
        'Android distribution APK differs from the current build',
      );
    }
    records.add({
      'abi': abi,
      'abis': expectedAbis.toList(),
      'apk': original,
      'distributed_apk': distributed,
    });
  }
  return records;
}

Future<File> archiveAndroidReleaseSymbols(
  String rootDir,
  Directory symbolsDirectory, {
  String? androidArch,
  bool androidUniversal = false,
}) async {
  final dartDirectory = Directory(p.join(symbolsDirectory.path, 'dart'));
  final files = <Map<String, Object>>[];
  final apks = await verifyAndroidReleaseApks(
    rootDir,
    androidArch: androidArch,
    androidUniversal: androidUniversal,
  );
  for (final output in apks) {
    final architectures = androidUniversal
        ? _androidAbiByArch.keys.toList()
        : [
            _androidAbiByArch.entries
                .singleWhere((entry) => entry.value == output['abi'])
                .key,
          ];
    final symbols = <Map<String, Object>>[];
    for (final architecture in architectures) {
      final target = _androidFlutterTarget[architecture]!;
      final file = File(p.join(dartDirectory.path, 'app.$target.symbols'));
      symbols.add({
        'abi': _androidAbiByArch[architecture]!,
        ...await _androidFileRecord(rootDir, file),
      });
    }
    files.add({
      ...output,
      'dart_symbols': androidUniversal ? symbols : symbols.single,
    });
  }

  final mapping = File(
    p.join(
      rootDir,
      'build',
      'app',
      'outputs',
      'mapping',
      'release',
      'mapping.txt',
    ),
  );
  await _androidFileRecord(rootDir, mapping);
  final r8Directory = Directory(p.join(symbolsDirectory.path, 'r8'));
  await r8Directory.create(recursive: true);
  final r8Files = <Map<String, Object>>[];
  for (final name in [
    'mapping.txt',
    'configuration.txt',
    'seeds.txt',
    'usage.txt',
    'resources.txt',
  ]) {
    final source = File(p.join(mapping.parent.path, name));
    if (!await source.exists()) continue;
    final output = await source.copy(p.join(r8Directory.path, name));
    r8Files.add(await _androidFileRecord(rootDir, output));
  }
  final pubspec =
      loadYaml(await File(p.join(rootDir, 'pubspec.yaml')).readAsString())
          as YamlMap;
  final manifest = File(p.join(symbolsDirectory.path, 'manifest.json'));
  await manifest.writeAsString(
    '${const JsonEncoder.withIndent('  ').convert({'version': pubspec['version'], 'obfuscated': true, 'universal': androidUniversal, 'artifacts': files, 'r8': r8Files})}\n',
  );
  return manifest;
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
  bool androidUniversal = false,
  required bool verbose,
  required bool macOsFileSecretStorage,
}) async {
  Directory? androidSymbols;
  if (platform == 'android') {
    await validateAndroidReleaseSigningInputs(rootDir);
    androidSymbols = await prepareAndroidReleaseSymbols(
      rootDir,
      androidArch: androidArch,
      androidUniversal: androidUniversal,
    );
  }
  await writeBuildEnvironmentFile(
    rootDir,
    env,
    macOsFileSecretStorage: macOsFileSecretStorage,
  );

  final flutterBuildArgs = createFlutterBuildArgs(
    platform: platform,
    verbose: verbose,
    androidUniversal: androidUniversal,
    androidDebugInfoDirectory: androidSymbols == null
        ? null
        : p.join(androidSymbols.path, 'dart'),
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

  String? androidArtifactName;
  if (platform == 'android') {
    androidArtifactName = await androidReleaseArtifactName(rootDir);
    await quarantineAndroidReleaseApks(rootDir, androidSymbols!);
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
      if (androidArtifactName != null) '--artifact-name=$androidArtifactName',
      if (platform == 'android')
        '--build-target-platform=${androidTargetPlatforms(androidArch: androidArch, androidUniversal: androidUniversal)}',
      if (flutterBuildArgs.isNotEmpty)
        '--flutter-build-args=${flutterBuildArgs.join(',')}',
      ...descriptionArgs,
    ],
    includeParentEnvironment: true,
    environment: createPackagingEnvironment(
      platform: platform,
      androidArch: androidArch,
    ),
    runInShell: Platform.isWindows,
  );

  process.stdout.listen((data) {
    stdout.write(utf8.decode(data));
  });
  process.stderr.listen((data) {
    stderr.write(utf8.decode(data));
  });
  final exitCode = await process.exitCode;
  if (exitCode == 0 && platform == 'android') {
    await archiveAndroidReleaseSymbols(
      rootDir,
      androidSymbols!,
      androidArch: androidArch,
      androidUniversal: androidUniversal,
    );
  }
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

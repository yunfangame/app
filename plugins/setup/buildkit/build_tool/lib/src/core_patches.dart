import 'dart:io';

class CorePatchException implements Exception {
  const CorePatchException(this.message);

  final String message;

  @override
  String toString() => 'CorePatchException: $message';
}

class CorePatchApplier {
  CorePatchApplier({
    required this.rootDirectory,
    this.expectedRevision = '0f7f05adff5e2c49775a112dcfe05a6aa36fda0c',
    this.patchName = 'mixed-listener-readiness.patch',
  });

  final Directory rootDirectory;
  final String expectedRevision;
  final String patchName;

  Directory get _submodule =>
      Directory.fromUri(rootDirectory.absolute.uri.resolve('core/Clash.Meta/'));

  File get _patch => File.fromUri(
    rootDirectory.absolute.uri.resolve('core/patches/$patchName'),
  );

  bool apply() {
    if (!_patch.existsSync()) {
      throw CorePatchException('Missing required Core patch: ${_patch.path}');
    }
    if (!_submodule.existsSync()) {
      throw const CorePatchException(
        'Initialize the Clash.Meta submodule first',
      );
    }
    final repositoryRoot = _git(['rev-parse', '--show-toplevel']);
    if (Directory(
          repositoryRoot.stdout.toString().trim(),
        ).resolveSymbolicLinksSync() !=
        _submodule.resolveSymbolicLinksSync()) {
      throw const CorePatchException(
        'Clash.Meta is not an initialized submodule',
      );
    }
    final gitDirectory = _git([
      'rev-parse',
      '--absolute-git-dir',
    ]).stdout.toString().trim();
    final lock = File(
      '$gitDirectory/fengwo-core-patches.lock',
    ).openSync(mode: FileMode.append);
    try {
      lock.lockSync(FileLock.blockingExclusive);
      return _applyLocked();
    } finally {
      lock.closeSync();
    }
  }

  bool _applyLocked() {
    final revision = _git(['rev-parse', 'HEAD']).stdout.toString().trim();
    if (revision != expectedRevision) {
      throw CorePatchException(
        'Clash.Meta revision mismatch: expected $expectedRevision, got $revision',
      );
    }
    final paths = _git(['apply', '--numstat', '-z', _patch.path]).stdout
        .toString()
        .split('\u0000')
        .where((entry) => entry.isNotEmpty)
        .map((entry) => entry.split('\t'))
        .map((fields) {
          if (fields.length != 3 || fields.last.isEmpty) {
            throw const CorePatchException('Unsupported Core patch target');
          }
          return fields.last;
        })
        .toSet()
        .toList();
    if (paths.isEmpty) {
      throw const CorePatchException('Core patch has no targets');
    }
    final temporaryDirectory = Directory.systemTemp.createTempSync(
      'fengwo-core-patch-',
    );
    final environment = {
      'GIT_INDEX_FILE': '${temporaryDirectory.path}/expected.index',
    };
    try {
      _git(['read-tree', 'HEAD'], environment: environment);
      _git([
        'apply',
        '--cached',
        '--check',
        _patch.path,
      ], environment: environment);
      _git(['apply', '--cached', _patch.path], environment: environment);
      final expected = _git(
        ['diff', '--quiet', '--', ...paths],
        environment: environment,
        allowDifference: true,
      );
      if (expected.exitCode == 0) {
        _git(['apply', '--reverse', '--check', _patch.path]);
        return false;
      }
      final clean = _git([
        'diff',
        '--quiet',
        'HEAD',
        '--',
        ...paths,
      ], allowDifference: true);
      if (clean.exitCode != 0) {
        throw const CorePatchException(
          'Core patch overlaps local changes; preserve or move them before building',
        );
      }
      _git(['apply', '--check', _patch.path]);
      _git(['apply', _patch.path]);
      _git(['apply', '--reverse', '--check', _patch.path]);
      _git(['diff', '--quiet', '--', ...paths], environment: environment);
      return true;
    } finally {
      temporaryDirectory.deleteSync(recursive: true);
    }
  }

  ProcessResult _git(
    List<String> arguments, {
    Map<String, String>? environment,
    bool allowDifference = false,
  }) {
    final result = Process.runSync(
      'git',
      arguments,
      workingDirectory: _submodule.path,
      environment: environment,
    );
    if (result.exitCode != 0 && !(allowDifference && result.exitCode == 1)) {
      throw CorePatchException(
        'git ${arguments.join(' ')} failed: ${result.stderr.toString().trim()}',
      );
    }
    return result;
  }
}

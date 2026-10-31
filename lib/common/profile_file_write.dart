import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:collection/collection.dart';

final _profileFileWriteScopeKey = Object();
final _activeProfileFileWriteScopes = <ProfileFileWriteScope>{};
final _profileFileCommits = <String, Future<void>>{};

class ProfileFileWriteReceipt {
  ProfileFileWriteReceipt(this.path, this.bytes);

  final String path;
  final Uint8List? bytes;
  final Object owner = Object();
}

class ProfileFileWriteScope {
  ProfileFileWriteScope(this.path) {
    _activeProfileFileWriteScopes.add(this);
  }

  final String path;
  Object? _currentOwner;
  ProfileFileWriteReceipt? receipt;

  bool get ownsReceipt =>
      receipt != null && identical(_currentOwner, receipt!.owner);

  bool get hasForeignWrite => _currentOwner != null && !ownsReceipt;

  Future<T> run<T>(Future<T> Function() action) =>
      runZoned(action, zoneValues: {_profileFileWriteScopeKey: this});

  void dispose() {
    _activeProfileFileWriteScopes.remove(this);
    receipt = null;
    _currentOwner = null;
  }
}

Future<void> writeProfileFileBytes(
  File file,
  Uint8List bytes, {
  bool Function()? isCurrent,
}) => _withProfileFileCommit(file.path, () async {
  void ensureCurrent() {
    if (isCurrent?.call() == false) {
      throw StateError('profile_sync_superseded');
    }
  }

  ensureCurrent();
  await file.parent.create(recursive: true);
  final temporaryDirectory = await file.parent.createTemp('.profile-write-');
  try {
    final temporaryFile = File('${temporaryDirectory.path}/profile');
    await temporaryFile.writeAsBytes(bytes, flush: true);
    ensureCurrent();
    await temporaryFile.rename(file.path);
    _recordProfileFileCommit(file.path, bytes);
  } finally {
    await temporaryDirectory.delete(recursive: true);
  }
});

Future<void> restoreProfileFileBytes(
  File file,
  Uint8List? bytes, {
  required Uint8List? expectedBytes,
  required bool Function() isCurrent,
}) => _withProfileFileCommit(file.path, () async {
  Future<bool> matchesExpected() async {
    final current = await file.exists() ? await file.readAsBytes() : null;
    return const ListEquality<int>().equals(current, expectedBytes);
  }

  if (!isCurrent() || !await matchesExpected() || !isCurrent()) return;
  if (bytes == null) {
    if (expectedBytes != null) {
      await file.delete();
      _recordProfileFileCommit(file.path, null);
    }
    return;
  }
  final temporaryDirectory = await file.parent.createTemp('.profile-rollback-');
  try {
    final temporaryFile = File('${temporaryDirectory.path}/profile');
    await temporaryFile.writeAsBytes(bytes, flush: true);
    if (!await matchesExpected() || !isCurrent()) return;
    await temporaryFile.rename(file.path);
    _recordProfileFileCommit(file.path, bytes);
  } finally {
    await temporaryDirectory.delete(recursive: true);
  }
});

Future<void> _withProfileFileCommit(
  String path,
  Future<void> Function() commit,
) async {
  final previous = _profileFileCommits[path];
  final completion = Completer<void>();
  _profileFileCommits[path] = completion.future;
  try {
    if (previous != null) await previous;
    await commit();
  } finally {
    completion.complete();
    if (identical(_profileFileCommits[path], completion.future)) {
      _profileFileCommits.remove(path);
    }
  }
}

void _recordProfileFileCommit(String path, Uint8List? bytes) {
  final receipt = ProfileFileWriteReceipt(path, bytes);
  for (final scope in _activeProfileFileWriteScopes) {
    if (scope.path == path) scope._currentOwner = receipt.owner;
  }
  final scope = Zone.current[_profileFileWriteScopeKey];
  if (scope is ProfileFileWriteScope &&
      scope.path == path &&
      _activeProfileFileWriteScopes.contains(scope)) {
    scope.receipt = receipt;
  }
}

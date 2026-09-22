import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
import 'package:shared_preferences_platform_interface/types.dart';

import 'preferences_storage_error.dart';

void installWindowsPreferencesStore({
  bool? isWindows,
  WindowsPreferencesStore? store,
}) {
  if (isWindows ?? Platform.isWindows) {
    SharedPreferencesStorePlatform.instance =
        store ?? WindowsPreferencesStore();
  }
}

Future<void> resetWindowsPreferencesForStartup({
  bool Function(Map<String, Object>)? canRestore,
}) async {
  final store = SharedPreferencesStorePlatform.instance;
  if (store is! WindowsPreferencesStore) {
    throw PreferenceStorageException(
      operation: 'initialize',
      cause: StateError('Windows preferences store is not installed'),
    );
  }
  await store.resetForStartup(canRestore: canRestore);
}

class WindowsPreferencesStore extends SharedPreferencesStorePlatform {
  WindowsPreferencesStore({
    Future<Directory> Function()? directoryLoader,
    void Function(PreferenceStorageException)? onDiagnostic,
    this.beforeCommit,
  }) : _directoryLoader = directoryLoader ?? getApplicationSupportDirectory,
       _onDiagnostic = onDiagnostic ?? _reportDiagnostic;

  final Future<Directory> Function() _directoryLoader;
  final void Function(PreferenceStorageException) _onDiagnostic;
  final FutureOr<void> Function(File temporary, File destination)? beforeCommit;
  Future<void> _pending = Future<void>.value();
  File? _file;
  int _archiveSequence = 0;

  static void _reportDiagnostic(PreferenceStorageException error) {
    debugPrint('本地配置备用副本维护失败：$error');
  }

  Future<T> _serialize<T>(Future<T> Function() action) {
    final result = _pending.then((_) => action());
    _pending = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }

  Future<File> _getFile() async {
    if (_file case final file?) return file;
    try {
      final directory = await _directoryLoader();
      return _file = File(path.join(directory.path, 'shared_preferences.json'));
    } catch (error) {
      throw PreferenceStorageException(operation: 'initialize', cause: error);
    }
  }

  Future<List<int>?> _readBytes(File file) async {
    try {
      return await file.readAsBytes();
    } on FileSystemException catch (error) {
      final code = error.osError?.errorCode;
      if (code == 2 || (Platform.isWindows && code == 3)) return null;
      throw PreferenceStorageException(
        operation: 'read',
        cause: error,
        path: file.path,
      );
    } catch (error) {
      throw PreferenceStorageException(
        operation: 'read',
        cause: error,
        path: file.path,
      );
    }
  }

  Map<String, Object> _decode(List<int> bytes, File file) {
    try {
      final value = jsonDecode(utf8.decode(bytes));
      if (value is! Map<String, dynamic>) {
        throw const FormatException('Invalid preferences object');
      }
      final result = <String, Object>{};
      for (final entry in value.entries) {
        final item = entry.value;
        if (item is bool || item is String || (item is num && item.isFinite)) {
          result[entry.key] = item as Object;
        } else if (item is List && item.every((element) => element is String)) {
          result[entry.key] = List<String>.from(item);
        } else {
          throw const FormatException('Invalid preferences value');
        }
      }
      return result;
    } catch (error) {
      throw PreferenceStorageException(
        operation: 'decode',
        cause: error,
        path: file.path,
      );
    }
  }

  Map<String, Object>? _tryDecode(List<int> bytes, File file) {
    try {
      return _decode(bytes, file);
    } on PreferenceStorageException {
      return null;
    }
  }

  Future<_PreferencesSnapshot> _load(File file) async {
    final bytes = await _readBytes(file);
    if (bytes != null) {
      final values = _tryDecode(bytes, file);
      if (values != null) return _PreferencesSnapshot(values, bytes);
    }
    final backup = File('${file.path}.bak');
    final backupBytes = await _readBytes(backup);
    if (backupBytes == null) {
      if (bytes != null) {
        return _reset(file, bytes, null);
      }
      return const _PreferencesSnapshot(<String, Object>{}, null);
    }
    final recovered = _tryDecode(backupBytes, backup);
    if (recovered == null) {
      return _reset(file, bytes, backupBytes);
    }
    if (bytes != null) {
      await _archive(file, bytes);
    }
    await _replace(file, backupBytes, operation: 'recover');
    return _PreferencesSnapshot(recovered, backupBytes);
  }

  Future<void> _archive(File source, List<int> bytes) async {
    final archive = File(
      '${source.path}.recovery-'
      '${DateTime.now().microsecondsSinceEpoch}-$pid-${_archiveSequence++}',
    );
    await _replace(archive, bytes, operation: 'backup');
  }

  Future<_PreferencesSnapshot> _reset(
    File file,
    List<int>? bytes,
    List<int>? backupBytes,
  ) async {
    final backup = File('${file.path}.bak');
    if (bytes != null) await _archive(file, bytes);
    if (backupBytes != null) await _archive(backup, backupBytes);
    final empty = utf8.encode('{}');
    await _replace(backup, empty, operation: 'recover');
    await _replace(file, empty, operation: 'recover');
    return _PreferencesSnapshot(<String, Object>{}, empty);
  }

  Future<void> resetForStartup({
    bool Function(Map<String, Object>)? canRestore,
  }) {
    return _serialize(() async {
      final file = await _getFile();
      final bytes = await _readBytes(file);
      final backup = File('${file.path}.bak');
      final backupBytes = await _readBytes(backup);
      if (canRestore != null && backupBytes != null) {
        final values = _tryDecode(backupBytes, backup);
        if (values != null && canRestore(values)) {
          if (bytes != null) await _archive(file, bytes);
          await _replace(file, backupBytes, operation: 'recover');
          return;
        }
      }
      await _reset(file, bytes, backupBytes);
    });
  }

  Future<void> _replace(
    File destination,
    List<int> bytes, {
    required String operation,
  }) async {
    Directory? temporaryDirectory;
    try {
      await destination.parent.create(recursive: true);
      temporaryDirectory = await destination.parent.createTemp(
        '.shared_preferences-',
      );
      final temporary = File(
        path.join(temporaryDirectory.path, 'pending.json'),
      );
      await temporary.writeAsBytes(bytes, flush: true);
      await beforeCommit?.call(temporary, destination);
      await temporary.rename(destination.path);
    } catch (error) {
      throw PreferenceStorageException(
        operation: operation,
        cause: error,
        path: destination.path,
      );
    } finally {
      if (temporaryDirectory != null) {
        await _removeTemporaryDirectory(temporaryDirectory);
      }
    }
  }

  Future<void> _removeTemporaryDirectory(Directory directory) async {
    try {
      await directory.delete(recursive: true);
    } on FileSystemException {
      return;
    }
  }

  Future<File?> _retireBackup(File backup) async {
    if (await _readBytes(backup) == null) return null;
    final retired = File('${backup.path}.superseded');
    try {
      await beforeCommit?.call(backup, retired);
      return await backup.rename(retired.path);
    } catch (error) {
      throw PreferenceStorageException(
        operation: 'backup',
        cause: error,
        path: backup.path,
      );
    }
  }

  Future<void> _restoreRetiredBackup(File? retired, File backup) async {
    if (retired == null) return;
    try {
      await retired.rename(backup.path);
    } on FileSystemException catch (error) {
      _onDiagnostic(
        PreferenceStorageException(
          operation: 'backup',
          cause: error,
          path: backup.path,
        ),
      );
      return;
    }
  }

  Future<void> _ensureBackup(File file, List<int>? bytes) async {
    if (bytes == null) return;
    final backup = File('${file.path}.bak');
    try {
      final previous = await _readBytes(backup);
      if (listEquals(previous, bytes) ||
          (previous != null && _tryDecode(previous, backup) != null)) {
        return;
      }
      await _retireBackup(backup);
      await _replace(backup, bytes, operation: 'backup');
    } on PreferenceStorageException catch (error) {
      _onDiagnostic(error);
    }
  }

  Future<bool> _mutate(void Function(Map<String, Object>) update) {
    return _serialize(() async {
      final file = await _getFile();
      final previous = await _load(file);
      final preferences = Map<String, Object>.from(previous.values);
      update(preferences);
      late final List<int> bytes;
      try {
        bytes = utf8.encode(jsonEncode(preferences));
      } catch (error) {
        throw PreferenceStorageException(
          operation: 'write',
          cause: error,
          path: file.path,
        );
      }
      final backup = File('${file.path}.bak');
      final retired = await _retireBackup(backup);
      try {
        await _replace(file, bytes, operation: 'write');
      } catch (_) {
        await _restoreRetiredBackup(retired, backup);
        rethrow;
      }
      try {
        await _replace(backup, bytes, operation: 'backup');
      } on PreferenceStorageException catch (error) {
        _onDiagnostic(error);
        return true;
      }
      return true;
    });
  }

  @override
  Future<Map<String, Object>> getAll() => getAllWithPrefix('flutter.');

  @override
  Future<Map<String, Object>> getAllWithPrefix(String prefix) {
    return getAllWithParameters(
      GetAllParameters(filter: PreferencesFilter(prefix: prefix)),
    );
  }

  @override
  Future<Map<String, Object>> getAllWithParameters(
    GetAllParameters parameters,
  ) {
    final prefix = parameters.filter.prefix;
    final allowList = parameters.filter.allowList?.toSet();
    return _serialize(() async {
      final file = await _getFile();
      final snapshot = await _load(file);
      await _ensureBackup(file, snapshot.bytes);
      return Map<String, Object>.from(snapshot.values)..removeWhere(
        (key, _) =>
            !key.startsWith(prefix) ||
            (allowList != null && !allowList.contains(key)),
      );
    });
  }

  @override
  Future<bool> setValue(String valueType, String key, Object value) {
    final Object copied = value is List<String> ? value.toList() : value;
    final valid = switch (valueType) {
      'Bool' => copied is bool,
      'Double' => copied is double && copied.isFinite,
      'Int' => copied is int,
      'String' => copied is String,
      'StringList' => copied is List<String>,
      _ => false,
    };
    if (!valid) {
      return Future<bool>.error(
        PreferenceStorageException(
          operation: 'write',
          cause: const FormatException('Invalid preferences value type'),
          path: _file?.path,
        ),
      );
    }
    return _mutate((preferences) => preferences[key] = copied);
  }

  @override
  Future<bool> remove(String key) {
    return _mutate((preferences) => preferences.remove(key));
  }

  @override
  Future<bool> clear() => clearWithPrefix('flutter.');

  @override
  Future<bool> clearWithPrefix(String prefix) {
    return clearWithParameters(
      ClearParameters(filter: PreferencesFilter(prefix: prefix)),
    );
  }

  @override
  Future<bool> clearWithParameters(ClearParameters parameters) {
    final prefix = parameters.filter.prefix;
    final allowList = parameters.filter.allowList?.toSet();
    return _mutate(
      (preferences) => preferences.removeWhere(
        (key, _) =>
            key.startsWith(prefix) &&
            (allowList == null || allowList.contains(key)),
      ),
    );
  }
}

class _PreferencesSnapshot {
  const _PreferencesSnapshot(this.values, this.bytes);

  final Map<String, Object> values;
  final List<int>? bytes;
}

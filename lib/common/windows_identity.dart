import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

const windowsDataCompany = 'FengWo';
const windowsDataProduct = '蜂窝加速器';
const windowsUrlScheme = 'fengwo';

const _migrationJournalName = '.fengwo-migration.json';
const _migrationLockName = '.fengwo-migration.lock';
const _migrationStagePrefix = '.fengwo-migration-';
final _migrationQueues = <String, Future<void>>{};

const _persistentEntries = {
  'shared_preferences.json',
  'shared_preferences.json.bak',
  'flutter_secure_storage.dat',
  'database.sqlite',
  'database.sqlite-wal',
  'database.sqlite-shm',
  'profiles',
  'scripts',
  'config.yaml',
  'shared.json',
  'backup.zip',
};

class WindowsIdentityMigrationException implements Exception {
  const WindowsIdentityMigrationException(this.cause);

  final Object cause;

  @override
  String toString() =>
      'WINDOWS-IDENTITY-MIGRATION-FAILED：旧蜂窝数据未能复制，原文件已保留。'
      '请完全退出旧版蜂窝后重试。具体原因：$cause';
}

Future<Directory> prepareWindowsDataDirectory({
  required Directory destination,
  required Directory legacy,
  Future<void> Function(File source, File target)? copyFile,
  Future<void> Function(String name)? onPublished,
}) async {
  if (p.basename(destination.path) != windowsDataProduct ||
      p.basename(p.dirname(destination.path)) != windowsDataCompany) {
    throw ArgumentError.value(destination.path, 'destination');
  }
  if (p.basename(legacy.path) != windowsDataProduct ||
      p.basename(p.dirname(legacy.path)) != 'com.follow') {
    return destination;
  }
  var queueKey = p.normalize(destination.absolute.path);
  if (Platform.isWindows) queueKey = queueKey.toLowerCase();
  final previous = _migrationQueues[queueKey] ?? Future<void>.value();
  final operation = previous.then(
    (_) => _prepareWindowsDataDirectory(
      destination: destination,
      legacy: legacy,
      copyFile: copyFile,
      onPublished: onPublished,
    ),
  );
  final settled = operation.then<void>((_) {}, onError: (Object _) {});
  _migrationQueues[queueKey] = settled;
  try {
    return await operation;
  } finally {
    if (identical(_migrationQueues[queueKey], settled)) {
      _migrationQueues.remove(queueKey);
    }
  }
}

Future<Directory> _prepareWindowsDataDirectory({
  required Directory destination,
  required Directory legacy,
  Future<void> Function(File source, File target)? copyFile,
  Future<void> Function(String name)? onPublished,
}) async {
  final journal = File(p.join(destination.path, _migrationJournalName));
  Directory? staging;
  RandomAccessFile? migrationLock;
  RandomAccessFile? legacyLock;
  var journalPublished = false;
  try {
    if (!await journal.exists() &&
        await FileSystemEntity.type(legacy.path, followLinks: false) !=
            FileSystemEntityType.directory) {
      return destination;
    }
    await destination.parent.create(recursive: true);
    migrationLock = await File(
      p.join(destination.parent.path, _migrationLockName),
    ).open(mode: FileMode.append);
    await migrationLock.lock(FileLock.blockingExclusive);
    final journalType = await FileSystemEntity.type(
      journal.path,
      followLinks: false,
    );
    if (journalType != FileSystemEntityType.notFound) {
      if (journalType != FileSystemEntityType.file) {
        throw const FormatException('Invalid FengWo migration journal');
      }
      final transaction = await _readWindowsMigrationJournal(
        journal,
        destination.parent,
      );
      await _publishWindowsMigration(
        destination: destination,
        journal: journal,
        transaction: transaction,
        onPublished: onPublished,
      );
      return destination;
    }
    if (await FileSystemEntity.type(legacy.path, followLinks: false) !=
        FileSystemEntityType.directory) {
      return destination;
    }
    await destination.create(recursive: true);
    if (await destination.list().any(
      (entry) => p.basename(entry.path) != 'diagnostics',
    )) {
      return destination;
    }
    final lockFile = File(p.join(legacy.path, 'FlClash.lock'));
    if (await lockFile.exists()) {
      legacyLock = await lockFile.open(mode: FileMode.append);
      await legacyLock.lock(FileLock.exclusive);
    }
    staging = await destination.parent.createTemp(_migrationStagePrefix);
    Future<void> copyEntry(FileSystemEntity entry, String target) async {
      final type = await FileSystemEntity.type(entry.path, followLinks: false);
      if (type == FileSystemEntityType.file) {
        final output = File(target);
        if (copyFile != null) {
          await copyFile(File(entry.path), output);
        } else {
          await File(entry.path).copy(target);
        }
      } else if (type == FileSystemEntityType.directory) {
        await Directory(target).create();
        await for (final child in Directory(entry.path).list()) {
          await copyEntry(child, p.join(target, p.basename(child.path)));
        }
      } else {
        throw FileSystemException(
          'Unsupported entry in legacy FengWo data',
          entry.path,
        );
      }
    }

    final entries = <String, String>{};
    await for (final entry in legacy.list()) {
      if (!_persistentEntries.contains(p.basename(entry.path))) continue;
      await copyEntry(entry, p.join(staging.path, p.basename(entry.path)));
      entries[p.basename(entry.path)] = entry is Directory
          ? 'directory'
          : 'file';
    }
    final temporaryJournal = File(p.join(staging.path, 'journal.pending'));
    await temporaryJournal.writeAsString(
      jsonEncode({
        'version': 1,
        'stage': p.basename(staging.path),
        'entries': entries,
      }),
      flush: true,
    );
    await temporaryJournal.rename(journal.path);
    journalPublished = true;
    await _publishWindowsMigration(
      destination: destination,
      journal: journal,
      transaction: _WindowsMigrationTransaction(staging, entries),
      onPublished: onPublished,
    );
  } catch (error) {
    throw WindowsIdentityMigrationException(error);
  } finally {
    try {
      if (legacyLock != null) await legacyLock.close();
    } finally {
      try {
        if (!journalPublished && staging != null && await staging.exists()) {
          await staging.delete(recursive: true);
        }
      } finally {
        if (migrationLock != null) await migrationLock.close();
      }
    }
  }
  return destination;
}

class _WindowsMigrationTransaction {
  const _WindowsMigrationTransaction(this.staging, this.entries);

  final Directory staging;
  final Map<String, String> entries;
}

Future<_WindowsMigrationTransaction> _readWindowsMigrationJournal(
  File journal,
  Directory parent,
) async {
  if (await journal.length() > 65536) {
    throw const FormatException('Invalid FengWo migration journal');
  }
  final value = jsonDecode(await journal.readAsString());
  if (value is! Map || value['version'] != 1) {
    throw const FormatException('Invalid FengWo migration journal');
  }
  final stage = value['stage'];
  final rawEntries = value['entries'];
  if (stage is! String ||
      !RegExp(r'^\.fengwo-migration-[a-zA-Z0-9_-]+$').hasMatch(stage) ||
      rawEntries is! Map) {
    throw const FormatException('Invalid FengWo migration journal');
  }
  final entries = <String, String>{};
  for (final entry in rawEntries.entries) {
    if (entry.key is! String ||
        !_persistentEntries.contains(entry.key) ||
        !const {'file', 'directory'}.contains(entry.value)) {
      throw const FormatException('Invalid FengWo migration journal');
    }
    entries[entry.key as String] = entry.value as String;
  }
  return _WindowsMigrationTransaction(
    Directory(p.join(parent.path, stage)),
    entries,
  );
}

Future<void> _publishWindowsMigration({
  required Directory destination,
  required File journal,
  required _WindowsMigrationTransaction transaction,
  Future<void> Function(String name)? onPublished,
}) async {
  final stagingType = await FileSystemEntity.type(
    transaction.staging.path,
    followLinks: false,
  );
  if (stagingType != FileSystemEntityType.directory &&
      stagingType != FileSystemEntityType.notFound) {
    throw const FormatException('Invalid FengWo migration staging directory');
  }
  final names = transaction.entries.keys.toList()..sort();
  for (final name in names) {
    final source = p.join(transaction.staging.path, name);
    final target = p.join(destination.path, name);
    final sourceType = await FileSystemEntity.type(source, followLinks: false);
    final targetType = await FileSystemEntity.type(target, followLinks: false);
    final expectedType = transaction.entries[name] == 'directory'
        ? FileSystemEntityType.directory
        : FileSystemEntityType.file;
    if (sourceType == FileSystemEntityType.notFound &&
        targetType == expectedType) {
      continue;
    }
    if (sourceType != expectedType ||
        targetType != FileSystemEntityType.notFound) {
      throw FileSystemException('FengWo migration entry conflicts', name);
    }
    if (expectedType == FileSystemEntityType.directory) {
      await Directory(source).rename(target);
    } else {
      await File(source).rename(target);
    }
    await onPublished?.call(name);
  }
  if (await transaction.staging.exists()) await transaction.staging.delete();
  await journal.delete();
}

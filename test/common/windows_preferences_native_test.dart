import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:fl_clash/common/preferences_storage_error.dart';
import 'package:fl_clash/common/windows_preferences.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:win32/win32.dart' as win32;

win32.HANDLE _holdFile(File file, win32.FILE_SHARE_MODE shareMode) {
  final filename = file.path.toNativeUtf16();
  try {
    final result = win32.CreateFile(
      win32.PCWSTR(filename),
      win32.GENERIC_READ | win32.GENERIC_WRITE,
      shareMode,
      null,
      win32.OPEN_EXISTING,
      win32.FILE_ATTRIBUTE_NORMAL,
      null,
    );
    if (result.value == win32.INVALID_HANDLE_VALUE) {
      fail('CreateFileW could not hold the test file: ${result.error}');
    }
    return result.value;
  } finally {
    calloc.free(filename);
  }
}

void _releaseFile(win32.HANDLE handle) {
  final result = win32.CloseHandle(handle);
  expect(result.value, isTrue, reason: 'CloseHandle error: ${result.error}');
}

Matcher _sharingFailure(String operation) {
  return isA<PreferenceStorageException>()
      .having((error) => error.operation, 'operation', operation)
      .having(
        (error) => error.code,
        'recognized Windows sharing error',
        isIn(['PREF-LOCKED', 'PREF-ACCESS']),
      )
      .having(
        (error) => error.cause,
        'original OS error',
        isA<FileSystemException>(),
      );
}

void main() {
  group('native Windows preference file sharing', () {
    late Directory directory;
    late File mainFile;
    late File backupFile;
    late WindowsPreferencesStore store;

    setUp(() async {
      directory = await Directory.systemTemp.createTemp('fengwo-native-prefs-');
      mainFile = File(path.join(directory.path, 'shared_preferences.json'));
      backupFile = File('${mainFile.path}.bak');
      store = WindowsPreferencesStore(directoryLoader: () async => directory);
      await store.setValue('Int', 'flutter.version', 1);
    });

    tearDown(() async {
      await directory.delete(recursive: true);
    });

    test(
      'a handle without delete sharing blocks replacement without corrupting data',
      () async {
        final original = await mainFile.readAsBytes();
        final originalBackup = await backupFile.readAsBytes();
        final handle = _holdFile(
          mainFile,
          win32.FILE_SHARE_READ | win32.FILE_SHARE_WRITE,
        );
        try {
          await expectLater(
            store.setValue('Int', 'flutter.version', 2),
            throwsA(_sharingFailure('write')),
          );
          expect(await mainFile.readAsBytes(), original);
          expect(await backupFile.readAsBytes(), originalBackup);
          expect(await store.getAll(), {'flutter.version': 1});
          expect(
            await directory
                .list()
                .where((entry) => entry.path.contains('.recovery-'))
                .toList(),
            isEmpty,
          );
        } finally {
          _releaseFile(handle);
        }
        expect(await store.setValue('Int', 'flutter.version', 2), isTrue);
        expect(await store.getAll(), {'flutter.version': 2});
        expect(await backupFile.readAsBytes(), await mainFile.readAsBytes());
      },
    );

    test(
      'an exclusive native handle reports read failure and never resets preferences',
      () async {
        final original = await mainFile.readAsBytes();
        final originalBackup = await backupFile.readAsBytes();
        final handle = _holdFile(mainFile, win32.FILE_SHARE_NONE);
        try {
          for (var attempt = 0; attempt < 2; attempt++) {
            await expectLater(store.getAll(), throwsA(_sharingFailure('read')));
          }
          expect(await backupFile.readAsBytes(), originalBackup);
          expect(
            await directory
                .list()
                .where((entry) => entry.path.contains('.recovery-'))
                .toList(),
            isEmpty,
          );
        } finally {
          _releaseFile(handle);
        }
        expect(await mainFile.readAsBytes(), original);
        expect(await backupFile.readAsBytes(), originalBackup);
        expect(await store.getAll(), {'flutter.version': 1});
        expect(await store.setValue('Int', 'flutter.version', 2), isTrue);
        expect(await store.getAll(), {'flutter.version': 2});
      },
    );
  }, skip: !Platform.isWindows);
}

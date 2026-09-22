import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:fl_clash/common/preferences_storage_error.dart';
import 'package:fl_clash/common/windows_preferences.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
import 'package:shared_preferences_platform_interface/types.dart';

void main() {
  late Directory directory;
  late File mainFile;
  late File backupFile;
  late WindowsPreferencesStore store;
  late SharedPreferencesStorePlatform originalStore;

  Future<List<File>> archives() async {
    return directory
        .list()
        .where((entry) => entry is File && entry.path.contains('.recovery-'))
        .cast<File>()
        .toList();
  }

  Future<Map<String, dynamic>> persisted() async {
    return jsonDecode(await mainFile.readAsString()) as Map<String, dynamic>;
  }

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('fengwo-preferences-');
    mainFile = File(path.join(directory.path, 'shared_preferences.json'));
    backupFile = File('${mainFile.path}.bak');
    store = WindowsPreferencesStore(directoryLoader: () async => directory);
    originalStore = SharedPreferencesStorePlatform.instance;
  });

  tearDown(() async {
    SharedPreferencesStorePlatform.instance = originalStore;
    await directory.delete(recursive: true);
  });

  test(
    'registers only on Windows and delegates explicit startup reset',
    () async {
      installWindowsPreferencesStore(isWindows: false, store: store);
      expect(SharedPreferencesStorePlatform.instance, same(originalStore));
      installWindowsPreferencesStore(isWindows: true, store: store);
      expect(SharedPreferencesStorePlatform.instance, same(store));
      await store.setValue('Int', 'flutter.version', 1);
      await resetWindowsPreferencesForStartup();
      expect(await persisted(), isEmpty);
      expect(await archives(), hasLength(2));
    },
  );

  test('fresh install reads empty without creating configuration', () async {
    expect(await store.getAll(), isEmpty);
    expect(await mainFile.exists(), isFalse);
    expect(await directory.list().toList(), isEmpty);
  });

  test(
    'keeps the legacy filename, prefix, values and unrelated keys',
    () async {
      final existing = <String, Object>{
        'flutter.version': 1,
        'flutter.config': '{"user":"test@example.invalid"}',
        'flutter.enabled': true,
        'flutter.scale': 1.25,
        'flutter.tags': ['one', 'two'],
        'native.setting': 'untouched',
      };
      await mainFile.writeAsString(jsonEncode(existing));
      expect(await store.getAll(), Map.of(existing)..remove('native.setting'));
      await store.setValue('Int', 'flutter.version', 2);
      expect(await persisted(), {...existing, 'flutter.version': 2});
      expect(jsonDecode(await backupFile.readAsString()), {
        ...existing,
        'flutter.version': 2,
      });
      expect(await archives(), isEmpty);
    },
  );

  test('reads the latest disk state before each mutation', () async {
    await store.setValue('Int', 'flutter.a', 1);
    await mainFile.writeAsString('{"flutter.a":1,"flutter.external":2}');
    await store.setValue('Int', 'flutter.b', 3);
    expect(await persisted(), {
      'flutter.a': 1,
      'flutter.external': 2,
      'flutter.b': 3,
    });
  });

  test(
    'serializes overlapping operations and snapshots mutable input',
    () async {
      final entered = Completer<void>();
      final release = Completer<void>();
      var first = true;
      store = WindowsPreferencesStore(
        directoryLoader: () async => directory,
        beforeCommit: (_, destination) async {
          if (destination.path == mainFile.path && first) {
            first = false;
            entered.complete();
            await release.future;
          }
        },
      );
      final firstWrite = store.setValue('Int', 'flutter.first', 1);
      await entered.future;
      final values = ['original'];
      final secondWrite = store.setValue('StringList', 'flutter.list', values);
      values.add('mutated');
      final read = store.getAll();
      release.complete();
      await Future.wait([firstWrite, secondWrite]);
      expect(await read, {
        'flutter.first': 1,
        'flutter.list': ['original'],
      });
      final returned = await store.getAll();
      (returned['flutter.list'] as List<String>).add('other');
      expect((await store.getAll())['flutter.list'], ['original']);
    },
  );

  test('honors prefix and allow-list for reads and clear', () async {
    await mainFile.writeAsString(
      '{"flutter.keep":1,"flutter.remove":2,"native.keep":3}',
    );
    expect(
      await store.getAllWithParameters(
        GetAllParameters(
          filter: PreferencesFilter(
            prefix: 'flutter.',
            allowList: {'flutter.remove'},
          ),
        ),
      ),
      {'flutter.remove': 2},
    );
    await store.clearWithParameters(
      ClearParameters(
        filter: PreferencesFilter(
          prefix: 'flutter.',
          allowList: {'flutter.remove'},
        ),
      ),
    );
    expect(await persisted(), {'flutter.keep': 1, 'native.keep': 3});
    await store.clear();
    expect(await persisted(), {'native.keep': 3});
    await store.remove('native.keep');
    expect(await persisted(), isEmpty);
  });

  for (final bad in [
    '',
    '{"secret":"truncated',
    '[]',
    'null',
    '{"x":null}',
    '{"x":{"nested":true}}',
    '{"x":[1]}',
    '{"x":1e400}',
  ]) {
    test(
      'archives invalid content then initializes: ${bad.length} ${bad.hashCode}',
      () async {
        await mainFile.writeAsString(bad);
        expect(await store.getAll(), isEmpty);
        expect(await persisted(), isEmpty);
        expect(jsonDecode(await backupFile.readAsString()), isEmpty);
        final saved = await archives();
        expect(saved, hasLength(1));
        expect(await saved.single.readAsString(), bad);
      },
    );
  }

  test('recovers valid backup before choosing a fresh install', () async {
    const damaged = '{"flutter.secret":"private';
    const valid = '{"flutter.version":1,"flutter.account":"preserved"}';
    await mainFile.writeAsString(damaged);
    await backupFile.writeAsString(valid);
    expect(await store.getAll(), {
      'flutter.version': 1,
      'flutter.account': 'preserved',
    });
    expect(await mainFile.readAsString(), valid);
    expect(await backupFile.readAsString(), valid);
    expect(await (await archives()).single.readAsString(), damaged);
  });

  test('recovers a missing primary file from the valid backup', () async {
    await backupFile.writeAsString('{"flutter.version":1}');
    expect(await store.getAll(), {'flutter.version': 1});
    expect(await mainFile.readAsString(), await backupFile.readAsString());
    expect(await archives(), isEmpty);
  });

  test('keeps a valid primary even when an old backup is corrupt', () async {
    await mainFile.writeAsString('{"flutter.version":1}');
    await backupFile.writeAsString('bad-backup');
    expect(await store.getAll(), {'flutter.version': 1});
    expect(await archives(), isEmpty);
    expect(await mainFile.readAsString(), '{"flutter.version":1}');
    expect(await backupFile.readAsString(), '{"flutter.version":1}');
    expect(
      await File('${backupFile.path}.superseded').readAsString(),
      'bad-backup',
    );
  });

  test(
    'archives both corrupt files before reset and never reuses old backup',
    () async {
      await mainFile.writeAsString('bad-main');
      await backupFile.writeAsString('bad-backup');
      expect(await store.getAll(), isEmpty);
      expect(
        await Future.wait(
          (await archives()).map((file) => file.readAsString()),
        ),
        unorderedEquals(['bad-main', 'bad-backup']),
      );
      await mainFile.delete();
      expect(await store.getAll(), isEmpty);
      expect(await archives(), hasLength(2));
    },
  );

  test(
    'archives a corrupt backup even when the primary file is absent',
    () async {
      await backupFile.writeAsString('bad-backup');
      expect(await store.getAll(), isEmpty);
      expect(await (await archives()).single.readAsString(), 'bad-backup');
      expect(await persisted(), isEmpty);
    },
  );

  test(
    'explicit reset archives valid files before clearing both stores',
    () async {
      const current = '{"flutter.config":"invalid-config-json"}';
      const backup = '{"flutter.config":"old-config"}';
      await mainFile.writeAsString(current);
      await backupFile.writeAsString(backup);
      await store.resetForStartup();
      expect(await persisted(), isEmpty);
      expect(jsonDecode(await backupFile.readAsString()), isEmpty);
      expect(
        await Future.wait(
          (await archives()).map((file) => file.readAsString()),
        ),
        unorderedEquals([current, backup]),
      );
    },
  );

  test(
    'write failure preserves the original file and permits a later retry',
    () async {
      const original = '{"flutter.version":1,"flutter.preserved":true}';
      await mainFile.writeAsString(original);
      await backupFile.writeAsString(original);
      var fail = true;
      final cause = FileSystemException(
        'denied',
        mainFile.path,
        const OSError('', 5),
      );
      store = WindowsPreferencesStore(
        directoryLoader: () async => directory,
        beforeCommit: (temporary, destination) async {
          expect(await temporary.readAsString(), isNotEmpty);
          if (destination.path == mainFile.path && fail) throw cause;
        },
      );
      await expectLater(
        store.setValue('Int', 'flutter.version', 2),
        throwsA(
          isA<PreferenceStorageException>()
              .having((error) => error.operation, 'operation', 'write')
              .having((error) => error.cause, 'cause', same(cause))
              .having((error) => error.code, 'code', 'PREF-ACCESS'),
        ),
      );
      expect(await mainFile.readAsString(), original);
      expect(await backupFile.readAsString(), original);
      expect(await store.getAll(), jsonDecode(original));
      expect(
        await directory.list().where((entry) => entry is Directory).toList(),
        isEmpty,
      );
      fail = false;
      await store.setValue('Int', 'flutter.version', 2);
      expect((await persisted())['flutter.version'], 2);
    },
  );

  test(
    'failed reset preserves both original files in recovery archives',
    () async {
      const current = '{"flutter.config":"invalid-config-json"}';
      const backup = '{"flutter.config":"old-config"}';
      await mainFile.writeAsString(current);
      await backupFile.writeAsString(backup);
      store = WindowsPreferencesStore(
        directoryLoader: () async => directory,
        beforeCommit: (_, destination) {
          if (destination.path == mainFile.path) {
            throw FileSystemException(
              'locked',
              destination.path,
              const OSError('', 32),
            );
          }
        },
      );
      await expectLater(
        store.resetForStartup(),
        throwsA(isA<PreferenceStorageException>()),
      );
      expect(await mainFile.readAsString(), current);
      expect(
        await Future.wait(
          (await archives()).map((file) => file.readAsString()),
        ),
        unorderedEquals([current, backup]),
      );
    },
  );

  test('backup failure prevents changing the main file', () async {
    const original = '{"flutter.version":1}';
    const previous = '{"flutter.version":0}';
    await mainFile.writeAsString(original);
    await backupFile.writeAsString(previous);
    store = WindowsPreferencesStore(
      directoryLoader: () async => directory,
      beforeCommit: (_, destination) {
        if (destination.path == '${backupFile.path}.superseded') {
          throw FileSystemException(
            'locked',
            destination.path,
            const OSError('', 32),
          );
        }
      },
    );
    await expectLater(
      store.setValue('Int', 'flutter.version', 2),
      throwsA(
        isA<PreferenceStorageException>().having(
          (error) => error.code,
          'code',
          'PREF-LOCKED',
        ),
      ),
    );
    expect(await mainFile.readAsString(), original);
    expect(await backupFile.readAsString(), previous);
  });

  test('archive failure never clears damaged files or valid backup', () async {
    const damaged = 'private broken config';
    const valid = '{"flutter.version":1}';
    await mainFile.writeAsString(damaged);
    await backupFile.writeAsString(valid);
    store = WindowsPreferencesStore(
      directoryLoader: () async => directory,
      beforeCommit: (_, destination) {
        if (destination.path.contains('.recovery-')) {
          throw FileSystemException(
            'full',
            destination.path,
            const OSError('', 112),
          );
        }
      },
    );
    await expectLater(
      store.getAll(),
      throwsA(
        isA<PreferenceStorageException>().having(
          (error) => error.code,
          'code',
          'PREF-DISK',
        ),
      ),
    );
    expect(await mainFile.readAsString(), damaged);
    expect(await backupFile.readAsString(), valid);
    expect(await archives(), isEmpty);
  });

  test(
    'recovery failure preserves damaged original, archive and backup',
    () async {
      const damaged = 'damaged';
      const valid = '{"flutter.version":1}';
      await mainFile.writeAsString(damaged);
      await backupFile.writeAsString(valid);
      store = WindowsPreferencesStore(
        directoryLoader: () async => directory,
        beforeCommit: (_, destination) {
          if (destination.path == mainFile.path) {
            throw FileSystemException(
              'locked',
              destination.path,
              const OSError('', 32),
            );
          }
        },
      );
      await expectLater(
        store.getAll(),
        throwsA(isA<PreferenceStorageException>()),
      );
      expect(await mainFile.readAsString(), damaged);
      expect(await backupFile.readAsString(), valid);
      expect(await (await archives()).single.readAsString(), damaged);
    },
  );

  test('an actual read failure is not treated as corrupt content', () async {
    await Directory(mainFile.path).create();
    await backupFile.writeAsString('{"flutter.version":1}');
    await expectLater(
      store.getAll(),
      throwsA(
        isA<PreferenceStorageException>().having(
          (error) => error.operation,
          'operation',
          'read',
        ),
      ),
    );
    expect(await Directory(mainFile.path).exists(), isTrue);
    expect(await backupFile.readAsString(), '{"flutter.version":1}');
    expect(await archives(), isEmpty);
  });

  test('rejects invalid writes before modifying disk', () async {
    await mainFile.writeAsString('{"flutter.version":1}');
    for (final value in <(String, Object)>[
      ('String', 1),
      ('StringList', [1]),
      ('Double', double.nan),
      ('Unknown', true),
    ]) {
      await expectLater(
        store.setValue(value.$1, 'flutter.bad', value.$2),
        throwsA(isA<PreferenceStorageException>()),
      );
    }
    expect(await mainFile.readAsString(), '{"flutter.version":1}');
    expect(await backupFile.exists(), isFalse);
  });

  test(
    'schema recovery prefers a backup accepted by the startup validator',
    () async {
      await mainFile.writeAsString('{"flutter.config":"broken"}');
      await backupFile.writeAsString('{"flutter.config":"valid"}');
      installWindowsPreferencesStore(isWindows: true, store: store);
      expect(await store.getAll(), {'flutter.config': 'broken'});
      await resetWindowsPreferencesForStartup(
        canRestore: (values) => values['flutter.config'] == 'valid',
      );
      expect(await store.getAll(), {'flutter.config': 'valid'});
      expect(
        await (await archives()).single.readAsString(),
        '{"flutter.config":"broken"}',
      );
    },
  );

  test(
    'schema recovery archives a structurally valid but rejected backup',
    () async {
      await mainFile.writeAsString('{"flutter.config":"broken"}');
      await backupFile.writeAsString('{"flutter.config":"also-broken"}');
      await store.resetForStartup(canRestore: (_) => false);
      expect(await persisted(), isEmpty);
      expect(await archives(), hasLength(2));
    },
  );

  test(
    'recovery cannot resurrect a removed account or cleared preferences',
    () async {
      await store.setValue('String', 'flutter.token', 'test-token');
      await store.remove('flutter.token');
      await mainFile.writeAsString('broken');
      expect(await store.getAll(), isEmpty);
      await store.setValue('String', 'flutter.token', 'test-token');
      await store.clear();
      await mainFile.writeAsString('broken-again');
      expect(await store.getAll(), isEmpty);
      expect(jsonDecode(await backupFile.readAsString()), isEmpty);
    },
  );

  test(
    'a failed redundant backup cannot revive credentials after committed removal',
    () async {
      await store.setValue('String', 'flutter.token', 'test-token');
      var failBackup = true;
      final diagnostics = <PreferenceStorageException>[];
      store = WindowsPreferencesStore(
        directoryLoader: () async => directory,
        onDiagnostic: diagnostics.add,
        beforeCommit: (_, destination) {
          if (destination.path == backupFile.path && failBackup) {
            throw FileSystemException(
              'locked',
              destination.path,
              const OSError('', 32),
            );
          }
        },
      );
      expect(await store.remove('flutter.token'), isTrue);
      expect(diagnostics, hasLength(1));
      expect(diagnostics.single.code, 'PREF-LOCKED');
      expect(await persisted(), isEmpty);
      expect(await backupFile.exists(), isFalse);
      expect(await File('${backupFile.path}.superseded').exists(), isTrue);
      failBackup = false;
      await mainFile.writeAsString('corrupt after committed removal');
      expect(await store.getAll(), isEmpty);
      expect(jsonDecode(await backupFile.readAsString()), isEmpty);
    },
  );

  test('a disabled automatic login setting survives recovery', () async {
    await store.setValue('Bool', 'flutter.autoLogin', true);
    await store.setValue('Bool', 'flutter.autoLogin', false);
    await mainFile.writeAsString('damaged');
    expect(await store.getAll(), {'flutter.autoLogin': false});
  });

  test(
    'reads repair redundant backup and report failure without blocking valid data',
    () async {
      await mainFile.writeAsString('{"flutter.version":1}');
      final diagnostics = <PreferenceStorageException>[];
      var fail = true;
      store = WindowsPreferencesStore(
        directoryLoader: () async => directory,
        onDiagnostic: diagnostics.add,
        beforeCommit: (_, destination) {
          if (destination.path == backupFile.path && fail) {
            throw FileSystemException(
              'sensitive details must not be logged',
              destination.path,
              const OSError('', 112),
            );
          }
        },
      );
      expect(await store.getAll(), {'flutter.version': 1});
      expect(diagnostics, hasLength(1));
      expect(
        diagnostics.single.toString(),
        isNot(contains('sensitive details')),
      );
      expect(diagnostics.single.code, 'PREF-DISK');
      expect(await backupFile.exists(), isFalse);
      fail = false;
      expect(await store.getAll(), {'flutter.version': 1});
      expect(await backupFile.readAsString(), await mainFile.readAsString());
    },
  );
}

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:fl_clash/common/windows_identity.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory root;
  late Directory destination;
  late Directory legacy;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('fengwo-identity-test-');
    destination = Directory(
      p.join(root.path, windowsDataCompany, windowsDataProduct),
    );
    legacy = Directory(p.join(root.path, 'com.follow', windowsDataProduct));
    await legacy.create(recursive: true);
  });

  tearDown(() async => root.delete(recursive: true));

  test(
    'copies branded account data and subscriptions without changing source',
    () async {
      final source = File(p.join(legacy.path, 'shared_preferences.json'));
      await source.writeAsString(
        '{"flutter.xboard.email":"test@example.invalid"}',
      );
      await File(
        p.join(legacy.path, 'flutter_secure_storage.dat'),
      ).writeAsBytes([1, 2, 3, 4]);
      final profiles = Directory(p.join(legacy.path, 'profiles'));
      await profiles.create();
      await File(
        p.join(profiles.path, 'account.yaml'),
      ).writeAsString('synthetic');
      await File(
        p.join(legacy.path, 'FlClash.lock'),
      ).writeAsString('legacy-lock');

      await prepareWindowsDataDirectory(
        destination: destination,
        legacy: legacy,
      );

      expect(
        await File(
          p.join(destination.path, 'shared_preferences.json'),
        ).readAsString(),
        await source.readAsString(),
      );
      expect(
        await File(
          p.join(destination.path, 'flutter_secure_storage.dat'),
        ).readAsBytes(),
        [1, 2, 3, 4],
      );
      expect(
        await File(
          p.join(destination.path, 'profiles', 'account.yaml'),
        ).readAsString(),
        'synthetic',
      );
      expect(
        await File(p.join(destination.path, 'FlClash.lock')).exists(),
        false,
      );
      expect(
        await File(p.join(legacy.path, 'FlClash.lock')).readAsString(),
        'legacy-lock',
      );
      expect(await source.exists(), true);
    },
  );

  test(
    'never imports original FlClash settings or its newer database',
    () async {
      final foreign = Directory(p.join(root.path, 'com.follow', 'FlClash'));
      await foreign.create(recursive: true);
      final file = File(p.join(foreign.path, 'database.sqlite'));
      await file.writeAsString('foreign-schema-10');

      await prepareWindowsDataDirectory(
        destination: destination,
        legacy: foreign,
      );

      expect(
        await File(p.join(destination.path, 'database.sqlite')).exists(),
        false,
      );
      expect(await file.readAsString(), 'foreign-schema-10');
    },
  );

  test('current account data wins over stale legacy account data', () async {
    await destination.create(recursive: true);
    final current = File(p.join(destination.path, 'shared_preferences.json'));
    await current.writeAsString('current-account');
    await File(
      p.join(legacy.path, 'shared_preferences.json'),
    ).writeAsString('legacy-account');

    await prepareWindowsDataDirectory(destination: destination, legacy: legacy);

    expect(await current.readAsString(), 'current-account');
  });

  test('startup diagnostics do not prevent safe legacy data import', () async {
    await Directory(
      p.join(destination.path, 'diagnostics'),
    ).create(recursive: true);
    await File(
      p.join(legacy.path, 'shared_preferences.json'),
    ).writeAsString('legacy-account');

    await prepareWindowsDataDirectory(destination: destination, legacy: legacy);

    expect(
      await File(
        p.join(destination.path, 'shared_preferences.json'),
      ).readAsString(),
      'legacy-account',
    );
  });

  test(
    'failed copying leaves source and destination intact and can retry',
    () async {
      final source = File(p.join(legacy.path, 'shared_preferences.json'));
      await source.writeAsString('remembered-settings');
      await expectLater(
        prepareWindowsDataDirectory(
          destination: destination,
          legacy: legacy,
          copyFile: (_, _) async =>
              throw const FileSystemException('write failed'),
        ),
        throwsA(isA<WindowsIdentityMigrationException>()),
      );
      expect(await source.readAsString(), 'remembered-settings');
      expect(await destination.list().toList(), isEmpty);
      expect(
        await destination.parent
            .list()
            .map((entry) => p.basename(entry.path))
            .where((name) => name != '.fengwo-migration.lock')
            .toList(),
        [windowsDataProduct],
      );

      await prepareWindowsDataDirectory(
        destination: destination,
        legacy: legacy,
      );

      expect(
        await File(
          p.join(destination.path, 'shared_preferences.json'),
        ).readAsString(),
        'remembered-settings',
      );
    },
  );

  test('repeated starts do not recopy legacy data over new settings', () async {
    await File(
      p.join(legacy.path, 'shared_preferences.json'),
    ).writeAsString('legacy-account');
    await prepareWindowsDataDirectory(destination: destination, legacy: legacy);
    final current = File(p.join(destination.path, 'shared_preferences.json'));
    await current.writeAsString('new-account');

    await prepareWindowsDataDirectory(destination: destination, legacy: legacy);

    expect(await current.readAsString(), 'new-account');
  });

  test('rejects a destination outside the owned FengWo namespace', () async {
    await expectLater(
      prepareWindowsDataDirectory(
        destination: Directory(p.join(root.path, 'foreign')),
        legacy: legacy,
      ),
      throwsArgumentError,
    );
    expect(await Directory(p.join(root.path, 'foreign')).exists(), false);
  });

  test(
    'resumes an interrupted publication without rereading old data',
    () async {
      final sourcePreferences = File(
        p.join(legacy.path, 'shared_preferences.json'),
      );
      await sourcePreferences.writeAsString('legacy-account');
      await File(
        p.join(legacy.path, 'flutter_secure_storage.dat'),
      ).writeAsBytes([1, 2, 3, 4]);
      await Directory(p.join(legacy.path, 'profiles')).create();
      await File(
        p.join(legacy.path, 'profiles', 'account.yaml'),
      ).writeAsString('legacy-profile');
      var published = 0;

      await expectLater(
        prepareWindowsDataDirectory(
          destination: destination,
          legacy: legacy,
          onPublished: (_) async {
            if (++published == 1) {
              throw const FileSystemException('publication interrupted');
            }
          },
        ),
        throwsA(isA<WindowsIdentityMigrationException>()),
      );

      expect(published, 1);
      expect(
        await File(p.join(destination.path, '.fengwo-migration.json')).exists(),
        true,
      );
      expect(await sourcePreferences.readAsString(), 'legacy-account');
      await sourcePreferences.writeAsString('later-legacy-account');
      await prepareWindowsDataDirectory(
        destination: destination,
        legacy: legacy,
      );

      expect(
        await File(
          p.join(destination.path, 'shared_preferences.json'),
        ).readAsString(),
        'legacy-account',
      );
      expect(
        await File(
          p.join(destination.path, 'profiles', 'account.yaml'),
        ).readAsString(),
        'legacy-profile',
      );
      expect(
        await File(
          p.join(destination.path, 'flutter_secure_storage.dat'),
        ).readAsBytes(),
        [1, 2, 3, 4],
      );
      expect(
        await File(p.join(destination.path, '.fengwo-migration.json')).exists(),
        false,
      );
      expect(
        await destination.parent
            .list()
            .where(
              (entry) =>
                  p.basename(entry.path).startsWith('.fengwo-migration-'),
            )
            .toList(),
        isEmpty,
      );
      expect(await sourcePreferences.readAsString(), 'later-legacy-account');
    },
  );

  test('resumes pending data even when the old directory is gone', () async {
    await File(
      p.join(legacy.path, 'shared_preferences.json'),
    ).writeAsString('legacy-account');
    await File(
      p.join(legacy.path, 'flutter_secure_storage.dat'),
    ).writeAsBytes([4, 3, 2, 1]);
    await expectLater(
      prepareWindowsDataDirectory(
        destination: destination,
        legacy: legacy,
        onPublished: (_) async =>
            throw const FileSystemException('publication interrupted'),
      ),
      throwsA(isA<WindowsIdentityMigrationException>()),
    );
    await legacy.delete(recursive: true);

    await prepareWindowsDataDirectory(destination: destination, legacy: legacy);

    expect(
      await File(
        p.join(destination.path, 'shared_preferences.json'),
      ).readAsString(),
      'legacy-account',
    );
    expect(
      await File(p.join(destination.path, '.fengwo-migration.json')).exists(),
      false,
    );
  });

  test(
    'pending publication never overwrites conflicting account data',
    () async {
      await File(
        p.join(legacy.path, 'flutter_secure_storage.dat'),
      ).writeAsBytes([1]);
      await File(
        p.join(legacy.path, 'shared_preferences.json'),
      ).writeAsString('legacy-account');
      await expectLater(
        prepareWindowsDataDirectory(
          destination: destination,
          legacy: legacy,
          onPublished: (_) async =>
              throw const FileSystemException('publication interrupted'),
        ),
        throwsA(isA<WindowsIdentityMigrationException>()),
      );
      final current = File(p.join(destination.path, 'shared_preferences.json'));
      await current.writeAsString('current-account');

      await expectLater(
        prepareWindowsDataDirectory(destination: destination, legacy: legacy),
        throwsA(isA<WindowsIdentityMigrationException>()),
      );

      expect(await current.readAsString(), 'current-account');
      expect(
        await File(
          p.join(legacy.path, 'shared_preferences.json'),
        ).readAsString(),
        'legacy-account',
      );
      expect(
        await File(p.join(destination.path, '.fengwo-migration.json')).exists(),
        true,
      );
    },
  );

  test('releases the migration queue after an interrupted operation', () async {
    await File(
      p.join(legacy.path, 'flutter_secure_storage.dat'),
    ).writeAsBytes([1]);
    await File(
      p.join(legacy.path, 'shared_preferences.json'),
    ).writeAsString('legacy-account');
    final first = prepareWindowsDataDirectory(
      destination: destination,
      legacy: legacy,
      onPublished: (_) async =>
          throw const FileSystemException('publication interrupted'),
    );
    final firstAssertion = expectLater(
      first,
      throwsA(isA<WindowsIdentityMigrationException>()),
    );
    final second = prepareWindowsDataDirectory(
      destination: destination,
      legacy: legacy,
    );

    await firstAssertion;
    await second;

    expect(
      await File(
        p.join(destination.path, 'shared_preferences.json'),
      ).readAsString(),
      'legacy-account',
    );
  });

  test(
    'concurrent callers copy once and preserve all staged entries',
    () async {
      await File(
        p.join(legacy.path, 'shared_preferences.json'),
      ).writeAsString('legacy-account');
      final entered = Completer<void>();
      final release = Completer<void>();
      var copies = 0;
      Future<void> copy(File source, File target) async {
        copies++;
        if (!entered.isCompleted) entered.complete();
        await release.future;
        await source.copy(target.path);
      }

      final first = prepareWindowsDataDirectory(
        destination: destination,
        legacy: legacy,
        copyFile: copy,
      );
      await entered.future;
      final second = prepareWindowsDataDirectory(
        destination: destination,
        legacy: legacy,
        copyFile: copy,
      );
      release.complete();
      await Future.wait([first, second]);

      expect(copies, 1);
      expect(
        await File(
          p.join(destination.path, 'shared_preferences.json'),
        ).readAsString(),
        'legacy-account',
      );
    },
  );

  test(
    'rejects an unsafe journal without touching unrelated directories',
    () async {
      await destination.create(recursive: true);
      final foreign = Directory(p.join(root.path, 'foreign'));
      await foreign.create();
      final current = File(p.join(foreign.path, 'shared_preferences.json'));
      await current.writeAsString('foreign-account');
      await File(
        p.join(destination.path, '.fengwo-migration.json'),
      ).writeAsString(
        jsonEncode({
          'version': 1,
          'stage': '../../foreign',
          'entries': {'shared_preferences.json': 'file'},
        }),
      );

      await expectLater(
        prepareWindowsDataDirectory(destination: destination, legacy: legacy),
        throwsA(isA<WindowsIdentityMigrationException>()),
      );

      expect(await current.readAsString(), 'foreign-account');
    },
  );

  test(
    'finishes a journal after its empty staging directory was removed',
    () async {
      await File(
        p.join(legacy.path, 'shared_preferences.json'),
      ).writeAsString('legacy-account');
      await expectLater(
        prepareWindowsDataDirectory(
          destination: destination,
          legacy: legacy,
          onPublished: (_) async =>
              throw const FileSystemException('publication interrupted'),
        ),
        throwsA(isA<WindowsIdentityMigrationException>()),
      );
      final journal = File(p.join(destination.path, '.fengwo-migration.json'));
      final data = jsonDecode(await journal.readAsString()) as Map;
      await Directory(
        p.join(destination.parent.path, data['stage'] as String),
      ).delete();

      await prepareWindowsDataDirectory(
        destination: destination,
        legacy: legacy,
      );

      expect(await journal.exists(), false);
      expect(
        await File(
          p.join(destination.path, 'shared_preferences.json'),
        ).readAsString(),
        'legacy-account',
      );
    },
  );
}

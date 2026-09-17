import 'dart:convert';
import 'dart:io';

import 'package:fl_clash/common/account_rule_backup.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  late Directory directory;
  late File source;
  late File backup;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('account_rule_backup_');
    source = File('${directory.path}/live.sqlite');
    backup = File('${directory.path}/backup.sqlite');
  });

  tearDown(() => directory.delete(recursive: true));

  void seedDatabase({bool accountSchema = true}) {
    final database = sqlite3.open(source.path);
    try {
      database.execute('''
        CREATE TABLE rules (
          id INTEGER PRIMARY KEY,
          content TEXT NOT NULL
        )
      ''');
      database.execute('''
        CREATE TABLE profile_rule_mapping (
          id TEXT PRIMARY KEY,
          profile_id INTEGER,
          rule_id INTEGER NOT NULL REFERENCES rules(id),
          scene TEXT,
          "order" TEXT
          ${accountSchema ? ', account_key TEXT' : ''}
        )
      ''');
      database.execute('''
        INSERT INTO rules VALUES
          (1, 'ordinary-profile.example'),
          (2, 'ordinary-global.example'),
          (3, 'shared.example'),
          (4, 'unlinked-rule.example')
      ''');
      database.execute('''
        INSERT INTO profile_rule_mapping (id, profile_id, rule_id, scene, "order")
        VALUES
          ('profile-rule', 10, 1, 'added', 'a'),
          ('global-rule', NULL, 2, NULL, 'b'),
          ('shared-rule', 10, 3, 'added', 'c')
      ''');
      if (!accountSchema) {
        return;
      }
      database.execute('''
        CREATE TABLE profile_rule_accounts (
          profile_id INTEGER PRIMARY KEY,
          account_key TEXT NOT NULL
        )
      ''');
      database.execute('''
        INSERT INTO profile_rule_accounts VALUES
          (20, 'private-account-key-a'),
          (30, 'private-account-key-b')
      ''');
      database.execute('''
        INSERT INTO rules VALUES
          (5, 'private-account-process.exe'),
          (6, 'private-account-domain.example')
      ''');
      database.execute('''
        INSERT INTO profile_rule_mapping
          (id, rule_id, scene, "order", account_key)
        VALUES
          ('private-account-key-a-shared', 3, 'added', 'a', 'private-account-key-a'),
          ('private-account-key-a-process', 5, 'added', 'b', 'private-account-key-a'),
          ('private-account-key-a-disabled', 5, 'disabled', 'b', 'private-account-key-a'),
          ('private-account-key-b-domain', 6, 'added', 'a', 'private-account-key-b')
      ''');
    } finally {
      database.close();
    }
  }

  test(
    'backup excludes account rules and owner data without changing live data',
    () async {
      seedDatabase();
      final originalBytes = await source.readAsBytes();

      await copyDatabaseWithoutAccountRules(source, backup);

      expect(await source.readAsBytes(), originalBytes);
      final database = sqlite3.open(backup.path);
      try {
        expect(
          database
              .select('SELECT id FROM rules ORDER BY id')
              .map((row) => row['id']),
          [1, 2, 3, 4],
        );
        expect(
          database
              .select('SELECT id FROM profile_rule_mapping ORDER BY id')
              .map((row) => row['id']),
          ['global-rule', 'profile-rule', 'shared-rule'],
        );
        expect(database.select('SELECT * FROM profile_rule_accounts'), isEmpty);
        expect(
          database.select('PRAGMA integrity_check').single['integrity_check'],
          'ok',
        );
      } finally {
        database.close();
      }
      final backupContents = latin1.decode(await backup.readAsBytes());
      expect(backupContents, isNot(contains('private-account-')));
    },
  );

  test('older databases retain ordinary rules unchanged', () async {
    seedDatabase(accountSchema: false);
    final originalBytes = await source.readAsBytes();

    await copyDatabaseWithoutAccountRules(source, backup);

    expect(await backup.readAsBytes(), originalBytes);
    expect(await source.readAsBytes(), originalBytes);
  });

  test('refuses to sanitize the live database in place', () async {
    seedDatabase();
    final originalBytes = await source.readAsBytes();

    await expectLater(
      copyDatabaseWithoutAccountRules(source, source),
      throwsArgumentError,
    );

    expect(await source.readAsBytes(), originalBytes);
  });
}

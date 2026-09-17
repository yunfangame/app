import 'dart:io';

import 'package:sqlite3/sqlite3.dart';

Future<void> copyDatabaseWithoutAccountRules(
  File source,
  File destination,
) async {
  if (source.absolute.path == destination.absolute.path ||
      (await destination.exists() &&
          await FileSystemEntity.identical(source.path, destination.path))) {
    throw ArgumentError('The backup must use a separate database file');
  }
  await source.copy(destination.path);
  final database = sqlite3.open(destination.path);
  try {
    final tables = database
        .select("SELECT name FROM sqlite_master WHERE type = 'table'")
        .map((row) => row['name'] as String)
        .toSet();
    final hasAccountLinks =
        tables.contains('profile_rule_mapping') &&
        database
            .select('PRAGMA table_info(profile_rule_mapping)')
            .any((row) => row['name'] == 'account_key');
    if (!hasAccountLinks && !tables.contains('profile_rule_accounts')) {
      return;
    }
    database.execute('PRAGMA journal_mode = DELETE');
    database.execute('BEGIN IMMEDIATE');
    try {
      if (hasAccountLinks) {
        database.execute('''
          CREATE TEMP TABLE excluded_account_rules AS
          SELECT DISTINCT rule_id FROM profile_rule_mapping
          WHERE account_key IS NOT NULL
        ''');
        database.execute('''
          DELETE FROM profile_rule_mapping WHERE account_key IS NOT NULL
        ''');
        database.execute('''
          DELETE FROM rules
          WHERE id IN (SELECT rule_id FROM excluded_account_rules)
            AND id NOT IN (SELECT rule_id FROM profile_rule_mapping)
        ''');
        database.execute('DROP TABLE excluded_account_rules');
      }
      if (tables.contains('profile_rule_accounts')) {
        database.execute('DELETE FROM profile_rule_accounts');
      }
      database.execute('COMMIT');
    } catch (_) {
      database.execute('ROLLBACK');
      rethrow;
    }
    database.execute('VACUUM');
  } finally {
    database.close();
  }
}

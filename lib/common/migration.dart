import 'dart:io';

import 'package:fl_clash/database/database.dart';
import 'package:fl_clash/models/models.dart';

import 'preferences.dart';
import 'preferences_storage_error.dart';
import 'task.dart';

typedef MigrationTransform =
    Future<MigrationData> Function(Map<String, Object?> configMap);

abstract interface class MigrationStore {
  Future<Map<String, Object?>?> getConfigMap();

  Future<int> getVersion();

  Future<Map<String, Object?>?> getClashConfigMap();

  Future<void> restore(MigrationData data);

  Future<bool> saveConfig(Config config);

  Future<void> clearClashConfig();

  Future<void> setVersion(int version);
}

class _AppMigrationStore implements MigrationStore {
  const _AppMigrationStore();

  @override
  Future<Map<String, Object?>?> getConfigMap() => preferences.getConfigMap();

  @override
  Future<int> getVersion() => preferences.getVersion();

  @override
  Future<Map<String, Object?>?> getClashConfigMap() =>
      preferences.getClashConfigMap();

  @override
  Future<void> restore(MigrationData data) {
    return database.restore(
      data.profiles,
      data.scripts,
      data.rules,
      data.links,
      data.proxyGroups,
    );
  }

  @override
  Future<bool> saveConfig(Config config) => preferences.saveConfig(config);

  @override
  Future<void> clearClashConfig() => preferences.clearClashConfig();

  @override
  Future<void> setVersion(int version) => preferences.setVersion(version);
}

class Migration {
  final MigrationStore _store;
  final MigrationTransform _migrateV0;
  final Future<void> Function()? _recoverDamagedConfig;

  Migration({
    required MigrationStore store,
    MigrationTransform? migrateV0,
    Future<void> Function()? recoverDamagedConfig,
  }) : _store = store,
       _migrateV0 = migrateV0 ?? oldToNowTask,
       _recoverDamagedConfig = recoverDamagedConfig;

  static const currentVersion = 1;

  Future<Config> run() async {
    try {
      return await _load();
    } on PreferenceStorageException catch (error) {
      final recover = _recoverDamagedConfig;
      if (recover == null || error.code != 'PREF-FORMAT') rethrow;
      await recover();
      return _load();
    }
  }

  Future<Config> _load() async {
    final configMap = await _store.getConfigMap();
    final oldVersion = await _store.getVersion();
    if (oldVersion > currentVersion) {
      throw StateError(
        'Local data version $oldVersion is newer than $currentVersion.',
      );
    }

    if (!_isV0(configMap)) {
      var currentConfigMap = configMap;
      final clashConfigMap = oldVersion == 0
          ? await _store.getClashConfigMap()
          : null;
      if (clashConfigMap != null) {
        currentConfigMap = Map<String, Object?>.from(configMap ?? const {});
        currentConfigMap.putIfAbsent('patchClashConfig', () => clashConfigMap);
      }
      final config = _decode(currentConfigMap);
      final storedPassword = _getStoredDavPassword(currentConfigMap);
      final needsPasswordProtection =
          storedPassword != null && storedPassword == config.davProps?.password;
      if (clashConfigMap != null || needsPasswordProtection) {
        await _save(config);
      }
      if (clashConfigMap != null) {
        await _store.clearClashConfig();
        await _store.setVersion(currentVersion);
      }
      return config;
    }

    final clashConfigMap = await _store.getClashConfigMap();
    final legacyConfigMap = Map<String, Object?>.from(configMap!);
    if (clashConfigMap != null) {
      legacyConfigMap['patchClashConfig'] = clashConfigMap;
    }
    final MigrationData data;
    try {
      data = await _migrateV0(legacyConfigMap);
    } on FormatException catch (error, stack) {
      _invalid(error, stack);
    } on TypeError catch (error, stack) {
      _invalid(error, stack);
    } on ArgumentError catch (error, stack) {
      _invalid(error, stack);
    } on StateError catch (error, stack) {
      _invalid(error, stack);
    }
    final config = _decode(data.configMap);
    await _store.restore(data);
    await _save(config);
    if (clashConfigMap != null) await _store.clearClashConfig();
    await _store.setVersion(currentVersion);
    return config;
  }

  Config _decode(Map<String, Object?>? configMap) {
    try {
      return Config.realFromJson(configMap);
    } catch (error, stack) {
      _invalid(error, stack);
    }
  }

  Never _invalid(Object error, StackTrace stack) {
    Error.throwWithStackTrace(
      PreferenceStorageException(operation: 'decode', cause: error),
      stack,
    );
  }

  Future<void> _save(Config config) async {
    if (!await _store.saveConfig(config)) {
      throw PreferenceStorageException(
        operation: 'write',
        cause: StateError('Preference storage rejected the write'),
      );
    }
  }
}

bool _isV0(Map<String, Object?>? configMap) =>
    configMap?['proxiesStyle'] != null;

String? _getStoredDavPassword(Map<String, Object?>? configMap) {
  final dav = configMap?['davProps'] ?? configMap?['dav'];
  if (dav is! Map) {
    return null;
  }
  final password = dav['password'];
  return password is String && password.isNotEmpty ? password : null;
}

final migration = Migration(
  store: const _AppMigrationStore(),
  recoverDamagedConfig: Platform.isWindows
      ? preferences.recoverForStartup
      : null,
);

import 'dart:io';

import 'package:fl_clash/database/database.dart';
import 'package:fl_clash/models/models.dart';

import 'mixed_port.dart';
import 'preferences.dart';
import 'preferences_storage_error.dart';
import 'print.dart';
import 'proxy.dart';
import 'task.dart';

typedef MigrationTransform =
    Future<MigrationData> Function(Map<String, Object?> configMap);

typedef _LoadedMigrationConfig = ({Config config, bool mixedPortMissing});

abstract interface class MigrationStore {
  Future<Map<String, Object?>?> getConfigMap();

  Future<int> getVersion();

  Future<Map<String, Object?>?> getClashConfigMap();

  Future<void> restore(MigrationData data);

  Future<bool> saveConfig(Config config);

  Future<void> clearClashConfig();

  Future<void> setVersion(int version);

  Future<bool> getDesktopMixedPortMigrated();

  Future<void> setDesktopMixedPortMigrated();
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

  @override
  Future<bool> getDesktopMixedPortMigrated() =>
      preferences.getDesktopMixedPortMigrated();

  @override
  Future<void> setDesktopMixedPortMigrated() =>
      preferences.setDesktopMixedPortMigrated();
}

class Migration {
  final MigrationStore _store;
  final MigrationTransform _migrateV0;
  final Config _newInstallDefaults;
  final Future<void> Function()? _recoverDamagedConfig;
  final bool _migrateDesktopMixedPort;
  final Future<bool> Function(int)? _prepareDesktopPortMigration;

  Migration({
    required MigrationStore store,
    MigrationTransform? migrateV0,
    Config? newInstallDefaults,
    Future<void> Function()? recoverDamagedConfig,
    bool migrateDesktopMixedPort = false,
    Future<bool> Function(int)? prepareDesktopPortMigration,
  }) : _store = store,
       _migrateV0 = migrateV0 ?? oldToNowTask,
       _newInstallDefaults =
           newInstallDefaults ?? const Config(themeProps: defaultThemeProps),
       _recoverDamagedConfig = recoverDamagedConfig,
       _migrateDesktopMixedPort = migrateDesktopMixedPort,
       _prepareDesktopPortMigration = prepareDesktopPortMigration;

  static const currentVersion = 1;

  Future<Config> run() async {
    try {
      return await _migrateDesktopPort(await _load());
    } on PreferenceStorageException catch (error) {
      final recover = _recoverDamagedConfig;
      if (recover == null || error.code != 'PREF-FORMAT') rethrow;
      await recover();
      return _migrateDesktopPort(await _load());
    }
  }

  Future<_LoadedMigrationConfig> _load() async {
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
      return (
        config: config,
        mixedPortMissing: _isMixedPortMissing(currentConfigMap),
      );
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
    return (
      config: config,
      mixedPortMissing: _isMixedPortMissing(data.configMap),
    );
  }

  Config _decode(Map<String, Object?>? configMap) {
    if (configMap == null) return _newInstallDefaults;
    try {
      return Config.realFromJson(configMap);
    } catch (error, stack) {
      _invalid(error, stack);
    }
  }

  Future<Config> _migrateDesktopPort(_LoadedMigrationConfig loaded) async {
    final config = loaded.config;
    if (!_migrateDesktopMixedPort) return config;
    if (await _store.getDesktopMixedPortMigrated()) {
      return loaded.mixedPortMissing
          ? config.copyWith(
              patchClashConfig: config.patchClashConfig.copyWith(
                mixedPort: desktopDefaultMixedPort,
              ),
            )
          : config;
    }
    if (config.patchClashConfig.mixedPort == defaultMixedPort) {
      final prepare = _prepareDesktopPortMigration;
      if (prepare != null) {
        try {
          if (!await prepare(defaultMixedPort)) return config;
        } catch (error) {
          commonPrint.event(
            'migration.desktop_port.deferred',
            fields: {
              'port': defaultMixedPort,
              'target_port': desktopDefaultMixedPort,
              'stage': 'native_exception',
              'error_type': error.runtimeType.toString(),
            },
          );
          return config;
        }
      }
    }
    final migrated = config.patchClashConfig.mixedPort == defaultMixedPort
        ? config.copyWith(
            patchClashConfig: config.patchClashConfig.copyWith(
              mixedPort: desktopDefaultMixedPort,
            ),
          )
        : config;
    await _save(migrated);
    await _store.setDesktopMixedPortMigrated();
    return migrated;
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

bool _isMixedPortMissing(Map<String, Object?>? configMap) {
  final patch = configMap?['patchClashConfig'];
  return patch == null || (patch is Map && patch['mixed-port'] == null);
}

String? _getStoredDavPassword(Map<String, Object?>? configMap) {
  final dav = configMap?['davProps'] ?? configMap?['dav'];
  if (dav is! Map) {
    return null;
  }
  final password = dav['password'];
  return password is String && password.isNotEmpty ? password : null;
}

Future<bool> _prepareDesktopMixedPortMigration(int port) async {
  final result = await proxy?.repairStaleProxyDetailed(port);
  if (result?.success != true) {
    commonPrint.event(
      'migration.desktop_port.deferred',
      fields: {
        'port': port,
        'target_port': desktopDefaultMixedPort,
        'stage': result?.stage ?? 'native_unavailable',
        if (result?.errorCode != null) 'error_code': result!.errorCode,
      },
    );
  }
  return result?.success ?? false;
}

final migration = Migration(
  store: const _AppMigrationStore(),
  newInstallDefaults: Platform.isWindows || Platform.isMacOS
      ? const Config(
          themeProps: defaultThemeProps,
          patchClashConfig: PatchClashConfig(
            mixedPort: desktopDefaultMixedPort,
          ),
        )
      : null,
  migrateDesktopMixedPort: Platform.isWindows || Platform.isMacOS,
  prepareDesktopPortMigration: Platform.isWindows || Platform.isMacOS
      ? _prepareDesktopMixedPortMigration
      : null,
  recoverDamagedConfig: Platform.isWindows
      ? preferences.recoverForStartup
      : null,
);

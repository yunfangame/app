import 'dart:convert';

import 'package:fl_clash/common/migration.dart';
import 'package:fl_clash/common/mixed_port.dart';
import 'package:fl_clash/common/preferences_storage_error.dart';
import 'package:fl_clash/models/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Migration', () {
    test(
      'compatible settings without a version are read without rewriting',
      () async {
        final store = _FakeMigrationStore(
          configMap: _createConfigMap(),
          version: 0,
        );
        final config = await Migration(store: store).run();
        expect(config, Config.realFromJson(store.configMap));
        expect(store.events, [
          'getConfigMap',
          'getVersion',
          'getClashConfigMap',
        ]);
        expect(store.restoredData, isNull);
        expect(store.savedConfig, isNull);
      },
    );

    test(
      'first install uses defaults without an empty database restore',
      () async {
        final store = _FakeMigrationStore(configMap: null, version: 0);
        final config = await Migration(store: store).run();
        expect(config, const Config(themeProps: defaultThemeProps));
        expect(store.events, [
          'getConfigMap',
          'getVersion',
          'getClashConfigMap',
        ]);
        expect(store.restoredData, isNull);
        expect(store.savedConfig, isNull);
      },
    );

    test('fresh desktop identity uses a separate listener port', () async {
      final store = _FakeMigrationStore(configMap: null, version: 0);
      final config = await Migration(
        store: store,
        newInstallDefaults: const Config(
          themeProps: defaultThemeProps,
          patchClashConfig: PatchClashConfig(mixedPort: 17980),
        ),
      ).run();
      expect(config.patchClashConfig.mixedPort, 17980);
      expect(store.restoredData, isNull);
    });

    test('desktop defaults preserve a returning user custom port', () async {
      final saved = _createConfigMap();
      (saved['patchClashConfig'] as Map<String, dynamic>)['mixed-port'] = 17890;
      final store = _FakeMigrationStore(configMap: saved, version: 1);
      final config = await Migration(
        store: store,
        newInstallDefaults: const Config(
          themeProps: defaultThemeProps,
          patchClashConfig: PatchClashConfig(mixedPort: 17980),
        ),
      ).run();
      expect(config.patchClashConfig.mixedPort, 17890);
      expect(store.savedConfig, isNull);
    });

    test('desktop migrates the legacy default only once', () async {
      final store = _FakeMigrationStore(
        configMap: _createConfigMap(),
        version: 1,
      );
      final migration = Migration(store: store, migrateDesktopMixedPort: true);
      final config = await migration.run();
      expect(config.patchClashConfig.mixedPort, desktopDefaultMixedPort);
      expect(store.desktopMixedPortMigrated, isTrue);
      expect(store.events.sublist(2), [
        'getDesktopMixedPortMigrated',
        'saveConfig',
        'setDesktopMixedPortMigrated',
      ]);
      await store.saveConfig(
        config.copyWith(
          patchClashConfig: config.patchClashConfig.copyWith(mixedPort: 7890),
        ),
      );
      store.events.clear();
      final restarted = await migration.run();
      expect(restarted.patchClashConfig.mixedPort, 7890);
      expect(store.events, [
        'getConfigMap',
        'getVersion',
        'getDesktopMixedPortMigrated',
      ]);
    });

    test(
      'desktop prepares the old default before saving or marking it',
      () async {
        final store = _FakeMigrationStore(
          configMap: _createConfigMap(),
          version: 1,
        );
        final config = await Migration(
          store: store,
          migrateDesktopMixedPort: true,
          prepareDesktopPortMigration: (port) async {
            expect(port, 7890);
            store.events.add('prepareDesktopPortMigration');
            return true;
          },
        ).run();
        expect(config.patchClashConfig.mixedPort, desktopDefaultMixedPort);
        expect(store.events.sublist(2), [
          'getDesktopMixedPortMigrated',
          'prepareDesktopPortMigration',
          'saveConfig',
          'setDesktopMixedPortMigrated',
        ]);
      },
    );

    for (final throwsException in [false, true]) {
      test(
        'desktop failed stale repair retains the old port, throws=$throwsException',
        () async {
          final store = _FakeMigrationStore(
            configMap: _createConfigMap(),
            version: 1,
          );
          var repairReady = false;
          var calls = 0;
          final migration = Migration(
            store: store,
            migrateDesktopMixedPort: true,
            prepareDesktopPortMigration: (port) async {
              calls++;
              expect(port, 7890);
              if (!repairReady && throwsException) {
                throw StateError('Native proxy inspection unavailable');
              }
              return repairReady;
            },
          );
          expect((await migration.run()).patchClashConfig.mixedPort, 7890);
          expect(store.savedConfig, isNull);
          expect(store.desktopMixedPortMigrated, isFalse);
          repairReady = true;
          expect(
            (await migration.run()).patchClashConfig.mixedPort,
            desktopDefaultMixedPort,
          );
          expect(calls, 2);
          expect(store.desktopMixedPortMigrated, isTrue);
        },
      );
    }

    test(
      'active external listener skip allows migration without claiming its proxy',
      () async {
        final store = _FakeMigrationStore(
          configMap: _createConfigMap(),
          version: 1,
        );
        final externalProxy = {'enabled': true, 'port': 7890};
        final before = Map.of(externalProxy);
        final config = await Migration(
          store: store,
          migrateDesktopMixedPort: true,
          prepareDesktopPortMigration: (port) async {
            expect(port, externalProxy['port']);
            expect(externalProxy['enabled'], isTrue);
            return true;
          },
        ).run();
        expect(config.patchClashConfig.mixedPort, desktopDefaultMixedPort);
        expect(externalProxy, before);
        expect(store.desktopMixedPortMigrated, isTrue);
      },
    );

    test(
      'desktop preparation never runs for custom, zero, fresh or completed settings',
      () async {
        var calls = 0;
        for (final port in [0, 8080, desktopDefaultMixedPort, 7890]) {
          final map = _createConfigMap();
          (map['patchClashConfig'] as Map)['mixed-port'] = port;
          final store = _FakeMigrationStore(
            configMap: map,
            version: 1,
            desktopMixedPortMigrated: port == 7890,
          );
          expect(
            (await Migration(
              store: store,
              migrateDesktopMixedPort: true,
              prepareDesktopPortMigration: (_) async {
                calls++;
                return false;
              },
            ).run()).patchClashConfig.mixedPort,
            port,
          );
        }
        final fresh = await Migration(
          store: _FakeMigrationStore(configMap: null, version: 0),
          newInstallDefaults: const Config(
            themeProps: defaultThemeProps,
            patchClashConfig: PatchClashConfig(
              mixedPort: desktopDefaultMixedPort,
            ),
          ),
          migrateDesktopMixedPort: true,
          prepareDesktopPortMigration: (_) async {
            calls++;
            return false;
          },
        ).run();
        expect(fresh.patchClashConfig.mixedPort, desktopDefaultMixedPort);
        expect(calls, 0);
      },
    );

    for (final port in [0, 8080, 17890, desktopDefaultMixedPort]) {
      test('desktop migration preserves the configured port $port', () async {
        final map = _createConfigMap();
        (map['patchClashConfig'] as Map)['mixed-port'] = port;
        final store = _FakeMigrationStore(configMap: map, version: 1);
        final config = await Migration(
          store: store,
          migrateDesktopMixedPort: true,
        ).run();
        expect(config.patchClashConfig.mixedPort, port);
        expect(store.desktopMixedPortMigrated, isTrue);
        expect(store.restoredData, isNull);
      });
    }

    for (final missing in ['patch', 'port', 'null-port']) {
      test('desktop missing $missing uses the desktop default', () async {
        final map = _createConfigMap();
        if (missing == 'patch') {
          map.remove('patchClashConfig');
        } else if (missing == 'port') {
          (map['patchClashConfig'] as Map).remove('mixed-port');
        } else {
          (map['patchClashConfig'] as Map)['mixed-port'] = null;
        }
        final store = _FakeMigrationStore(
          configMap: map,
          version: 1,
          desktopMixedPortMigrated: true,
        );
        final config = await Migration(
          store: store,
          migrateDesktopMixedPort: true,
        ).run();
        expect(config.patchClashConfig.mixedPort, desktopDefaultMixedPort);
        expect(store.savedConfig, isNull);
      });

      for (final throwsException in [false, true]) {
        test(
          'desktop old missing $missing repairs before migration, throws=$throwsException',
          () async {
            final map = _createConfigMap();
            if (missing == 'patch') {
              map.remove('patchClashConfig');
            } else if (missing == 'port') {
              (map['patchClashConfig'] as Map).remove('mixed-port');
            } else {
              (map['patchClashConfig'] as Map)['mixed-port'] = null;
            }
            final store = _FakeMigrationStore(configMap: map, version: 1);
            var canRepair = false;
            final preparedPorts = <int>[];
            final migration = Migration(
              store: store,
              migrateDesktopMixedPort: true,
              prepareDesktopPortMigration: (port) async {
                preparedPorts.add(port);
                if (!canRepair && throwsException) {
                  throw StateError('Proxy inspection unavailable');
                }
                return canRepair;
              },
            );
            expect((await migration.run()).patchClashConfig.mixedPort, 7890);
            expect(store.configMap, map);
            expect(store.savedConfig, isNull);
            expect(store.desktopMixedPortMigrated, isFalse);
            canRepair = true;
            expect(
              (await migration.run()).patchClashConfig.mixedPort,
              desktopDefaultMixedPort,
            );
            expect(
              store.savedConfig!.patchClashConfig.mixedPort,
              desktopDefaultMixedPort,
            );
            expect(store.desktopMixedPortMigrated, isTrue);
            expect(preparedPorts, [7890, 7890]);
            expect(store.restoredData, isNull);
          },
        );
      }
    }

    test(
      'desktop first install durably saves before completing migration',
      () async {
        final store = _FakeMigrationStore(configMap: null, version: 0);
        final config = await Migration(
          store: store,
          migrateDesktopMixedPort: true,
        ).run();
        expect(config.patchClashConfig.mixedPort, desktopDefaultMixedPort);
        expect(store.savedConfig, config);
        expect(store.desktopMixedPortMigrated, isTrue);
        expect(store.restoredData, isNull);
        expect(store.events.sublist(3), [
          'getDesktopMixedPortMigrated',
          'saveConfig',
          'setDesktopMixedPortMigrated',
        ]);
      },
    );

    test(
      'desktop migration also upgrades the separate legacy default',
      () async {
        final map = _createConfigMap()..remove('patchClashConfig');
        final store = _FakeMigrationStore(
          configMap: map,
          version: 0,
          clashConfigMap: _createClashConfigMap(mixedPort: 7890),
        );
        final config = await Migration(
          store: store,
          migrateDesktopMixedPort: true,
        ).run();
        expect(config.patchClashConfig.mixedPort, desktopDefaultMixedPort);
        expect(store.savedConfig, config);
        expect(store.didClearClashConfig, isTrue);
        expect(store.desktopMixedPortMigrated, isTrue);
      },
    );

    test(
      'failed desktop port save cannot complete migration or reset data',
      () async {
        final store = _FakeMigrationStore(
          configMap: _createConfigMap(),
          version: 1,
          configSaveResult: false,
        );
        var recoveries = 0;
        await expectLater(
          Migration(
            store: store,
            migrateDesktopMixedPort: true,
            recoverDamagedConfig: () async => recoveries++,
          ).run(),
          throwsA(isA<PreferenceStorageException>()),
        );
        expect(store.desktopMixedPortMigrated, isFalse);
        expect(
          (store.configMap!['patchClashConfig'] as Map)['mixed-port'],
          7890,
        );
        expect(store.events, isNot(contains('setDesktopMixedPortMigrated')));
        expect(store.restoredData, isNull);
        expect(recoveries, 0);
      },
    );

    test(
      'failed marker save retries without discarding the saved port',
      () async {
        final store = _FakeMigrationStore(
          configMap: _createConfigMap(),
          version: 1,
          markerSaveResult: false,
        );
        final migration = Migration(
          store: store,
          migrateDesktopMixedPort: true,
        );
        await expectLater(
          migration.run(),
          throwsA(isA<PreferenceStorageException>()),
        );
        expect(
          store.savedConfig!.patchClashConfig.mixedPort,
          desktopDefaultMixedPort,
        );
        expect(store.desktopMixedPortMigrated, isFalse);
        store.markerSaveResult = true;
        expect(
          (await migration.run()).patchClashConfig.mixedPort,
          desktopDefaultMixedPort,
        );
        expect(store.desktopMixedPortMigrated, isTrue);
      },
    );

    test(
      'damaged settings recover once and load the recovered configuration',
      () async {
        final store = _FakeMigrationStore(
          configMap: {'currentProfileId': 'broken'},
          version: 1,
        );
        var recoveries = 0;
        final expected = _createConfigMap()..['currentProfileId'] = 42;
        final config = await Migration(
          store: store,
          recoverDamagedConfig: () async {
            recoveries++;
            store.configMap = expected;
          },
        ).run();
        expect(recoveries, 1);
        expect(config.currentProfileId, 42);
        expect(store.savedConfig, isNull);
        expect(store.restoredData, isNull);
      },
    );

    test(
      'unrecoverable legacy conversion can restart with fresh settings',
      () async {
        final store = _FakeMigrationStore(
          configMap: {'proxiesStyle': {}},
          version: 0,
        );
        final config = await Migration(
          store: store,
          migrateV0: (_) async =>
              throw const FormatException('invalid legacy data'),
          recoverDamagedConfig: () async {
            store.events.add('backupAndReset');
            store.configMap = null;
          },
        ).run();
        expect(config, const Config(themeProps: defaultThemeProps));
        expect(
          store.events.where((value) => value == 'backupAndReset'),
          hasLength(1),
        );
        expect(store.restoredData, isNull);
        expect(store.savedConfig, isNull);
      },
    );

    test(
      'failed recovery does not loop or overwrite the damaged data',
      () async {
        final store = _FakeMigrationStore(
          configMap: {'currentProfileId': 'broken'},
          version: 1,
        );
        var recoveries = 0;
        await expectLater(
          Migration(
            store: store,
            recoverDamagedConfig: () async {
              recoveries++;
            },
          ).run(),
          throwsA(isA<PreferenceStorageException>()),
        );
        expect(recoveries, 1);
        expect(store.savedConfig, isNull);
      },
    );

    test('a failed write never resets existing data', () async {
      final configMap = _createConfigMap()..remove('patchClashConfig');
      final store = _FakeMigrationStore(
        configMap: configMap,
        version: 0,
        clashConfigMap: _createClashConfigMap(mixedPort: 1234),
        configSaveResult: false,
      );
      var recoveries = 0;
      await expectLater(
        Migration(
          store: store,
          recoverDamagedConfig: () async {
            recoveries++;
          },
        ).run(),
        throwsA(
          isA<PreferenceStorageException>().having(
            (e) => e.operation,
            'operation',
            'write',
          ),
        ),
      );
      expect(recoveries, 0);
      expect(store.didClearClashConfig, isFalse);
      expect(store.version, 0);
    });

    test('downgrading cannot reset a newer data version', () async {
      final store = _FakeMigrationStore(
        configMap: _createConfigMap(),
        version: 2,
      );
      var recoveries = 0;
      await expectLater(
        Migration(
          store: store,
          recoverDamagedConfig: () async {
            recoveries++;
          },
        ).run(),
        throwsA(isA<StateError>()),
      );
      expect(recoveries, 0);
      expect(store.savedConfig, isNull);
    });

    test('returns current config without rewriting storage', () async {
      final configMap = _createConfigMap(
        davProps: const DAVProps(
          uri: 'https://example.com/dav',
          user: 'user',
          password: 'secret',
        ),
      );
      final store = _FakeMigrationStore(
        configMap: configMap,
        version: Migration.currentVersion,
      );

      final config = await Migration(store: store).run();

      expect(config, Config.realFromJson(configMap));
      expect(config.davProps?.password, 'secret');
      expect(store.events, ['getConfigMap', 'getVersion']);
    });

    test(
      'obfuscates a compatible DAV password without a version migration',
      () async {
        final configMap = _createConfigMap(
          davProps: const DAVProps(
            uri: 'https://example.com/dav',
            user: 'user',
          ),
        );
        final davProps = configMap['davProps']! as Map<String, Object?>;
        davProps['password'] = 'secret';
        final store = _FakeMigrationStore(configMap: configMap, version: 1);

        final config = await Migration(store: store).run();

        expect(config.davProps?.user, 'user');
        expect(config.davProps?.password, 'secret');
        expect(store.savedConfig, config);
        expect(store.version, Migration.currentVersion);
        expect(store.events, ['getConfigMap', 'getVersion', 'saveConfig']);
        final savedConfigMap =
            jsonDecode(jsonEncode(store.savedConfig)) as Map<String, Object?>;
        final savedDavProps =
            savedConfigMap['davProps']! as Map<String, Object?>;
        expect(savedDavProps['password'], startsWith('v1.'));
        expect(savedDavProps['password'], isNot(contains('secret')));
      },
    );

    test(
      'commits v0 cleanup and version only after migrated data is saved',
      () async {
        final configMap = <String, Object?>{
          'proxiesStyle': <String, Object?>{},
          'dav': <String, Object?>{
            'uri': 'https://example.com/dav',
            'user': 'user',
            'password': 'secret',
          },
        };
        final store = _FakeMigrationStore(
          configMap: configMap,
          version: 0,
          clashConfigMap: <String, Object?>{'mixed-port': 7890},
        );
        final migration = Migration(
          store: store,
          migrateV0: (configMap) async {
            store.events.add('migrateV0');
            expect(configMap['patchClashConfig'], store.clashConfigMap);
            return MigrationData(
              configMap: _createConfigMap(
                davProps: const DAVProps(
                  uri: 'https://example.com/dav',
                  user: 'user',
                  password: 'secret',
                ),
              ),
            );
          },
        );

        await migration.run();

        expect(store.events, [
          'getConfigMap',
          'getVersion',
          'getClashConfigMap',
          'migrateV0',
          'restore',
          'saveConfig',
          'clearClashConfig',
          'setVersion',
        ]);
        expect(store.savedConfig?.davProps?.password, 'secret');
        expect(store.didClearClashConfig, isTrue);
        expect(store.version, Migration.currentVersion);
      },
    );

    test(
      'preserves legacy clash config when current-shaped data has version zero',
      () async {
        final configMap = _createConfigMap()..remove('patchClashConfig');
        final clashConfigMap = _createClashConfigMap(mixedPort: 1234);
        final store = _FakeMigrationStore(
          configMap: configMap,
          version: 0,
          clashConfigMap: clashConfigMap,
        );

        final config = await Migration(store: store).run();

        expect(config.patchClashConfig.mixedPort, 1234);
        expect(store.savedConfig?.patchClashConfig.mixedPort, 1234);
        expect(store.didClearClashConfig, isTrue);
        expect(store.events, [
          'getConfigMap',
          'getVersion',
          'getClashConfigMap',
          'saveConfig',
          'clearClashConfig',
          'setVersion',
        ]);
      },
    );

    test('does not clear legacy clash config when saving fails', () async {
      final configMap = _createConfigMap()..remove('patchClashConfig');
      final store = _FakeMigrationStore(
        configMap: configMap,
        version: 0,
        clashConfigMap: _createClashConfigMap(mixedPort: 1234),
        configSaveResult: false,
      );

      await expectLater(
        Migration(store: store).run(),
        throwsA(isA<PreferenceStorageException>()),
      );

      expect(store.didClearClashConfig, isFalse);
      expect(store.version, 0);
      expect(store.events, [
        'getConfigMap',
        'getVersion',
        'getClashConfigMap',
        'saveConfig',
      ]);
    });

    test('keeps the current version when password obfuscation fails', () async {
      final configMap = _createConfigMap(
        davProps: const DAVProps(uri: 'https://example.com/dav', user: 'user'),
      );
      final davProps = configMap['davProps']! as Map<String, Object?>;
      davProps['password'] = 'secret';
      final store = _FakeMigrationStore(
        configMap: configMap,
        version: Migration.currentVersion,
        configSaveResult: false,
      );

      await expectLater(
        Migration(store: store).run(),
        throwsA(isA<PreferenceStorageException>()),
      );

      expect(store.events, ['getConfigMap', 'getVersion', 'saveConfig']);
      expect(store.version, Migration.currentVersion);
    });
  });
}

Map<String, Object?> _createConfigMap({DAVProps? davProps}) {
  return jsonDecode(
        jsonEncode(Config(themeProps: defaultThemeProps, davProps: davProps)),
      )
      as Map<String, Object?>;
}

Map<String, Object?> _createClashConfigMap({required int mixedPort}) {
  return jsonDecode(jsonEncode(PatchClashConfig(mixedPort: mixedPort)))
      as Map<String, Object?>;
}

class _FakeMigrationStore implements MigrationStore {
  Map<String, Object?>? configMap;
  Map<String, Object?>? clashConfigMap;
  final bool configSaveResult;
  final List<String> events = [];

  int version;
  Config? savedConfig;
  MigrationData? restoredData;
  bool didClearClashConfig = false;
  bool desktopMixedPortMigrated;
  bool markerSaveResult;

  _FakeMigrationStore({
    required this.configMap,
    required this.version,
    this.clashConfigMap,
    this.configSaveResult = true,
    this.desktopMixedPortMigrated = false,
    this.markerSaveResult = true,
  });

  @override
  Future<void> clearClashConfig() async {
    events.add('clearClashConfig');
    didClearClashConfig = true;
  }

  @override
  Future<Map<String, Object?>?> getClashConfigMap() async {
    events.add('getClashConfigMap');
    return clashConfigMap;
  }

  @override
  Future<Map<String, Object?>?> getConfigMap() async {
    events.add('getConfigMap');
    return configMap;
  }

  @override
  Future<int> getVersion() async {
    events.add('getVersion');
    return version;
  }

  @override
  Future<void> restore(MigrationData data) async {
    events.add('restore');
    restoredData = data;
  }

  @override
  Future<bool> saveConfig(Config config) async {
    events.add('saveConfig');
    savedConfig = config;
    if (configSaveResult) {
      configMap = jsonDecode(jsonEncode(config)) as Map<String, Object?>;
    }
    return configSaveResult;
  }

  @override
  Future<void> setVersion(int version) async {
    events.add('setVersion');
    this.version = version;
  }

  @override
  Future<bool> getDesktopMixedPortMigrated() async {
    events.add('getDesktopMixedPortMigrated');
    return desktopMixedPortMigrated;
  }

  @override
  Future<void> setDesktopMixedPortMigrated() async {
    events.add('setDesktopMixedPortMigrated');
    if (!markerSaveResult) {
      throw PreferenceStorageException(
        operation: 'write',
        cause: StateError('Preference storage rejected the write'),
      );
    }
    desktopMixedPortMigrated = true;
  }
}

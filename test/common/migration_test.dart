import 'dart:convert';

import 'package:fl_clash/common/migration.dart';
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

  _FakeMigrationStore({
    required this.configMap,
    required this.version,
    this.clashConfigMap,
    this.configSaveResult = true,
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
    return configSaveResult;
  }

  @override
  Future<void> setVersion(int version) async {
    events.add('setVersion');
    this.version = version;
  }
}

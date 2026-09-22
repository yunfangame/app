import 'dart:convert';
import 'dart:io';

import 'package:fl_clash/common/migration.dart';
import 'package:fl_clash/common/preferences.dart';
import 'package:fl_clash/common/windows_preferences.dart';
import 'package:fl_clash/models/models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late File file;
  late Preferences preferences;
  late _UpgradeStore store;
  late SharedPreferencesStorePlatform previous;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('fengwo-upgrade-test-');
    file = File('${directory.path}/shared_preferences.json');
    previous = SharedPreferencesStorePlatform.instance;
    SharedPreferences.resetStatic();
    installWindowsPreferencesStore(
      isWindows: true,
      store: WindowsPreferencesStore(directoryLoader: () async => directory),
    );
    preferences = Preferences.forTesting(loader: SharedPreferences.getInstance);
    store = _UpgradeStore(preferences);
  });

  tearDown(() async {
    SharedPreferences.resetStatic();
    SharedPreferencesStorePlatform.instance = previous;
    await directory.delete(recursive: true);
  });

  Future<Config> start() => Migration(
    store: store,
    recoverDamagedConfig: preferences.recoverForStartup,
  ).run();

  for (final hasVersion in [true, false]) {
    test(
      'old release settings survive overwrite upgrade, version=$hasVersion',
      () async {
        final original = _savedPreferences(includeVersion: hasVersion);
        await file.writeAsString(original);
        final rules = File('${directory.path}/database.sqlite');
        await rules.writeAsString('existing-rule-database');

        final config = await start();
        final storage = await SharedPreferences.getInstance();

        expect(config.currentProfileId, 71);
        expect(config.appSettingProps.campusOperator, 'telecom');
        expect(config.appSettingProps.campusNetworkEnabled, isTrue);
        expect(config.excludeSSIDs, ['Campus WiFi']);
        expect(storage.getBool('xboard.auto_login'), isTrue);
        expect(storage.getString('xboard.email'), 'upgrade-test@example.test');
        expect(await file.readAsString(), original);
        expect(await rules.readAsString(), 'existing-rule-database');
        expect(store.restores, 0);
      },
    );
  }

  test(
    'truncated preferences recover the valid backup and keep the account',
    () async {
      const damaged = '{"flutter.config":';
      await file.writeAsString(damaged);
      await File('${file.path}.bak').writeAsString(_savedPreferences());
      final config = await start();
      expect(config.currentProfileId, 71);
      expect(
        (await SharedPreferences.getInstance()).getBool('xboard.auto_login'),
        isTrue,
      );
      final archives = await directory
          .list()
          .where((f) => f.path.contains('.recovery-'))
          .toList();
      expect(archives, hasLength(1));
      expect(await File(archives.single.path).readAsString(), damaged);
      expect(store.restores, 0);
    },
  );

  test(
    'valid outer JSON with a damaged config recovers a usable backup',
    () async {
      final damaged = jsonEncode({
        'flutter.config': jsonEncode({'currentProfileId': 'broken'}),
        'flutter.version': 1,
      });
      await file.writeAsString(damaged);
      await File('${file.path}.bak').writeAsString(_savedPreferences());
      final config = await start();
      expect(config.currentProfileId, 71);
      expect(
        (await SharedPreferences.getInstance()).getString('xboard.email'),
        'upgrade-test@example.test',
      );
      expect(await file.readAsString(), _savedPreferences());
      expect(store.restores, 0);
    },
  );

  test(
    'damaged legacy clash data cannot be restored as a valid backup',
    () async {
      final values =
          jsonDecode(_savedPreferences(includeVersion: false))
              as Map<String, dynamic>;
      values['flutter.clash_config'] = 'broken';
      await file.writeAsString(jsonEncode(values));
      final config = await start();
      expect(config.currentProfileId, isNull);
      expect(jsonDecode(await file.readAsString()), isEmpty);
      expect(store.restores, 0);
    },
  );

  test(
    'backup with missing optional config retains unrelated account preferences',
    () async {
      await file.writeAsString(jsonEncode({'flutter.config': 'broken'}));
      await File('${file.path}.bak').writeAsString(
        jsonEncode({
          'flutter.version': 1,
          'flutter.xboard.email': 'preserved@example.test',
        }),
      );
      final config = await start();
      expect(config.currentProfileId, isNull);
      expect(
        (await SharedPreferences.getInstance()).getString('xboard.email'),
        'preserved@example.test',
      );
      expect(store.restores, 0);
    },
  );

  for (final content in ['truncated', 'inner-schema']) {
    test('unrecoverable $content is archived before fresh startup', () async {
      final damaged = content == 'truncated'
          ? '{"flutter.config":'
          : jsonEncode({
              'flutter.config': '{"currentProfileId":"broken"}',
              'flutter.version': 1,
            });
      await file.writeAsString(damaged);
      final config = await start();
      expect(config.currentProfileId, isNull);
      expect(
        (await SharedPreferences.getInstance()).getString('xboard.email'),
        isNull,
      );
      expect(jsonDecode(await file.readAsString()), isEmpty);
      final archives = await directory
          .list()
          .where((f) => f.path.contains('.recovery-'))
          .toList();
      expect(archives, isNotEmpty);
      expect(await File(archives.first.path).readAsString(), damaged);
      expect(store.restores, 0);
      expect(await start(), config);
    });
  }
}

String _savedPreferences({bool includeVersion = true}) {
  return jsonEncode({
    if (includeVersion) 'flutter.version': 1,
    'flutter.config': jsonEncode(
      const Config(
        themeProps: defaultThemeProps,
        currentProfileId: 71,
        appSettingProps: AppSettingProps(
          campusOperator: 'telecom',
          campusNetworkEnabled: true,
        ),
        excludeSSIDs: ['Campus WiFi'],
      ),
    ),
    'flutter.xboard.email': 'upgrade-test@example.test',
    'flutter.xboard.auto_login': true,
  });
}

class _UpgradeStore implements MigrationStore {
  _UpgradeStore(this.preferences);

  final Preferences preferences;
  int restores = 0;

  @override
  Future<Map<String, Object?>?> getConfigMap() => preferences.getConfigMap();

  @override
  Future<int> getVersion() => preferences.getVersion();

  @override
  Future<Map<String, Object?>?> getClashConfigMap() =>
      preferences.getClashConfigMap();

  @override
  Future<void> clearClashConfig() => preferences.clearClashConfig();

  @override
  Future<void> restore(MigrationData data) async {
    restores++;
  }

  @override
  Future<bool> saveConfig(Config config) => preferences.saveConfig(config);

  @override
  Future<void> setVersion(int version) => preferences.setVersion(version);
}

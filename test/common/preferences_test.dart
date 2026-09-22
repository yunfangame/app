import 'dart:io';

import 'package:fl_clash/common/constant.dart';
import 'package:fl_clash/common/preferences.dart';
import 'package:fl_clash/common/preferences_storage_error.dart';
import 'package:fl_clash/models/models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'initialization errors cannot become version zero or empty data',
    () async {
      const cause = FileSystemException(
        'denied',
        'settings.json',
        OSError('', 5),
      );
      final preferences = Preferences.forTesting(
        loader: () async => throw cause,
      );
      for (final operation in [
        preferences.getVersion,
        preferences.getConfigMap,
      ]) {
        await expectLater(
          operation(),
          throwsA(
            isA<PreferenceStorageException>()
                .having((e) => e.cause, 'cause', same(cause))
                .having((e) => e.code, 'code', 'PREF-ACCESS'),
          ),
        );
      }
    },
  );

  for (final value in ['{"private-token":', '[]', 'null', '', 42]) {
    test(
      'invalid config is surfaced without replacing it: ${value.runtimeType}',
      () async {
        SharedPreferences.setMockInitialValues({configKey: value});
        final storage = await SharedPreferences.getInstance();
        final preferences = Preferences.forTesting(loader: () async => storage);
        await expectLater(
          preferences.getConfigMap(),
          throwsA(
            isA<PreferenceStorageException>()
                .having((e) => e.code, 'code', 'PREF-FORMAT')
                .having(
                  (e) => e.toString(),
                  'safe detail',
                  isNot(contains('private-token')),
                ),
          ),
        );
        expect(storage.get(configKey), value);
      },
    );
  }

  test('only a genuinely missing configuration returns null', () async {
    final storage = await SharedPreferences.getInstance();
    final preferences = Preferences.forTesting(loader: () async => storage);
    expect(await preferences.getConfigMap(), isNull);
    expect(await preferences.getVersion(), 0);
  });

  test('invalid version does not trigger a version zero migration', () async {
    SharedPreferences.setMockInitialValues({'version': 'bad'});
    final preferences = Preferences.forTesting(
      loader: SharedPreferences.getInstance,
    );
    await expectLater(
      preferences.getVersion(),
      throwsA(isA<PreferenceStorageException>()),
    );
  });

  test(
    'failed writes report failure and leave durable data unchanged',
    () async {
      final original = SharedPreferencesStorePlatform.instance;
      final store = _RejectWritesStore({
        'flutter.config': '{"currentProfileId":7}',
      });
      SharedPreferences.resetStatic();
      SharedPreferencesStorePlatform.instance = store;
      addTearDown(() {
        SharedPreferences.resetStatic();
        SharedPreferencesStorePlatform.instance = original;
      });
      final storage = await SharedPreferences.getInstance();
      final preferences = Preferences.forTesting(loader: () async => storage);
      await expectLater(
        preferences.saveConfig(
          const Config(themeProps: defaultThemeProps, currentProfileId: 9),
        ),
        throwsA(
          isA<PreferenceStorageException>().having(
            (e) => e.operation,
            'operation',
            'write',
          ),
        ),
      );
      expect(store.values['flutter.config'], '{"currentProfileId":7}');
      await expectLater(
        preferences.setVersion(1),
        throwsA(isA<PreferenceStorageException>()),
      );
      expect(store.values['flutter.version'], isNull);
    },
  );

  test(
    'diagnostics omit raw exceptions and preserve actionable Windows codes',
    () {
      for (final entry in {
        5: 'PREF-ACCESS',
        32: 'PREF-LOCKED',
        112: 'PREF-DISK',
      }.entries) {
        final error = PreferenceStorageException(
          operation: 'write',
          cause: FileSystemException(
            'secret-token@example.test',
            '',
            OSError('', entry.key),
          ),
        );
        expect(error.code, entry.value);
        expect(error.toString(), contains(entry.key.toString()));
        expect(error.toString(), isNot(contains('secret-token')));
      }
    },
  );
}

class _RejectWritesStore extends SharedPreferencesStorePlatform {
  _RejectWritesStore(this.values);

  final Map<String, Object> values;

  @override
  Future<Map<String, Object>> getAll() async => Map.of(values);

  @override
  Future<bool> setValue(String valueType, String key, Object value) async =>
      false;

  @override
  Future<bool> remove(String key) async => false;

  @override
  Future<bool> clear() async => false;
}

import 'dart:convert';
import 'dart:io';

import 'package:fl_clash/common/local_secret_store.dart';
import 'package:fl_clash/common/macos_identity.dart';
import 'package:fl_clash/common/subscription_v2.dart';
import 'package:fl_clash/common/xboard_session_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final platform in [
    TargetPlatform.macOS,
    TargetPlatform.android,
    TargetPlatform.linux,
  ]) {
    test(
      'default stores send native ${platform.name} storage options',
      () async {
        const channel = MethodChannel(
          'plugins.it_nomads.com/flutter_secure_storage',
        );
        final calls = <MethodCall>[];
        debugDefaultTargetPlatformOverride = platform;
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, (call) async {
              calls.add(call);
              return null;
            });
        addTearDown(() {
          debugDefaultTargetPlatformOverride = null;
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
              .setMockMethodCallHandler(channel, null);
        });
        SharedPreferences.setMockInitialValues({
          'xboard.remember_me': true,
          'xboard.email': 'fixture@example.invalid',
          'xboard.endpoint': 'https://fixture.invalid',
          'xboard.credentials_enabled': true,
          'xboard.session_enabled': true,
        });
        await const FlutterSecureStorage().read(key: 'fixture.baseline');
        final baselineOptions =
            (calls.single.arguments as Map)['options'] as Map;
        calls.clear();

        await FlutterSecureSecretStringStore().read('fixture.local');
        await SecureSubscriptionV2ValueStore().read('fixture.subscription');
        await XboardSessionStorage().load();

        expect(calls.every((call) => call.method == 'read'), isTrue);
        expect(
          calls.map((call) => (call.arguments as Map)['key']),
          containsAll([
            'fixture.local',
            'fixture.subscription',
            'xboard.credentials_v2',
            'xboard.token',
            'xboard.auth_data',
          ]),
        );
        final expectedOptions = platform == TargetPlatform.macOS
            ? identitySecureStorage.mOptions.toMap()
            : baselineOptions;
        for (final call in calls) {
          expect((call.arguments as Map)['options'], expectedOptions);
        }
        if (platform == TargetPlatform.macOS) {
          expect(expectedOptions['accountName'], macIdentityKeychainService);
          expect(
            expectedOptions['accountName'],
            isNot(baselineOptions['accountName']),
          );
        }
      },
    );
  }

  test('native preparation precedes own lock and secret migration', () async {
    final steps = <String>[];
    final result = await prepareMacStartupIdentity(
      prepareIdentity: () async {
        steps.add('native');
        return {'legacyImported': true, 'status': 'imported'};
      },
      acquireLock: () async => steps.add('lock'),
      migrateSecrets: () async {
        steps.add('secrets');
        return true;
      },
    );
    expect(steps, ['native', 'lock', 'secrets']);
    expect(result.legacyImported, isTrue);
    expect(result.requiresLogin, isFalse);
  });

  test('fresh install never reads legacy keychain', () async {
    var reads = 0;
    final result = await prepareMacStartupIdentity(
      prepareIdentity: () async => {
        'legacyImported': false,
        'status': 'no_compatible_legacy',
      },
      migrateSecrets: () async {
        reads++;
        return true;
      },
    );
    expect(result.legacyImported, isFalse);
    expect(reads, 0);
  });

  test('native migration exception permits independent startup', () async {
    var locks = 0;
    final result = await prepareMacStartupIdentity(
      prepareIdentity: () async => throw PlatformException(
        code: 'failure',
        message: 'private-preference-value',
      ),
      acquireLock: () async => locks++,
    );
    expect(result.status, 'migration_failed');
    expect(locks, 1);
  });

  test('malformed native reply permits independent startup', () async {
    final result = await prepareMacStartupIdentity(
      prepareIdentity: () async => {'legacyImported': 'bad'},
    );
    expect(result.status, 'migration_failed');
    expect(result.legacyImported, isFalse);
  });

  test('keychain failure requests login without blocking startup', () async {
    final result = await prepareMacStartupIdentity(
      prepareIdentity: () async => {
        'legacyImported': true,
        'status': 'imported',
      },
      migrateSecrets: () async => throw StateError('private-keychain-value'),
    );
    expect(result.legacyImported, isTrue);
    expect(result.requiresLogin, isTrue);
  });

  test('own lock failure is preserved', () async {
    var secrets = 0;
    await expectLater(
      prepareMacStartupIdentity(
        prepareIdentity: () async => {
          'legacyImported': true,
          'status': 'imported',
        },
        acquireLock: () async => throw StateError('already running'),
        migrateSecrets: () async {
          secrets++;
          return true;
        },
      ),
      throwsStateError,
    );
    expect(secrets, 0);
  });

  test('only remembered active credentials are required', () {
    expect(macRequiredSecretGroups({'xboard.remember_me': false}), isEmpty);
    expect(
      macRequiredSecretGroups({
        'xboard.remember_me': true,
        'xboard.forget_requested': true,
      }),
      isEmpty,
    );
    expect(
      macRequiredSecretGroups({
        'xboard.remember_me': true,
        'xboard.endpoint': 'https://fixture.invalid',
        'xboard.secure_subscription': true,
      }),
      [
        {'xboard.credentials_v2', 'xboard.password'},
        {'xboard.token'},
        {'xboard.auth_data'},
        {'subscription_v2.device_seed'},
      ],
    );
  });

  group('credential migration', () {
    late Directory root;
    late _MemoryStore store;
    late Map<String, String> legacy;
    var reads = 0;
    final credentialKey =
        'subscription_v2.credential.${List.filled(64, 'a').join()}';

    setUp(() async {
      root = await Directory.systemTemp.createTemp('fengwo-identity-unit-');
      store = _MemoryStore();
      reads = 0;
      legacy = {
        'xboard.token': 'fixture-token',
        'xboard.auth_data': 'fixture-auth',
        'xboard.password': 'fixture-password',
        'subscription_v2.device_seed': 'fixture-device',
        credentialKey: 'fixture-credential',
        'foreign.secret': 'not-imported',
      };
    });

    tearDown(() async => root.delete(recursive: true));

    MacLegacySecretMigration migration({
      Future<Map<String, String>> Function()? readLegacy,
      Map<String, String> copiedSecrets = const {},
      List<Set<String>> requiredKeyGroups = const [],
    }) => MacLegacySecretMigration(
      root: root,
      target: store,
      copiedSecrets: copiedSecrets,
      requiredKeyGroups: requiredKeyGroups,
      readLegacy:
          readLegacy ??
          () async {
            reads++;
            return legacy;
          },
    );

    test('allowlisted credentials copied without deleting originals', () async {
      expect(await migration().run(), isTrue);
      expect(reads, 1);
      expect(store.values['xboard.token'], 'fixture-token');
      expect(store.values['subscription_v2.device_seed'], 'fixture-device');
      expect(store.values[credentialKey], 'fixture-credential');
      expect(store.values.containsKey('foreign.secret'), isFalse);
      expect(legacy['xboard.token'], 'fixture-token');
      expect(store.deletes, 0);
    });

    test('completed marker never revives deleted session', () async {
      expect(await migration().run(), isTrue);
      store.values.clear();
      expect(await migration().run(), isTrue);
      expect(reads, 1);
      expect(store.values, isEmpty);
    });

    test('complete copied encrypted keys avoid legacy keychain', () async {
      expect(
        await migration(
          copiedSecrets: const {'xboard.token': 'copied'},
          requiredKeyGroups: const [
            {'xboard.token'},
          ],
        ).run(),
        isTrue,
      );
      expect(reads, 0);
      expect(store.values['xboard.token'], 'copied');
    });

    test('missing copied keys fall back to legacy keychain', () async {
      expect(
        await migration(
          copiedSecrets: const {'xboard.token': 'copied'},
          requiredKeyGroups: const [
            {'xboard.token'},
            {'xboard.auth_data'},
          ],
        ).run(),
        isTrue,
      );
      expect(reads, 1);
      expect(store.values['xboard.token'], 'copied');
      expect(store.values['xboard.auth_data'], 'fixture-auth');
    });

    test('new own credentials are never overwritten or merged', () async {
      store.values['xboard.token'] = 'new-account';
      expect(
        await migration(
          requiredKeyGroups: const [
            {'xboard.token'},
          ],
        ).run(),
        isTrue,
      );
      expect(store.values, {'xboard.token': 'new-account'});
      expect(reads, 0);
    });

    test('partial new credentials are never mixed with old account', () async {
      store.values['xboard.token'] = 'new-token';
      expect(
        await migration(
          requiredKeyGroups: const [
            {'xboard.token'},
            {'xboard.auth_data'},
          ],
        ).run(),
        isFalse,
      );
      expect(store.values, {'xboard.token': 'new-token'});
      expect(reads, 0);
    });

    test('missing required credentials request login once', () async {
      legacy.clear();
      expect(
        await migration(
          requiredKeyGroups: const [
            {'xboard.token'},
          ],
        ).run(),
        isFalse,
      );
      expect(
        await migration(
          requiredKeyGroups: const [
            {'xboard.token'},
          ],
        ).run(),
        isFalse,
      );
      expect(reads, 1);
      final record = jsonDecode(
        await File(
          '${root.path}/${MacLegacySecretMigration.markerName}',
        ).readAsString(),
      );
      expect(record['requiresLogin'], isTrue);
    });

    test(
      'keychain access failure is bounded and does not read again',
      () async {
        final missing = migration(
          requiredKeyGroups: const [
            {'xboard.token'},
          ],
          readLegacy: () async {
            reads++;
            throw StateError('denied');
          },
        );
        expect(await missing.run(), isFalse);
        expect(await missing.run(), isFalse);
        expect(reads, 1);
        expect(store.values, isEmpty);
      },
    );

    test(
      'manual login after missing legacy credentials remains enabled',
      () async {
        legacy.clear();
        final operation = migration(
          requiredKeyGroups: const [
            {'xboard.token'},
          ],
        );
        expect(await operation.run(), isFalse);
        store.values['xboard.token'] = 'new-login';
        expect(await operation.run(), isTrue);
        expect(reads, 1);
        expect(store.values['xboard.token'], 'new-login');
      },
    );

    test('write failure retains pending state for retry', () async {
      store.failOnce = 'xboard.auth_data';
      final operation = migration(
        requiredKeyGroups: const [
          {'xboard.token'},
          {'xboard.auth_data'},
        ],
      );
      expect(await operation.run(), isFalse);
      expect(await operation.run(), isTrue);
      expect(reads, 2);
      expect(store.values['xboard.token'], 'fixture-token');
      expect(store.values['xboard.auth_data'], 'fixture-auth');
      expect(store.deletes, 0);
    });

    test('invalid credential key is ignored', () async {
      legacy['subscription_v2.credential.wrong'] = 'not-imported';
      expect(await migration().run(), isTrue);
      expect(
        store.values.containsKey('subscription_v2.credential.wrong'),
        isFalse,
      );
    });

    test('malformed marker does not read or overwrite secrets', () async {
      await File(
        '${root.path}/${MacLegacySecretMigration.markerName}',
      ).writeAsString('bad-json');
      expect(await migration().run(), isFalse);
      expect(reads, 0);
      expect(store.values, isEmpty);
    });
  });
}

class _MemoryStore implements SecretStringStore {
  final values = <String, String>{};
  String? failOnce;
  var deletes = 0;

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async {
    if (key == failOnce) {
      failOnce = null;
      throw StateError('injected write failure');
    }
    values[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    deletes++;
    values.remove(key);
  }
}

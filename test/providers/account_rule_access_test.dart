import 'dart:async';
import 'dart:io';

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/common/xboard_rule_account.dart';
import 'package:fl_clash/database/database.dart'
    show ProfilesCompanionExt, database;
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/database.dart';
import 'package:fl_clash/state.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:riverpod/riverpod.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late PathProviderPlatform originalPathProvider;
  var profileId = 100;

  setUpAll(() async {
    originalPathProvider = PathProviderPlatform.instance;
    directory = await Directory.systemTemp.createTemp('account_rule_access_');
    PathProviderPlatform.instance = _FakePathProvider(directory.path);
  });

  setUp(() async {
    profileId++;
    globalState.clearXboardSession();
    await database.delete(database.profileRuleLinks).go();
    await database.delete(database.rules).go();
    await database.delete(database.profileRuleAccounts).go();
    await database.delete(database.profiles).go();
  });

  tearDown(globalState.clearXboardSession);

  tearDownAll(() async {
    await database.close();
    await commonPrint.flushDiagnosticEvents();
    PathProviderPlatform.instance = originalPathProvider;
    await directory.delete(recursive: true);
  });

  for (final accountScoped in [true, false]) {
    test(
      'saves, sorts, toggles and deletes allowed rules, account=$accountScoped',
      () async {
        final fixture = await _Fixture.create(
          profileId,
          accountScoped: accountScoped,
        );
        addTearDown(fixture.container.dispose);
        if (accountScoped) {
          globalState.activateXboardSession(_session('account-a'));
        }
        final rules = fixture.rules;
        final disabled = fixture.disabled;

        await rules.putAndWait(fixture.third);
        expect(
          (await database.rulesDao.queryProfileAddedRules(profileId).get()).map(
            (rule) => rule.id,
          ),
          [fixture.first.id, fixture.second.id, fixture.third.id],
        );
        await rules.orderAndWait(2, 0);
        expect(
          (await database.rulesDao.queryProfileAddedRules(profileId).get()).map(
            (rule) => rule.id,
          ),
          [fixture.third.id, fixture.first.id, fixture.second.id],
        );
        await disabled.putAndWait(fixture.second.id);
        await disabled.delAndWait(fixture.first.id);
        expect(
          (await database.rulesDao.queryAddedRules(profileId).get()).map(
            (rule) => rule.id,
          ),
          [fixture.third.id, fixture.first.id],
        );
        await rules.delAllAndWait([fixture.third.id]);
        await rules.putAndWait(fixture.first.copyWith(content: 'Updated.exe'));
        final active = await database.rulesDao.queryAddedRules(profileId).get();
        expect(active, [fixture.first.copyWith(content: 'Updated.exe')]);
        expect(
          await database.rulesDao.getProfileAccountKey(profileId),
          accountScoped
              ? xboardRuleAccountKeyForEmail('account-a@example.com')
              : null,
        );
      },
    );
  }

  for (final identity in ['account-b', 'logged-out']) {
    for (final operation in [
      'add',
      'edit',
      'delete',
      'sort',
      'disable',
      'enable',
    ]) {
      test('$identity cannot $operation saved account A rules', () async {
        final fixture = await _Fixture.create(profileId);
        addTearDown(fixture.container.dispose);
        globalState.activateXboardSession(_session('account-a'));
        final before = await _snapshot();
        final originalValue = fixture.rules.value;
        final originalDisabled = fixture.disabled.value;
        if (identity == 'logged-out') {
          globalState.clearXboardSession();
        } else {
          globalState.activateXboardSession(_session(identity));
        }

        final changing = switch (operation) {
          'add' => fixture.rules.putAndWait(fixture.third),
          'edit' => fixture.rules.putAndWait(
            fixture.first.copyWith(content: 'Changed.exe'),
          ),
          'delete' => fixture.rules.delAllAndWait([fixture.first.id]),
          'sort' => fixture.rules.orderAndWait(0, 1),
          'disable' => fixture.disabled.putAndWait(fixture.second.id),
          'enable' => fixture.disabled.delAndWait(fixture.first.id),
          _ => throw StateError(operation),
        };
        await expectLater(changing, throwsA(_accountMismatch));

        expect(await _snapshot(), before);
        expect(fixture.rules.value, originalValue);
        expect(fixture.disabled.value, originalDisabled);
      });
    }
  }

  test(
    'non-awaited put rolls back when a different account owns the session',
    () async {
      final fixture = await _Fixture.create(profileId);
      addTearDown(fixture.container.dispose);
      final before = await _snapshot();
      final originalValue = fixture.rules.value;
      globalState.activateXboardSession(_session('account-b'));
      final failure = Completer<Object>();

      runZonedGuarded<void>(
        () => fixture.rules.put(fixture.third),
        (error, _) => failure.complete(error),
      );

      expect(await failure.future, _accountMismatch);
      expect(await _snapshot(), before);
      expect(fixture.rules.value, originalValue);
    },
  );

  test(
    'reauthentication while checking ownership rejects a stale save',
    () async {
      final fixture = await _Fixture.create(profileId);
      addTearDown(fixture.container.dispose);
      globalState.activateXboardSession(_session('account-a'));
      final before = await _snapshot();

      final changing = fixture.rules.putAndWait(fixture.third);
      globalState.clearXboardSession();
      globalState.activateXboardSession(_session('account-a'));
      await expectLater(changing, throwsA(_accountMismatch));

      expect(await _snapshot(), before);
    },
  );
}

final _accountMismatch = isA<StateError>().having(
  (error) => error.message,
  'message',
  'profile_rule_account_mismatch',
);

Future<Map<String, Object>> _snapshot() async => {
  'rules': await database.select(database.rules).get(),
  'links': await database.select(database.profileRuleLinks).get(),
  'accounts': await database.select(database.profileRuleAccounts).get(),
};

class _Fixture {
  const _Fixture(
    this.container,
    this.profileId,
    this.first,
    this.second,
    this.third,
  );

  final ProviderContainer container;
  final int profileId;
  final Rule first;
  final Rule second;
  final Rule third;

  ProfileAddedRules get rules =>
      container.read(profileAddedRulesProvider(profileId).notifier);

  ProfileDisabledRuleIds get disabled =>
      container.read(profileDisabledRuleIdsProvider(profileId).notifier);

  static Future<_Fixture> create(
    int profileId, {
    bool accountScoped = true,
  }) async {
    await database.profilesDao.putAll([
      Profile(id: profileId, autoUpdateDuration: Duration.zero).toCompanion(),
    ]);
    if (accountScoped) {
      await database.rulesDao.bindProfileAccount(
        profileId,
        xboardRuleAccountKeyForEmail('account-a@example.com')!,
      );
    }
    Rule rule(int offset, String content, String order) => Rule(
      id: profileId * 10 + offset,
      ruleAction: RuleAction.PROCESS_NAME,
      content: content,
      ruleTarget: 'DIRECT',
      order: order,
    );
    final first = rule(1, 'WeChat.exe', 'a0');
    final second = rule(2, 'Weixin.exe', 'a1');
    final third = rule(3, 'Another.exe', 'a2');
    await database.rulesDao.putProfileAddedRule(profileId, first);
    await database.rulesDao.putProfileAddedRule(profileId, second);
    await database.rulesDao.putDisabledLink(profileId, first.id);
    final container = ProviderContainer();
    container.listen(profileAddedRulesProvider(profileId), (_, _) {});
    container.listen(profileDisabledRuleIdsProvider(profileId), (_, _) {});
    await container.read(profileAddedRulesProvider(profileId).future);
    await container.read(profileDisabledRuleIdsProvider(profileId).future);
    return _Fixture(container, profileId, first, second, third);
  }
}

XboardLoginResult _session(String account) {
  final endpoint = Uri.parse('https://api.example.com');
  return XboardLoginResult(
    endpoint: endpoint,
    token: '$account-token',
    authData: 'Bearer $account',
    isAdmin: false,
    subscription: XboardSubscriptionData(
      endpoint: endpoint,
      subscribeUrl: null,
      uploadBytes: 0,
      downloadBytes: 0,
      transferEnableBytes: 1024,
      email: '$account@example.com',
      rawData: const {},
    ),
  );
}

class _FakePathProvider extends PathProviderPlatform {
  _FakePathProvider(this.root);

  final String root;

  @override
  Future<String?> getTemporaryPath() async => root;

  @override
  Future<String?> getApplicationSupportPath() async => root;

  @override
  Future<String?> getApplicationCachePath() async => root;
}

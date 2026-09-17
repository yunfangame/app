import 'package:drift/native.dart';
import 'package:fl_clash/common/xboard_account_rule_store.dart';
import 'package:fl_clash/common/xboard_account_rules.dart';
import 'package:fl_clash/common/xboard_auth.dart';
import 'package:fl_clash/database/database.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test(
    'uses account identity instead of API or subscription address',
    () async {
      final store = XboardAccountRuleStore();
      final firstSession = _session(
        email: 'Member@Example.com',
        uuid: 'account-uuid',
        endpoint: 'https://api-one.example.com',
        subscribeUrl: 'https://subscribe-one.example.com/client/token-one',
        token: 'token-one',
      );
      const snapshot = XboardAccountRuleSnapshot(
        rules: [
          Rule(
            id: 11,
            ruleAction: RuleAction.DOMAIN,
            content: 'example.com',
            ruleTarget: 'DIRECT',
            order: 'a',
          ),
          Rule(
            id: 12,
            ruleAction: RuleAction.IP_CIDR,
            content: '192.0.2.0/24',
            ruleTarget: 'REJECT',
            order: 'b',
          ),
        ],
        disabledRuleIds: {12},
      );

      await store.save(firstSession, snapshot);

      final changedInfrastructure = _session(
        email: 'member@example.com',
        uuid: 'account-uuid',
        endpoint: 'https://api-two.example.com',
        subscribeUrl: 'https://subscribe-two.example.com/client/token-two',
        token: 'rotated-token',
      );
      final restored = await store.load(changedInfrastructure);
      expect(restored?.rules, snapshot.rules);
      expect(restored?.disabledRuleIds, snapshot.disabledRuleIds);

      final otherAccount = _session(
        email: 'other@example.com',
        uuid: 'other-account-uuid',
        endpoint: 'https://api-one.example.com',
        subscribeUrl: 'https://subscribe-one.example.com/client/token-one',
        token: 'token-one',
      );
      expect(await store.load(otherAccount), isNull);
    },
  );

  test(
    'migrates profile rules and restores them after profile deletion',
    () async {
      final appDatabase = Database(NativeDatabase.memory());
      addTearDown(appDatabase.close);
      final binding = XboardAccountRules(
        appDatabase: appDatabase,
        store: XboardAccountRuleStore(),
      );
      final session = _session(
        email: 'member@example.com',
        uuid: 'account-uuid',
        endpoint: 'https://api-one.example.com',
        subscribeUrl: 'https://subscribe.example.com/client/token',
        token: 'token-one',
      );
      const firstProfile = Profile(id: 1, autoUpdateDuration: Duration.zero);
      const firstRule = Rule(
        id: 101,
        ruleAction: RuleAction.DOMAIN_SUFFIX,
        content: 'first.example',
        ruleTarget: 'DIRECT',
        order: 'a',
      );
      const secondRule = Rule(
        id: 102,
        ruleAction: RuleAction.IP_CIDR,
        content: '198.51.100.0/24',
        ruleTarget: 'REJECT',
        order: 'b',
      );
      await appDatabase.profiles.put(firstProfile.toCompanion());
      await appDatabase.rulesDao.putProfileAddedRule(1, firstRule);
      await appDatabase.rulesDao.putProfileAddedRule(1, secondRule);
      await appDatabase.rulesDao.putDisabledLink(1, secondRule.id);

      expect(await binding.restoreOrMigrate(session, 1), isFalse);

      await appDatabase.profiles.remove((profile) => profile.id.equals(1));
      const replacementProfile = Profile(
        id: 2,
        autoUpdateDuration: Duration.zero,
      );
      await appDatabase.profiles.put(replacementProfile.toCompanion());

      expect(await binding.restoreOrMigrate(session, 2), isTrue);
      expect(await appDatabase.rulesDao.queryProfileAddedRules(2).get(), [
        firstRule,
        secondRule,
      ]);
      expect(
        await appDatabase.rulesDao
            .queryProfileDisabledRules(2)
            .map((rule) => rule.id)
            .get(),
        [secondRule.id],
      );
    },
  );

  test(
    'saving an empty rule set prevents deleted rules from returning',
    () async {
      final appDatabase = Database(NativeDatabase.memory());
      addTearDown(appDatabase.close);
      final binding = XboardAccountRules(
        appDatabase: appDatabase,
        store: XboardAccountRuleStore(),
      );
      final session = _session(
        email: 'member@example.com',
        uuid: 'account-uuid',
        endpoint: 'https://api.example.com',
        subscribeUrl: 'https://subscribe.example.com/client/token',
        token: 'token',
      );
      const profile = Profile(id: 1, autoUpdateDuration: Duration.zero);
      const rule = Rule(
        id: 201,
        ruleAction: RuleAction.DOMAIN,
        content: 'deleted.example',
        ruleTarget: 'DIRECT',
        order: 'a',
      );
      await appDatabase.profiles.put(profile.toCompanion());
      await appDatabase.rulesDao.putProfileAddedRule(profile.id, rule);
      await binding.save(session, profile.id);
      await appDatabase.rulesDao.delRules([rule.id]);
      await binding.save(session, profile.id);
      await appDatabase.profiles.remove((row) => row.id.equals(profile.id));
      const replacement = Profile(id: 2, autoUpdateDuration: Duration.zero);
      await appDatabase.profiles.put(replacement.toCompanion());

      expect(await binding.restoreOrMigrate(session, replacement.id), isFalse);
      expect(
        await appDatabase.rulesDao.queryProfileAddedRules(replacement.id).get(),
        isEmpty,
      );
    },
  );

  test('backup cleanup removes local account rules only', () async {
    final appDatabase = Database(NativeDatabase.memory());
    addTearDown(appDatabase.close);
    const profile = Profile(id: 1, autoUpdateDuration: Duration.zero);
    const globalRule = Rule(
      id: 301,
      ruleAction: RuleAction.DOMAIN,
      content: 'global.example',
      ruleTarget: 'DIRECT',
      order: 'a',
    );
    const accountRule = Rule(
      id: 302,
      ruleAction: RuleAction.DOMAIN,
      content: 'account.example',
      ruleTarget: 'REJECT',
      order: 'a',
    );
    const customRule = Rule(
      id: 303,
      ruleAction: RuleAction.MATCH,
      ruleTarget: 'DIRECT',
      order: 'a',
    );
    await appDatabase.profiles.put(profile.toCompanion());
    await appDatabase.rulesDao.putGlobalRule(globalRule);
    await appDatabase.rulesDao.putProfileAddedRule(profile.id, accountRule);
    await appDatabase.rulesDao.putDisabledLink(profile.id, accountRule.id);
    await appDatabase.rulesDao.putProfileCustomRule(profile.id, customRule);

    await appDatabase.rulesDao.removeLocalAccountRulesForBackup();

    expect(
      await appDatabase.rulesDao.queryProfileAddedRules(profile.id).get(),
      isEmpty,
    );
    expect(
      await appDatabase.rulesDao.queryProfileDisabledRules(profile.id).get(),
      isEmpty,
    );
    expect(await appDatabase.rulesDao.queryGlobalAddedRules().get(), [
      globalRule,
    ]);
    expect(
      await appDatabase.rulesDao.queryProfileCustomRules(profile.id).get(),
      [customRule],
    );
    expect(
      (await appDatabase.select(appDatabase.rules).get())
          .map((rule) => rule.id)
          .toSet(),
      {globalRule.id, customRule.id},
    );
  });
}

XboardLoginResult _session({
  required String email,
  required String uuid,
  required String endpoint,
  required String subscribeUrl,
  required String token,
}) {
  final endpointUri = Uri.parse(endpoint);
  return XboardLoginResult(
    endpoint: endpointUri,
    token: token,
    authData: 'Bearer $token',
    isAdmin: false,
    subscription: XboardSubscriptionData(
      endpoint: endpointUri,
      subscribeUrl: Uri.parse(subscribeUrl),
      email: email,
      uuid: uuid,
      uploadBytes: 0,
      downloadBytes: 0,
      transferEnableBytes: 0,
      rawData: const {},
    ),
  );
}

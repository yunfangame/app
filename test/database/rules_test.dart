import 'dart:io';

import 'package:drift/native.dart';
import 'package:fl_clash/database/database.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('added rules follow profile then global UI order', () async {
    final database = Database(NativeDatabase.memory());
    addTearDown(database.close);
    await database.profilesDao.putAll([
      const Profile(id: 1, autoUpdateDuration: Duration.zero).toCompanion(),
    ]);
    await database.rulesDao.putGlobalRule(
      const Rule(id: 4, content: 'global second', order: 'b'),
    );
    await database.rulesDao.putProfileAddedRule(
      1,
      const Rule(id: 2, content: 'profile second', order: 'b'),
    );
    await database.rulesDao.putGlobalRule(
      const Rule(id: 3, content: 'global first', order: 'a'),
    );
    await database.rulesDao.putProfileAddedRule(
      1,
      const Rule(id: 1, content: 'profile first', order: 'a'),
    );

    final rules = await database.rulesDao.queryAddedRules(1).get();

    expect(rules.map((rule) => rule.id), [1, 2, 3, 4]);
  });

  test(
    'saved process rules survive closing and reopening the database',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'saved_rules_test_',
      );
      final file = File('${directory.path}/rules.sqlite');
      var savedDatabase = Database(NativeDatabase.createInBackground(file));
      const firstProfile = Profile(id: 1, autoUpdateDuration: Duration.zero);
      const secondProfile = Profile(id: 2, autoUpdateDuration: Duration.zero);
      const weChatRule = Rule(
        id: 1,
        ruleAction: RuleAction.PROCESS_NAME,
        content: 'WeChat.exe',
        ruleTarget: 'DIRECT',
        order: 'a',
      );
      const weixinRule = Rule(
        id: 2,
        ruleAction: RuleAction.PROCESS_NAME,
        content: 'Weixin.exe',
        ruleTarget: 'DIRECT',
        order: 'b',
      );
      const globalRule = Rule(
        id: 3,
        ruleAction: RuleAction.DOMAIN_SUFFIX,
        content: 'example.com',
        ruleTarget: 'DIRECT',
        order: 'a',
      );

      try {
        await savedDatabase.profilesDao.putAll([
          firstProfile.toCompanion(),
          secondProfile.toCompanion(),
        ]);
        await savedDatabase.rulesDao.putProfileAddedRule(1, weChatRule);
        await savedDatabase.rulesDao.putProfileAddedRule(1, weixinRule);
        await savedDatabase.rulesDao.putGlobalRule(globalRule);
        await savedDatabase.rulesDao.orderProfileAddedRule(
          1,
          ruleId: weixinRule.id,
          order: 'Z',
        );
        await savedDatabase.rulesDao.putDisabledLink(1, weChatRule.id);
        await savedDatabase.rulesDao.bindProfileAccount(1, 'account-a');
        await savedDatabase.rulesDao.bindProfileAccount(2, 'account-b');
        await savedDatabase.close();

        savedDatabase = Database(NativeDatabase.createInBackground(file));
        final reorderedWeixinRule = weixinRule.copyWith(order: 'Z');
        expect(
          await savedDatabase.rulesDao.getProfileAccountKey(1),
          'account-a',
        );

        expect(await savedDatabase.profilesDao.query().get(), [
          firstProfile,
          secondProfile,
        ]);
        expect(await savedDatabase.rulesDao.queryProfileAddedRules(1).get(), [
          reorderedWeixinRule,
          weChatRule,
        ]);
        expect(await savedDatabase.rulesDao.queryGlobalAddedRules().get(), [
          globalRule,
        ]);
        expect(await savedDatabase.rulesDao.queryAddedRules(1).get(), [
          reorderedWeixinRule,
          globalRule,
        ]);
        expect(await savedDatabase.rulesDao.queryAddedRules(2).get(), [
          globalRule,
        ]);
        await (savedDatabase.delete(
          savedDatabase.profiles,
        )..where((table) => table.id.equals(1))).go();
        await savedDatabase.rulesDao.bindProfileAccount(3, 'account-a');
        expect(await savedDatabase.rulesDao.queryAddedRules(3).get(), [
          reorderedWeixinRule,
          globalRule,
        ]);
      } finally {
        await savedDatabase.close();
        await directory.delete(recursive: true);
      }
    },
  );
}

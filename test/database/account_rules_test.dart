import 'dart:async';

import 'package:drift/native.dart';
import 'package:fl_clash/database/database.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:flutter_test/flutter_test.dart';

const _weChat = Rule(
  id: 11,
  ruleAction: RuleAction.PROCESS_NAME,
  content: 'WeChat.exe',
  ruleTarget: 'DIRECT',
  order: 'a',
);
const _weixin = Rule(
  id: 12,
  ruleAction: RuleAction.PROCESS_NAME,
  content: 'Weixin.exe',
  ruleTarget: 'DIRECT',
  order: 'b',
);
const _global = Rule(
  id: 13,
  ruleAction: RuleAction.DOMAIN_SUFFIX,
  content: 'example.com',
  ruleTarget: 'DIRECT',
  order: 'a',
);

void main() {
  late Database database;

  setUp(() async {
    database = Database(NativeDatabase.memory());
    await database.customStatement('PRAGMA foreign_keys = ON');
    await database.profilesDao.putAll([
      for (final id in [1, 2, 3])
        Profile(id: id, autoUpdateDuration: Duration.zero).toCompanion(),
    ]);
  });

  tearDown(() => database.close());

  test(
    'watched rules follow account binding and account edits from another profile',
    () async {
      await database.rulesDao.bindProfileAccount(2, 'account-a');
      await database.rulesDao.putProfileAddedRule(2, _weChat);
      final updates = StreamIterator(
        database.rulesDao.queryAddedRules(1).watch(),
      );
      addTearDown(updates.cancel);

      Future<void> expectNext(List<Rule> rules) async {
        expect(
          await updates.moveNext().timeout(const Duration(seconds: 2)),
          isTrue,
        );
        expect(updates.current, rules);
      }

      await expectNext([]);
      await database.rulesDao.bindProfileAccount(1, 'account-a');
      await expectNext([_weChat]);
      await database.rulesDao.putProfileAddedRule(2, _weixin);
      await expectNext([_weChat, _weixin]);
      await database.rulesDao.orderProfileAddedRule(
        2,
        ruleId: _weixin.id,
        order: 'Z',
      );
      final reordered = _weixin.copyWith(order: 'Z');
      await expectNext([reordered, _weChat]);
      await database.rulesDao.putDisabledLink(2, _weChat.id);
      await expectNext([reordered]);
      await database.rulesDao.delDisabledLink(2, _weChat.id);
      await expectNext([reordered, _weChat]);
      await database.rulesDao.delRules([_weChat.id]);
      await expectNext([reordered]);
    },
  );

  test(
    'first binding migrates added and disabled rules but keeps custom rules',
    () async {
      final custom = _weixin.copyWith(id: 14);
      await database.rulesDao.putProfileAddedRule(1, _weChat);
      await database.rulesDao.putDisabledLink(1, _weChat.id);
      await database.rulesDao.putProfileCustomRule(1, custom);
      await database.rulesDao.putGlobalRule(_global);

      await database.rulesDao.bindProfileAccount(1, 'account-a');
      await database.rulesDao.bindProfileAccount(2, 'account-a');

      expect(await database.rulesDao.getProfileAccountKey(1), 'account-a');
      expect(await database.rulesDao.queryProfileAddedRules(2).get(), [
        _weChat,
      ]);
      expect(
        (await database.rulesDao.queryProfileDisabledRules(2).get()).single.id,
        _weChat.id,
      );
      expect(await database.rulesDao.queryAddedRules(2).get(), [_global]);
      expect(await database.rulesDao.queryProfileCustomRules(1).get(), [
        custom,
      ]);
      expect(await database.rulesDao.queryProfileCustomRules(2).get(), isEmpty);
      final links = await database.select(database.profileRuleLinks).get();
      final accountLinks = links.where((link) => link.accountKey != null);
      expect(accountLinks, hasLength(2));
      expect(accountLinks.every((link) => link.profileId == null), isTrue);
      expect(
        accountLinks.every((link) => link.id.startsWith('account:account-a_')),
        isTrue,
      );
      expect(await database.rulesDao.queryGlobalAddedRules().get(), [_global]);
    },
  );

  test(
    'switching A to B to A preserves independent rules and global overrides',
    () async {
      await database.rulesDao.putGlobalRule(_global);
      await database.rulesDao.bindProfileAccount(1, 'account-a');
      await database.rulesDao.putProfileAddedRule(1, _weChat);
      await database.rulesDao.putDisabledLink(1, _global.id);
      await database.rulesDao.bindProfileAccount(2, 'account-b');
      await database.rulesDao.putProfileAddedRule(2, _weixin);
      await database.rulesDao.bindProfileAccount(3, 'account-a');

      expect(await database.rulesDao.queryAddedRules(1).get(), [_weChat]);
      expect(await database.rulesDao.queryAddedRules(2).get(), [
        _weixin,
        _global,
      ]);
      expect(await database.rulesDao.queryAddedRules(3).get(), [_weChat]);
      expect(await database.rulesDao.queryGlobalAddedRules().get(), [_global]);
      expect(await database.rulesDao.queryProfileAddedRules(99).get(), isEmpty);
      await expectLater(
        database.rulesDao.bindProfileAccount(1, 'account-b'),
        throwsA(isA<StateError>()),
      );
      expect(await database.rulesDao.getProfileAccountKey(1), 'account-a');
    },
  );

  test(
    'deleting a profile preserves account rules and permits binding before profile creation',
    () async {
      await database.rulesDao.bindProfileAccount(1, 'account-a');
      await database.rulesDao.putProfileAddedRule(1, _weChat);
      await (database.delete(
        database.profiles,
      )..where((table) => table.id.equals(1))).go();

      await database.rulesDao.bindProfileAccount(99, 'account-a');

      expect(await database.rulesDao.queryAddedRules(99).get(), [_weChat]);
      await database.profilesDao.putAll([
        const Profile(id: 99, autoUpdateDuration: Duration.zero).toCompanion(),
      ]);
      expect(await database.rulesDao.queryAddedRules(99).get(), [_weChat]);
      await database.setProfileCustomData(99, [], []);
      expect(await database.rulesDao.queryAddedRules(99).get(), [_weChat]);
    },
  );

  test(
    'existing account state wins over legacy rules including an empty rule list',
    () async {
      await database.rulesDao.bindProfileAccount(1, 'account-a');
      await database.rulesDao.putProfileAddedRule(1, _weChat);
      await database.rulesDao.putProfileAddedRule(2, _weixin);
      await database.rulesDao.putDisabledLink(2, _weixin.id);

      await database.rulesDao.bindProfileAccount(2, 'account-a');

      expect(await database.rulesDao.queryAddedRules(2).get(), [_weChat]);
      expect(
        await database.rulesDao.queryProfileDisabledRules(2).get(),
        isEmpty,
      );
      await database.rulesDao.delRules([_weChat.id]);
      await database.rulesDao.putProfileAddedRule(3, _weixin);
      await database.rulesDao.bindProfileAccount(3, 'account-a');
      expect(await database.rulesDao.queryProfileAddedRules(3).get(), isEmpty);
      expect(await database.rulesDao.queryAddedRules(1).get(), isEmpty);
    },
  );

  test(
    'account CRUD order and enable changes are visible to a replacement profile',
    () async {
      await database.rulesDao.bindProfileAccount(1, 'account-a');
      await database.rulesDao.bindProfileAccount(2, 'account-a');
      await database.rulesDao.putProfileAddedRule(1, _weChat);
      await database.rulesDao.putProfileAddedRule(1, _weixin);
      final edited = _weChat.copyWith(content: 'WeChatAppEx.exe');
      await database.rulesDao.putProfileAddedRule(2, edited);
      await database.rulesDao.orderProfileAddedRule(
        2,
        ruleId: _weixin.id,
        order: 'Z',
      );
      final reordered = _weixin.copyWith(order: 'Z');
      expect(await database.rulesDao.queryAddedRules(1).get(), [
        reordered,
        edited,
      ]);
      await database.rulesDao.putDisabledLink(2, edited.id);
      expect(await database.rulesDao.queryAddedRules(1).get(), [reordered]);
      await database.rulesDao.delDisabledLink(1, edited.id);
      expect(await database.rulesDao.queryAddedRules(2).get(), [
        reordered,
        edited,
      ]);
      await database.rulesDao.delRules([edited.id]);
      expect(await database.rulesDao.queryProfileAddedRules(1).get(), [
        reordered,
      ]);
      expect(await database.rulesDao.queryGlobalAddedRules().get(), isEmpty);
    },
  );

  test(
    'restore preserves account rules and cannot import them as global rules',
    () async {
      await database.rulesDao.bindProfileAccount(1, 'account-a');
      await database.rulesDao.putProfileAddedRule(1, _weChat);
      await database.rulesDao.putDisabledLink(1, _weChat.id);
      final foreignRule = _weixin.copyWith(id: 15);

      await database.restore(
        [const Profile(id: 2, autoUpdateDuration: Duration.zero)],
        [],
        [_weChat.copyWith(ruleTarget: 'REJECT'), _global, foreignRule],
        [
          ProfileRuleLink(ruleId: _weChat.id),
          ProfileRuleLink(ruleId: _global.id),
          ProfileRuleLink(
            ruleId: foreignRule.id,
            accountKey: 'other-account',
            scene: RuleScene.added,
          ),
        ],
        [],
        isOverride: true,
      );
      await database.rulesDao.bindProfileAccount(2, 'account-a');

      expect(await database.rulesDao.queryProfileAddedRules(2).get(), [
        _weChat,
      ]);
      expect(
        (await database.rulesDao.queryProfileDisabledRules(2).get()).single.id,
        _weChat.id,
      );
      expect(
        (await database.rulesDao.queryGlobalAddedRules().get()).single.id,
        _global.id,
      );
      expect(
        (await database.rulesDao.queryAddedRules(2).get()).single.id,
        _global.id,
      );
      await database.rulesDao.bindProfileAccount(99, 'other-account');
      expect(await database.rulesDao.queryProfileAddedRules(99).get(), isEmpty);
    },
  );
}

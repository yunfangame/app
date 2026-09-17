import 'package:fl_clash/database/database.dart';

import 'xboard_account_rule_store.dart';
import 'xboard_auth.dart';

class XboardAccountRules {
  XboardAccountRules({Database? appDatabase, XboardAccountRuleStore? store})
    : _database = appDatabase ?? database,
      _store = store ?? XboardAccountRuleStore();

  final Database _database;
  final XboardAccountRuleStore _store;

  Future<void> save(XboardLoginResult session, int profileId) async {
    final rules = await _database.rulesDao
        .queryProfileAddedRules(profileId)
        .get();
    final disabledRuleIds = await _database.rulesDao
        .queryProfileDisabledRules(profileId)
        .map((rule) => rule.id)
        .get();
    await _store.save(
      session,
      XboardAccountRuleSnapshot(
        rules: List.unmodifiable(rules),
        disabledRuleIds: Set.unmodifiable(disabledRuleIds),
      ),
    );
  }

  Future<bool> restoreOrMigrate(
    XboardLoginResult session,
    int profileId, {
    bool Function()? isCurrent,
  }) async {
    if (isCurrent?.call() == false) return false;
    final currentRules = await _database.rulesDao
        .queryProfileAddedRules(profileId)
        .get();
    final currentDisabledRuleIds = await _database.rulesDao
        .queryProfileDisabledRules(profileId)
        .map((rule) => rule.id)
        .get();
    if (isCurrent?.call() == false) return false;
    if (currentRules.isNotEmpty || currentDisabledRuleIds.isNotEmpty) {
      await _store.save(
        session,
        XboardAccountRuleSnapshot(
          rules: List.unmodifiable(currentRules),
          disabledRuleIds: Set.unmodifiable(currentDisabledRuleIds),
        ),
      );
      return false;
    }

    final snapshot = await _store.load(session);
    if (isCurrent?.call() == false) return false;
    if (snapshot == null) {
      await _store.save(
        session,
        const XboardAccountRuleSnapshot(rules: [], disabledRuleIds: {}),
      );
      return false;
    }
    if (snapshot.rules.isEmpty && snapshot.disabledRuleIds.isEmpty) {
      return false;
    }
    if (isCurrent?.call() == false) return false;
    await _database.rulesDao.replaceProfileAddedRules(
      profileId,
      snapshot.rules,
      snapshot.disabledRuleIds,
    );
    return true;
  }
}

final xboardAccountRules = XboardAccountRules();

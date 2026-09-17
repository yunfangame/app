part of 'database.dart';

@DataClassName('RawRule')
@TableIndex(name: 'idx_rule_target', columns: {#ruleTarget})
class Rules extends Table {
  @override
  String get tableName => 'rules';

  IntColumn get id => integer()();

  TextColumn get ruleAction => textEnum<RuleAction>()();

  TextColumn get content => text().nullable()();

  TextColumn get ruleTarget => text().nullable()();

  TextColumn get ruleProvider => text().nullable()();

  TextColumn get subRule => text().nullable()();

  BoolColumn get noResolve => boolean().withDefault(const Constant(false))();

  BoolColumn get src => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {id};
}

@DriftAccessor(tables: [Rules, ProfileRuleLinks, ProfileRuleAccounts])
class RulesDao extends DatabaseAccessor<Database> with _$RulesDaoMixin {
  RulesDao(super.attachedDatabase);

  Future<String?> getProfileAccountKey(int profileId) async {
    final query = select(profileRuleAccounts)
      ..where((table) => table.profileId.equals(profileId));
    return (await query.getSingleOrNull())?.accountKey;
  }

  Future<void> bindProfileAccount(int profileId, String accountKey) async {
    if (accountKey.isEmpty) {
      throw ArgumentError.value(accountKey, 'accountKey');
    }
    await transaction(() async {
      final previous = await getProfileAccountKey(profileId);
      if (previous != null) {
        if (previous != accountKey) {
          throw StateError('profile_rule_account_mismatch');
        }
        return;
      }
      final accountProfiles = await (select(
        profileRuleAccounts,
      )..where((table) => table.accountKey.equals(accountKey))).get();
      final accountLinks = await (select(
        profileRuleLinks,
      )..where((table) => table.accountKey.equals(accountKey))).get();
      final legacyQuery = select(profileRuleLinks)
        ..where(
          (table) =>
              table.profileId.equals(profileId) &
              table.accountKey.isNull() &
              table.scene.isInValues([RuleScene.added, RuleScene.disabled]),
        );
      final legacyLinks = await legacyQuery.get();
      if (accountProfiles.isEmpty && accountLinks.isEmpty) {
        for (final link in legacyLinks) {
          await profileRuleLinks.insertOnConflictUpdate(
            link
                .toLink()
                .copyWith(profileId: null, accountKey: accountKey)
                .toCompanion(),
          );
        }
      }
      await profileRuleLinks.deleteWhere(
        (table) => table.id.isIn(legacyLinks.map((link) => link.id)),
      );
      await profileRuleAccounts.insertOnConflictUpdate(
        ProfileRuleAccountsCompanion.insert(
          profileId: Value(profileId),
          accountKey: accountKey,
        ),
      );
      await _deleteUnlinkedRules();
    });
  }

  Expression<bool> get _globalScope =>
      profileRuleLinks.profileId.isNull() &
      profileRuleLinks.accountKey.isNull();

  Expression<bool> _scope(int? profileId, RuleScene? scene) {
    if (profileId == null) return _globalScope;
    final local =
        profileRuleLinks.profileId.equals(profileId) &
        profileRuleLinks.accountKey.isNull();
    if (scene == RuleScene.custom) return local;
    final accountQuery = selectOnly(profileRuleAccounts)
      ..addColumns([profileRuleAccounts.accountKey])
      ..where(profileRuleAccounts.profileId.equals(profileId));
    return (local & notExistsQuery(accountQuery)) |
        (profileRuleLinks.profileId.isNull() &
            profileRuleLinks.accountKey.isInQuery(accountQuery));
  }

  Future<ProfileRuleLink> _link({
    required int ruleId,
    int? profileId,
    RuleScene? scene,
    String? order,
  }) async {
    final accountKey = profileId == null || scene == RuleScene.custom
        ? null
        : await getProfileAccountKey(profileId);
    return ProfileRuleLink(
      ruleId: ruleId,
      profileId: accountKey == null ? profileId : null,
      accountKey: accountKey,
      scene: scene,
      order: order,
    );
  }

  Selectable<Rule> queryGlobalAddedRules() {
    return _query();
  }

  Selectable<Rule> queryProfileAddedRules(int profileId) {
    return _query(profileId: profileId, scene: RuleScene.added);
  }

  Selectable<Rule> queryProfileDisabledRules(int profileId) {
    return _query(profileId: profileId, scene: RuleScene.disabled);
  }

  Selectable<Rule> queryProfileCustomRules(int profileId) {
    return _query(profileId: profileId, scene: RuleScene.custom);
  }

  Selectable<int> profileCustomRulesCount(int profileId) {
    final query = _getSelectStatement(
      profileId: profileId,
      scene: RuleScene.custom,
    );
    return query.count;
  }

  Selectable<Rule> queryAddedRules(int profileId) {
    final disabledIdsQuery = selectOnly(profileRuleLinks)
      ..addColumns([profileRuleLinks.ruleId])
      ..where(
        _scope(profileId, RuleScene.disabled) &
            profileRuleLinks.scene.equalsValue(RuleScene.disabled),
      );

    final query = select(rules).join([
      innerJoin(profileRuleLinks, profileRuleLinks.ruleId.equalsExp(rules.id)),
    ]);

    query.where(
      (_globalScope |
              (_scope(profileId, RuleScene.added) &
                  profileRuleLinks.scene.equalsValue(RuleScene.added))) &
          profileRuleLinks.ruleId.isNotInQuery(disabledIdsQuery),
    );

    query.orderBy([
      OrderingTerm.asc(
        _globalScope.caseMatch<int>(
          when: {const Constant(true): const Constant(1)},
          orElse: const Constant(0),
        ),
      ),
      OrderingTerm.asc(profileRuleLinks.order),
    ]);

    return query.map((row) {
      final ruleData = row.readTable(rules);
      final order = row.read(profileRuleLinks.order);
      return ruleData.toRule(order);
    });
  }

  Future<void> resetOrders() async {
    final stmt = profileRuleLinks.select();

    stmt.orderBy([
      (t) => OrderingTerm.asc(t.scene),
      (t) => OrderingTerm.desc(t.order),
      (t) => OrderingTerm.desc(t.id),
    ]);

    final links = await stmt.map((item) => item.toLink()).get();
    final keys = indexing.generateNKeys(links.length);
    await batch((b) {
      b.insertAllOnConflictUpdate(
        profileRuleLinks,
        links.mapIndexed((index, item) => item.toCompanion(keys[index])),
      );
    });
  }

  void restoreWithBatch(
    Batch batch,
    Iterable<Rule> rules,
    Iterable<ProfileRuleLink> links, {
    Set<int> protectedRuleIds = const {},
  }) {
    final importedLinks = links
        .where(
          (link) =>
              link.accountKey == null &&
              !protectedRuleIds.contains(link.ruleId),
        )
        .toList();
    final importedRuleIds = importedLinks.map((link) => link.ruleId).toSet();
    final importedRules = rules
        .where(
          (rule) =>
              importedRuleIds.contains(rule.id) &&
              !protectedRuleIds.contains(rule.id),
        )
        .toList();
    batch.insertAllOnConflictUpdate(
      this.rules,
      importedRules.map((item) => item.toCompanion()),
    );
    final ruleIds = {
      ...importedRules.map((item) => item.id),
      ...protectedRuleIds,
    };
    batch.deleteWhere(this.rules, (t) => t.id.isNotIn(ruleIds));
    final keys = indexing.generateNKeys(importedLinks.length);
    batch.insertAllOnConflictUpdate(
      profileRuleLinks,
      importedLinks.mapIndexed((index, item) => item.toCompanion(keys[index])),
    );
    final linkKeys = importedLinks.map((item) => item.key);
    batch.deleteWhere(
      profileRuleLinks,
      (t) => t.accountKey.isNull() & t.id.isNotIn(linkKeys),
    );
  }

  Future<Set<int>> _accountRuleIds() async {
    final query = selectOnly(profileRuleLinks)
      ..addColumns([profileRuleLinks.ruleId])
      ..where(profileRuleLinks.accountKey.isNotNull());
    return (await query.get())
        .map((row) => row.read(profileRuleLinks.ruleId)!)
        .toSet();
  }

  Future<void> delRules(Iterable<int> ruleIds) {
    return _delAll(ruleIds);
  }

  Future<void> putGlobalRule(Rule rule) {
    return _put(rule);
  }

  Future<void> putProfileAddedRule(int profileId, Rule rule) {
    return _put(rule, profileId: profileId, scene: RuleScene.added);
  }

  Future<void> putProfileCustomRule(int profileId, Rule rule) {
    return _put(rule, profileId: profileId, scene: RuleScene.custom);
  }

  Future<void> putProfileDisabledRule(int profileId, Rule rule) {
    return _put(rule, profileId: profileId, scene: RuleScene.disabled);
  }

  void setCustomRulesWithBatch(int profileId, Batch b, Iterable<Rule> rules) {
    _setWithBatch(b, rules, profileId: profileId, scene: RuleScene.custom);
  }

  Future<int> putDisabledLink(int profileId, int ruleId) async {
    final link = await _link(
      ruleId: ruleId,
      profileId: profileId,
      scene: RuleScene.disabled,
    );
    return profileRuleLinks.insertOnConflictUpdate(link.toCompanion());
  }

  Future<bool> delDisabledLink(int profileId, int ruleId) async {
    final link = await _link(
      ruleId: ruleId,
      profileId: profileId,
      scene: RuleScene.disabled,
    );
    return profileRuleLinks.deleteOne(link.toCompanion());
  }

  Future<int> orderGlobalRule({
    required int ruleId,
    required String order,
  }) async {
    return _order(ruleId: ruleId, order: order);
  }

  Future<int> orderProfileAddedRule(
    int profileId, {
    required int ruleId,
    required String order,
  }) async {
    return _order(
      ruleId: ruleId,
      order: order,
      profileId: profileId,
      scene: RuleScene.added,
    );
  }

  Future<int> orderProfileCustomRule(
    int profileId, {
    required int ruleId,
    required String order,
  }) async {
    return _order(
      ruleId: ruleId,
      order: order,
      profileId: profileId,
      scene: RuleScene.custom,
    );
  }

  Future<int> renameCustomRuleTarget(
    int profileId, {
    required String oldName,
    required String newName,
  }) {
    final stmt = rules.update()
      ..where((t) => t.ruleTarget.equals(oldName))
      ..where(
        (t) => t.id.isInQuery(
          selectOnly(profileRuleLinks)
            ..addColumns([profileRuleLinks.ruleId])
            ..where(
              profileRuleLinks.profileId.equals(profileId) &
                  profileRuleLinks.scene.equalsValue(RuleScene.custom),
            ),
        ),
      );
    return stmt.write(RulesCompanion(ruleTarget: Value(newName)));
  }

  JoinedSelectStatement<HasResultSet, dynamic> _getSelectStatement({
    int? profileId,
    RuleScene? scene,
  }) {
    final query = select(rules).join([
      innerJoin(profileRuleLinks, profileRuleLinks.ruleId.equalsExp(rules.id)),
    ]);

    query.where(
      _scope(profileId, scene) &
          (profileId == null
              ? const Constant(true)
              : profileRuleLinks.scene.equalsValue(scene)),
    );

    query.orderBy([OrderingTerm.asc(profileRuleLinks.order)]);

    return query;
  }

  Selectable<Rule> _query({int? profileId, RuleScene? scene}) {
    final query = _getSelectStatement(profileId: profileId, scene: scene);

    return query.map((row) {
      return row.readTable(rules).toRule(row.read(profileRuleLinks.order));
    });
  }

  Future<int> _order({
    required int ruleId,
    required String order,
    int? profileId,
    RuleScene? scene,
  }) async {
    final stmt = profileRuleLinks.update();
    stmt.where((t) {
      return _scope(profileId, scene) &
          t.ruleId.equals(ruleId) &
          t.scene.equalsValue(scene);
    });
    return stmt.write(ProfileRuleLinksCompanion(order: Value(order)));
  }

  Future<int> _put(Rule rule, {int? profileId, RuleScene? scene}) async {
    return transaction(() async {
      final row = await rules.insertOnConflictUpdate(rule.toCompanion());
      if (row == 0) {
        return 0;
      }
      return profileRuleLinks.insertOnConflictUpdate(
        (await _link(
          ruleId: rule.id,
          profileId: profileId,
          scene: scene,
          order: rule.order,
        )).toCompanion(),
      );
    });
  }

  Future<void> _delAll(Iterable<int> ruleIds) async {
    final ids = ruleIds.toList(growable: false);
    await transaction(() async {
      await profileRuleLinks.deleteWhere((t) => t.ruleId.isIn(ids));
      await rules.deleteWhere((t) => t.id.isIn(ids));
    });
  }

  Future<void> _deleteUnlinkedRules() async {
    final linkedIds = selectOnly(profileRuleLinks)
      ..addColumns([profileRuleLinks.ruleId]);
    await rules.deleteWhere((rule) => rule.id.isNotInQuery(linkedIds));
  }

  void _setWithBatch(
    Batch b,
    Iterable<Rule> rules, {
    int? profileId,
    RuleScene? scene,
  }) async {
    b.insertAllOnConflictUpdate(
      this.rules,
      rules.map((item) => item.toCompanion()),
    );

    b.deleteWhere(
      profileRuleLinks,
      (t) =>
          _scope(profileId, scene) &
          (scene == null ? const Constant(true) : t.scene.equalsValue(scene)),
    );

    final keys = indexing.generateNKeys(rules.length);

    b.insertAllOnConflictUpdate(
      profileRuleLinks,
      rules.mapIndexed(
        (index, item) => ProfileRuleLink(
          ruleId: item.id,
          profileId: profileId,
          scene: scene,
        ).toCompanion(keys[index]),
      ),
    );

    b.deleteWhere(this.rules, (r) {
      final linkedIds = selectOnly(profileRuleLinks);
      linkedIds.addColumns([profileRuleLinks.ruleId]);
      return r.id.isNotInQuery(linkedIds);
    });
  }
}

extension RawRuleExt on RawRule {
  Rule toRule([String? order]) {
    return Rule(
      id: id,
      ruleAction: ruleAction,
      content: content,
      ruleTarget: ruleTarget,
      ruleProvider: ruleProvider,
      subRule: subRule,
      noResolve: noResolve,
      src: src,
      order: order,
    );
  }
}

extension RulesCompanionExt on Rule {
  RulesCompanion toCompanion() {
    return RulesCompanion.insert(
      id: Value(id),
      ruleAction: ruleAction,
      content: Value(content),
      ruleTarget: Value(ruleTarget),
      ruleProvider: Value(ruleProvider),
      subRule: Value(subRule),
      noResolve: Value(noResolve),
      src: Value(src),
    );
  }
}

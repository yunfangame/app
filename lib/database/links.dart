part of 'database.dart';

@DataClassName('RawProfileRuleLink')
@TableIndex(
  name: 'idx_profile_scene_order',
  columns: {#profileId, #scene, #order},
)
class ProfileRuleLinks extends Table {
  @override
  String get tableName => 'profile_rule_mapping';

  TextColumn get id => text()();

  IntColumn get profileId => integer().nullable().references(
    Profiles,
    #id,
    onDelete: KeyAction.cascade,
  )();

  IntColumn get ruleId =>
      integer().references(Rules, #id, onDelete: KeyAction.cascade)();

  TextColumn get accountKey => text().nullable()();

  TextColumn get scene => textEnum<RuleScene>().nullable()();

  TextColumn get order => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('RawProfileRuleAccount')
class ProfileRuleAccounts extends Table {
  IntColumn get profileId => integer()();

  TextColumn get accountKey => text()();

  @override
  Set<Column> get primaryKey => {profileId};
}

extension RawProfileRuleLinkExt on RawProfileRuleLink {
  ProfileRuleLink toLink() {
    return ProfileRuleLink(
      profileId: profileId,
      accountKey: accountKey,
      ruleId: ruleId,
      scene: scene,
      order: order,
    );
  }
}

extension ProfileRuleLinksCompanionExt on ProfileRuleLink {
  ProfileRuleLinksCompanion toCompanion([String? order]) {
    return ProfileRuleLinksCompanion.insert(
      id: key,
      ruleId: ruleId,
      scene: Value(scene),
      profileId: Value(profileId),
      accountKey: Value(accountKey),
      order: Value(order ?? this.order),
    );
  }
}

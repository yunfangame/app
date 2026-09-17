import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:fl_clash/models/models.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'xboard_auth.dart';

class XboardAccountRuleSnapshot {
  const XboardAccountRuleSnapshot({
    required this.rules,
    required this.disabledRuleIds,
  });

  factory XboardAccountRuleSnapshot.fromJson(Map<String, Object?> json) {
    if (json['version'] != 1) {
      throw const FormatException('Unsupported account rule snapshot');
    }
    final rawRules = json['rules'];
    final rawDisabledRuleIds = json['disabled_rule_ids'];
    if (rawRules is! List || rawDisabledRuleIds is! List) {
      throw const FormatException('Invalid account rule snapshot');
    }
    final rules = rawRules
        .map((item) {
          if (item is! Map) {
            throw const FormatException('Invalid account rule');
          }
          return Rule.fromJson(
            item.map((key, value) => MapEntry(key.toString(), value)),
          );
        })
        .toList(growable: false);
    final ruleIds = rules.map((rule) => rule.id).toSet();
    final disabledRuleIds = rawDisabledRuleIds
        .map((item) => item is int ? item : int.tryParse(item.toString()))
        .whereType<int>()
        .where(ruleIds.contains)
        .toSet();
    return XboardAccountRuleSnapshot(
      rules: List.unmodifiable(rules),
      disabledRuleIds: Set.unmodifiable(disabledRuleIds),
    );
  }

  final List<Rule> rules;
  final Set<int> disabledRuleIds;

  Map<String, Object?> toJson() => {
    'version': 1,
    'rules': rules.map((rule) => rule.toJson()).toList(growable: false),
    'disabled_rule_ids': disabledRuleIds.toList(growable: false),
  };
}

class XboardAccountRuleStore {
  XboardAccountRuleStore({
    Future<SharedPreferences> Function()? preferencesLoader,
  }) : _preferencesLoader = preferencesLoader ?? SharedPreferences.getInstance;

  static const _keyPrefix = 'xboard.local_account_rules.v1.';

  final Future<SharedPreferences> Function() _preferencesLoader;
  Future<void> _writeQueue = Future.value();

  Future<XboardAccountRuleSnapshot?> load(XboardLoginResult session) async {
    final preferences = await _preferencesLoader();
    for (final key in _keys(session)) {
      final source = preferences.getString(key);
      if (source == null || source.isEmpty) continue;
      try {
        final decoded = jsonDecode(source);
        if (decoded is! Map) continue;
        return XboardAccountRuleSnapshot.fromJson(
          decoded.map((key, value) => MapEntry(key.toString(), value)),
        );
      } catch (_) {
        continue;
      }
    }
    return null;
  }

  Future<void> save(
    XboardLoginResult session,
    XboardAccountRuleSnapshot snapshot,
  ) {
    final keys = _keys(session);
    if (keys.isEmpty) return Future.value();
    final source = jsonEncode(snapshot.toJson());
    final operation = _writeQueue.then((_) async {
      final preferences = await _preferencesLoader();
      for (final key in keys) {
        final saved = await preferences.setString(key, source);
        if (!saved) throw StateError('account_rules_save_failed');
      }
    });
    _writeQueue = operation.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return operation;
  }

  List<String> _keys(XboardLoginResult session) {
    final subscription = session.subscription;
    final identities = <String>{};
    final uuid = subscription.uuid?.trim();
    if (uuid != null && uuid.isNotEmpty) identities.add('uuid:$uuid');
    final email = subscription.email?.trim().toLowerCase();
    if (email != null && email.isNotEmpty) identities.add('email:$email');
    return identities.map(_key).toList(growable: false);
  }

  String _key(String identity) {
    final digest = sha256.convert(utf8.encode(identity)).toString();
    return '$_keyPrefix$digest';
  }
}

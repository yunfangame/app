import 'package:fl_clash/common/chain_proxy.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';

bool hasValidSavedNodeSelection({
  required Mode mode,
  required List<Group> groups,
  required Map<String, String> selectedMap,
  String? ruleGroupName,
  String? currentGroupName,
}) {
  if (mode == Mode.direct) return true;
  final groupsByName = <String, Group>{};
  for (final group in groups) {
    if (groupsByName.containsKey(group.name)) return false;
    groupsByName[group.name] = group;
  }
  final root = mode == Mode.global
      ? groupsByName[GroupName.GLOBAL.name]
      : _ruleRoot(groups, groupsByName, ruleGroupName, currentGroupName);
  if (root == null || mode == Mode.global && root.type != GroupType.Selector) {
    return false;
  }
  return _hasSavedPath(root, groupsByName, selectedMap, const {});
}

Group? _ruleRoot(
  List<Group> groups,
  Map<String, Group> groupsByName,
  String? ruleGroupName,
  String? currentGroupName,
) {
  final ruleGroup = groupsByName[ruleGroupName];
  if (ruleGroup != null && ruleGroup.name != GroupName.GLOBAL.name) {
    return ruleGroup;
  }
  final visibleSelectors = groups.where(
    (group) =>
        group.hidden == false &&
        group.name != GroupName.GLOBAL.name &&
        group.type == GroupType.Selector,
  );
  for (final group in visibleSelectors) {
    if (group.name == currentGroupName) return group;
  }
  return visibleSelectors.firstOrNull;
}

bool _hasSavedPath(
  Group group,
  Map<String, Group> groupsByName,
  Map<String, String> selectedMap,
  Set<String> ancestors,
) {
  if (ancestors.contains(group.name) || group.type == GroupType.Relay) {
    return false;
  }
  final nextAncestors = {...ancestors, group.name};
  bool memberIsValid(Proxy member) {
    if (isChainProxyRuntimeName(member.name)) return false;
    final name = _adapterToken(member.name);
    final type = _adapterToken(member.type);
    if (name.isEmpty || type.isEmpty) return false;
    if (_pseudoAdapters.contains(name) || _pseudoAdapters.contains(type)) {
      return false;
    }
    if (!_groupAdapterTypes.contains(type)) return true;
    final nestedGroup = groupsByName[member.name];
    return nestedGroup != null &&
        _hasSavedPath(nestedGroup, groupsByName, selectedMap, nextAncestors);
  }

  final savedName = selectedMap[group.name];
  if (group.type == GroupType.Selector ||
      group.type.isComputedSelected && savedName?.isNotEmpty == true) {
    if (savedName == null || savedName.isEmpty) return false;
    final members = group.all.where((member) => member.name == savedName);
    return members.length == 1 && memberIsValid(members.single);
  }
  return group.all.any(memberIsValid);
}

String _adapterToken(String value) {
  return value.toLowerCase().replaceAll(RegExp(r'[\s_-]'), '');
}

const _pseudoAdapters = {
  'global',
  'direct',
  'reject',
  'rejectdrop',
  'pass',
  'passrule',
  'rematch',
  'compatible',
  'dns',
  'unknown',
};

const _groupAdapterTypes = {
  'select',
  'selector',
  'urltest',
  'fallback',
  'loadbalance',
  'relay',
};

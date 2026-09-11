import 'package:fl_clash/common/chain_proxy.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';

class ModeNodeSelectionPlan {
  ModeNodeSelectionPlan({
    required this.nodeName,
    required this.targetGroupName,
    required Map<String, String> selections,
  }) : selections = Map.unmodifiable(selections);

  final String nodeName;
  final String targetGroupName;
  final Map<String, String> selections;
}

String? resolveRuleModeDisplayGroup({
  required String? ruleTargetName,
  required String? currentGroupName,
  required List<Group> groups,
}) {
  final visibleGroups = groups
      .where((group) => group.hidden == false)
      .where((group) => group.name != GroupName.GLOBAL.name)
      .toList();
  if (visibleGroups.isEmpty) return null;
  if (ruleTargetName != null &&
      visibleGroups.any((group) => group.name == ruleTargetName)) {
    return ruleTargetName;
  }
  if (currentGroupName != null &&
      visibleGroups.any((group) => group.name == currentGroupName)) {
    return currentGroupName;
  }
  return visibleGroups.first.name;
}

String? resolveModeNodeLeaf({
  required String rootGroupName,
  required List<Group> groups,
  required Map<String, String> selectedMap,
}) {
  final groupsByName = _uniqueGroupsByName(groups);
  if (groupsByName == null) return null;
  final root = groupsByName[rootGroupName];
  if (root == null) return null;
  return _resolveCurrentLeaf(root, groupsByName, selectedMap, const {});
}

ModeNodeSelectionPlan? planModeNodeSelection({
  required String sourceGroupName,
  required String targetGroupName,
  required List<Group> groups,
  required Map<String, String> selectedMap,
}) {
  final groupsByName = _uniqueGroupsByName(groups);
  if (groupsByName == null) return null;
  final source = groupsByName[sourceGroupName];
  final target = groupsByName[targetGroupName];
  if (target == null) return null;

  final nodeName = source == null
      ? sourceGroupName
      : _resolveCurrentLeaf(source, groupsByName, selectedMap, const {});
  if (nodeName == null) return null;

  final selections = _findTargetPath(
    target,
    nodeName,
    groupsByName,
    selectedMap,
    const {},
  );
  if (selections == null) return null;
  return ModeNodeSelectionPlan(
    nodeName: nodeName,
    targetGroupName: targetGroupName,
    selections: Map.fromEntries(selections),
  );
}

String? _resolveCurrentLeaf(
  Group group,
  Map<String, Group> groupsByName,
  Map<String, String> selectedMap,
  Set<String> ancestors,
) {
  if (ancestors.contains(group.name) ||
      group.type == GroupType.LoadBalance ||
      group.type == GroupType.Relay) {
    return null;
  }
  final selectedName = switch (group.type) {
    GroupType.Selector => _currentSelectorMember(group, selectedMap),
    GroupType.URLTest || GroupType.Fallback => group.realNow,
    GroupType.LoadBalance || GroupType.Relay => '',
  };
  if (selectedName.isEmpty) return null;

  final member = _memberNamed(group, selectedName);
  if (member == null) return null;
  if (_isGroupMember(member)) {
    final nestedGroup = groupsByName[selectedName];
    if (nestedGroup == null) return null;
    return _resolveCurrentLeaf(nestedGroup, groupsByName, selectedMap, {
      ...ancestors,
      group.name,
    });
  }
  return _isRealLeaf(member) ? member.name : null;
}

List<MapEntry<String, String>>? _findTargetPath(
  Group group,
  String nodeName,
  Map<String, Group> groupsByName,
  Map<String, String> selectedMap,
  Set<String> ancestors,
) {
  if (ancestors.contains(group.name) ||
      group.type == GroupType.LoadBalance ||
      group.type == GroupType.Relay) {
    return null;
  }
  final nextAncestors = {...ancestors, group.name};

  if (group.type.isComputedSelected) {
    final currentName = group.realNow;
    if (currentName.isEmpty) return null;
    final currentMember = _memberNamed(group, currentName);
    if (currentMember == null) return null;
    if (_isGroupMember(currentMember)) {
      final nestedGroup = groupsByName[currentName];
      if (nestedGroup == null) return null;
      return _findTargetPath(
        nestedGroup,
        nodeName,
        groupsByName,
        selectedMap,
        nextAncestors,
      );
    }
    return currentName == nodeName && _isRealLeaf(currentMember) ? [] : null;
  }

  final currentName = _currentSelectorMember(group, selectedMap);
  final orderedMembers = <Proxy>[
    if (currentName.isNotEmpty)
      for (final member in group.all)
        if (member.name == currentName) member,
    for (final member in group.all)
      if (member.name != currentName) member,
  ];
  for (final member in orderedMembers) {
    List<MapEntry<String, String>>? suffix;
    if (_isGroupMember(member)) {
      final nestedGroup = groupsByName[member.name];
      if (nestedGroup == null) continue;
      suffix = _findTargetPath(
        nestedGroup,
        nodeName,
        groupsByName,
        selectedMap,
        nextAncestors,
      );
    } else if (member.name == nodeName && _isRealLeaf(member)) {
      suffix = [];
    }
    if (suffix != null) {
      return [MapEntry(group.name, member.name), ...suffix];
    }
  }
  return null;
}

Map<String, Group>? _uniqueGroupsByName(List<Group> groups) {
  final groupsByName = <String, Group>{};
  for (final group in groups) {
    if (groupsByName.containsKey(group.name)) return null;
    groupsByName[group.name] = group;
  }
  return groupsByName;
}

Proxy? _memberNamed(Group group, String name) {
  for (final member in group.all) {
    if (member.name == name) return member;
  }
  return null;
}

String _currentSelectorMember(Group group, Map<String, String> selectedMap) {
  final saved = selectedMap[group.name] ?? '';
  if (_memberNamed(group, saved) != null) return saved;
  return _memberNamed(group, group.realNow) != null ? group.realNow : '';
}

bool _isRealLeaf(Proxy proxy) {
  if (isChainProxyRuntimeName(proxy.name)) return false;
  final name = _normaliseAdapterToken(proxy.name);
  final type = _normaliseAdapterToken(proxy.type);
  if (name.isEmpty || type.isEmpty) return false;
  if (_pseudoAdapters.contains(name) || _pseudoAdapters.contains(type)) {
    return false;
  }
  return !_groupAdapterTypes.contains(type);
}

bool _isGroupMember(Proxy proxy) {
  return _groupAdapterTypes.contains(_normaliseAdapterToken(proxy.type));
}

String _normaliseAdapterToken(String value) {
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

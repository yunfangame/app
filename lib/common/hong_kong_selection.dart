import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';

class HongKongCandidate {
  HongKongCandidate({
    required this.nodeName,
    required this.groupName,
    required Map<String, String> selections,
  }) : selections = Map.unmodifiable(selections);

  final String nodeName;
  final String groupName;
  final Map<String, String> selections;
}

List<HongKongCandidate> hongKongCandidates({
  required Mode mode,
  required List<Group> groups,
  required Map<String, String> selectedMap,
  String? currentGroupName,
}) {
  if (mode == Mode.direct) return const [];
  final groupsByName = <String, Group>{
    for (final group in groups) group.name: group,
  };
  if (mode == Mode.global) {
    final group = groupsByName[GroupName.GLOBAL.name];
    return group == null
        ? const []
        : _candidatesForGroup(group, groupsByName, selectedMap);
  }
  final visibleGroups = groups.where(
    (group) =>
        group.hidden == false &&
        group.name != GroupName.GLOBAL.name &&
        group.type == GroupType.Selector,
  );
  final preferredGroups = visibleGroups.where(
    (group) => group.name == currentGroupName,
  );
  for (final group in [
    ...preferredGroups,
    ...visibleGroups.where((group) => group.name != currentGroupName),
  ]) {
    final candidates = _candidatesForGroup(group, groupsByName, selectedMap);
    if (candidates.isNotEmpty) return candidates;
  }
  return const [];
}

List<HongKongCandidate> _candidatesForGroup(
  Group root,
  Map<String, Group> groupsByName,
  Map<String, String> selectedMap,
) {
  if (root.type != GroupType.Selector) return const [];
  final pending = <_SelectionStep>[
    for (final member in root.all.reversed)
      _SelectionStep(
        group: root,
        member: member,
        selections: const {},
        ancestors: {root.name},
        isCurrent: true,
      ),
  ];
  final currentCandidates = <HongKongCandidate>[];
  final otherCandidates = <HongKongCandidate>[];
  while (pending.isNotEmpty) {
    final step = pending.removeLast();
    final member = step.member;
    final selections = {...step.selections, step.group.name: member.name};
    final isCurrent =
        step.isCurrent &&
        step.group.getCurrentSelectedName(selectedMap[step.group.name] ?? '') ==
            member.name;
    final nestedGroup = groupsByName[member.name];
    if (nestedGroup != null) {
      if (nestedGroup.type != GroupType.Selector ||
          step.ancestors.contains(nestedGroup.name)) {
        continue;
      }
      for (final nestedMember in nestedGroup.all.reversed) {
        pending.add(
          _SelectionStep(
            group: nestedGroup,
            member: nestedMember,
            selections: selections,
            ancestors: {...step.ancestors, nestedGroup.name},
            isCurrent: isCurrent,
          ),
        );
      }
      continue;
    }
    if (!_isHongKongLeaf(member)) continue;
    final candidate = HongKongCandidate(
      nodeName: member.name,
      groupName: root.name,
      selections: selections,
    );
    (isCurrent ? currentCandidates : otherCandidates).add(candidate);
  }
  final includedNodes = <String>{};
  return List.unmodifiable([
    for (final candidate in [...currentCandidates, ...otherCandidates])
      if (includedNodes.add(candidate.nodeName)) candidate,
  ]);
}

bool _isHongKongLeaf(Proxy proxy) {
  if (!proxy.name.contains('香港')) return false;
  final type = proxy.type.toLowerCase().replaceAll('-', '').trim();
  if (const {
    '',
    'direct',
    'reject',
    'rejectdrop',
    'compatible',
    'pass',
    'passrule',
    'rematch',
    'dns',
    'unknown',
  }.contains(type)) {
    return false;
  }
  return !GroupType.values.any(
    (groupType) =>
        groupType.name.toLowerCase() == type ||
        groupType.value.replaceAll('-', '') == type,
  );
}

class _SelectionStep {
  const _SelectionStep({
    required this.group,
    required this.member,
    required this.selections,
    required this.ancestors,
    required this.isCurrent,
  });

  final Group group;
  final Proxy member;
  final Map<String, String> selections;
  final Set<String> ancestors;
  final bool isCurrent;
}

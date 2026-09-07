import 'package:fl_clash/common/compute.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';

class NetworkDiagnosticSelection {
  const NetworkDiagnosticSelection({
    required this.mode,
    this.selectedGroup,
    this.selectedNode,
  });

  final Mode mode;
  final String? selectedGroup;
  final String? selectedNode;
}

NetworkDiagnosticSelection computeNetworkDiagnosticSelection({
  required Mode mode,
  required List<Group> groups,
  required Map<String, String> selectedMap,
  String? currentGroupName,
}) {
  if (mode == Mode.direct) {
    return NetworkDiagnosticSelection(
      mode: mode,
      selectedNode: UsedProxy.DIRECT.name,
    );
  }
  final visibleGroups = groups
      .where((group) => group.hidden == false)
      .where((group) => group.name != GroupName.GLOBAL.name)
      .toList();
  final group = mode == Mode.global
      ? groups.getGroup(GroupName.GLOBAL.name)
      : visibleGroups.getGroup(currentGroupName ?? '') ??
            (visibleGroups.isEmpty ? null : visibleGroups.first);
  if (group == null) return NetworkDiagnosticSelection(mode: mode);
  return NetworkDiagnosticSelection(
    mode: mode,
    selectedGroup: group.name,
    selectedNode: _resolveSelectedLeaf(group, groups, selectedMap),
  );
}

String? _resolveSelectedLeaf(
  Group initialGroup,
  List<Group> groups,
  Map<String, String> selectedMap,
) {
  final visited = <String>{};
  var group = initialGroup;
  while (visited.length < 128) {
    if (!visited.add(group.name) ||
        group.type == GroupType.LoadBalance ||
        group.type == GroupType.Relay) {
      return null;
    }
    final selectedName = group.getCurrentSelectedName(
      selectedMap[group.name] ?? '',
    );
    if (selectedName.isEmpty) return null;
    final memberIndex = group.all.indexWhere(
      (proxy) => proxy.name == selectedName,
    );
    if (memberIndex < 0) return null;
    final nestedGroup = groups.getGroup(selectedName);
    if (nestedGroup != null) {
      group = nestedGroup;
      continue;
    }
    final memberType = group.all[memberIndex].type.toLowerCase();
    if (GroupType.values.any(
      (type) =>
          type.name.toLowerCase() == memberType || type.value == memberType,
    )) {
      return null;
    }
    return computeRealSelectedProxyState(
      initialGroup.name,
      groups: groups,
      selectedMap: selectedMap,
    ).proxyName;
  }
  return null;
}

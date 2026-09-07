import 'package:fl_clash/common/xboard_auth.dart';
import 'package:fl_clash/l10n/l10n.dart';

enum XboardNodeDisplayStatus { online, offline, unknown }

XboardNodeDisplayStatus resolveXboardNodeDisplayStatus(
  String name,
  Iterable<XboardNodeData> nodes, {
  bool statusAvailable = true,
}) {
  if (!statusAvailable || name.trim().isEmpty) {
    return XboardNodeDisplayStatus.unknown;
  }
  var matches = nodes.where((node) => node.name == name).toList();
  if (matches.isEmpty) {
    final key = xboardNodeMatchKey(name);
    if (key.isEmpty) return XboardNodeDisplayStatus.unknown;
    matches = nodes
        .where((node) => xboardNodeMatchKey(node.name) == key)
        .toList();
  }
  if (matches.length != 1) return XboardNodeDisplayStatus.unknown;
  final value = matches.single.rawData['is_online'];
  return switch (value is String ? value.trim().toLowerCase() : value) {
    true || 1 || '1' || 'true' => XboardNodeDisplayStatus.online,
    false || 0 || '0' || 'false' => XboardNodeDisplayStatus.offline,
    _ => XboardNodeDisplayStatus.unknown,
  };
}

String formatXboardNodeDisplayStatus(XboardNodeDisplayStatus status) {
  final l10n = AppLocalizations.current;
  return switch (status) {
    XboardNodeDisplayStatus.online => l10n.nodeBackendOnline,
    XboardNodeDisplayStatus.offline => l10n.nodeBackendOffline,
    XboardNodeDisplayStatus.unknown => l10n.nodeStatusUnknown,
  };
}

int? referenceDelayMilliseconds(int? measuredDelay) {
  return measuredDelay;
}

String formatReferenceDelay(int measuredDelay) {
  final l10n = AppLocalizations.current;
  if (measuredDelay == 0) return l10n.testingStatus;
  if (measuredDelay < 0) return l10n.timeout;
  return l10n.referenceDelayValue(measuredDelay);
}

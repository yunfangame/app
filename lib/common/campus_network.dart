import 'package:fl_clash/models/models.dart';

const campusNetworkConfigKey = 'campusHostsByOperator';
const legacyCampusNetworkConfigKey = 'campusHosts';

class CampusNetworkConfig {
  const CampusNetworkConfig(this.hostsByOperator);

  factory CampusNetworkConfig.fromRemote(Object? remoteConfig) {
    if (remoteConfig is! Map) {
      throw const FormatException('Invalid campus network config');
    }
    if (remoteConfig.containsKey(campusNetworkConfigKey)) {
      final value = remoteConfig[campusNetworkConfigKey];
      if (value is! Map) {
        throw const FormatException('Invalid campus network lines');
      }
      final grouped = _parseGroupedHosts(value);
      if (value.isEmpty || _hasAvailableLine(grouped)) {
        return CampusNetworkConfig(grouped);
      }
      throw const FormatException('Campus network config is incomplete');
    }
    final legacyValue = remoteConfig[legacyCampusNetworkConfigKey];
    if (legacyValue is List && legacyValue.isEmpty) {
      return const CampusNetworkConfig({});
    }
    final legacy = _parseLegacyHosts(legacyValue);
    if (_hasAvailableLine(legacy)) {
      return CampusNetworkConfig(legacy);
    }
    throw const FormatException('Campus network config is incomplete');
  }

  final Map<String, Map<String, String>> hostsByOperator;

  Map<String, String> hostsFor(String operator) =>
      Map.unmodifiable(hostsByOperator[operator] ?? const {});
}

PatchClashConfig applyCampusNetworkConfig(
  PatchClashConfig patchConfig,
  AppSettingProps appSettings,
) {
  if (!appSettings.campusNetworkEnabled) {
    return patchConfig;
  }
  final hosts = appSettings.campusHostsByOperator[appSettings.campusOperator];
  if (hosts == null || hosts.isEmpty) {
    return patchConfig;
  }
  return patchConfig.copyWith(
    hosts: {...patchConfig.hosts, ...hosts},
    dns: patchConfig.dns.copyWith(enable: true, useHosts: true),
  );
}

bool hasActiveCampusNetworkConfig(AppSettingProps appSettings) {
  if (!appSettings.campusNetworkEnabled) {
    return false;
  }
  return appSettings
          .campusHostsByOperator[appSettings.campusOperator]
          ?.isNotEmpty ==
      true;
}

bool hasCompleteCampusNetworkConfig(
  Map<String, Map<String, String>> hostsByOperator,
) {
  return _hasAvailableLine(hostsByOperator);
}

List<String> availableCampusOperators(
  Map<String, Map<String, String>> hostsByOperator,
) {
  return [
    for (final entry in hostsByOperator.entries)
      if (entry.value.isNotEmpty) entry.key,
  ];
}

String resolveCampusOperator(
  String selected,
  Map<String, Map<String, String>> hostsByOperator,
) {
  final available = availableCampusOperators(hostsByOperator);
  if (available.contains(selected)) {
    return selected;
  }
  return available.isEmpty ? '' : available.first;
}

Map<String, Map<String, String>> _parseGroupedHosts(Object? value) {
  if (value is! Map) {
    return const {};
  }
  final result = <String, Map<String, String>>{};
  for (final entry in value.entries) {
    if (entry.key is! String || (entry.key as String).trim().isEmpty) {
      continue;
    }
    final entries = _parseHostEntries(entry.value);
    if (entries.isNotEmpty) {
      result[entry.key as String] = entries;
    }
  }
  return result;
}

Map<String, Map<String, String>> _parseLegacyHosts(Object? value) {
  if (value is! List) {
    return const {};
  }
  final candidates = <String, List<String>>{};
  for (final entry in value) {
    final parsed = _parseHostEntry(entry);
    if (parsed == null) {
      continue;
    }
    final values = candidates.putIfAbsent(parsed.key, () => []);
    values.add(parsed.value);
  }
  final result = <String, Map<String, String>>{};
  final count = candidates.values.fold<int>(
    0,
    (maximum, values) => values.length > maximum ? values.length : maximum,
  );
  const legacyIds = ['telecom', 'unicom', 'mobile'];
  for (var index = 0; index < count; index++) {
    final hosts = <String, String>{};
    for (final entry in candidates.entries) {
      if (entry.value.length > index) {
        hosts[entry.key] = entry.value[index];
      }
    }
    if (hosts.isNotEmpty) {
      final id = index < legacyIds.length
          ? legacyIds[index]
          : 'line_${index + 1}';
      result[id] = hosts;
    }
  }
  return result;
}

Map<String, String> _parseHostEntries(Object? value) {
  if (value is! List) {
    return const {};
  }
  final hosts = <String, String>{};
  for (final entry in value) {
    final parsed = _parseHostEntry(entry);
    if (parsed != null) {
      hosts[parsed.key] = parsed.value;
    }
  }
  return hosts;
}

MapEntry<String, String>? _parseHostEntry(Object? value) {
  if (value is! String) {
    return null;
  }
  final parts = value.trim().split(RegExp(r'\s+'));
  if (parts.length != 2 || !_isIpv4(parts[0])) {
    return null;
  }
  final domain = parts[1].toLowerCase();
  final uri = Uri.tryParse('https://$domain');
  if (uri == null || uri.host != domain || domain.contains('..')) {
    return null;
  }
  return MapEntry(domain, parts[0]);
}

bool _isIpv4(String value) {
  final parts = value.split('.');
  if (parts.length != 4) {
    return false;
  }
  return parts.every((part) {
    if (part.isEmpty || (part.length > 1 && part.startsWith('0'))) {
      return false;
    }
    final number = int.tryParse(part);
    return number != null && number >= 0 && number <= 255;
  });
}

bool _hasAvailableLine(Map<String, Map<String, String>> value) {
  return availableCampusOperators(value).isNotEmpty;
}

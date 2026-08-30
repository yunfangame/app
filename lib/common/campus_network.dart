import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';

const campusNetworkConfigKey = 'campusHostsByOperator';
const legacyCampusNetworkConfigKey = 'campusHosts';

class CampusNetworkConfig {
  const CampusNetworkConfig(this.hostsByOperator);

  factory CampusNetworkConfig.fromRemote(Object? remoteConfig) {
    if (remoteConfig is! Map) {
      throw const FormatException('Invalid campus network config');
    }
    final grouped = _parseGroupedHosts(remoteConfig[campusNetworkConfigKey]);
    if (_isComplete(grouped)) {
      return CampusNetworkConfig(grouped);
    }
    final legacy = _parseLegacyHosts(
      remoteConfig[legacyCampusNetworkConfigKey],
    );
    if (_isComplete(legacy)) {
      return CampusNetworkConfig(legacy);
    }
    throw const FormatException('Campus network config is incomplete');
  }

  final Map<String, Map<String, String>> hostsByOperator;

  Map<String, String> hostsFor(CampusOperator operator) =>
      Map.unmodifiable(hostsByOperator[operator.name] ?? const {});
}

PatchClashConfig applyCampusNetworkConfig(
  PatchClashConfig patchConfig,
  AppSettingProps appSettings,
) {
  if (!appSettings.campusNetworkEnabled) {
    return patchConfig;
  }
  final hosts =
      appSettings.campusHostsByOperator[appSettings.campusOperator.name];
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
          .campusHostsByOperator[appSettings.campusOperator.name]
          ?.isNotEmpty ==
      true;
}

bool hasCompleteCampusNetworkConfig(
  Map<String, Map<String, String>> hostsByOperator,
) {
  return _isComplete(hostsByOperator);
}

Map<String, Map<String, String>> _parseGroupedHosts(Object? value) {
  if (value is! Map) {
    return const {};
  }
  final result = <String, Map<String, String>>{};
  for (final operator in CampusOperator.values) {
    final entries = _parseHostEntries(value[operator.name]);
    if (entries.isNotEmpty) {
      result[operator.name] = entries;
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
    if (!values.contains(parsed.value)) {
      values.add(parsed.value);
    }
  }
  final result = <String, Map<String, String>>{};
  for (var index = 0; index < CampusOperator.values.length; index++) {
    final hosts = <String, String>{};
    for (final entry in candidates.entries) {
      if (entry.value.length > index) {
        hosts[entry.key] = entry.value[index];
      }
    }
    if (hosts.isNotEmpty) {
      result[CampusOperator.values[index].name] = hosts;
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

bool _isComplete(Map<String, Map<String, String>> value) {
  return CampusOperator.values.every(
    (operator) => value[operator.name]?.isNotEmpty == true,
  );
}

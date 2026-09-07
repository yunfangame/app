import 'package:yaml/yaml.dart';

String? defaultRuleTarget(String configuration) {
  final config = loadYaml(configuration);
  if (config is! Map || config['rules'] is! List) return null;
  String? target;
  for (final rule in config['rules'] as List) {
    if (rule is! String) continue;
    final parts = rule.split(',').map((part) => part.trim()).toList();
    if (parts.length >= 2 && parts.first.toUpperCase() == 'MATCH') {
      target = parts[1];
      break;
    }
  }
  if (target == null || target.isEmpty) return null;
  final proxies = config['proxies'];
  final visited = <String>{};
  while (proxies is List && visited.add(target!)) {
    String? upstream;
    for (final proxy in proxies) {
      if (proxy is Map && proxy['name'] == target) {
        final value = proxy['dialer-proxy'];
        if (value is String && value.isNotEmpty) upstream = value;
        break;
      }
    }
    if (upstream == null) return target;
    target = upstream;
  }
  return proxies is List ? null : target;
}

import 'dart:io';

import 'package:fl_clash/enum/enum.dart';

const systemBypassDns = 'system://';

bool isValidBypassDomain(String value) {
  final domain = value.trim().toLowerCase();
  if (domain == '<local>') return true;
  if (InternetAddress.tryParse(domain) != null) return true;
  if (domain.isEmpty || domain.length > 253 || domain == '*') return false;
  final host = domain.startsWith('+.') || domain.startsWith('*.')
      ? domain.substring(2)
      : domain.startsWith('.')
      ? domain.substring(1)
      : domain;
  return host
      .split('.')
      .every(
        (label) =>
            label.isNotEmpty &&
            label.length <= 63 &&
            RegExp(r'^[a-z0-9_*][a-z0-9_*-]*$').hasMatch(label) &&
            !label.endsWith('-'),
      );
}

bool isValidBypassDns(String value) {
  final text = value.trim();
  if (text.isEmpty || text == systemBypassDns) return true;
  if (InternetAddress.tryParse(text) != null) return true;
  final uri = Uri.tryParse('udp://$text');
  return uri != null &&
      uri.userInfo.isEmpty &&
      uri.path.isEmpty &&
      !uri.hasQuery &&
      !uri.hasFragment &&
      uri.hasPort &&
      uri.port > 0 &&
      uri.port <= 65535 &&
      InternetAddress.tryParse(uri.host) != null;
}

List<String> bypassDomainRules(Iterable<String> domains) {
  final result = <String>{};
  for (final value in domains) {
    final domain = value.trim().toLowerCase();
    if (!isValidBypassDomain(domain) ||
        domain == '<local>' ||
        InternetAddress.tryParse(domain) != null ||
        RegExp(r'^[0-9.*]+$').hasMatch(domain)) {
      continue;
    }
    if (domain.startsWith('+.')) {
      result.add('DOMAIN-SUFFIX,${domain.substring(2)}');
    } else if (domain.startsWith('.')) {
      result.add('DOMAIN-WILDCARD,*$domain');
    } else {
      result.add(
        '${domain.contains('*') ? 'DOMAIN-WILDCARD' : 'DOMAIN'},$domain',
      );
    }
  }
  return result.toList();
}

Map<String, dynamic> applyBypassDomainConfig(
  Map<String, dynamic> source,
  Mode mode, {
  bool enabled = false,
  List<String> domains = const [],
  String nameserver = systemBypassDns,
}) {
  final config = Map<String, dynamic>.from(source);
  if (!enabled || mode != Mode.rule) return config;
  final domainRules = bypassDomainRules(domains);
  if (domainRules.isEmpty) return config;
  if (!isValidBypassDns(nameserver)) {
    throw const FormatException('Invalid bypass DNS server');
  }
  final server = nameserver.trim().isEmpty
      ? systemBypassDns
      : nameserver.trim();
  final providers = Map<String, dynamic>.from(
    config['rule-providers'] as Map? ?? {},
  );
  String addProvider(String base, String behavior, List<String> payload) {
    var name = base;
    for (var suffix = 2; providers.containsKey(name); suffix++) {
      name = '$base-$suffix';
    }
    providers[name] = {
      'type': 'inline',
      'behavior': behavior,
      'payload': payload,
    };
    return name;
  }

  final provider = addProvider(
    'fengwo-bypass-domains',
    'classical',
    domainRules,
  );
  final dns = Map<String, dynamic>.from(config['dns'] as Map? ?? {});
  dns['enable'] = true;
  if ((dns['nameserver'] as List?)?.isNotEmpty != true) {
    dns['nameserver'] = [systemBypassDns];
  }
  dns['nameserver-policy'] = {
    'rule-set:$provider': [
      server == systemBypassDns ? server : '$server#DIRECT',
    ],
    ...Map<String, dynamic>.from(dns['nameserver-policy'] as Map? ?? {}),
  };
  if ((dns['direct-nameserver'] as List?)?.isNotEmpty == true) {
    dns['direct-nameserver-follow-policy'] = true;
  }
  final filters = List<String>.from(dns['fake-ip-filter'] as List? ?? []);
  switch (dns['fake-ip-filter-mode']) {
    case 'rule':
      dns['fake-ip-filter'] = ['RULE-SET,$provider,real-ip', ...filters];
    case 'whitelist':
      final plainFilters = <String>[];
      final filterRules = <String>[];
      for (final filter in filters) {
        final normalized = filter.toLowerCase();
        if (normalized.startsWith('geosite:') ||
            normalized.startsWith('rule-set:')) {
          final separator = filter.indexOf(':');
          final type = normalized.startsWith('geosite:')
              ? 'GEOSITE'
              : 'RULE-SET';
          for (final name in filter.substring(separator + 1).split(',')) {
            filterRules.add('$type,$name,fake-ip');
          }
        } else {
          plainFilters.add(filter);
        }
      }
      if (plainFilters.isNotEmpty) {
        final original = addProvider(
          'fengwo-fake-ip-whitelist',
          'domain',
          plainFilters,
        );
        filterRules.add('RULE-SET,$original,fake-ip');
      }
      dns['fake-ip-filter-mode'] = 'rule';
      dns['fake-ip-filter'] = [
        'RULE-SET,$provider,real-ip',
        ...filterRules,
        'MATCH,real-ip',
      ];
    default:
      dns['fake-ip-filter'] = [...filters, 'rule-set:$provider'];
  }
  config['dns'] = dns;
  config['rule-providers'] = providers;
  config['rules'] = [
    'RULE-SET,$provider,DIRECT',
    ...List<String>.from(config['rules'] as List? ?? []),
  ];
  return config;
}

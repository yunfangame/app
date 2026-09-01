import 'dart:io';

const localNetworkBypassDomains = [
  '<local>',
  'localhost',
  '*.localhost',
  '*.local',
  '*.localdomain',
  '*.lan',
  '*.home.arpa',
  '127.*',
  '10.*',
  '169.254.*',
  '172.16.*',
  '172.17.*',
  '172.18.*',
  '172.19.*',
  '172.20.*',
  '172.21.*',
  '172.22.*',
  '172.23.*',
  '172.24.*',
  '172.25.*',
  '172.26.*',
  '172.27.*',
  '172.28.*',
  '172.29.*',
  '172.30.*',
  '172.31.*',
  '192.168.*',
  '::1',
];

const localNetworkFakeIpFilters = [
  'localhost',
  '*.localhost',
  '*.local',
  '*.localdomain',
  '*.lan',
  '*.home.arpa',
];

const localNetworkDirectRules = [
  'DOMAIN,localhost,DIRECT',
  'DOMAIN-SUFFIX,localhost,DIRECT',
  'DOMAIN-SUFFIX,local,DIRECT',
  'DOMAIN-SUFFIX,localdomain,DIRECT',
  'DOMAIN-SUFFIX,lan,DIRECT',
  'DOMAIN-SUFFIX,home.arpa,DIRECT',
  'IP-CIDR,10.0.0.0/8,DIRECT,no-resolve',
  'IP-CIDR,100.64.0.0/10,DIRECT,no-resolve',
  'IP-CIDR,127.0.0.0/8,DIRECT,no-resolve',
  'IP-CIDR,169.254.0.0/16,DIRECT,no-resolve',
  'IP-CIDR,172.16.0.0/12,DIRECT,no-resolve',
  'IP-CIDR,192.168.0.0/16,DIRECT,no-resolve',
  'IP-CIDR6,::1/128,DIRECT,no-resolve',
  'IP-CIDR6,fc00::/7,DIRECT,no-resolve',
  'IP-CIDR6,fe80::/10,DIRECT,no-resolve',
];

List<String> withLocalNetworkBypassDomains(Iterable<String> values) {
  return {
    ...values.where((value) => value != '172.2*'),
    ...localNetworkBypassDomains,
  }.toList();
}

List<String> withLocalNetworkFakeIpFilters(Iterable<Object?> values) {
  return {...values.whereType<String>(), ...localNetworkFakeIpFilters}.toList();
}

List<String> withLocalNetworkDirectRules(Iterable<String> values) {
  return {...localNetworkDirectRules, ...values}.toList();
}

extension NetworkInterfaceExt on NetworkInterface {
  bool get isWifi {
    final nameLowCase = name.toLowerCase();
    if (nameLowCase.contains('wlan') ||
        nameLowCase.contains('wi-fi') ||
        nameLowCase == 'en0' ||
        nameLowCase == 'eth0') {
      return true;
    }

    return false;
  }

  bool get includesIPv4 {
    return addresses.any((addr) => addr.isIPv4);
  }
}

extension InternetAddressExt on InternetAddress {
  bool get isIPv4 {
    return type == InternetAddressType.IPv4;
  }
}

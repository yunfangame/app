import 'dart:convert';

import 'package:fl_clash/common/bypass_domain.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> fixture() => {
  'dns': <String, dynamic>{
    'enable': true,
    'enhanced-mode': 'fake-ip',
    'nameserver': ['https://public.example/dns-query'],
    'fallback': ['tls://public.example'],
    'direct-nameserver': ['9.9.9.9'],
    'direct-nameserver-follow-policy': false,
    'nameserver-policy': {
      'geosite:private': ['9.9.9.9'],
      'oa.corp.example': ['8.8.8.8'],
    },
    'fake-ip-filter': ['+.existing.example'],
  },
  'rule-providers': {
    'fengwo-bypass-domains': {
      'type': 'inline',
      'behavior': 'domain',
      'payload': ['+.subscription.example'],
    },
  },
  'rules': ['DOMAIN,oa.corp.example,REJECT', 'MATCH,Proxy'],
};

void main() {
  test('old persisted network settings retain opt-in defaults', () {
    final value = NetworkProps.fromJson({
      'bypassDomain': ['oa.corp.example'],
    });
    expect(value.bypassDomainRouting, isFalse);
    expect(value.bypassDomainDns, systemBypassDns);
    final next = value.copyWith(
      bypassDomainRouting: true,
      bypassDomainDns: '10.0.0.53:5353',
    );
    expect(NetworkProps.fromJson(jsonDecode(jsonEncode(next))), next);
  });

  test(
    'domain validation rejects URLs ports control characters and broad catch-all',
    () {
      for (final value in [
        'oa.corp.example',
        '*.corp.example',
        '+.corp.example',
        'intranet',
        '<local>',
        '192.168.*',
        '::1',
      ]) {
        expect(isValidBypassDomain(value), isTrue, reason: value);
      }
      for (final value in [
        '',
        '*',
        'https://oa.corp.example',
        'oa.corp.example:80',
        'oa.corp.example/path',
        'corp,REJECT',
        'corp;*',
        'a..corp',
        'a.corp\nb.corp',
      ]) {
        expect(isValidBypassDomain(value), isFalse, reason: value);
      }
    },
  );

  test(
    'DNS servers support system IPv4 IPv6 and explicit ports without URL injection',
    () {
      for (final value in [
        '',
        'system://',
        '10.0.0.53',
        '10.0.0.53:5353',
        'fd00::53',
        '[fd00::53]:5353',
      ]) {
        expect(isValidBypassDns(value), isTrue, reason: value);
      }
      for (final value in [
        'public.example',
        '10.0.0.53:0',
        '10.0.0.53:65536',
        '10.0.0.53#Proxy',
        'https://public.example/dns-query',
        '10.0.0.53/path',
        'user@10.0.0.53:53',
      ]) {
        expect(isValidBypassDns(value), isFalse, reason: value);
      }
    },
  );

  test('native IP bypass entries do not become DNS domain rules', () {
    expect(
      bypassDomainRules([
        ' OA.Corp.Example ',
        'oa.corp.example',
        '*.corp.example',
        '+.corp.example',
        '.corp.example',
        '<local>',
        '10.*',
        '127.0.0.1',
        '::1',
        'invalid,REJECT',
      ]),
      [
        'DOMAIN,oa.corp.example',
        'DOMAIN-WILDCARD,*.corp.example',
        'DOMAIN-SUFFIX,corp.example',
      ],
    );
  });

  for (final mode in Mode.values) {
    test('disabled bypass preserves original config in $mode', () {
      final source = fixture();
      expect(
        applyBypassDomainConfig(source, mode, domains: ['oa.corp.example']),
        source,
      );
    });
    if (mode != Mode.rule) {
      test('enabled bypass does not change $mode semantics or DNS', () {
        final source = fixture();
        expect(
          applyBypassDomainConfig(
            source,
            mode,
            enabled: true,
            domains: ['*.corp.example'],
          ),
          source,
        );
      });
    }
  }

  test('empty exclusions leave rule mode untouched', () {
    final source = fixture();
    expect(applyBypassDomainConfig(source, Mode.rule, enabled: true), source);
    expect(
      applyBypassDomainConfig(
        source,
        Mode.rule,
        enabled: true,
        domains: ['<local>', '10.*'],
      ),
      source,
    );
  });

  test(
    'rule mode prioritizes intranet DNS and direct routing without modifying source',
    () {
      final source = fixture();
      final before = jsonDecode(jsonEncode(source));
      final result = applyBypassDomainConfig(
        source,
        Mode.rule,
        enabled: true,
        domains: ['*.corp.example'],
      );
      expect(source, before);
      expect(result['rules'], [
        'RULE-SET,fengwo-bypass-domains-2,DIRECT',
        ...source['rules'] as List,
      ]);
      final dns = result['dns'] as Map;
      final originalDns = source['dns'] as Map;
      expect(
        (dns['nameserver-policy'] as Map).keys.first,
        'rule-set:fengwo-bypass-domains-2',
      );
      expect(
        (dns['nameserver-policy'] as Map)['rule-set:fengwo-bypass-domains-2'],
        ['system://'],
      );
      expect(dns['nameserver'], originalDns['nameserver']);
      expect(dns['fallback'], originalDns['fallback']);
      expect(dns['direct-nameserver'], originalDns['direct-nameserver']);
      expect(dns['direct-nameserver-follow-policy'], isTrue);
      expect(dns['fake-ip-filter'], [
        '+.existing.example',
        'rule-set:fengwo-bypass-domains-2',
      ]);
      expect(
        (result['rule-providers'] as Map)['fengwo-bypass-domains'],
        (source['rule-providers'] as Map)['fengwo-bypass-domains'],
      );
    },
  );

  test(
    'custom intranet DNS is explicitly direct even when subscription DNS respects rules',
    () {
      final source = fixture();
      (source['dns'] as Map)['respect-rules'] = true;
      final result = applyBypassDomainConfig(
        source,
        Mode.rule,
        enabled: true,
        domains: ['oa.corp.example'],
        nameserver: '10.0.0.53:5353',
      );
      expect((result['dns']['nameserver-policy'] as Map).values.first, [
        '10.0.0.53:5353#DIRECT',
      ]);
      expect(result['dns']['respect-rules'], isTrue);
    },
  );

  test(
    'rule fake-IP filter adds intranet exception ahead of original MATCH',
    () {
      final source = fixture();
      (source['dns'] as Map).addAll(<String, dynamic>{
        'fake-ip-filter-mode': 'rule',
        'fake-ip-filter': ['MATCH,fake-ip'],
      });
      final result = applyBypassDomainConfig(
        source,
        Mode.rule,
        enabled: true,
        domains: ['oa.corp.example'],
      );
      expect(result['dns']['fake-ip-filter'], [
        'RULE-SET,fengwo-bypass-domains-2,real-ip',
        'MATCH,fake-ip',
      ]);
    },
  );

  test(
    'fake-IP whitelist preserves original real-IP default and public-domain matching',
    () {
      final source = fixture();
      (source['dns'] as Map).addAll(<String, dynamic>{
        'fake-ip-filter-mode': 'whitelist',
        'fake-ip-filter': [
          '+.existing.example',
          'geosite:cn',
          'rule-set:fengwo-bypass-domains',
        ],
      });
      final result = applyBypassDomainConfig(
        source,
        Mode.rule,
        enabled: true,
        domains: ['oa.corp.example'],
      );
      expect(result['dns']['fake-ip-filter-mode'], 'rule');
      expect(result['dns']['fake-ip-filter'], [
        'RULE-SET,fengwo-bypass-domains-2,real-ip',
        'GEOSITE,cn,fake-ip',
        'RULE-SET,fengwo-bypass-domains,fake-ip',
        'RULE-SET,fengwo-fake-ip-whitelist,fake-ip',
        'MATCH,real-ip',
      ]);
      expect(result['rule-providers']['fengwo-fake-ip-whitelist']['payload'], [
        '+.existing.example',
      ]);
    },
  );

  test('invalid DNS fails without inserting rules', () {
    expect(
      () => applyBypassDomainConfig(
        fixture(),
        Mode.rule,
        enabled: true,
        domains: ['oa.corp.example'],
        nameserver: 'invalid#Proxy',
      ),
      throwsFormatException,
    );
  });
}

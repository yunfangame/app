import 'dart:convert';
import 'dart:io';

import 'package:fl_clash/common/task.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yaml/yaml.dart';

const staleTarget = '香港动态家宽01-vip';
const domainPattern =
    r'(^|[.])(github[.]com|githubusercontent[.]com|githubassets[.]com|github[.]io|npmjs[.]org|npmjs[.]com|pypi[.]org|pythonhosted[.]org|huggingface[.]co|hf[.]co)$';
const staleRule = Rule(
  id: 73,
  ruleAction: RuleAction.DOMAIN_REGEX,
  content: domainPattern,
  ruleTarget: staleTarget,
);

Map<String, dynamic> subscription({bool restored = false}) => {
  'proxies': [
    for (var i = 0; i < 73; i++)
      {
        'name': restored && i == 0 ? staleTarget : 'Node $i',
        'type': 'http',
        'server': '127.0.0.1',
        'port': 58080 + i,
      },
  ],
  'proxy-groups': [
    {
      'name': 'Main',
      'type': 'select',
      'proxies': ['DIRECT'],
    },
  ],
  'rules': ['DOMAIN,existing.example,REJECT', 'MATCH,Main'],
};

Future<String> generate(
  Map<String, dynamic> raw, {
  List<Rule> added = const [staleRule],
  List<Rule> custom = const [],
  List<ProxyGroup> groups = const [],
  bool tun = false,
}) async {
  final result = await makeRealProfileTask(
    MakeRealProfileState(
      profilesPath: Directory.systemTemp.path,
      profileId: 73,
      rawConfig: raw,
      realPatchConfig: PatchClashConfig(tun: Tun(enable: tun)),
      overrideDns: false,
      appendSystemDns: false,
      proxyGroups: groups,
      rules: custom,
      addedRules: added,
      defaultUA: 'Stale-Rule-Test',
    ),
  );
  return result.a;
}

void main() {
  for (final tun in [false, true]) {
    test('73-node update replaces stale regex target with TUN $tun', () async {
      final raw = subscription();
      final before = jsonEncode(raw);
      const saved = [
        staleRule,
        Rule(content: 'active.example', ruleTarget: 'Node 1'),
        Rule(content: 'group.example', ruleTarget: 'Main'),
        Rule(content: 'fallback.example', ruleTarget: 'MATCH'),
      ];
      final yaml = await generate(raw, added: saved, tun: tun);
      final config = loadYaml(yaml);
      expect(config['proxies'], hasLength(73));
      expect(config['rules'].join('\n'), isNot(contains(staleTarget)));
      expect(
        config['rules'],
        containsAllInOrder([
          'DOMAIN-REGEX,$domainPattern,Main',
          'DOMAIN,active.example,Node 1',
          'DOMAIN,group.example,Main',
          'DOMAIN,fallback.example,Main',
          'DOMAIN,existing.example,REJECT',
          'MATCH,Main',
        ]),
      );
      expect(jsonEncode(raw), before);
      expect(saved.first, staleRule);
      expect(saved.first.ruleTarget, staleTarget);
      final directory = Platform.environment['FENGWO_RULE_EVIDENCE'];
      if (directory != null) {
        await Directory(directory).create(recursive: true);
        await File('$directory/fixed-tun-$tun.yaml').writeAsString(yaml);
        await File('$directory/broken-tun-$tun.yaml').writeAsString(
          yaml.replaceFirst('DOMAIN,active.example,Node 1', staleRule.rawValue),
        );
      }
    });
  }

  test('each refresh uses the latest available targets', () async {
    expect(
      loadYaml(await generate(subscription()))['rules'],
      isNot(contains(staleRule.rawValue)),
    );
    expect(
      loadYaml(await generate(subscription(restored: true)))['rules'],
      contains(staleRule.rawValue),
    );
    expect(
      loadYaml(await generate(subscription()))['rules'],
      isNot(contains(staleRule.rawValue)),
    );
  });

  test('renamed nodes and removed groups use the latest default', () async {
    final raw = subscription();
    raw['proxies'][0]['name'] = '$staleTarget-new';
    final result = loadYaml(
      await generate(
        raw,
        added: const [
          staleRule,
          Rule(content: 'removed.example', ruleTarget: 'OldGroup'),
          Rule(content: 'case.example', ruleTarget: 'main'),
        ],
      ),
    );
    expect(result['rules'].join('\n'), isNot(contains(staleTarget)));
    expect(result['rules'].join('\n'), isNot(contains('OldGroup')));
    expect(result['rules'], contains('MATCH,Main'));
  });

  test('all built-in targets and sub-rule references are preserved', () async {
    final saved = [
      for (final target in [
        'DIRECT',
        'REJECT',
        'REJECT-DROP',
        'COMPATIBLE',
        'PASS',
        'PASS-RULE',
        'GLOBAL',
      ])
        Rule(content: 'builtin.example', ruleTarget: target),
      const Rule(
        ruleAction: RuleAction.SUB_RULE,
        content: '(NETWORK,TCP)',
        subRule: 'nested',
      ),
    ];
    final raw = subscription();
    raw['sub-rules'] = {
      'nested': ['MATCH,DIRECT'],
    };
    final config = loadYaml(await generate(raw, added: saved));
    expect(config['rules'], containsAllInOrder(saved.map((r) => r.rawValue)));
  });

  test('custom rules use effective replacement groups', () async {
    final config = loadYaml(
      await generate(
        subscription(),
        custom: const [
          staleRule,
          Rule(content: 'old-group.example', ruleTarget: 'Main'),
          Rule(content: 'new-group.example', ruleTarget: 'Replacement'),
          Rule(ruleAction: RuleAction.MATCH, ruleTarget: 'DIRECT'),
        ],
        groups: const [
          ProxyGroup(
            id: 1,
            name: 'Replacement',
            type: GroupType.Selector,
            proxies: ['DIRECT'],
          ),
        ],
      ),
    );
    final rules = config['rules'].join('\n');
    expect(rules, isNot(contains(staleTarget)));
    expect(rules, contains('DOMAIN,old-group.example,DIRECT'));
    expect(rules, contains('DOMAIN,new-group.example,Replacement'));
    expect(config['rules'].last, 'MATCH,DIRECT');
  });

  test('missing default uses the existing GLOBAL selection', () async {
    final raw = subscription();
    raw['rules'] = ['DOMAIN,existing.example,DIRECT'];
    final config = loadYaml(
      await generate(
        raw,
        added: const [
          Rule(content: 'placeholder.example', ruleTarget: 'MATCH'),
        ],
      ),
    );
    expect(config['rules'], contains('DOMAIN,placeholder.example,GLOBAL'));
  });

  test('stale references in subscription rules are repaired too', () async {
    final raw = subscription();
    raw['rules'] = [staleRule.rawValue, 'MATCH,Main'];
    final config = loadYaml(await generate(raw, added: const []));
    expect(config['rules'], contains('DOMAIN-REGEX,$domainPattern,Main'));
  });
}

import 'dart:convert';
import 'dart:io';

import 'package:fl_clash/common/bypass_domain.dart';
import 'package:fl_clash/common/task.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yaml/yaml.dart';

void main() {
  test(
    'generated profiles preserve public routing and emit valid intranet policies',
    () async {
      final fixtures = <Map<String, Object>>[];
      for (final mode in [Mode.rule, Mode.global]) {
        for (final filterMode in ['blacklist', 'whitelist', 'rule']) {
          final profile = await makeRealProfileTask(
            MakeRealProfileState(
              profilesPath: '/tmp/fengwo-bypass-test',
              profileId: 1,
              rawConfig: {
                'dns': {
                  'enable': true,
                  'enhanced-mode': 'fake-ip',
                  'fake-ip-range': '198.18.0.1/16',
                  'fake-ip-filter-mode': filterMode,
                  'fake-ip-filter': switch (filterMode) {
                    'rule' => ['MATCH,fake-ip'],
                    'whitelist' => ['+.public.test'],
                    _ => ['+.unchanged.test'],
                  },
                  'nameserver': ['127.0.0.1:55153'],
                  'direct-nameserver': ['127.0.0.1:55153'],
                  'direct-nameserver-follow-policy': false,
                  'nameserver-policy': {
                    'oa.corp.example': ['127.0.0.1:55153'],
                  },
                },
                'proxies': [
                  {
                    'name': 'Proxy',
                    'type': 'http',
                    'server': '127.0.0.1',
                    'port': 58080,
                  },
                ],
                'rules': ['DOMAIN,oa.corp.example,REJECT', 'MATCH,Proxy'],
              },
              realPatchConfig: PatchClashConfig(
                mode: mode,
                tun: const Tun(enable: false),
              ),
              overrideDns: false,
              appendSystemDns: false,
              proxyGroups: [],
              rules: [],
              addedRules: [],
              defaultUA: 'FengWo-Bypass-Test',
              bypassDomainRouting: true,
              bypassDomains: ['*.corp.example'],
              bypassDomainDns: '127.0.0.1:55154',
            ),
          );
          expect(loadYaml(profile.a)['mode'], mode.name);
          expect(
            profile.a.contains('rule-set:fengwo-bypass-domains'),
            mode == Mode.rule,
          );
          fixtures.add({
            'mode': mode.name,
            'filter_mode': filterMode,
            'yaml': profile.a,
          });
        }
      }
      expect(bypassDomainRules(['*.corp.example']), [
        'DOMAIN-WILDCARD,*.corp.example',
      ]);
      final directory = Platform.environment['FENGWO_BYPASS_EVIDENCE'];
      if (directory != null) {
        await Directory(directory).create(recursive: true);
        await File(
          '$directory/generated-runtime-fixtures.json',
        ).writeAsString(jsonEncode(fixtures));
      }
    },
  );
}

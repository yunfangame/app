import 'dart:convert';
import 'dart:io';

import 'package:fl_clash/common/chain_proxy.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'generate native chain fixtures through the production transformer',
    () async {
      final output = Directory('tooling/windows/real/generated');
      await output.create(recursive: true);
      final cases = <Map<String, dynamic>>[
        {'name': 'rule-no-auth', 'exit_auth': false},
        {'name': 'rule-auth-ip'},
        {'name': 'rule-auth-domain', 'server': 'localhost'},
        {'name': 'global-auth', 'mode': 'global'},
        {'name': 'switch-exit', 'exit_port': 31814},
        {'name': 'disabled', 'disabled': true},
        {'name': 'direct-mode', 'mode': 'direct'},
        {
          'name': 'exit-wrong-password',
          'password': 'synthetic-wrong',
          'failure': 'authentication',
        },
        {
          'name': 'exit-connect-rejected',
          'behavior': 'reject',
          'failure': 'connect',
        },
        {
          'name': 'exit-handshake-timeout',
          'behavior': 'timeout',
          'failure': 'timeout',
        },
        {
          'name': 'node-wrong-password',
          'node_password': 'synthetic-wrong',
          'failure': 'node-authentication',
        },
        {'name': 'http-exit-auth', 'protocol': 'http'},
        for (var index = 1; index <= 20; index++)
          {
            'name': 'restart-${index.toString().padLeft(2, '0')}',
            'restart_iteration': index,
            'mode': index.isOdd ? 'global' : 'rule',
            'exit_port': index % 3 == 0 ? 31814 : 31813,
          },
      ];
      for (final item in cases) {
        final mode = switch (item['mode']) {
          'global' => Mode.global,
          'direct' => Mode.direct,
          _ => Mode.rule,
        };
        final source = <String, dynamic>{
          'mixed-port': 17980,
          'allow-lan': false,
          'bind-address': '127.0.0.1',
          'mode': mode.name,
          'log-level': 'warning',
          'ipv6': false,
          'find-process-mode': 'off',
          'external-controller': '',
          'geodata-mode': false,
          'geo-auto-update': false,
          'dns': {'enable': false},
          'tun': {'enable': false},
          'proxies': [
            {
              'name': 'Synthetic Node',
              'type': 'socks5',
              'server': '127.0.0.1',
              'port': 31811,
              'username': 'synthetic-node',
              'password': item['node_password'] ?? 'synthetic-node-pass',
              'udp': false,
            },
          ],
          'proxy-groups': <Object>[],
          'rules': ['MATCH,Synthetic Node'],
        };
        final chain = item['disabled'] == true
            ? null
            : ChainProxyConfig(
                name: 'Synthetic Exit',
                protocol: item['protocol'] == 'http'
                    ? ChainProxyProtocol.http
                    : ChainProxyProtocol.socks5,
                server: item['server'] as String? ?? '127.0.0.1',
                port: item['exit_port'] as int? ?? 31813,
                username: item['exit_auth'] == false ? '' : 'synthetic-exit',
                password: item['exit_auth'] == false
                    ? ''
                    : item['password'] as String? ?? 'synthetic-exit-pass',
              );
        final result = applyChainProxyConfig(
          source,
          chain,
          mode,
          globalTarget: 'Synthetic Node',
        );
        if (chain != null && mode != Mode.direct) {
          final wrapper = (result['proxies'] as List).cast<Map>().last;
          expect(wrapper['dialer-proxy'], 'Synthetic Node');
          expect(wrapper['name'], chainProxyRuntimeName);
        }
        await File(
          '${output.path}/${item['name']}.json',
        ).writeAsString(jsonEncode(result));
      }
      await File('${output.path}/cases.json').writeAsString(jsonEncode(cases));
      await File('${output.path}/generation.json').writeAsString(
        jsonEncode({
          'generator':
              'package:fl_clash/common/chain_proxy.dart::applyChainProxyConfig',
          'production_callsite': 'lib/common/task.dart',
          'synthetic_credentials_only': true,
          'case_count': cases.length,
          'modes': ['rule', 'global', 'direct'],
        }),
      );
    },
  );
}

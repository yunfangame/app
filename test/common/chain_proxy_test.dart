import 'dart:convert';
import 'dart:io';

import 'package:fl_clash/common/chain_proxy.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const proxy = ChainProxyConfig(
    name: 'Taiwan exit',
    server: 'proxy.example',
    port: 1080,
    username: 'user',
    password: 'secret',
  );

  test('chain proxy config persists and names are unique ignoring case', () {
    const settings = AppSettingProps(
      chainProxies: [proxy],
      activeChainProxyName: 'Taiwan exit',
    );
    final restored = AppSettingProps.fromJson(
      jsonDecode(jsonEncode(settings)) as Map<String, Object?>,
    );

    expect(restored.chainProxies, [proxy]);
    expect(activeChainProxy(restored), proxy);
    expect(
      hasDuplicateChainProxyName(restored.chainProxies, ' taiwan EXIT '),
      isTrue,
    );
  });

  test('rule mode wraps proxy policies and preserves direct traffic', () {
    final result = applyChainProxyConfig(
      {
        'proxies': [
          {'name': 'Node A', 'type': 'ss'},
        ],
        'proxy-providers': {
          'remote': {'url': 'https://provider.example/sub.yaml'},
        },
        'rules': [
          'DOMAIN,local.example,DIRECT',
          'DOMAIN,overseas.example,Select',
          'MATCH,Select',
        ],
      },
      proxy,
      Mode.rule,
      bypassDomains: const ['subscription.example'],
    );

    final proxies = result['proxies'] as List;
    final wrapper = proxies.cast<Map>().firstWhere(
      (item) => item['name'] == chainProxyRuntimeName,
    );
    expect(wrapper['type'], 'socks5');
    expect(wrapper['dialer-proxy'], 'Select');
    expect(wrapper['username'], 'user');
    expect(result['rules'], [
      'DOMAIN,subscription.example,Select',
      'DOMAIN,provider.example,Select',
      'DOMAIN,local.example,DIRECT',
      'DOMAIN,overseas.example,$chainProxyRuntimeName',
      'MATCH,$chainProxyRuntimeName',
    ]);
  });

  test('global mode adds one wrapper around the previous global target', () {
    final result = applyChainProxyConfig(
      {'proxies': <Object>[]},
      proxy,
      Mode.global,
      globalTarget: 'Node A',
    );

    expect(result['proxies'], [
      {
        'name': chainProxyRuntimeName,
        'type': 'socks5',
        'server': 'proxy.example',
        'port': 1080,
        'username': 'user',
        'password': 'secret',
        'udp': true,
        'dialer-proxy': 'Node A',
      },
    ]);
  });

  test('canonical chain wrapper follows MATCH instead of the first policy', () {
    final source = <String, dynamic>{
      'proxies': <Object>[],
      'rules': [
        'DOMAIN,first.example,First policy',
        'DOMAIN,second.example,Second policy',
        'DOMAIN,local.example,DIRECT',
        'MATCH,Default policy',
      ],
    };
    final original = jsonEncode(source);
    final result = applyChainProxyConfig(source, proxy, Mode.rule);
    final wrappers = (result['proxies'] as List).cast<Map>();

    expect(
      wrappers.singleWhere(
        (item) => item['name'] == chainProxyRuntimeName,
      )['dialer-proxy'],
      'Default policy',
    );
    expect(result['rules'], [
      'DOMAIN,first.example,$chainProxyRuntimeName 2',
      'DOMAIN,second.example,$chainProxyRuntimeName 3',
      'DOMAIN,local.example,DIRECT',
      'MATCH,$chainProxyRuntimeName',
    ]);
    expect(jsonEncode(source), original);
  });

  test(
    'MATCH parsing trims targets and preserves trailing rule parameters',
    () {
      final result = applyChainProxyConfig(
        {
          'rules': [
            'IP-CIDR,203.0.113.0/24, Earlier policy , NO-RESOLVE ',
            'SRC-IP-CIDR,198.51.100.0/24, Main policy , src ',
            ' mAtCh , Main policy ',
          ],
        },
        proxy,
        Mode.rule,
      );
      final wrappers = (result['proxies'] as List).cast<Map>();

      expect(wrappers, hasLength(2));
      expect(
        wrappers.singleWhere(
          (item) => item['name'] == chainProxyRuntimeName,
        )['dialer-proxy'],
        'Main policy',
      );
      expect(result['rules'], [
        'IP-CIDR,203.0.113.0/24,$chainProxyRuntimeName 2, NO-RESOLVE ',
        'SRC-IP-CIDR,198.51.100.0/24,$chainProxyRuntimeName, src ',
        ' mAtCh ,$chainProxyRuntimeName',
      ]);
    },
  );

  test('the first MATCH defines the canonical wrapper and provider bypass', () {
    final result = applyChainProxyConfig(
      {
        'rules': [
          'DOMAIN,specific.example,Specific policy',
          'MATCH,Effective default',
          'MATCH,Unreachable default',
        ],
      },
      proxy,
      Mode.rule,
      bypassDomains: const ['subscription.example'],
    );
    final wrappers = (result['proxies'] as List).cast<Map>();

    expect(
      wrappers.singleWhere(
        (item) => item['name'] == chainProxyRuntimeName,
      )['dialer-proxy'],
      'Effective default',
    );
    expect(result['rules'], [
      'DOMAIN,subscription.example,Effective default',
      'DOMAIN,specific.example,$chainProxyRuntimeName 2',
      'MATCH,$chainProxyRuntimeName',
      'MATCH,$chainProxyRuntimeName 3',
    ]);
  });

  test(
    'without MATCH the first proxy policy retains the canonical wrapper',
    () {
      final result = applyChainProxyConfig(
        {
          'rules': [
            'DOMAIN,local.example,DIRECT',
            'DOMAIN,first.example,First policy',
            'DOMAIN,second.example,Second policy',
          ],
        },
        proxy,
        Mode.rule,
        bypassDomains: const ['subscription.example'],
      );
      final wrappers = (result['proxies'] as List).cast<Map>();

      expect(
        wrappers.singleWhere(
          (item) => item['name'] == chainProxyRuntimeName,
        )['dialer-proxy'],
        'First policy',
      );
      expect(result['rules'], [
        'DOMAIN,subscription.example,DIRECT',
        'DOMAIN,local.example,DIRECT',
        'DOMAIN,first.example,$chainProxyRuntimeName',
        'DOMAIN,second.example,$chainProxyRuntimeName 2',
      ]);
    },
  );

  test('direct and rejecting MATCH targets are never chained', () {
    for (final target in ['DIRECT', 'PASS', 'DNS', 'REJECT', 'REJECT-DROP']) {
      final result = applyChainProxyConfig(
        {
          'rules': ['DOMAIN,specific.example,Specific policy', 'MATCH,$target'],
        },
        proxy,
        Mode.rule,
      );
      final wrappers = (result['proxies'] as List).cast<Map>();

      expect(wrappers, hasLength(1));
      expect(wrappers.single['dialer-proxy'], 'Specific policy');
      expect(result['rules'], [
        'DOMAIN,specific.example,$chainProxyRuntimeName',
        'MATCH,$target',
      ]);
      final entirelyDirect = applyChainProxyConfig(
        {
          'rules': ['MATCH,$target'],
        },
        proxy,
        Mode.rule,
      );
      expect(entirelyDirect['proxies'], isEmpty);
      expect(entirelyDirect['rules'], ['MATCH,$target']);
    }
  });

  test('disabled chain and direct mode preserve the source configuration', () {
    final source = <String, dynamic>{
      'proxies': <Object>[],
      'rules': ['MATCH,Default policy'],
    };

    expect(applyChainProxyConfig(source, null, Mode.rule), source);
    expect(applyChainProxyConfig(source, proxy, Mode.direct), source);
  });

  test('global mode never creates a chain wrapper around itself', () {
    for (final target in [chainProxyRuntimeName, '$chainProxyRuntimeName 2']) {
      final source = {'proxies': <Object>[]};
      expect(
        applyChainProxyConfig(source, proxy, Mode.global, globalTarget: target),
        source,
      );
    }
  });

  test('validation reports a detected alternate protocol', () async {
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final subscription = server.listen((socket) {
      socket.first.then((bytes) {
        if (bytes.isNotEmpty && bytes.first == 5) {
          socket.destroy();
          return;
        }
        socket.write(
          'HTTP/1.1 200 Connection Established\r\n\r\n'
          'HTTP/1.1 204 No Content\r\nConnection: close\r\n\r\n',
        );
        socket.close();
      });
    });
    addTearDown(() async {
      await subscription.cancel();
      await server.close();
    });

    final result = await validateChainProxy(
      ChainProxyConfig(
        name: 'HTTP only',
        server: InternetAddress.loopbackIPv4.address,
        port: server.port,
      ),
      timeout: const Duration(seconds: 1),
    );

    expect(result.status, ChainProxyValidationStatus.wrongProtocol);
    expect(result.detectedProtocol, ChainProxyProtocol.http);
  });
}

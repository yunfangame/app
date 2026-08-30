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

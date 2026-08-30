import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';

const chainProxyRuntimeName = '蜂窝链式代理';

enum ChainProxyValidationStatus { available, wrongProtocol, unavailable }

class ChainProxyValidationResult {
  const ChainProxyValidationResult(this.status, {this.detectedProtocol});

  final ChainProxyValidationStatus status;
  final ChainProxyProtocol? detectedProtocol;

  bool get isAvailable => status == ChainProxyValidationStatus.available;
}

typedef ChainProxyValidator =
    Future<ChainProxyValidationResult> Function(ChainProxyConfig config);

ChainProxyConfig? activeChainProxy(AppSettingProps settings) {
  final activeName = settings.activeChainProxyName;
  if (activeName == null) return null;
  for (final proxy in settings.chainProxies) {
    if (proxy.name == activeName) return proxy;
  }
  return null;
}

bool hasDuplicateChainProxyName(
  Iterable<ChainProxyConfig> proxies,
  String name, {
  String? excludingName,
}) {
  final normalized = name.trim().toLowerCase();
  return proxies.any(
    (proxy) =>
        proxy.name != excludingName &&
        proxy.name.trim().toLowerCase() == normalized,
  );
}

Map<String, dynamic> applyChainProxyConfig(
  Map<String, dynamic> source,
  ChainProxyConfig? chainProxy,
  Mode mode, {
  String? globalTarget,
  List<String> bypassDomains = const [],
}) {
  final config = Map<String, dynamic>.from(source);
  if (chainProxy == null || mode == Mode.direct) return config;
  final proxies = List<dynamic>.from(config['proxies'] as List? ?? const []);
  final rules = List<String>.from(config['rules'] as List? ?? const []);
  if (mode == Mode.global) {
    final target = globalTarget?.trim();
    if (target == null || target.isEmpty || target == chainProxyRuntimeName) {
      return config;
    }
    proxies.add(_proxyMap(chainProxy, chainProxyRuntimeName, target));
    config['proxies'] = proxies;
    return config;
  }

  final wrappers = <String, String>{};
  String? fallbackTarget;
  for (final rule in rules.reversed) {
    final parts = rule.split(',');
    if (parts.length >= 2 && parts.first.trim().toUpperCase() == 'MATCH') {
      fallbackTarget = parts[1].trim();
      break;
    }
  }
  final rewrittenRules = rules.map((rule) {
    final parts = rule.split(',');
    if (parts.length < 2 || parts.first.trim().toUpperCase() == 'SUB-RULE') {
      return rule;
    }
    var targetIndex = parts.length - 1;
    while (targetIndex > 0 && _isRuleParameter(parts[targetIndex])) {
      targetIndex--;
    }
    final target = parts[targetIndex].trim();
    if (_isDirectRuleTarget(target)) return rule;
    final wrapperName = wrappers.putIfAbsent(
      target,
      () => wrappers.isEmpty
          ? chainProxyRuntimeName
          : '$chainProxyRuntimeName ${wrappers.length + 1}',
    );
    parts[targetIndex] = wrapperName;
    return parts.join(',');
  }).toList();
  for (final entry in wrappers.entries) {
    proxies.add(_proxyMap(chainProxy, entry.value, entry.key));
  }
  final providerDomains = _providerDomains(config);
  final directRules = {...bypassDomains, ...providerDomains}
      .where((domain) => domain.isNotEmpty)
      .map((domain) => 'DOMAIN,$domain,${fallbackTarget ?? 'DIRECT'}');
  config['proxies'] = proxies;
  config['rules'] = [...directRules, ...rewrittenRules];
  return config;
}

Set<String> _providerDomains(Map<String, dynamic> config) {
  final result = <String>{};
  for (final key in const ['proxy-providers', 'rule-providers']) {
    final providers = config[key];
    if (providers is! Map) continue;
    for (final provider in providers.values) {
      if (provider is! Map) continue;
      final url = provider['url'];
      if (url is! String) continue;
      final host = Uri.tryParse(url)?.host;
      if (host?.isNotEmpty == true) result.add(host!);
    }
  }
  return result;
}

bool _isRuleParameter(String value) {
  final normalized = value.trim().toLowerCase();
  return normalized == 'src' || normalized == 'no-resolve';
}

bool _isDirectRuleTarget(String value) {
  final normalized = value.trim().toUpperCase();
  return normalized == 'DIRECT' ||
      normalized == 'PASS' ||
      normalized == 'DNS' ||
      normalized.startsWith('REJECT');
}

Map<String, dynamic> _proxyMap(
  ChainProxyConfig proxy,
  String name,
  String dialerProxy,
) {
  return <String, dynamic>{
    'name': name,
    'type': proxy.protocol.name,
    'server': proxy.server,
    'port': proxy.port,
    if (proxy.username.isNotEmpty) 'username': proxy.username,
    if (proxy.password.isNotEmpty) 'password': proxy.password,
    if (proxy.protocol == ChainProxyProtocol.socks5) 'udp': true,
    'dialer-proxy': dialerProxy,
  };
}

Future<ChainProxyValidationResult> validateChainProxy(
  ChainProxyConfig config, {
  Duration timeout = const Duration(seconds: 10),
}) async {
  final selectedWorks = await _validateProtocol(config, timeout);
  if (selectedWorks) {
    return const ChainProxyValidationResult(
      ChainProxyValidationStatus.available,
    );
  }
  final alternate = config.protocol == ChainProxyProtocol.socks5
      ? ChainProxyProtocol.http
      : ChainProxyProtocol.socks5;
  final alternateWorks = await _validateProtocol(
    config.copyWith(protocol: alternate),
    timeout,
  );
  if (alternateWorks) {
    return ChainProxyValidationResult(
      ChainProxyValidationStatus.wrongProtocol,
      detectedProtocol: alternate,
    );
  }
  return const ChainProxyValidationResult(
    ChainProxyValidationStatus.unavailable,
  );
}

Future<bool> _validateProtocol(
  ChainProxyConfig config,
  Duration timeout,
) async {
  try {
    return await _validateConnection(config).timeout(timeout);
  } catch (_) {
    return false;
  }
}

Future<bool> _validateConnection(ChainProxyConfig config) async {
  final socket = await Socket.connect(
    config.server,
    config.port,
    timeout: const Duration(seconds: 5),
  );
  final reader = _SocketReader(socket);
  try {
    if (config.protocol == ChainProxyProtocol.socks5) {
      final connected = await _openSocksTunnel(socket, reader, config);
      if (!connected) return false;
    } else {
      final authorization = config.username.isEmpty
          ? ''
          : 'Proxy-Authorization: Basic '
                '${base64Encode(utf8.encode('${config.username}:${config.password}'))}\r\n';
      socket.write(
        'CONNECT www.cloudflare.com:80 HTTP/1.1\r\n'
        'Host: www.cloudflare.com\r\n'
        '$authorization'
        'Proxy-Connection: keep-alive\r\n\r\n',
      );
      await socket.flush();
      if (await _readHttpStatus(reader) != 200) return false;
    }
    socket.write(
      'GET /cdn-cgi/trace HTTP/1.1\r\n'
      'Host: www.cloudflare.com\r\n'
      'Accept: */*\r\n'
      'Connection: close\r\n\r\n',
    );
    await socket.flush();
    final status = await _readHttpStatus(reader);
    return status != null && status >= 200 && status < 400;
  } finally {
    await reader.cancel();
    await socket.close();
  }
}

Future<int?> _readHttpStatus(_SocketReader reader) async {
  final header = ascii.decode(await reader.readUntil(const [13, 10, 13, 10]));
  final statusMatch = RegExp(r'^HTTP/\d(?:\.\d)?\s+(\d{3})').firstMatch(header);
  return int.tryParse(statusMatch?.group(1) ?? '');
}

Future<bool> _openSocksTunnel(
  Socket socket,
  _SocketReader reader,
  ChainProxyConfig config,
) async {
  final hasCredentials = config.username.isNotEmpty;
  socket.add(hasCredentials ? const [5, 2, 0, 2] : const [5, 1, 0]);
  await socket.flush();
  final selection = await reader.readExact(2);
  if (selection[0] != 5 || selection[1] == 0xff) return false;
  if (selection[1] == 2) {
    final username = utf8.encode(config.username);
    final password = utf8.encode(config.password);
    if (username.isEmpty || username.length > 255 || password.length > 255) {
      return false;
    }
    socket.add([1, username.length, ...username, password.length, ...password]);
    await socket.flush();
    final authentication = await reader.readExact(2);
    if (authentication[1] != 0) return false;
  } else if (selection[1] != 0) {
    return false;
  }
  final host = ascii.encode('www.cloudflare.com');
  socket.add([5, 1, 0, 3, host.length, ...host, 0, 80]);
  await socket.flush();
  final response = await reader.readExact(4);
  if (response[0] != 5 || response[1] != 0) return false;
  final addressLength = switch (response[3]) {
    1 => 4,
    3 => (await reader.readExact(1)).first,
    4 => 16,
    _ => -1,
  };
  if (addressLength < 0) return false;
  await reader.readExact(addressLength + 2);
  return true;
}

class _SocketReader {
  _SocketReader(Socket socket) : _iterator = StreamIterator(socket);

  final StreamIterator<Uint8List> _iterator;
  final List<int> _pending = [];

  Future<List<int>> readExact(int length) async {
    while (_pending.length < length) {
      if (!await _iterator.moveNext()) {
        throw const SocketException('Proxy closed the connection');
      }
      _pending.addAll(_iterator.current);
    }
    final result = _pending.sublist(0, length);
    _pending.removeRange(0, length);
    return result;
  }

  Future<List<int>> readUntil(List<int> marker) async {
    while (true) {
      final index = _indexOf(_pending, marker);
      if (index >= 0) {
        final length = index + marker.length;
        final result = _pending.sublist(0, length);
        _pending.removeRange(0, length);
        return result;
      }
      if (_pending.length > 32768 || !await _iterator.moveNext()) {
        throw const SocketException('Invalid proxy response');
      }
      _pending.addAll(_iterator.current);
    }
  }

  Future<void> cancel() => _iterator.cancel();
}

int _indexOf(List<int> source, List<int> pattern) {
  if (source.length < pattern.length) return -1;
  for (var index = 0; index <= source.length - pattern.length; index++) {
    var matches = true;
    for (var offset = 0; offset < pattern.length; offset++) {
      if (source[index + offset] != pattern[offset]) {
        matches = false;
        break;
      }
    }
    if (matches) return index;
  }
  return -1;
}

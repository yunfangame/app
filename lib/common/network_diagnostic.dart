import 'dart:async';
import 'dart:io';

import 'package:fl_clash/common/app_localizations.dart';
import 'package:proxy/proxy.dart';

typedef NetworkDiagnosticPortProbe = Future<bool> Function(int port);
typedef NetworkDiagnosticInternetProbe = Future<bool> Function(int port);
typedef NetworkDiagnosticDnsProbe = Future<bool> Function(String host);
typedef NetworkDiagnosticProxyInspector =
    Future<ProxyOperationResult> Function(int expectedPort);

class NetworkDiagnosticInput {
  const NetworkDiagnosticInput({
    required this.hasProfile,
    required this.running,
    required this.systemProxyRequested,
    required this.tunRequested,
    required this.port,
  });

  final bool hasProfile;
  final bool running;
  final bool systemProxyRequested;
  final bool tunRequested;
  final int port;
}

class NetworkDiagnosticStep {
  const NetworkDiagnosticStep({
    required this.name,
    required this.success,
    required this.detail,
  });

  final String name;
  final bool success;
  final String detail;

  Map<String, Object?> toDiagnosticFields() => {
    'name': name,
    'success': success,
    'detail': detail,
  };
}

class NetworkDiagnosticReport {
  const NetworkDiagnosticReport({
    required this.code,
    required this.summary,
    required this.steps,
    this.proxyResult,
  });

  final String code;
  final String summary;
  final List<NetworkDiagnosticStep> steps;
  final ProxyOperationResult? proxyResult;

  bool get success => code == 'W-NET-OK';

  String get displayText {
    final buffer = StringBuffer('$code：$summary');
    for (final step in steps) {
      buffer
        ..writeln()
        ..write('${step.success ? '✓' : '✗'} ${step.name}：${step.detail}');
    }
    return buffer.toString();
  }

  Map<String, Object?> toDiagnosticFields() => {
    'diagnostic_code': code,
    'success': success,
    'summary': summary,
    'steps': steps.map((step) => step.toDiagnosticFields()).toList(),
    if (proxyResult != null) 'system_proxy': proxyResult!.toDiagnosticFields(),
  };
}

class NetworkDiagnosticService {
  NetworkDiagnosticService({
    NetworkDiagnosticPortProbe? portProbe,
    NetworkDiagnosticInternetProbe? internetProbe,
    NetworkDiagnosticDnsProbe? dnsProbe,
    NetworkDiagnosticProxyInspector? proxyInspector,
    List<String> configHosts = const [
      'house.zryc.tech',
      'zryc.oss-cn-beijing.aliyuncs.com',
    ],
  }) : _portProbe = portProbe ?? _probeLocalPort,
       _internetProbe = internetProbe ?? _probeViaLocalProxy,
       _dnsProbe = dnsProbe ?? _probeDns,
       _proxyInspector = proxyInspector,
       _configHosts = List.unmodifiable(configHosts);

  final NetworkDiagnosticPortProbe _portProbe;
  final NetworkDiagnosticInternetProbe _internetProbe;
  final NetworkDiagnosticDnsProbe _dnsProbe;
  final NetworkDiagnosticProxyInspector? _proxyInspector;
  final List<String> _configHosts;

  Future<NetworkDiagnosticReport> run(NetworkDiagnosticInput input) async {
    final l10n = currentAppLocalizations;
    final steps = <NetworkDiagnosticStep>[];
    if (!input.hasProfile) {
      return NetworkDiagnosticReport(
        code: 'W-PROFILE-01',
        summary: l10n.networkDiagnosticNoProfile,
        steps: const [],
      );
    }

    final dnsResults = await Future.wait(
      _configHosts.map((host) async => (host, await _dnsProbe(host))),
    );
    final reachableConfigCount = dnsResults.where((item) => item.$2).length;
    steps.add(
      NetworkDiagnosticStep(
        name: l10n.networkDiagnosticConfigDomains,
        success: reachableConfigCount > 0,
        detail: l10n.networkDiagnosticConfigDomainsResult(
          reachableConfigCount,
          dnsResults.length,
        ),
      ),
    );

    if (!input.running) {
      return NetworkDiagnosticReport(
        code: 'W-CORE-01',
        summary: l10n.networkDiagnosticCoreNotRunning,
        steps: List.unmodifiable(steps),
      );
    }

    final portAvailable = await _portProbe(input.port);
    steps.add(
      NetworkDiagnosticStep(
        name: l10n.networkDiagnosticLocalProxyPort,
        success: portAvailable,
        detail: portAvailable
            ? l10n.networkDiagnosticPortListening('127.0.0.1:${input.port}')
            : l10n.networkDiagnosticPortUnavailable('127.0.0.1:${input.port}'),
      ),
    );
    if (!portAvailable) {
      return NetworkDiagnosticReport(
        code: 'W-PORT-02',
        summary: l10n.networkDiagnosticPortNotListening,
        steps: List.unmodifiable(steps),
      );
    }

    ProxyOperationResult? proxyResult;
    if (input.systemProxyRequested && _proxyInspector != null) {
      proxyResult = await _proxyInspector(input.port);
      steps.add(
        NetworkDiagnosticStep(
          name: l10n.networkDiagnosticWindowsSystemProxy,
          success: proxyResult.success,
          detail: proxyResult.success
              ? l10n.networkDiagnosticProxyVerified('127.0.0.1:${input.port}')
              : l10n.networkDiagnosticProxyFailure(
                  proxyResult.diagnosticCode,
                  proxyResult.stage,
                  proxyResult.errorCode == null
                      ? ''
                      : ' / Win32 ${proxyResult.errorCode}',
                ),
        ),
      );
    }

    final internetAvailable = await _internetProbe(input.port);
    steps.add(
      NetworkDiagnosticStep(
        name: l10n.networkDiagnosticNodeInternet,
        success: internetAvailable,
        detail: internetAvailable
            ? l10n.networkDiagnosticInternetSuccess
            : l10n.networkDiagnosticInternetFailed,
      ),
    );
    if (proxyResult != null && !proxyResult.success) {
      return NetworkDiagnosticReport(
        code: proxyResult.diagnosticCode,
        summary: l10n.networkDiagnosticSystemProxyInvalid,
        steps: List.unmodifiable(steps),
        proxyResult: proxyResult,
      );
    }
    if (!internetAvailable) {
      return NetworkDiagnosticReport(
        code: 'W-NODE-05',
        summary: l10n.networkDiagnosticNodeUnavailable,
        steps: List.unmodifiable(steps),
        proxyResult: proxyResult,
      );
    }

    if (!input.systemProxyRequested && !input.tunRequested) {
      return NetworkDiagnosticReport(
        code: 'W-ROUTE-08',
        summary: l10n.networkDiagnosticTrafficEntryMissing,
        steps: List.unmodifiable(steps),
        proxyResult: proxyResult,
      );
    }

    if (reachableConfigCount == 0) {
      return NetworkDiagnosticReport(
        code: 'W-DNS-01',
        summary: l10n.networkDiagnosticConfigDnsFailed,
        steps: List.unmodifiable(steps),
        proxyResult: proxyResult,
      );
    }

    return NetworkDiagnosticReport(
      code: 'W-NET-OK',
      summary: l10n.networkDiagnosticSuccess,
      steps: List.unmodifiable(steps),
      proxyResult: proxyResult,
    );
  }

  static Future<bool> _probeLocalPort(int port) async {
    Socket? socket;
    try {
      socket = await Socket.connect(
        InternetAddress.loopbackIPv4,
        port,
        timeout: const Duration(seconds: 2),
      );
      return true;
    } catch (_) {
      return false;
    } finally {
      socket?.destroy();
    }
  }

  static Future<bool> _probeDns(String host) async {
    try {
      final addresses = await InternetAddress.lookup(
        host,
      ).timeout(const Duration(seconds: 3));
      return addresses.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> _probeViaLocalProxy(int port) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 4)
      ..findProxy = (_) => 'PROXY 127.0.0.1:$port';
    try {
      for (final uri in const [
        'https://cp.cloudflare.com/generate_204',
        'https://www.gstatic.com/generate_204',
        'http://www.msftconnecttest.com/connecttest.txt',
      ].map(Uri.parse)) {
        try {
          final request = await client
              .getUrl(uri)
              .timeout(const Duration(seconds: 5));
          request.followRedirects = false;
          final response = await request.close().timeout(
            const Duration(seconds: 5),
          );
          await response.drain<void>();
          if (response.statusCode >= 200 && response.statusCode < 400) {
            return true;
          }
        } catch (_) {}
      }
      return false;
    } finally {
      client.close(force: true);
    }
  }
}

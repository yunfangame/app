import 'package:fl_clash/common/network_diagnostic.dart';
import 'package:fl_clash/l10n/l10n.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:proxy/proxy.dart';

void main() {
  setUpAll(() => AppLocalizations.load(const Locale('en')));

  NetworkDiagnosticService service({
    bool portAvailable = true,
    bool internetAvailable = true,
    bool dnsAvailable = true,
    ProxyOperationResult? proxyResult,
  }) {
    return NetworkDiagnosticService(
      dnsProbe: (_) async => dnsAvailable,
      portProbe: (_) async => portAvailable,
      internetProbe: (_) async => internetAvailable,
      proxyInspector: proxyResult == null ? null : (_) async => proxyResult,
    );
  }

  const base = NetworkDiagnosticInput(
    hasProfile: true,
    running: true,
    systemProxyRequested: true,
    tunRequested: false,
    port: 7890,
  );

  test('reports a missing profile before probing the runtime', () async {
    final report = await service().run(
      const NetworkDiagnosticInput(
        hasProfile: false,
        running: false,
        systemProxyRequested: false,
        tunRequested: false,
        port: 7890,
      ),
    );

    expect(report.code, 'W-PROFILE-01');
  });

  test('distinguishes an unavailable local mixed port', () async {
    final report = await service(portAvailable: false).run(base);

    expect(report.code, 'W-PORT-02');
  });

  test('reports a Windows proxy readback mismatch', () async {
    final report = await service(
      proxyResult: const ProxyOperationResult(
        success: false,
        operation: 'inspect',
        stage: 'readback_mismatch',
        enabled: false,
        server: '127.0.0.1:7890',
      ),
    ).run(base);

    expect(report.code, 'W-PROXY-04');
    expect(report.steps.last.success, isTrue);
  });

  for (final internetAvailable in [true, false]) {
    test(
      'TUN cannot hide a proxy failure (internet=$internetAvailable)',
      () async {
        final report =
            await service(
              internetAvailable: internetAvailable,
              proxyResult: const ProxyOperationResult(
                success: false,
                operation: 'inspect',
                stage: 'readback_mismatch',
                enabled: false,
              ),
            ).run(
              const NetworkDiagnosticInput(
                hasProfile: true,
                running: true,
                systemProxyRequested: true,
                tunRequested: true,
                port: 7890,
              ),
            );
        expect(report.code, 'W-PROXY-04');
        expect(report.success, isFalse);
        expect(report.steps.last.success, internetAvailable);
      },
    );
  }

  test('does not report overall success when config DNS fails', () async {
    final report = await service(dnsAvailable: false).run(base);
    expect(report.code, 'W-DNS-01');
    expect(report.success, isFalse);
  });

  test('distinguishes a node that cannot reach the internet', () async {
    final report = await service(internetAvailable: false).run(
      const NetworkDiagnosticInput(
        hasProfile: true,
        running: true,
        systemProxyRequested: false,
        tunRequested: true,
        port: 7890,
      ),
    );

    expect(report.code, 'W-NODE-05');
  });

  test('reports a missing traffic entry path', () async {
    final report = await service().run(
      const NetworkDiagnosticInput(
        hasProfile: true,
        running: true,
        systemProxyRequested: false,
        tunRequested: false,
        port: 7890,
      ),
    );

    expect(report.code, 'W-ROUTE-08');
  });

  test('reports success after port, proxy and internet verification', () async {
    final report = await service(
      proxyResult: const ProxyOperationResult(
        success: true,
        operation: 'inspect',
        stage: 'verified',
        enabled: true,
        server: '127.0.0.1:7890',
      ),
    ).run(base);

    expect(report.code, 'W-NET-OK');
    expect(report.success, isTrue);
    expect(report.summary, contains('not verified'));
  });
}

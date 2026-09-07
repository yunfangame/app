import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:fl_clash/common/network_diagnostic.dart';
import 'package:fl_clash/l10n/l10n.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:proxy/proxy.dart';

class _MockHttpClient extends Mock implements HttpClient {}

class _MockHttpClientRequest extends Mock implements HttpClientRequest {}

class _MockHttpClientResponse extends Mock implements HttpClientResponse {}

void main() {
  setUpAll(() async {
    registerFallbackValue(Uri.https('www.youtube.com', '/'));
    await AppLocalizations.load(const Locale('en'));
  });

  NetworkDiagnosticService service({
    bool portAvailable = true,
    bool internetAvailable = true,
    bool dnsAvailable = true,
    ProxyOperationResult? proxyResult,
    NetworkDiagnosticYouTubeProbe? youtubeProbe,
  }) {
    return NetworkDiagnosticService(
      dnsProbe: (_) async => dnsAvailable,
      portProbe: (_) async => portAvailable,
      internetProbe: (_) async => internetAvailable,
      proxyInspector: proxyResult == null ? null : (_) async => proxyResult,
      youtubeProbe:
          youtubeProbe ??
          (_) async => const NetworkDiagnosticHttpResult(
            statusCode: 200,
            elapsedMilliseconds: 386,
          ),
    );
  }

  const base = NetworkDiagnosticInput(
    hasProfile: true,
    running: true,
    systemProxyRequested: true,
    tunRequested: false,
    port: 7890,
    selectedNode: 'Singapore Selected Node',
    selectedGroup: 'My Proxy Group',
    mode: 'rule',
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
    expect(report.steps.last.name, 'YouTube HTTPS');
    expect(report.steps.last.detail, contains('386 ms'));
    expect(report.steps.last.latencyMs, 386);
    expect(report.steps.last.httpStatus, 200);
    expect(report.selectedNode, base.selectedNode);
    expect(report.selectedGroup, base.selectedGroup);
    expect(report.mode, 'rule');
    expect(report.displayText, contains(base.selectedNode!));
    expect(report.displayText, contains(base.selectedGroup!));
    final exported = jsonEncode(report.toDiagnosticFields());
    expect(exported, isNot(contains(base.selectedNode!)));
    expect(exported, isNot(contains(base.selectedGroup!)));
    expect(exported, contains('selected_node_ref'));
    expect(exported, contains('latency_ms'));
  });

  test(
    'runs YouTube exactly once after successful basic probes using the mixed port',
    () async {
      final calls = <String>[];
      final report = await NetworkDiagnosticService(
        configHosts: const ['example.test'],
        dnsProbe: (_) async {
          calls.add('dns');
          return true;
        },
        portProbe: (_) async {
          calls.add('port');
          return true;
        },
        internetProbe: (_) async {
          calls.add('internet');
          return true;
        },
        youtubeProbe: (port) async {
          calls.add('youtube:$port');
          return const NetworkDiagnosticHttpResult(
            statusCode: 200,
            elapsedMilliseconds: 1234,
          );
        },
      ).run(base);
      expect(calls, ['dns', 'port', 'internet', 'youtube:7890']);
      expect(report.success, isTrue);
      expect(report.displayText, contains('1234 ms'));
    },
  );

  test('does not run YouTube when any basic prerequisite fails', () async {
    var youtubeCalls = 0;
    Future<NetworkDiagnosticHttpResult> youtubeProbe(int port) async {
      youtubeCalls++;
      return const NetworkDiagnosticHttpResult(
        statusCode: 200,
        elapsedMilliseconds: 12,
      );
    }

    for (final diagnostic in [
      service(portAvailable: false, youtubeProbe: youtubeProbe),
      service(internetAvailable: false, youtubeProbe: youtubeProbe),
      service(dnsAvailable: false, youtubeProbe: youtubeProbe),
      service(
        proxyResult: const ProxyOperationResult(
          success: false,
          operation: 'inspect',
          stage: 'readback_mismatch',
        ),
        youtubeProbe: youtubeProbe,
      ),
    ]) {
      final report = await diagnostic.run(base);
      expect(report.success, isFalse);
      expect(report.selectedNode, base.selectedNode);
    }
    await service(youtubeProbe: youtubeProbe).run(
      const NetworkDiagnosticInput(
        hasProfile: false,
        running: false,
        systemProxyRequested: false,
        tunRequested: false,
        port: 7890,
      ),
    );
    await service(youtubeProbe: youtubeProbe).run(
      const NetworkDiagnosticInput(
        hasProfile: true,
        running: false,
        systemProxyRequested: true,
        tunRequested: false,
        port: 7890,
      ),
    );
    await service(youtubeProbe: youtubeProbe).run(
      const NetworkDiagnosticInput(
        hasProfile: true,
        running: true,
        systemProxyRequested: false,
        tunRequested: false,
        port: 7890,
      ),
    );
    expect(youtubeCalls, 0);
  });

  for (final failure in NetworkDiagnosticHttpFailure.values) {
    test('YouTube $failure does not report overall network success', () async {
      final report = await service(
        youtubeProbe: (_) async => NetworkDiagnosticHttpResult(
          failure: failure,
          statusCode: failure == NetworkDiagnosticHttpFailure.http ? 403 : null,
        ),
      ).run(base);
      expect(report.code, 'W-YOUTUBE-01');
      expect(report.success, isFalse);
      expect(report.steps.last.success, isFalse);
      expect(report.steps.last.failure, failure.name);
      expect(report.steps.last.detail, isNot(contains(' ms')));
    });
  }

  test(
    'unexpected YouTube probe errors retain completed basic checks',
    () async {
      final report = await service(
        youtubeProbe: (_) async =>
            throw const SocketException('private endpoint'),
      ).run(base);
      expect(report.code, 'W-YOUTUBE-01');
      expect(report.steps.last.failure, 'network');
      expect(report.displayText, isNot(contains('private endpoint')));
      expect(report.steps.where((step) => step.success), isNotEmpty);
    },
  );

  group('YouTube HTTPS transport', () {
    late _MockHttpClient client;
    late _MockHttpClientRequest request;
    late _MockHttpClientResponse response;
    late String Function(Uri)? route;

    setUp(() {
      client = _MockHttpClient();
      request = _MockHttpClientRequest();
      response = _MockHttpClientResponse();
      route = null;
      when(() => client.findProxy = any()).thenAnswer((invocation) {
        route = invocation.positionalArguments.single as String Function(Uri)?;
        return route;
      });
      when(() => client.getUrl(any())).thenAnswer((_) async => request);
      when(() => request.close()).thenAnswer((_) async => response);
      when(() => response.statusCode).thenReturn(200);
    });

    test(
      'uses explicit local proxy, HTTPS GET and unmodified elapsed milliseconds',
      () async {
        final result = await NetworkDiagnosticYouTubeChecker(
          clientFactory: () => client,
        ).call(17890);
        expect(result.success, isTrue);
        expect(result.elapsedMilliseconds, greaterThanOrEqualTo(0));
        expect(
          route!(Uri.https('www.youtube.com', '/')),
          'PROXY 127.0.0.1:17890',
        );
        verify(
          () => client.getUrl(Uri.https('www.youtube.com', '/')),
        ).called(1);
        verify(() => request.followRedirects = false).called(1);
        verify(() => client.close(force: true)).called(1);
        verifyNever(() => client.badCertificateCallback = any());
      },
    );

    for (final status in [200, 204, 302, 403, 429, 500]) {
      test(
        'classifies HTTP $status without following a redirect or ignoring an error',
        () async {
          when(() => response.statusCode).thenReturn(status);
          final result = await NetworkDiagnosticYouTubeChecker(
            clientFactory: () => client,
          ).call(7890);
          expect(result.success, status >= 200 && status < 300);
          expect(result.statusCode, status);
          expect(
            result.failure,
            status < 300 ? null : NetworkDiagnosticHttpFailure.http,
          );
          verify(() => client.close(force: true)).called(1);
        },
      );
    }

    for (final entry in <(Object, NetworkDiagnosticHttpFailure)>[
      (
        TimeoutException('private timeout details'),
        NetworkDiagnosticHttpFailure.timeout,
      ),
      (
        const HandshakeException('private certificate details'),
        NetworkDiagnosticHttpFailure.tls,
      ),
      (
        const SocketException('private address'),
        NetworkDiagnosticHttpFailure.network,
      ),
    ]) {
      test('classifies ${entry.$2} safely and closes the client', () async {
        when(() => request.close()).thenThrow(entry.$1);
        final result = await NetworkDiagnosticYouTubeChecker(
          clientFactory: () => client,
        ).call(7890);
        expect(result.success, isFalse);
        expect(result.failure, entry.$2);
        expect(result.displayText, isNot(contains('private')));
        expect(result.elapsedMilliseconds, isNull);
        verify(() => client.close(force: true)).called(1);
      });
    }

    test('bounds response-header wait and closes a hung connection', () async {
      final pending = Completer<HttpClientResponse>();
      when(() => request.close()).thenAnswer((_) => pending.future);
      final result = await NetworkDiagnosticYouTubeChecker(
        clientFactory: () => client,
        timeout: const Duration(milliseconds: 10),
      ).call(7890);
      expect(result.failure, NetworkDiagnosticHttpFailure.timeout);
      verify(() => client.close(force: true)).called(1);
      pending.complete(response);
      await Future<void>.delayed(Duration.zero);
    });

    test('bounds connection setup and absorbs a late socket failure', () async {
      final pending = Completer<HttpClientRequest>();
      when(() => client.getUrl(any())).thenAnswer((_) => pending.future);
      final result = await NetworkDiagnosticYouTubeChecker(
        clientFactory: () => client,
        timeout: const Duration(milliseconds: 10),
      ).call(7890);
      expect(result.failure, NetworkDiagnosticHttpFailure.timeout);
      verify(() => client.close(force: true)).called(1);
      verifyNever(() => request.close());
      pending.completeError(const SocketException('late socket failure'));
      await Future<void>.delayed(Duration.zero);
      expect(result.failure, NetworkDiagnosticHttpFailure.timeout);
    });
  });
}

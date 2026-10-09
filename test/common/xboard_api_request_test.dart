import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:fl_clash/common/api_health.dart';
import 'package:fl_clash/common/api_request_router.dart';
import 'package:fl_clash/common/xboard_api_request.dart';
import 'package:fl_clash/common/xboard_auth.dart';
import 'package:fl_clash/common/xboard_marquee.dart';
import 'package:fl_clash/common/xboard_tickets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final primary = Uri.parse('https://primary.example:8443/base');
  final backup = Uri.parse('https://backup.example');
  final candidates = [primary, backup];

  test('replaces only the trusted origin and retains path and query', () async {
    final calls = <Uri>[];
    final executor = XboardApiRequestExecutor(
      apiHealthService: _VerifiedHealth(candidates),
      router: ApiRequestRouter(),
    );
    final source = primary.replace(
      path: '/api/v1/user/ticket-sync/detail',
      queryParameters: {'id': '17', 'search': 'two words'},
    );
    final result = await executor.run(
      endpoint: source,
      allowRetry: true,
      request: (endpoint, _) async {
        calls.add(endpoint);
        if (endpoint.host == primary.host) {
          throw const SocketException('Failed host lookup');
        }
        return 'ready';
      },
    );
    expect(result, 'ready');
    expect(calls.map((uri) => uri.host), [primary.host, backup.host]);
    expect(calls.last.port, 443);
    expect(calls.last.path, source.path);
    expect(calls.last.query, source.query);
  });

  test(
    'unconfigured session host never receives an authenticated request',
    () async {
      final calls = <Uri>[];
      final health = _VerifiedHealth([backup]);
      final executor = XboardApiRequestExecutor(apiHealthService: health);
      await executor.run(
        endpoint: Uri.parse(
          'https://untrusted.example/api/v1/user/ticket-sync/summary',
        ),
        allowRetry: true,
        request: (endpoint, _) async => calls.add(endpoint),
      );
      expect(calls.single.host, backup.host);
      expect(health.verifiedLoads, 1);
    },
  );

  test('verified candidate failure cannot trust the caller endpoint', () async {
    var calls = 0;
    final executor = XboardApiRequestExecutor(
      apiHealthService: _VerifiedHealth(
        [],
        failure: const FormatException('signature'),
      ),
    );
    await expectLater(
      executor.run<void>(
        endpoint: primary,
        allowRetry: true,
        request: (_, _) async => calls++,
      ),
      throwsFormatException,
    );
    expect(calls, 0);
  });

  for (final hosts in [
    <Uri>[],
    [Uri.parse('http://primary.example')],
    [Uri.parse('https://user:secret@primary.example')],
  ]) {
    test(
      'empty or unsafe trusted candidates fail before dispatch: $hosts',
      () async {
        var calls = 0;
        final executor = XboardApiRequestExecutor(
          apiHealthService: _VerifiedHealth(hosts),
        );
        await expectLater(
          executor.run<void>(
            endpoint: primary,
            allowRetry: true,
            request: (_, _) async => calls++,
          ),
          throwsFormatException,
        );
        expect(calls, 0);
      },
    );
  }

  test('business rejection does not try another origin', () async {
    var calls = 0;
    final executor = XboardApiRequestExecutor(
      apiHealthService: _VerifiedHealth(candidates),
    );
    await expectLater(
      executor.run<void>(
        endpoint: primary,
        allowRetry: true,
        request: (_, _) async {
          calls++;
          throw const FormatException('business rejection');
        },
      ),
      throwsFormatException,
    );
    expect(calls, 1);
  });

  for (final oldOutcome in ['success', 'unauthorized', 'network_failure']) {
    test(
      'old ordinary request $oldOutcome cannot clear a newer recovery probe',
      () async {
        var now = DateTime(2026, 10, 7);
        final router = ApiRequestRouter(now: () => now);
        final executor = XboardApiRequestExecutor(
          apiHealthService: _VerifiedHealth([primary]),
          router: router,
        );
        final oldResponse = Completer<String>();
        final oldStarted = Completer<void>();
        final oldOperation = executor.run(
          endpoint: primary,
          allowRetry: false,
          request: (_, _) {
            oldStarted.complete();
            return oldResponse.future;
          },
        );
        final oldAssertion = oldOutcome == 'success'
            ? expectLater(oldOperation, completion('old'))
            : expectLater(oldOperation, throwsA(isA<Exception>()));
        await oldStarted.future;
        expect(
          router.recoveryProbeToken(primary, candidates: [primary]),
          isNull,
        );
        router.recordFailure(
          primary,
          candidates: [primary],
          error: const SocketException('Failed host lookup'),
          probeToken: null,
        );
        now = now.add(const Duration(seconds: 16));
        final probeResponse = Completer<String>();
        final probeStarted = Completer<void>();
        final probeOperation = executor.run(
          endpoint: primary,
          allowRetry: false,
          request: (_, _) {
            probeStarted.complete();
            return probeResponse.future;
          },
        );
        await probeStarted.future;
        final probeToken = router.recoveryProbeToken(
          primary,
          candidates: [primary],
        );
        expect(probeToken, isNotNull);
        if (oldOutcome == 'success') {
          oldResponse.complete('old');
        } else if (oldOutcome == 'unauthorized') {
          final options = RequestOptions(path: primary.toString());
          oldResponse.completeError(
            DioException.badResponse(
              statusCode: 403,
              requestOptions: options,
              response: Response(requestOptions: options, statusCode: 403),
            ),
          );
        } else {
          oldResponse.completeError(
            const SocketException('Failed host lookup'),
          );
        }
        await oldAssertion;
        expect(
          router.recoveryProbeToken(primary, candidates: [primary]),
          same(probeToken),
        );
        expect(
          router.orderCandidates([primary], reserveRecoveryProbe: true),
          isEmpty,
        );
        probeResponse.complete('recovered');
        expect(await probeOperation, 'recovered');
        expect(
          router.recoveryProbeToken(primary, candidates: [primary]),
          isNull,
        );
        expect(router.orderCandidates([primary], reserveRecoveryProbe: true), [
          primary,
        ]);
      },
    );
  }

  for (final status in [403, 429]) {
    test(
      'terminal $status releases only the probe owned by its attempt',
      () async {
        var now = DateTime(2026, 10, 7);
        final router = ApiRequestRouter(now: () => now);
        router.recordFailure(
          primary,
          candidates: [primary],
          error: const SocketException('Failed host lookup'),
          probeToken: null,
        );
        now = now.add(const Duration(seconds: 16));
        Object? requestProbe;
        var calls = 0;
        final executor = XboardApiRequestExecutor(
          apiHealthService: _VerifiedHealth([primary]),
          router: router,
        );
        await expectLater(
          executor.run<void>(
            endpoint: primary,
            allowRetry: true,
            request: (uri, _) async {
              calls++;
              requestProbe = router.recoveryProbeToken(
                primary,
                candidates: [primary],
              );
              final options = RequestOptions(path: uri.toString());
              throw DioException.badResponse(
                statusCode: status,
                requestOptions: options,
                response: Response(requestOptions: options, statusCode: status),
              );
            },
          ),
          throwsA(isA<DioException>()),
        );
        expect(calls, 1);
        expect(requestProbe, isNotNull);
        expect(
          router.recoveryProbeToken(primary, candidates: [primary]),
          isNull,
        );
        expect(router.orderCandidates([primary], reserveRecoveryProbe: true), [
          primary,
        ]);
      },
    );
  }

  test('ticket failure steers marquee to the shared healthy origin', () async {
    final adapter = _RequestAdapter((options, _) async {
      if (options.uri.host == primary.host) {
        return _json(503, {'message': 'unavailable'});
      }
      if (options.uri.path == xboardMarqueeUnreadPath) {
        return _json(200, {
          'status': 1,
          'data': {'items': []},
        });
      }
      return _json(200, {
        'data': {'unread_count': 0},
      });
    });
    final dio = Dio()..httpClientAdapter = adapter;
    final router = ApiRequestRouter();
    final health = _VerifiedHealth(candidates);
    final tickets = XboardTicketApi(
      dio: dio,
      apiHealthService: health,
      router: router,
    );
    final marquee = XboardMarqueeApi(
      dio: dio,
      apiHealthService: health,
      router: router,
    );
    await tickets.request(
      _session(primary),
      'ticket-sync/summary',
      query: {'status': 0, 'page': 2},
    );
    await marquee.fetchUnread(
      endpoint: primary,
      token: 'marquee-token',
      limit: 7,
    );
    expect(adapter.requests.map((request) => request.uri.host), [
      primary.host,
      backup.host,
      backup.host,
    ]);
    expect(adapter.requests[1].uri.path, '/api/v1/user/ticket-sync/summary');
    expect(adapter.requests[1].uri.queryParameters, {
      'status': '0',
      'page': '2',
    });
    expect(adapter.requests[1].headers['Authorization'], 'Bearer account');
    expect(adapter.requests[2].data, {'token': 'marquee-token', 'limit': 7});
    expect(
      adapter.requests.every((request) => !request.followRedirects),
      isTrue,
    );
  });

  test(
    'unread pure POST retries and keeps the token and request body',
    () async {
      final adapter = _RequestAdapter((options, _) async {
        if (options.uri.host == primary.host) return _json(502, {});
        return _json(200, {
          'status': 1,
          'data': {'items': []},
        });
      });
      final api = XboardMarqueeApi(
        dio: Dio()..httpClientAdapter = adapter,
        apiHealthService: _VerifiedHealth(candidates),
        router: ApiRequestRouter(),
      );
      await api.fetchUnread(endpoint: primary, token: 'read-token', limit: 3);
      expect(adapter.requests, hasLength(2));
      for (final request in adapter.requests) {
        expect(request.method, 'POST');
        expect(request.uri.path, xboardMarqueeUnreadPath);
        expect(request.data, {'token': 'read-token', 'limit': 3});
      }
    },
  );

  for (final status in [301, 302, 401, 403, 404, 429, 500]) {
    test('ticket HTTP $status does not retry or follow redirects', () async {
      final adapter = _RequestAdapter(
        (_, _) async =>
            _json(status, {}, location: 'https://evil.example/collect'),
      );
      final api = XboardTicketApi(
        dio: Dio()..httpClientAdapter = adapter,
        apiHealthService: _VerifiedHealth(candidates),
        router: ApiRequestRouter(),
      );
      await expectLater(
        api.request(_session(primary), 'ticket-sync/summary'),
        throwsA(isA<DioException>()),
      );
      expect(adapter.requests, hasLength(1));
      expect(adapter.requests.single.uri.host, primary.host);
      expect(adapter.requests.single.followRedirects, isFalse);
    });
  }

  test('malformed ticket business response cannot switch hosts', () async {
    final adapter = _RequestAdapter(
      (_, _) async => _json(200, {'status': 0, 'data': false}),
    );
    final api = XboardTicketApi(
      dio: Dio()..httpClientAdapter = adapter,
      apiHealthService: _VerifiedHealth(candidates),
      router: ApiRequestRouter(),
    );
    await expectLater(
      api.request(_session(primary), 'ticket-sync/summary'),
      throwsFormatException,
    );
    expect(adapter.requests, hasLength(1));
  });

  for (final path in [
    'ticket-sync/read',
    'ticket-sync/save',
    'ticket-sync/reply',
    'ticket-sync/close',
  ]) {
    test(
      'ticket $path write is one shot even when upstream returns 503',
      () async {
        final adapter = _RequestAdapter((_, _) async => _json(503, {}));
        final api = XboardTicketApi(
          dio: Dio()..httpClientAdapter = adapter,
          apiHealthService: _VerifiedHealth(candidates),
          router: ApiRequestRouter(),
        );
        await expectLater(
          api.request(
            _session(primary),
            path,
            body: {'ticket_id': 17, 'message': 'hello'},
          ),
          throwsA(isA<DioException>()),
        );
        expect(adapter.requests, hasLength(1));
        final request = adapter.requests.single;
        expect(request.method, 'POST');
        expect(Map.fromEntries((request.data as FormData).fields), {
          'ticket_id': '17',
          'message': 'hello',
        });
        expect(request.headers['Authorization'], 'Bearer account');
      },
    );
  }

  testWidgets('write timeout cancels Dio without replaying a ticket write', (
    tester,
  ) async {
    final pending = Completer<ResponseBody>();
    var cancelled = false;
    final adapter = _RequestAdapter((_, cancelFuture) {
      cancelFuture?.then((_) => cancelled = true);
      return pending.future;
    });
    final api = XboardTicketApi(
      dio: Dio()..httpClientAdapter = adapter,
      apiHealthService: _VerifiedHealth(candidates),
      requestTimeout: const Duration(seconds: 2),
      router: ApiRequestRouter(),
    );
    final assertion = expectLater(
      api.request(
        _session(primary),
        'ticket-sync/save',
        body: {'subject': 'help'},
      ),
      throwsA(isA<TimeoutException>()),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));
    await assertion;
    expect(cancelled, isTrue);
    expect(adapter.requests, hasLength(1));
    pending.complete(_json(200, {'data': true}));
    await tester.pump();
    expect(adapter.requests, hasLength(1));
  });

  testWidgets('marquee read timeout remains one shot and cancels Dio', (
    tester,
  ) async {
    final pending = Completer<ResponseBody>();
    var cancelled = false;
    final adapter = _RequestAdapter((_, cancelFuture) {
      cancelFuture?.then((_) => cancelled = true);
      return pending.future;
    });
    final api = XboardMarqueeApi(
      dio: Dio()..httpClientAdapter = adapter,
      apiHealthService: _VerifiedHealth(candidates),
      requestTimeout: const Duration(seconds: 2),
      router: ApiRequestRouter(),
    );
    final assertion = expectLater(
      api.markRead(endpoint: primary, token: 'token', message: _message()),
      throwsA(isA<TimeoutException>()),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));
    await assertion;
    expect(cancelled, isTrue);
    expect(adapter.requests, hasLength(1));
    expect(adapter.requests.single.data, {'token': 'token', 'message_id': 17});
    pending.complete(_json(200, {'status': 1, 'data': true}));
    await tester.pump();
  });

  testWidgets('all four reads share one hard overall deadline', (tester) async {
    final calls = <CancelToken>[];
    final responses = <Completer<String>>[];
    final executor = XboardApiRequestExecutor(
      configLoader: () async => {
        'hosts': List.generate(4, (index) => 'https://api$index.example'),
      },
      requestTimeout: const Duration(seconds: 2),
      operationTimeout: const Duration(seconds: 5),
      router: ApiRequestRouter(),
    );
    final assertion = expectLater(
      executor.run(
        endpoint: Uri.parse(
          'https://api0.example/api/v1/user/ticket-sync/detail?id=1',
        ),
        allowRetry: true,
        request: (_, token) {
          calls.add(token);
          final response = Completer<String>();
          responses.add(response);
          return response.future;
        },
      ),
      throwsA(isA<TimeoutException>()),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));
    await tester.pump(const Duration(seconds: 2));
    expect(calls, hasLength(3));
    await tester.pump(const Duration(seconds: 1));
    await assertion;
    expect(calls.every((token) => token.isCancelled), isTrue);
    for (final response in responses) {
      response.complete('late');
    }
    await tester.pump(const Duration(seconds: 5));
    expect(calls, hasLength(3));
  });

  testWidgets('late configuration cannot dispatch credentials after deadline', (
    tester,
  ) async {
    final pending = Completer<Object?>();
    var calls = 0;
    final executor = XboardApiRequestExecutor(
      configLoader: () => pending.future,
      operationTimeout: const Duration(seconds: 1),
    );
    final assertion = expectLater(
      executor.run<void>(
        endpoint: primary,
        allowRetry: true,
        request: (_, _) async => calls++,
      ),
      throwsA(isA<TimeoutException>()),
    );
    await tester.pump(const Duration(seconds: 1));
    await assertion;
    pending.complete({
      'hosts': [primary.toString()],
    });
    await tester.pump();
    expect(calls, 0);
  });

  testWidgets('late failed-origin success cannot replace the backup health', (
    tester,
  ) async {
    final pending = Completer<String>();
    final router = ApiRequestRouter();
    final executor = XboardApiRequestExecutor(
      apiHealthService: _VerifiedHealth(candidates),
      router: router,
      requestTimeout: const Duration(seconds: 1),
    );
    CancelToken? firstToken;
    final result = executor.run(
      endpoint: primary,
      allowRetry: true,
      request: (uri, token) async {
        if (uri.host == primary.host) {
          firstToken = token;
          return pending.future;
        }
        return 'backup';
      },
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(await result, 'backup');
    expect(firstToken!.isCancelled, isTrue);
    pending.complete('obsolete');
    await tester.pump();
    expect(
      router.orderCandidates(candidates, preferred: primary).first.host,
      backup.host,
    );
  });
}

class _VerifiedHealth extends ApiHealthService {
  _VerifiedHealth(this.candidates, {this.failure});

  final List<Uri> candidates;
  final Object? failure;
  int verifiedLoads = 0;

  @override
  Future<List<Uri>> loadVerifiedCandidateEndpoints() async {
    verifiedLoads++;
    if (failure != null) throw failure!;
    return candidates;
  }

  @override
  Future<Object?> loadConfig({bool forceRefresh = false}) =>
      throw StateError('remote-only path');

  @override
  Future<List<Uri>> loadCandidateEndpoints() =>
      throw StateError('unverified fallback');
}

class _RequestAdapter implements HttpClientAdapter {
  _RequestAdapter(this.respond);

  final Future<ResponseBody> Function(RequestOptions, Future<void>?) respond;
  final List<RequestOptions> requests = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) {
    requests.add(options);
    return respond(options, cancelFuture);
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody _json(int status, Object payload, {String? location}) =>
    ResponseBody.fromString(
      jsonEncode(payload),
      status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
        if (location != null) 'location': [location],
      },
    );

XboardLoginResult _session(Uri endpoint) => XboardLoginResult(
  endpoint: endpoint,
  token: 'token',
  authData: 'Bearer account',
  isAdmin: false,
  subscription: XboardSubscriptionData(
    endpoint: endpoint,
    subscribeUrl: null,
    uploadBytes: 0,
    downloadBytes: 0,
    transferEnableBytes: 100,
    rawData: const {},
  ),
);

XboardMarqueeMessage _message() => const XboardMarqueeMessage(
  id: 17,
  marqueeText: 'text',
  title: 'title',
  detailText: 'detail',
  actionUrl: '',
);

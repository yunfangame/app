import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:fl_clash/common/api_request_router.dart';
import 'package:fl_clash/common/api_endpoint_preference.dart';
import 'package:fl_clash/common/api_health.dart';
import 'package:fl_clash/common/xboard_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final first = Uri.parse('https://one.example.com');
  final second = Uri.parse('https://two.example.com:1443');
  final candidates = [first, second];
  const authData = 'Bearer account-token';

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    ApiRequestRouter.shared.clear();
  });

  final reads = <String, Future<Object?> Function(XboardAuthService)>{
    'nodes': (service) =>
        service.fetchNodes(endpoint: first, authData: authData),
    'plans': (service) =>
        service.fetchPlans(endpoint: first, authData: authData, planId: 8),
    'payment methods': (service) =>
        service.fetchPaymentMethods(endpoint: first, authData: authData),
    'order check': (service) => service.checkOrder(
      endpoint: first,
      authData: authData,
      tradeNo: 'existing-order',
    ),
    'orders': (service) =>
        service.fetchOrders(endpoint: first, authData: authData),
    'order detail': (service) => service.fetchOrderDetail(
      endpoint: first,
      authData: authData,
      tradeNo: 'existing-order',
    ),
    'notices': (service) =>
        service.fetchNotices(endpoint: first, authData: authData),
    'user info': (service) =>
        service.fetchUserInfo(endpoint: first, authData: authData),
    'login IPs': (service) =>
        service.fetchLoginIps(endpoint: first, authData: authData),
    'subscription': (service) =>
        service.fetchSubscription(endpoint: first, authData: authData),
    'traffic logs': (service) =>
        service.fetchTrafficLogs(endpoint: first, authData: authData),
    'invite summary': (service) =>
        service.fetchInviteSummary(endpoint: first, authData: authData),
    'invite details': (service) =>
        service.fetchInviteDetails(endpoint: first, authData: authData),
    'guest config': (service) => service.loadGuestConfig(),
  };

  for (final entry in reads.entries) {
    test(
      '${entry.key} retries only trusted origins and preserves the request',
      () async {
        final requests = <RequestOptions>[];
        final dio = Dio()
          ..interceptors.add(
            InterceptorsWrapper(
              onRequest: (options, handler) {
                requests.add(options);
                handler.resolve(
                  Response<Object?>(
                    requestOptions: options,
                    statusCode: options.uri.host == first.host ? 503 : 401,
                    data: const {'message': 'unavailable'},
                  ),
                );
              },
            ),
          );
        final service = XboardAuthService(
          dio: dio,
          endpointLoader: () async => candidates,
          diagnosticRecorder: (_, _) {},
        );
        await expectLater(
          entry.value(service),
          throwsA(isA<XboardAuthException>()),
        );
        expect(requests.map((request) => request.uri.host), [
          first.host,
          second.host,
        ]);
        expect(requests.last.uri.port, second.port);
        expect(requests.last.uri.path, requests.first.uri.path);
        expect(requests.last.uri.query, requests.first.uri.query);
        expect(requests.last.method, requests.first.method);
        expect(requests.last.followRedirects, isFalse);
        if (entry.key != 'guest config') {
          expect(requests.last.headers['Authorization'], authData);
        }
      },
    );
  }

  final writes = <String, Future<Object?> Function(XboardAuthService)>{
    'create order': (service) => service.createOrder(
      endpoint: first,
      authData: authData,
      planId: 8,
      period: 'month_price',
    ),
    'checkout': (service) => service.checkoutOrder(
      endpoint: first,
      authData: authData,
      tradeNo: 'existing-order',
      methodId: 1,
    ),
    'cancel': (service) => service.cancelOrder(
      endpoint: first,
      authData: authData,
      tradeNo: 'existing-order',
    ),
    'block IP': (service) => service.blockLoginIp(
      endpoint: first,
      authData: authData,
      ip: '192.0.2.1',
    ),
    'unblock IP': (service) => service.unblockLoginIp(
      endpoint: first,
      authData: authData,
      ip: '192.0.2.1',
    ),
    'invite save': (service) =>
        service.generateInviteCode(endpoint: first, authData: authData),
    'commission transfer': (service) => service.transferCommission(
      endpoint: first,
      authData: authData,
      amount: 100,
    ),
    'ticket': (service) => service.createTicket(
      endpoint: first,
      authData: authData,
      subject: 'question',
      level: 1,
      message: 'help',
    ),
    'preferences': (service) => service.updateUserPreferences(
      endpoint: first,
      authData: authData,
      remindExpire: true,
      remindTraffic: true,
    ),
    'change password': (service) => service.changePassword(
      endpoint: first,
      authData: authData,
      oldPassword: 'old',
      newPassword: 'new',
    ),
    'reset security': (service) =>
        service.resetSecurity(endpoint: first, authData: authData),
    'register': (service) => service.register(
      email: 'user@example.com',
      password: 'secret',
      emailCode: 'code',
    ),
    'reset password': (service) => service.resetPassword(
      email: 'user@example.com',
      password: 'secret',
      emailCode: 'code',
    ),
    'email verify': (service) =>
        service.sendEmailVerification(email: 'user@example.com'),
    'login': (service) =>
        service.login(email: 'user@example.com', password: 'secret'),
  };

  for (final entry in writes.entries) {
    test(
      '${entry.key} does not replay a lost response and cools the entry for the next service',
      () async {
        final requests = <RequestOptions>[];
        final dio = Dio()
          ..interceptors.add(
            InterceptorsWrapper(
              onRequest: (options, handler) {
                requests.add(options);
                handler.reject(
                  DioException(
                    requestOptions: options,
                    type: DioExceptionType.receiveTimeout,
                  ),
                );
              },
            ),
          );
        final service = XboardAuthService(
          dio: dio,
          endpointLoader: () async => candidates,
          diagnosticRecorder: (_, _) {},
        );
        await expectLater(entry.value(service), throwsA(anything));
        expect(requests, hasLength(1));
        expect(requests.single.uri.host, first.host);
        final after = XboardAuthService(
          endpointLoader: () async => candidates,
          plansRequester: (endpoint, token) async {
            expect(endpoint.host, second.host);
            expect(token, authData);
            return const XboardLoginResponse(
              statusCode: 200,
              data: {'data': []},
            );
          },
        );
        expect(
          await after.fetchPlans(endpoint: first, authData: authData),
          isEmpty,
        );
      },
    );
  }

  for (final status in [302, 400, 401, 403, 404, 422, 429, 500]) {
    test(
      'HTTP $status stops without sending credentials to another entry',
      () async {
        final calls = <Uri>[];
        final service = XboardAuthService(
          endpointLoader: () async => candidates,
          plansRequester: (endpoint, token) async {
            calls.add(endpoint);
            return XboardLoginResponse(
              statusCode: status,
              data: const {'message': 'rejected'},
            );
          },
        );
        await expectLater(
          service.fetchPlans(endpoint: first, authData: authData),
          throwsA(isA<XboardAuthException>()),
        );
        expect(calls, hasLength(1));
        expect(
          ApiRequestRouter.shared.orderCandidates(candidates).first,
          first,
        );
      },
    );
  }

  test('a write initially selects the healthy entry', () async {
    ApiRequestRouter.shared.recordFailure(
      first,
      candidates: candidates,
      error: TimeoutException('timeout'),
    );
    var count = 0;
    final service = XboardAuthService(
      endpointLoader: () async => candidates,
      orderSaveRequester: (endpoint, token, plan, period) async {
        count++;
        expect(endpoint.host, second.host);
        return const XboardLoginResponse(
          statusCode: 200,
          data: {'data': 'new-order'},
        );
      },
    );
    expect(
      await service.createOrder(
        endpoint: first,
        authData: authData,
        planId: 8,
        period: 'month_price',
      ),
      'new-order',
    );
    expect(count, 1);
  });

  test('a removed saved host is excluded when restoring an account', () async {
    final calls = <Uri>[];
    final service = XboardAuthService(
      endpointLoader: () async => candidates,
      subscriptionRequester: (endpoint, token) async {
        calls.add(endpoint);
        return const XboardLoginResponse(
          statusCode: 200,
          data: {
            'data': {'u': 0, 'd': 0, 'transfer_enable': 100},
          },
        );
      },
    );
    final session = await service.restoreSession(
      preferredEndpoint: Uri.parse('https://removed.example.com'),
      token: 'token',
      authData: authData,
    );
    expect(calls.single.host, first.host);
    expect(session.endpoint.host, first.host);
  });

  test('HTTPS credentials cannot fall back to HTTP', () async {
    var requests = 0;
    final service = XboardAuthService(
      endpointLoader: () async => [Uri.parse('http://two.example.com')],
      plansRequester: (_, _) async {
        requests++;
        return const XboardLoginResponse(statusCode: 200, data: {'data': []});
      },
    );
    await expectLater(
      service.fetchPlans(endpoint: first, authData: authData),
      throwsA(isA<XboardAuthException>()),
    );
    expect(requests, 0);
  });

  for (final error in [
    const FormatException('Invalid config signature'),
    null,
  ]) {
    test(
      'unverified or empty candidates never promote the caller origin',
      () async {
        var requests = 0;
        final service = XboardAuthService(
          endpointLoader: () async {
            if (error != null) throw error;
            return const [];
          },
          plansRequester: (_, _) async {
            requests++;
            return const XboardLoginResponse(
              statusCode: 200,
              data: {'data': []},
            );
          },
        );
        await expectLater(
          service.fetchPlans(endpoint: first, authData: authData),
          throwsA(anything),
        );
        expect(requests, 0);
      },
    );
  }

  test(
    'one request timeout can safely fall back within the remaining read budget',
    () async {
      final calls = <Uri>[];
      final service = XboardAuthService(
        apiRequestTimeout: const Duration(milliseconds: 30),
        apiOperationTimeout: const Duration(milliseconds: 120),
        endpointLoader: () async => candidates,
        plansRequester: (endpoint, _) async {
          calls.add(endpoint);
          if (endpoint.host == first.host) {
            return Completer<XboardLoginResponse>().future;
          }
          return const XboardLoginResponse(statusCode: 200, data: {'data': []});
        },
        diagnosticRecorder: (_, _) {},
      );
      expect(
        await service.fetchPlans(endpoint: first, authData: authData),
        isEmpty,
      );
      expect(calls.map((endpoint) => endpoint.host), [first.host, second.host]);
    },
  );

  test(
    'total budget stops fallback and ignores late success persistence',
    () async {
      final waiting = <Completer<XboardLoginResponse>>[];
      final service = XboardAuthService(
        apiRequestTimeout: const Duration(milliseconds: 40),
        apiOperationTimeout: const Duration(milliseconds: 70),
        endpointLoader: () async => [
          ...candidates,
          Uri.parse('https://three.example.com'),
        ],
        plansRequester: (_, _) {
          final response = Completer<XboardLoginResponse>();
          waiting.add(response);
          return response.future;
        },
        diagnosticRecorder: (_, _) {},
      );
      final stopwatch = Stopwatch()..start();
      await expectLater(
        service.fetchPlans(endpoint: first, authData: authData),
        throwsA(isA<TimeoutException>()),
      );
      expect(stopwatch.elapsed, lessThan(const Duration(seconds: 1)));
      expect(waiting.length, inInclusiveRange(1, 2));
      for (final response in waiting) {
        response.complete(
          const XboardLoginResponse(statusCode: 200, data: {'data': []}),
        );
      }
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(await ApiEndpointPreferenceStore().load(), isNull);
    },
  );

  test(
    'optional endpoint persistence cannot hold a successful API result',
    () async {
      final health = _PendingPreferenceHealth([first]);
      final service = XboardAuthService(
        apiHealthService: health,
        apiOperationTimeout: const Duration(milliseconds: 60),
        plansRequester: (_, _) async =>
            const XboardLoginResponse(statusCode: 200, data: {'data': []}),
      );
      expect(
        await service
            .fetchPlans(endpoint: first, authData: authData)
            .timeout(const Duration(milliseconds: 200)),
        isEmpty,
      );
      expect(health.saveCalls, 1);
      health.saved.complete();
    },
  );

  test('hard deadline cancels the actual Dio adapter request', () async {
    final adapter = _PendingRoutingAdapter();
    final dio = Dio()..httpClientAdapter = adapter;
    final service = XboardAuthService(
      dio: dio,
      apiRequestTimeout: const Duration(milliseconds: 35),
      apiOperationTimeout: const Duration(milliseconds: 35),
      endpointLoader: () async => [first],
      diagnosticRecorder: (_, _) {},
    );
    await expectLater(
      service.fetchPlans(endpoint: first, authData: authData),
      throwsA(isA<TimeoutException>()),
    );
    await adapter.cancelled.future.timeout(const Duration(seconds: 1));
    expect(adapter.requests, 1);
    adapter.response.complete(ResponseBody.fromString('{"data":[]}', 200));
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(await ApiEndpointPreferenceStore().load(), isNull);
    dio.close(force: true);
  });

  test('all notice pages share one operation budget', () async {
    var calls = 0;
    final service = XboardAuthService(
      apiRequestTimeout: const Duration(milliseconds: 120),
      apiOperationTimeout: const Duration(milliseconds: 160),
      endpointLoader: () async => [first],
      noticesRequester: (endpoint, _) async {
        calls++;
        await Future<void>.delayed(const Duration(milliseconds: 100));
        return XboardLoginResponse(
          statusCode: 200,
          data: {
            'data': [
              {'id': calls, 'title': 'notice', 'content': 'text'},
            ],
            'total': 5,
          },
        );
      },
      diagnosticRecorder: (_, _) {},
    );
    final stopwatch = Stopwatch()..start();
    await expectLater(
      service.fetchNotices(endpoint: first, authData: authData),
      throwsA(isA<TimeoutException>()),
    );
    expect(calls, inInclusiveRange(1, 2));
    expect(stopwatch.elapsed, lessThan(const Duration(seconds: 1)));
    await Future<void>.delayed(const Duration(milliseconds: 120));
    expect(calls, inInclusiveRange(1, 2));
  });

  test('later notice candidate loads share the remaining budget', () async {
    var loads = 0;
    var calls = 0;
    final waiting = Completer<List<Uri>>();
    final service = XboardAuthService(
      apiOperationTimeout: const Duration(milliseconds: 240),
      endpointLoader: () {
        loads++;
        return loads == 1 ? Future.value([first]) : waiting.future;
      },
      noticesRequester: (_, _) async {
        calls++;
        await Future<void>.delayed(const Duration(milliseconds: 160));
        return const XboardLoginResponse(
          statusCode: 200,
          data: {
            'data': [
              {'id': 1, 'title': 'notice', 'content': 'text'},
            ],
            'total': 2,
          },
        );
      },
      diagnosticRecorder: (_, _) {},
    );
    final stopwatch = Stopwatch()..start();
    await expectLater(
      service.fetchNotices(endpoint: first, authData: authData),
      throwsA(isA<TimeoutException>()),
    );
    expect(stopwatch.elapsed, lessThan(const Duration(milliseconds: 360)));
    expect(loads, 2);
    expect(calls, 1);
    waiting.complete([first]);
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(calls, 1);
  });

  test('legacy login and subscription validation share one budget', () async {
    var loginCalls = 0;
    var subscriptionCalls = 0;
    final service = XboardAuthService(
      apiRequestTimeout: const Duration(milliseconds: 120),
      apiOperationTimeout: const Duration(milliseconds: 160),
      endpointLoader: () async => candidates,
      loginRequester: (_, _, _) async {
        loginCalls++;
        await Future<void>.delayed(const Duration(milliseconds: 100));
        return const XboardLoginResponse(
          statusCode: 200,
          data: {
            'data': {'token': 'token', 'auth_data': authData},
          },
        );
      },
      subscriptionRequester: (_, _) {
        subscriptionCalls++;
        return Completer<XboardLoginResponse>().future;
      },
      diagnosticRecorder: (_, _) {},
    );
    final stopwatch = Stopwatch()..start();
    await expectLater(
      service.login(email: 'user@example.com', password: 'secret'),
      throwsA(
        isA<XboardAuthException>().having(
          (error) => error.failure,
          'failure',
          XboardAuthFailure.subscriptionUnavailable,
        ),
      ),
    );
    expect(loginCalls, 1);
    expect(subscriptionCalls, 1);
    expect(service.currentSession, isNull);
    expect(stopwatch.elapsed, lessThan(const Duration(seconds: 1)));
  });

  test(
    'continuous response bytes cannot bypass the operation deadline',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final timers = <Timer>[];
      server.listen((request) {
        request.response.headers.contentType = ContentType.json;
        request.response.write('{"data":[');
        unawaited(request.response.done.catchError((Object _) {}));
        timers.add(
          Timer.periodic(const Duration(milliseconds: 2), (_) {
            request.response.write(' ');
            unawaited(request.response.flush().catchError((Object _) {}));
          }),
        );
      });
      final endpoint = Uri.parse('http://127.0.0.1:${server.port}');
      final dio = Dio(
        BaseOptions(receiveTimeout: const Duration(milliseconds: 500)),
      );
      dio.httpClientAdapter = IOHttpClientAdapter(
        createHttpClient: () =>
            _RealRoutingHttpOverrides().createHttpClient(null),
      );
      try {
        final service = XboardAuthService(
          dio: dio,
          apiRequestTimeout: const Duration(milliseconds: 70),
          apiOperationTimeout: const Duration(milliseconds: 70),
          endpointLoader: () async => [endpoint],
          diagnosticRecorder: (_, _) {},
        );
        final stopwatch = Stopwatch()..start();
        await expectLater(
          service.fetchPlans(endpoint: endpoint, authData: authData),
          throwsA(isA<TimeoutException>()),
        );
        expect(stopwatch.elapsed, lessThan(const Duration(seconds: 1)));
      } finally {
        for (final timer in timers) {
          timer.cancel();
        }
        dio.close(force: true);
        await server.close(force: true);
      }
    },
  );
}

class _PendingRoutingAdapter implements HttpClientAdapter {
  final cancelled = Completer<void>();
  final response = Completer<ResponseBody>();
  int requests = 0;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? stream,
    Future<void>? cancelFuture,
  ) {
    requests++;
    if (cancelFuture != null) {
      unawaited(
        cancelFuture.then((_) {
          if (!cancelled.isCompleted) cancelled.complete();
        }),
      );
    }
    return response.future;
  }

  @override
  void close({bool force = false}) {}
}

class _RealRoutingHttpOverrides extends HttpOverrides {}

class _PendingPreferenceHealth extends ApiHealthService {
  _PendingPreferenceHealth(this.candidates);

  final List<Uri> candidates;
  final saved = Completer<void>();
  int saveCalls = 0;

  @override
  Future<List<Uri>> loadVerifiedCandidateEndpoints() async => candidates;

  @override
  Future<void> rememberSuccessfulEndpoint(Uri endpoint) {
    saveCalls++;
    return saved.future;
  }
}

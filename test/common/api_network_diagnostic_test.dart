import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:fl_clash/common/api_health.dart';
import 'package:fl_clash/common/api_network_diagnostic.dart';
import 'package:fl_clash/common/xboard_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  for (final entry in {
    10013: ApiNetworkFailure.permissionDenied,
    10060: ApiNetworkFailure.timeout,
    10061: ApiNetworkFailure.connectionRefused,
    10054: ApiNetworkFailure.connectionReset,
    11001: ApiNetworkFailure.dns,
    11002: ApiNetworkFailure.dns,
    13: ApiNetworkFailure.permissionDenied,
    111: ApiNetworkFailure.connectionRefused,
    54: ApiNetworkFailure.connectionReset,
  }.entries) {
    test('retains socket reason and OS code ${entry.key}', () {
      final diagnostic = classifyApiNetworkFailure(
        _dioError(
          _dioError(
            SocketException(
              'Sensitive host api.private.example',
              osError: OSError('Sensitive details', entry.key),
            ),
          ),
        ),
        stage: 'login',
      );
      expect(diagnostic.failure, entry.value);
      expect(diagnostic.osErrorCode, entry.key);
    });
  }

  test('classifies TLS and timeout without exposing raw exceptions', () {
    final tls = classifyApiNetworkFailure(
      _dioError(const HandshakeException('private certificate subject')),
      stage: 'remote_config',
    );
    expect(tls.failure, ApiNetworkFailure.tls);
    expect(
      classifyApiNetworkFailure(
        _dioError(TimeoutException('private host')),
        stage: 'login',
      ).failure,
      ApiNetworkFailure.timeout,
    );
    expect(
      classifyApiNetworkFailure(
        DioException(
          requestOptions: RequestOptions(),
          type: DioExceptionType.receiveTimeout,
        ),
        stage: 'login',
      ).failure,
      ApiNetworkFailure.timeout,
    );
    expect(jsonEncode(tls.toDiagnosticFields()), isNot(contains('private')));
  });

  test('recognizes DNS messages without a portable OS code', () {
    expect(
      classifyApiNetworkFailure(
        _dioError(const SocketException("Failed host lookup: 'private.test'")),
        stage: 'api_probe',
      ).failure,
      ApiNetworkFailure.dns,
    );
  });

  test(
    'HTTP status takes precedence and safe fields contain no request data',
    () {
      final request = RequestOptions(
        path: 'https://private.example/login?token=secret-token',
        data: {'email': 'customer@example.com', 'password': 'secret-password'},
        headers: {'Authorization': 'Bearer secret-auth'},
      );
      final diagnostic = classifyApiNetworkFailure(
        DioException(
          requestOptions: request,
          response: Response(
            requestOptions: request,
            statusCode: 403,
            data: '<html>secret-response</html>',
          ),
        ),
        stage: 'login',
        endpoint: Uri.parse(
          'https://username:password@private.example/p?token=xx',
        ),
        elapsedMilliseconds: 17,
        attemptId: 'test_1',
      );
      expect(diagnostic.failure, ApiNetworkFailure.http);
      expect(diagnostic.statusCode, 403);
      expect(diagnostic.endpointRef, matches(RegExp(r'^[a-f0-9]{12}$')));
      expect(diagnostic.toDiagnosticFields()['elapsed_ms'], 17);
      final serialized = jsonEncode(diagnostic.toDiagnosticFields());
      for (final forbidden in [
        'secret',
        'private.example',
        'username',
        'password',
        'customer@example.com',
        'Bearer',
      ]) {
        expect(serialized, isNot(contains(forbidden)));
      }
    },
  );

  test('config diagnostics retain TLS evidence and attempt metadata', () async {
    final events = <Map<String, Object?>>[];
    final service = ApiHealthService(
      configUrl: 'https://private.example/config?key=secret-config',
      configRetryDelays: const [Duration.zero],
      configLoader: (_) async =>
          throw _dioError(const HandshakeException('private-subject')),
      diagnosticRecorder: (event, fields) =>
          events.add({'event': event, ...fields}),
    );
    final snapshot = await service.check();
    expect(snapshot.diagnostic?.failure, ApiNetworkFailure.tls);
    expect(snapshot.diagnostic?.attemptId, isNotEmpty);
    expect(snapshot.diagnostic?.elapsedMilliseconds, isNonNegative);
    expect(events.single['event'], 'api.config.attempt.failed');
    expect(jsonEncode(events), isNot(contains('private')));
    expect(jsonEncode(events), isNot(contains('secret')));
  });

  test('API probe records timeout instead of an unclassified false', () async {
    final service = ApiHealthService(
      endpointProbe: (_) => Completer<bool>().future,
      probeTimeout: const Duration(milliseconds: 1),
      diagnosticRecorder: (_, _) {},
    );
    final result = await service.probeEndpoint(Uri.parse('https://api.test'));
    expect(result.reachable, isFalse);
    expect(result.diagnostic?.failure, ApiNetworkFailure.timeout);
    expect(result.diagnostic?.stage, 'api_probe');
  });

  test(
    'API probe records wrapped permission failure without AV attribution',
    () async {
      final service = ApiHealthService(
        endpointProbe: (_) async => throw _dioError(
          const SocketException('blocked', osError: OSError('blocked', 10013)),
        ),
        diagnosticRecorder: (_, _) {},
      );
      final result = await service.probeEndpoint(Uri.parse('https://api.test'));
      expect(result.diagnostic?.failure, ApiNetworkFailure.permissionDenied);
      expect(result.diagnostic?.osErrorCode, 10013);
      expect(
        result.diagnostic?.toDiagnosticFields().keys,
        isNot(contains('antivirus')),
      );
    },
  );

  for (final status in [401, 403, 407, 502]) {
    test('HTML HTTP $status is not reported as a bad password', () async {
      final service = XboardAuthService(
        endpointLoader: () async => [Uri.parse('https://api.example.com')],
        loginRequester: (_, _, _) async => XboardLoginResponse(
          statusCode: status,
          data: '<html>Access denied by gateway</html>',
        ),
        diagnosticRecorder: (_, _) {},
      );
      await expectLater(
        service.login(email: 'customer@example.com', password: 'secret'),
        throwsA(
          isA<XboardAuthException>()
              .having(
                (error) => error.failure,
                'failure',
                XboardAuthFailure.unavailable,
              )
              .having(
                (error) => error.diagnostic?.failure,
                'reason',
                ApiNetworkFailure.http,
              )
              .having(
                (error) => error.diagnostic?.statusCode,
                'status',
                status,
              ),
        ),
      );
    });
  }

  test('login network fallback succeeds with safe attempt logs', () async {
    final events = <Map<String, Object?>>[];
    var requests = 0;
    final service = XboardAuthService(
      endpointLoader: () async => [
        Uri.parse('https://first.example.com'),
        Uri.parse('https://second.example.com'),
      ],
      loginRequester: (_, _, _) async {
        requests++;
        if (requests == 1) {
          throw _dioError(
            const SocketException(
              'customer@example.com secret-password private.example',
              osError: OSError('secret-error', 10054),
            ),
          );
        }
        return const XboardLoginResponse(
          statusCode: 200,
          data: {
            'data': {
              'token': 'secret-token',
              'auth_data': 'Bearer secret-auth',
            },
          },
        );
      },
      subscriptionRequester: (_, _) async => const XboardLoginResponse(
        statusCode: 200,
        data: {
          'data': {
            'subscribe_url': 'https://private.example/subscribe?token=secret',
          },
        },
      ),
      diagnosticRecorder: (event, fields) =>
          events.add({'event': event, ...fields}),
    );
    await service.login(
      email: 'customer@example.com',
      password: 'secret-password',
    );
    expect(requests, 2);
    expect(events.map((event) => event['event']), [
      'auth.api.attempt.failed',
      'auth.api.attempt.succeeded',
    ]);
    expect(events.first['reason'], 'connection_reset');
    expect(events.first['os_error_code'], 10054);
    expect(events.first['attempt_id'], isNot(events.last['attempt_id']));
    final serialized = jsonEncode(events);
    for (final forbidden in ['secret', 'customer', 'example.com', 'Bearer']) {
      expect(serialized, isNot(contains(forbidden)));
    }
  });

  test(
    'diagnostic recorder failure never changes the network result',
    () async {
      final service = ApiHealthService(
        endpointProbe: (_) async => true,
        diagnosticRecorder: (_, _) => throw StateError('storage unavailable'),
      );
      expect(
        (await service.probeEndpoint(Uri.parse('https://api.test'))).reachable,
        isTrue,
      );
    },
  );
}

DioException _dioError(Object error) => DioException(
  requestOptions: RequestOptions(path: 'https://private.example?token=secret'),
  type: DioExceptionType.connectionError,
  error: error,
);

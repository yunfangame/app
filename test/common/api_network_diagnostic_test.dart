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

  test('retains nested BoringSSL issuer reason without raw TLS details', () {
    final diagnostic = classifyApiNetworkFailure(
      _dioError(
        _dioError(
          const HandshakeException(
            'Handshake error in client for private.example '
            'customer@example.com secret-password',
            OSError(
              'CERTIFICATE_VERIFY_FAILED: unable to get local issuer '
              'certificate(handshake.cc:297) subject=private-certificate',
              -1,
            ),
          ),
        ),
      ),
      stage: 'login',
    );
    expect(diagnostic.failure, ApiNetworkFailure.tls);
    expect(diagnostic.osErrorCode, -1);
    expect(diagnostic.tlsFailure, ApiTlsFailure.missingIssuer);
    expect(diagnostic.toDiagnosticFields(), {
      'reason': 'tls',
      'stage': 'login',
      'tls_reason': 'missing_issuer',
      'os_error_code': -1,
    });
    final serialized = jsonEncode(diagnostic.toDiagnosticFields());
    for (final forbidden in [
      'private',
      'customer',
      'example.com',
      'secret',
      'CERTIFICATE_VERIFY_FAILED',
      'handshake.cc',
      'subject=',
    ]) {
      expect(serialized, isNot(contains(forbidden)));
    }
  });

  for (final entry in {
    'unable to get issuer certificate': 'missing_issuer',
    'unable to verify the first certificate': 'missing_issuer',
    'CERTIFICATE_VERIFY_FAILED: certificate has expired': 'expired',
    'CERT_HAS_EXPIRED': 'expired',
    'CERTIFICATE_VERIFY_FAILED: certificate is not yet valid': 'not_yet_valid',
    'CERTIFICATE_VERIFY_FAILED: Hostname mismatch': 'hostname_mismatch',
    'IP address mismatch': 'hostname_mismatch',
    'CERTIFICATE_VERIFY_FAILED: self-signed certificate': 'untrusted',
    'SELF_SIGNED_CERT_IN_CHAIN': 'untrusted',
    'CERTIFICATE_VERIFY_FAILED: certificate untrusted': 'untrusted',
    'CERTIFICATE_VERIFY_FAILED: certificate revoked': 'revoked',
    'CERTIFICATE_VERIFY_FAILED': 'certificate_verify_failed',
    'certificate verification failed': 'certificate_verify_failed',
    'TLS handshake failed': 'handshake_failed',
  }.entries) {
    for (final inOsError in [false, true]) {
      test('classifies TLS reason ${entry.key} in OS error $inOsError', () {
        final diagnostic = classifyApiNetworkFailure(
          _dioError(
            TlsException(
              inOsError ? 'private TLS details' : entry.key,
              inOsError ? OSError(entry.key, -1) : null,
            ),
          ),
          stage: 'api_probe',
        );
        expect(diagnostic.failure, ApiNetworkFailure.tls);
        expect(diagnostic.toDiagnosticFields()['tls_reason'], entry.value);
      });
    }
  }

  test('bad certificate and handshake types have safe fallback reasons', () {
    final badCertificate = classifyApiNetworkFailure(
      DioException(
        requestOptions: RequestOptions(),
        type: DioExceptionType.badCertificate,
      ),
      stage: 'login',
    );
    expect(badCertificate.failure, ApiNetworkFailure.tls);
    expect(
      badCertificate.toDiagnosticFields()['tls_reason'],
      'certificate_verify_failed',
    );
    final handshake = classifyApiNetworkFailure(
      const HandshakeException('private details'),
      stage: 'login',
    );
    expect(handshake.toDiagnosticFields()['tls_reason'], 'handshake_failed');
    final unknownTls = classifyApiNetworkFailure(
      const TlsException('private details'),
      stage: 'login',
    );
    expect(unknownTls.failure, ApiNetworkFailure.tls);
    expect(unknownTls.toDiagnosticFields(), {
      'reason': 'tls',
      'stage': 'login',
    });
  });

  test('HTTP precedence drops TLS reason while retaining OS evidence', () {
    final request = RequestOptions();
    final diagnostic = classifyApiNetworkFailure(
      DioException(
        requestOptions: request,
        response: Response(requestOptions: request, statusCode: 403),
        type: DioExceptionType.badCertificate,
        error: _dioError(
          const HandshakeException(
            'Handshake error in client',
            OSError(
              'CERTIFICATE_VERIFY_FAILED: unable to get local issuer '
              'certificate',
              -1,
            ),
          ),
        ),
      ),
      stage: 'login',
    );
    expect(diagnostic.failure, ApiNetworkFailure.http);
    expect(diagnostic.statusCode, 403);
    expect(diagnostic.osErrorCode, -1);
    expect(diagnostic.tlsFailure, isNull);
    expect(diagnostic.toDiagnosticFields(), {
      'reason': 'http',
      'stage': 'login',
      'http_status': 403,
      'os_error_code': -1,
    });
    expect(
      const ApiNetworkDiagnostic(
        failure: ApiNetworkFailure.http,
        stage: 'login',
        tlsFailure: ApiTlsFailure.expired,
      ).toDiagnosticFields().containsKey('tls_reason'),
      isFalse,
    );
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

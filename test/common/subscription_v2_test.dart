import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as dart_crypto;
import 'package:cryptography/cryptography.dart';
import 'package:dio/dio.dart';
import 'package:fl_clash/common/api_health.dart';
import 'package:fl_clash/common/api_network_diagnostic.dart';
import 'package:fl_clash/common/api_request_router.dart';
import 'package:fl_clash/common/diagnostic_log.dart';
import 'package:fl_clash/common/subscription_v2.dart';
import 'package:fl_clash/common/xboard_auth.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final status in [403, 407, 429, 503]) {
    test(
      'secure gateway retains HTTP $status without legacy downgrade',
      () async {
        final server = await _FakeSubscriptionV2Server.create();
        final events = <Map<String, Object?>>[];
        final dio = Dio();
        addTearDown(() => dio.close(force: true));
        dio.interceptors.add(
          InterceptorsWrapper(
            onRequest: (options, handler) => handler.resolve(
              Response<Object?>(
                requestOptions: options,
                statusCode: status,
                data: '<html>private gateway response secret</html>',
              ),
            ),
          ),
        );
        final client = SubscriptionV2Client(
          apiHealthService: _healthService(server.config),
          dio: dio,
          valueStore: _MemorySubscriptionV2ValueStore(),
          diagnosticRecorder: (event, fields) =>
              events.add({'event': event, ...fields}),
        );
        var legacyCalls = 0;
        final service = XboardAuthService(
          endpointLoader: () async => [
            Uri.parse('https://private.example.com'),
          ],
          subscriptionV2Client: client,
          diagnosticRecorder: (_, _) {},
          loginRequester: (_, _, _) async {
            legacyCalls++;
            throw StateError('Legacy must not be called');
          },
        );
        await expectLater(
          service.login(email: 'private@example.com', password: 'secret'),
          throwsA(
            isA<XboardAuthException>()
                .having(
                  (error) => error.failure,
                  'failure',
                  XboardAuthFailure.unavailable,
                )
                .having((error) => error.statusCode, 'HTTP status', status)
                .having(
                  (error) => error.diagnostic?.failure,
                  'reason',
                  ApiNetworkFailure.http,
                )
                .having(
                  (error) => error.diagnostic?.stage,
                  'stage',
                  'secure_gateway',
                ),
          ),
        );
        expect(legacyCalls, 0);
        final gatewayFailure = events.singleWhere(
          (event) => event['event'] == 'api.secure_gateway.failed',
        );
        expect(gatewayFailure['http_status'], status);
        expect(jsonEncode(events), isNot(contains('private')));
        expect(jsonEncode(events), isNot(contains('secret')));
      },
    );
  }

  test('secure gateway retains wrapped connection reset evidence', () async {
    final server = await _FakeSubscriptionV2Server.create();
    final dio = Dio();
    addTearDown(() => dio.close(force: true));
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) => handler.reject(
          DioException(
            requestOptions: options,
            type: DioExceptionType.connectionError,
            error: const SocketException(
              'private.example.com',
              osError: OSError('reset', 10054),
            ),
          ),
        ),
      ),
    );
    final client = SubscriptionV2Client(
      apiHealthService: _healthService(server.config),
      dio: dio,
      valueStore: _MemorySubscriptionV2ValueStore(),
      diagnosticRecorder: (_, _) {},
    );
    await expectLater(
      client.secureLogin(
        endpoint: Uri.parse('https://private.example.com'),
        email: 'private@example.com',
        password: 'secret',
        appVersion: 'test',
      ),
      throwsA(
        isA<SubscriptionV2Exception>()
            .having((error) => error.code, 'code', 'gateway_unavailable')
            .having(
              (error) => error.diagnostic?.failure,
              'reason',
              ApiNetworkFailure.connectionReset,
            )
            .having((error) => error.diagnostic?.osErrorCode, 'OS code', 10054),
      ),
    );
  });

  test('local Debug device storage persists without Keychain', () async {
    SharedPreferences.setMockInitialValues({});
    final store = LocalDebugSubscriptionV2ValueStore();

    await store.write('device', 'seed');
    expect(await store.read('device'), 'seed');

    await store.delete('device');
    expect(await store.read('device'), isNull);
  });

  test('recognizes only legacy XBoard sakula subscription URLs', () {
    expect(
      isLegacyXboardSubscriptionProfileSource(
        'https://api.example.com/sakula/cddfa43b5a09bdd07b05d85955a7cf0f',
      ),
      isTrue,
    );
    expect(
      isLegacyXboardSubscriptionProfileSource(
        'https://api.example.com/client/cddfa43b5a09bdd07b05d85955a7cf0f',
      ),
      isFalse,
    );
    expect(
      isLegacyXboardSubscriptionProfileSource(
        'https://api.example.com/sakula/not-a-token',
      ),
      isFalse,
    );
    expect(
      isLegacyXboardSubscriptionProfileSource(
        'fengwo-v2://key/cddfa43b5a09bdd07b05d85955a7cf0f',
      ),
      isFalse,
    );
  });

  test('registers a device and redeems one-time encrypted profiles', () async {
    final server = await _FakeSubscriptionV2Server.create();
    final store = _MemorySubscriptionV2ValueStore();
    final client = SubscriptionV2Client(
      apiHealthService: _healthService(server.config),
      valueStore: store,
      requester: server.request,
      now: () => DateTime.utc(2026, 8, 31, 12),
      random: Random(42),
    );

    final first = await client.fetchProfile(
      endpoint: Uri.parse('https://api.example.com/base'),
      userToken: '0123456789abcdef0123456789abcdef',
      appVersion: '1.9.0',
      platform: 'macos',
    );
    final second = await client.fetchProfile(
      endpoint: Uri.parse('https://api.example.com/base'),
      userToken: '0123456789abcdef0123456789abcdef',
      appVersion: '1.9.0',
      platform: 'macos',
    );
    await client.revokeDevice(
      endpoint: Uri.parse('https://api.example.com/base'),
      userToken: '0123456789abcdef0123456789abcdef',
    );
    final third = await client.fetchProfile(
      endpoint: Uri.parse('https://api.example.com/base'),
      userToken: '0123456789abcdef0123456789abcdef',
      appVersion: '1.9.0',
      platform: 'macos',
    );

    expect(utf8.decode(first!.bytes), server.profile);
    expect(utf8.decode(second!.bytes), server.profile);
    expect(utf8.decode(third!.bytes), server.profile);
    expect(first.sourceId, startsWith('fengwo-v2://test-key/'));
    expect(server.operations, [
      'register_device',
      'issue_ticket',
      'redeem_ticket',
      'issue_ticket',
      'redeem_ticket',
      'revoke_device',
      'register_device',
      'issue_ticket',
      'redeem_ticket',
    ]);
    expect(server.redeemedTickets, hasLength(3));
  });

  test(
    'profile pipeline diagnostics contain only safe stage metadata',
    () async {
      final server = await _FakeSubscriptionV2Server.create();
      final events = <Map<String, Object?>>[];
      final client = SubscriptionV2Client(
        apiHealthService: _healthService(server.config),
        valueStore: _MemorySubscriptionV2ValueStore(),
        requester: server.request,
        now: () => DateTime.utc(2026, 8, 31, 12),
        random: Random(43),
        diagnosticRecorder: (event, fields) =>
            events.add({'event': event, ...fields}),
      );
      final login = await client.secureLogin(
        endpoint: Uri.parse('https://api.example.com'),
        email: 'gray@example.com',
        password: 'correct-password',
        appVersion: '1.9.0',
        platform: 'macos',
      );
      events.clear();

      final profile = await client.fetchProfile(
        endpoint: Uri.parse('https://api.example.com'),
        userToken: login!.token,
        appVersion: '1.9.0',
        platform: 'macos',
        allowTokenRegistration: false,
      );

      expect(profile, isNotNull);
      expect(
        events.map((event) => event['stage']),
        containsAll([
          'profile_config_read',
          'profile_credential_read',
          'issue_ticket',
          'issue_ticket_decrypt',
          'redeem_ticket',
          'redeem_ticket_decrypt',
        ]),
      );
      final redeemCompleted = events.singleWhere(
        (event) =>
            event['event'] == 'subscription.pipeline.completed' &&
            event['stage'] == 'redeem_ticket',
      );
      expect(
        redeemCompleted['content_bytes'],
        utf8.encode(server.profile).length,
      );
      for (final event in events) {
        expect(
          event.keys.toSet().difference({
            'event',
            'stage',
            'error_code',
            'content_bytes',
          }),
          isEmpty,
        );
      }
      final encoded = jsonEncode(events);
      expect(encoded, isNot(contains('api.example.com')));
      expect(encoded, isNot(contains(login.token)));
      expect(encoded, isNot(contains(server.profile)));
    },
  );

  test(
    'profile pipeline diagnostics reject unsafe remote error text',
    () async {
      final events = <Map<String, Object?>>[];

      await expectLater(
        runSubscriptionDiagnosticStage<void>(
          stage: 'issue_ticket',
          recorder: (event, fields) => events.add({'event': event, ...fields}),
          task: () async {
            throw const SubscriptionV2Exception(
              'token=private-token private-api.example.com',
            );
          },
        ),
        throwsA(isA<SubscriptionV2Exception>()),
      );

      final failed = events.singleWhere(
        (event) => event['event'] == 'subscription.pipeline.failed',
      );
      expect(failed['error_code'], 'invalid_error_code');
      final encoded = jsonEncode(events);
      expect(encoded, isNot(contains('private-token')));
      expect(encoded, isNot(contains('private-api.example.com')));
    },
  );

  test(
    'allows legacy fallback only for a signed gray-list rejection',
    () async {
      final server = await _FakeSubscriptionV2Server.create(allowed: false);
      final client = SubscriptionV2Client(
        apiHealthService: _healthService(server.config),
        valueStore: _MemorySubscriptionV2ValueStore(),
        requester: server.request,
        now: () => DateTime.utc(2026, 8, 31, 12),
        random: Random(7),
      );

      final result = await client.fetchProfile(
        endpoint: Uri.parse('https://api.example.com'),
        userToken: '0123456789abcdef0123456789abcdef',
        appVersion: '1.9.0',
      );

      expect(result, isNull);
      expect(server.operations, ['register_device']);
    },
  );

  test(
    'node metadata uses a signed request with the stored account device',
    () async {
      final server = await _FakeSubscriptionV2Server.create();
      final store = _MemorySubscriptionV2ValueStore();
      final events = <Map<String, Object?>>[];
      final endpoint = Uri.parse('https://api.example.com');
      final client = SubscriptionV2Client(
        apiHealthService: _healthService(server.config),
        valueStore: store,
        requester: server.request,
        now: () => DateTime.utc(2026, 8, 31, 12),
        random: Random(31),
      );
      final login = await client.secureLogin(
        endpoint: endpoint,
        email: 'gray@example.com',
        password: 'correct-password',
        appVersion: '1.0.5',
      );
      final restoredClient = SubscriptionV2Client(
        apiHealthService: _healthService(server.config),
        valueStore: store,
        requester: server.request,
        now: () => DateTime.utc(2026, 8, 31, 12),
        random: Random(32),
        diagnosticRecorder: (event, fields) =>
            events.add({'event': event, ...fields}),
      );
      final metadata = await restoredClient.fetchNodes(
        endpoint: endpoint,
        userToken: login!.token,
      );
      expect((metadata['nodes']! as List).single, {
        'id': 1,
        'name': '测试节点',
        'type': 'anytls',
        'rate': 1,
        'tags': ['HK', 'VIP'],
        'is_online': true,
        'last_check_at': 1788177600,
      });
      await expectLater(
        restoredClient.fetchNodes(
          endpoint: endpoint,
          userToken: 'another-account',
        ),
        throwsA(
          isA<SubscriptionV2Exception>().having(
            (error) => error.code,
            'code',
            'device_not_registered',
          ),
        ),
      );
      expect(server.operations, ['login_device', 'get_nodes']);
      expect(
        events.any((event) => event['stage'] == 'get_nodes_decrypt'),
        isTrue,
      );
    },
  );

  test('secure login binds the device before returning credentials', () async {
    final server = await _FakeSubscriptionV2Server.create();
    final client = SubscriptionV2Client(
      apiHealthService: _healthService(server.config),
      valueStore: _MemorySubscriptionV2ValueStore(),
      requester: server.request,
      now: () => DateTime.utc(2026, 8, 31, 12),
      random: Random(11),
    );

    final login = await client.secureLogin(
      endpoint: Uri.parse('https://api.example.com'),
      email: 'gray@example.com',
      password: 'correct-password',
      appVersion: '1.9.0',
      platform: 'macos',
    );
    final summary = await client.fetchSummary(
      endpoint: Uri.parse('https://api.example.com'),
      userToken: login!.token,
    );
    final profile = await client.fetchProfile(
      endpoint: Uri.parse('https://api.example.com'),
      userToken: login.token,
      appVersion: '1.9.0',
      platform: 'macos',
      allowTokenRegistration: false,
    );
    await client.resetSecurity(
      endpoint: Uri.parse('https://api.example.com'),
      userToken: login.token,
    );

    expect(login.authData, 'Bearer secure-session');
    expect(login.subscription['plan_id'], 7);
    expect(summary['email'], 'gray@example.com');
    expect(summary, isNot(contains('token')));
    expect(utf8.decode(profile!.bytes), server.profile);
    expect(server.operations, [
      'login_device',
      'get_summary',
      'issue_ticket',
      'redeem_ticket',
      'reset_security',
    ]);
  });

  test(
    'secure login allows legacy fallback only after signed rejection',
    () async {
      final server = await _FakeSubscriptionV2Server.create(allowed: false);
      final client = SubscriptionV2Client(
        apiHealthService: _healthService(server.config),
        valueStore: _MemorySubscriptionV2ValueStore(),
        requester: server.request,
        now: () => DateTime.utc(2026, 8, 31, 12),
        random: Random(12),
      );

      final login = await client.secureLogin(
        endpoint: Uri.parse('https://api.example.com'),
        email: 'public@example.com',
        password: 'correct-password',
        appVersion: '1.9.0',
      );

      expect(login, isNull);
      expect(server.operations, ['login_device']);
    },
  );

  test('secure login does not downgrade when V2 config is absent', () async {
    var gatewayRequests = 0;
    final client = SubscriptionV2Client(
      apiHealthService: _healthService({
        'Authentication': 'FengWo',
        'hosts': ['https://api.example.com'],
      }),
      valueStore: _MemorySubscriptionV2ValueStore(),
      requester: (endpoint, envelope) async {
        gatewayRequests++;
        return const {};
      },
    );

    await expectLater(
      client.secureLogin(
        endpoint: Uri.parse('https://api.example.com'),
        email: 'public@example.com',
        password: 'correct-password',
        appVersion: '1.9.0',
      ),
      throwsA(
        isA<SubscriptionV2Exception>()
            .having((error) => error.code, 'code', 'secure_config_disabled')
            .having((error) => error.requestRef, 'request ref', isNull),
      ),
    );
    expect(gatewayRequests, 0);
  });

  test(
    'secure login preserves a signed business code and request ref',
    () async {
      final server = await _FakeSubscriptionV2Server.create(
        loginRejectionCode: 'future_policy_denied',
      );
      final client = SubscriptionV2Client(
        apiHealthService: _healthService(server.config),
        valueStore: _MemorySubscriptionV2ValueStore(),
        requester: server.request,
        now: () => DateTime.utc(2026, 8, 31, 12),
        random: Random(13),
      );

      await expectLater(
        client.secureLogin(
          endpoint: Uri.parse('https://api.example.com'),
          email: 'public@example.com',
          password: 'correct-password',
          appVersion: '1.9.0',
        ),
        throwsA(
          isA<SubscriptionV2Exception>()
              .having((error) => error.code, 'code', 'future_policy_denied')
              .having(
                (error) => error.requestRef,
                'request ref',
                matches(RegExp(r'^[a-f0-9]{12}$')),
              ),
        ),
      );
      expect(server.operations, ['login_device']);
    },
  );

  test('missing response signature keeps a retryable protocol code', () async {
    final server = await _FakeSubscriptionV2Server.create();
    final client = SubscriptionV2Client(
      apiHealthService: _healthService(server.config),
      valueStore: _MemorySubscriptionV2ValueStore(),
      requester: (endpoint, envelope) async {
        final response = await server.request(endpoint, envelope);
        return Map<String, Object?>.from(response)..remove('signature');
      },
      now: () => DateTime.utc(2026, 8, 31, 12),
      random: Random(14),
    );

    await expectLater(
      client.secureLogin(
        endpoint: Uri.parse('https://api.example.com'),
        email: 'gray@example.com',
        password: 'correct-password',
        appVersion: '1.9.0',
      ),
      throwsA(
        isA<SubscriptionV2Exception>()
            .having((error) => error.code, 'code', 'invalid_signature')
            .having(
              (error) => error.requestRef,
              'request ref',
              matches(RegExp(r'^[a-f0-9]{12}$')),
            ),
      ),
    );
  });

  test('rejects a response whose server signature was modified', () async {
    final server = await _FakeSubscriptionV2Server.create();
    final client = SubscriptionV2Client(
      apiHealthService: _healthService(server.config),
      valueStore: _MemorySubscriptionV2ValueStore(),
      requester: (endpoint, envelope) async {
        final response = await server.request(endpoint, envelope);
        return Map<String, Object?>.from(response)
          ..['signature'] = _encode(List<int>.filled(64, 1));
      },
      now: () => DateTime.utc(2026, 8, 31, 12),
      random: Random(9),
    );

    await expectLater(
      client.fetchProfile(
        endpoint: Uri.parse('https://api.example.com'),
        userToken: '0123456789abcdef0123456789abcdef',
        appVersion: '1.9.0',
      ),
      throwsA(
        isA<SubscriptionV2Exception>()
            .having((error) => error.code, 'code', 'invalid_server_signature')
            .having(
              (error) => error.requestRef,
              'request ref',
              matches(RegExp(r'^[a-f0-9]{12}$')),
            ),
      ),
    );
  });

  test('keeps V2 disabled unless the complete public config is valid', () {
    expect(
      parseSubscriptionV2RemoteConfig({
        'Authentication': 'FengWo',
        'subscriptionV2': {'enabled': false},
      }),
      isNull,
    );
    expect(
      () => parseSubscriptionV2RemoteConfig({
        'subscriptionV2': {
          'enabled': true,
          'gatewayPath': 'https://attacker.example/api/v2/g/test',
          'keyId': 'test',
          'serverEncryptionPublicKey': _encode(List<int>.filled(32, 1)),
          'serverSigningPublicKey': _encode(List<int>.filled(32, 2)),
        },
      }),
      throwsFormatException,
    );
  });
  for (final lostOperation in ['issue_ticket', 'redeem_ticket']) {
    test(
      'restarts profile exchange after lost $lostOperation response',
      () async {
        final server = await _FakeSubscriptionV2Server.create()
          ..hosts = _trustedHosts;
        final store = _MemorySubscriptionV2ValueStore();
        final client = _fixtureClient(
          server,
          store,
          diagnosticRecorder: (event, _) {
            if (event == 'subscription_v2.gateway.retry') {
              throw StateError('Unavailable diagnostic recorder');
            }
          },
          requester: (endpoint, envelope) async {
            final response = await server.request(endpoint, envelope);
            if (endpoint.host == 'api.example.com' &&
                server.operations.last == lostOperation) {
              throw TimeoutException('Simulated lost gateway response');
            }
            return response;
          },
        );
        await _fixtureLogin(client);

        final profile = await _fixtureProfile(client);

        expect(utf8.decode(profile!.bytes), server.profile);
        expect(server.operations, [
          'login_device',
          'issue_ticket',
          if (lostOperation == 'redeem_ticket') 'redeem_ticket',
          'issue_ticket',
          'redeem_ticket',
        ]);
        expect(server.endpoints.last.host, 'backup.example.com');
        expect(server.ticketSequence, 2);
        expect(
          server.redeemedTickets,
          hasLength(lostOperation == 'redeem_ticket' ? 2 : 1),
        );
        expect(
          server.envelopes.map((envelope) => envelope['request_id']).toSet(),
          hasLength(server.envelopes.length),
        );
        expect(
          server.payloads.map((payload) => payload['nonce']).toSet(),
          hasLength(server.payloads.length),
        );
        expect(
          server.payloads.where((payload) => payload['op'] != 'login_device'),
          everyElement(isNot(contains('user_token'))),
        );
      },
    );
  }

  for (final operation in ['get_nodes', 'get_summary']) {
    test(
      'retries read-only $operation on a trusted equivalent gateway',
      () async {
        final server = await _FakeSubscriptionV2Server.create()
          ..hosts = _trustedHosts;
        final client = _fixtureClient(
          server,
          _MemorySubscriptionV2ValueStore(),
          requester: (endpoint, envelope) async {
            final response = await server.request(endpoint, envelope);
            if (endpoint.host == 'api.example.com' &&
                server.operations.last == operation) {
              throw TimeoutException('Simulated lost gateway response');
            }
            return response;
          },
        );
        await _fixtureLogin(client);

        final data = operation == 'get_nodes'
            ? await client.fetchNodes(
                endpoint: _primaryEndpoint,
                userToken: _token,
              )
            : await client.fetchSummary(
                endpoint: _primaryEndpoint,
                userToken: _token,
              );

        expect(data, isNotEmpty);
        expect(server.operations, ['login_device', operation, operation]);
        expect(server.endpoints.last.host, 'backup.example.com');
        expect(
          server.payloads.last['nonce'],
          isNot(server.payloads[1]['nonce']),
        );
      },
    );
  }

  test('never sends a stored credential to an unlisted gateway', () async {
    final server = await _FakeSubscriptionV2Server.create()
      ..hosts = _trustedHosts;
    final store = _MemorySubscriptionV2ValueStore();
    final client = _fixtureClient(server, store);
    await _fixtureLogin(client);

    await expectLater(
      client.fetchProfile(
        endpoint: Uri.parse('https://unlisted.example.com'),
        userToken: _token,
        appVersion: '1.9.0',
        allowTokenRegistration: false,
      ),
      throwsA(_subscriptionError('untrusted_gateway')),
    );
    server.hosts = ['https://backup.example.com'];
    final changedConfigClient = _fixtureClient(server, store);
    await expectLater(
      _fixtureProfile(changedConfigClient, endpoint: _backupEndpoint),
      throwsA(_subscriptionError('device_not_registered')),
    );
    expect(server.operations, ['login_device']);
  });

  test('legacy configs without hosts retain exact gateway binding', () async {
    final server = await _FakeSubscriptionV2Server.create();
    final store = _MemorySubscriptionV2ValueStore();
    final client = _fixtureClient(server, store);
    await _fixtureLogin(client);

    await expectLater(
      _fixtureProfile(client, endpoint: _backupEndpoint),
      throwsA(_subscriptionError('device_not_registered')),
    );
    expect(server.operations, ['login_device']);
    expect(await _fixtureProfile(client), isNotNull);
  });

  for (final rejection in [
    'invalid_credentials',
    'rate_limited',
    'device_not_registered',
    'invalid_ticket',
    'invalid_device_signature',
    'request_expired',
    'gateway_unavailable',
  ]) {
    test('stops profile fallback on signed $rejection rejection', () async {
      final server = await _FakeSubscriptionV2Server.create()
        ..hosts = _trustedHosts
        ..operationRejections['issue_ticket'] = rejection;
      final router = ApiRequestRouter();
      final client = _fixtureClient(
        server,
        _MemorySubscriptionV2ValueStore(),
        requestRouter: router,
      );
      await _fixtureLogin(client);

      await expectLater(
        _fixtureProfile(client),
        throwsA(_subscriptionError(rejection)),
      );
      expect(server.operations, ['login_device', 'issue_ticket']);
      expect(server.endpoints.map((endpoint) => endpoint.host).toSet(), {
        'api.example.com',
      });
      expect(
        router
            .orderCandidates(
              _trustedHosts.map(Uri.parse),
              preferred: _primaryEndpoint,
            )
            .first,
        _primaryEndpoint,
      );
    });
  }

  test('stops profile fallback on an invalid server signature', () async {
    final server = await _FakeSubscriptionV2Server.create()
      ..hosts = _trustedHosts;
    final client = _fixtureClient(
      server,
      _MemorySubscriptionV2ValueStore(),
      requester: (endpoint, envelope) async {
        final response = await server.request(endpoint, envelope);
        if (server.operations.last == 'issue_ticket') {
          response['signature'] = _encode(List<int>.filled(64, 0));
        }
        return response;
      },
    );
    await _fixtureLogin(client);

    await expectLater(
      _fixtureProfile(client),
      throwsA(_subscriptionError('invalid_server_signature')),
    );
    expect(server.operations, ['login_device', 'issue_ticket']);
  });

  test(
    'legacy opt-in repairs a device rejection once on the same gateway',
    () async {
      final server = await _FakeSubscriptionV2Server.create()
        ..hosts = _trustedHosts
        ..operationRejections['issue_ticket'] = 'device_not_registered';
      final client = _fixtureClient(
        server,
        _MemorySubscriptionV2ValueStore(),
        requester: (endpoint, envelope) async {
          final response = await server.request(endpoint, envelope);
          if (server.operations.last == 'register_device') {
            server.operationRejections.remove('issue_ticket');
          }
          return response;
        },
      );
      await _fixtureLogin(client);

      final profile = await client.fetchProfile(
        endpoint: _primaryEndpoint,
        userToken: _token,
        appVersion: '1.9.0',
      );
      expect(utf8.decode(profile!.bytes), server.profile);
      expect(server.operations, [
        'login_device',
        'issue_ticket',
        'register_device',
        'issue_ticket',
        'redeem_ticket',
      ]);
      expect(server.endpoints.map((endpoint) => endpoint.host).toSet(), {
        'api.example.com',
      });
    },
  );

  test(
    'legacy device repair never switches gateways after rejection',
    () async {
      final server = await _FakeSubscriptionV2Server.create()
        ..hosts = _trustedHosts
        ..operationRejections['issue_ticket'] = 'device_not_registered';
      final client = _fixtureClient(
        server,
        _MemorySubscriptionV2ValueStore(),
        requester: (endpoint, envelope) async {
          final response = await server.request(endpoint, envelope);
          if (server.operations.last == 'register_device') {
            throw TimeoutException('Simulated lost registration response');
          }
          return response;
        },
      );
      await _fixtureLogin(client);

      await expectLater(
        client.fetchProfile(
          endpoint: _primaryEndpoint,
          userToken: _token,
          appVersion: '1.9.0',
        ),
        throwsA(_subscriptionError('gateway_unavailable')),
      );
      expect(server.operations, [
        'login_device',
        'issue_ticket',
        'register_device',
      ]);
      expect(server.endpoints.map((endpoint) => endpoint.host).toSet(), {
        'api.example.com',
      });
    },
  );

  for (final status in [401, 403, 429]) {
    test('stops profile fallback on HTTP $status', () async {
      final server = await _FakeSubscriptionV2Server.create()
        ..hosts = _trustedHosts;
      final store = _MemorySubscriptionV2ValueStore();
      await _fixtureLogin(_fixtureClient(server, store));
      final requests = <Uri>[];
      final router = ApiRequestRouter();
      final dio = Dio();
      addTearDown(() => dio.close(force: true));
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            requests.add(options.uri);
            handler.resolve(
              Response<Object?>(
                requestOptions: options,
                statusCode: status,
                data: {},
              ),
            );
          },
        ),
      );
      final client = _fixtureClient(
        server,
        store,
        dio: dio,
        requestRouter: router,
      );

      await expectLater(
        _fixtureProfile(client),
        throwsA(
          _subscriptionError(
            'gateway_unavailable',
          ).having((error) => error.statusCode, 'HTTP status', status),
        ),
      );
      expect(requests, hasLength(1));
      expect(requests.single.host, 'api.example.com');
      expect(
        router
            .orderCandidates(
              _trustedHosts.map(Uri.parse),
              preferred: _primaryEndpoint,
            )
            .first,
        _primaryEndpoint,
      );
    });
  }

  test('retains desktop TLS reason and stops secure gateway fallback', () async {
    final server = await _FakeSubscriptionV2Server.create()
      ..hosts = _trustedHosts;
    final store = _MemorySubscriptionV2ValueStore();
    await _fixtureLogin(_fixtureClient(server, store));
    final dio = Dio();
    addTearDown(() => dio.close(force: true));
    var requests = 0;
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          requests++;
          handler.reject(
            DioException(
              requestOptions: options,
              type: DioExceptionType.connectionError,
              error: const HandshakeException(
                'private certificate subject',
                OSError(
                  'CERTIFICATE_VERIFY_FAILED: unable to get local issuer certificate',
                  -1,
                ),
              ),
            ),
          );
        },
      ),
    );
    final events = <Map<String, Object?>>[];
    final client = _fixtureClient(
      server,
      store,
      dio: dio,
      diagnosticRecorder: (event, fields) =>
          events.add({'event': event, ...fields}),
    );

    await expectLater(
      _fixtureProfile(client),
      throwsA(
        _subscriptionError('gateway_unavailable')
            .having(
              (error) => error.diagnostic?.failure,
              'reason',
              ApiNetworkFailure.tls,
            )
            .having(
              (error) => error.diagnostic?.tlsFailure,
              'TLS reason',
              ApiTlsFailure.missingIssuer,
            ),
      ),
    );
    expect(requests, 1);
    expect(
      events.singleWhere(
        (event) => event['event'] == 'api.secure_gateway.failed',
      )['tls_reason'],
      'missing_issuer',
    );
    expect(jsonEncode(events), isNot(contains('private certificate subject')));
  });

  test('never follows a secure gateway redirect to an unlisted origin', () async {
    final destination = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final origin = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => destination.close(force: true));
    addTearDown(() => origin.close(force: true));
    var foreignRequests = 0;
    var originRequests = 0;
    final destinationListener = destination.listen((request) async {
      foreignRequests++;
      await request.drain<void>();
      request.response.statusCode = 500;
      await request.response.close();
    });
    final originListener = origin.listen((request) async {
      originRequests++;
      await request.drain<void>();
      request.response.statusCode = 302;
      request.response.headers.set(
        HttpHeaders.locationHeader,
        'http://127.0.0.1:${destination.port}${_FakeSubscriptionV2Server.gatewayPath}',
      );
      await request.response.close();
    });
    addTearDown(destinationListener.cancel);
    addTearDown(originListener.cancel);
    final endpoint = Uri.parse('http://127.0.0.1:${origin.port}');
    final server = await _FakeSubscriptionV2Server.create()
      ..hosts = ['https://api.example.com', endpoint.toString()];
    final store = _MemorySubscriptionV2ValueStore();
    await _fixtureLogin(_fixtureClient(server, store));
    final dio = Dio();
    addTearDown(() => dio.close(force: true));
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          if (options.uri.host == '127.0.0.1') {
            handler.next(options);
          } else {
            handler.reject(
              DioException(
                requestOptions: options,
                error: StateError('Unexpected non-local test request'),
              ),
            );
          }
        },
      ),
    );
    final client = _fixtureClient(server, store, dio: dio);

    await HttpOverrides.runWithHttpOverrides(
      () => expectLater(
        _fixtureProfile(client, endpoint: endpoint),
        throwsA(
          _subscriptionError(
            'gateway_unavailable',
          ).having((error) => error.statusCode, 'HTTP status', 302),
        ),
      ),
      _LocalHttpOverrides(),
    );
    expect(originRequests, 1);
    expect(foreignRequests, 0);
  });

  for (final operation in ['login_device', 'reset_security', 'revoke_device']) {
    test('does not replay $operation after a lost response', () async {
      final server = await _FakeSubscriptionV2Server.create()
        ..hosts = _trustedHosts;
      final store = _MemorySubscriptionV2ValueStore();
      if (operation != 'login_device') {
        await _fixtureLogin(_fixtureClient(server, store));
      }
      final client = _fixtureClient(
        server,
        store,
        requester: (endpoint, envelope) async {
          await server.request(endpoint, envelope);
          throw TimeoutException('Simulated lost gateway response');
        },
      );
      final Future<Object?> result = switch (operation) {
        'login_device' => _fixtureLogin(client),
        'reset_security' => client.resetSecurity(
          endpoint: _primaryEndpoint,
          userToken: _token,
        ),
        _ => client.revokeDevice(endpoint: _primaryEndpoint, userToken: _token),
      };

      await expectLater(
        result,
        throwsA(_subscriptionError('gateway_unavailable')),
      );
      expect(
        server.operations.where((value) => value == operation),
        hasLength(1),
      );
      expect(server.endpoints.map((endpoint) => endpoint.host).toSet(), {
        'api.example.com',
      });
    });
  }

  test(
    'coalesces concurrent profile fetches and releases completed work',
    () async {
      final server = await _FakeSubscriptionV2Server.create()
        ..hosts = _trustedHosts;
      final started = Completer<void>();
      final release = Completer<void>();
      final client = _fixtureClient(
        server,
        _MemorySubscriptionV2ValueStore(),
        requester: (endpoint, envelope) async {
          final response = await server.request(endpoint, envelope);
          if (server.operations.last == 'issue_ticket' &&
              !started.isCompleted) {
            started.complete();
            await release.future;
          }
          return response;
        },
      );
      await _fixtureLogin(client);
      final first = _fixtureProfile(client);
      await started.future;
      final second = _fixtureProfile(client, endpoint: _backupEndpoint);
      await Future<void>.delayed(Duration.zero);
      expect(server.operations, ['login_device', 'issue_ticket']);
      release.complete();

      final profiles = await Future.wait([first, second]);
      expect(
        profiles.every(
          (profile) => utf8.decode(profile!.bytes) == server.profile,
        ),
        isTrue,
      );
      expect(server.ticketSequence, 1);
      expect(await _fixtureProfile(client), isNotNull);
      expect(server.ticketSequence, 2);
    },
  );

  for (final scope in [
    'same account and config',
    'different account',
    'different config',
  ]) {
    test('default clients isolate shared profile work for $scope', () async {
      final directory = await Directory.systemTemp.createTemp(
        'subscription-v2-shared-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final previousPathProvider = PathProviderPlatform.instance;
      PathProviderPlatform.instance = _TemporaryPathProvider(directory.path);
      addTearDown(() async {
        await diagnosticLog.flush();
        PathProviderPlatform.instance = previousPathProvider;
      });
      FlutterSecureStorage.setMockInitialValues({});
      addTearDown(() => FlutterSecureStorage.setMockInitialValues({}));
      final server = await _FakeSubscriptionV2Server.create();
      const otherToken = 'fedcba9876543210fedcba9876543210';
      server.loginTokens['other@example.com'] = otherToken;
      final origins = [
        await HttpServer.bind(InternetAddress.loopbackIPv4, 0),
        await HttpServer.bind(InternetAddress.loopbackIPv4, 0),
      ];
      final endpoints = [
        for (final origin in origins)
          Uri.parse('http://127.0.0.1:${origin.port}'),
      ];
      server.hosts = endpoints.map((endpoint) => endpoint.toString()).toList();
      var routerNow = DateTime.utc(2026, 10, 7);
      final router = ApiRequestRouter(now: () => routerNow);
      final started = Completer<void>();
      final release = Completer<void>();
      final restRelease = Completer<void>();
      addTearDown(() {
        if (!release.isCompleted) release.complete();
        if (!restRelease.isCompleted) restRelease.complete();
      });
      for (final origin in origins) {
        addTearDown(() => origin.close(force: true));
        final listener = origin.listen((request) async {
          final envelope = Map<String, Object?>.from(
            jsonDecode(await utf8.decoder.bind(request).join()) as Map,
          );
          final response = await server.request(request.requestedUri, envelope);
          if (server.operations.last == 'issue_ticket' &&
              !release.isCompleted) {
            if (!started.isCompleted) started.complete();
            await release.future;
          }
          request.response.headers.contentType = ContentType.json;
          request.response.write(jsonEncode(response));
          await request.response.close();
        });
        addTearDown(listener.cancel);
      }
      var loadedConfigs = 0;
      final bothLoaded = Completer<void>();
      SubscriptionV2Client clientFor(Map<String, Object?> config) =>
          SubscriptionV2Client(
            apiHealthService: ApiHealthService(
              configUrl: 'https://config.example/app.json',
              configLoader: (_) async {
                if (++loadedConfigs == 2) bothLoaded.complete();
                return config;
              },
            ),
            diagnosticRecorder: (_, _) {},
            requestRouter: router,
          );

      await HttpOverrides.runWithHttpOverrides(() async {
        final loginClient = SubscriptionV2Client(
          apiHealthService: _healthService(server.config),
          diagnosticRecorder: (_, _) {},
          requestRouter: router,
        );
        await loginClient.secureLogin(
          endpoint: endpoints.first,
          email: 'gray@example.com',
          password: 'correct-password',
          appVersion: '1.9.0',
        );
        if (scope == 'different account') {
          await loginClient.secureLogin(
            endpoint: endpoints.first,
            email: 'other@example.com',
            password: 'correct-password',
            appVersion: '1.9.0',
          );
        }
        if (scope == 'same account and config') {
          for (final endpoint in endpoints) {
            router.recordFailure(
              endpoint,
              candidates: endpoints,
              error: TimeoutException('Previously unavailable'),
            );
          }
          routerNow = routerNow.add(const Duration(seconds: 16));
        }
        final firstConfig = Map<String, Object?>.from(server.config);
        if (scope == 'different config') {
          firstConfig['hosts'] = [endpoints.first.toString()];
        }
        final firstClient = clientFor(firstConfig);
        final secondClient = clientFor(server.config);
        final first = _fixtureProfile(firstClient, endpoint: endpoints.first);
        await started.future;
        final second = secondClient.fetchProfile(
          endpoint: endpoints.last,
          userToken: scope == 'different account' ? otherToken : _token,
          appVersion: '1.9.0',
          platform: 'android',
          allowTokenRegistration: false,
        );
        await bothLoaded.future;
        await Future<void>.delayed(Duration.zero);
        if (scope == 'same account and config') {
          expect(server.endpoints.last.origin, endpoints.first.origin);
          final restStarted = Completer<void>();
          final restEndpoints = <Uri>[];
          final rest = XboardAuthService(
            requestRouter: router,
            endpointLoader: () async => endpoints,
            diagnosticRecorder: (_, _) {},
            plansRequester: (endpoint, _) async {
              restEndpoints.add(endpoint);
              restStarted.complete();
              await restRelease.future;
              return const XboardLoginResponse(
                statusCode: 200,
                data: {'data': <Object?>[]},
              );
            },
          );
          final plans = rest.fetchPlans(
            endpoint: endpoints.first,
            authData: 'Bearer fixture',
          );
          await restStarted.future.timeout(const Duration(seconds: 2));
          expect(restEndpoints.single.origin, endpoints.last.origin);
          final blocked = SubscriptionV2Client(
            apiHealthService: _healthService(server.config),
            diagnosticRecorder: (_, _) {},
            requestRouter: router,
          );
          await expectLater(
            blocked.fetchSummary(endpoint: endpoints.first, userToken: _token),
            throwsA(_subscriptionError('gateway_unavailable')),
          );
          expect(server.operations, ['login_device', 'issue_ticket']);
          restRelease.complete();
          expect(await plans, isEmpty);
        }
        release.complete();
        final profiles = await Future.wait([first, second]);

        expect(
          profiles.map((profile) => utf8.decode(profile!.bytes)),
          everyElement(server.profile),
        );
        expect(
          server.ticketSequence,
          scope == 'same account and config' ? 1 : 2,
        );
        if (scope == 'different account') {
          expect(profiles.first!.sourceId, isNot(profiles.last!.sourceId));
        }
      }, _LocalHttpOverrides());
    });
  }

  for (final lostOperation in ['register_device', 'issue_ticket']) {
    test(
      'registration replay boundary after lost $lostOperation response',
      () async {
        final server = await _FakeSubscriptionV2Server.create()
          ..hosts = _trustedHosts;
        final client = _fixtureClient(
          server,
          _MemorySubscriptionV2ValueStore(),
          requester: (endpoint, envelope) async {
            final response = await server.request(endpoint, envelope);
            if (endpoint.host == 'api.example.com' &&
                server.operations.last == lostOperation) {
              throw TimeoutException('Simulated lost response');
            }
            return response;
          },
        );
        final result = client.fetchProfile(
          endpoint: _primaryEndpoint,
          userToken: _token,
          appVersion: '1.9.0',
        );

        if (lostOperation == 'register_device') {
          await expectLater(
            result,
            throwsA(_subscriptionError('gateway_unavailable')),
          );
          expect(server.operations, ['register_device']);
          expect(server.endpoints.single.host, 'api.example.com');
        } else {
          final profile = await result;
          expect(utf8.decode(profile!.bytes), server.profile);
          expect(server.operations, [
            'register_device',
            'issue_ticket',
            'issue_ticket',
            'redeem_ticket',
          ]);
          expect(server.endpoints.last.host, 'backup.example.com');
        }
      },
    );
  }

  test(
    'new clients share the healthy first gateway for every secure operation',
    () async {
      ApiRequestRouter.shared.clear();
      addTearDown(ApiRequestRouter.shared.clear);
      final server = await _FakeSubscriptionV2Server.create()
        ..hosts = _trustedHosts;
      final store = _MemorySubscriptionV2ValueStore();
      Future<Map<String, Object?>> request(
        Uri endpoint,
        Map<String, Object?> envelope,
      ) async {
        final response = await server.request(endpoint, envelope);
        if (endpoint.host == 'api.example.com' &&
            server.operations.last == 'issue_ticket') {
          throw TimeoutException('Primary gateway unavailable');
        }
        return response;
      }

      SubscriptionV2Client newClient() =>
          _sharedRouterClient(server, store, requester: request);
      await _fixtureLogin(newClient());
      expect(await _fixtureProfile(newClient()), isNotNull);
      expect(
        ApiRequestRouter.shared
            .orderCandidates(
              _trustedHosts.map(Uri.parse),
              preferred: _primaryEndpoint,
            )
            .first,
        _backupEndpoint,
      );

      for (final operation in [
        'profile',
        'get_summary',
        'get_nodes',
        'reset_security',
        'login_device',
        'revoke_device',
      ]) {
        final start = server.operations.length;
        final client = newClient();
        final result = await _fixtureOperation(client, operation);
        if (operation == 'login_device') {
          expect((result! as SubscriptionV2Login).endpoint, _backupEndpoint);
        }
        expect(
          server.endpoints[start].host,
          'backup.example.com',
          reason: operation,
        );
        expect(
          server.operations.length - start,
          operation == 'profile' ? 2 : 1,
        );
      }
    },
  );

  for (final operation in ['login_device', 'reset_security', 'revoke_device']) {
    test(
      'dynamic first gateway does not replay lost $operation responses',
      () async {
        ApiRequestRouter.shared.clear();
        addTearDown(ApiRequestRouter.shared.clear);
        final server = await _FakeSubscriptionV2Server.create()
          ..hosts = _trustedHosts;
        final store = _MemorySubscriptionV2ValueStore();
        var loseMutationResponse = false;
        Future<Map<String, Object?>> request(
          Uri endpoint,
          Map<String, Object?> envelope,
        ) async {
          final response = await server.request(endpoint, envelope);
          if ((endpoint.host == 'api.example.com' &&
                  server.operations.last == 'issue_ticket') ||
              (loseMutationResponse && server.operations.last == operation)) {
            throw TimeoutException('Simulated lost response');
          }
          return response;
        }

        SubscriptionV2Client newClient() =>
            _sharedRouterClient(server, store, requester: request);
        await _fixtureLogin(newClient());
        expect(await _fixtureProfile(newClient()), isNotNull);
        final start = server.operations.length;
        loseMutationResponse = true;

        await expectLater(
          _fixtureOperation(newClient(), operation),
          throwsA(_subscriptionError('gateway_unavailable')),
        );
        expect(server.operations.sublist(start), [operation]);
        expect(server.endpoints[start].host, 'backup.example.com');
      },
    );
  }

  test('cooled gateway recovers through a fresh trusted request', () async {
    var now = DateTime.utc(2026, 10, 7);
    final router = ApiRequestRouter(now: () => now);
    final server = await _FakeSubscriptionV2Server.create()
      ..hosts = _trustedHosts;
    final store = _MemorySubscriptionV2ValueStore();
    var losePrimaryResponse = true;
    Future<Map<String, Object?>> request(
      Uri endpoint,
      Map<String, Object?> envelope,
    ) async {
      final response = await server.request(endpoint, envelope);
      if (losePrimaryResponse &&
          endpoint.host == 'api.example.com' &&
          server.operations.last == 'issue_ticket') {
        losePrimaryResponse = false;
        throw TimeoutException('Primary gateway unavailable');
      }
      return response;
    }

    SubscriptionV2Client newClient() => _fixtureClient(
      server,
      store,
      requester: request,
      requestRouter: router,
    );
    await _fixtureLogin(newClient());
    expect(await _fixtureProfile(newClient()), isNotNull);
    await _fixtureOperation(newClient(), 'get_summary');
    expect(server.endpoints.last.host, 'backup.example.com');
    now = now.add(const Duration(seconds: 16));

    await _fixtureOperation(newClient(), 'get_summary');
    expect(server.endpoints.last.host, 'api.example.com');
    await _fixtureOperation(newClient(), 'get_nodes');
    expect(server.endpoints.last.host, 'api.example.com');
  });

  for (final operation in [
    'login_device',
    'reset_security',
    'revoke_device',
    'register_device',
  ]) {
    test('reserves half-open gateways across REST and $operation', () async {
      var now = DateTime.utc(2026, 10, 7);
      final router = ApiRequestRouter(now: () => now);
      final server = await _FakeSubscriptionV2Server.create()
        ..hosts = _trustedHosts;
      final store = _MemorySubscriptionV2ValueStore();
      final restStarted = Completer<void>();
      final restRelease = Completer<void>();
      final mutationStarted = Completer<void>();
      final mutationRelease = Completer<void>();
      addTearDown(() {
        if (!restRelease.isCompleted) restRelease.complete();
        if (!mutationRelease.isCompleted) mutationRelease.complete();
      });
      var blockMutation = false;
      Future<Map<String, Object?>> request(
        Uri endpoint,
        Map<String, Object?> envelope,
      ) async {
        final response = await server.request(endpoint, envelope);
        if (blockMutation && server.operations.last == operation) {
          mutationStarted.complete();
          await mutationRelease.future;
        }
        return response;
      }

      SubscriptionV2Client clientFor(SubscriptionV2ValueStore valueStore) =>
          _fixtureClient(
            server,
            valueStore,
            requester: request,
            requestRouter: router,
          );
      await _fixtureLogin(clientFor(store));
      final candidates = _trustedHosts.map(Uri.parse).toList();
      for (final endpoint in candidates) {
        router.recordFailure(
          endpoint,
          candidates: candidates,
          error: TimeoutException('Previously unavailable'),
        );
      }
      now = now.add(const Duration(seconds: 16));
      final restEndpoints = <Uri>[];
      final rest = XboardAuthService(
        requestRouter: router,
        endpointLoader: () async => candidates,
        diagnosticRecorder: (_, _) {},
        plansRequester: (endpoint, _) async {
          restEndpoints.add(endpoint);
          restStarted.complete();
          await restRelease.future;
          return const XboardLoginResponse(
            statusCode: 200,
            data: {'data': <Object?>[]},
          );
        },
      );
      final plans = rest.fetchPlans(
        endpoint: _primaryEndpoint,
        authData: 'Bearer fixture',
      );
      await restStarted.future.timeout(const Duration(seconds: 2));
      expect(restEndpoints.single.origin, _primaryEndpoint.origin);
      blockMutation = true;
      final mutation = operation == 'register_device'
          ? clientFor(_MemorySubscriptionV2ValueStore()).fetchProfile(
              endpoint: _primaryEndpoint,
              userToken: _token,
              appVersion: '1.9.0',
            )
          : _fixtureOperation(clientFor(store), operation);
      await mutationStarted.future.timeout(const Duration(seconds: 2));
      expect(server.endpoints.last.origin, _backupEndpoint.origin);
      await expectLater(
        clientFor(
          store,
        ).fetchNodes(endpoint: _primaryEndpoint, userToken: _token),
        throwsA(_subscriptionError('gateway_unavailable')),
      );
      expect(server.operations, ['login_device', operation]);
      mutationRelease.complete();
      restRelease.complete();
      await mutation;
      expect(await plans, isEmpty);
    });
  }

  test('HTTPS gateway failover never dispatches to HTTP', () async {
    final server = await _FakeSubscriptionV2Server.create()
      ..hosts = ['https://api.example.com', 'http://backup.example.com'];
    final store = _MemorySubscriptionV2ValueStore();
    await _fixtureLogin(_fixtureClient(server, store));
    final client = _fixtureClient(
      server,
      store,
      requester: (endpoint, envelope) async {
        await server.request(endpoint, envelope);
        throw TimeoutException('Simulated network failure');
      },
    );

    await expectLater(
      _fixtureProfile(client),
      throwsA(_subscriptionError('gateway_unavailable')),
    );
    expect(server.operations, ['login_device', 'issue_ticket']);
    expect(
      server.endpoints.every((endpoint) => endpoint.scheme == 'https'),
      isTrue,
    );
  });

  test('HTTPS profile never coalesces with an HTTP-origin exchange', () async {
    final server = await _FakeSubscriptionV2Server.create()
      ..hosts = ['http://api.example.com', 'https://backup.example.com'];
    final httpEndpoint = Uri.parse(server.hosts!.first);
    final httpsEndpoint = Uri.parse(server.hosts!.last);
    final store = _MemorySubscriptionV2ValueStore();
    await _fixtureClient(server, store).secureLogin(
      endpoint: httpsEndpoint,
      email: 'gray@example.com',
      password: 'correct-password',
      appVersion: '1.9.0',
      platform: 'android',
    );
    final started = Completer<void>();
    final release = Completer<void>();
    addTearDown(() {
      if (!release.isCompleted) release.complete();
    });
    final client = _fixtureClient(
      server,
      store,
      requester: (endpoint, envelope) async {
        final response = await server.request(endpoint, envelope);
        if (endpoint.scheme == 'http' &&
            server.operations.last == 'issue_ticket') {
          started.complete();
          await release.future;
        }
        return response;
      },
    );
    final httpProfile = _fixtureProfile(client, endpoint: httpEndpoint);
    await started.future.timeout(const Duration(seconds: 2));
    final httpsProfile = await _fixtureProfile(
      client,
      endpoint: httpsEndpoint,
    ).timeout(const Duration(seconds: 2));
    expect(utf8.decode(httpsProfile!.bytes), server.profile);
    expect(server.endpoints.skip(2).map((endpoint) => endpoint.scheme), [
      'https',
      'https',
    ]);
    release.complete();
    expect(utf8.decode((await httpProfile)!.bytes), server.profile);
    expect(server.ticketSequence, 2);
  });

  test('local missing credentials never reserve recovery probes', () async {
    var now = DateTime.utc(2026, 10, 7);
    final router = ApiRequestRouter(now: () => now);
    final server = await _FakeSubscriptionV2Server.create()
      ..hosts = _trustedHosts;
    final store = _MemorySubscriptionV2ValueStore();
    final candidates = _trustedHosts.map(Uri.parse).toList();
    for (final endpoint in candidates) {
      router.recordFailure(
        endpoint,
        candidates: candidates,
        error: TimeoutException('Previously unavailable'),
      );
    }
    now = now.add(const Duration(seconds: 16));
    SubscriptionV2Client newClient() =>
        _fixtureClient(server, store, requestRouter: router);
    await Future.wait([
      expectLater(
        _fixtureProfile(newClient()),
        throwsA(_subscriptionError('device_not_registered')),
      ),
      expectLater(
        newClient().fetchSummary(endpoint: _primaryEndpoint, userToken: _token),
        throwsA(_subscriptionError('device_not_registered')),
      ),
      expectLater(
        newClient().resetSecurity(
          endpoint: _primaryEndpoint,
          userToken: _token,
        ),
        throwsA(_subscriptionError('device_not_registered')),
      ),
    ]);
    expect(server.operations, isEmpty);

    expect(await _fixtureLogin(newClient()), isNotNull);
    expect(server.operations, ['login_device']);
    expect(server.endpoints.single.origin, _primaryEndpoint.origin);
  });

  test('router output cannot bypass HTTPS policy', () async {
    final server = await _FakeSubscriptionV2Server.create()
      ..hosts = ['https://api.example.com', 'http://backup.example.com'];
    final client = _fixtureClient(
      server,
      _MemorySubscriptionV2ValueStore(),
      requestRouter: _UntrustedGatewayRouter(
        Uri.parse('http://backup.example.com/api/v2/g/test-gateway'),
      ),
    );

    await expectLater(
      _fixtureLogin(client),
      throwsA(_subscriptionError('untrusted_gateway')),
    );
    expect(server.operations, isEmpty);
  });

  for (final rejection in [
    'invalid_credentials',
    'rate_limited',
    'invalid_server_signature',
    'http_403',
    'http_429',
  ]) {
    test('terminal $rejection releases the recovery probe', () async {
      var now = DateTime.utc(2026, 10, 7);
      final router = ApiRequestRouter(now: () => now);
      final server = await _FakeSubscriptionV2Server.create()
        ..hosts = _trustedHosts;
      final store = _MemorySubscriptionV2ValueStore();
      Future<Map<String, Object?>> request(
        Uri endpoint,
        Map<String, Object?> envelope,
      ) async {
        final response = await server.request(endpoint, envelope);
        if (server.operations.last == 'get_summary') {
          if (rejection == 'invalid_server_signature') {
            response['signature'] = _encode(List<int>.filled(64, 0));
          } else if (rejection.startsWith('http_')) {
            throw SubscriptionV2Exception(
              'gateway_unavailable',
              statusCode: int.parse(rejection.substring(5)),
            );
          }
        }
        return response;
      }

      SubscriptionV2Client newClient() => _fixtureClient(
        server,
        store,
        requester: request,
        requestRouter: router,
      );
      await _fixtureLogin(newClient());
      if (rejection == 'invalid_credentials' || rejection == 'rate_limited') {
        server.operationRejections['get_summary'] = rejection;
      }
      final candidates = _trustedHosts.map(Uri.parse).toList();
      for (final endpoint in candidates) {
        router.recordFailure(
          endpoint,
          candidates: candidates,
          error: TimeoutException('Previously unavailable'),
        );
      }
      now = now.add(const Duration(seconds: 16));
      await expectLater(
        newClient().fetchSummary(endpoint: _primaryEndpoint, userToken: _token),
        throwsA(
          _subscriptionError(
            rejection.startsWith('http_') ? 'gateway_unavailable' : rejection,
          ),
        ),
      );
      expect(server.operations, ['login_device', 'get_summary']);
      expect(server.endpoints.last.origin, _primaryEndpoint.origin);

      expect(await _fixtureLogin(newClient()), isNotNull);
      expect(server.endpoints.last.origin, _primaryEndpoint.origin);
      expect(server.operations, [
        'login_device',
        'get_summary',
        'login_device',
      ]);
    });
  }

  for (final rejection in [
    'invalid_credentials',
    'invalid_server_signature',
    'http_403',
  ]) {
    test('old $rejection cannot release a new recovery probe', () async {
      var now = DateTime.utc(2026, 10, 7);
      final router = ApiRequestRouter(now: () => now);
      final server = await _FakeSubscriptionV2Server.create()
        ..hosts = _trustedHosts;
      final store = _MemorySubscriptionV2ValueStore();
      final oldStarted = Completer<void>();
      final oldRelease = Completer<void>();
      final probeStarted = Completer<void>();
      final probeRelease = Completer<void>();
      addTearDown(() {
        if (!oldRelease.isCompleted) oldRelease.complete();
        if (!probeRelease.isCompleted) probeRelease.complete();
      });
      var summaryRequests = 0;
      Future<Map<String, Object?>> request(
        Uri endpoint,
        Map<String, Object?> envelope,
      ) async {
        final response = await server.request(endpoint, envelope);
        if (server.operations.last == 'get_summary') {
          if (++summaryRequests == 1) {
            oldStarted.complete();
            await oldRelease.future;
            if (rejection == 'invalid_server_signature') {
              response['signature'] = _encode(List<int>.filled(64, 0));
            } else if (rejection == 'http_403') {
              throw const SubscriptionV2Exception(
                'gateway_unavailable',
                statusCode: 403,
              );
            }
          } else if (summaryRequests == 2) {
            probeStarted.complete();
            await probeRelease.future;
          }
        }
        return response;
      }

      SubscriptionV2Client newClient() => _fixtureClient(
        server,
        store,
        requester: request,
        requestRouter: router,
      );
      await _fixtureLogin(newClient());
      if (rejection == 'invalid_credentials') {
        server.operationRejections['get_summary'] = rejection;
      }
      final old = newClient().fetchSummary(
        endpoint: _primaryEndpoint,
        userToken: _token,
      );
      await oldStarted.future.timeout(const Duration(seconds: 2));
      server.operationRejections.remove('get_summary');
      router.recordFailure(
        _primaryEndpoint,
        candidates: _trustedHosts.map(Uri.parse),
        error: TimeoutException('Concurrent request failed'),
      );
      now = now.add(const Duration(seconds: 16));
      final probe = newClient().fetchSummary(
        endpoint: _primaryEndpoint,
        userToken: _token,
      );
      await probeStarted.future.timeout(const Duration(seconds: 2));
      expect(server.endpoints.last.origin, _primaryEndpoint.origin);
      oldRelease.complete();
      await expectLater(
        old,
        throwsA(
          _subscriptionError(
            rejection == 'http_403' ? 'gateway_unavailable' : rejection,
          ),
        ),
      );

      expect(await _fixtureLogin(newClient()), isNotNull);
      expect(server.endpoints.last.origin, _backupEndpoint.origin);
      probeRelease.complete();
      expect(await probe, isNotEmpty);
    });
  }

  test('router output cannot expand the verified gateway set', () async {
    final server = await _FakeSubscriptionV2Server.create()
      ..hosts = _trustedHosts;
    final client = _fixtureClient(
      server,
      _MemorySubscriptionV2ValueStore(),
      requestRouter: _UntrustedGatewayRouter(),
    );

    await expectLater(
      _fixtureLogin(client),
      throwsA(_subscriptionError('untrusted_gateway')),
    );
    expect(server.operations, isEmpty);
  });

  for (final totalBudget in [false, true]) {
    test(
      'cancels Dio at the ${totalBudget ? 'operation' : 'request'} deadline',
      () async {
        final server = await _FakeSubscriptionV2Server.create()
          ..hosts = _trustedHosts;
        final store = _MemorySubscriptionV2ValueStore();
        await _fixtureLogin(_fixtureClient(server, store));
        final adapter = _BlockedGatewayAdapter();
        final dio = Dio()..httpClientAdapter = adapter;
        addTearDown(() => dio.close(force: true));
        final client = _fixtureClient(
          server,
          store,
          dio: dio,
          gatewayRequestTimeout: Duration(
            milliseconds: totalBudget ? 5000 : 250,
          ),
          operationTimeout: Duration(milliseconds: totalBudget ? 250 : 5000),
        );
        final stopwatch = Stopwatch()..start();

        await expectLater(
          _fixtureProfile(client),
          throwsA(
            _subscriptionError('gateway_unavailable').having(
              (error) => error.diagnostic?.failure,
              'reason',
              ApiNetworkFailure.timeout,
            ),
          ),
        );
        await Future<void>.delayed(Duration.zero);
        expect(stopwatch.elapsed, lessThan(const Duration(seconds: 2)));
        expect(adapter.requests, hasLength(totalBudget ? 1 : 2));
        expect(adapter.cancellations, adapter.requests.length);
        expect(
          adapter.requests.map((request) => request.followRedirects),
          everyElement(isFalse),
        );
        expect(server.operations, ['login_device']);
      },
    );
  }

  test(
    'Dio cancellation leaves the trusted fallback transport usable',
    () async {
      final server = await _FakeSubscriptionV2Server.create()
        ..hosts = _trustedHosts;
      final store = _MemorySubscriptionV2ValueStore();
      await _fixtureLogin(_fixtureClient(server, store));
      final adapter = _BlockedGatewayAdapter(fallbackServer: server);
      final dio = Dio()..httpClientAdapter = adapter;
      addTearDown(() => dio.close(force: true));
      final client = _fixtureClient(
        server,
        store,
        dio: dio,
        gatewayRequestTimeout: const Duration(milliseconds: 250),
        operationTimeout: const Duration(seconds: 2),
      );

      final profile = await _fixtureProfile(client);

      expect(utf8.decode(profile!.bytes), server.profile);
      expect(adapter.requests.map((request) => request.uri.host), [
        'api.example.com',
        'backup.example.com',
        'backup.example.com',
      ]);
      expect(adapter.cancellations, 1);
      expect(server.operations, [
        'login_device',
        'issue_ticket',
        'redeem_ticket',
      ]);
    },
  );

  test(
    'ignores late registration responses after the operation deadline',
    () async {
      final server = await _FakeSubscriptionV2Server.create();
      final store = _MemorySubscriptionV2ValueStore();
      final started = Completer<void>();
      final release = Completer<void>();
      final client = _fixtureClient(
        server,
        store,
        operationTimeout: const Duration(milliseconds: 250),
        requester: (endpoint, envelope) async {
          final response = await server.request(endpoint, envelope);
          if (server.operations.last == 'register_device' &&
              !started.isCompleted) {
            started.complete();
            await release.future;
          }
          return response;
        },
      );
      final result = client.fetchProfile(
        endpoint: _primaryEndpoint,
        userToken: _token,
        appVersion: '1.9.0',
      );
      final assertion = expectLater(
        result,
        throwsA(_subscriptionError('gateway_unavailable')),
      );
      await started.future;
      await assertion;
      final beforeRelease = Map<String, String>.from(store.values);
      release.complete();
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(store.values, beforeRelease);
      expect(store.values, hasLength(1));
      expect(server.operations, ['register_device']);
      final next = await client.fetchProfile(
        endpoint: _primaryEndpoint,
        userToken: _token,
        appVersion: '1.9.0',
      );
      expect(utf8.decode(next!.bytes), server.profile);
      expect(server.operations, [
        'register_device',
        'register_device',
        'issue_ticket',
        'redeem_ticket',
      ]);
    },
  );

  test(
    'does not create a device seed after a timed-out storage read',
    () async {
      final server = await _FakeSubscriptionV2Server.create();
      final store = _DelayedReadSubscriptionV2ValueStore();
      final client = _fixtureClient(
        server,
        store,
        operationTimeout: const Duration(milliseconds: 250),
      );

      await expectLater(
        client.fetchProfile(
          endpoint: _primaryEndpoint,
          userToken: _token,
          appVersion: '1.9.0',
        ),
        throwsA(_subscriptionError('gateway_unavailable')),
      );
      store.release.complete();
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(store.values, isEmpty);
      expect(server.operations, isEmpty);
    },
  );
}

const _token = '0123456789abcdef0123456789abcdef';
const _trustedHosts = ['https://api.example.com', 'https://backup.example.com'];
final _primaryEndpoint = Uri.parse(_trustedHosts.first);
final _backupEndpoint = Uri.parse(_trustedHosts.last);

TypeMatcher<SubscriptionV2Exception> _subscriptionError(String code) =>
    isA<SubscriptionV2Exception>().having((error) => error.code, 'code', code);

SubscriptionV2Client _fixtureClient(
  _FakeSubscriptionV2Server server,
  SubscriptionV2ValueStore store, {
  SubscriptionV2Requester? requester,
  Dio? dio,
  ApiDiagnosticRecorder? diagnosticRecorder,
  ApiRequestRouter? requestRouter,
  Duration gatewayRequestTimeout = const Duration(seconds: 20),
  Duration operationTimeout = const Duration(seconds: 45),
}) => SubscriptionV2Client(
  apiHealthService: _healthService(server.config),
  valueStore: store,
  requester: dio == null ? requester ?? server.request : null,
  dio: dio,
  now: () => DateTime.utc(2026, 8, 31, 12),
  diagnosticRecorder: diagnosticRecorder ?? (_, _) {},
  requestRouter: requestRouter ?? ApiRequestRouter(),
  gatewayRequestTimeout: gatewayRequestTimeout,
  operationTimeout: operationTimeout,
);

Future<SubscriptionV2Login?> _fixtureLogin(SubscriptionV2Client client) =>
    client.secureLogin(
      endpoint: _primaryEndpoint,
      email: 'gray@example.com',
      password: 'correct-password',
      appVersion: '1.9.0',
      platform: 'android',
    );

Future<SubscriptionV2Profile?> _fixtureProfile(
  SubscriptionV2Client client, {
  Uri? endpoint,
}) => client.fetchProfile(
  endpoint: endpoint ?? _primaryEndpoint,
  userToken: _token,
  appVersion: '1.9.0',
  platform: 'android',
  allowTokenRegistration: false,
);

SubscriptionV2Client _sharedRouterClient(
  _FakeSubscriptionV2Server server,
  SubscriptionV2ValueStore store, {
  required SubscriptionV2Requester requester,
}) => SubscriptionV2Client(
  apiHealthService: _healthService(server.config),
  valueStore: store,
  requester: requester,
  now: () => DateTime.utc(2026, 8, 31, 12),
  diagnosticRecorder: (_, _) {},
);

Future<Object?> _fixtureOperation(
  SubscriptionV2Client client,
  String operation,
) => switch (operation) {
  'profile' => _fixtureProfile(client),
  'get_summary' => client.fetchSummary(
    endpoint: _primaryEndpoint,
    userToken: _token,
  ),
  'get_nodes' => client.fetchNodes(
    endpoint: _primaryEndpoint,
    userToken: _token,
  ),
  'reset_security' => client.resetSecurity(
    endpoint: _primaryEndpoint,
    userToken: _token,
  ),
  'login_device' => _fixtureLogin(client),
  _ => client.revokeDevice(endpoint: _primaryEndpoint, userToken: _token),
};

ApiHealthService _healthService(Map<String, Object?> config) {
  return ApiHealthService(
    configUrl: 'https://config.example/app.json',
    configLoader: (_) async => config,
  );
}

class _MemorySubscriptionV2ValueStore implements SubscriptionV2ValueStore {
  final values = <String, String>{};

  @override
  Future<void> delete(String key) async {
    values.remove(key);
  }

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async {
    values[key] = value;
  }
}

class _DelayedReadSubscriptionV2ValueStore
    extends _MemorySubscriptionV2ValueStore {
  final release = Completer<void>();

  @override
  Future<String?> read(String key) async {
    await release.future;
    return super.read(key);
  }
}

class _LocalHttpOverrides extends HttpOverrides {}

class _UntrustedGatewayRouter extends ApiRequestRouter {
  _UntrustedGatewayRouter([this.endpoint]);

  final Uri? endpoint;

  @override
  List<Uri> orderCandidates(
    Iterable<Uri> candidates, {
    Uri? preferred,
    Iterable<Uri>? eligibleCandidates,
    bool reserveRecoveryProbe = false,
  }) => [
    endpoint ?? Uri.parse('https://unlisted.example.com/api/v2/g/test-gateway'),
  ];
}

class _TemporaryPathProvider extends PathProviderPlatform {
  _TemporaryPathProvider(this.path);

  final String path;

  @override
  Future<String?> getApplicationSupportPath() async => path;
}

class _BlockedGatewayAdapter implements HttpClientAdapter {
  _BlockedGatewayAdapter({this.fallbackServer});

  final _FakeSubscriptionV2Server? fallbackServer;
  final requests = <RequestOptions>[];
  var cancellations = 0;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    if (fallbackServer case final server?
        when options.uri.host == 'backup.example.com') {
      final response = await server.request(
        options.uri,
        Map<String, Object?>.from(options.data as Map),
      );
      return ResponseBody.fromString(
        jsonEncode(response),
        200,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType],
        },
      );
    }
    await cancelFuture;
    cancellations++;
    throw DioException(requestOptions: options, type: DioExceptionType.cancel);
  }

  @override
  void close({bool force = false}) {}
}

class _FakeSubscriptionV2Server {
  _FakeSubscriptionV2Server._({
    required this.encryptionKeyPair,
    required this.encryptionPublicKey,
    required this.signingKeyPair,
    required this.signingPublicKey,
    required this.allowed,
    required this.loginRejectionCode,
  });

  static const keyId = 'test-key';
  static const gatewayPath = '/api/v2/g/test-gateway';

  final SimpleKeyPair encryptionKeyPair;
  final SimplePublicKey encryptionPublicKey;
  final SimpleKeyPair signingKeyPair;
  final SimplePublicKey signingPublicKey;
  final bool allowed;
  final String? loginRejectionCode;
  final operations = <String>[];
  final endpoints = <Uri>[];
  final envelopes = <Map<String, Object?>>[];
  final payloads = <Map<String, Object?>>[];
  final operationRejections = <String, String>{};
  final loginTokens = <String, String>{};
  List<String>? hosts;
  final redeemedTickets = <String>{};
  final tickets = <String>{};
  SimplePublicKey? devicePublicKey;
  var ticketSequence = 0;
  final profile = 'mixed-port: 7890\nproxies: []\nrules: []\n';

  static Future<_FakeSubscriptionV2Server> create({
    bool allowed = true,
    String? loginRejectionCode,
  }) async {
    final encryptionKeyPair = await X25519().newKeyPair();
    final signingKeyPair = await Ed25519().newKeyPair();
    return _FakeSubscriptionV2Server._(
      encryptionKeyPair: encryptionKeyPair,
      encryptionPublicKey: await encryptionKeyPair.extractPublicKey(),
      signingKeyPair: signingKeyPair,
      signingPublicKey: await signingKeyPair.extractPublicKey(),
      allowed: allowed,
      loginRejectionCode: loginRejectionCode,
    );
  }

  Map<String, Object?> get config => {
    'Authentication': 'FengWo',
    if (hosts != null) 'hosts': hosts,
    'subscriptionV2': {
      'enabled': true,
      'gatewayPath': gatewayPath,
      'keyId': keyId,
      'serverEncryptionPublicKey': _encode(encryptionPublicKey.bytes),
      'serverSigningPublicKey': _encode(signingPublicKey.bytes),
    },
  };

  Future<Map<String, Object?>> request(
    Uri endpoint,
    Map<String, Object?> envelope,
  ) async {
    expect(
      endpoint.toString(),
      isIn([
        for (final host in hosts ?? ['https://api.example.com'])
          '${Uri.parse(host).origin}$gatewayPath',
      ]),
    );
    final requestId = envelope['request_id']! as String;
    final remotePublicKey = SimplePublicKey(
      _decode(envelope['epk']! as String),
      type: KeyPairType.x25519,
    );
    final shared = await X25519().sharedSecretKey(
      keyPair: encryptionKeyPair,
      remotePublicKey: remotePublicKey,
    );
    final requestKey = await _deriveKey(shared, 'request', requestId);
    final plaintext = await AesGcm.with256bits().decrypt(
      SecretBox(
        _decode(envelope['ciphertext']! as String),
        nonce: _decode(envelope['nonce']! as String),
        mac: Mac(_decode(envelope['tag']! as String)),
      ),
      secretKey: requestKey,
      aad: utf8.encode(
        canonicalSubscriptionV2Json({
          'epk': envelope['epk'],
          'kid': keyId,
          'request_id': requestId,
          'v': 1,
        }),
      ),
    );
    final payload = (jsonDecode(utf8.decode(plaintext)) as Map).map(
      (key, value) => MapEntry(key.toString(), value),
    );
    final operation = payload['op']! as String;
    operations.add(operation);
    endpoints.add(endpoint);
    envelopes.add(Map.from(envelope));
    payloads.add(payload);
    final responsePayload = await _handle(operation, payload);
    return _encryptResponse(shared, requestId, responsePayload);
  }

  Future<Map<String, Object?>> _handle(
    String operation,
    Map<String, Object?> payload,
  ) async {
    if (operation == 'login_device') {
      final publicKey = SimplePublicKey(
        _decode(payload['device_public_key']! as String),
        type: KeyPairType.ed25519,
      );
      await _verifyDeviceSignature(payload, publicKey);
      if (loginRejectionCode case final code?) {
        return {'status': 0, 'error': code};
      }
      if (!allowed) {
        return {'status': 0, 'error': 'not_in_gray_allowlist'};
      }
      if (payload['password'] != 'correct-password') {
        return {'status': 0, 'error': 'invalid_credentials'};
      }
      devicePublicKey = publicKey;
      return {
        'status': 1,
        'data': {
          'token': loginTokens[payload['email']] ?? _token,
          'auth_data': 'Bearer secure-session',
          'is_admin': false,
          'device_id': 'device-1',
          'device_expires_at': 2000000000,
          'subscription': _summary,
        },
      };
    }
    if (operation == 'register_device') {
      final publicKey = SimplePublicKey(
        _decode(payload['device_public_key']! as String),
        type: KeyPairType.ed25519,
      );
      await _verifyDeviceSignature(payload, publicKey);
      if (!allowed) {
        return {'status': 0, 'error': 'not_in_gray_allowlist'};
      }
      devicePublicKey = publicKey;
      return {
        'status': 1,
        'data': {'device_id': 'device-1', 'expires_at': 2000000000},
      };
    }
    final publicKey = devicePublicKey;
    if (publicKey == null) {
      return {'status': 0, 'error': 'device_not_registered'};
    }
    await _verifyDeviceSignature(payload, publicKey);
    if (operationRejections[operation] case final code?) {
      return {'status': 0, 'error': code};
    }
    if (operation == 'revoke_device') {
      devicePublicKey = null;
      return {
        'status': 1,
        'data': {'revoked': true},
      };
    }
    if (operation == 'issue_ticket') {
      final ticket = 'ticket-${++ticketSequence}';
      tickets.add(ticket);
      return {
        'status': 1,
        'data': {'ticket': ticket, 'expires_at': 2000000000},
      };
    }
    if (operation == 'get_summary') {
      return {'status': 1, 'data': _summary};
    }
    if (operation == 'get_nodes') {
      return {
        'status': 1,
        'data': {
          'nodes': [
            {
              'id': 1,
              'name': '测试节点',
              'type': 'anytls',
              'rate': 1,
              'tags': ['HK', 'VIP'],
              'is_online': true,
              'last_check_at': 1788177600,
            },
          ],
        },
      };
    }
    if (operation == 'reset_security') {
      return {
        'status': 1,
        'data': {'reset': true},
      };
    }
    final ticket = payload['ticket']?.toString() ?? '';
    if (operation != 'redeem_ticket' || !tickets.remove(ticket)) {
      return {'status': 0, 'error': 'invalid_ticket'};
    }
    redeemedTickets.add(ticket);
    return {
      'status': 1,
      'data': {
        'content_type': 'application/yaml',
        'content_encoding': 'base64url',
        'profile': _encode(utf8.encode(profile)),
        'issued_at': 1788177600,
      },
    };
  }

  Map<String, Object?> get _summary => {
    'plan_id': 7,
    'email': 'gray@example.com',
    'expired_at': null,
    'u': 1,
    'd': 2,
    'transfer_enable': 100,
    'device_limit': 3,
    'speed_limit': null,
    'next_reset_at': null,
    'reset_day': 0,
    'plan': {'id': 7, 'name': '安全套餐', 'transfer_enable': 100},
  };

  Future<void> _verifyDeviceSignature(
    Map<String, Object?> payload,
    SimplePublicKey publicKey,
  ) async {
    final unsigned = Map<String, Object?>.from(payload);
    final signature = _decode(unsigned.remove('signature')! as String);
    final valid = await Ed25519().verify(
      utf8.encode(canonicalSubscriptionV2Json(unsigned)),
      signature: Signature(signature, publicKey: publicKey),
    );
    expect(valid, isTrue);
  }

  Future<Map<String, Object?>> _encryptResponse(
    SecretKey shared,
    String requestId,
    Map<String, Object?> payload,
  ) async {
    final responseKey = await _deriveKey(shared, 'response', requestId);
    final encrypted = await AesGcm.with256bits().encrypt(
      utf8.encode(jsonEncode(payload)),
      secretKey: responseKey,
      nonce: List<int>.generate(12, (index) => index + 1),
      aad: utf8.encode(
        canonicalSubscriptionV2Json({
          'kid': keyId,
          'request_id': requestId,
          'v': 1,
        }),
      ),
    );
    final response = <String, Object?>{
      'v': 1,
      'kid': keyId,
      'request_id': requestId,
      'nonce': _encode(encrypted.nonce),
      'ciphertext': _encode(encrypted.cipherText),
      'tag': _encode(encrypted.mac.bytes),
    };
    final signature = await Ed25519().sign(
      utf8.encode(canonicalSubscriptionV2Json(response)),
      keyPair: signingKeyPair,
    );
    response['signature'] = _encode(signature.bytes);
    return response;
  }

  Future<SecretKey> _deriveKey(
    SecretKey shared,
    String direction,
    String requestId,
  ) {
    return Hkdf(hmac: Hmac.sha256(), outputLength: 32).deriveKey(
      secretKey: shared,
      nonce: dart_crypto.sha256
          .convert(utf8.encode('fengwo-subscription-v2|$keyId'))
          .bytes,
      info: utf8.encode('fengwo-subscription-v2/$direction|$requestId'),
    );
  }
}

String _encode(List<int> value) => base64UrlEncode(value).replaceAll('=', '');

List<int> _decode(String value) => base64Url.decode(base64Url.normalize(value));

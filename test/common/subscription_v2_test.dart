import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart' as dart_crypto;
import 'package:cryptography/cryptography.dart';
import 'package:fl_clash/common/api_health.dart';
import 'package:fl_clash/common/subscription_v2.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

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
        isA<SubscriptionV2Exception>().having(
          (error) => error.code,
          'code',
          'invalid_server_signature',
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
}

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

class _FakeSubscriptionV2Server {
  _FakeSubscriptionV2Server._({
    required this.encryptionKeyPair,
    required this.encryptionPublicKey,
    required this.signingKeyPair,
    required this.signingPublicKey,
    required this.allowed,
  });

  static const keyId = 'test-key';
  static const gatewayPath = '/api/v2/g/test-gateway';

  final SimpleKeyPair encryptionKeyPair;
  final SimplePublicKey encryptionPublicKey;
  final SimpleKeyPair signingKeyPair;
  final SimplePublicKey signingPublicKey;
  final bool allowed;
  final operations = <String>[];
  final redeemedTickets = <String>{};
  final tickets = <String>{};
  SimplePublicKey? devicePublicKey;
  var ticketSequence = 0;
  final profile = 'mixed-port: 7890\nproxies: []\nrules: []\n';

  static Future<_FakeSubscriptionV2Server> create({bool allowed = true}) async {
    final encryptionKeyPair = await X25519().newKeyPair();
    final signingKeyPair = await Ed25519().newKeyPair();
    return _FakeSubscriptionV2Server._(
      encryptionKeyPair: encryptionKeyPair,
      encryptionPublicKey: await encryptionKeyPair.extractPublicKey(),
      signingKeyPair: signingKeyPair,
      signingPublicKey: await signingKeyPair.extractPublicKey(),
      allowed: allowed,
    );
  }

  Map<String, Object?> get config => {
    'Authentication': 'FengWo',
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
    expect(endpoint.toString(), 'https://api.example.com$gatewayPath');
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
          'token': '0123456789abcdef0123456789abcdef',
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

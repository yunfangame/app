import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as dart_crypto;
import 'package:cryptography/cryptography.dart';
import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api_health.dart';
import 'local_secret_store.dart';

const _subscriptionV2Version = 1;
const _deviceSeedKey = 'subscription_v2.device_seed';
const _credentialKeyPrefix = 'subscription_v2.credential.';
const subscriptionV2ProfileScheme = 'fengwo-v2';

bool isSubscriptionV2ProfileSource(String value) =>
    Uri.tryParse(value)?.scheme == subscriptionV2ProfileScheme;

bool isLegacyXboardSubscriptionProfileSource(String value) {
  final uri = Uri.tryParse(value);
  if (uri == null ||
      !uri.isAbsolute ||
      (uri.scheme != 'http' && uri.scheme != 'https') ||
      uri.host.isEmpty ||
      uri.pathSegments.length != 2 ||
      uri.pathSegments.first != 'sakula') {
    return false;
  }
  return RegExp(r'^[0-9a-fA-F]{32}$').hasMatch(uri.pathSegments.last);
}

class SubscriptionV2Exception implements Exception {
  const SubscriptionV2Exception(this.code);

  final String code;

  @override
  String toString() => 'SubscriptionV2Exception($code)';
}

class SubscriptionV2RemoteConfig {
  const SubscriptionV2RemoteConfig({
    required this.gatewayPath,
    required this.keyId,
    required this.serverEncryptionPublicKey,
    required this.serverSigningPublicKey,
  });

  final String gatewayPath;
  final String keyId;
  final List<int> serverEncryptionPublicKey;
  final List<int> serverSigningPublicKey;
}

class SubscriptionV2Profile {
  const SubscriptionV2Profile({required this.bytes, required this.sourceId});

  final Uint8List bytes;
  final String sourceId;
}

class SubscriptionV2Login {
  const SubscriptionV2Login({
    required this.endpoint,
    required this.token,
    required this.authData,
    required this.isAdmin,
    required this.subscription,
    required this.rawData,
  });

  final Uri endpoint;
  final String token;
  final String authData;
  final bool isAdmin;
  final Map<String, Object?> subscription;
  final Map<String, Object?> rawData;
}

abstract interface class SubscriptionV2ValueStore {
  Future<String?> read(String key);

  Future<void> write(String key, String value);

  Future<void> delete(String key);
}

class SecureSubscriptionV2ValueStore implements SubscriptionV2ValueStore {
  SecureSubscriptionV2ValueStore({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);

  @override
  Future<void> delete(String key) => _storage.delete(key: key);
}

class PlatformSubscriptionV2ValueStore implements SubscriptionV2ValueStore {
  PlatformSubscriptionV2ValueStore({SecretStringStore? store})
    : _store = store ?? createPlatformSecretStringStore();

  final SecretStringStore _store;

  @override
  Future<String?> read(String key) => _store.read(key);

  @override
  Future<void> write(String key, String value) => _store.write(key, value);

  @override
  Future<void> delete(String key) => _store.delete(key);
}

class LocalDebugSubscriptionV2ValueStore implements SubscriptionV2ValueStore {
  LocalDebugSubscriptionV2ValueStore({
    Future<SharedPreferences> Function()? preferencesLoader,
  }) : _preferencesLoader = preferencesLoader ?? SharedPreferences.getInstance;

  static const _keyPrefix = 'subscription_v2.debug.';

  final Future<SharedPreferences> Function() _preferencesLoader;

  @override
  Future<String?> read(String key) async {
    final preferences = await _preferencesLoader();
    return preferences.getString('$_keyPrefix$key');
  }

  @override
  Future<void> write(String key, String value) async {
    final preferences = await _preferencesLoader();
    await preferences.setString('$_keyPrefix$key', value);
  }

  @override
  Future<void> delete(String key) async {
    final preferences = await _preferencesLoader();
    await preferences.remove('$_keyPrefix$key');
  }
}

SubscriptionV2ValueStore createSubscriptionV2ValueStore({
  bool? useLocalDebugStorage,
}) {
  return useLocalDebugStorage == true
      ? LocalDebugSubscriptionV2ValueStore()
      : PlatformSubscriptionV2ValueStore();
}

typedef SubscriptionV2Requester =
    Future<Map<String, Object?>> Function(
      Uri endpoint,
      Map<String, Object?> envelope,
    );

class SubscriptionV2Client {
  SubscriptionV2Client({
    ApiHealthService? apiHealthService,
    Dio? dio,
    SubscriptionV2ValueStore? valueStore,
    SubscriptionV2Requester? requester,
    DateTime Function()? now,
    Random? random,
  }) : _apiHealthService = apiHealthService ?? ApiHealthService(),
       _dio =
           dio ??
           Dio(
             BaseOptions(
               connectTimeout: const Duration(seconds: 5),
               sendTimeout: const Duration(seconds: 5),
               receiveTimeout: const Duration(seconds: 10),
             ),
           ),
       _valueStore = valueStore ?? createSubscriptionV2ValueStore(),
       _requester = requester,
       _now = now ?? DateTime.now,
       _random = random ?? Random.secure();

  final ApiHealthService _apiHealthService;
  final Dio _dio;
  final SubscriptionV2ValueStore _valueStore;
  final SubscriptionV2Requester? _requester;
  final DateTime Function() _now;
  final Random _random;

  Future<void> clearCredential(String userToken) =>
      _valueStore.delete(_credentialKey(userToken));

  Future<void> revokeDevice({
    required Uri endpoint,
    required String userToken,
  }) async {
    final credentialKey = _credentialKey(userToken);
    try {
      final config = parseSubscriptionV2RemoteConfig(
        await _apiHealthService.loadConfig(),
      );
      if (config == null) return;
      final gateway = _buildGatewayUri(endpoint, config.gatewayPath);
      final credential = await _loadCredential(credentialKey, config, gateway);
      if (credential == null) return;
      final identity = await _loadIdentity();
      await _sendSigned(config, gateway, identity, {
        'op': 'revoke_device',
        'timestamp': _timestamp,
        'nonce': _randomBase64(18),
        'device_id': credential.deviceId,
      });
    } finally {
      await _valueStore.delete(credentialKey);
    }
  }

  Future<SubscriptionV2Profile?> fetchProfile({
    required Uri endpoint,
    required String userToken,
    required String appVersion,
    String? platform,
    bool allowTokenRegistration = true,
  }) async {
    final config = parseSubscriptionV2RemoteConfig(
      await _apiHealthService.loadConfig(),
    );
    if (config == null) return null;
    final gateway = _buildGatewayUri(endpoint, config.gatewayPath);
    final identity = await _loadIdentity();
    final credentialKey = _credentialKey(userToken);
    var credential = await _loadCredential(credentialKey, config, gateway);
    try {
      if (credential == null) {
        if (!allowTokenRegistration) {
          throw const SubscriptionV2Exception('device_not_registered');
        }
        credential = await _registerDevice(
          config: config,
          gateway: gateway,
          identity: identity,
          credentialKey: credentialKey,
          userToken: userToken,
          appVersion: appVersion,
          platform: platform ?? Platform.operatingSystem,
        );
      }
      return await _fetchWithCredential(
        config: config,
        gateway: gateway,
        identity: identity,
        credential: credential,
        userToken: userToken,
      );
    } on SubscriptionV2Exception catch (error) {
      if (error.code == 'not_in_gray_allowlist') return null;
      if (error.code != 'device_not_registered') rethrow;
      await _valueStore.delete(credentialKey);
      if (!allowTokenRegistration) rethrow;
      final registered = await _registerDevice(
        config: config,
        gateway: gateway,
        identity: identity,
        credentialKey: credentialKey,
        userToken: userToken,
        appVersion: appVersion,
        platform: platform ?? Platform.operatingSystem,
      );
      return _fetchWithCredential(
        config: config,
        gateway: gateway,
        identity: identity,
        credential: registered,
        userToken: userToken,
      );
    }
  }

  Future<SubscriptionV2Profile> _fetchWithCredential({
    required SubscriptionV2RemoteConfig config,
    required Uri gateway,
    required _SubscriptionV2Identity identity,
    required _SubscriptionV2Credential credential,
    required String userToken,
  }) async {
    final issued = await _sendSigned(config, gateway, identity, {
      'op': 'issue_ticket',
      'timestamp': _timestamp,
      'nonce': _randomBase64(18),
      'device_id': credential.deviceId,
    });
    final ticket = _requiredString(issued, 'ticket');
    final redeemed = await _sendSigned(config, gateway, identity, {
      'op': 'redeem_ticket',
      'timestamp': _timestamp,
      'nonce': _randomBase64(18),
      'device_id': credential.deviceId,
      'ticket': ticket,
    });
    if (_requiredString(redeemed, 'content_encoding') != 'base64url') {
      throw const SubscriptionV2Exception('unsupported_content_encoding');
    }
    final profileBytes = _decodeBase64Url(_requiredString(redeemed, 'profile'));
    if (profileBytes.isEmpty) {
      throw const SubscriptionV2Exception('empty_profile');
    }
    final tokenHash = dart_crypto.sha256
        .convert(utf8.encode(userToken))
        .toString()
        .substring(0, 24);
    return SubscriptionV2Profile(
      bytes: Uint8List.fromList(profileBytes),
      sourceId: '$subscriptionV2ProfileScheme://${config.keyId}/$tokenHash',
    );
  }

  Future<SubscriptionV2Login?> secureLogin({
    required Uri endpoint,
    required String email,
    required String password,
    required String appVersion,
    String? platform,
  }) async {
    final config = parseSubscriptionV2RemoteConfig(
      await _apiHealthService.loadConfig(),
    );
    if (config == null) return null;
    final gateway = _buildGatewayUri(endpoint, config.gatewayPath);
    final identity = await _loadIdentity();
    try {
      final data = await _sendSigned(config, gateway, identity, {
        'op': 'login_device',
        'timestamp': _timestamp,
        'nonce': _randomBase64(18),
        'email': email.trim(),
        'password': password,
        'device_public_key': _encodeBase64Url(identity.publicKey.bytes),
        'platform': platform ?? Platform.operatingSystem,
        'app_version': appVersion,
      });
      final token = _requiredString(data, 'token');
      final authData = _requiredString(data, 'auth_data');
      final deviceId = _requiredString(data, 'device_id');
      final deviceExpiresAt = _requiredInt(data, 'device_expires_at');
      final rawSubscription = data['subscription'];
      if (rawSubscription is! Map) {
        throw const SubscriptionV2Exception('invalid_subscription');
      }
      final credential = _SubscriptionV2Credential(
        deviceId: deviceId,
        expiresAt: deviceExpiresAt,
        keyId: config.keyId,
        gateway: gateway.toString(),
      );
      await _valueStore.write(
        _credentialKey(token),
        jsonEncode(credential.toJson()),
      );
      return SubscriptionV2Login(
        endpoint: endpoint,
        token: token,
        authData: authData,
        isAdmin: data['is_admin'] == true || data['is_admin'] == 1,
        subscription: rawSubscription.map(
          (key, value) => MapEntry(key.toString(), value),
        ),
        rawData: Map.unmodifiable(data),
      );
    } on SubscriptionV2Exception catch (error) {
      if (error.code == 'not_in_gray_allowlist') return null;
      rethrow;
    }
  }

  Future<Map<String, Object?>> fetchSummary({
    required Uri endpoint,
    required String userToken,
  }) {
    return _sendWithStoredCredential(
      endpoint: endpoint,
      userToken: userToken,
      operation: 'get_summary',
    );
  }

  Future<void> resetSecurity({
    required Uri endpoint,
    required String userToken,
  }) async {
    final data = await _sendWithStoredCredential(
      endpoint: endpoint,
      userToken: userToken,
      operation: 'reset_security',
    );
    if (data['reset'] != true) {
      throw const SubscriptionV2Exception('reset_failed');
    }
  }

  Future<Map<String, Object?>> _sendWithStoredCredential({
    required Uri endpoint,
    required String userToken,
    required String operation,
  }) async {
    final config = parseSubscriptionV2RemoteConfig(
      await _apiHealthService.loadConfig(),
    );
    if (config == null) {
      throw const SubscriptionV2Exception('secure_config_disabled');
    }
    final gateway = _buildGatewayUri(endpoint, config.gatewayPath);
    final credential = await _loadCredential(
      _credentialKey(userToken),
      config,
      gateway,
    );
    if (credential == null) {
      throw const SubscriptionV2Exception('device_not_registered');
    }
    final identity = await _loadIdentity();
    return _sendSigned(config, gateway, identity, {
      'op': operation,
      'timestamp': _timestamp,
      'nonce': _randomBase64(18),
      'device_id': credential.deviceId,
    });
  }

  Future<_SubscriptionV2Credential> _registerDevice({
    required SubscriptionV2RemoteConfig config,
    required Uri gateway,
    required _SubscriptionV2Identity identity,
    required String credentialKey,
    required String userToken,
    required String appVersion,
    required String platform,
  }) async {
    final data = await _sendSigned(config, gateway, identity, {
      'op': 'register_device',
      'timestamp': _timestamp,
      'nonce': _randomBase64(18),
      'user_token': userToken,
      'device_public_key': _encodeBase64Url(identity.publicKey.bytes),
      'platform': platform,
      'app_version': appVersion,
    });
    final credential = _SubscriptionV2Credential(
      deviceId: _requiredString(data, 'device_id'),
      expiresAt: _requiredInt(data, 'expires_at'),
      keyId: config.keyId,
      gateway: gateway.toString(),
    );
    await _valueStore.write(credentialKey, jsonEncode(credential.toJson()));
    return credential;
  }

  Future<Map<String, Object?>> _sendSigned(
    SubscriptionV2RemoteConfig config,
    Uri gateway,
    _SubscriptionV2Identity identity,
    Map<String, Object?> payload,
  ) async {
    final signature = await Ed25519().sign(
      utf8.encode(canonicalSubscriptionV2Json(payload)),
      keyPair: identity.keyPair,
    );
    final signed = Map<String, Object?>.from(payload)
      ..['signature'] = _encodeBase64Url(signature.bytes);
    return _sendEncrypted(config, gateway, signed);
  }

  Future<Map<String, Object?>> _sendEncrypted(
    SubscriptionV2RemoteConfig config,
    Uri gateway,
    Map<String, Object?> payload,
  ) async {
    final exchange = X25519();
    final ephemeral = await exchange.newKeyPair();
    final ephemeralPublic = await ephemeral.extractPublicKey();
    final shared = await exchange.sharedSecretKey(
      keyPair: ephemeral,
      remotePublicKey: SimplePublicKey(
        config.serverEncryptionPublicKey,
        type: KeyPairType.x25519,
      ),
    );
    final requestId = _randomHex(16);
    final encodedPublicKey = _encodeBase64Url(ephemeralPublic.bytes);
    final requestAad = utf8.encode(
      canonicalSubscriptionV2Json({
        'epk': encodedPublicKey,
        'kid': config.keyId,
        'request_id': requestId,
        'v': _subscriptionV2Version,
      }),
    );
    final requestKey = await _deriveKey(
      shared,
      config.keyId,
      'request',
      requestId,
    );
    final nonce = _randomBytes(12);
    final encrypted = await AesGcm.with256bits().encrypt(
      utf8.encode(canonicalSubscriptionV2Json(payload)),
      secretKey: requestKey,
      nonce: nonce,
      aad: requestAad,
    );
    final envelope = <String, Object?>{
      'v': _subscriptionV2Version,
      'kid': config.keyId,
      'request_id': requestId,
      'epk': encodedPublicKey,
      'nonce': _encodeBase64Url(encrypted.nonce),
      'ciphertext': _encodeBase64Url(encrypted.cipherText),
      'tag': _encodeBase64Url(encrypted.mac.bytes),
    };
    final response = await (_requester ?? _request)(gateway, envelope);
    return _decryptResponse(
      config: config,
      requestId: requestId,
      shared: shared,
      response: response,
    );
  }

  Future<Map<String, Object?>> _decryptResponse({
    required SubscriptionV2RemoteConfig config,
    required String requestId,
    required SecretKey shared,
    required Map<String, Object?> response,
  }) async {
    if (response['v'] != _subscriptionV2Version ||
        response['kid'] != config.keyId ||
        response['request_id'] != requestId) {
      throw const SubscriptionV2Exception('invalid_response_envelope');
    }
    final signatureBytes = _decodeBase64Url(
      _requiredString(response, 'signature'),
    );
    final signed = Map<String, Object?>.from(response)..remove('signature');
    final verified = await Ed25519().verify(
      utf8.encode(canonicalSubscriptionV2Json(signed)),
      signature: Signature(
        signatureBytes,
        publicKey: SimplePublicKey(
          config.serverSigningPublicKey,
          type: KeyPairType.ed25519,
        ),
      ),
    );
    if (!verified) {
      throw const SubscriptionV2Exception('invalid_server_signature');
    }
    final responseKey = await _deriveKey(
      shared,
      config.keyId,
      'response',
      requestId,
    );
    final plaintext = await AesGcm.with256bits().decrypt(
      SecretBox(
        _decodeBase64Url(_requiredString(response, 'ciphertext')),
        nonce: _decodeBase64Url(_requiredString(response, 'nonce')),
        mac: Mac(_decodeBase64Url(_requiredString(response, 'tag'))),
      ),
      secretKey: responseKey,
      aad: utf8.encode(
        canonicalSubscriptionV2Json({
          'kid': config.keyId,
          'request_id': requestId,
          'v': _subscriptionV2Version,
        }),
      ),
    );
    final decoded = jsonDecode(utf8.decode(plaintext));
    if (decoded is! Map) {
      throw const SubscriptionV2Exception('invalid_response_payload');
    }
    final body = decoded.map((key, value) => MapEntry(key.toString(), value));
    if (body['status'] != 1) {
      throw SubscriptionV2Exception(
        body['error']?.toString() ?? 'subscription_v2_rejected',
      );
    }
    final data = body['data'];
    if (data is! Map) {
      throw const SubscriptionV2Exception('invalid_response_data');
    }
    return data.map((key, value) => MapEntry(key.toString(), value));
  }

  Future<Map<String, Object?>> _request(
    Uri endpoint,
    Map<String, Object?> envelope,
  ) async {
    final response = await _dio.postUri<Object?>(
      endpoint,
      data: envelope,
      options: Options(
        responseType: ResponseType.json,
        headers: const {'Cache-Control': 'no-store'},
        validateStatus: (status) =>
            status != null && status >= 200 && status < 600,
      ),
    );
    if ((response.statusCode ?? 0) < 200 ||
        (response.statusCode ?? 0) >= 300 ||
        response.data is! Map) {
      throw const SubscriptionV2Exception('gateway_unavailable');
    }
    return (response.data as Map).map(
      (key, value) => MapEntry(key.toString(), value),
    );
  }

  Future<_SubscriptionV2Identity> _loadIdentity() async {
    final stored = await _valueStore.read(_deviceSeedKey);
    List<int>? seed;
    if (stored != null) {
      try {
        final decoded = _decodeBase64Url(stored);
        if (decoded.length == 32) seed = decoded;
      } on FormatException {
        seed = null;
      }
    }
    if (seed == null) {
      final generated = await Ed25519().newKeyPair();
      seed = await generated.extractPrivateKeyBytes();
      await _valueStore.write(_deviceSeedKey, _encodeBase64Url(seed));
    }
    final keyPair = await Ed25519().newKeyPairFromSeed(seed);
    return _SubscriptionV2Identity(
      keyPair: keyPair,
      publicKey: await keyPair.extractPublicKey(),
    );
  }

  Future<_SubscriptionV2Credential?> _loadCredential(
    String key,
    SubscriptionV2RemoteConfig config,
    Uri gateway,
  ) async {
    final stored = await _valueStore.read(key);
    if (stored == null) return null;
    try {
      final decoded = jsonDecode(stored);
      if (decoded is! Map) return null;
      final credential = _SubscriptionV2Credential.fromJson(decoded);
      if (credential.keyId != config.keyId ||
          credential.gateway != gateway.toString() ||
          credential.expiresAt <= _timestamp + 30) {
        return null;
      }
      return credential;
    } catch (_) {
      return null;
    }
  }

  Future<SecretKey> _deriveKey(
    SecretKey shared,
    String keyId,
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

  Uri _buildGatewayUri(Uri endpoint, String gatewayPath) {
    final origin = endpoint.replace(path: '/', query: null, fragment: null);
    return origin.resolve(gatewayPath);
  }

  int get _timestamp => _now().toUtc().millisecondsSinceEpoch ~/ 1000;

  String _credentialKey(String userToken) =>
      '$_credentialKeyPrefix${dart_crypto.sha256.convert(utf8.encode(userToken))}';

  String _randomBase64(int length) => _encodeBase64Url(_randomBytes(length));

  String _randomHex(int length) => _randomBytes(
    length,
  ).map((value) => value.toRadixString(16).padLeft(2, '0')).join();

  List<int> _randomBytes(int length) =>
      List<int>.generate(length, (_) => _random.nextInt(256));
}

SubscriptionV2RemoteConfig? parseSubscriptionV2RemoteConfig(Object? source) {
  if (source is! Map) return null;
  final raw = source['subscriptionV2'] ?? source['subscription_v2'];
  if (raw is! Map || raw['enabled'] != true) return null;
  final gatewayPath = raw['gatewayPath']?.toString().trim() ?? '';
  final keyId = raw['keyId']?.toString().trim() ?? '';
  final encryptionKey = _decodeBase64Url(
    raw['serverEncryptionPublicKey']?.toString() ?? '',
  );
  final signingKey = _decodeBase64Url(
    raw['serverSigningPublicKey']?.toString() ?? '',
  );
  final gateway = Uri.tryParse(gatewayPath);
  if (gateway == null ||
      gateway.isAbsolute ||
      !gatewayPath.startsWith('/api/v2/') ||
      gateway.hasQuery ||
      gateway.hasFragment ||
      keyId.isEmpty ||
      encryptionKey.length != 32 ||
      signingKey.length != 32) {
    throw const FormatException('Invalid subscription V2 configuration');
  }
  return SubscriptionV2RemoteConfig(
    gatewayPath: gatewayPath,
    keyId: keyId,
    serverEncryptionPublicKey: List.unmodifiable(encryptionKey),
    serverSigningPublicKey: List.unmodifiable(signingKey),
  );
}

String canonicalSubscriptionV2Json(Object? value) =>
    jsonEncode(_sortCanonicalValue(value));

Object? _sortCanonicalValue(Object? value) {
  if (value is List) {
    return value.map(_sortCanonicalValue).toList(growable: false);
  }
  if (value is Map) {
    final entries = value.entries.toList()
      ..sort(
        (left, right) => left.key.toString().compareTo(right.key.toString()),
      );
    return <String, Object?>{
      for (final entry in entries)
        entry.key.toString(): _sortCanonicalValue(entry.value),
    };
  }
  return value;
}

String _encodeBase64Url(List<int> value) =>
    base64UrlEncode(value).replaceAll('=', '');

List<int> _decodeBase64Url(String value) {
  if (value.isEmpty || !RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(value)) {
    throw const FormatException('Invalid Base64URL value');
  }
  return base64Url.decode(base64Url.normalize(value));
}

String _requiredString(Map<String, Object?> data, String key) {
  final value = data[key];
  if (value is! String || value.isEmpty) {
    throw SubscriptionV2Exception('invalid_$key');
  }
  return value;
}

int _requiredInt(Map<String, Object?> data, String key) {
  final value = data[key];
  if (value is! int) {
    throw SubscriptionV2Exception('invalid_$key');
  }
  return value;
}

class _SubscriptionV2Identity {
  const _SubscriptionV2Identity({
    required this.keyPair,
    required this.publicKey,
  });

  final SimpleKeyPair keyPair;
  final SimplePublicKey publicKey;
}

class _SubscriptionV2Credential {
  const _SubscriptionV2Credential({
    required this.deviceId,
    required this.expiresAt,
    required this.keyId,
    required this.gateway,
  });

  factory _SubscriptionV2Credential.fromJson(Map source) {
    return _SubscriptionV2Credential(
      deviceId: source['device_id']?.toString() ?? '',
      expiresAt: source['expires_at'] is int ? source['expires_at'] as int : 0,
      keyId: source['key_id']?.toString() ?? '',
      gateway: source['gateway']?.toString() ?? '',
    );
  }

  final String deviceId;
  final int expiresAt;
  final String keyId;
  final String gateway;

  Map<String, Object?> toJson() => {
    'device_id': deviceId,
    'expires_at': expiresAt,
    'key_id': keyId,
    'gateway': gateway,
  };
}

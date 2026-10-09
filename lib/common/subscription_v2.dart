import 'dart:async';
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
import 'api_network_diagnostic.dart';
import 'api_request_router.dart';
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
  const SubscriptionV2Exception(
    this.code, {
    this.statusCode,
    this.diagnostic,
    this.requestRef,
  });

  final String code;
  final int? statusCode;
  final ApiNetworkDiagnostic? diagnostic;
  final String? requestRef;

  SubscriptionV2Exception withRequestRef(String value) =>
      SubscriptionV2Exception(
        code,
        statusCode: statusCode,
        diagnostic: diagnostic,
        requestRef: requestRef ?? value,
      );

  @override
  String toString() => 'SubscriptionV2Exception($code)';
}

class SubscriptionV2RemoteConfig {
  const SubscriptionV2RemoteConfig({
    required this.gatewayPath,
    required this.keyId,
    required this.serverEncryptionPublicKey,
    required this.serverSigningPublicKey,
    this.trustedGateways = const [],
    this.enforceGatewayTrust = false,
  });

  final String gatewayPath;
  final String keyId;
  final List<int> serverEncryptionPublicKey;
  final List<int> serverSigningPublicKey;
  final List<Uri> trustedGateways;
  final bool enforceGatewayTrust;
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

String subscriptionV2DiagnosticErrorCode(Object error) {
  if (error is SubscriptionV2Exception) {
    final normalized = error.code.trim().toLowerCase();
    return RegExp(r'^[a-z0-9_]{1,64}$').hasMatch(normalized)
        ? normalized
        : 'invalid_error_code';
  }
  if (error is DioException) return 'dio_${error.type.name}';
  if (error is FormatException) return 'invalid_format';
  if (error is ArgumentError) return 'invalid_argument';
  if (error is StateError) return 'state_error';
  if (error is SocketException) return 'socket_error';
  return 'unexpected_error';
}

class SubscriptionV2Client {
  SubscriptionV2Client({
    ApiHealthService? apiHealthService,
    Dio? dio,
    SubscriptionV2ValueStore? valueStore,
    SubscriptionV2Requester? requester,
    DateTime Function()? now,
    Random? random,
    ApiDiagnosticRecorder? diagnosticRecorder,
    ApiRequestRouter? requestRouter,
    Duration gatewayRequestTimeout = const Duration(seconds: 20),
    Duration operationTimeout = const Duration(seconds: 45),
  }) : assert(gatewayRequestTimeout > Duration.zero),
       assert(operationTimeout > Duration.zero),
       _apiHealthService = apiHealthService ?? ApiHealthService(),
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
       _random = random ?? Random.secure(),
       _gatewayRequestTimeout = gatewayRequestTimeout,
       _operationTimeout = operationTimeout,
       _requestRouter = requestRouter ?? ApiRequestRouter.shared,
       _shareProfileRequests =
           valueStore == null &&
           requester == null &&
           dio == null &&
           now == null &&
           random == null &&
           gatewayRequestTimeout == const Duration(seconds: 20) &&
           operationTimeout == const Duration(seconds: 45),
       _diagnosticRecorder = diagnosticRecorder ?? recordApiDiagnosticEvent;

  final ApiHealthService _apiHealthService;
  final Dio _dio;
  final SubscriptionV2ValueStore _valueStore;
  final SubscriptionV2Requester? _requester;
  final DateTime Function() _now;
  final Random _random;
  final ApiDiagnosticRecorder _diagnosticRecorder;
  final Duration _gatewayRequestTimeout;
  final Duration _operationTimeout;
  final ApiRequestRouter _requestRouter;
  final bool _shareProfileRequests;
  final _pendingProfiles = <String, Future<SubscriptionV2Profile?>>{};
  static final _sharedPendingProfiles =
      <String, Future<SubscriptionV2Profile?>>{};

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
      var gateway = _gatewayCandidates(endpoint, config).first;
      final credential = await _loadCredential(credentialKey, config, gateway);
      if (credential == null) return;
      final identity = await _loadIdentity();
      Object? probeToken;
      gateway = _gatewayCandidates(
        endpoint,
        config,
        reserveRecoveryProbe: true,
        onProbeToken: (token) => probeToken = token,
      ).first;
      await _sendSigned(config, gateway, identity, {
        'op': 'revoke_device',
        'timestamp': _timestamp,
        'nonce': _randomBase64(18),
        'device_id': credential.deviceId,
      }, probeToken: probeToken);
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
    final config = await _loadSubscriptionV2Config('config_read');
    final gateways = _gatewayCandidates(endpoint, config);
    final trustedGateways =
        config.trustedGateways.map((gateway) => gateway.toString()).toList()
          ..sort();
    final requestKey = dart_crypto.sha256
        .convert(
          utf8.encode(
            canonicalSubscriptionV2Json({
              'credential': _credentialKey(userToken),
              'key_id': config.keyId,
              'encryption_key': config.serverEncryptionPublicKey,
              'signing_key': config.serverSigningPublicKey,
              'gateways': trustedGateways.isEmpty
                  ? [gateways.first.toString()]
                  : trustedGateways,
              'require_https': endpoint.scheme == 'https',
              'allow_token_registration': allowTokenRegistration,
              'app_version': appVersion,
              'platform': platform ?? Platform.operatingSystem,
            }),
          ),
        )
        .toString();
    final pending = _shareProfileRequests
        ? _sharedPendingProfiles
        : _pendingProfiles;
    final existing = pending[requestKey];
    if (existing != null) return existing;
    late _SubscriptionV2Identity identity;
    _SubscriptionV2Credential? credential;
    final future = _withGatewayFailover<SubscriptionV2Profile?>(
      gateways: gateways,
      prepare: (scope) async {
        identity = await _loadIdentity(scope: scope);
        credential = await _loadCredential(
          _credentialKey(userToken),
          config,
          gateways.first,
        );
        scope.ensureActive();
        if (credential == null && !allowTokenRegistration) {
          throw const SubscriptionV2Exception('device_not_registered');
        }
      },
      selectGateways: (attempted, scope) => _gatewayCandidates(
        endpoint,
        config,
        reserveRecoveryProbe: true,
        excludedGateways: attempted,
        onProbeToken: (token) => scope.probeToken = token,
      ),
      operation: (gateway, scope) => _fetchProfileAtGateway(
        config: config,
        gateway: gateway,
        userToken: userToken,
        appVersion: appVersion,
        platform: platform,
        allowTokenRegistration: allowTokenRegistration,
        identity: identity,
        initialCredential: credential,
        rememberCredential: (value) => credential = value,
        scope: scope,
      ),
    );
    pending[requestKey] = future;
    try {
      return await future;
    } finally {
      if (identical(pending[requestKey], future)) pending.remove(requestKey);
    }
  }

  Future<SubscriptionV2Profile?> _fetchProfileAtGateway({
    required SubscriptionV2RemoteConfig config,
    required Uri gateway,
    required String userToken,
    required String appVersion,
    required String? platform,
    required bool allowTokenRegistration,
    required _SubscriptionV2Identity identity,
    required _SubscriptionV2Credential? initialCredential,
    required void Function(_SubscriptionV2Credential credential)
    rememberCredential,
    required _SubscriptionV2RequestScope scope,
  }) async {
    final credentialKey = _credentialKey(userToken);
    var credential = initialCredential;
    try {
      credential ??= await _registerDevice(
        config: config,
        gateway: gateway,
        identity: identity,
        credentialKey: credentialKey,
        userToken: userToken,
        appVersion: appVersion,
        platform: platform ?? Platform.operatingSystem,
        scope: scope,
      );
      rememberCredential(credential);
      return await _fetchWithCredential(
        config: config,
        gateway: gateway,
        identity: identity,
        credential: credential,
        userToken: userToken,
        scope: scope,
      );
    } on SubscriptionV2Exception catch (error) {
      if (error.code == 'not_in_gray_allowlist') return null;
      if (error.code != 'device_not_registered') rethrow;
      scope.allowGatewayFallback = false;
      scope.ensureActive();
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
        scope: scope,
      );
      rememberCredential(registered);
      return _fetchWithCredential(
        config: config,
        gateway: gateway,
        identity: identity,
        credential: registered,
        userToken: userToken,
        scope: scope,
      );
    }
  }

  Future<SubscriptionV2Profile> _fetchWithCredential({
    required SubscriptionV2RemoteConfig config,
    required Uri gateway,
    required _SubscriptionV2Identity identity,
    required _SubscriptionV2Credential credential,
    required String userToken,
    _SubscriptionV2RequestScope? scope,
  }) async {
    final issued = await _sendSignedAndTrack(
      stage: 'ticket_issue',
      operation: {
        'op': 'issue_ticket',
        'timestamp': _timestamp,
        'nonce': _randomBase64(18),
        'device_id': credential.deviceId,
      },
      config: config,
      gateway: gateway,
      identity: identity,
      scope: scope,
    );
    final ticket = _requiredString(issued, 'ticket');
    final redeemed = await _sendSignedAndTrack(
      stage: 'ticket_redeem',
      operation: {
        'op': 'redeem_ticket',
        'timestamp': _timestamp,
        'nonce': _randomBase64(18),
        'device_id': credential.deviceId,
        'ticket': ticket,
      },
      config: config,
      gateway: gateway,
      identity: identity,
      scope: scope,
    );
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
    final config = await _loadSubscriptionV2Config('config_read');
    _gatewayCandidates(endpoint, config);
    final identity = await _loadIdentity();
    Object? probeToken;
    final gateway = _gatewayCandidates(
      endpoint,
      config,
      reserveRecoveryProbe: true,
      onProbeToken: (token) => probeToken = token,
    ).first;
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
      }, probeToken: probeToken);
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
      final credentialData = jsonEncode(credential.toJson());
      await _writeCredentialData(_credentialKey(token), credentialData);
      return SubscriptionV2Login(
        endpoint: Uri.parse(gateway.origin),
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

  Future<Map<String, Object?>> fetchNodes({
    required Uri endpoint,
    required String userToken,
  }) {
    return _sendWithStoredCredential(
      endpoint: endpoint,
      userToken: userToken,
      operation: 'get_nodes',
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
    final gateways = _gatewayCandidates(endpoint, config);
    late _SubscriptionV2Credential credential;
    late _SubscriptionV2Identity identity;
    return _withGatewayFailover<Map<String, Object?>>(
      gateways: gateways,
      prepare: (scope) async {
        final loaded = await _loadCredential(
          _credentialKey(userToken),
          config,
          gateways.first,
        );
        scope.ensureActive();
        if (loaded == null) {
          throw const SubscriptionV2Exception('device_not_registered');
        }
        credential = loaded;
        identity = await _loadIdentity(scope: scope);
      },
      selectGateways: (attempted, scope) => _gatewayCandidates(
        endpoint,
        config,
        reserveRecoveryProbe: true,
        excludedGateways: attempted,
        onProbeToken: (token) => scope.probeToken = token,
      ),
      allowRetry: const {'get_nodes', 'get_summary'}.contains(operation),
      operation: (gateway, scope) async {
        return _sendSigned(config, gateway, identity, {
          'op': operation,
          'timestamp': _timestamp,
          'nonce': _randomBase64(18),
          'device_id': credential.deviceId,
        }, scope: scope);
      },
    );
  }

  Future<_SubscriptionV2Credential> _registerDevice({
    required SubscriptionV2RemoteConfig config,
    required Uri gateway,
    required _SubscriptionV2Identity identity,
    required String credentialKey,
    required String userToken,
    required String appVersion,
    required String platform,
    _SubscriptionV2RequestScope? scope,
  }) async {
    final allowGatewayFallback = scope?.allowGatewayFallback;
    if (scope != null) scope.allowGatewayFallback = false;
    final data = await _sendSigned(config, gateway, identity, {
      'op': 'register_device',
      'timestamp': _timestamp,
      'nonce': _randomBase64(18),
      'user_token': userToken,
      'device_public_key': _encodeBase64Url(identity.publicKey.bytes),
      'platform': platform,
      'app_version': appVersion,
    }, scope: scope);
    final credential = _SubscriptionV2Credential(
      deviceId: _requiredString(data, 'device_id'),
      expiresAt: _requiredInt(data, 'expires_at'),
      keyId: config.keyId,
      gateway: gateway.toString(),
    );
    scope?.ensureActive();
    await _valueStore.write(credentialKey, jsonEncode(credential.toJson()));
    scope?.ensureActive();
    if (scope != null) {
      scope.allowGatewayFallback = allowGatewayFallback!;
    }
    return credential;
  }

  Future<Map<String, Object?>> _sendSigned(
    SubscriptionV2RemoteConfig config,
    Uri gateway,
    _SubscriptionV2Identity identity,
    Map<String, Object?> payload, {
    _SubscriptionV2RequestScope? scope,
    Object? probeToken,
  }) async {
    final requestProbeToken = probeToken ?? scope?.probeToken;
    final signature = await Ed25519().sign(
      utf8.encode(canonicalSubscriptionV2Json(payload)),
      keyPair: identity.keyPair,
    );
    final signed = Map<String, Object?>.from(payload)
      ..['signature'] = _encodeBase64Url(signature.bytes);
    scope?.ensureActive();
    return _sendEncrypted(
      config,
      gateway,
      signed,
      scope: scope,
      probeToken: requestProbeToken,
    );
  }

  Future<Map<String, Object?>> _sendEncrypted(
    SubscriptionV2RemoteConfig config,
    Uri gateway,
    Map<String, Object?> payload, {
    _SubscriptionV2RequestScope? scope,
    Object? probeToken,
  }) async {
    try {
      scope?.ensureActive();
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
      final requestRef = _subscriptionV2RequestRef(requestId);
      late final Map<String, Object?> response;
      try {
        scope?.ensureActive();
        final requester = _requester;
        response = requester == null
            ? await _request(gateway, envelope, scope: scope)
            : await requester(
                gateway,
                envelope,
              ).timeout(_requestTimeout(scope));
        scope?.ensureActive();
      } on SubscriptionV2Exception catch (error) {
        _recordGatewayFailure(
          config,
          gateway,
          error,
          scope: scope,
          probeToken: probeToken,
        );
        throw error.withRequestRef(requestRef);
      } on TimeoutException catch (error) {
        final failure = SubscriptionV2Exception(
          'gateway_unavailable',
          requestRef: requestRef,
          diagnostic: classifyApiNetworkFailure(
            error,
            stage: 'secure_gateway',
            endpoint: gateway,
          ),
        );
        _recordGatewayFailure(
          config,
          gateway,
          failure,
          scope: scope,
          probeToken: probeToken,
        );
        throw failure;
      }
      try {
        final data = await _decryptResponse(
          config: config,
          requestId: requestId,
          shared: shared,
          response: response,
          stage: payload['op'] == 'get_nodes'
              ? 'get_nodes_decrypt'
              : 'config_decrypt',
        );
        scope?.ensureActive();
        _requestRouter.recordSuccess(
          gateway,
          candidates: _trustedGatewayCandidates(config, gateway),
          probeToken: probeToken,
        );
        return data;
      } on SubscriptionV2Exception catch (error) {
        throw error.withRequestRef(requestRef);
      } on TimeoutException catch (error) {
        throw SubscriptionV2Exception(
          'gateway_unavailable',
          requestRef: requestRef,
          diagnostic: classifyApiNetworkFailure(
            error,
            stage: 'secure_gateway',
            endpoint: gateway,
          ),
        );
      } catch (_) {
        throw SubscriptionV2Exception(
          'invalid_response_payload',
          requestRef: requestRef,
        );
      }
    } finally {
      if (scope?.isActive ?? true) {
        _requestRouter.releaseRecoveryProbe(
          gateway,
          candidates: _trustedGatewayCandidates(config, gateway),
          probeToken: probeToken,
        );
      }
    }
  }

  Future<Map<String, Object?>> _decryptResponse({
    required SubscriptionV2RemoteConfig config,
    required String requestId,
    required SecretKey shared,
    required Map<String, Object?> response,
    String stage = 'config_decrypt',
  }) async {
    _recordSubscriptionV2Stage(stage);
    try {
      if (response['v'] != _subscriptionV2Version ||
          response['kid'] != config.keyId ||
          response['request_id'] != requestId) {
        _recordSubscriptionV2Stage(
          '${stage}_failed',
          errorCode: 'invalid_response_envelope',
        );
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
        _recordSubscriptionV2Stage(
          '${stage}_failed',
          errorCode: 'invalid_server_signature',
        );
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
      _recordSubscriptionV2Stage('${stage}_ok', contentBytes: plaintext.length);

      final decoded = jsonDecode(utf8.decode(plaintext));
      if (decoded is! Map) {
        _recordSubscriptionV2Stage(
          'config_validation_failed',
          errorCode: 'invalid_response_payload',
        );
        throw const SubscriptionV2Exception('invalid_response_payload');
      }
      _recordSubscriptionV2Stage('config_validation');
      final body = decoded.map((key, value) => MapEntry(key.toString(), value));
      if (body['status'] != 1) {
        final error = body['error']?.toString() ?? 'subscription_v2_rejected';
        _recordSubscriptionV2Stage(
          'config_validation_failed',
          errorCode: error,
        );
        throw SubscriptionV2Exception(error);
      }
      final data = body['data'];
      if (data is! Map) {
        _recordSubscriptionV2Stage(
          'config_validation_failed',
          errorCode: 'invalid_response_data',
        );
        throw const SubscriptionV2Exception('invalid_response_data');
      }
      _recordSubscriptionV2Stage(
        'config_validation_ok',
        contentBytes: _estimatedByteLength(data),
      );
      return data.map((key, value) => MapEntry(key.toString(), value));
    } on SubscriptionV2Exception catch (error) {
      if (!error.code.startsWith('invalid_') &&
          error.code != 'subscription_v2_rejected' &&
          error.code != 'invalid_response_envelope' &&
          error.code != 'invalid_server_signature') {
        _recordSubscriptionV2Stage('${stage}_failed', errorCode: error.code);
      }
      rethrow;
    } catch (error) {
      final errorCode = error is TimeoutException
          ? 'gateway_unavailable'
          : _errorCode(error);
      _recordSubscriptionV2Stage('${stage}_failed', errorCode: errorCode);
      throw SubscriptionV2Exception(
        errorCode,
        diagnostic: classifyApiNetworkFailure(error, stage: stage),
      );
    }
  }

  Future<Map<String, Object?>> _request(
    Uri endpoint,
    Map<String, Object?> envelope, {
    _SubscriptionV2RequestScope? scope,
  }) async {
    final stopwatch = Stopwatch()..start();
    final attemptId = newApiDiagnosticAttemptId();
    final requestId = envelope['request_id'];
    final requestRef = requestId is String
        ? _subscriptionV2RequestRef(requestId)
        : null;
    ApiNetworkDiagnostic? diagnostic;
    final cancelToken = CancelToken();
    scope?.add(cancelToken);
    try {
      final response = await _dio
          .postUri<Object?>(
            endpoint,
            data: envelope,
            options: Options(
              responseType: ResponseType.json,
              headers: const {'Cache-Control': 'no-store'},
              followRedirects: false,
              validateStatus: (status) =>
                  status != null && status >= 200 && status < 600,
            ),
            cancelToken: cancelToken,
          )
          .timeout(
            _requestTimeout(scope),
            onTimeout: () {
              cancelToken.cancel('Secure gateway request deadline');
              throw TimeoutException('Secure gateway request deadline');
            },
          );
      scope?.ensureActive();
      if ((response.statusCode ?? 0) < 200 ||
          (response.statusCode ?? 0) >= 300 ||
          response.data is! Map) {
        diagnostic = classifyApiNetworkFailure(
          StateError('Gateway HTTP response'),
          stage: 'secure_gateway',
          endpoint: endpoint,
          statusCode: response.statusCode,
          elapsedMilliseconds: stopwatch.elapsedMilliseconds,
          attemptId: attemptId,
        );
        throw SubscriptionV2Exception(
          'gateway_unavailable',
          statusCode: response.statusCode,
          diagnostic: diagnostic,
        );
      }
      return (response.data as Map).map(
        (key, value) => MapEntry(key.toString(), value),
      );
    } on SubscriptionV2Exception {
      rethrow;
    } catch (error) {
      diagnostic = classifyApiNetworkFailure(
        error,
        stage: 'secure_gateway',
        endpoint: endpoint,
        elapsedMilliseconds: stopwatch.elapsedMilliseconds,
        attemptId: attemptId,
      );
      throw SubscriptionV2Exception(
        'gateway_unavailable',
        statusCode: diagnostic.statusCode,
        diagnostic: diagnostic,
      );
    } finally {
      stopwatch.stop();
      scope?.remove(cancelToken);
      if (diagnostic != null) {
        emitApiDiagnosticEvent(
          _diagnosticRecorder,
          'api.secure_gateway.failed',
          {...diagnostic.toDiagnosticFields(), 'request_ref': ?requestRef},
        );
      }
    }
  }

  Future<_SubscriptionV2Identity> _loadIdentity({
    _SubscriptionV2RequestScope? scope,
  }) async {
    final stored = await _valueStore.read(_deviceSeedKey);
    scope?.ensureActive();
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
      scope?.ensureActive();
      seed = await generated.extractPrivateKeyBytes();
      scope?.ensureActive();
      await _valueStore.write(_deviceSeedKey, _encodeBase64Url(seed));
      scope?.ensureActive();
    }
    final keyPair = await Ed25519().newKeyPairFromSeed(seed);
    scope?.ensureActive();
    final publicKey = await keyPair.extractPublicKey();
    scope?.ensureActive();
    return _SubscriptionV2Identity(keyPair: keyPair, publicKey: publicKey);
  }

  Future<_SubscriptionV2Credential?> _loadCredential(
    String key,
    SubscriptionV2RemoteConfig config,
    Uri gateway,
  ) async {
    const operationRef = 'device_credential_read';
    _recordSubscriptionV2Stage(operationRef);
    try {
      final stored = await _valueStore.read(key);
      if (stored == null) {
        _recordSubscriptionV2Stage('${operationRef}_missing');
        return null;
      }
      final decoded = jsonDecode(stored);
      if (decoded is! Map) {
        _recordSubscriptionV2Stage(
          '${operationRef}_failed',
          errorCode: 'invalid_credential_payload',
        );
        return null;
      }
      final credential = _SubscriptionV2Credential.fromJson(decoded);
      final gateways = config.trustedGateways
          .map((value) => value.toString())
          .toSet();
      final requestedGateway = gateway.toString();
      final gatewayMatches =
          credential.gateway == requestedGateway ||
          (gateways.contains(credential.gateway) &&
              gateways.contains(requestedGateway));
      if (credential.keyId != config.keyId ||
          !gatewayMatches ||
          (config.enforceGatewayTrust &&
              !gateways.contains(requestedGateway)) ||
          credential.expiresAt <= _timestamp + 30) {
        _recordSubscriptionV2Stage(
          '${operationRef}_failed',
          errorCode: 'credential_not_match',
        );
        return null;
      }
      _recordSubscriptionV2Stage(
        '${operationRef}_ok',
        contentBytes: stored.length,
      );
      return credential;
    } catch (error) {
      _recordSubscriptionV2Stage(
        '${operationRef}_failed',
        errorCode: _errorCode(error),
      );
      return null;
    }
  }

  Future<SubscriptionV2RemoteConfig> _loadSubscriptionV2Config(
    String stage,
  ) async {
    final operation = stage;
    _recordSubscriptionV2Stage(operation);
    try {
      final configSource = await _apiHealthService.loadConfig();
      final config = parseSubscriptionV2RemoteConfig(configSource);
      if (config == null) {
        throw const SubscriptionV2Exception('secure_config_disabled');
      }
      _recordSubscriptionV2Stage(
        '${operation}_ok',
        contentBytes: _estimatedByteLength(configSource),
      );
      return config;
    } on SubscriptionV2Exception catch (error) {
      _recordSubscriptionV2Stage('${operation}_failed', errorCode: error.code);
      rethrow;
    } catch (error) {
      final errorCode = _errorCode(error);
      _recordSubscriptionV2Stage('${operation}_failed', errorCode: errorCode);
      if (error is Error) {
        throw SubscriptionV2Exception(
          errorCode,
          diagnostic: classifyApiNetworkFailure(
            error,
            stage: 'subscription_config',
          ),
        );
      }
      if (error is Exception) {
        throw SubscriptionV2Exception(errorCode);
      }
      throw const SubscriptionV2Exception('subscription_v2_unknown_error');
    }
  }

  Future<void> _writeCredentialData(String key, String credentialData) async {
    const operation = 'device_credential_write';
    _recordSubscriptionV2Stage(operation);
    try {
      await _valueStore.write(key, credentialData);
      _recordSubscriptionV2Stage(
        '${operation}_ok',
        contentBytes: _estimatedByteLength(credentialData),
      );
    } catch (error) {
      _recordSubscriptionV2Stage(
        '${operation}_failed',
        errorCode: _errorCode(error),
      );
      rethrow;
    }
  }

  Future<Map<String, Object?>> _sendSignedAndTrack({
    required String stage,
    required Map<String, Object?> operation,
    required SubscriptionV2RemoteConfig config,
    required Uri gateway,
    required _SubscriptionV2Identity identity,
    _SubscriptionV2RequestScope? scope,
  }) async {
    _recordSubscriptionV2Stage(stage);
    try {
      final response = await _sendSigned(
        config,
        gateway,
        identity,
        operation,
        scope: scope,
      );
      _recordSubscriptionV2Stage(
        '${stage}_ok',
        contentBytes: _estimatedByteLength(response),
      );
      return response;
    } on SubscriptionV2Exception catch (error) {
      _recordSubscriptionV2Stage('${stage}_failed', errorCode: error.code);
      rethrow;
    } catch (error) {
      _recordSubscriptionV2Stage(
        '${stage}_failed',
        errorCode: _errorCode(error),
      );
      throw SubscriptionV2Exception(
        _errorCode(error),
        diagnostic: classifyApiNetworkFailure(error, stage: stage),
      );
    }
  }

  void _recordSubscriptionV2Stage(
    String stage, {
    String? errorCode,
    int? contentBytes,
  }) {
    _diagnosticRecorder('subscription_v2.stage', {
      'stage': stage,
      if (errorCode != null)
        'error_code': subscriptionV2DiagnosticErrorCode(
          SubscriptionV2Exception(errorCode),
        ),
      'content_bytes': ?contentBytes,
    });
  }

  int? _estimatedByteLength(Object? value) {
    if (value == null) return null;
    if (value is String) return value.length;
    if (value is List<int>) return value.length;
    if (value is Map || value is List) {
      try {
        return utf8.encode(jsonEncode(value)).length;
      } catch (_) {
        return null;
      }
    }
    return null;
  }

  String _errorCode(Object error) => subscriptionV2DiagnosticErrorCode(error);

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

  List<Uri> _gatewayCandidates(
    Uri endpoint,
    SubscriptionV2RemoteConfig config, {
    bool reserveRecoveryProbe = false,
    Set<Uri> excludedGateways = const {},
    void Function(Object? token)? onProbeToken,
  }) {
    final requested = _buildGatewayUri(endpoint, config.gatewayPath);
    if (!const {'http', 'https'}.contains(requested.scheme) ||
        requested.host.isEmpty ||
        requested.userInfo.isNotEmpty ||
        (config.enforceGatewayTrust &&
            !config.trustedGateways.contains(requested))) {
      throw const SubscriptionV2Exception('untrusted_gateway');
    }
    final candidates = _trustedGatewayCandidates(config, requested).toSet();
    final eligible = candidates
        .where(
          (gateway) =>
              !excludedGateways.contains(gateway) &&
              (requested.scheme != 'https' || gateway.scheme == 'https'),
        )
        .toSet();
    final routed = _requestRouter.orderCandidates(
      candidates,
      preferred: requested,
      eligibleCandidates: eligible,
      reserveRecoveryProbe: reserveRecoveryProbe,
    );
    if (routed.isEmpty && reserveRecoveryProbe) {
      throw const SubscriptionV2Exception('gateway_unavailable');
    }
    final ordered = routed.where(eligible.contains).take(4).toList();
    if (ordered.isEmpty) {
      throw const SubscriptionV2Exception('untrusted_gateway');
    }
    if (reserveRecoveryProbe) {
      onProbeToken?.call(
        _requestRouter.recoveryProbeToken(
          ordered.first,
          candidates: candidates,
        ),
      );
    }
    return List.unmodifiable(ordered);
  }

  Iterable<Uri> _trustedGatewayCandidates(
    SubscriptionV2RemoteConfig config,
    Uri requested,
  ) => {requested, ...config.trustedGateways};

  void _recordGatewayFailure(
    SubscriptionV2RemoteConfig config,
    Uri gateway,
    SubscriptionV2Exception error, {
    _SubscriptionV2RequestScope? scope,
    Object? probeToken,
  }) {
    if (scope?.isActive == false) return;
    _requestRouter.recordFailure(
      gateway,
      candidates: _trustedGatewayCandidates(config, gateway),
      error: error.diagnostic ?? error,
      statusCode: error.statusCode,
      probeToken: probeToken,
    );
  }

  bool _canRetryGateway(SubscriptionV2Exception error) {
    if (error.code != 'gateway_unavailable') return false;
    if (error.statusCode case final status?) {
      return const {502, 503, 504}.contains(status);
    }
    final failure = error.diagnostic?.failure;
    return const {
      ApiNetworkFailure.network,
      ApiNetworkFailure.timeout,
      ApiNetworkFailure.dns,
      ApiNetworkFailure.connectionRefused,
      ApiNetworkFailure.connectionReset,
    }.contains(failure);
  }

  Duration _requestTimeout(_SubscriptionV2RequestScope? scope) {
    if (scope == null) return _gatewayRequestTimeout;
    final remaining = scope.remaining;
    return remaining < _gatewayRequestTimeout
        ? remaining
        : _gatewayRequestTimeout;
  }

  Future<T> _withGatewayFailover<T>({
    required List<Uri> gateways,
    required Future<void> Function(_SubscriptionV2RequestScope scope) prepare,
    required List<Uri> Function(
      Set<Uri> attempted,
      _SubscriptionV2RequestScope scope,
    )
    selectGateways,
    required Future<T> Function(Uri gateway, _SubscriptionV2RequestScope scope)
    operation,
    bool allowRetry = true,
  }) async {
    final scope = _SubscriptionV2RequestScope(_operationTimeout);
    var activeGateway = gateways.first;
    final attempted = <Uri>{};
    SubscriptionV2Exception? previousFailure;
    Future<T> run() async {
      await prepare(scope);
      scope.ensureActive();
      for (var index = 0; index < gateways.length; index++) {
        scope.ensureActive();
        final previousGateway = activeGateway;
        activeGateway = selectGateways(attempted, scope).first;
        attempted.add(activeGateway);
        if (previousFailure case final error?) {
          emitApiDiagnosticEvent(
            _diagnosticRecorder,
            'subscription_v2.gateway.retry',
            {
              'endpoint_ref': apiDiagnosticEndpointRef(previousGateway),
              'next_endpoint_ref': apiDiagnosticEndpointRef(activeGateway),
              'error_code': subscriptionV2DiagnosticErrorCode(error),
              'http_status': ?error.statusCode,
            },
          );
        }
        try {
          final result = await operation(activeGateway, scope);
          scope.ensureActive();
          return result;
        } on SubscriptionV2Exception catch (error) {
          if (!allowRetry ||
              !scope.allowGatewayFallback ||
              !_canRetryGateway(error) ||
              index == gateways.length - 1) {
            rethrow;
          }
          previousFailure = error;
        }
      }
      throw const SubscriptionV2Exception('gateway_unavailable');
    }

    try {
      return await run().timeout(
        _operationTimeout,
        onTimeout: () {
          scope.cancel();
          throw SubscriptionV2Exception(
            'gateway_unavailable',
            diagnostic: classifyApiNetworkFailure(
              TimeoutException('Secure gateway operation deadline'),
              stage: 'secure_gateway',
              endpoint: activeGateway,
              elapsedMilliseconds: scope.elapsedMilliseconds,
            ),
          );
        },
      );
    } on TimeoutException catch (error) {
      throw SubscriptionV2Exception(
        'gateway_unavailable',
        diagnostic: classifyApiNetworkFailure(
          error,
          stage: 'secure_gateway',
          endpoint: activeGateway,
          elapsedMilliseconds: scope.elapsedMilliseconds,
        ),
      );
    } finally {
      scope.cancel();
    }
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

String _subscriptionV2RequestRef(String requestId) => dart_crypto.sha256
    .convert(utf8.encode(requestId))
    .toString()
    .substring(0, 12);

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
    trustedGateways: List.unmodifiable({
      for (final endpoint in parseApiEndpoints(source))
        if (endpoint.userInfo.isEmpty)
          endpoint
              .replace(path: '/', query: null, fragment: null)
              .resolve(gatewayPath),
    }),
    enforceGatewayTrust: source.containsKey('hosts'),
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

class _SubscriptionV2RequestScope {
  _SubscriptionV2RequestScope(this.timeout);

  final Duration timeout;
  final _stopwatch = Stopwatch()..start();
  final _tokens = <CancelToken>{};
  bool _active = true;
  bool allowGatewayFallback = true;
  Object? probeToken;

  int get elapsedMilliseconds => _stopwatch.elapsedMilliseconds;

  bool get isActive => _active && _stopwatch.elapsed < timeout;

  Duration get remaining {
    ensureActive();
    return timeout - _stopwatch.elapsed;
  }

  void ensureActive() {
    if (!isActive) {
      throw TimeoutException('Secure gateway operation deadline');
    }
  }

  void add(CancelToken token) {
    ensureActive();
    _tokens.add(token);
  }

  void remove(CancelToken token) => _tokens.remove(token);

  void cancel() {
    _active = false;
    _stopwatch.stop();
    for (final token in _tokens.toList()) {
      token.cancel('Secure gateway operation deadline');
    }
    _tokens.clear();
  }
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

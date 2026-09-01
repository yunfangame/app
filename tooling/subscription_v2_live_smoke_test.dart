import 'dart:convert';
import 'dart:io';

import 'package:fl_clash/common/api_health.dart';
import 'package:fl_clash/common/subscription_v2.dart';
import 'package:flutter_test/flutter_test.dart';

late final HttpClient _liveHttpClient;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null;
  _liveHttpClient = HttpClient();

  test(
    'production gateways complete the V2 encrypted handshake',
    () async {
      addTearDown(() => _liveHttpClient.close(force: true));
      final config = jsonDecode(
        await File(
          'tooling/remote_config/ConFigOss4.source.json',
        ).readAsString(),
      );
      final endpoints = parseApiEndpoints(config);
      expect(endpoints, hasLength(3));

      for (final endpoint in endpoints) {
        final client = SubscriptionV2Client(
          apiHealthService: ApiHealthService(
            configUrl: 'https://config.invalid/ConFigOss4.json',
            configLoader: (_) async => config,
          ),
          valueStore: _MemorySubscriptionV2ValueStore(),
          requester: _request,
        );
        await expectLater(
          client.secureLogin(
            endpoint: endpoint,
            email: 'v2-deployment-smoke@example.invalid',
            password: 'invalid-deployment-smoke-password',
            appVersion: '0.8.96-smoke',
            platform: 'deployment-smoke',
          ),
          throwsA(
            isA<SubscriptionV2Exception>().having(
              (error) => error.code,
              'code',
              'invalid_credentials',
            ),
          ),
        );
      }
    },
    timeout: const Timeout(Duration(minutes: 1)),
  );
}

Future<Map<String, Object?>> _request(
  Uri endpoint,
  Map<String, Object?> envelope,
) async {
  final request = await _liveHttpClient.postUrl(endpoint);
  request.headers.contentType = ContentType.json;
  request.add(utf8.encode(jsonEncode(envelope)));
  final response = await request.close().timeout(const Duration(seconds: 15));
  final body = await utf8.decoder.bind(response).join();
  final decoded = jsonDecode(body);
  if (response.statusCode < 200 ||
      response.statusCode >= 300 ||
      decoded is! Map) {
    throw const SubscriptionV2Exception('gateway_unavailable');
  }
  return decoded.map((key, value) => MapEntry(key.toString(), value));
}

class _MemorySubscriptionV2ValueStore implements SubscriptionV2ValueStore {
  final _values = <String, String>{};

  @override
  Future<void> delete(String key) async {
    _values.remove(key);
  }

  @override
  Future<String?> read(String key) async => _values[key];

  @override
  Future<void> write(String key, String value) async {
    _values[key] = value;
  }
}

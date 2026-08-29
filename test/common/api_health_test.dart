import 'dart:convert';

import 'package:fl_clash/common/api_endpoint_preference.dart';
import 'package:fl_clash/common/api_health.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('parses only hosts and normalizes domains', () {
    expect(
      parseApiEndpoints({
        'hosts': [
          'api-one.example.com',
          'https://api-two.example.com/health',
          {'domain': 'api-three.example.com'},
          'api-one.example.com',
          'ftp://invalid.example.com',
        ],
      }).map((endpoint) => endpoint.toString()),
      [
        'https://api-one.example.com',
        'https://api-two.example.com/health',
        'https://api-three.example.com',
      ],
    );

    expect(
      parseApiEndpoints({
        'api_domains': ['https://ignored.example.com'],
        'campusHosts': ['127.0.0.1 ignored.example.com'],
      }),
      isEmpty,
    );
  });

  test('decodes the agreed Base64 config and validates authentication', () {
    final encoded = base64Encode(
      utf8.encode(
        jsonEncode({
          'Authentication': 'FengWo',
          'hosts': ['https://api.example.com'],
        }),
      ),
    );

    final config = decodeApiHealthConfig(encoded);
    expect(parseApiEndpoints(config).single.host, 'api.example.com');
    expect(
      () => decodeApiHealthConfig(
        jsonEncode({'Authentication': 'Other', 'hosts': []}),
      ),
      throwsFormatException,
    );
  });

  test('maps connectivity percentages to the requested status levels', () {
    expect(_snapshot(5, 4).percentage, 80);
    expect(_snapshot(5, 4).level, ApiHealthLevel.healthy);
    expect(_snapshot(2, 1).percentage, 50);
    expect(_snapshot(2, 1).level, ApiHealthLevel.warning);
    expect(_snapshot(5, 2).level, ApiHealthLevel.critical);
    expect(_snapshot(5, 2).shouldPulse, isFalse);
    expect(_snapshot(5, 0).level, ApiHealthLevel.critical);
    expect(_snapshot(5, 0).shouldPulse, isTrue);
  });

  test('each check reloads config and probes all endpoints', () async {
    var configLoads = 0;
    var probes = 0;
    final service = ApiHealthService(
      configUrl: 'https://config.example.com/app.json',
      configLoader: (_) async {
        configLoads++;
        return {
          'Authentication': 'FengWo',
          'hosts': ['https://one.example.com', 'https://two.example.com'],
        };
      },
      endpointProbe: (endpoint) async {
        probes++;
        return endpoint.host == 'one.example.com';
      },
    );

    final first = await service.check();
    final second = await service.check();

    expect(configLoads, 2);
    expect(probes, 4);
    expect(first.percentage, 50);
    expect(second.percentage, 50);
  });

  test('missing config URL returns an unavailable snapshot', () async {
    final snapshot = await ApiHealthService(configUrl: '').check();

    expect(snapshot.level, ApiHealthLevel.unavailable);
    expect(snapshot.total, 0);
  });

  test('persists and prioritizes the selected healthy endpoint', () async {
    final store = ApiEndpointPreferenceStore();
    final service = ApiHealthService(preferenceStore: store);
    await service.savePreferredEndpoint(
      Uri.parse('https://preferred.example.com/health?source=config'),
    );
    final snapshot = ApiHealthSnapshot(
      endpoints: [
        ApiEndpointHealth(
          endpoint: Uri.parse('https://fast.example.com'),
          reachable: true,
          latency: const Duration(milliseconds: 20),
        ),
        ApiEndpointHealth(
          endpoint: Uri.parse('https://preferred.example.com'),
          reachable: true,
          latency: const Duration(milliseconds: 200),
        ),
      ],
      checkedAt: DateTime(2026),
    );

    final ordered = await service.orderedReachableEndpoints(snapshot);

    expect(
      await service.loadPreferredEndpoint(),
      Uri.parse('https://preferred.example.com'),
    );
    expect(ordered.first.endpoint.host, 'preferred.example.com');
    expect(ordered.last.endpoint.host, 'fast.example.com');
  });
}

ApiHealthSnapshot _snapshot(int total, int reachable) {
  return ApiHealthSnapshot(
    endpoints: List.generate(
      total,
      (index) => ApiEndpointHealth(
        endpoint: Uri.parse('https://api-$index.example.com'),
        reachable: index < reachable,
        latency: const Duration(milliseconds: 20),
      ),
    ),
    checkedAt: DateTime(2026),
  );
}

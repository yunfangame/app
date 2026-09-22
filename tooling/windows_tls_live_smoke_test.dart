import 'dart:convert';
import 'dart:io';

import 'package:fl_clash/common/api_health.dart';
import 'package:fl_clash/common/windows_tls_trust.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null;

  test(
    'public APIs verify with supplemental roots and no system roots',
    () async {
      // ignore: invalid_use_of_visible_for_testing_member
      SharedPreferences.setMockInitialValues({});
      final keys =
          jsonDecode(
                await File('tooling/remote_config/keys.json').readAsString(),
              )
              as Map<String, dynamic>;
      await WindowsTlsTrust(isWindows: true).initialize();
      final service = ApiHealthService(
        aesKey: keys['aesKey'] as String,
        signingPublicKey: keys['signingPublicKey'] as String,
        diagnosticRecorder: (_, _) {},
      );
      final endpoints = await service.loadCandidateEndpoints();
      expect(endpoints, isNotEmpty);
      final urls = [
        Uri.parse(apiHealthConfigUrl),
        ...endpoints.map(
          (endpoint) => endpoint.resolve('/api/v1/guest/comm/config'),
        ),
      ];
      final context = SecurityContext(withTrustedRoots: false);
      await WindowsTlsTrust(
        isWindows: true,
        context: () => context,
      ).initialize();
      for (var index = 0; index < urls.length; index++) {
        final uri = urls[index];
        int? status;
        for (var attempt = 0; attempt < 3; attempt++) {
          try {
            status = await _status(uri, context);
            break;
          } on IOException {
            if (attempt == 2) rethrow;
          }
        }
        expect(status, 200, reason: 'Public endpoint ${index + 1}');
      }
      await expectLater(
        _status(urls.first, SecurityContext(withTrustedRoots: false)),
        throwsA(isA<HandshakeException>()),
      );
      final output = File('build/tls_targets.json');
      await output.parent.create(recursive: true);
      await output.writeAsString(
        jsonEncode([
          ...urls.map((uri) => uri.toString()),
          apiHealthBackupConfigUrl,
        ]),
      );
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );
}

Future<int> _status(Uri uri, SecurityContext context) async {
  final client = HttpClient(context: context)
    ..connectionTimeout = const Duration(seconds: 8);
  client.findProxy = (_) => 'DIRECT';
  try {
    final request = await client
        .getUrl(uri)
        .timeout(const Duration(seconds: 8));
    request.followRedirects = false;
    final response = await request.close().timeout(const Duration(seconds: 8));
    return response.statusCode;
  } finally {
    client.close(force: true);
  }
}

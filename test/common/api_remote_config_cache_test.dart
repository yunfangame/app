import 'dart:convert';

import 'package:fl_clash/common/api_remote_config_cache.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('writes encrypted config metadata as one cache value', () async {
    final store = ApiRemoteConfigCacheStore();

    await store.save(
      encryptedConfig: '{"ciphertext":"encrypted"}',
      candidateCount: 3,
    );

    final preferences = await SharedPreferences.getInstance();
    expect(preferences.getKeys(), {'xboard.remote_config.encrypted.v1'});
    final raw = preferences.getString('xboard.remote_config.encrypted.v1');
    final decoded = jsonDecode(raw!) as Map<String, Object?>;
    expect(decoded['version'], 1);
    expect(decoded['candidateCount'], 3);
    expect(decoded['encryptedConfig'], '{"ciphertext":"encrypted"}');
    expect(await store.load(), '{"ciphertext":"encrypted"}');
  });

  test('removes incomplete cache values', () async {
    SharedPreferences.setMockInitialValues({
      'xboard.remote_config.encrypted.v1': jsonEncode({
        'version': 1,
        'candidateCount': 0,
        'encryptedConfig': 'broken',
      }),
    });
    final store = ApiRemoteConfigCacheStore();

    expect(await store.load(), isNull);

    final preferences = await SharedPreferences.getInstance();
    expect(
      preferences.containsKey('xboard.remote_config.encrypted.v1'),
      isFalse,
    );
  });
}

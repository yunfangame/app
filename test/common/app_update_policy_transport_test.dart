import 'dart:async';
import 'dart:io';

import 'package:fl_clash/common/api_health.dart';
import 'package:fl_clash/common/app_update.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test(
    'automatic config reads reuse verified TTL and manual refresh fetches a fresh preferred source',
    () async {
      final configRequests = <Uri>[];
      final manifestRequests = <Uri>[];
      var configRevision = 1;
      final health = ApiHealthService(
        configUrl: 'https://config.example/primary',
        backupConfigUrls: const ['https://config.example/backup'],
        configLoader: (uri) async {
          configRequests.add(uri);
          return {
            'Authentication': 'FengWo',
            'UpdateUrl': 'https://update.example/manifest-$configRevision.json',
          };
        },
      );
      final service = AppUpdateService(
        apiHealthService: health,
        manifestLoader: (uri) async {
          manifestRequests.add(uri);
          return _manifest;
        },
        packageKeyResolver: () => 'windows-x64',
        aesKey: '',
        signingPublicKey: '',
      );
      addTearDown(service.close);
      await service.discoverUpdate(currentVersion: '1.0.4');
      configRevision = 2;
      await service.discoverUpdate(currentVersion: '1.0.4');
      expect(configRequests, hasLength(1));
      expect(manifestRequests.map((uri) => uri.path), [
        '/manifest-1.json',
        '/manifest-1.json',
      ]);
      expect(
        manifestRequests.every(
          (uri) => !uri.queryParameters.containsKey('_fengwo_update_refresh'),
        ),
        isTrue,
      );
      await service.discoverUpdate(currentVersion: '1.0.4', forceRefresh: true);
      await service.discoverUpdate(currentVersion: '1.0.4', forceRefresh: true);
      expect(configRequests, hasLength(3));
      expect(
        configRequests
            .skip(1)
            .map((uri) => uri.queryParameters['_fengwo_refresh']),
        everyElement(isNotEmpty),
      );
      final forced = manifestRequests.skip(2).toList();
      expect(forced.map((uri) => uri.path), [
        '/manifest-2.json',
        '/manifest-2.json',
      ]);
      expect(
        forced.map((uri) => uri.queryParameters['_fengwo_update_refresh']),
        everyElement(isNotEmpty),
      );
      expect(
        forced
            .map((uri) => uri.queryParameters['_fengwo_update_refresh'])
            .toSet(),
        hasLength(2),
      );
    },
  );

  test('automatic gate prevents cold configuration traffic', () async {
    var configs = 0;
    final service = AppUpdateService(
      mainConfigLoader: () async {
        configs++;
        return {'UpdateUrl': 'https://update.example/manifest.json'};
      },
      manifestLoader: (_) async => _manifest,
      packageKeyResolver: () => 'windows-x64',
    );
    addTearDown(service.close);
    await expectLater(
      service.discoverUpdate(currentVersion: '1.0.4', canFetch: () => false),
      throwsA(isA<AppUpdateCheckDeferred>()),
    );
    expect(configs, 0);
  });

  test('backgrounding after config prevents a new manifest request', () async {
    final config = Completer<Object?>();
    var active = true;
    var manifests = 0;
    final service = AppUpdateService(
      mainConfigLoader: () => config.future,
      manifestLoader: (_) async {
        manifests++;
        return _manifest;
      },
      packageKeyResolver: () => 'windows-x64',
    );
    addTearDown(service.close);
    final request = service.discoverUpdate(
      currentVersion: '1.0.4',
      canFetch: () => active,
    );
    final assertion = expectLater(
      request,
      throwsA(isA<AppUpdateCheckDeferred>()),
    );
    active = false;
    config.complete({'UpdateUrl': 'https://update.example/manifest.json'});
    await assertion;
    expect(manifests, 0);
  });

  test('automatic manifest retries stop when availability changes', () async {
    var active = true;
    var requests = 0;
    final service = AppUpdateService(
      mainConfigLoader: () async => {
        'UpdateUrl': appUpdateTrustedManifestUrls.first,
      },
      manifestLoader: (_) async {
        requests++;
        active = false;
        throw const SocketException('controlled outage');
      },
      packageKeyResolver: () => 'windows-x64',
      retryDelay: Duration.zero,
    );
    addTearDown(service.close);
    await expectLater(
      service.discoverUpdate(currentVersion: '1.0.4', canFetch: () => active),
      throwsA(isA<AppUpdateCheckDeferred>()),
    );
    expect(requests, 1);
  });
}

const _manifest = {
  'Authentication': 'FengWo',
  'format': 'fengwo-update',
  'schemaVersion': 1,
  'packages': {
    'windows-x64': {
      'enabled': true,
      'version': '1.0.5',
      'downloadUrl': 'https://update.example/app.exe',
    },
  },
};

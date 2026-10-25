import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:fl_clash/common/android_update_transport.dart';
import 'package:fl_clash/common/app_update.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('test/android-update');
  final calls = <MethodCall>[];
  late AndroidUpdateTransport transport;
  final uri = Uri.parse(appUpdateTrustedManifestUrls.first);

  void handler(Future<Object?> Function(MethodCall) callback) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          return callback(call);
        });
  }

  setUp(() {
    calls.clear();
    SharedPreferences.setMockInitialValues({});
    transport = AndroidUpdateTransport(channel: channel);
  });
  tearDown(() {
    transport.close();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('fetches bytes and releases the native request', () async {
    handler(
      (call) async => call.method == 'fetchUpdateConfig'
          ? Uint8List.fromList(utf8.encode('{"ok":true}'))
          : null,
    );
    expect(await transport.load(uri), '{"ok":true}');
    expect(calls.map((call) => call.method), [
      'fetchUpdateConfig',
      'cancelUpdateConfig',
    ]);
    expect((calls.first.arguments as Map)['kind'], 'update_manifest');
  });

  for (final (code, matcher) in <(String, Matcher)>[
    ('UPDATE_TIMEOUT', isA<TimeoutException>()),
    ('UPDATE_TLS', isA<HandshakeException>()),
    ('UPDATE_DNS', isA<SocketException>()),
    ('UPDATE_NETWORK', isA<SocketException>()),
    ('UPDATE_SIZE', isA<FormatException>()),
    ('UPDATE_INVALID', isA<FormatException>()),
    ('UPDATE_CANCELLED', isA<DioException>()),
    ('UPDATE_HTTP', isA<DioException>()),
  ]) {
    test('maps native $code safely and cancels its resources', () async {
      handler((call) async {
        if (call.method == 'fetchUpdateConfig') {
          throw PlatformException(code: code, details: 503);
        }
        return null;
      });
      await expectLater(transport.load(uri), throwsA(matcher));
      expect(calls.last.method, 'cancelUpdateConfig');
    });
  }

  test('pre-cancelled and closed transports never start a request', () async {
    handler((_) async => null);
    final cancel = CancelToken()..cancel();
    await expectLater(
      transport.load(uri, cancelToken: cancel),
      throwsA(isA<DioException>()),
    );
    transport.close();
    await expectLater(transport.load(uri), throwsStateError);
    expect(calls, isEmpty);
  });

  for (final closing in [false, true]) {
    test(
      'pending native request is cancelled on ${closing ? 'close' : 'token'}',
      () async {
        final response = Completer<Object?>();
        final started = Completer<void>();
        handler((call) async {
          if (call.method == 'fetchUpdateConfig') {
            started.complete();
            return response.future;
          }
          if (!response.isCompleted) {
            response.completeError(PlatformException(code: 'UPDATE_CANCELLED'));
          }
          return null;
        });
        final cancel = CancelToken();
        final request = transport.load(uri, cancelToken: cancel);
        final expectation = expectLater(request, throwsA(isA<DioException>()));
        await started.future;
        if (closing) {
          transport.close();
        } else {
          cancel.cancel();
        }
        await expectation;
        expect(
          calls.where((call) => call.method == 'cancelUpdateConfig'),
          hasLength(1),
        );
      },
    );
  }

  test('main config and manifest both use the native underlay', () async {
    handler((call) async {
      if (call.method != 'fetchUpdateConfig') return null;
      final args = call.arguments as Map;
      final payload = args['kind'] == 'main_config'
          ? {'Authentication': 'FengWo', 'UpdateUrl': '$uri'}
          : {
              'Authentication': 'FengWo',
              'format': 'fengwo-update',
              'schemaVersion': 1,
              'packages': {
                'android-arm64-v8a': {
                  'enabled': true,
                  'version': '1.0.10',
                  'downloadUrl': 'https://downloads.example/fengwo.apk',
                },
              },
            };
      return Uint8List.fromList(utf8.encode(jsonEncode(payload)));
    });
    final events = <Map<String, Object?>>[];
    final service = AppUpdateService(
      androidTransport: transport,
      packageKeyResolver: () => 'android-arm64-v8a',
      diagnosticRecorder: (_, fields) => events.add(fields),
      aesKey: '',
      signingPublicKey: '',
    );
    addTearDown(service.close);
    expect(
      (await service.discoverUpdate(currentVersion: '1.0.10')).status,
      AppUpdateCheckStatus.upToDate,
    );
    expect(
      (await service.discoverUpdate(currentVersion: '1.0.10')).status,
      AppUpdateCheckStatus.upToDate,
    );
    final automaticConfigCalls = calls
        .where((call) => call.method == 'fetchUpdateConfig')
        .map((call) => call.arguments as Map)
        .where((args) => args['kind'] == 'main_config')
        .length;
    expect(automaticConfigCalls, 2);
    for (var attempt = 0; attempt < 2; attempt++) {
      expect(
        (await service.discoverUpdate(
          currentVersion: '1.0.10',
          forceRefresh: true,
        )).status,
        AppUpdateCheckStatus.upToDate,
      );
    }
    final refreshNonces = calls
        .where((call) => call.method == 'fetchUpdateConfig')
        .map((call) => call.arguments as Map)
        .where((args) => args['kind'] == 'main_config')
        .map(
          (args) => Uri.parse(
            args['url'] as String,
          ).queryParameters['_fengwo_refresh'],
        )
        .toList();
    expect(refreshNonces.take(2), everyElement(isNull));
    expect(refreshNonces.skip(2), hasLength(4));
    expect(refreshNonces.skip(2), everyElement(isNotEmpty));
    expect(refreshNonces.skip(2).toSet(), hasLength(2));
    final manifestNonces = calls
        .where((call) => call.method == 'fetchUpdateConfig')
        .map((call) => call.arguments as Map)
        .where((args) => args['kind'] == 'update_manifest')
        .map(
          (args) => Uri.parse(
            args['url'] as String,
          ).queryParameters['_fengwo_update_refresh'],
        )
        .toList();
    expect(manifestNonces.take(2), everyElement(isNull));
    expect(manifestNonces.skip(2), everyElement(isNotEmpty));
    expect(manifestNonces.skip(2).toSet(), hasLength(2));
    final kinds = calls
        .where((call) => call.method == 'fetchUpdateConfig')
        .map((call) => (call.arguments as Map)['kind']);
    expect(kinds, contains('main_config'));
    expect(kinds, contains('update_manifest'));
    expect(events.first['transport'], 'android_underlying_network');
  });
}

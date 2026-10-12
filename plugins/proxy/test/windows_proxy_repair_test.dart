import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:proxy/proxy_method_channel.dart';
import 'package:proxy/proxy_platform_interface.dart';

class _StopOnlyProxy extends ProxyPlatform {
  int stops = 0;

  @override
  Future<bool> stopProxy({int? expectedPort}) async {
    stops++;
    return true;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final proxy = MethodChannelProxy();

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(proxy.methodChannel, null);
  });

  test('stale repair sends an explicit guarded native request', () async {
    MethodCall? request;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(proxy.methodChannel, (call) async {
          request = call;
          return {
            'success': true,
            'operation': 'stop',
            'stage': 'restored',
            'restoredCount': 1,
            'enabled': false,
          };
        });

    final result = await proxy.repairStaleProxyDetailed(7890);

    expect(request?.method, 'RepairStaleProxyDetailed');
    expect(request?.arguments, {'expectedPort': 7890});
    expect(result.success, isTrue);
    expect(result.stage, 'restored');
    expect(result.restoredCount, 1);
  });

  test('stale repair preserves the active native listener result', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(proxy.methodChannel, (_) async {
          return {
            'success': true,
            'operation': 'stop',
            'stage': 'skipped_active_listener',
            'writeSkipped': true,
          };
        });

    final result = await proxy.repairStaleProxyDetailed(7890);

    expect(result.success, isTrue);
    expect(result.writeSkipped, isTrue);
    expect(result.stage, 'skipped_active_listener');
  });

  test('invalid repair ports never reach the method channel', () async {
    var calls = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(proxy.methodChannel, (_) async {
          calls++;
          return true;
        });

    for (final port in [-1, 0, 65536]) {
      final result = await proxy.repairStaleProxyDetailed(port);
      expect(result.success, isFalse);
      expect(result.stage, 'invalid_arguments');
    }
    expect(calls, 0);
  });

  test(
    'missing repair implementation never falls back to ordinary stop',
    () async {
      final methods = <String>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(proxy.methodChannel, (call) async {
            methods.add(call.method);
            throw MissingPluginException('No guarded native repair');
          });

      final result = await proxy.repairStaleProxyDetailed(7890);

      expect(result.success, isFalse);
      expect(result.stage, 'unsupported');
      expect(methods, ['RepairStaleProxyDetailed']);
    },
  );

  test('native repair failure keeps the system code and stage', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(proxy.methodChannel, (_) async {
          return {
            'success': false,
            'operation': 'stop',
            'stage': 'listener_inspection',
            'errorCode': 5,
          };
        });

    final result = await proxy.repairStaleProxyDetailed(7890);

    expect(result.success, isFalse);
    expect(result.errorCode, 5);
    expect(result.stage, 'listener_inspection');
  });

  test('channel repair errors fail without a destructive fallback', () async {
    final methods = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(proxy.methodChannel, (call) async {
          methods.add(call.method);
          throw PlatformException(code: 'proxy_shutdown', message: 'closed');
        });

    final result = await proxy.repairStaleProxyDetailed(7890);

    expect(result.success, isFalse);
    expect(result.stage, 'method_channel');
    expect(result.message, 'proxy_shutdown: closed');
    expect(methods, ['RepairStaleProxyDetailed']);
  });

  test('null repair reply is a failure', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(proxy.methodChannel, (_) async => null);

    expect((await proxy.repairStaleProxyDetailed(7890)).success, isFalse);
  });

  test(
    'platform default cannot delegate stale repair to unguarded stop',
    () async {
      final platform = _StopOnlyProxy();

      final result = await platform.repairStaleProxyDetailed(7890);

      expect(result.success, isFalse);
      expect(result.stage, 'unsupported');
      expect(platform.stops, 0);
    },
  );
}

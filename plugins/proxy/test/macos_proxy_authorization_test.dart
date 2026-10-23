import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:proxy/src/macos_proxy_authorization.dart';
import 'package:proxy/src/proxy_command.dart';
import 'package:proxy/src/proxy_result.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('fengwo-proxy-authorization-test');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final events = <Map<String, Object?>>[];
  late MacosProxyAuthorization bridge;
  final commands = [
    ProxyCommand('/usr/sbin/networksetup', [
      '-setwebproxy',
      'Private Wi-Fi',
      '127.0.0.1',
      '17980',
    ]),
    ProxyCommand('/usr/sbin/networksetup', [
      '-setwebproxystate',
      'Private Wi-Fi',
      'on',
    ]),
  ];

  setUp(() {
    events.clear();
    bridge = MacosProxyAuthorization(
      channel: channel,
      onDiagnostic: (event, fields) => events.add({'event': event, ...fields}),
    );
  });
  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
  });

  test('native writes are structured and never run CLI commands', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'writeCommands');
      expect(call.arguments, {
        'commands': commands.map((command) => command.args).toList(),
      });
      return {
        'success': true,
        'committed': true,
        'authorizationAttempted': true,
        'authorizationUsed': true,
      };
    });
    final runner = MacosAuthorizedCommandRunner(
      ProxyCommandRunner(
        (executable, args, {runInShell = false}) async =>
            throw StateError('unexpected CLI write'),
      ),
      bridge,
    );

    final result = await runner.runDetailed(commands);

    expect(result.success, isTrue);
    expect(result.command, same(commands.last));
    expect(events.last['authorization_used'], isTrue);
    expect(events.toString(), isNot(contains('Private Wi-Fi')));
    expect(events.toString(), isNot(contains('127.0.0.1')));
  });

  for (final committed in [false, true]) {
    test(
      'native failed write retains ownership evidence committed=$committed',
      () async {
        messenger.setMockMethodCallHandler(
          channel,
          (_) async => {
            'success': false,
            'committed': committed,
            'systemError': 1003,
            'reason': 'preferences_commit',
            'authorizationAttempted': true,
          },
        );

        final failure = await bridge.write(commands);
        final result = const ProxyOperationResult(
          success: false,
          operation: 'start',
          stage: 'apply_default',
          platform: 'macos',
        ).withCommandFailure(failure);

        expect(failure.success, isFalse);
        expect(
          failure.command,
          same(committed ? commands.last : commands.first),
        );
        expect(result.errorCode, 1003);
        expect(result.command, 'SystemConfiguration writeCommands');
        expect(result.toDiagnosticFields()['system_error'], 1003);
        expect(result.toDiagnosticFields(), isNot(contains('win32_error')));
      },
    );
  }

  test('cancelled authorization cannot report successful connection', () async {
    messenger.setMockMethodCallHandler(
      channel,
      (_) async => {
        'success': false,
        'systemError': -60006,
        'reason': 'authorization_cancelled',
        'authorizationCancelled': true,
      },
    );

    expect((await bridge.write(commands)).success, isFalse);
    expect(events.last['authorization_cancelled'], isTrue);
  });

  test(
    'service discovery failures expose counts but not private identities',
    () async {
      messenger.setMockMethodCallHandler(
        channel,
        (_) async => {
          'success': false,
          'reason': 'service_not_unique',
          'systemError': 0,
          'scoped_match_count': 2,
          'global_match_count': 4,
          'serviceName': 'Private Wi-Fi',
          'networkSetID': 'private-location',
          'serviceID': 'private-service',
        },
      );

      final result = await bridge.write(commands);
      expect(result.success, isFalse);
      expect(result.processResult?.exitCode, 1);
      expect(events.last['scoped_match_count'], 2);
      expect(events.last['global_match_count'], 4);
      expect(events.toString(), isNot(contains('Private Wi-Fi')));
      expect(events.toString(), isNot(contains('private-location')));
      expect(events.toString(), isNot(contains('private-service')));
      expect(await bridge.readAutoDiscovery('Wi-Fi'), isNull);
      expect(
        events.last['event'],
        'system_proxy.native.auto_discovery.unavailable',
      );
      expect(events.last['reason'], 'service_not_unique');
    },
  );

  test(
    'native discovery progress keeps only bounded diagnostic fields',
    () async {
      await messenger.handlePlatformMessage(
        channel.name,
        const StandardMethodCodec().encodeMethodCall(
          const MethodCall('diagnostic', {
            'event': 'service.discovery.completed',
            'fields': {
              'success': true,
              'selection': 'unique_current_set',
              'scoped_match_count': 1,
              'global_match_count': 3,
              'serviceName': 'Private Wi-Fi',
              'serviceID': 'private-service',
            },
          }),
        ),
        (_) {},
      );
      expect(
        events.single['event'],
        'system_proxy.native.service.discovery.completed',
      );
      expect(events.single['selection'], 'unique_current_set');
      expect(events.single['global_match_count'], 3);
      expect(events.toString(), isNot(contains('Private Wi-Fi')));
      expect(events.toString(), isNot(contains('private-service')));
    },
  );

  test('getter remains ordinary read-only CLI work', () async {
    var reads = 0;
    messenger.setMockMethodCallHandler(
      channel,
      (_) async => fail('read must not authorize'),
    );
    final runner = MacosAuthorizedCommandRunner(
      ProxyCommandRunner((executable, args, {runInShell = false}) async {
        reads++;
        expect(args.first, '-getwebproxy');
        return ProcessResult(0, 0, 'Enabled: No\nServer: \nPort: 0\n', '');
      }),
      bridge,
    );

    expect(
      (await runner.runDetailed([
        ProxyCommand('/usr/sbin/networksetup', ['-getwebproxy', 'Wi-Fi']),
      ])).success,
      isTrue,
    );
    expect(reads, 1);
    expect(events, isEmpty);
  });

  test(
    'service identity round-trips without entering diagnostic logs',
    () async {
      const id = (
        serviceID: '11111111-1111-4111-8111-111111111111',
        networkSetID: 'fixture-location',
      );
      messenger.setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'readAutoDiscovery') {
          return {
            'serviceName': 'Wi-Fi',
            'serviceID': id.serviceID,
            'networkSetID': id.networkSetID,
            'enabled': false,
          };
        }
        expect(call.method, 'writeCommands');
        expect((call.arguments as Map)['serviceIdentity'], {
          'serviceID': id.serviceID,
          'networkSetID': id.networkSetID,
        });
        return {'success': true, 'committed': true};
      });
      expect(await bridge.readServiceIdentity('Wi-Fi'), id);
      final scoped = [
        for (final command in commands)
          ProxyCommand(command.executable, command.args, macosIdentity: id),
      ];
      expect((await bridge.write(scoped)).success, isTrue);
      expect(events.toString(), isNot(contains(id.serviceID)));
      expect(events.toString(), isNot(contains(id.networkSetID)));
    },
  );

  test('a mixed identity batch cannot reach native writes', () async {
    messenger.setMockMethodCallHandler(
      channel,
      (_) async => fail('mixed identity reached native code'),
    );
    final result = await bridge.write([
      commands.first,
      ProxyCommand(
        commands.last.executable,
        commands.last.args,
        macosIdentity: (
          serviceID: '11111111-1111-4111-8111-111111111111',
          networkSetID: 'fixture-location',
        ),
      ),
    ]);
    expect(result.success, isFalse);
    expect(result.processResult?.exitCode, 1);
  });

  test(
    'missing WPAD is accepted only from the exact service typed response',
    () async {
      messenger.setMockMethodCallHandler(
        channel,
        (_) async => {
          'serviceID': '11111111-1111-4111-8111-111111111111',
          'serviceName': 'Wi-Fi',
          'enabled': false,
          'settingPresent': false,
        },
      );

      expect(await bridge.readAutoDiscovery('Wi-Fi'), isFalse);
      expect(events.last['setting_present'], isFalse);
    },
  );

  for (final response in [
    null,
    {
      'serviceName': 'Other',
      'serviceID': '11111111-1111-4111-8111-111111111111',
      'enabled': false,
    },
    {'serviceName': 'Wi-Fi', 'serviceID': 'invalid', 'enabled': false},
    {
      'serviceName': 'Wi-Fi',
      'serviceID': '11111111-1111-4111-8111-111111111111',
      'enabled': 'false',
    },
  ]) {
    test('unknown WPAD response remains unreadable $response', () async {
      messenger.setMockMethodCallHandler(channel, (_) async => response);
      expect(await bridge.readAutoDiscovery('Wi-Fi'), isNull);
    });
  }

  test('missing native bridge fails closed without CLI write retry', () async {
    messenger.setMockMethodCallHandler(
      channel,
      (_) async => throw MissingPluginException(),
    );

    expect((await bridge.write(commands)).success, isFalse);
    expect(await bridge.readAutoDiscovery('Wi-Fi'), isNull);
    await bridge.invalidate();
  });

  test(
    'platform errors are logged without potentially private messages',
    () async {
      messenger.setMockMethodCallHandler(
        channel,
        (_) async => throw PlatformException(
          code: 'failure',
          message: 'secret.internal.invalid',
        ),
      );

      expect(await bridge.readAutoDiscovery('Wi-Fi'), isNull);
      expect((await bridge.write(commands)).success, isFalse);
      expect(events.toString(), isNot(contains('secret.internal.invalid')));
    },
  );

  test(
    'invalidation is sent independently of queued authorization work',
    () async {
      messenger.setMockMethodCallHandler(channel, (call) async {
        expect(call.method, 'invalidate');
        return {'success': true};
      });
      await bridge.invalidate();
      expect(events.last['event'], 'system_proxy.native.invalidated');
    },
  );
}

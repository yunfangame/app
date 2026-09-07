import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:proxy/proxy.dart';
import 'package:proxy/proxy_method_channel.dart';
import 'package:proxy/src/linux_proxy.dart';
import 'package:proxy/src/macos_proxy.dart';
import 'package:proxy/src/proxy_command.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Proxy', () {
    test('rejects ports outside the TCP port range', () async {
      final proxy = Proxy(
        processRunner: (executable, arguments, {runInShell = false}) async {
          fail('invalid ports must not execute platform commands');
        },
      );

      expect(await proxy.startProxy(0), isFalse);
      expect(await proxy.startProxy(65536), isFalse);
    });
  });

  group('ProxyCommandRunner', () {
    test('treats an empty command set as failure', () async {
      final runner = ProxyCommandRunner((
        executable,
        arguments, {
        runInShell = false,
      }) async {
        fail('empty command sets must not start a process');
      });

      expect(await runner.run(const []), isFalse);
    });

    test('stops after the first failed command', () async {
      var callCount = 0;
      final runner = ProxyCommandRunner((
        executable,
        arguments, {
        runInShell = false,
      }) async {
        callCount++;
        return ProcessResult(callCount, callCount == 1 ? 1 : 0, '', '');
      });

      final result = await runner.run([
        ProxyCommand('first', const []),
        ProxyCommand('second', const []),
      ]);

      expect(result, isFalse);
      expect(callCount, 1);
    });

    test('converts process launch failures to false', () async {
      final runner = ProxyCommandRunner((
        executable,
        arguments, {
        runInShell = false,
      }) async {
        throw ProcessException(executable, arguments);
      });

      expect(await runner.run([ProxyCommand('missing', const [])]), isFalse);
    });
  });

  group('Linux proxy command builders', () {
    test(
      'checks each fallback command only once for unknown desktops',
      () async {
        final checkedExecutables = <String>[];
        final executedCommands = <String>[];
        final proxy = LinuxProxy(
          commandRunner: ProxyCommandRunner((
            executable,
            arguments, {
            runInShell = false,
          }) async {
            executedCommands.add(executable);
            return ProcessResult(1, 0, '', '');
          }),
          executableChecker: (executable) async {
            checkedExecutables.add(executable);
            return executable == 'kwriteconfig5';
          },
        );

        final result = await proxy.start(
          7890,
          const ['localhost'],
          desktop: 'UNKNOWN',
          homeDir: '/home/user',
        );

        expect(result, isTrue);
        expect(checkedExecutables, [
          'gsettings',
          'kwriteconfig6',
          'kwriteconfig5',
        ]);
        expect(executedCommands, everyElement('kwriteconfig5'));
      },
    );

    test('builds GNOME commands without duplicate port writes', () {
      final commands = LinuxProxyCommands.buildStart(
        port: 7890,
        bypassDomain: ['localhost', '127.0.0.1'],
        desktop: 'GNOME',
        homeDir: '/home/user',
      );

      final portCommands = commands.where(
        (command) => command.args.length == 4 && command.args[2] == 'port',
      );
      final hostCommands = commands.where(
        (command) => command.args.length == 4 && command.args[2] == 'host',
      );

      expect(portCommands, hasLength(3));
      expect(hostCommands, hasLength(3));
      expect(commands.last.args, [
        'set',
        'org.gnome.system.proxy',
        'mode',
        'manual',
      ]);
      expect(
        commands
            .singleWhere(
              (command) =>
                  command.args.contains('org.gnome.system.proxy') &&
                  command.args.contains('ignore-hosts'),
            )
            .args
            .last,
        "['localhost', '127.0.0.1']",
      );
    });

    test('builds empty GNOME ignore-hosts as an empty list', () {
      final commands = LinuxProxyCommands.buildStart(
        port: 7890,
        bypassDomain: const [],
        desktop: 'GNOME',
        homeDir: '/home/user',
      );

      expect(
        commands
            .singleWhere(
              (command) =>
                  command.args.contains('org.gnome.system.proxy') &&
                  command.args.contains('ignore-hosts'),
            )
            .args
            .last,
        '[]',
      );
    });

    test('escapes backslashes and quotes in GNOME ignore-hosts', () {
      final commands = LinuxProxyCommands.buildStart(
        port: 7890,
        bypassDomain: [r'local\host', "it's"],
        desktop: 'GNOME',
        homeDir: '/home/user',
      );

      expect(
        commands
            .singleWhere((command) => command.args.contains('ignore-hosts'))
            .args
            .last,
        r"['local\\host', 'it\'s']",
      );
    });

    test('builds MATE commands with MATE proxy schema', () {
      final commands = LinuxProxyCommands.buildStart(
        port: 7890,
        bypassDomain: ['localhost'],
        desktop: 'MATE',
        homeDir: '/home/user',
      );

      expect(
        commands.any(
          (command) => command.args.contains('org.mate.system.proxy'),
        ),
        isTrue,
      );
      expect(
        commands.any(
          (command) => command.args.contains('org.gnome.system.proxy'),
        ),
        isFalse,
      );
    });

    test('falls back to GNOME gsettings commands for XFCE when available', () {
      final commands = LinuxProxyCommands.buildStart(
        port: 7890,
        bypassDomain: ['localhost'],
        desktop: 'XFCE',
        homeDir: '/home/user',
        availableExecutables: {'gsettings'},
      );

      expect(commands.map((command) => command.executable).toSet(), {
        'gsettings',
      });
      expect(
        commands.any(
          (command) =>
              command.args.contains('org.gnome.system.proxy') &&
              command.args.contains('manual'),
        ),
        isTrue,
      );
    });

    test('prefers kwriteconfig6 for KDE when available', () {
      final commands = LinuxProxyCommands.buildStart(
        port: 7890,
        bypassDomain: ['localhost'],
        desktop: 'KDE',
        homeDir: '/home/user',
        availableExecutables: {'kwriteconfig6', 'kwriteconfig5'},
      );

      expect(commands.map((command) => command.executable).toSet(), {
        'kwriteconfig6',
      });
    });

    test(
      'falls back to kwriteconfig5 for KDE when kwriteconfig6 is missing',
      () {
        final commands = LinuxProxyCommands.buildStart(
          port: 7890,
          bypassDomain: ['localhost'],
          desktop: 'KDE',
          homeDir: '/home/user',
          availableExecutables: {'kwriteconfig5'},
        );

        expect(commands.map((command) => command.executable).toSet(), {
          'kwriteconfig5',
        });
      },
    );

    test('uses available backend for unknown desktops', () {
      final commands = LinuxProxyCommands.buildStart(
        port: 7890,
        bypassDomain: ['localhost'],
        desktop: 'UNKNOWN',
        homeDir: '/home/user',
        availableExecutables: {'kwriteconfig5'},
      );

      expect(commands.map((command) => command.executable).toSet(), {
        'kwriteconfig5',
      });
    });

    test('does not use an unrelated backend for a known desktop', () {
      final commands = LinuxProxyCommands.buildStart(
        port: 7890,
        bypassDomain: ['localhost'],
        desktop: 'KDE',
        homeDir: '/home/user',
        availableExecutables: {'gsettings'},
      );

      expect(commands, isEmpty);
    });
  });

  group('macOS proxy command builders', () {
    test(
      'filters networksetup service list headers, disabled services, and blanks',
      () {
        final services = MacosProxyCommands.parseNetworkServices('''
An asterisk (*) denotes that a network service is disabled.
Wi-Fi
*Thunderbolt Bridge
USB 10/100/1000 LAN

''');

        expect(services, ['Wi-Fi', 'USB 10/100/1000 LAN']);
      },
    );

    test('passes bypass domains as separate networksetup arguments', () {
      final command = MacosProxyCommands.buildProxyBypass('Wi-Fi', [
        'localhost',
        '127.0.0.1',
      ]);

      expect(command.executable, '/usr/sbin/networksetup');
      expect(command.args, [
        '-setproxybypassdomains',
        'Wi-Fi',
        'localhost',
        '127.0.0.1',
      ]);
    });

    test('uses Empty when clearing bypass domains', () {
      final command = MacosProxyCommands.buildProxyBypass('Wi-Fi', const []);

      expect(command.args, ['-setproxybypassdomains', 'Wi-Fi', 'Empty']);
    });

    test('configures values before enabling proxy states', () {
      final commands = MacosProxyCommands.buildStart('Wi-Fi', 7890, const [
        'localhost',
      ]);

      final firstStateCommand = commands.indexWhere(
        (command) =>
            command.args.first == '-setwebproxystate' ||
            command.args.first == '-setsecurewebproxystate' ||
            command.args.first == '-setsocksfirewallproxystate',
      );

      expect(commands.first.args, ['-setautoproxystate', 'Wi-Fi', 'off']);
      expect(firstStateCommand, 5);
      expect(commands[4].args.first, '-setproxybypassdomains');
    });

    test('finds the primary network service from the default device', () {
      expect(
        MacosProxyCommands.parseDefaultDevice('''
   route to: default
destination: default
  interface: en0
'''),
        'en0',
      );
      expect(
        MacosProxyCommands.parseNetworkServiceOrder('''
(1) Wi-Fi
(Hardware Port: Wi-Fi, Device: en0)
(2) USB LAN
(Hardware Port: USB LAN, Device: en7)
'''),
        {'en0': 'Wi-Fi', 'en7': 'USB LAN'},
      );
    });

    test('requires HTTP HTTPS and SOCKS effective readback to match', () {
      final state = MacosEffectiveProxyState.parse('''
<dictionary> {
  HTTPEnable : 1
  HTTPPort : 7890
  HTTPProxy : 127.0.0.1
  HTTPSEnable : 1
  HTTPSPort : 7890
  HTTPSProxy : 127.0.0.1
  SOCKSEnable : 1
  SOCKSPort : 7890
  SOCKSProxy : 127.0.0.1
}
''');

      expect(state.matches(7890), isTrue);
      expect(state.matches(7891), isFalse);
      expect(state.primaryServer, '127.0.0.1:7890');
    });

    test(
      'uses primary service and restores its original proxy state',
      () async {
        final calls = <List<String>>[];
        var effectiveEnabled = false;
        final proxy = MacosProxy(
          commandRunner: ProxyCommandRunner((
            executable,
            arguments, {
            runInShell = false,
          }) async {
            calls.add([executable, ...arguments]);
            if (arguments.firstOrNull == '-listallnetworkservices') {
              return ProcessResult(1, 0, 'Wi-Fi\nUSB LAN\n', '');
            }
            if (executable == '/sbin/route') {
              return ProcessResult(1, 0, 'interface: en0\n', '');
            }
            if (arguments.firstOrNull == '-listnetworkserviceorder') {
              return ProcessResult(
                1,
                0,
                '(1) Wi-Fi\n(Hardware Port: Wi-Fi, Device: en0)\n'
                    '(2) USB LAN\n(Hardware Port: USB LAN, Device: en7)\n',
                '',
              );
            }
            if ({
              '-getwebproxy',
              '-getsecurewebproxy',
              '-getsocksfirewallproxy',
            }.contains(arguments.firstOrNull)) {
              return ProcessResult(
                1,
                0,
                'Enabled: No\nServer: old.proxy\nPort: 8080\n',
                '',
              );
            }
            if (arguments.firstOrNull == '-getautoproxyurl') {
              return ProcessResult(
                1,
                0,
                'URL: http://old/pac\nEnabled: Yes\n',
                '',
              );
            }
            if (arguments.firstOrNull == '-getproxybypassdomains') {
              return ProcessResult(1, 0, 'localhost\n', '');
            }
            if (executable == '/usr/sbin/scutil') {
              return ProcessResult(
                1,
                0,
                effectiveEnabled
                    ? '''
HTTPEnable : 1
HTTPPort : 7890
HTTPProxy : 127.0.0.1
HTTPSEnable : 1
HTTPSPort : 7890
HTTPSProxy : 127.0.0.1
SOCKSEnable : 1
SOCKSPort : 7890
SOCKSProxy : 127.0.0.1
'''
                    : '<dictionary> {\n}\n',
                '',
              );
            }
            if (arguments.firstOrNull == '-setsocksfirewallproxystate' &&
                arguments.last == 'on') {
              effectiveEnabled = true;
            }
            if (arguments.firstOrNull == '-setsocksfirewallproxystate' &&
                arguments.last == 'off') {
              effectiveEnabled = false;
            }
            return ProcessResult(1, 0, '', '');
          }),
        );

        final started = await proxy.startDetailed(7890, const ['localhost']);
        final stopped = await proxy.stopDetailed(expectedPort: 7890);

        expect(started.success, isTrue);
        expect(started.connectionName, 'Wi-Fi');
        expect(stopped.success, isTrue);
        expect(
          calls.where((call) => call.contains('-setwebproxy')).toList(),
          containsAll([
            [
              '/usr/sbin/networksetup',
              '-setwebproxy',
              'Wi-Fi',
              '127.0.0.1',
              '7890',
            ],
            [
              '/usr/sbin/networksetup',
              '-setwebproxy',
              'Wi-Fi',
              'old.proxy',
              '8080',
            ],
          ]),
        );
        expect(
          calls
              .where((call) => call.contains('-setwebproxy'))
              .any((call) => call.contains('USB LAN')),
          isFalse,
        );
      },
    );

    test(
      'keeps fallback services armed while no primary route exists',
      () async {
        final proxy = MacosProxy(
          commandRunner: ProxyCommandRunner((
            executable,
            arguments, {
            runInShell = false,
          }) async {
            if (arguments.firstOrNull == '-listallnetworkservices') {
              return ProcessResult(1, 0, 'Wi-Fi\n', '');
            }
            if (executable == '/sbin/route') {
              return ProcessResult(1, 1, '', 'no route');
            }
            if (arguments.firstOrNull == '-listnetworkserviceorder') {
              return ProcessResult(1, 0, '', '');
            }
            if ({
              '-getwebproxy',
              '-getsecurewebproxy',
              '-getsocksfirewallproxy',
            }.contains(arguments.firstOrNull)) {
              return ProcessResult(1, 0, 'Enabled: No\nServer:\nPort: 0\n', '');
            }
            if (arguments.firstOrNull == '-getautoproxyurl') {
              return ProcessResult(1, 0, 'URL:\nEnabled: No\n', '');
            }
            if (arguments.firstOrNull == '-getproxybypassdomains') {
              return ProcessResult(
                1,
                0,
                "There aren't any bypass domains set on Wi-Fi.\n",
                '',
              );
            }
            if (executable == '/usr/sbin/scutil') {
              return ProcessResult(1, 0, '<dictionary> {\n}\n', '');
            }
            return ProcessResult(1, 0, '', '');
          }),
        );

        final result = await proxy.startDetailed(7890, const []);

        expect(result.success, isTrue);
        expect(result.stage, 'fallback_pending');
        expect(result.fallbackUsed, isTrue);
      },
    );

    test('reports failure when no active network service is found', () async {
      var callCount = 0;
      final proxy = MacosProxy(
        commandRunner: ProxyCommandRunner((
          executable,
          arguments, {
          runInShell = false,
        }) async {
          callCount++;
          return ProcessResult(
            callCount,
            0,
            'An asterisk (*) denotes that a network service is disabled.\n',
            '',
          );
        }),
      );

      expect(await proxy.start(7890, const []), isFalse);
      expect(callCount, 1);
    });
  });

  group('MethodChannelProxy', () {
    final proxy = MethodChannelProxy();

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(proxy.methodChannel, null);
    });

    test('sends the Windows start contract', () async {
      MethodCall? capturedCall;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(proxy.methodChannel, (call) async {
            capturedCall = call;
            return true;
          });

      final result = await proxy.startProxy(7890, const ['localhost']);

      expect(result, isTrue);
      expect(capturedCall?.method, 'StartProxyDetailed');
      expect(capturedCall?.arguments, {
        'port': 7890,
        'bypassDomain': ['localhost'],
      });
    });

    test('maps a null native response to false', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(proxy.methodChannel, (_) async => null);

      expect(await proxy.stopProxy(), isFalse);
    });

    test('sends the guarded Windows stop contract', () async {
      MethodCall? capturedCall;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(proxy.methodChannel, (call) async {
            capturedCall = call;
            return {
              'success': true,
              'operation': 'stop',
              'stage': 'verified',
              'enabled': false,
            };
          });

      final result = await proxy.stopProxyDetailed(expectedPort: 7890);

      expect(result.success, isTrue);
      expect(capturedCall?.method, 'StopProxyDetailed');
      expect(capturedCall?.arguments, {'expectedPort': 7890});
    });

    test('parses detailed Windows proxy failures', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(proxy.methodChannel, (_) async {
            return {
              'success': false,
              'operation': 'start',
              'stage': 'registry_write',
              'errorCode': 5,
              'connectionName': 'Work VPN',
              'enabled': false,
              'server': '',
              'fallbackUsed': true,
              'rasFailureCount': 1,
              'message': 'Access denied',
            };
          });

      final result = await proxy.startProxyDetailed(7890, const []);

      expect(result.success, isFalse);
      expect(result.diagnosticCode, 'W-PROXY-03');
      expect(result.errorCode, 5);
      expect(result.connectionName, 'Work VPN');
      expect(result.fallbackUsed, isTrue);
      expect(result.rasFailureCount, 1);
    });

    test('inspects the effective Windows proxy state', () async {
      MethodCall? capturedCall;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(proxy.methodChannel, (call) async {
            capturedCall = call;
            return {
              'success': true,
              'operation': 'inspect',
              'stage': 'verified',
              'enabled': true,
              'server': '127.0.0.1:7890',
            };
          });

      final result = await proxy.inspectProxy(7890);

      expect(result.success, isTrue);
      expect(result.enabled, isTrue);
      expect(result.server, '127.0.0.1:7890');
      expect(capturedCall?.method, 'InspectProxy');
      expect(capturedCall?.arguments, {'expectedPort': 7890});
    });
  });
}

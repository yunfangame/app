import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:proxy/src/macos_proxy.dart';
import 'package:proxy/src/proxy_command.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('MacosProxy network service verification', () {
    test(
      'start and inspect use matching service despite global PAC only',
      () async {
        final system = _NetworkSystem();
        final proxy = system.proxy();

        final started = await proxy.startDetailed(7890, ['localhost']);
        final inspected = await proxy.inspectDetailed(7890);

        expect(started.success, isTrue);
        expect(started.connectionName, 'Service A');
        expect(inspected.success, isTrue);
        expect(inspected.stage, 'verified');
        expect(inspected.server, '127.0.0.1:7890');
        expect(system.globalProxy, isNot(contains('HTTPPort')));
        expect(system.services['Service B']!.web.enabled, isFalse);
        expect(system.writes.every((args) => args[1] == 'Service A'), isTrue);
      },
    );

    group('read-only verification retries', () {
      test(
        'start recovers from a transient read failure without rewriting',
        () async {
          final system = _NetworkSystem();
          var verificationReads = 0;
          system.beforeRead = (args) {
            if (args[0] != '-getwebproxy' || system.writes.isEmpty) return;
            verificationReads++;
            if (verificationReads == 1) {
              system.readOverrides['-getwebproxy'] = ProcessResult(
                1,
                1,
                '',
                'temporary',
              );
            } else {
              system.readOverrides.remove('-getwebproxy');
            }
          };

          final result = await system.proxy().startDetailed(7890, [
            'localhost',
          ]);

          expect(result.success, isTrue);
          expect(verificationReads, 2);
          expect(system.writes, hasLength(9));
          expect(
            system.writes.where((args) => args[0] == '-setwebproxy'),
            hasLength(1),
          );
        },
      );

      test(
        'start waits for matching readback without repeating writes',
        () async {
          final system = _NetworkSystem();
          var verificationReads = 0;
          system.beforeRead = (args) {
            if (args[0] != '-getsecurewebproxy' || system.writes.isEmpty) {
              return;
            }
            verificationReads++;
            if (verificationReads == 1) {
              system.readOverrides[args[0]] =
                  'Enabled: No\nServer: 127.0.0.1\nPort: 7890\n';
            } else {
              system.readOverrides.remove(args[0]);
            }
          };

          final result = await system.proxy().startDetailed(7890, []);

          expect(result.success, isTrue);
          expect(verificationReads, 2);
          expect(system.writes, hasLength(9));
        },
      );

      test(
        'inspect recovers from transient primary identity unavailability',
        () async {
          final system = _NetworkSystem();
          system.services['Service A']!.enableOwned();
          system.beforeServiceNameRead = (count) {
            if (count == 1) {
              system.serviceNames.remove(_NetworkSystem.serviceAId);
            } else {
              system.serviceNames[_NetworkSystem.serviceAId] = 'Service A';
            }
          };

          final result = await system.proxy().inspectDetailed(7890);

          expect(result.success, isTrue);
          expect(result.connectionName, 'Service A');
          expect(system.primaryReads, 3);
          expect(system.writes, isEmpty);
        },
      );

      test(
        'persistent wrong endpoint fails after three read attempts',
        () async {
          final system = _NetworkSystem();
          system.services['Service A']!.enableOwned();
          system.services['Service A']!.secureWeb.port = 7897;

          final result = await system.proxy().inspectDetailed(7890);

          expect(result.success, isFalse);
          expect(result.stage, 'readback_mismatch');
          expect(
            system.getterReads.where((args) => args[0] == '-getwebproxy'),
            hasLength(3),
          );
          expect(system.writes, isEmpty);
        },
      );

      test(
        'continuous service switching never yields a stable verification',
        () async {
          final system = _NetworkSystem();
          for (final state in system.services.values) {
            state.enableOwned();
          }
          system.beforeRead = (args) {
            if (args[0] == '-getsecurewebproxy') {
              system.primaryId = args[1] == 'Service A'
                  ? _NetworkSystem.serviceBId
                  : _NetworkSystem.serviceAId;
            }
          };

          final result = await system.proxy().inspectDetailed(7890);

          expect(result.success, isFalse);
          expect(result.stage, 'service_discovery');
          expect(
            system.getterReads.where((args) => args[0] == '-getwebproxy'),
            hasLength(3),
          );
          expect(system.writes, isEmpty);
        },
      );

      test('switch to an incorrectly configured service still fails', () async {
        final system = _NetworkSystem();
        system.services['Service A']!.enableOwned();
        system.beforeRead = (args) {
          if (args[0] == '-getsecurewebproxy' && args[1] == 'Service A') {
            system.primaryId = _NetworkSystem.serviceBId;
          }
        };

        final result = await system.proxy().inspectDetailed(7890);

        expect(result.success, isFalse);
        expect(result.connectionName, 'Service B');
        expect(
          system.getterReads.where((args) => args[0] == '-getwebproxy'),
          hasLength(3),
        );
        expect(system.writes, isEmpty);
      });

      test('a later stable correctly configured service can verify', () async {
        final system = _NetworkSystem();
        for (final state in system.services.values) {
          state.enableOwned();
        }
        system.beforeRead = (args) {
          if (args[0] == '-getsecurewebproxy' && args[1] == 'Service A') {
            system.primaryId = _NetworkSystem.serviceBId;
          }
        };

        final result = await system.proxy().inspectDetailed(7890);

        expect(result.success, isTrue);
        expect(result.connectionName, 'Service B');
        expect(
          system.getterReads.where((args) => args[0] == '-getwebproxy'),
          hasLength(2),
        );
        expect(system.writes, isEmpty);
      });

      test('successful first read performs no extra verification', () async {
        final system = _NetworkSystem();
        system.services['Service A']!.enableOwned();

        final result = await system.proxy().inspectDetailed(7890);

        expect(result.success, isTrue);
        expect(system.primaryReads, 2);
        expect(system.getterReads, hasLength(6));
        expect(system.writes, isEmpty);
      });
    });

    final mismatches = <String, void Function(_ServiceState)>{
      'wrong port': (state) => state.secureWeb.port = 7897,
      'one disabled protocol': (state) => state.socks.enabled = false,
      'PAC still enabled': (state) => state.pacEnabled = true,
      'WPAD still enabled': (state) => state.discovery = true,
    };
    for (final entry in mismatches.entries) {
      test('start and inspect reject ${entry.key}', () async {
        final system = _NetworkSystem();
        system.afterWrite = (args) {
          if (args[0] == '-setsocksfirewallproxystate' && args[2] == 'on') {
            entry.value(system.services[args[1]]!);
          }
        };
        final proxy = system.proxy();

        final started = await proxy.startDetailed(7890, []);
        final inspected = await proxy.inspectDetailed(7890);

        expect(started.success, isFalse);
        expect(started.stage, 'readback_mismatch');
        expect(inspected.success, isFalse);
        expect(inspected.stage, 'readback_mismatch');
      });
    }

    final failures = <String, (String, Object)>{
      'endpoint exception': (
        '-getwebproxy',
        const ProcessException('/usr/sbin/networksetup', []),
      ),
      'endpoint command failure': (
        '-getwebproxy',
        ProcessResult(1, 1, '', 'read denied'),
      ),
      'empty endpoint': ('-getwebproxy', ''),
      'missing endpoint Enabled': (
        '-getwebproxy',
        'Server: 127.0.0.1\nPort: 7890\n',
      ),
      'empty PAC': ('-getautoproxyurl', ''),
      'missing PAC Enabled': (
        '-getautoproxyurl',
        'URL: https://pac.example.invalid/service-a.pac\n',
      ),
      'empty WPAD': ('-getproxyautodiscovery', ''),
      'bypass command failure': (
        '-getproxybypassdomains',
        ProcessResult(1, 1, '', 'read denied'),
      ),
    };
    for (final entry in failures.entries) {
      test('${entry.key} stays unknown and prevents capture writes', () async {
        final system = _NetworkSystem();
        system.readOverrides[entry.value.$1] = entry.value.$2;
        final proxy = system.proxy();

        final inspected = await proxy.inspectDetailed(7890);
        final started = await proxy.startDetailed(7890, []);

        expect(inspected.success, isFalse);
        expect(inspected.stage, 'readback');
        expect(inspected.enabled, isNull);
        expect(started.success, isFalse);
        expect(started.stage, 'readback');
        expect(system.writes, isEmpty);
      });
    }

    test(
      'service switching during reads cannot combine A and B evidence',
      () async {
        final system = _NetworkSystem();
        for (final state in system.services.values) {
          state.enableOwned();
        }
        system.beforeRead = (args) {
          if (args[0] == '-getsecurewebproxy' && args[1] == 'Service A') {
            system.primaryId = _NetworkSystem.serviceBId;
          }
        };

        final result = await system
            .proxy(verificationAttempts: 1)
            .inspectDetailed(7890);

        expect(result.success, isFalse);
        expect(result.stage, 'service_discovery');
        expect(result.enabled, isNull);
        expect(system.writes, isEmpty);
      },
    );

    test(
      'changed service identity with the same name invalidates verification',
      () async {
        final system = _NetworkSystem();
        system.services['Service A']!.enableOwned();
        system.serviceNames[_NetworkSystem.serviceBId] = 'Service A';
        system.beforeRead = (args) {
          if (args[0] == '-getsecurewebproxy') {
            system.primaryId = _NetworkSystem.serviceBId;
          }
        };

        final result = await system
            .proxy(verificationAttempts: 1)
            .inspectDetailed(7890);

        expect(result.success, isFalse);
        expect(result.stage, 'service_discovery');
      },
    );

    test(
      'stop restores each visited service PAC WPAD and bypass snapshot',
      () async {
        final system = _NetworkSystem();
        final originalA = system.services['Service A']!.snapshot();
        final originalB = system.services['Service B']!.snapshot();
        final proxy = system.proxy();

        expect(
          (await proxy.startDetailed(7890, ['localhost'])).success,
          isTrue,
        );
        system.primaryId = _NetworkSystem.serviceBId;
        expect(
          (await proxy.startDetailed(7890, ['127.0.0.1'])).success,
          isTrue,
        );
        expect(system.services['Service A']!.snapshot(), isNot(originalA));
        expect(system.services['Service B']!.snapshot(), isNot(originalB));
        system.primaryId = null;
        system.routeDevice = 'unavailable';

        final stopped = await proxy.stopDetailed(expectedPort: 7890);

        expect(stopped.success, isTrue);
        expect(system.services['Service A']!.snapshot(), originalA);
        expect(system.services['Service B']!.snapshot(), originalB);
      },
    );

    for (final ipv6Only in [false, true]) {
      test('SC primary wins over utun route with ipv6Only=$ipv6Only', () async {
        final system = _NetworkSystem()
          ..primaryId = _NetworkSystem.serviceBId
          ..routeDevice = 'utun8'
          ..ipv6Only = ipv6Only;

        final started = await system.proxy().startDetailed(7890, []);

        expect(started.success, isTrue);
        expect(started.connectionName, 'Service B');
        expect(system.writes.every((args) => args[1] == 'Service B'), isTrue);
        expect(system.routeReads, 0);
      });
    }

    test(
      'unknown SC primary name cannot fall back to a plausible route',
      () async {
        final system = _NetworkSystem();
        system.serviceNames[_NetworkSystem.serviceAId] = 'Removed Service';
        final proxy = system.proxy();

        expect((await proxy.startDetailed(7890, [])).success, isFalse);
        final inspected = await proxy.inspectDetailed(7890);

        expect(inspected.success, isFalse);
        expect(inspected.stage, 'service_discovery');
        expect(system.writes, isEmpty);
        expect(system.routeReads, 0);
      },
    );

    test(
      'unresolved SC primary ID cannot fall back to another service',
      () async {
        final system = _NetworkSystem();
        system.serviceNames.remove(_NetworkSystem.serviceAId);

        final result = await system.proxy().startDetailed(7890, []);

        expect(result.success, isFalse);
        expect(result.stage, 'service_discovery');
        expect(system.writes, isEmpty);
        expect(system.routeReads, 0);
      },
    );

    test('fallback rejects two network services on the same NIC', () async {
      final system = _NetworkSystem()
        ..primaryId = null
        ..deviceB = 'en0';

      final result = await system.proxy().startDetailed(7890, []);

      expect(result.success, isFalse);
      expect(result.stage, 'service_discovery');
      expect(system.writes, isEmpty);
    });

    test(
      'stop cannot succeed while one owned endpoint remains enabled',
      () async {
        final system = _NetworkSystem();
        system.services['Service A']!.enableOwned();
        system.ignoredWrites.add('-setwebproxystate');

        final result = await system.proxy().stopDetailed(expectedPort: 7890);

        expect(system.services['Service A']!.web.enabled, isTrue);
        expect(system.services['Service A']!.secureWeb.enabled, isFalse);
        expect(system.services['Service A']!.socks.enabled, isFalse);
        expect(result.success, isFalse);
        expect(result.stage, 'restore');
      },
    );

    test(
      'cleanup without snapshot preserves third party proxy settings',
      () async {
        final system = _NetworkSystem();
        final state = system.services['Service A']!;
        state.web.enabled = true;
        state.web.port = 7890;
        state.secureWeb.enabled = true;
        state.secureWeb.server = 'proxy.example.invalid';
        state.secureWeb.port = 8080;
        final expected = state.snapshot();
        expected['web'] = [false, '127.0.0.1', 7890];
        final untouched = system.services['Service B']!.snapshot();

        final stopped = await system.proxy().stopDetailed(expectedPort: 7890);

        expect(stopped.success, isTrue);
        expect(state.snapshot(), expected);
        expect(system.services['Service B']!.snapshot(), untouched);
        expect(system.writes, [
          ['-setwebproxystate', 'Service A', 'off'],
        ]);
      },
    );

    test(
      'failed restore readback retains original snapshot for retry',
      () async {
        final system = _NetworkSystem();
        final state = system.services['Service A']!;
        final original = state.snapshot();
        final proxy = system.proxy();
        expect(
          (await proxy.startDetailed(7890, ['localhost'])).success,
          isTrue,
        );
        system.readOverrides['-getautoproxyurl'] = '';

        final firstStop = await proxy.stopDetailed(expectedPort: 7890);

        expect(firstStop.success, isFalse);
        expect(firstStop.stage, 'restore');
        expect(state.snapshot(), original);
        system.readOverrides.clear();
        state.enableOwned();
        state.pacUrl = 'https://pac.example.invalid/changed.pac';
        state.bypass = ['changed.invalid'];
        system.writes.clear();

        final secondStop = await proxy.stopDetailed(expectedPort: 7890);

        expect(secondStop.success, isTrue);
        expect(state.snapshot(), original);
        expect(
          system.writes,
          contains(
            equals(['-setautoproxyurl', 'Service A', original['pacUrl']]),
          ),
        );
      },
    );

    final coldReadFailures = <String, (String, Object)>{
      'enumeration command failure': (
        '-listallnetworkservices',
        ProcessResult(1, 1, '', 'enumeration denied'),
      ),
      'enumeration exception': (
        '-listallnetworkservices',
        const ProcessException('/usr/sbin/networksetup', []),
      ),
      'empty enumeration': ('-listallnetworkservices', ''),
      'service readback command failure': (
        '-getwebproxy',
        ProcessResult(1, 1, '', 'read denied'),
      ),
      'service readback exception': (
        '-getwebproxy',
        const ProcessException('/usr/sbin/networksetup', []),
      ),
      'empty service readback': ('-getwebproxy', ''),
    };
    for (final entry in coldReadFailures.entries) {
      test('cold stop rejects ${entry.key}', () async {
        final system = _NetworkSystem();
        system.services['Service A']!.enableOwned();
        system.readOverrides[entry.value.$1] = entry.value.$2;

        final result = await system.proxy().stopDetailed(expectedPort: 7890);

        expect(result.success, isFalse);
        expect(result.stage, isNot('verified'));
        expect(system.writes, isEmpty);
        expect(system.services['Service A']!.web.enabled, isTrue);
      });
    }
  });
}

class _Endpoint {
  bool enabled = false;
  String server = '127.0.0.1';
  int port = 7897;

  String output() =>
      'Enabled: ${enabled ? 'Yes' : 'No'}\n'
      'Server: $server\nPort: $port\nAuthenticated Proxy Enabled: 0\n';

  List<Object> snapshot() => [enabled, server, port];
}

class _ServiceState {
  _ServiceState({
    required this.pacUrl,
    required this.discovery,
    required this.bypass,
  });

  final web = _Endpoint();
  final secureWeb = _Endpoint();
  final socks = _Endpoint();
  String pacUrl;
  bool pacEnabled = true;
  bool discovery;
  List<String> bypass;

  void enableOwned() {
    for (final endpoint in [web, secureWeb, socks]) {
      endpoint.enabled = true;
      endpoint.server = '127.0.0.1';
      endpoint.port = 7890;
    }
    pacEnabled = false;
    discovery = false;
  }

  Map<String, Object> snapshot() => {
    'web': web.snapshot(),
    'secureWeb': secureWeb.snapshot(),
    'socks': socks.snapshot(),
    'pacUrl': pacUrl,
    'pacEnabled': pacEnabled,
    'discovery': discovery,
    'bypass': [...bypass],
  };
}

class _NetworkSystem {
  static const serviceAId = '11111111-1111-4111-8111-111111111111';
  static const serviceBId = '22222222-2222-4222-8222-222222222222';

  final services = <String, _ServiceState>{
    'Service A': _ServiceState(
      pacUrl: 'https://pac.example.invalid/service-a.pac',
      discovery: true,
      bypass: ['*.a.invalid', 'localhost'],
    ),
    'Service B': _ServiceState(
      pacUrl: 'https://pac.example.invalid/service-b.pac',
      discovery: false,
      bypass: ['*.b.invalid', '127.0.0.1'],
    ),
  };
  final serviceNames = <String, String>{
    serviceAId: 'Service A',
    serviceBId: 'Service B',
  };
  final writes = <List<String>>[];
  final getterReads = <List<String>>[];
  final readOverrides = <String, Object>{};
  final ignoredWrites = <String>{};
  String? primaryId = serviceAId;
  String routeDevice = 'en0';
  String deviceB = 'en5';
  bool ipv6Only = false;
  int routeReads = 0;
  int primaryReads = 0;
  int serviceNameReads = 0;
  void Function(int)? beforeServiceNameRead;
  void Function(List<String>)? beforeRead;
  void Function(List<String>)? afterWrite;
  final globalProxy =
      '<dictionary> {\n'
      '  ProxyAutoConfigEnable : 1\n'
      '  ProxyAutoConfigURLString : https://pac.example.invalid/global.pac\n'
      '}\n';

  MacosProxy proxy({int verificationAttempts = 3}) => MacosProxy(
    commandRunner: ProxyCommandRunner(run),
    verificationAttempts: verificationAttempts,
    verificationRetryInterval: Duration.zero,
  );

  Future<ProcessResult> run(
    String executable,
    List<String> arguments, {
    bool runInShell = false,
  }) async {
    expect(runInShell, isFalse);
    if (executable == '/bin/sh') {
      expect(arguments.first, '-c');
      expect(arguments, hasLength(2));
      final command = arguments[1];
      expect(command.endsWith("' | /usr/sbin/scutil"), isTrue);
      if (command.contains('show State:/Network/Global/IPv4')) {
        primaryReads++;
        expect(command, contains('show State:/Network/Global/IPv6'));
        if (primaryId == null) return _result('<dictionary> {\n}\n');
        final primary = '<dictionary> {\n  PrimaryService : $primaryId\n}\n';
        return _result(ipv6Only ? 'No such key\n$primary' : primary);
      }
      final match = RegExp(
        r'show Setup:/Network/Service/([0-9a-fA-F-]{36})',
      ).firstMatch(command);
      expect(match, isNotNull, reason: 'Unexpected shell command: $command');
      beforeServiceNameRead?.call(++serviceNameReads);
      final name = serviceNames[match!.group(1)];
      return name == null
          ? _result('No such key\n', exitCode: 1)
          : _result('<dictionary> {\n  UserDefinedName : $name\n}\n');
    }
    if (executable == '/sbin/route') {
      expect(arguments, ['-n', 'get', 'default']);
      routeReads++;
      return _result('   interface: $routeDevice\n');
    }
    if (executable == '/usr/sbin/scutil') {
      expect(arguments, ['--proxy']);
      return _result(globalProxy);
    }
    expect(executable, '/usr/sbin/networksetup');
    final flag = arguments.first;
    if (flag == '-listallnetworkservices') {
      final override = readOverrides[flag];
      if (override is ProcessException) throw override;
      if (override is ProcessResult) return override;
      if (override is String) return _result(override);
      return _result(
        'An asterisk (*) denotes that a network service is disabled.\n'
        '${services.keys.join('\n')}\n',
      );
    }
    if (flag == '-listnetworkserviceorder') {
      return _result(
        '(1) Service A\n(Hardware Port: Wi-Fi, Device: en0)\n'
        '(2) Service B\n(Hardware Port: Ethernet, Device: $deviceB)\n',
      );
    }
    expect(arguments.length, greaterThanOrEqualTo(2));
    final state = services[arguments[1]];
    expect(state, isNotNull);
    if (flag.startsWith('-get')) {
      getterReads.add([...arguments]);
      beforeRead?.call(arguments);
      final override = readOverrides[flag];
      if (override is ProcessException) throw override;
      if (override is ProcessResult) return override;
      if (override is String) return _result(override);
      return switch (flag) {
        '-getwebproxy' => _result(state!.web.output()),
        '-getsecurewebproxy' => _result(state!.secureWeb.output()),
        '-getsocksfirewallproxy' => _result(state!.socks.output()),
        '-getautoproxyurl' => _result(
          'URL: ${state!.pacUrl}\nEnabled: ${state.pacEnabled ? 'Yes' : 'No'}\n',
        ),
        '-getproxyautodiscovery' => _result(
          'Auto Proxy Discovery: ${state!.discovery ? 'On' : 'Off'}\n',
        ),
        '-getproxybypassdomains' => _result(
          state!.bypass.isEmpty
              ? "There aren't any bypass domains set on ${arguments[1]}.\n"
              : '${state.bypass.join('\n')}\n',
        ),
        _ => throw StateError('Unexpected read: $arguments'),
      };
    }
    expect(flag, startsWith('-set'));
    writes.add([...arguments]);
    if (ignoredWrites.contains(flag)) return _result('');
    final endpoint = switch (flag) {
      '-setwebproxy' || '-setwebproxystate' => state!.web,
      '-setsecurewebproxy' || '-setsecurewebproxystate' => state!.secureWeb,
      '-setsocksfirewallproxy' || '-setsocksfirewallproxystate' => state!.socks,
      _ => null,
    };
    if (endpoint != null) {
      if (flag.endsWith('state')) {
        endpoint.enabled = arguments[2] == 'on';
      } else {
        endpoint.server = arguments[2];
        endpoint.port = int.parse(arguments[3]);
      }
    } else {
      switch (flag) {
        case '-setautoproxystate':
          state!.pacEnabled = arguments[2] == 'on';
        case '-setautoproxyurl':
          state!.pacUrl = arguments[2];
        case '-setproxyautodiscovery':
          state!.discovery = arguments[2] == 'on';
        case '-setproxybypassdomains':
          state!.bypass = arguments[2] == 'Empty' ? [] : arguments.sublist(2);
        default:
          throw StateError('Unexpected write: $arguments');
      }
    }
    afterWrite?.call(arguments);
    return _result('');
  }

  ProcessResult _result(String stdout, {int exitCode = 0}) =>
      ProcessResult(1, exitCode, stdout, '');
}

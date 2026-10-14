import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/core/core.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/main.dart' as application;
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/state.dart';

Future<void> main() async {
  if (!Platform.isWindows ||
      Platform.environment['GITHUB_ACTIONS'] != 'true' ||
      Platform.environment['RUNNER_OS'] != 'Windows') {
    exit(64);
  }
  final home = Platform.environment['FENGWO_NETWORK_TEST_HOME'];
  if (home == null || home.isEmpty) exit(64);
  final directory = Directory(home);
  final settings =
      jsonDecode(await File('$home/fixture.json').readAsString())
          as Map<String, dynamic>;
  Future<void> record(String phase, [Map<String, Object?> fields = const {}]) =>
      File(
        '$home/$phase.json',
      ).writeAsString(jsonEncode({'phase': phase, ...fields}), flush: true);
  try {
    await application.main();
    await _waitFor(() async {
      if (globalState.logoutXboard == null || !globalState.isAttach) {
        return false;
      }
      return globalState.container.read(initProvider) &&
          globalState.container.read(coreStatusProvider) ==
              CoreStatus.connected;
    });
    await Future<void>.delayed(const Duration(seconds: 3));
    final container = globalState.container;
    final port = settings['port'] as int;
    final tun = settings['tun'] as bool;
    final systemProxy = settings['proxy'] as bool;
    final device = settings['device'] as String;
    final endpoint = Uri.parse('http://127.0.0.1:9');
    final session = XboardLoginResult(
      endpoint: endpoint,
      token: '',
      authData: '',
      isAdmin: false,
      subscription: XboardSubscriptionData(
        endpoint: endpoint,
        subscribeUrl: null,
        uploadBytes: 0,
        downloadBytes: 0,
        transferEnableBytes: 1,
        rawData: const {},
      ),
    );
    container
        .read(networkSettingProvider.notifier)
        .update((state) => state.copyWith(systemProxy: systemProxy));
    container
        .read(patchClashConfigProvider.notifier)
        .update(
          (state) => state.copyWith(
            mixedPort: port,
            tun: Tun(
              enable: tun,
              device: device,
              autoRoute: true,
              stack: TunStack.gvisor,
              dnsHijack: const [],
            ),
          ),
        );
    container.read(authorizedTunEnableProvider.notifier).value =
        TunAuthorizationState.authorized;
    await Future<void>.delayed(const Duration(seconds: 3));
    await File(await appPath.configFilePath).writeAsString('''
mixed-port: $port
allow-lan: false
bind-address: 127.0.0.1
mode: rule
log-level: warning
ipv6: false
find-process-mode: off
external-controller: ''
geodata-mode: false
geo-auto-update: false
dns:
  enable: false
tun:
  enable: $tun
  device: $device
  stack: gvisor
  auto-route: true
  auto-detect-interface: true
  dns-hijack: []
proxies: []
proxy-groups: []
rules:
  - MATCH,DIRECT
''', flush: true);
    final setupResult = await coreController.setupConfig(
      params: const SetupParams(
        selectedMap: {},
        testUrl: 'https://www.baidu.com',
      ),
    );
    if (setupResult.isNotEmpty) throw StateError(setupResult);

    Future<void> connect(String phase) async {
      if (!await coreController.startListener()) {
        throw StateError('The real Core listener did not start');
      }
      container.read(runTimeProvider.notifier).value = 0;
      container.read(windowsTunReadyProvider.notifier).value = tun;
      globalState.activateXboardSession(session);
      if (systemProxy) {
        await _waitFor(() async {
          final result = await proxy!.inspectProxy(port);
          return result.success &&
              result.enabled == true &&
              (result.server ?? '').contains('127.0.0.1:$port');
        });
      }
      await Future<void>.delayed(const Duration(seconds: 2));
      await tray!.update(
        trayState: container.read(trayStateProvider),
        traffic: const Traffic(),
      );
      await commonPrint.flushDiagnosticEvents();
      await record(phase, {'port': port, 'tun': tun, 'proxy': systemProxy});
    }

    await connect('active');
    final command = File('${directory.path}/command.txt');
    while (true) {
      if (await command.exists()) {
        final value = (await command.readAsString()).trim();
        await command.delete();
        if (value == 'logout') {
          await globalState.logoutXboard!();
          if (globalState.xboardSession != null ||
              container.read(isStartProvider) ||
              container.read(tunActiveProvider)) {
            throw StateError('Logout did not clear session and running state');
          }
          await record('logged-out');
        } else if (value == 'reconnect') {
          await connect('reconnected');
        } else {
          throw StateError('Unknown fixture command');
        }
      }
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
  } catch (error, stackTrace) {
    await record('failed', {'error': '$error', 'stack': '$stackTrace'});
    await commonPrint.flushDiagnosticEvents();
    exit(1);
  }
}

Future<void> _waitFor(Future<bool> Function() check) async {
  final watch = Stopwatch()..start();
  while (watch.elapsed < const Duration(seconds: 60)) {
    if (await check()) return;
    await Future<void>.delayed(const Duration(milliseconds: 250));
  }
  throw TimeoutException('Native application readiness timed out');
}

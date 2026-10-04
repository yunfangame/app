import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/common/startup_connection_coordinator.dart';
import 'package:fl_clash/common/windows_preferences.dart';
import 'package:fl_clash/core/core.dart';
import 'package:fl_clash/database/database.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/manager/core_manager.dart';
import 'package:fl_clash/manager/proxy_manager.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:rust_api/rust_api.dart';

Future<void> main() async {
  final environment = Platform.environment;
  if (!Platform.isWindows ||
      environment['GITHUB_ACTIONS'] != 'true' ||
      environment['RUNNER_OS'] != 'Windows' ||
      environment['FENGWO_STARTUP_NATIVE_CI'] != '1') {
    stderr.writeln(
      'Native startup probe requires its isolated Windows CI supervisor.',
    );
    exit(64);
  }
  final reportPath = environment['FENGWO_STARTUP_NATIVE_REPORT'];
  if (reportPath == null || !path.isAbsolute(reportPath)) {
    stderr.writeln('An absolute native report path is required.');
    exit(64);
  }
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MaterialApp(home: SizedBox.shrink()));
  await WidgetsBinding.instance.endOfFrame;
  final probe = _NativeStartupProbe(File(reportPath));
  await probe.execute();
  exit(probe.passed ? 0 : 1);
}

class _NativeStartupProbe {
  _NativeStartupProbe(this.reportFile);

  final File reportFile;
  final cases = <Map<String, Object?>>[];
  final errors = <String>[];
  final cleanup = <String, Object?>{};
  final coordinators = <StartupConnectionCoordinator>[];
  final heldResponses = <HttpResponse>[];
  final pendingProbes = <Future<void>>[];
  final cancelRequestEntered = Completer<void>();
  final originalPathProvider = PathProviderPlatform.instance;
  ProviderContainer? container;
  Directory? dataDirectory;
  HttpServer? server;
  StreamSubscription<HttpRequest>? requests;
  ProviderSubscription<Config>? configSubscription;
  int mixedPort = 0;
  bool mounted = false;
  bool coreStarted = false;
  bool passed = false;
  int probes = 0;
  int connects = 0;
  int localRequests = 0;
  int discardedProbeResults = 0;
  bool timeoutReleased = false;
  bool cancellationReleased = false;
  static const fixtureGroup = 'NativeStartupFixture';
  static const responseBody = 'fengwo-native-startup-loopback';

  ProviderContainer get state => container!;
  SetupAction get setup => state.read(setupActionProvider.notifier);
  Uri endpoint(String route) =>
      Uri.parse('http://127.0.0.1:${server!.port}/$route');

  Future<void> execute() async {
    final startedAt = DateTime.now().toUtc();
    try {
      await _initialize();
      await _defaultOff();
      await _enabledOnce();
      await _timeoutRetainsSelection();
      await _cancelPendingProbe();
      passed = true;
    } catch (error, stack) {
      errors.add('$error');
      stderr.writeln('$error\n$stack');
    } finally {
      await _cleanup();
      passed = passed && errors.isEmpty;
      await reportFile.parent.create(recursive: true);
      await reportFile.writeAsString(
        const JsonEncoder.withIndent('  ').convert({
          'status': passed ? 'passed' : 'failed',
          'started_at_utc': startedAt.toIso8601String(),
          'completed_at_utc': DateTime.now().toUtc().toIso8601String(),
          'platform': Platform.operatingSystemVersion,
          'pid': pid,
          'mixed_port': mixedPort,
          'auth': {
            'mode': 'synthetic_authenticated_gate',
            'actual_login_verified': false,
          },
          'bootstrap': {
            'mode': 'fixture_after_real_core_configuration',
            'data_directory_isolated': dataDirectory != null,
            'application_login_bootstrap_verified': false,
            'cold_restart_verified': false,
          },
          'native_components': [
            'StartupConnectionCoordinator',
            'CommonAction.startAfterLogin',
            'SetupAction.startAutomatically',
            'CoreController',
            'CoreManager',
            'ProxyManager',
            'Windows proxy plugin',
          ],
          'fixture': {
            'route': 'local_http_direct',
            'selected_group': fixtureGroup,
            'selected_proxy': 'DIRECT',
            'tun_enabled': false,
          },
          'probe_callbacks': probes,
          'connect_callbacks': connects,
          'local_http_requests': localRequests,
          'late_probe_results_discarded': discardedProbeResults,
          'cases': cases,
          'cleanup': cleanup,
          'errors': errors,
        }),
        flush: true,
      );
    }
  }

  Future<void> _initialize() async {
    dataDirectory = await Directory.systemTemp.createTemp(
      'fengwo-startup-native-',
    );
    PathProviderPlatform.instance = _FixturePaths(dataDirectory!.path);
    installWindowsPreferencesStore(
      store: WindowsPreferencesStore(
        directoryLoader: () async => dataDirectory!,
      ),
    );
    await RustLib.init();
    final version = await system.init();
    container = await globalState.init(version);
    configSubscription = state.listen(configProvider, (_, _) {});
    _require(
      !state.read(appSettingProvider).autoRun,
      'Fresh settings must default off',
    );
    _require(
      !AppSettingProps.fromJson({}).autoRun,
      'Older settings must default off',
    );
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    requests = server!.listen(_onRequest);
    final reserved = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    mixedPort = reserved.port;
    await reserved.close();
    final initialProxy = await proxy!.inspectProxy(mixedPort);
    _require(
      initialProxy.enabled == false,
      'Supervisor must provide an account without an enabled proxy',
    );
    state.read(networkSettingProvider.notifier).value = const NetworkProps(
      systemProxy: false,
      autoSetSystemDns: false,
      appendSystemDns: false,
    );
    state.read(patchClashConfigProvider.notifier).value = PatchClashConfig(
      mixedPort: mixedPort,
      mode: Mode.rule,
      dns: const Dns(enable: false),
      tun: const Tun(enable: false),
    );
    state
        .read(appSettingProvider.notifier)
        .update(
          (value) => value.copyWith(testUrl: endpoint('probe').toString()),
        );
    await state.read(coreActionProvider.notifier).startCore();
    coreStarted = true;
    _require(
      state.read(coreStatusProvider) == CoreStatus.connected,
      'Real Core did not initialize',
    );
    final profile = await Profile.normal(label: fixtureGroup)
        .copyWith(
          currentGroupName: fixtureGroup,
          selectedMap: const {fixtureGroup: 'DIRECT'},
          autoUpdate: false,
        )
        .saveFile(
          Uint8List.fromList(
            utf8.encode(
              jsonEncode({
                'mixed-port': mixedPort,
                'mode': 'rule',
                'dns': {'enable': false},
                'tun': {'enable': false},
                'proxies': <Object>[],
                'proxy-groups': [
                  {
                    'name': fixtureGroup,
                    'type': 'select',
                    'proxies': ['DIRECT', 'REJECT'],
                  },
                ],
                'rules': ['MATCH,$fixtureGroup'],
              }),
            ),
          ),
        );
    await state.read(profilesProvider.notifier).putDurable(profile);
    state.read(currentProfileIdProvider.notifier).value = profile.id;
    await setup.initStatus();
    state.read(initProvider.notifier).value = true;
    runApp(
      UncontrolledProviderScope(
        container: state,
        child: MaterialApp(
          navigatorKey: globalState.navigatorKey,
          home: ProxyManager(
            child: CoreManager(child: const SizedBox.shrink()),
          ),
        ),
      ),
    );
    mounted = true;
    await WidgetsBinding.instance.endOfFrame;
    await _assertStopped();
    await _assertSelection();
  }

  void _onRequest(HttpRequest request) {
    localRequests++;
    if (request.uri.path == '/cancel' && !cancellationReleased) {
      heldResponses.add(request.response);
      if (!cancelRequestEntered.isCompleted) cancelRequestEntered.complete();
      return;
    }
    if (request.uri.path == '/timeout' && !timeoutReleased) {
      heldResponses.add(request.response);
      return;
    }
    request.response
      ..statusCode = HttpStatus.ok
      ..write(responseBody);
    unawaited(request.response.close());
  }

  StartupConnectionCoordinator _coordinator({Duration? timeout}) {
    final coordinator = timeout == null
        ? StartupConnectionCoordinator()
        : StartupConnectionCoordinator(probeTimeout: timeout);
    coordinators.add(coordinator);
    return coordinator;
  }

  bool _canProceed() =>
      state.read(appSettingProvider).autoRun &&
      state.read(initProvider) &&
      state.read(coreStatusProvider) == CoreStatus.connected;

  Future<void> _run(
    StartupConnectionCoordinator coordinator,
    StartupConnectionAttempt attempt, {
    String route = 'probe',
    void Function(Object)? onProbeError,
  }) {
    return coordinator.run(
      attempt,
      authenticated: true,
      routingReady: true,
      canProceed: _canProceed,
      testLatency: (isCurrent) {
        probes++;
        final operation = () async {
          final delay = await coreController.getDelay(
            endpoint(route).toString(),
            'DIRECT',
          );
          if (isCurrent()) {
            state.read(proxiesActionProvider.notifier).setDelay(delay);
          } else {
            discardedProbeResults++;
          }
          if (route == 'probe') {
            _require(
              delay.value != null && delay.value! >= 0,
              'Real Core latency probe failed',
            );
          }
        }();
        pendingProbes.add(
          operation.then<void>((_) {}, onError: (Object _, StackTrace _) {}),
        );
        return operation;
      },
      isConnected: () =>
          state.read(isStartProvider) || state.read(connectionPendingProvider),
      connect: () async {
        connects++;
        await state
            .read(commonActionProvider.notifier)
            .startAfterLogin(isCurrent: _canProceed);
      },
      onProbeError: (error) {
        if (onProbeError == null) {
          throw StateError('Unexpected native probe error: $error');
        }
        onProbeError(error);
      },
      onConnectionError: (error) =>
          throw StateError('Native automatic connection failed: $error'),
    );
  }

  Future<void> _defaultOff() async {
    final coordinator = _coordinator();
    final attempt = coordinator.begin(
      enabled: state.read(appSettingProvider).autoRun,
      isCurrent: () => true,
    );
    await _run(coordinator, attempt);
    _require(
      probes == 0 && connects == 0,
      'Disabled startup invoked automatic work',
    );
    await _assertStopped();
    cases.add({
      'name': 'default_off',
      'passed': true,
      'probes': 0,
      'connects': 0,
    });
  }

  Future<void> _enabledOnce() async {
    state
        .read(appSettingProvider.notifier)
        .update((value) => value.copyWith(autoRun: true));
    final coordinator = _coordinator();
    final attempt = coordinator.begin(enabled: true, isCurrent: () => true);
    await Future.wait([
      _run(coordinator, attempt),
      _run(coordinator, attempt),
      _run(coordinator, attempt),
    ]);
    await _assertConnected();
    await _run(coordinator, attempt);
    _require(
      probes == 1 && connects == 1,
      'Repeated readiness did not coalesce',
    );
    await _assertSelection();
    cases.add({
      'name': 'enabled_native_connect_once',
      'passed': true,
      'probes': 1,
      'connects': 1,
    });
    await _stop();
  }

  Future<void> _timeoutRetainsSelection() async {
    var timeoutErrors = 0;
    final coordinator = _coordinator(
      timeout: const Duration(milliseconds: 250),
    );
    final attempt = coordinator.begin(enabled: true, isCurrent: () => true);
    await _run(
      coordinator,
      attempt,
      route: 'timeout',
      onProbeError: (error) {
        _require(
          error is TimeoutException,
          'Controlled probe did not time out',
        );
        timeoutErrors++;
      },
    );
    _require(
      timeoutErrors == 1 && probes == 2 && connects == 2,
      'Timeout did not connect exactly once',
    );
    await _assertConnected();
    await _assertSelection();
    await _releaseHeldResponses();
    await Future.wait(pendingProbes).timeout(const Duration(seconds: 8));
    await _assertSelection();
    cases.add({
      'name': 'native_probe_timeout_retains_direct',
      'passed': true,
      'coordinator_timeout_ms': 250,
      'default_timeout_verified': false,
    });
    await _stop();
  }

  Future<void> _cancelPendingProbe() async {
    final coordinator = _coordinator();
    final revision = state
        .read(proxiesActionProvider.notifier)
        .manualSelectionRevision;
    final attempt = coordinator.begin(
      enabled: true,
      isCurrent: () =>
          state.read(proxiesActionProvider.notifier).manualSelectionRevision ==
          revision,
    );
    final running = _run(coordinator, attempt, route: 'cancel');
    await cancelRequestEntered.future.timeout(const Duration(seconds: 8));
    await setup.setRunning(false, propagateErrors: true);
    state
        .read(appSettingProvider.notifier)
        .update((value) => value.copyWith(autoRun: false));
    coordinator.cancel();
    await running.timeout(const Duration(seconds: 2));
    await _releaseHeldResponses(releaseCancellation: true);
    await Future.wait(pendingProbes).timeout(const Duration(seconds: 8));
    _require(
      probes == 3 && connects == 2,
      'Cancelled native probe initiated a connection',
    );
    await _assertStopped();
    await _assertSelection();
    cases.add({
      'name': 'cancel_during_native_probe',
      'passed': true,
      'new_connects': 0,
    });
  }

  Future<void> _assertConnected() async {
    _require(
      state.read(isStartProvider),
      'Provider did not confirm connection',
    );
    await _until(() async {
      final result = await proxy!.inspectProxy(mixedPort);
      return result.success &&
          result.enabled == true &&
          result.server == '127.0.0.1:$mixedPort';
    }, 'Native system proxy did not match the listener');
    final client = HttpClient()
      ..findProxy = (_) => 'PROXY 127.0.0.1:$mixedPort';
    try {
      final response = await (await client.getUrl(
        endpoint('traffic'),
      )).close().timeout(const Duration(seconds: 8));
      final body = await utf8.decoder.bind(response).join();
      _require(
        response.statusCode == 200 && body == responseBody,
        'HTTP did not cross the real mixed listener',
      );
    } finally {
      client.close(force: true);
    }
  }

  Future<void> _assertSelection() async {
    final groups = await coreController.getProxiesGroups(
      sortType: ProxiesSortType.none,
      delayMap: {},
      selectedMap: {},
      defaultTestUrl: endpoint('probe').toString(),
    );
    _require(
      groups.getGroup(fixtureGroup)?.now == 'DIRECT',
      'Native fixture selection changed',
    );
    _require(
      state.read(patchClashConfigProvider).mode == Mode.rule,
      'Fixture mode changed',
    );
  }

  Future<void> _stop() async {
    await setup.setRunning(false, propagateErrors: true);
    await _assertStopped();
  }

  Future<void> _assertStopped() async {
    _require(
      !state.read(isStartProvider) && !state.read(connectionPendingProvider),
      'Connection state remained active',
    );
    await _until(() async {
      final result = await proxy!.inspectProxy(mixedPort);
      return result.enabled == false && !await _listening();
    }, 'Native proxy or listener remained active');
  }

  Future<bool> _listening() async {
    try {
      final socket = await Socket.connect(
        InternetAddress.loopbackIPv4,
        mixedPort,
        timeout: const Duration(milliseconds: 200),
      );
      socket.destroy();
      return true;
    } on SocketException {
      return false;
    }
  }

  Future<void> _until(Future<bool> Function() condition, String message) async {
    final watch = Stopwatch()..start();
    while (watch.elapsed < const Duration(seconds: 10)) {
      if (await condition()) return;
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    throw StateError(message);
  }

  Future<void> _releaseHeldResponses({bool releaseCancellation = false}) async {
    timeoutReleased = true;
    cancellationReleased = cancellationReleased || releaseCancellation;
    final responses = List<HttpResponse>.of(heldResponses);
    heldResponses.clear();
    for (final response in responses) {
      try {
        response.statusCode = HttpStatus.ok;
        response.write(responseBody);
        await response.close();
      } on IOException {
        continue;
      }
    }
  }

  Future<void> _cleanup() async {
    for (final coordinator in coordinators) {
      coordinator.dispose();
    }
    Future<void> clean(String name, Future<void> Function() action) async {
      try {
        await action().timeout(const Duration(seconds: 12));
        cleanup[name] = true;
      } catch (error) {
        cleanup[name] = false;
        errors.add('cleanup_$name: $error');
      }
    }

    await clean('probes_released', () async {
      await _releaseHeldResponses(releaseCancellation: true);
      await Future.wait(pendingProbes);
    });
    if (container != null && coreStarted) {
      await clean('stopped', _stop);
    }
    if (mounted) {
      runApp(const SizedBox.shrink());
      await WidgetsBinding.instance.endOfFrame;
    }
    await clean('core_closed', () async {
      if (coreStarted) await coreController.close();
    });
    if (mixedPort != 0) {
      await clean('proxy_disabled', () async {
        final result = await proxy!.stopProxyDetailed(expectedPort: mixedPort);
        _require(result.success, 'Owned proxy cleanup failed');
        _require(
          (await proxy!.inspectProxy(mixedPort)).enabled == false,
          'Native proxy is still enabled',
        );
      });
      await clean('listeners_closed', () async {
        _require(!await _listening(), 'Native TCP listener survived cleanup');
        final udp = await RawDatagramSocket.bind(
          InternetAddress.loopbackIPv4,
          mixedPort,
        );
        udp.close();
      });
    }
    await clean('fixture_closed', () async {
      await requests?.cancel();
      await server?.close(force: true);
    });
    await clean('data_closed', () async {
      configSubscription?.close();
      container?.dispose();
      await database.close();
      await commonPrint.flushDiagnosticEvents();
      PathProviderPlatform.instance = originalPathProvider;
    });
  }
}

class _FixturePaths extends PathProviderPlatform {
  _FixturePaths(this.root);

  final String root;

  @override
  Future<String?> getApplicationSupportPath() async => root;

  @override
  Future<String?> getApplicationCachePath() async => root;

  @override
  Future<String?> getTemporaryPath() async => root;

  @override
  Future<String?> getDownloadsPath() async => root;
}

void _require(bool condition, String message) {
  if (!condition) throw StateError(message);
}

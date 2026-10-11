import 'dart:async';
import 'dart:io';

import 'proxy_command.dart';
import 'proxy_result.dart';

typedef MacosProxyListenerProbe =
    Future<bool> Function(InternetAddress address, int port);

class MacosProxy {
  final ProxyCommandRunner _commandRunner;
  final MacosProxyListenerProbe _listenerProbe;
  final Map<String, MacosNetworkServiceProxyState> _originalStates = {};
  final Set<String> _managedServices = {};
  final Map<String, _MacosProxyWriteState> _appliedStates = {};
  final int verificationAttempts;
  final Duration verificationRetryInterval;
  final Duration listenerInspectionTimeout;

  MacosProxy({
    required ProxyCommandRunner commandRunner,
    this.verificationAttempts = 3,
    this.verificationRetryInterval = const Duration(milliseconds: 250),
    this.listenerInspectionTimeout = const Duration(seconds: 2),
    MacosProxyListenerProbe? listenerProbe,
  }) : assert(verificationAttempts > 0),
       assert(!verificationRetryInterval.isNegative),
       _commandRunner = commandRunner,
       _listenerProbe = listenerProbe ?? _probeListener;

  Future<bool> start(int port, List<String> bypassDomain) async {
    return (await startDetailed(port, bypassDomain)).success;
  }

  Future<ProxyOperationResult> startDetailed(
    int port,
    List<String> bypassDomain,
  ) async {
    final diagnostics = _MacosCommandDiagnostics();
    final result = await _startDetailed(port, bypassDomain, diagnostics);
    return result
        .withCommandFailure(diagnostics.firstFailure)
        .withPlatform('macos');
  }

  Future<ProxyOperationResult> _startDetailed(
    int port,
    List<String> bypassDomain,
    _MacosCommandDiagnostics diagnostics,
  ) async {
    final targets = await _networkServicesInPriorityOrder(diagnostics);
    if (targets.primaryService == null) {
      return const ProxyOperationResult(
        success: false,
        operation: 'start',
        stage: 'service_discovery',
      );
    }
    final applied = <String>[];
    final attemptedWrites = <String, _MacosProxyWriteState>{};
    final previousWrites = <String, _MacosProxyWriteState?>{};
    var writeSkipped = true;
    for (final service in targets.services) {
      final current = await _readNetworkServiceState(service, diagnostics);
      if (current == null) {
        return const ProxyOperationResult(
          success: false,
          operation: 'start',
          stage: 'readback',
          message: 'Cannot read original network service proxy settings',
        );
      }
      if (current.matchesTarget(port, bypassDomain)) {
        applied.add(service);
        continue;
      }
      if (!_managedServices.contains(service) ||
          _appliedStates[service]?.matches(current) != true) {
        _originalStates[service] = current;
      }
      writeSkipped = false;
      final commands = MacosProxyCommands.buildStart(
        service,
        port,
        bypassDomain,
      );
      final previousApplied = _appliedStates[service];
      previousWrites[service] = previousApplied;
      final result = await _commandRunner.runDetailed(commands);
      diagnostics.record(result);
      final pending = _MacosProxyWriteState.afterCommands(
        current,
        commands,
        result,
      );
      attemptedWrites[service] = pending;
      _appliedStates[service] = pending;
      _managedServices.add(service);
      if (result.success) {
        applied.add(service);
      } else {
        final readback = await _readNetworkServiceState(service, diagnostics);
        if (readback != null && readback.matchesExactly(current)) {
          if (previousApplied?.matches(current) == true) {
            _appliedStates[service] = previousApplied!;
          } else {
            _originalStates.remove(service);
            _managedServices.remove(service);
            _appliedStates.remove(service);
          }
        } else if (readback != null) {
          _appliedStates[service]!.confirm(readback);
        }
      }
    }
    if (applied.isEmpty) {
      return const ProxyOperationResult(
        success: false,
        operation: 'start',
        stage: 'apply_default',
      );
    }
    final inspection = await _inspectDetailed(
      port,
      diagnostics,
      bypassDomain: bypassDomain,
    );
    if (!inspection.success) {
      for (final entry in attemptedWrites.entries) {
        if (!identical(_appliedStates[entry.key], entry.value)) continue;
        final current = await _readNetworkServiceState(entry.key, diagnostics);
        if (current?.matchesExactly(entry.value.before) != true) continue;
        final previous = previousWrites[entry.key];
        if (previous?.matches(current!) == true) {
          _appliedStates[entry.key] = previous!;
        } else {
          _originalStates.remove(entry.key);
          _managedServices.remove(entry.key);
          _appliedStates.remove(entry.key);
        }
      }
      return ProxyOperationResult(
        success: false,
        operation: 'start',
        stage: inspection.stage,
        enabled: inspection.enabled,
        server: inspection.server,
        connectionName: inspection.connectionName ?? targets.primaryService,
        message: inspection.message,
        writeSkipped: writeSkipped,
      );
    }
    return ProxyOperationResult(
      success: true,
      operation: 'start',
      stage: 'verified',
      enabled: true,
      server: '$proxyHost:$port',
      connectionName: inspection.connectionName,
      message: inspection.message,
      writeSkipped: writeSkipped,
    );
  }

  Future<bool> stop({int? expectedPort}) async {
    return (await stopDetailed(expectedPort: expectedPort)).success;
  }

  Future<ProxyOperationResult> stopDetailed({int? expectedPort}) async {
    final diagnostics = _MacosCommandDiagnostics();
    final result = await _stopDetailed(expectedPort, diagnostics);
    return result
        .withCommandFailure(diagnostics.firstFailure)
        .withPlatform('macos');
  }

  Future<ProxyOperationResult> _stopDetailed(
    int? expectedPort,
    _MacosCommandDiagnostics diagnostics,
  ) async {
    var succeeded = true;
    var writeSkipped = true;
    var restoreAbandoned = false;
    final restoredServices = <String>{};
    for (final entry in _originalStates.entries) {
      final current = await _readNetworkServiceState(entry.key, diagnostics);
      if (current == null) {
        succeeded = false;
        continue;
      }
      if (current.restores(entry.value)) {
        restoredServices.add(entry.key);
        continue;
      }
      final owned = _appliedStates[entry.key];
      if (owned == null || !owned.matches(current)) {
        restoredServices.add(entry.key);
        restoreAbandoned = true;
        continue;
      }
      writeSkipped = false;
      final commands = MacosProxyCommands.buildRestore(entry.key, entry.value);
      final applied = await _commandRunner.runDetailed(commands);
      diagnostics.record(applied);
      final pending = _MacosProxyWriteState.afterCommands(
        current,
        commands,
        applied,
      );
      _appliedStates[entry.key] = pending;
      final readback = await _readNetworkServiceState(entry.key, diagnostics);
      if (!applied.success && readback?.matchesExactly(current) == true) {
        _appliedStates[entry.key] = owned;
      } else if (readback != null) {
        pending.confirm(readback);
      }
      final restored = readback != null && readback.restores(entry.value);
      succeeded = restored && succeeded;
      if (restored) restoredServices.add(entry.key);
    }
    for (final service in restoredServices) {
      _originalStates.remove(service);
      _managedServices.remove(service);
      _appliedStates.remove(service);
    }
    final cleanupCandidates = _managedServices
        .where((service) => !_originalStates.containsKey(service))
        .toList();
    for (final service in cleanupCandidates) {
      final state = await _readNetworkServiceState(service, diagnostics);
      if (state == null) {
        succeeded = false;
        continue;
      }
      final owned = _appliedStates[service];
      if (owned == null || !owned.matches(state)) {
        _managedServices.remove(service);
        _appliedStates.remove(service);
        restoreAbandoned = true;
        continue;
      }
      if (!state.isOwnedBy(null)) {
        _managedServices.remove(service);
        _appliedStates.remove(service);
        continue;
      }
      final commands = MacosProxyCommands.buildStop(service, state, null);
      final applied = await _commandRunner.runDetailed(commands);
      diagnostics.record(applied);
      final pending = _MacosProxyWriteState.afterCommands(
        state,
        commands,
        applied,
      );
      _appliedStates[service] = pending;
      final readback = await _readNetworkServiceState(service, diagnostics);
      if (!applied.success && readback?.matchesExactly(state) == true) {
        _appliedStates[service] = owned;
      } else if (readback != null) {
        pending.confirm(readback);
      }
      final stopped = readback != null && !readback.isOwnedBy(null);
      succeeded = stopped && succeeded;
      writeSkipped = false;
      if (stopped) {
        _managedServices.remove(service);
        _appliedStates.remove(service);
      }
    }
    if (!succeeded) {
      return ProxyOperationResult(
        success: false,
        operation: 'stop',
        stage: 'restore',
        writeSkipped: writeSkipped,
        restoreAbandoned: restoreAbandoned,
      );
    }
    return ProxyOperationResult(
      success: true,
      operation: 'stop',
      stage: 'verified',
      enabled: false,
      writeSkipped: writeSkipped,
      restoreAbandoned: restoreAbandoned,
      message: restoreAbandoned
          ? 'Proxy settings changed outside this session; restore was skipped'
          : null,
    );
  }

  Future<ProxyOperationResult> repairStaleDetailed(int expectedPort) async {
    if (expectedPort < 1 || expectedPort > 65535) {
      return const ProxyOperationResult(
        success: false,
        operation: 'stop',
        stage: 'invalid_arguments',
        platform: 'macos',
      );
    }
    final diagnostics = _MacosCommandDiagnostics();
    final blocked = await _checkStaleListener(expectedPort);
    if (blocked != null) return blocked;
    final services = await _networkServices(diagnostics);
    if (services == null) {
      return const ProxyOperationResult(
        success: false,
        operation: 'stop',
        stage: 'service_discovery',
        platform: 'macos',
      ).withCommandFailure(diagnostics.firstFailure);
    }
    var wrote = false;
    for (final service in services) {
      final state = await _readNetworkServiceState(service, diagnostics);
      if (state == null) {
        return const ProxyOperationResult(
          success: false,
          operation: 'stop',
          stage: 'readback',
          platform: 'macos',
        ).withCommandFailure(diagnostics.firstFailure);
      }
      if (!state.isOwnedBy(expectedPort)) continue;
      final checked = await _checkStaleListener(expectedPort);
      if (checked != null) return checked;
      final current = await _readNetworkServiceState(service, diagnostics);
      if (current == null) {
        return const ProxyOperationResult(
          success: false,
          operation: 'stop',
          stage: 'readback',
          platform: 'macos',
        ).withCommandFailure(diagnostics.firstFailure);
      }
      if (!current.matchesExactly(state)) continue;
      final result = await _commandRunner.runDetailed(
        MacosProxyCommands.buildStop(service, current, expectedPort),
      );
      diagnostics.record(result);
      wrote = true;
      final readback = await _readNetworkServiceState(service, diagnostics);
      if (readback == null || readback.isOwnedBy(expectedPort)) {
        return const ProxyOperationResult(
          success: false,
          operation: 'stop',
          stage: 'restore',
          platform: 'macos',
        ).withCommandFailure(diagnostics.firstFailure);
      }
    }
    return ProxyOperationResult(
      success: true,
      operation: 'stop',
      stage: wrote ? 'restored' : 'skipped_foreign_or_restored',
      writeSkipped: !wrote,
      platform: 'macos',
    );
  }

  Future<ProxyOperationResult?> _checkStaleListener(int port) async {
    try {
      final result = await _commandRunner
          .process('/usr/sbin/lsof', [
            '-nP',
            '-a',
            '-iTCP:$port',
            '-sTCP:LISTEN',
            '-Fp',
          ])
          .timeout(listenerInspectionTimeout);
      final output = result.stdout.toString().trim();
      if (result.exitCode == 0 &&
          RegExp(r'^p[1-9][0-9]*$', multiLine: true).hasMatch(output)) {
        return const ProxyOperationResult(
          success: true,
          operation: 'stop',
          stage: 'skipped_active_listener',
          writeSkipped: true,
          platform: 'macos',
        );
      }
      if (result.exitCode == 1 &&
          output.isEmpty &&
          result.stderr.toString().trim().isEmpty) {
        for (final address in [
          InternetAddress.loopbackIPv4,
          InternetAddress.loopbackIPv6,
        ]) {
          if (await _listenerProbe(
            address,
            port,
          ).timeout(listenerInspectionTimeout)) {
            return const ProxyOperationResult(
              success: true,
              operation: 'stop',
              stage: 'skipped_active_listener',
              writeSkipped: true,
              platform: 'macos',
            );
          }
        }
        return null;
      }
      return const ProxyOperationResult(
        success: false,
        operation: 'stop',
        stage: 'listener_inspection',
        platform: 'macos',
      ).withCommandFailure(
        ProxyCommandResult(
          success: false,
          command: ProxyCommand('/usr/sbin/lsof', ['-iTCP:$port']),
          processResult: result,
        ),
      );
    } on ProcessException catch (error) {
      return const ProxyOperationResult(
        success: false,
        operation: 'stop',
        stage: 'listener_inspection',
        platform: 'macos',
      ).withCommandFailure(
        ProxyCommandResult(
          success: false,
          command: ProxyCommand('/usr/sbin/lsof', ['-iTCP:$port']),
          exception: error,
        ),
      );
    } on TimeoutException {
      return const ProxyOperationResult(
        success: false,
        operation: 'stop',
        stage: 'listener_inspection',
        platform: 'macos',
      );
    } on SocketException catch (error) {
      return ProxyOperationResult(
        success: false,
        operation: 'stop',
        stage: 'listener_inspection',
        errorCode: error.osError?.errorCode,
        platform: 'macos',
      );
    }
  }

  static Future<bool> _probeListener(InternetAddress address, int port) async {
    Socket? socket;
    try {
      socket = await Socket.connect(
        address,
        port,
        timeout: const Duration(milliseconds: 350),
      );
      return true;
    } on SocketException catch (error) {
      if (error.osError?.errorCode == 61) return false;
      rethrow;
    } finally {
      socket?.destroy();
    }
  }

  Future<ProxyOperationResult> inspectDetailed(int expectedPort) async {
    final diagnostics = _MacosCommandDiagnostics();
    final result = await _inspectDetailed(expectedPort, diagnostics);
    return result
        .withCommandFailure(diagnostics.firstFailure)
        .withPlatform('macos');
  }

  Future<ProxyOperationResult> _inspectDetailed(
    int expectedPort,
    _MacosCommandDiagnostics diagnostics, {
    List<String>? bypassDomain,
  }) async {
    var result = await _inspectDetailedOnce(
      expectedPort,
      diagnostics,
      bypassDomain: bypassDomain,
    );
    for (
      var attempt = 1;
      attempt < verificationAttempts && !result.success;
      attempt++
    ) {
      if (!const {
        'service_discovery',
        'readback',
        'readback_mismatch',
      }.contains(result.stage)) {
        break;
      }
      await Future<void>.delayed(verificationRetryInterval);
      result = await _inspectDetailedOnce(
        expectedPort,
        diagnostics,
        bypassDomain: bypassDomain,
      );
    }
    return result;
  }

  Future<ProxyOperationResult> _inspectDetailedOnce(
    int expectedPort,
    _MacosCommandDiagnostics diagnostics, {
    List<String>? bypassDomain,
  }) async {
    final targets = await _networkServicesInPriorityOrder(diagnostics);
    final service = targets.primaryService;
    if (service == null) {
      return const ProxyOperationResult(
        success: false,
        operation: 'inspect',
        stage: 'service_discovery',
      );
    }
    final state = await _readNetworkServiceState(service, diagnostics);
    if (state == null) {
      return ProxyOperationResult(
        success: false,
        operation: 'inspect',
        stage: 'readback',
        connectionName: service,
        message: 'Cannot read network service proxy settings',
      );
    }
    final currentTargets = await _networkServicesInPriorityOrder(diagnostics);
    if (currentTargets.primaryService != service ||
        currentTargets.primaryServiceId != targets.primaryServiceId) {
      return const ProxyOperationResult(
        success: false,
        operation: 'inspect',
        stage: 'service_discovery',
        message: 'Active network service changed during proxy verification',
      );
    }
    final endpoints = [state.web, state.secureWeb, state.socks];
    final enabledEndpoints = endpoints.where((endpoint) => endpoint.enabled);
    final endpoint =
        enabledEndpoints
            .where((endpoint) => endpoint.isOwnedBy(expectedPort))
            .firstOrNull ??
        enabledEndpoints.firstOrNull;
    final matches =
        endpoints.every((endpoint) => endpoint.isOwnedBy(expectedPort)) &&
        !state.autoProxy.enabled &&
        !state.autoDiscovery &&
        (bypassDomain == null ||
            state.matchesTarget(expectedPort, bypassDomain));
    if (matches) _appliedStates[service]?.confirm(state);
    return ProxyOperationResult(
      success: matches,
      operation: 'inspect',
      stage: matches ? 'verified' : 'readback_mismatch',
      enabled: enabledEndpoints.isNotEmpty,
      server: endpoint == null ? null : '${endpoint.server}:${endpoint.port}',
      connectionName: service,
      message: matches ? 'Network service proxy settings verified' : null,
    );
  }

  Future<MacosNetworkServiceProxyState?> _readNetworkServiceState(
    String service,
    _MacosCommandDiagnostics diagnostics,
  ) async {
    try {
      final web = await _readEndpoint('-getwebproxy', service, diagnostics);
      final secureWeb = await _readEndpoint(
        '-getsecurewebproxy',
        service,
        diagnostics,
      );
      final socks = await _readEndpoint(
        '-getsocksfirewallproxy',
        service,
        diagnostics,
      );
      final autoProxyResult = await _networksetup([
        '-getautoproxyurl',
        service,
      ], diagnostics);
      final discoveryResult = await _networksetup([
        '-getproxyautodiscovery',
        service,
      ], diagnostics);
      final bypassResult = await _networksetup([
        '-getproxybypassdomains',
        service,
      ], diagnostics);
      if (web == null ||
          secureWeb == null ||
          socks == null ||
          autoProxyResult == null ||
          discoveryResult == null ||
          bypassResult == null) {
        return null;
      }
      return MacosNetworkServiceProxyState(
        web: web,
        secureWeb: secureWeb,
        socks: socks,
        autoProxy: MacosAutoProxyState.parse(autoProxyResult.stdout.toString()),
        autoDiscovery: MacosProxyCommands.parseEnabled(
          MacosProxyCommands.parseKeyValueOutput(
            discoveryResult.stdout.toString(),
          )['Auto Proxy Discovery'],
        ),
        bypassDomains: MacosProxyCommands.parseBypassDomains(
          bypassResult.stdout.toString(),
        ),
      );
    } on ProcessException {
      return null;
    } on FormatException {
      return null;
    }
  }

  Future<MacosProxyEndpoint?> _readEndpoint(
    String command,
    String service,
    _MacosCommandDiagnostics diagnostics,
  ) async {
    final result = await _networksetup([command, service], diagnostics);
    if (result == null) return null;
    return MacosProxyEndpoint.parse(result.stdout.toString());
  }

  Future<_MacosNetworkTargets> _networkServicesInPriorityOrder(
    _MacosCommandDiagnostics diagnostics,
  ) async {
    final services = await _networkServices(diagnostics);
    if (services == null || services.isEmpty) {
      return const _MacosNetworkTargets(services: [], primaryService: null);
    }
    final primary = await _primaryNetworkService();
    if (primary != null) {
      final service = primary.$2;
      return _MacosNetworkTargets(
        services: service != null && services.contains(service)
            ? [service]
            : [],
        primaryService: service != null && services.contains(service)
            ? service
            : null,
        primaryServiceId: primary.$1,
      );
    }
    final defaultDevice = await _defaultDevice();
    final serviceOrder = await _networkServiceOrder(diagnostics);
    final primaryService = defaultDevice == null
        ? null
        : serviceOrder[defaultDevice];
    if (primaryService == null || !services.contains(primaryService)) {
      return _MacosNetworkTargets(services: services, primaryService: null);
    }
    return _MacosNetworkTargets(
      services: [primaryService],
      primaryService: primaryService,
    );
  }

  Future<(String, String?)?> _primaryNetworkService() async {
    String? discoveredServiceId;
    try {
      final primaryResult = await _commandRunner.process('/bin/sh', [
        '-c',
        "printf 'show State:/Network/Global/IPv4\\nshow State:/Network/Global/IPv6\\nquit\\n' | /usr/sbin/scutil",
      ]);
      if (primaryResult.exitCode != 0) return null;
      final serviceId = RegExp(
        r'^\s*PrimaryService\s*:\s*([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12})\s*$',
        multiLine: true,
      ).firstMatch(primaryResult.stdout.toString())?.group(1);
      if (serviceId == null) return null;
      discoveredServiceId = serviceId;
      final serviceResult = await _commandRunner.process('/bin/sh', [
        '-c',
        "printf 'show Setup:/Network/Service/$serviceId\\nquit\\n' | /usr/sbin/scutil",
      ]);
      if (serviceResult.exitCode != 0) return (serviceId, null);
      return (
        serviceId,
        MacosProxyCommands.parseKeyValueOutput(
          serviceResult.stdout.toString(),
        )['UserDefinedName'],
      );
    } on ProcessException {
      return discoveredServiceId == null ? null : (discoveredServiceId, null);
    }
  }

  Future<String?> _defaultDevice() async {
    try {
      final result = await _commandRunner.process('/sbin/route', [
        '-n',
        'get',
        'default',
      ]);
      if (result.exitCode != 0) return null;
      return MacosProxyCommands.parseDefaultDevice(result.stdout.toString());
    } on ProcessException {
      return null;
    }
  }

  Future<Map<String, String>> _networkServiceOrder(
    _MacosCommandDiagnostics diagnostics,
  ) async {
    try {
      final result = await _networksetup([
        '-listnetworkserviceorder',
      ], diagnostics);
      if (result == null) return const {};
      return MacosProxyCommands.parseNetworkServiceOrder(
        result.stdout.toString(),
      );
    } on ProcessException {
      return const {};
    }
  }

  Future<List<String>?> _networkServices(
    _MacosCommandDiagnostics diagnostics,
  ) async {
    try {
      final result = await _networksetup([
        '-listallnetworkservices',
      ], diagnostics);
      if (result == null || result.stdout.toString().trim().isEmpty) {
        return null;
      }
      return MacosProxyCommands.parseNetworkServices(result.stdout.toString());
    } on ProcessException {
      return null;
    }
  }

  Future<ProcessResult?> _networksetup(
    List<String> arguments,
    _MacosCommandDiagnostics diagnostics,
  ) async {
    final result = await _commandRunner.runDetailed([
      ProxyCommand('/usr/sbin/networksetup', arguments),
    ]);
    diagnostics.record(result);
    return result.success ? result.processResult : null;
  }
}

class _MacosCommandDiagnostics {
  ProxyCommandResult? firstFailure;

  void record(ProxyCommandResult result) {
    if (!result.success) firstFailure ??= result;
  }
}

class _MacosProxyWriteState {
  _MacosProxyWriteState(this.before, this.commands);

  factory _MacosProxyWriteState.afterCommands(
    MacosNetworkServiceProxyState before,
    List<ProxyCommand> commands,
    ProxyCommandResult result,
  ) {
    final index = result.command == null
        ? -1
        : commands.indexOf(result.command!);
    return _MacosProxyWriteState(
      before,
      result.success ? commands : commands.take(index + 1).toList(),
    );
  }

  final MacosNetworkServiceProxyState before;
  final List<ProxyCommand> commands;
  MacosNetworkServiceProxyState? _confirmed;
  bool _rejected = false;

  void confirm(MacosNetworkServiceProxyState state) {
    if (_confirmed != null || _rejected) return;
    if (matches(state)) {
      _confirmed = state;
    } else {
      _rejected = true;
    }
  }

  bool matches(MacosNetworkServiceProxyState current) {
    if (_rejected) return false;
    final confirmed = _confirmed;
    if (confirmed != null) return current.matchesExactly(confirmed);
    bool endpointMatches(
      MacosProxyEndpoint actual,
      MacosProxyEndpoint original,
      String valueFlag,
      String stateFlag,
    ) {
      final values = <(String, int?)>{(original.server, original.port)};
      final enabled = <bool>{original.enabled};
      for (final command in commands) {
        final args = command.args;
        if (args.first == valueFlag) {
          values.add((args[2], int.parse(args[3])));
          enabled.add(true);
        } else if (args.first == stateFlag) {
          enabled.add(args[2] == 'on');
        }
      }
      return values.contains((actual.server, actual.port)) &&
          enabled.contains(actual.enabled);
    }

    final pacUrls = <String>{before.autoProxy.url};
    final pacEnabled = <bool>{before.autoProxy.enabled};
    final discovery = <bool>{before.autoDiscovery};
    final bypass = <List<String>>[before.bypassDomains];
    for (final command in commands) {
      final args = command.args;
      switch (args.first) {
        case '-setautoproxyurl':
          pacUrls.add(args[2]);
          pacEnabled.add(true);
        case '-setautoproxystate':
          pacEnabled.add(args[2] == 'on');
        case '-setproxyautodiscovery':
          discovery.add(args[2] == 'on');
        case '-setproxybypassdomains':
          bypass.add(args[2] == 'Empty' ? [] : args.sublist(2));
      }
    }
    return endpointMatches(
          current.web,
          before.web,
          '-setwebproxy',
          '-setwebproxystate',
        ) &&
        endpointMatches(
          current.secureWeb,
          before.secureWeb,
          '-setsecurewebproxy',
          '-setsecurewebproxystate',
        ) &&
        endpointMatches(
          current.socks,
          before.socks,
          '-setsocksfirewallproxy',
          '-setsocksfirewallproxystate',
        ) &&
        pacUrls.contains(current.autoProxy.url) &&
        pacEnabled.contains(current.autoProxy.enabled) &&
        discovery.contains(current.autoDiscovery) &&
        bypass.any((domains) => _sameDomains(current.bypassDomains, domains));
  }
}

bool _sameDomains(List<String> left, List<String> right) {
  final leftSet = left.toSet();
  final rightSet = right.toSet();
  return leftSet.length == rightSet.length && leftSet.containsAll(rightSet);
}

class _MacosNetworkTargets {
  const _MacosNetworkTargets({
    required this.services,
    required this.primaryService,
    this.primaryServiceId,
  });

  final List<String> services;
  final String? primaryService;
  final String? primaryServiceId;
}

class MacosProxyEndpoint {
  const MacosProxyEndpoint({
    required this.enabled,
    required this.server,
    required this.port,
  });

  final bool enabled;
  final String server;
  final int? port;

  factory MacosProxyEndpoint.parse(String output) {
    final values = MacosProxyCommands.parseKeyValueOutput(output);
    final enabled = MacosProxyCommands.parseEnabled(values['Enabled']);
    final server = values['Server'];
    final port = int.tryParse(values['Port'] ?? '');
    if (server == null ||
        port == null ||
        port < 0 ||
        port > 65535 ||
        (enabled && (server.isEmpty || port == 0))) {
      throw const FormatException('Incomplete network service proxy endpoint');
    }
    return MacosProxyEndpoint(enabled: enabled, server: server, port: port);
  }

  bool isOwnedBy(int? expectedPort) {
    return enabled &&
        server == proxyHost &&
        (expectedPort == null || port == expectedPort);
  }
}

class MacosAutoProxyState {
  const MacosAutoProxyState({required this.enabled, required this.url});

  final bool enabled;
  final String url;

  factory MacosAutoProxyState.parse(String output) {
    final values = MacosProxyCommands.parseKeyValueOutput(output);
    final enabled = MacosProxyCommands.parseEnabled(values['Enabled']);
    final url = values['URL'];
    if (url == null || (enabled && url.isEmpty)) {
      throw const FormatException('Incomplete automatic proxy settings');
    }
    return MacosAutoProxyState(enabled: enabled, url: url);
  }
}

class MacosNetworkServiceProxyState {
  const MacosNetworkServiceProxyState({
    required this.web,
    required this.secureWeb,
    required this.socks,
    required this.autoProxy,
    required this.bypassDomains,
    required this.autoDiscovery,
  });

  final MacosProxyEndpoint web;
  final MacosProxyEndpoint secureWeb;
  final MacosProxyEndpoint socks;
  final MacosAutoProxyState autoProxy;
  final List<String> bypassDomains;
  final bool autoDiscovery;

  bool matchesTarget(int port, List<String> bypass) {
    return [
          web,
          secureWeb,
          socks,
        ].every((endpoint) => endpoint.isOwnedBy(port)) &&
        !autoProxy.enabled &&
        !autoDiscovery &&
        _sameDomains(bypassDomains, bypass);
  }

  bool matchesExactly(MacosNetworkServiceProxyState other) {
    bool sameEndpoint(MacosProxyEndpoint left, MacosProxyEndpoint right) {
      return left.enabled == right.enabled &&
          left.server == right.server &&
          left.port == right.port;
    }

    return sameEndpoint(web, other.web) &&
        sameEndpoint(secureWeb, other.secureWeb) &&
        sameEndpoint(socks, other.socks) &&
        autoProxy.enabled == other.autoProxy.enabled &&
        autoProxy.url == other.autoProxy.url &&
        autoDiscovery == other.autoDiscovery &&
        _sameDomains(bypassDomains, other.bypassDomains);
  }

  bool restores(MacosNetworkServiceProxyState original) {
    bool endpointMatches(
      MacosProxyEndpoint actual,
      MacosProxyEndpoint expected,
    ) {
      return actual.enabled == expected.enabled &&
          (expected.server.isEmpty ||
              expected.port == null ||
              (actual.server == expected.server &&
                  actual.port == expected.port));
    }

    return endpointMatches(web, original.web) &&
        endpointMatches(secureWeb, original.secureWeb) &&
        endpointMatches(socks, original.socks) &&
        autoProxy.enabled == original.autoProxy.enabled &&
        (original.autoProxy.url.isEmpty ||
            autoProxy.url == original.autoProxy.url) &&
        autoDiscovery == original.autoDiscovery &&
        bypassDomains.length == original.bypassDomains.length &&
        bypassDomains.toSet().containsAll(original.bypassDomains);
  }

  bool isOwnedBy(int? expectedPort) {
    return web.isOwnedBy(expectedPort) ||
        secureWeb.isOwnedBy(expectedPort) ||
        socks.isOwnedBy(expectedPort);
  }
}

class MacosProxyCommands {
  static List<ProxyCommand> buildStart(
    String service,
    int port,
    List<String> bypassDomain,
  ) {
    return [
      ProxyCommand('/usr/sbin/networksetup', [
        '-setautoproxystate',
        service,
        'off',
      ]),
      ProxyCommand('/usr/sbin/networksetup', [
        '-setproxyautodiscovery',
        service,
        'off',
      ]),
      ProxyCommand('/usr/sbin/networksetup', [
        '-setwebproxy',
        service,
        proxyHost,
        '$port',
      ]),
      ProxyCommand('/usr/sbin/networksetup', [
        '-setsecurewebproxy',
        service,
        proxyHost,
        '$port',
      ]),
      ProxyCommand('/usr/sbin/networksetup', [
        '-setsocksfirewallproxy',
        service,
        proxyHost,
        '$port',
      ]),
      buildProxyBypass(service, bypassDomain),
      ProxyCommand('/usr/sbin/networksetup', [
        '-setwebproxystate',
        service,
        'on',
      ]),
      ProxyCommand('/usr/sbin/networksetup', [
        '-setsecurewebproxystate',
        service,
        'on',
      ]),
      ProxyCommand('/usr/sbin/networksetup', [
        '-setsocksfirewallproxystate',
        service,
        'on',
      ]),
    ];
  }

  static List<ProxyCommand> buildStop(
    String service,
    MacosNetworkServiceProxyState state,
    int? expectedPort,
  ) {
    return [
      if (state.web.isOwnedBy(expectedPort))
        ProxyCommand('/usr/sbin/networksetup', [
          '-setwebproxystate',
          service,
          'off',
        ]),
      if (state.secureWeb.isOwnedBy(expectedPort))
        ProxyCommand('/usr/sbin/networksetup', [
          '-setsecurewebproxystate',
          service,
          'off',
        ]),
      if (state.socks.isOwnedBy(expectedPort))
        ProxyCommand('/usr/sbin/networksetup', [
          '-setsocksfirewallproxystate',
          service,
          'off',
        ]),
    ];
  }

  static List<ProxyCommand> buildRestore(
    String service,
    MacosNetworkServiceProxyState state,
  ) {
    return [
      ..._buildEndpointValue('-setwebproxy', service, state.web),
      ..._buildEndpointValue('-setsecurewebproxy', service, state.secureWeb),
      ..._buildEndpointValue('-setsocksfirewallproxy', service, state.socks),
      if (state.autoProxy.url.isNotEmpty)
        ProxyCommand('/usr/sbin/networksetup', [
          '-setautoproxyurl',
          service,
          state.autoProxy.url,
        ]),
      buildProxyBypass(service, state.bypassDomains),
      ProxyCommand('/usr/sbin/networksetup', [
        '-setwebproxystate',
        service,
        state.web.enabled ? 'on' : 'off',
      ]),
      ProxyCommand('/usr/sbin/networksetup', [
        '-setsecurewebproxystate',
        service,
        state.secureWeb.enabled ? 'on' : 'off',
      ]),
      ProxyCommand('/usr/sbin/networksetup', [
        '-setsocksfirewallproxystate',
        service,
        state.socks.enabled ? 'on' : 'off',
      ]),
      ProxyCommand('/usr/sbin/networksetup', [
        '-setautoproxystate',
        service,
        state.autoProxy.enabled ? 'on' : 'off',
      ]),
      ProxyCommand('/usr/sbin/networksetup', [
        '-setproxyautodiscovery',
        service,
        state.autoDiscovery ? 'on' : 'off',
      ]),
    ];
  }

  static List<ProxyCommand> _buildEndpointValue(
    String command,
    String service,
    MacosProxyEndpoint endpoint,
  ) {
    if (endpoint.server.isEmpty || endpoint.port == null) return const [];
    return [
      ProxyCommand('/usr/sbin/networksetup', [
        command,
        service,
        endpoint.server,
        '${endpoint.port}',
      ]),
    ];
  }

  static ProxyCommand buildProxyBypass(
    String service,
    List<String> bypassDomain,
  ) {
    return ProxyCommand('/usr/sbin/networksetup', [
      '-setproxybypassdomains',
      service,
      if (bypassDomain.isEmpty) 'Empty' else ...bypassDomain,
    ]);
  }

  static List<String> parseNetworkServices(String stdout) {
    return stdout
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .where((line) => !line.startsWith('*'))
        .where((line) => !line.startsWith('An asterisk '))
        .toList();
  }

  static String? parseDefaultDevice(String stdout) {
    final match = RegExp(
      r'^\s*interface:\s*(\S+)\s*$',
      multiLine: true,
    ).firstMatch(stdout);
    return match?.group(1);
  }

  static Map<String, String> parseNetworkServiceOrder(String stdout) {
    final services = <String, String>{};
    final ambiguousDevices = <String>{};
    String? pendingService;
    for (final rawLine in stdout.split('\n')) {
      final line = rawLine.trim();
      if (line.startsWith('(*)')) {
        pendingService = null;
        continue;
      }
      final serviceMatch = RegExp(r'^\(\d+\)\s+(.+)$').firstMatch(line);
      if (serviceMatch != null) {
        pendingService = serviceMatch.group(1)?.trim();
        continue;
      }
      final deviceMatch = RegExp(r'Device:\s*([^,)]+)').firstMatch(line);
      final device = deviceMatch?.group(1)?.trim();
      if (pendingService != null && device?.isNotEmpty == true) {
        if (services.containsKey(device)) {
          services.remove(device);
          ambiguousDevices.add(device!);
        } else if (!ambiguousDevices.contains(device)) {
          services[device!] = pendingService;
        }
        pendingService = null;
      }
    }
    return services;
  }

  static List<String> parseBypassDomains(String stdout) {
    final lines = stdout
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList();
    if (lines.length == 1 &&
        lines.first.startsWith('There aren\'t any bypass domains set on')) {
      return const [];
    }
    return lines;
  }

  static Map<String, String> parseKeyValueOutput(String stdout) {
    final values = <String, String>{};
    for (final rawLine in stdout.split('\n')) {
      final separator = rawLine.indexOf(':');
      if (separator < 0) continue;
      final key = rawLine.substring(0, separator).trim();
      final value = rawLine.substring(separator + 1).trim();
      if (key.isNotEmpty) values[key] = value;
    }
    return values;
  }

  static bool parseEnabled(String? value) {
    return switch (value?.toLowerCase()) {
      'yes' || '1' || 'on' => true,
      'no' || '0' || 'off' => false,
      _ => throw const FormatException('Missing or invalid proxy enable state'),
    };
  }
}

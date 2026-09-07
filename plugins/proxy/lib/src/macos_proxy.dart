import 'dart:io';

import 'proxy_command.dart';
import 'proxy_result.dart';

class MacosProxy {
  final ProxyCommandRunner _commandRunner;
  final Map<String, MacosNetworkServiceProxyState> _originalStates = {};
  final Set<String> _managedServices = {};

  MacosProxy({required ProxyCommandRunner commandRunner})
    : _commandRunner = commandRunner;

  Future<bool> start(int port, List<String> bypassDomain) async {
    return (await startDetailed(port, bypassDomain)).success;
  }

  Future<ProxyOperationResult> startDetailed(
    int port,
    List<String> bypassDomain,
  ) async {
    final targets = await _networkServicesInPriorityOrder();
    if (targets.services.isEmpty) {
      return const ProxyOperationResult(
        success: false,
        operation: 'start',
        stage: 'service_discovery',
      );
    }
    await _captureOriginalStates(targets.services);
    final applied = <String>[];
    for (final service in targets.services) {
      if (await _commandRunner.run(
        MacosProxyCommands.buildStart(service, port, bypassDomain),
      )) {
        applied.add(service);
        _managedServices.add(service);
      }
    }
    if (applied.isEmpty) {
      return const ProxyOperationResult(
        success: false,
        operation: 'start',
        stage: 'apply_default',
      );
    }
    final inspection = await inspectDetailed(port);
    if (!inspection.success) {
      if (targets.primaryService == null &&
          inspection.stage == 'readback_mismatch') {
        return ProxyOperationResult(
          success: true,
          operation: 'start',
          stage: 'fallback_pending',
          enabled: inspection.enabled,
          server: inspection.server,
          connectionName: applied.first,
          fallbackUsed: true,
        );
      }
      return ProxyOperationResult(
        success: false,
        operation: 'start',
        stage: inspection.stage,
        enabled: inspection.enabled,
        server: inspection.server,
        connectionName: targets.primaryService,
        fallbackUsed:
            targets.primaryService == null ||
            !applied.contains(targets.primaryService),
        message: inspection.message,
      );
    }
    return ProxyOperationResult(
      success: true,
      operation: 'start',
      stage: 'verified',
      enabled: true,
      server: '$proxyHost:$port',
      connectionName: targets.primaryService ?? applied.first,
      fallbackUsed:
          targets.primaryService == null ||
          !applied.contains(targets.primaryService),
    );
  }

  Future<bool> stop({int? expectedPort}) async {
    return (await stopDetailed(expectedPort: expectedPort)).success;
  }

  Future<ProxyOperationResult> stopDetailed({int? expectedPort}) async {
    var succeeded = true;
    final hasSessionState =
        _originalStates.isNotEmpty || _managedServices.isNotEmpty;
    final restoredServices = <String>{};
    for (final entry in _originalStates.entries) {
      final commands = MacosProxyCommands.buildRestore(entry.key, entry.value);
      final restored = await _commandRunner.run(commands);
      succeeded = restored && succeeded;
      if (restored) restoredServices.add(entry.key);
    }
    for (final service in restoredServices) {
      _originalStates.remove(service);
      _managedServices.remove(service);
    }
    final cleanupCandidates = _managedServices
        .where((service) => !_originalStates.containsKey(service))
        .toList();
    for (final service in cleanupCandidates) {
      final state = await _readNetworkServiceState(service);
      if (state == null) {
        succeeded = false;
        continue;
      }
      if (!state.isOwnedBy(expectedPort)) {
        _managedServices.remove(service);
        continue;
      }
      final stopped = await _commandRunner.run(
        MacosProxyCommands.buildStop(service),
      );
      succeeded = stopped && succeeded;
      if (stopped) _managedServices.remove(service);
    }
    if (!hasSessionState) {
      final services = await _networkServices();
      for (final service in services) {
        final state = await _readNetworkServiceState(service);
        if (state == null || !state.isOwnedBy(expectedPort)) continue;
        final stopped = await _commandRunner.run(
          MacosProxyCommands.buildStop(service),
        );
        succeeded = stopped && succeeded;
      }
    }
    if (!succeeded) {
      return const ProxyOperationResult(
        success: false,
        operation: 'stop',
        stage: 'restore',
      );
    }
    if (expectedPort != null) {
      final inspection = await inspectDetailed(expectedPort);
      if (inspection.success) {
        return ProxyOperationResult(
          success: false,
          operation: 'stop',
          stage: 'readback_mismatch',
          enabled: inspection.enabled,
          server: inspection.server,
        );
      }
    }
    return const ProxyOperationResult(
      success: true,
      operation: 'stop',
      stage: 'verified',
      enabled: false,
    );
  }

  Future<ProxyOperationResult> inspectDetailed(int expectedPort) async {
    try {
      final result = await _commandRunner.process('/usr/sbin/scutil', [
        '--proxy',
      ]);
      if (result.exitCode != 0) {
        return ProxyOperationResult(
          success: false,
          operation: 'inspect',
          stage: 'readback',
          errorCode: result.exitCode,
        );
      }
      final state = MacosEffectiveProxyState.parse(result.stdout.toString());
      final matches = state.matches(expectedPort);
      return ProxyOperationResult(
        success: matches,
        operation: 'inspect',
        stage: matches ? 'verified' : 'readback_mismatch',
        enabled: state.anyEnabled,
        server: state.primaryServer,
        message: state.isComplete ? null : 'Incomplete proxy readback',
      );
    } on ProcessException catch (error) {
      return ProxyOperationResult(
        success: false,
        operation: 'inspect',
        stage: 'readback',
        errorCode: error.errorCode,
      );
    }
  }

  Future<void> _captureOriginalStates(List<String> services) async {
    for (final service in services) {
      if (_originalStates.containsKey(service)) continue;
      final state = await _readNetworkServiceState(service);
      if (state != null) _originalStates[service] = state;
    }
  }

  Future<MacosNetworkServiceProxyState?> _readNetworkServiceState(
    String service,
  ) async {
    try {
      final web = await _readEndpoint('-getwebproxy', service);
      final secureWeb = await _readEndpoint('-getsecurewebproxy', service);
      final socks = await _readEndpoint('-getsocksfirewallproxy', service);
      final autoProxyResult = await _commandRunner.process(
        '/usr/sbin/networksetup',
        ['-getautoproxyurl', service],
      );
      final bypassResult = await _commandRunner.process(
        '/usr/sbin/networksetup',
        ['-getproxybypassdomains', service],
      );
      if (web == null ||
          secureWeb == null ||
          socks == null ||
          autoProxyResult.exitCode != 0 ||
          bypassResult.exitCode != 0) {
        return null;
      }
      return MacosNetworkServiceProxyState(
        web: web,
        secureWeb: secureWeb,
        socks: socks,
        autoProxy: MacosAutoProxyState.parse(autoProxyResult.stdout.toString()),
        bypassDomains: MacosProxyCommands.parseBypassDomains(
          bypassResult.stdout.toString(),
        ),
      );
    } on ProcessException {
      return null;
    }
  }

  Future<MacosProxyEndpoint?> _readEndpoint(
    String command,
    String service,
  ) async {
    final result = await _commandRunner.process('/usr/sbin/networksetup', [
      command,
      service,
    ]);
    if (result.exitCode != 0) return null;
    return MacosProxyEndpoint.parse(result.stdout.toString());
  }

  Future<_MacosNetworkTargets> _networkServicesInPriorityOrder() async {
    final services = await _networkServices();
    if (services.isEmpty) {
      return const _MacosNetworkTargets(services: [], primaryService: null);
    }
    final defaultDevice = await _defaultDevice();
    final serviceOrder = await _networkServiceOrder();
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

  Future<Map<String, String>> _networkServiceOrder() async {
    try {
      final result = await _commandRunner.process('/usr/sbin/networksetup', [
        '-listnetworkserviceorder',
      ]);
      if (result.exitCode != 0) return const {};
      return MacosProxyCommands.parseNetworkServiceOrder(
        result.stdout.toString(),
      );
    } on ProcessException {
      return const {};
    }
  }

  Future<List<String>> _networkServices() async {
    try {
      final result = await _commandRunner.process('/usr/sbin/networksetup', [
        '-listallnetworkservices',
      ]);
      if (result.exitCode != 0) return [];
      return MacosProxyCommands.parseNetworkServices(result.stdout.toString());
    } on ProcessException {
      return [];
    }
  }
}

class _MacosNetworkTargets {
  const _MacosNetworkTargets({
    required this.services,
    required this.primaryService,
  });

  final List<String> services;
  final String? primaryService;
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
    return MacosProxyEndpoint(
      enabled: MacosProxyCommands.parseEnabled(values['Enabled']),
      server: values['Server'] ?? '',
      port: int.tryParse(values['Port'] ?? ''),
    );
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
    return MacosAutoProxyState(
      enabled: MacosProxyCommands.parseEnabled(values['Enabled']),
      url: values['URL'] ?? '',
    );
  }
}

class MacosNetworkServiceProxyState {
  const MacosNetworkServiceProxyState({
    required this.web,
    required this.secureWeb,
    required this.socks,
    required this.autoProxy,
    required this.bypassDomains,
  });

  final MacosProxyEndpoint web;
  final MacosProxyEndpoint secureWeb;
  final MacosProxyEndpoint socks;
  final MacosAutoProxyState autoProxy;
  final List<String> bypassDomains;

  bool isOwnedBy(int? expectedPort) {
    return web.isOwnedBy(expectedPort) ||
        secureWeb.isOwnedBy(expectedPort) ||
        socks.isOwnedBy(expectedPort);
  }
}

class MacosEffectiveProxyState {
  const MacosEffectiveProxyState({
    required this.httpEnabled,
    required this.httpHost,
    required this.httpPort,
    required this.httpsEnabled,
    required this.httpsHost,
    required this.httpsPort,
    required this.socksEnabled,
    required this.socksHost,
    required this.socksPort,
  });

  final bool httpEnabled;
  final String? httpHost;
  final int? httpPort;
  final bool httpsEnabled;
  final String? httpsHost;
  final int? httpsPort;
  final bool socksEnabled;
  final String? socksHost;
  final int? socksPort;

  factory MacosEffectiveProxyState.parse(String output) {
    final values = MacosProxyCommands.parseScutilProxyOutput(output);
    return MacosEffectiveProxyState(
      httpEnabled: values['HTTPEnable'] == '1',
      httpHost: values['HTTPProxy'],
      httpPort: int.tryParse(values['HTTPPort'] ?? ''),
      httpsEnabled: values['HTTPSEnable'] == '1',
      httpsHost: values['HTTPSProxy'],
      httpsPort: int.tryParse(values['HTTPSPort'] ?? ''),
      socksEnabled: values['SOCKSEnable'] == '1',
      socksHost: values['SOCKSProxy'],
      socksPort: int.tryParse(values['SOCKSPort'] ?? ''),
    );
  }

  bool get anyEnabled => httpEnabled || httpsEnabled || socksEnabled;

  bool get isComplete =>
      httpHost != null && httpsHost != null && socksHost != null;

  String? get primaryServer {
    if (httpHost != null && httpPort != null) return '$httpHost:$httpPort';
    if (httpsHost != null && httpsPort != null) {
      return '$httpsHost:$httpsPort';
    }
    if (socksHost != null && socksPort != null) {
      return '$socksHost:$socksPort';
    }
    return null;
  }

  bool matches(int expectedPort) {
    return httpEnabled &&
        httpHost == proxyHost &&
        httpPort == expectedPort &&
        httpsEnabled &&
        httpsHost == proxyHost &&
        httpsPort == expectedPort &&
        socksEnabled &&
        socksHost == proxyHost &&
        socksPort == expectedPort;
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

  static List<ProxyCommand> buildStop(String service) {
    return [
      ProxyCommand('/usr/sbin/networksetup', [
        '-setautoproxystate',
        service,
        'off',
      ]),
      ProxyCommand('/usr/sbin/networksetup', [
        '-setwebproxystate',
        service,
        'off',
      ]),
      ProxyCommand('/usr/sbin/networksetup', [
        '-setsecurewebproxystate',
        service,
        'off',
      ]),
      ProxyCommand('/usr/sbin/networksetup', [
        '-setsocksfirewallproxystate',
        service,
        'off',
      ]),
      buildProxyBypass(service, const []),
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
    String? pendingService;
    for (final rawLine in stdout.split('\n')) {
      final line = rawLine.trim();
      final serviceMatch = RegExp(r'^\(\d+\)\s+(.+)$').firstMatch(line);
      if (serviceMatch != null) {
        pendingService = serviceMatch.group(1)?.trim();
        continue;
      }
      final deviceMatch = RegExp(r'Device:\s*([^,)]+)').firstMatch(line);
      final device = deviceMatch?.group(1)?.trim();
      if (pendingService != null && device?.isNotEmpty == true) {
        services[device!] = pendingService;
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

  static Map<String, String> parseScutilProxyOutput(String stdout) {
    final values = <String, String>{};
    for (final rawLine in stdout.split('\n')) {
      final match = RegExp(
        r'^\s*([A-Za-z]+)\s*:\s*(.*?)\s*$',
      ).firstMatch(rawLine);
      final key = match?.group(1);
      final value = match?.group(2);
      if (key != null && value != null) values[key] = value;
    }
    return values;
  }

  static bool parseEnabled(String? value) {
    return value == 'Yes' || value == '1' || value == 'On';
  }
}

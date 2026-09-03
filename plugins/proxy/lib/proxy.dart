import 'dart:io';

import 'proxy_platform_interface.dart';
import 'src/linux_proxy.dart';
import 'src/macos_proxy.dart';
import 'src/proxy_command.dart';
import 'src/proxy_result.dart';

export 'src/proxy_command.dart' show ProxyExecutableChecker, ProxyProcessRunner;
export 'src/proxy_result.dart' show ProxyOperationResult;

class Proxy {
  static const int _minPort = 1;
  static const int _maxPort = 65535;

  late final LinuxProxy _linuxProxy;
  late final MacosProxy _macosProxy;

  Proxy({
    ProxyProcessRunner? processRunner,
    ProxyExecutableChecker? executableChecker,
  }) {
    final commandRunner = ProxyCommandRunner(processRunner ?? Process.run);
    _linuxProxy = LinuxProxy(
      commandRunner: commandRunner,
      executableChecker: executableChecker,
    );
    _macosProxy = MacosProxy(commandRunner: commandRunner);
  }

  Future<bool> startProxy(
    int port, [
    List<String> bypassDomain = const [],
  ]) async => (await startProxyDetailed(port, bypassDomain)).success;

  Future<ProxyOperationResult> startProxyDetailed(
    int port, [
    List<String> bypassDomain = const [],
  ]) async {
    if (port < _minPort || port > _maxPort) {
      return const ProxyOperationResult(
        success: false,
        operation: 'start',
        stage: 'invalid_arguments',
        message: 'Proxy port must be between 1 and 65535',
      );
    }
    return switch (Platform.operatingSystem) {
      'macos' => ProxyOperationResult.generic(
        success: await _macosProxy.start(port, bypassDomain),
        operation: 'start',
      ),
      'linux' => ProxyOperationResult.generic(
        success: await _linuxProxy.start(
          port,
          bypassDomain,
          desktop: Platform.environment['XDG_CURRENT_DESKTOP'],
          homeDir: Platform.environment['HOME'],
        ),
        operation: 'start',
      ),
      'windows' => await ProxyPlatform.instance.startProxyDetailed(
        port,
        bypassDomain,
      ),
      String() => const ProxyOperationResult(
        success: false,
        operation: 'start',
        stage: 'unsupported',
      ),
    };
  }

  Future<bool> stopProxy({int? expectedPort}) async =>
      (await stopProxyDetailed(expectedPort: expectedPort)).success;

  Future<ProxyOperationResult> stopProxyDetailed({int? expectedPort}) async {
    return switch (Platform.operatingSystem) {
      'macos' => ProxyOperationResult.generic(
        success: await _macosProxy.stop(),
        operation: 'stop',
      ),
      'linux' => ProxyOperationResult.generic(
        success: await _linuxProxy.stop(
          desktop: Platform.environment['XDG_CURRENT_DESKTOP'],
          homeDir: Platform.environment['HOME'],
        ),
        operation: 'stop',
      ),
      'windows' => await ProxyPlatform.instance.stopProxyDetailed(
        expectedPort: expectedPort,
      ),
      String() => const ProxyOperationResult(
        success: false,
        operation: 'stop',
        stage: 'unsupported',
      ),
    };
  }

  Future<ProxyOperationResult> inspectProxy(int expectedPort) async {
    if (Platform.isWindows) {
      return ProxyPlatform.instance.inspectProxy(expectedPort);
    }
    return const ProxyOperationResult(
      success: false,
      operation: 'inspect',
      stage: 'unsupported',
    );
  }
}

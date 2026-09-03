import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'proxy_method_channel.dart';
import 'src/proxy_result.dart';

abstract class ProxyPlatform extends PlatformInterface {
  /// Constructs a ProxyPlatform.
  ProxyPlatform() : super(token: _token);

  static final Object _token = Object();

  static ProxyPlatform _instance = MethodChannelProxy();

  /// The default instance of [ProxyPlatform] to use.
  ///
  /// Defaults to [MethodChannelProxy].
  static ProxyPlatform get instance => _instance;

  static set instance(ProxyPlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  Future<bool> startProxy(int port, List<String> bypassDomain) {
    throw UnimplementedError('startProxy() has not been implemented.');
  }

  Future<bool> stopProxy({int? expectedPort}) {
    throw UnimplementedError('stopProxy() has not been implemented.');
  }

  Future<ProxyOperationResult> startProxyDetailed(
    int port,
    List<String> bypassDomain,
  ) async {
    final success = await startProxy(port, bypassDomain);
    return ProxyOperationResult.generic(success: success, operation: 'start');
  }

  Future<ProxyOperationResult> stopProxyDetailed({int? expectedPort}) async {
    final success = await stopProxy(expectedPort: expectedPort);
    return ProxyOperationResult.generic(success: success, operation: 'stop');
  }

  Future<ProxyOperationResult> inspectProxy(int expectedPort) async {
    return const ProxyOperationResult(
      success: false,
      operation: 'inspect',
      stage: 'unsupported',
    );
  }
}

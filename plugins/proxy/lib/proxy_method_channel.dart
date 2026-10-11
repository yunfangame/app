import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'proxy_platform_interface.dart';
import 'src/proxy_result.dart';

/// An implementation of [ProxyPlatform] that uses method channels.
class MethodChannelProxy extends ProxyPlatform {
  static const _startProxyMethod = 'StartProxy';
  static const _stopProxyMethod = 'StopProxy';
  static const _startProxyDetailedMethod = 'StartProxyDetailed';
  static const _stopProxyDetailedMethod = 'StopProxyDetailed';
  static const _inspectProxyMethod = 'InspectProxy';
  static const _repairStaleProxyMethod = 'RepairStaleProxyDetailed';

  /// The method channel used to interact with the native platform.
  @visibleForTesting
  final methodChannel = const MethodChannel('proxy');

  @override
  Future<bool> startProxy(int port, List<String> bypassDomain) async {
    return (await startProxyDetailed(port, bypassDomain)).success;
  }

  @override
  Future<bool> stopProxy({int? expectedPort}) async {
    return (await stopProxyDetailed(expectedPort: expectedPort)).success;
  }

  @override
  Future<ProxyOperationResult> startProxyDetailed(
    int port,
    List<String> bypassDomain,
  ) async {
    try {
      final result = await methodChannel.invokeMethod<Object?>(
        _startProxyDetailedMethod,
        {'port': port, 'bypassDomain': bypassDomain},
      );
      return ProxyOperationResult.fromChannel(result, operation: 'start');
    } on MissingPluginException {
      final legacy = await methodChannel.invokeMethod<bool>(_startProxyMethod, {
        'port': port,
        'bypassDomain': bypassDomain,
      });
      return ProxyOperationResult.fromChannel(legacy, operation: 'start');
    } on PlatformException catch (error) {
      return ProxyOperationResult(
        success: false,
        operation: 'start',
        stage: 'method_channel',
        message: '${error.code}: ${error.message ?? ''}'.trim(),
      );
    }
  }

  @override
  Future<ProxyOperationResult> stopProxyDetailed({int? expectedPort}) async {
    try {
      final result = await methodChannel.invokeMethod<Object?>(
        _stopProxyDetailedMethod,
        expectedPort == null ? null : {'expectedPort': expectedPort},
      );
      return ProxyOperationResult.fromChannel(result, operation: 'stop');
    } on MissingPluginException {
      final legacy = await methodChannel.invokeMethod<bool>(_stopProxyMethod);
      return ProxyOperationResult.fromChannel(legacy, operation: 'stop');
    } on PlatformException catch (error) {
      return ProxyOperationResult(
        success: false,
        operation: 'stop',
        stage: 'method_channel',
        message: '${error.code}: ${error.message ?? ''}'.trim(),
      );
    }
  }

  @override
  Future<ProxyOperationResult> repairStaleProxyDetailed(
    int expectedPort,
  ) async {
    if (expectedPort < 1 || expectedPort > 65535) {
      return const ProxyOperationResult(
        success: false,
        operation: 'stop',
        stage: 'invalid_arguments',
      );
    }
    try {
      final result = await methodChannel.invokeMethod<Object?>(
        _repairStaleProxyMethod,
        {'expectedPort': expectedPort},
      );
      return ProxyOperationResult.fromChannel(result, operation: 'stop');
    } on MissingPluginException catch (error) {
      return ProxyOperationResult(
        success: false,
        operation: 'stop',
        stage: 'unsupported',
        message: error.message,
      );
    } on PlatformException catch (error) {
      return ProxyOperationResult(
        success: false,
        operation: 'stop',
        stage: 'method_channel',
        message: '${error.code}: ${error.message ?? ''}'.trim(),
      );
    }
  }

  @override
  Future<ProxyOperationResult> inspectProxy(int expectedPort) async {
    try {
      final result = await methodChannel.invokeMethod<Object?>(
        _inspectProxyMethod,
        {'expectedPort': expectedPort},
      );
      return ProxyOperationResult.fromChannel(result, operation: 'inspect');
    } on MissingPluginException catch (error) {
      return ProxyOperationResult(
        success: false,
        operation: 'inspect',
        stage: 'unsupported',
        message: error.message,
      );
    } on PlatformException catch (error) {
      return ProxyOperationResult(
        success: false,
        operation: 'inspect',
        stage: 'method_channel',
        message: '${error.code}: ${error.message ?? ''}'.trim(),
      );
    }
  }
}

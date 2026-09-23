import 'package:fl_clash/common/desktop_proxy_failure.dart';
import 'package:fl_clash/core/method.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:proxy/proxy.dart';

void main() {
  for (final entry in <String, (DesktopProxyFailureKind, bool)>{
    'address_in_use': (DesktopProxyFailureKind.addressInUse, true),
    'access_denied': (DesktopProxyFailureKind.listenerAccessDenied, true),
    'invalid_bind_address': (DesktopProxyFailureKind.invalidBindAddress, false),
    'address_not_available': (
      DesktopProxyFailureKind.addressNotAvailable,
      false,
    ),
    'bind_failed': (DesktopProxyFailureKind.configurationFailed, false),
  }.entries) {
    test('classifies structured listener reason ${entry.key}', () {
      final failure = DesktopProxyFailure.fromError(
        CoreMethodException(
          code: 'listener_not_ready',
          message: 'Local mixed listener is not ready',
          details: {'listener': 'mixed', 'reason': entry.key},
        ),
        port: 7890,
      );

      expect(failure.kind, entry.value.$1);
      expect(failure.canChangePort, entry.value.$2);
      expect(failure.port, 7890);
      expect(failure.code, 'listener_not_ready');
      expect(failure.reason, entry.key);
      expect(failure.isSystemProxyFailure, isFalse);
    });
  }

  test(
    'local readiness failure allows a new port without claiming a conflict',
    () {
      final failure = DesktopProxyFailure.fromError(
        const CoreMethodException(
          code: 'local_port_unavailable',
          message: 'Local proxy endpoint is unavailable',
          details: {'reason': 'timeout'},
        ),
        port: 7890,
      );

      expect(failure.kind, DesktopProxyFailureKind.localPortUnavailable);
      expect(failure.canChangePort, isTrue);
    },
  );

  test(
    'TUN permission failures are never reported as port permission failures',
    () {
      final failure = DesktopProxyFailure.fromError(
        const CoreMethodException(
          code: 'listener_not_ready',
          message: 'Local tun listener is not ready',
          details: {'listener': 'tun', 'reason': 'access_denied'},
        ),
        port: 7890,
      );

      expect(failure.kind, DesktopProxyFailureKind.configurationFailed);
      expect(failure.canChangePort, isFalse);
    },
  );

  test('unstructured and malformed errors do not claim a port conflict', () {
    for (final error in [
      StateError('address_in_use in subscription text'),
      const CoreMethodException(
        code: 'parse_config_failed',
        message: 'address_in_use in invalid proxy name',
      ),
      const CoreMethodException(
        code: 'listener_not_ready',
        message: 'unknown failure',
        details: 'address_in_use',
      ),
    ]) {
      final failure = DesktopProxyFailure.fromError(error, port: 7890);

      expect(failure.kind, DesktopProxyFailureKind.configurationFailed);
      expect(failure.canChangePort, isFalse);
    }
  });

  for (final stage in [
    'registry_write',
    'apply_default',
    'readback',
    'readback_mismatch',
    'notify_settings_changed',
    'notify_refresh',
    'apply_ras',
    'method_channel',
    'invalid_response',
    'unsupported',
    'platform_apply',
  ]) {
    test('system proxy $stage does not recommend another port', () {
      final result = ProxyOperationResult(
        success: false,
        operation: 'start',
        stage: stage,
      );
      final failure = DesktopProxyFailure.fromSystemProxy(result, port: 7890);

      expect(failure.isSystemProxyFailure, isTrue);
      expect(failure.canChangePort, isFalse);
      expect(failure.port, 7890);
      expect(failure.code, result.diagnosticCode);
      expect(failure.reason, stage);
    });
  }

  test(
    'system permission denial has a distinct cause without a port workaround',
    () {
      final failure = DesktopProxyFailure.fromSystemProxy(
        const ProxyOperationResult(
          success: false,
          operation: 'start',
          stage: 'registry_write',
          errorCode: 5,
        ),
        port: 7890,
      );

      expect(failure.kind, DesktopProxyFailureKind.systemProxyAccessDenied);
      expect(failure.canChangePort, isFalse);
    },
  );

  test('system proxy local-port verification failure can change ports', () {
    final failure = DesktopProxyFailure.fromSystemProxy(
      const ProxyOperationResult(
        success: false,
        operation: 'start',
        stage: 'local_port_unavailable',
      ),
      port: 7890,
    );

    expect(failure.kind, DesktopProxyFailureKind.localPortUnavailable);
    expect(failure.canChangePort, isTrue);
    expect(failure.code, 'W-PROXY-02');
  });
}

import 'package:fl_clash/core/method.dart';
import 'package:proxy/proxy.dart';

enum DesktopProxyFailureKind {
  addressInUse,
  listenerAccessDenied,
  invalidBindAddress,
  addressNotAvailable,
  localPortUnavailable,
  systemProxyAccessDenied,
  systemProxyWriteFailed,
  systemProxyReadbackFailed,
  systemProxyFailed,
  configurationFailed,
}

class DesktopProxyFailure {
  const DesktopProxyFailure({
    required this.kind,
    required this.port,
    required this.code,
    this.reason,
  });

  factory DesktopProxyFailure.fromError(Object error, {required int port}) {
    if (error is DesktopProxyFailure) return error;
    if (error is! CoreMethodException) {
      return DesktopProxyFailure(
        kind: DesktopProxyFailureKind.configurationFailed,
        port: port,
        code: 'configuration_failed',
      );
    }
    final details = error.details;
    final reason = details is Map ? details['reason']?.toString() : null;
    final isTun = details is Map && details['listener'] == 'tun';
    final kind = isTun
        ? DesktopProxyFailureKind.configurationFailed
        : switch (reason ?? error.code) {
            'address_in_use' => DesktopProxyFailureKind.addressInUse,
            'access_denied' => DesktopProxyFailureKind.listenerAccessDenied,
            'invalid_bind_address' =>
              DesktopProxyFailureKind.invalidBindAddress,
            'address_not_available' =>
              DesktopProxyFailureKind.addressNotAvailable,
            'local_port_unavailable' =>
              DesktopProxyFailureKind.localPortUnavailable,
            _ =>
              error.code == 'local_port_unavailable'
                  ? DesktopProxyFailureKind.localPortUnavailable
                  : DesktopProxyFailureKind.configurationFailed,
          };
    return DesktopProxyFailure(
      kind: kind,
      port: port,
      code: error.code,
      reason: reason,
    );
  }

  factory DesktopProxyFailure.fromSystemProxy(
    ProxyOperationResult result, {
    required int port,
  }) {
    final kind = result.stage == 'local_port_unavailable'
        ? DesktopProxyFailureKind.localPortUnavailable
        : result.errorCode == 5 || result.stage == 'access_denied'
        ? DesktopProxyFailureKind.systemProxyAccessDenied
        : switch (result.stage) {
            'registry_write' ||
            'apply_default' => DesktopProxyFailureKind.systemProxyWriteFailed,
            'readback' || 'readback_mismatch' =>
              DesktopProxyFailureKind.systemProxyReadbackFailed,
            _ => DesktopProxyFailureKind.systemProxyFailed,
          };
    return DesktopProxyFailure(
      kind: kind,
      port: port,
      code: result.diagnosticCode,
      reason: result.stage,
    );
  }

  final DesktopProxyFailureKind kind;
  final int port;
  final String code;
  final String? reason;

  bool get canChangePort => switch (kind) {
    DesktopProxyFailureKind.addressInUse ||
    DesktopProxyFailureKind.listenerAccessDenied ||
    DesktopProxyFailureKind.localPortUnavailable => true,
    _ => false,
  };

  bool get isSystemProxyFailure => switch (kind) {
    DesktopProxyFailureKind.systemProxyAccessDenied ||
    DesktopProxyFailureKind.systemProxyWriteFailed ||
    DesktopProxyFailureKind.systemProxyReadbackFailed ||
    DesktopProxyFailureKind.systemProxyFailed => true,
    _ => false,
  };
}

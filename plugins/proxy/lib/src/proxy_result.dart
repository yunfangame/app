import 'package:flutter/foundation.dart';

import 'proxy_command.dart';

@immutable
class ProxyOperationResult {
  const ProxyOperationResult({
    required this.success,
    required this.operation,
    required this.stage,
    this.errorCode,
    this.connectionName,
    this.enabled,
    this.automaticProxyEnabled,
    this.server,
    this.fallbackUsed = false,
    this.rasFailureCount = 0,
    this.message,
    this.command,
    this.commandExitCode,
    this.commandStdout,
    this.commandStderr,
    this.commandSpawnError,
    this.commandSpawnErrorCode,
    this.platform,
    this.writeSkipped = false,
    this.restoreAbandoned = false,
    this.snapshotCount = 0,
    this.restoredCount = 0,
    this.skippedCount = 0,
    this.pendingCleanup = false,
  });

  final bool success;
  final String operation;
  final String stage;
  final int? errorCode;
  final String? connectionName;
  final bool? enabled;
  final bool? automaticProxyEnabled;
  final String? server;
  final bool fallbackUsed;
  final int rasFailureCount;
  final String? message;
  final String? command;
  final int? commandExitCode;
  final String? commandStdout;
  final String? commandStderr;
  final String? commandSpawnError;
  final int? commandSpawnErrorCode;
  final String? platform;
  final bool writeSkipped;
  final bool restoreAbandoned;
  final int snapshotCount;
  final int restoredCount;
  final int skippedCount;
  final bool pendingCleanup;

  ProxyOperationResult withPlatform(String value) {
    if (platform == value) return this;
    return ProxyOperationResult(
      success: success,
      operation: operation,
      stage: stage,
      errorCode: errorCode,
      connectionName: connectionName,
      enabled: enabled,
      automaticProxyEnabled: automaticProxyEnabled,
      server: server,
      fallbackUsed: fallbackUsed,
      rasFailureCount: rasFailureCount,
      message: message,
      command: command,
      commandExitCode: commandExitCode,
      commandStdout: commandStdout,
      commandStderr: commandStderr,
      commandSpawnError: commandSpawnError,
      commandSpawnErrorCode: commandSpawnErrorCode,
      platform: value,
      writeSkipped: writeSkipped,
      restoreAbandoned: restoreAbandoned,
      snapshotCount: snapshotCount,
      restoredCount: restoredCount,
      skippedCount: skippedCount,
      pendingCleanup: pendingCleanup,
    );
  }

  ProxyOperationResult withCommandFailure(ProxyCommandResult? failure) {
    if (failure == null || failure.success || success) return this;
    final failedCommand = failure.command;
    final exception = failure.exception;
    return ProxyOperationResult(
      success: success,
      operation: operation,
      stage: stage,
      errorCode: errorCode,
      connectionName: connectionName,
      enabled: enabled,
      automaticProxyEnabled: automaticProxyEnabled,
      server: server,
      fallbackUsed: fallbackUsed,
      rasFailureCount: rasFailureCount,
      message: message,
      command: failedCommand == null
          ? null
          : _bounded(
              '${failedCommand.executable} ${failedCommand.args.firstOrNull ?? ''}'
                  .trim(),
              256,
            ),
      commandExitCode: failure.processResult?.exitCode,
      commandStdout: _bounded(failure.processResult?.stdout.toString()),
      commandStderr: _bounded(failure.processResult?.stderr.toString()),
      commandSpawnError: exception == null
          ? null
          : _bounded('ProcessException: ${exception.message}'),
      commandSpawnErrorCode: exception?.errorCode,
      platform: platform,
      writeSkipped: writeSkipped,
      restoreAbandoned: restoreAbandoned,
      snapshotCount: snapshotCount,
      restoredCount: restoredCount,
      skippedCount: skippedCount,
      pendingCleanup: pendingCleanup,
    );
  }

  factory ProxyOperationResult.fromChannel(
    Object? value, {
    required String operation,
  }) {
    if (value is bool) {
      return ProxyOperationResult(
        success: value,
        operation: operation,
        stage: value ? 'completed' : 'platform_apply',
        platform: 'windows',
      );
    }
    if (value is Map) {
      return ProxyOperationResult(
        success: value['success'] == true,
        operation: value['operation']?.toString() ?? operation,
        stage: value['stage']?.toString() ?? 'unknown',
        errorCode: _asInt(value['errorCode']),
        connectionName: _asOptionalString(value['connectionName']),
        enabled: value['enabled'] is bool ? value['enabled'] as bool : null,
        automaticProxyEnabled: value['automaticProxyEnabled'] is bool
            ? value['automaticProxyEnabled'] as bool
            : null,
        server: _asOptionalString(value['server']),
        fallbackUsed: value['fallbackUsed'] == true,
        rasFailureCount: _asInt(value['rasFailureCount']) ?? 0,
        message: _asOptionalString(value['message']),
        platform: 'windows',
        writeSkipped: value['writeSkipped'] == true,
        restoreAbandoned: value['restoreAbandoned'] == true,
        snapshotCount: _asCount(value['snapshotCount']),
        restoredCount: _asCount(value['restoredCount']),
        skippedCount: _asCount(value['skippedCount']),
        pendingCleanup: value['pendingCleanup'] == true,
      );
    }
    return ProxyOperationResult(
      success: false,
      operation: operation,
      stage: 'invalid_response',
      message: value == null ? 'Native response is empty' : '$value',
      platform: 'windows',
    );
  }

  factory ProxyOperationResult.generic({
    required bool success,
    required String operation,
    String? message,
  }) => ProxyOperationResult(
    success: success,
    operation: operation,
    stage: success ? 'completed' : 'platform_apply',
    message: message,
  );

  String get diagnosticCode {
    final prefix = switch (platform) {
      'macos' => 'M',
      'linux' => 'L',
      _ => 'W',
    };
    if (success) return '$prefix-PROXY-OK';
    final suffix = switch (stage) {
      'invalid_arguments' => '01',
      'local_port_unavailable' => '02',
      'registry_write' || 'apply_default' => '03',
      'readback' || 'readback_mismatch' => '04',
      'notify_settings_changed' || 'notify_refresh' => '05',
      'apply_ras' => '06',
      'method_channel' || 'invalid_response' => '07',
      'unsupported' => '08',
      'restore' ||
      'restore_readback' ||
      'restore_mismatch' ||
      'restore_default' ||
      'restore_ras' => '10',
      'snapshot' ||
      'capture_original' ||
      'capture_default' ||
      'capture_ras' => '11',
      _ => '09',
    };
    return '$prefix-PROXY-$suffix';
  }

  Map<String, Object?> toDiagnosticFields() => {
    'success': success,
    'operation': operation,
    'stage': stage,
    'diagnostic_code': diagnosticCode,
    if (platform != null) 'platform': platform,
    if (errorCode != null)
      (platform == 'macos' ? 'system_error' : 'win32_error'): errorCode,
    if (connectionName?.isNotEmpty == true) 'connection_name': connectionName,
    if (enabled != null) 'readback_enabled': enabled,
    if (automaticProxyEnabled != null)
      'readback_automatic_proxy_enabled': automaticProxyEnabled,
    if (server?.isNotEmpty == true) 'readback_server': server,
    'fallback_used': fallbackUsed,
    'ras_failure_count': rasFailureCount,
    if (writeSkipped) 'write_skipped': true,
    if (restoreAbandoned) 'restore_abandoned': true,
    if (snapshotCount > 0) 'snapshot_count': snapshotCount,
    if (restoredCount > 0) 'restored_count': restoredCount,
    if (skippedCount > 0) 'skipped_count': skippedCount,
    if (pendingCleanup) 'pending_cleanup': true,
    if (message?.isNotEmpty == true) 'message': message,
    if (command?.isNotEmpty == true) 'command': _bounded(command, 256),
    if (commandExitCode != null) 'command_exit_code': commandExitCode,
    if (commandStdout?.isNotEmpty == true)
      'command_stdout': _bounded(commandStdout),
    if (commandStderr?.isNotEmpty == true)
      'command_stderr': _bounded(commandStderr),
    if (commandSpawnError?.isNotEmpty == true)
      'command_spawn_error': _bounded(commandSpawnError),
    if (commandSpawnErrorCode != null)
      'command_spawn_error_code': commandSpawnErrorCode,
  };

  static String? _bounded(String? value, [int limit = 1024]) {
    final text = value?.trim();
    if (text == null || text.isEmpty) return null;
    return text.length <= limit ? text : text.substring(0, limit);
  }

  static int? _asInt(Object? value) => switch (value) {
    int() => value,
    num() => value.toInt(),
    String() => int.tryParse(value),
    _ => null,
  };

  static String? _asOptionalString(Object? value) {
    final text = value?.toString().trim();
    return text == null || text.isEmpty ? null : text;
  }

  static int _asCount(Object? value) {
    final count = _asInt(value);
    return count != null && count > 0 ? count : 0;
  }
}

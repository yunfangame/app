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
  });

  final bool success;
  final String operation;
  final String stage;
  final int? errorCode;
  final String? connectionName;
  final bool? enabled;
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
        server: _asOptionalString(value['server']),
        fallbackUsed: value['fallbackUsed'] == true,
        rasFailureCount: _asInt(value['rasFailureCount']) ?? 0,
        message: _asOptionalString(value['message']),
      );
    }
    return ProxyOperationResult(
      success: false,
      operation: operation,
      stage: 'invalid_response',
      message: value == null ? 'Native response is empty' : '$value',
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
    if (success) return 'W-PROXY-OK';
    return switch (stage) {
      'invalid_arguments' => 'W-PROXY-01',
      'local_port_unavailable' => 'W-PROXY-02',
      'registry_write' || 'apply_default' => 'W-PROXY-03',
      'readback' || 'readback_mismatch' => 'W-PROXY-04',
      'notify_settings_changed' || 'notify_refresh' => 'W-PROXY-05',
      'apply_ras' => 'W-PROXY-06',
      'method_channel' || 'invalid_response' => 'W-PROXY-07',
      'unsupported' => 'W-PROXY-08',
      _ => 'W-PROXY-09',
    };
  }

  Map<String, Object?> toDiagnosticFields() => {
    'success': success,
    'operation': operation,
    'stage': stage,
    'diagnostic_code': diagnosticCode,
    if (errorCode != null) 'win32_error': errorCode,
    if (connectionName?.isNotEmpty == true) 'connection_name': connectionName,
    if (enabled != null) 'readback_enabled': enabled,
    if (server?.isNotEmpty == true) 'readback_server': server,
    'fallback_used': fallbackUsed,
    'ras_failure_count': rasFailureCount,
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
}

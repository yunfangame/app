import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:proxy/src/proxy_command.dart';
import 'package:proxy/src/proxy_result.dart';

void main() {
  group('ProxyOperationResult command diagnostics', () {
    const failure = ProxyOperationResult(
      success: false,
      operation: 'start',
      stage: 'apply_default',
    );

    test('command failure keeps platform-neutral fields without arguments', () {
      final result = failure.withCommandFailure(
        ProxyCommandResult(
          success: false,
          command: ProxyCommand('/usr/sbin/networksetup', const [
            '-setautoproxystate',
            'Private Service',
            'off',
          ]),
          processResult: ProcessResult(1, 14, 'needs authorization', 'denied'),
        ),
      );

      expect(result.toDiagnosticFields(), {
        'success': false,
        'operation': 'start',
        'stage': 'apply_default',
        'diagnostic_code': 'W-PROXY-03',
        'fallback_used': false,
        'ras_failure_count': 0,
        'command': '/usr/sbin/networksetup -setautoproxystate',
        'command_exit_code': 14,
        'command_stdout': 'needs authorization',
        'command_stderr': 'denied',
      });
      expect(result.errorCode, isNull);
    });

    test('spawn failure is separate from a process exit code', () {
      final result = failure.withCommandFailure(
        ProxyCommandResult(
          success: false,
          command: ProxyCommand('/usr/sbin/networksetup', const [
            '-setwebproxy',
          ]),
          exception: ProcessException(
            '/usr/sbin/networksetup',
            ['-setwebproxy'],
            'permission denied',
            13,
          ),
        ),
      );
      final fields = result.toDiagnosticFields();

      expect(
        fields['command_spawn_error'],
        'ProcessException: permission denied',
      );
      expect(fields['command_spawn_error_code'], 13);
      expect(fields, isNot(contains('command_exit_code')));
      expect(fields, isNot(contains('win32_error')));
    });

    test('command output and spawn messages have bounded size', () {
      final longText = List.filled(3000, 'x').join();
      final result = failure.withCommandFailure(
        ProxyCommandResult(
          success: false,
          command: ProxyCommand(longText, [longText]),
          processResult: ProcessResult(1, 14, longText, longText),
          exception: ProcessException('networksetup', [], longText, 13),
        ),
      );

      expect(result.command, hasLength(256));
      expect(result.commandStdout, hasLength(1024));
      expect(result.commandStderr, hasLength(1024));
      expect(result.commandSpawnError, hasLength(1024));
      expect(result.toDiagnosticFields()['command_stderr'], hasLength(1024));
    });

    test('Windows diagnostics remain unchanged', () {
      final result = ProxyOperationResult.fromChannel({
        'success': false,
        'operation': 'start',
        'stage': 'registry_write',
        'errorCode': 5,
        'connectionName': 'Work VPN',
        'enabled': false,
        'fallbackUsed': true,
        'rasFailureCount': 1,
        'message': 'Access denied',
      }, operation: 'start');

      expect(result.toDiagnosticFields(), {
        'success': false,
        'operation': 'start',
        'stage': 'registry_write',
        'diagnostic_code': 'W-PROXY-03',
        'win32_error': 5,
        'connection_name': 'Work VPN',
        'readback_enabled': false,
        'fallback_used': true,
        'ras_failure_count': 1,
        'message': 'Access denied',
      });
    });
  });
}

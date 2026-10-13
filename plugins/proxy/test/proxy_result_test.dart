import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:proxy/src/proxy_command.dart';
import 'package:proxy/src/proxy_result.dart';

void main() {
  test(
    'RAS trace survives platform tagging and excludes unknown native fields',
    () {
      final result = ProxyOperationResult.fromChannel({
        'success': true,
        'operation': 'start',
        'stage': 'verified',
        'activeRasCount': 0,
        'inactiveRasSkippedCount': 1,
        'savedRasEnumerationError': 5,
        'connectionTrace': [
          {
            'connectionName': 'Old broadband',
            'phase': 'skip_inactive_ras',
            'success': true,
            'active': false,
            'errorCode': 0,
            'elapsedMs': 2,
            'differences': ['inactive_pac_url_ignored', 'private PAC URL'],
            'password': 'must-not-export',
            'server': 'private-server',
          },
        ],
      }, operation: 'start').withPlatform('windows');
      final fields = result.toDiagnosticFields();
      expect(fields['inactive_ras_skipped_count'], 1);
      expect(fields['active_ras_count'], 0);
      expect(fields['saved_ras_enumeration_error'], 5);
      final trace = (fields['connection_trace']! as List).single as Map;
      expect(trace['active'], false);
      expect(trace['phase'], 'skip_inactive_ras');
      expect(trace['differences'], ['inactive_pac_url_ignored']);
      expect(trace, isNot(contains('password')));
      expect(trace, isNot(contains('server')));
      expect(fields.toString(), isNot(contains('must-not-export')));
      expect(fields.toString(), isNot(contains('private PAC URL')));
      expect(
        result.withPlatform('macos').connectionTrace,
        result.connectionTrace,
      );
    },
  );

  test('RAS connection trace and strings have bounded sizes', () {
    final text = List.filled(300, 'x').join();
    final result = ProxyOperationResult.fromChannel({
      'success': false,
      'stage': 'readback_mismatch',
      'traceDroppedCount': 7,
      'connectionTrace': List.filled(300, {
        'connectionName': text,
        'phase': text,
        'expectedFlags': 3,
        'actualFlags': 11,
        'differences': ['flags'],
      }),
    }, operation: 'start');
    expect(result.connectionTrace, hasLength(128));
    expect(result.connectionTrace.first['connection_name'], hasLength(128));
    expect(result.connectionTrace.first['phase'], hasLength(64));
    expect(result.toDiagnosticFields()['connection_trace_dropped_count'], 7);
    expect(result.connectionTrace.first['expected_flags'], 3);
    expect(result.connectionTrace.first['actual_flags'], 11);
  });

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
        'platform': 'windows',
        'connection_name': 'Work VPN',
        'readback_enabled': false,
        'fallback_used': true,
        'ras_failure_count': 1,
        'message': 'Access denied',
      });
    });

    test('automatic proxy state survives decoding and diagnostic copies', () {
      for (final automatic in [false, true]) {
        final result = ProxyOperationResult.fromChannel({
          'success': false,
          'operation': 'inspect',
          'stage': 'readback_mismatch',
          'enabled': false,
          'automaticProxyEnabled': automatic,
        }, operation: 'inspect');
        final tagged = result.withPlatform('macos');
        final copied = tagged.withCommandFailure(
          ProxyCommandResult(
            success: false,
            processResult: ProcessResult(1, 14, '', 'permission denied'),
          ),
        );

        expect(result.automaticProxyEnabled, automatic);
        expect(tagged.automaticProxyEnabled, automatic);
        expect(copied.automaticProxyEnabled, automatic);
        expect(
          copied.toDiagnosticFields()['readback_automatic_proxy_enabled'],
          automatic,
        );
        expect(copied.diagnosticCode, 'M-PROXY-04');
      }
    });

    test('session decisions survive native decoding and platform tagging', () {
      final result = ProxyOperationResult.fromChannel({
        'success': true,
        'operation': 'stop',
        'stage': 'skipped_foreign_proxy',
        'writeSkipped': true,
        'restoreAbandoned': true,
      }, operation: 'stop');

      expect(result.writeSkipped, isTrue);
      expect(result.restoreAbandoned, isTrue);
      expect(result.diagnosticCode, 'W-PROXY-OK');
      expect(result.toDiagnosticFields()['write_skipped'], isTrue);
      expect(result.toDiagnosticFields()['restore_abandoned'], isTrue);
      final tagged = result.withPlatform('macos');
      expect(tagged.writeSkipped, isTrue);
      expect(tagged.restoreAbandoned, isTrue);
      expect(tagged.diagnosticCode, 'M-PROXY-OK');
    });

    test(
      'Mac failure retains the platform and command without Win32 labels',
      () {
        const failure = ProxyOperationResult(
          success: false,
          operation: 'stop',
          stage: 'restore',
          platform: 'macos',
          writeSkipped: true,
          restoreAbandoned: true,
        );
        final result = failure.withCommandFailure(
          ProxyCommandResult(
            success: false,
            command: ProxyCommand('/usr/sbin/networksetup', [
              '-setwebproxy',
              'Private Service',
            ]),
            processResult: ProcessResult(1, 14, '', 'permission denied'),
          ),
        );

        expect(result.diagnosticCode, 'M-PROXY-10');
        expect(result.platform, 'macos');
        expect(result.writeSkipped, isTrue);
        expect(result.restoreAbandoned, isTrue);
        expect(result.toDiagnosticFields(), isNot(contains('win32_error')));
        expect(result.commandExitCode, 14);
        expect(result.command, '/usr/sbin/networksetup -setwebproxy');
        expect(result.withPlatform('macos'), same(result));
      },
    );

    test('snapshot failure has a distinct code with its native error', () {
      final windows = ProxyOperationResult.fromChannel({
        'success': false,
        'stage': 'snapshot',
        'errorCode': 5,
      }, operation: 'start');
      final macos = windows.withPlatform('macos');

      expect(windows.diagnosticCode, 'W-PROXY-11');
      expect(windows.toDiagnosticFields()['win32_error'], 5);
      expect(macos.diagnosticCode, 'M-PROXY-11');
      expect(macos.toDiagnosticFields()['system_error'], 5);
      expect(macos.toDiagnosticFields(), isNot(contains('win32_error')));
    });

    test('native cleanup progress remains visible after platform tagging', () {
      final result = ProxyOperationResult.fromChannel({
        'success': false,
        'operation': 'stop',
        'stage': 'restore_ras',
        'errorCode': 5,
        'snapshotCount': 3,
        'restoredCount': 1,
        'skippedCount': 1,
        'pendingCleanup': true,
      }, operation: 'stop').withPlatform('windows');

      expect(result.diagnosticCode, 'W-PROXY-10');
      expect(result.toDiagnosticFields()['snapshot_count'], 3);
      expect(result.toDiagnosticFields()['restored_count'], 1);
      expect(result.toDiagnosticFields()['skipped_count'], 1);
      expect(result.toDiagnosticFields()['pending_cleanup'], isTrue);
      expect(result.toDiagnosticFields()['win32_error'], 5);
    });
  });
}

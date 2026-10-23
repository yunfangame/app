import 'dart:convert';
import 'dart:io';

import 'package:fl_clash/common/diagnostic_log.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:proxy/src/proxy_result.dart';

void main() {
  test(
    'proxy traces persist in order and export with recursive redaction',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'proxy-trace-log-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final log = DiagnosticLog(directoryLoader: () async => directory);
      final result = ProxyOperationResult.fromChannel({
        'success': false,
        'stage': 'readback_mismatch',
        'errorCode': 13,
        'activeRasCount': 1,
        'inactiveRasSkippedCount': 1,
        'connectionTrace': [
          {
            'connectionName': 'old person@example.com',
            'phase': 'skip_inactive_ras',
            'active': false,
            'success': true,
            'elapsedMs': 0,
          },
          {
            'connectionName': 'VPN 203.0.113.20 edge.example.com',
            'phase': 'readback',
            'active': true,
            'success': false,
            'errorCode': 13,
            'elapsedMs': 7,
            'expectedFlags': 3,
            'actualFlags': 1,
            'differences': ['flags'],
            'password': 'never-export-this',
          },
        ],
      }, operation: 'start');
      await log.record(
        'system_proxy.apply.completed',
        fields: result.toDiagnosticFields(),
      );
      await log.record(
        'system_proxy.restore.completed',
        fields: {'success': true},
      );
      final exported = await log.readAll();
      final entries = const LineSplitter()
          .convert(exported)
          .map((line) => jsonDecode(line) as Map)
          .toList();
      expect(entries, hasLength(2));
      expect(entries.first['sequence'], 1);
      expect(entries.last['sequence'], 2);
      final fields = entries.first['fields'] as Map;
      expect(fields['active_ras_count'], 1);
      expect(fields['inactive_ras_skipped_count'], 1);
      final trace = fields['connection_trace'] as List;
      expect(trace.first['phase'], 'skip_inactive_ras');
      expect(trace.last['phase'], 'readback');
      expect(trace.last['differences'], ['flags']);
      expect(trace.last['win32_error'], 13);
      expect(exported, contains('<redacted-email>'));
      expect(exported, contains('<redacted-ip>'));
      expect(exported, contains('<redacted-host>'));
      for (final secret in [
        'person@example.com',
        '203.0.113.20',
        'edge.example.com',
        'never-export-this',
      ]) {
        expect(exported, isNot(contains(secret)));
      }
    },
  );

  test(
    'successful RAS recovery retains the complete failed-to-verified trace',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'ras-recovery-log-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final log = DiagnosticLog(directoryLoader: () async => directory);
      final phases = [
        'write',
        'readback',
        'notify',
        'verify',
        'ras_retry_activity',
        'ras_retry_write',
        'ras_retry_notify',
        'verify_after_ras_retry',
      ];
      final result = ProxyOperationResult.fromChannel({
        'success': true,
        'stage': 'verified_ansi_fallback',
        'fallbackUsed': true,
        'connectionTrace': phases.map((phase) {
          final mismatch = phase == 'readback' || phase == 'verify';
          return {
            'connectionName': 'VPN private.example.com',
            'phase': phase,
            'success': !mismatch,
            'errorCode': mismatch ? 13 : 0,
            'differences': mismatch ? ['proxy_bypass'] : <String>[],
          };
        }).toList(),
      }, operation: 'start');
      await log.record(
        'system_proxy.apply.completed',
        fields: result.toDiagnosticFields(),
      );
      final exported = await log.readAll();
      final fields = (jsonDecode(exported.trim()) as Map)['fields'] as Map;
      expect(fields['success'], isTrue);
      expect(fields['fallback_used'], isTrue);
      expect(fields['diagnostic_code'], 'W-PROXY-OK');
      final trace = fields['connection_trace'] as List;
      expect(trace.map((row) => (row as Map)['phase']), phases);
      expect(
        trace.where((row) => (row as Map)['success'] == false),
        hasLength(2),
      );
      expect(exported, isNot(contains('private.example.com')));
    },
  );
}

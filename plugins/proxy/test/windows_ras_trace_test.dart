import 'package:flutter_test/flutter_test.dart';
import 'package:proxy/src/proxy_result.dart';

void main() {
  test('active and inactive RAS trace excludes raw configuration values', () {
    final result = ProxyOperationResult.fromChannel({
      'success': true,
      'stage': 'verified',
      'activeRasCount': 0,
      'inactiveRasSkippedCount': 1,
      'restoredCount': 1,
      'connectionTrace': [
        {
          'connectionName': 'Old broadband',
          'phase': 'skip_inactive_ras',
          'active': false,
          'success': true,
          'differences': ['flags', 'private-url'],
          'server': 'private-server',
          'password': 'private-password',
        },
      ],
    }, operation: 'start');
    final fields = result.toDiagnosticFields();
    final trace = (fields['connection_trace']! as List).single as Map;
    expect(fields['active_ras_count'], 0);
    expect(fields['inactive_ras_skipped_count'], 1);
    expect(fields['restored_count'], 1);
    expect(trace['active'], false);
    expect(trace['differences'], ['flags']);
    expect(fields.toString(), isNot(contains('private-password')));
    expect(fields.toString(), isNot(contains('private-server')));
    expect(fields.toString(), isNot(contains('private-url')));
  });

  test(
    'RAS traces are bounded and failed captures retain their diagnostic code',
    () {
      final result = ProxyOperationResult.fromChannel({
        'success': false,
        'stage': 'capture_ras',
        'errorCode': 6,
        'traceDroppedCount': 2,
        'connectionTrace': List.filled(300, {
          'connectionName': 'RAS_ENUM',
          'phase': 'discover_activity',
          'errorCode': 6,
          'success': false,
        }),
      }, operation: 'start');
      expect(result.connectionTrace, hasLength(128));
      expect(result.diagnosticCode, 'W-PROXY-11');
      expect(result.toDiagnosticFields()['connection_trace_dropped_count'], 2);
    },
  );
}

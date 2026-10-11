import 'package:flutter_test/flutter_test.dart';
import 'package:proxy/src/proxy_result.dart';

void main() {
  for (final enabled in [true, false]) {
    test('preserves automatic proxy state $enabled from native readback', () {
      final result = ProxyOperationResult.fromChannel({
        'success': false,
        'stage': 'readback_mismatch',
        'enabled': true,
        'automaticProxyEnabled': enabled,
        'server': '127.0.0.1:17980',
      }, operation: 'inspect');

      expect(result.automaticProxyEnabled, enabled);
      expect(result.enabled, true);
      expect(result.server, '127.0.0.1:17980');
      expect(result.stage, 'readback_mismatch');
      expect(
        result.toDiagnosticFields()['readback_automatic_proxy_enabled'],
        enabled,
      );
    });
  }

  for (final value in [null, 0, 1, 'false', 'true']) {
    test('does not interpret $value as a known automatic proxy state', () {
      final result = ProxyOperationResult.fromChannel({
        'success': false,
        'stage': 'readback',
        'errorCode': 5,
        'automaticProxyEnabled': value,
      }, operation: 'inspect');

      expect(result.automaticProxyEnabled, isNull);
      expect(result.errorCode, 5);
      expect(result.stage, 'readback');
      expect(
        result.toDiagnosticFields().containsKey(
          'readback_automatic_proxy_enabled',
        ),
        isFalse,
      );
    });
  }

  test('older native responses preserve unknown automatic proxy state', () {
    for (final response in [
      true,
      {'success': true, 'stage': 'verified'},
    ]) {
      final result = ProxyOperationResult.fromChannel(
        response,
        operation: 'inspect',
      );

      expect(result.success, isTrue);
      expect(result.automaticProxyEnabled, isNull);
      expect(
        result.toDiagnosticFields().containsKey(
          'readback_automatic_proxy_enabled',
        ),
        isFalse,
      );
    }
  });
}

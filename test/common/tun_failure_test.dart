import 'package:fl_clash/common/tun_failure.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final entry in {
    2: 'helper_missing',
    3: 'helper_missing',
    5: 'access_denied',
    577: 'security_policy_blocked',
    1053: 'service_timeout',
    1067: 'service_exited',
    1072: 'service_pending_delete',
    1223: 'authorization_cancelled',
    1275: 'security_policy_blocked',
  }.entries) {
    test('installer exit ${entry.key} preserves the Windows cause', () {
      final failure = TunFailure.installerExit(entry.key);

      expect(failure.toDiagnosticData(), {
        'stage': 'service_install',
        'reason': entry.value,
        'os_error_code': entry.key,
        'installer_exit_code': entry.key,
      });
    });
  }

  for (final code in [1, 91234]) {
    test('unknown installer exit $code is retained without guessing cause', () {
      final failure = TunFailure.installerExit(code);

      expect(failure.toDiagnosticData(), {
        'stage': 'service_install',
        'reason': 'installer_failed',
        'installer_exit_code': code,
      });
    });
  }
}

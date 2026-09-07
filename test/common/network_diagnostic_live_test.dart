import 'package:fl_clash/common/network_diagnostic.dart';
import 'package:fl_clash/l10n/l10n.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'live YouTube HTTPS probe through an existing local proxy',
    () async {
      await AppLocalizations.load(const Locale('en'));
      final result = await NetworkDiagnosticYouTubeChecker().call(
        const int.fromEnvironment(
          'FENGWO_DIAGNOSTIC_PROXY_PORT',
          defaultValue: 7890,
        ),
      );
      expect(result.success, isTrue, reason: result.displayText);
      expect(result.elapsedMilliseconds, greaterThanOrEqualTo(0));
      expect(result.elapsedMilliseconds, lessThan(8000));
    },
    skip: !const bool.fromEnvironment('FENGWO_LIVE_NETWORK_TEST'),
  );
}

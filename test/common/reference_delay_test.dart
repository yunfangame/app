import 'package:fl_clash/common/reference_delay.dart';
import 'package:fl_clash/l10n/l10n.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('preserves every raw latency measurement', () {
    for (final value in [
      null,
      -100,
      -1,
      0,
      1,
      50,
      80,
      99,
      100,
      101,
      150,
      151,
      350,
      500,
      10000,
    ]) {
      expect(referenceDelayMilliseconds(value), value);
    }
  });

  for (final locale in [
    const Locale('zh', 'CN'),
    const Locale('en'),
    const Locale('ja'),
    const Locale('ru'),
  ]) {
    test('reference formatting and statuses follow locale $locale', () async {
      await AppLocalizations.load(locale);
      final l10n = AppLocalizations.current;
      expect(formatReferenceDelay(500), l10n.referenceDelayValue(500));
      expect(formatReferenceDelay(80), l10n.referenceDelayValue(80));
      expect(formatReferenceDelay(0), l10n.testingStatus);
      expect(formatReferenceDelay(-1), l10n.timeout);
    });
  }
}

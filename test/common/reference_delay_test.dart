import 'package:fl_clash/common/reference_delay.dart';
import 'package:fl_clash/l10n/l10n.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('preserves missing, pending, failed and low latency measurements', () {
    for (final value in [null, -100, -1, 0, 1, 50, 80, 99, 100]) {
      expect(referenceDelayMilliseconds(value), value);
    }
  });

  test('applies the agreed boundaries without a maximum cap', () {
    const values = {
      101: 100,
      120: 100,
      149: 100,
      150: 100,
      151: 101,
      200: 150,
      250: 200,
      251: 201,
      280: 230,
      349: 299,
      350: 300,
      351: 301,
      500: 450,
      1000: 950,
      10000: 9950,
    };
    for (final entry in values.entries) {
      expect(referenceDelayMilliseconds(entry.key), entry.value);
    }
  });

  test('never inverts increasing latency and changes by at most 50 ms', () {
    var previous = 0;
    for (var measured = 1; measured <= 10000; measured++) {
      final displayed = referenceDelayMilliseconds(measured)!;
      expect(displayed, greaterThanOrEqualTo(previous));
      expect(measured - displayed, inInclusiveRange(0, 50));
      if (measured > 100) expect(displayed, greaterThanOrEqualTo(100));
      previous = displayed;
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
      expect(formatReferenceDelay(500), l10n.referenceDelayValue(450));
      expect(formatReferenceDelay(80), l10n.referenceDelayValue(80));
      expect(formatReferenceDelay(0), l10n.testingStatus);
      expect(formatReferenceDelay(-1), l10n.nodeStatusUnknown);
      expect(formatReferenceDelay(500), isNot('450 ms'));
    });
  }
}

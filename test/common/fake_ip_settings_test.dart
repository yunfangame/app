import 'package:fl_clash/common/fake_ip_settings.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('filter normalization preserves advanced expressions and order', () {
    expect(
      normalizeFakeIpFilters(
        ' *.lan \r\n\n+.example.org\n*.lan\n'
        'geosite:private,cn\nrule-set:LocalDomain\n',
      ),
      ['*.lan', '+.example.org', 'geosite:private,cn', 'rule-set:LocalDomain'],
    );
    expect(normalizeFakeIpFilters(' \r\n\t'), isEmpty);
  });

  test('filter patterns accept core syntax and reject unsafe copy-paste', () {
    for (final filter in [
      '*.lan',
      '+.example.org',
      '.example.org',
      'stun.*.*',
      'localhost',
      'geosite:private,cn',
      'rule-set:LocalDomain',
    ]) {
      expect(isValidFakeIpFilter(filter), isTrue, reason: filter);
    }
    for (final filter in [
      '',
      'a..example.org',
      'a.example.org.',
      'a*b.example.org',
      'example.+.org',
      'https://example.org/path',
      'a b.example.org',
      'geosite:',
      'rule-set:',
    ]) {
      expect(isValidFakeIpFilter(filter), isFalse, reason: filter);
    }
  });

  test(
    'range validation accepts usable IPv4 pools and rejects core failures',
    () {
      for (final range in ['198.18.0.1/16', '198.19.0.1/16', '198.18.0.1/29']) {
        expect(isValidFakeIpRange(range), isTrue, reason: range);
      }
      for (final range in [
        '',
        '198.18.0.1',
        '198.18.0.1/30',
        '198.18.0.1/31',
        '198.18.0.1/32',
        '198.18.0.1/33',
        '198.18.0.1/-1',
        '198.18.0.1/abc',
        '198.18.0.256/16',
        '198.18.0/16',
        '::1/16',
        'example.org/16',
        'https://198.18.0.1/16',
      ]) {
        expect(isValidFakeIpRange(range), isFalse, reason: range);
      }
    },
  );
}

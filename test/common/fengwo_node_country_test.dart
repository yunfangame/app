import 'package:fl_clash/common/fengwo_node_country.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('normalizes and deduplicates country and region tags', () {
    expect(
      fengWoCountryCodesFromTags([' HK ', 'hk', 'US', 'us', 'mo', 'TW', 'tw']),
      {'HK', 'US', 'MO', 'TW'},
    );
  });

  test('ignores plan labels, arbitrary codes and node names', () {
    expect(
      fengWoCountryCodesFromTags([
        '',
        ' ',
        'VIP',
        '专线',
        '解锁',
        'Netflix',
        'ZZ',
        'XX',
        '香港',
        'Japan 01',
        'HK-US',
      ]),
      isEmpty,
    );
  });

  test('keeps distinct labels from every node and skips empty lists', () {
    const nodeTags = <List<String>>[
      ['HK', 'VIP'],
      ['HK', 'US'],
      [],
      [' sg ', '专线'],
    ];
    expect(fengWoCountryCodesFromTags(nodeTags.expand((tags) => tags)), {
      'HK',
      'US',
      'SG',
    });
  });

  test('does not invent countries without tags', () {
    expect(fengWoCountryCodesFromTags(const []), isEmpty);
  });
}

import 'package:fl_clash/common/rule_target_repair.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'new subscription default replaces stale targets without changing conditions',
    () {
      final input = [
        r'DOMAIN-REGEX,^(foo,bar|test){1,3}[.]example$,Old',
        'IP-CIDR,192.0.2.0/24,Old,no-resolve',
        'AND,((NETWORK,TCP),(DST-PORT,443)),Old',
        'DOMAIN,keep.example,Active',
        'SUB-RULE,(NETWORK,TCP),nested',
        'MATCH,New',
      ];
      final result = repairRuleTargets(
        input,
        availableTargets: {'GLOBAL', 'Active', 'New'},
        subscriptionRules: ['MATCH,New'],
      );
      expect(result.rules, [
        r'DOMAIN-REGEX,^(foo,bar|test){1,3}[.]example$,New',
        'IP-CIDR,192.0.2.0/24,New,no-resolve',
        'AND,((NETWORK,TCP),(DST-PORT,443)),New',
        'DOMAIN,keep.example,Active',
        'SUB-RULE,(NETWORK,TCP),nested',
        'MATCH,New',
      ]);
      expect(result.replacedCount, 3);
      expect(input[0], endsWith(',Old'));
    },
  );

  test('new default wins over an obsolete local catch-all', () {
    final result = repairRuleTargets(
      ['DOMAIN,test.example,Old', 'MATCH,Old'],
      availableTargets: {'GLOBAL', 'New'},
      subscriptionRules: ['MATCH,New'],
    );
    expect(result.rules, ['DOMAIN,test.example,New', 'MATCH,New']);
  });

  test('successive subscriptions use their own default and rules', () {
    for (final target in ['New A', 'New B']) {
      final current = ['DOMAIN,current.example,REJECT', 'MATCH,$target'];
      final result = repairRuleTargets(
        ['DOMAIN,custom.example,Old', ...current],
        availableTargets: {'GLOBAL', 'REJECT', target},
        subscriptionRules: current,
      );
      expect(result.rules, ['DOMAIN,custom.example,$target', ...current]);
    }
  });

  test(
    'valid configuration is byte stable and malformed rules are not removed',
    () {
      final rules = [
        'DOMAIN,valid.example, DIRECT ',
        'DOMAIN,missing-target.example,',
        'invalid',
        'SUB-RULE,(NETWORK,TCP),missing-sub-rule',
        'MATCH,DIRECT',
      ];
      final result = repairRuleTargets(
        rules,
        availableTargets: {'DIRECT', 'GLOBAL'},
        subscriptionRules: rules,
      );
      expect(result.rules, rules);
      expect(result.replacedCount, 0);
    },
  );
}

import 'package:fl_clash/common/default_rule_target.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('uses the first catch-all rather than a visited service group', () {
    expect(
      defaultRuleTarget('''
rules:
  - DOMAIN-SUFFIX,netflix.com,Netflix
  - MATCH,Main
  - MATCH,Unused
'''),
      'Main',
    );
  });

  test('follows the default chain wrapper to its selection group', () {
    expect(
      defaultRuleTarget('''
proxies:
  - name: Wrapper
    type: socks5
    dialer-proxy: Main
rules:
  - MATCH,Wrapper
'''),
      'Main',
    );
  });

  test('keeps explicit direct catch-all identifiable', () {
    expect(defaultRuleTarget('rules: ["MATCH,DIRECT"]'), 'DIRECT');
  });

  test('does not infer a target from an unrelated rule', () {
    expect(defaultRuleTarget('rules: ["DOMAIN,example.com,Main"]'), isNull);
    expect(defaultRuleTarget(''), isNull);
  });

  test('cyclic dialer wrappers cannot become default targets', () {
    expect(
      defaultRuleTarget('''
proxies:
  - name: A
    dialer-proxy: B
  - name: B
    dialer-proxy: A
rules:
  - MATCH,A
'''),
      isNull,
    );
  });
}

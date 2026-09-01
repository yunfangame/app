import 'package:fl_clash/common/network.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('local network bypass merges safety entries with saved settings', () {
    final result = withLocalNetworkBypassDomains([
      'custom.internal',
      '172.2*',
      '192.168.*',
    ]);

    expect(result.first, 'custom.internal');
    expect(result, isNot(contains('172.2*')));
    expect(result, containsAll(localNetworkBypassDomains));
    expect(result.where((value) => value == '192.168.*'), hasLength(1));
  });

  test('local DNS filters preserve profile values and avoid duplicates', () {
    final result = withLocalNetworkFakeIpFilters([
      'printer.example',
      '*.lan',
      123,
    ]);

    expect(result.first, 'printer.example');
    expect(result, containsAll(localNetworkFakeIpFilters));
    expect(result.where((value) => value == '*.lan'), hasLength(1));
  });

  test('local direct rules are placed before subscription rules', () {
    final result = withLocalNetworkDirectRules([
      'MATCH,Proxy',
      localNetworkDirectRules.first,
    ]);

    expect(
      result.take(localNetworkDirectRules.length),
      localNetworkDirectRules,
    );
    expect(result.last, 'MATCH,Proxy');
    expect(
      result.where((value) => value == localNetworkDirectRules.first),
      hasLength(1),
    );
  });
}

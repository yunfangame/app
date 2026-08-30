import 'package:fl_clash/common/xboard_auth.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const offlineNode = XboardNodeData(
    name: '🇸🇬 新加坡-专线-01',
    type: 'anytls',
    rate: 1,
    tags: ['SG'],
    isOnline: false,
    rawData: {},
  );
  const onlineNode = XboardNodeData(
    name: '日本-专线-01',
    type: 'anytls',
    rate: 1,
    tags: ['JP'],
    isOnline: true,
    rawData: {},
  );

  test('XBoard offline nodes are matched despite display separators', () {
    expect(
      isXboardNodeMarkedOffline('新加坡 专线 01', const [offlineNode, onlineNode]),
      isTrue,
    );
  });

  test('online and unknown nodes remain eligible for delay tests', () {
    expect(
      isXboardNodeMarkedOffline('日本-专线-01', const [offlineNode, onlineNode]),
      isFalse,
    );
    expect(
      isXboardNodeMarkedOffline('台湾-专线-01', const [offlineNode, onlineNode]),
      isFalse,
    );
  });
}

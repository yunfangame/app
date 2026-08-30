import 'package:fl_clash/common/cloudflare_optimizer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parses bounded Cloudflare optimization settings', () {
    final config = CloudflareOptimizeConfig.fromRemote({
      'cfOptimize': {
        'targets': [
          'cf.example.com',
          {'domain': 'EDGE.EXAMPLE.COM', 'port': 8443},
          {'domain': 'invalid', 'port': 0},
          'cf.example.com',
        ],
        'candidateIps': ['104.16.1.1', 'invalid', '104.16.1.1'],
        'candidateCount': 500,
        'downloadBytes': 100,
        'topCount': 20,
      },
    });

    expect(config.targets.map((target) => '${target.domain}:${target.port}'), [
      'cf.example.com:443',
      'edge.example.com:8443',
    ]);
    expect(config.candidateIps, ['104.16.1.1']);
    expect(config.candidateCount, 200);
    expect(config.downloadBytes, 250000);
    expect(config.topCount, 10);
    expect(config.canApply, isTrue);
  });

  test('missing remote section keeps optimization read only', () {
    final config = CloudflareOptimizeConfig.fromRemote(const {});

    expect(config.targets, isEmpty);
    expect(config.canApply, isFalse);
    expect(config.candidateCount, 48);
    expect(config.topCount, 5);
  });
}

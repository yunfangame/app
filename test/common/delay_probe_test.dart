import 'package:fl_clash/common/delay_probe.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('delay probes preserve HTTPS and replace insecure URLs', () {
    expect(
      reliableDelayProbeUrl('https://example.com/ping'),
      'https://example.com/ping',
    );
    expect(
      reliableDelayProbeUrl(
        'http://www.gstatic.com/generate_204',
        fallback: 'https://fallback.example/ping',
      ),
      'https://fallback.example/ping',
    );
  });

  test('runtime normalization only rewrites health-check probes', () {
    final config = <String, dynamic>{
      'proxy-groups': [
        {'name': '自动选择', 'url': 'http://www.gstatic.com/generate_204'},
      ],
      'proxy-providers': {
        'remote': {
          'url': 'http://subscription.example/profile.yaml',
          'health-check': {'url': 'http://www.gstatic.com/generate_204'},
        },
      },
    };

    normalizeRuntimeDelayProbeUrls(
      config,
      fallback: 'https://fallback.example/ping',
    );

    expect(config['proxy-groups'][0]['url'], 'https://fallback.example/ping');
    expect(
      config['proxy-providers']['remote']['health-check']['url'],
      'https://fallback.example/ping',
    );
    expect(
      config['proxy-providers']['remote']['url'],
      'http://subscription.example/profile.yaml',
    );
  });

  test('identifies the known native second-response diagnostic', () {
    expect(
      isNoisyDelayProbeDiagnostic(
        'node failed to get the second response from '
        'http://www.gstatic.com/generate_204: context deadline exceeded',
      ),
      isTrue,
    );
    expect(
      isNoisyDelayProbeDiagnostic(
        'node failed to get the second response from '
        'https://www.gstatic.com/generate_204: context canceled',
      ),
      isTrue,
    );
    expect(
      isNoisyDelayProbeDiagnostic(
        'node Head "https://www.gstatic.com/generate_204": '
        'context deadline exceeded',
      ),
      isTrue,
    );
    expect(isNoisyDelayProbeDiagnostic('TUN failed to start'), isFalse);
  });
}

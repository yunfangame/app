import 'package:fl_clash/common/delay_probe.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('delay probes preserve valid HTTP and HTTPS URLs', () {
    expect(
      reliableDelayProbeUrl(null),
      'http://cp.cloudflare.com/generate_204',
    );
    expect(
      reliableDelayProbeUrl('https://example.com/ping'),
      'https://example.com/ping',
    );
    expect(
      reliableDelayProbeUrl('http://cp.cloudflare.com/generate_204'),
      'http://cp.cloudflare.com/generate_204',
    );
    expect(
      reliableDelayProbeUrl(
        'ftp://invalid.example/ping',
        fallback: 'http://cp.cloudflare.com/generate_204',
      ),
      'http://cp.cloudflare.com/generate_204',
    );
  });

  test('runtime normalization only rewrites health-check probes', () {
    final config = <String, dynamic>{
      'proxy-groups': [
        {'name': '自动选择', 'url': 'ftp://invalid.example/ping'},
      ],
      'proxy-providers': {
        'remote': {
          'url': 'http://subscription.example/profile.yaml',
          'health-check': {'url': 'ftp://invalid.example/ping'},
        },
      },
    };

    normalizeRuntimeDelayProbeUrls(
      config,
      fallback: 'http://cp.cloudflare.com/generate_204',
    );

    expect(
      config['proxy-groups'][0]['url'],
      'http://cp.cloudflare.com/generate_204',
    );
    expect(
      config['proxy-providers']['remote']['health-check']['url'],
      'http://cp.cloudflare.com/generate_204',
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

import 'package:fl_clash/common/chain_proxy.dart';
import 'package:fl_clash/common/chain_proxy_validation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('successful preferred probe needs no fallback', () async {
    final urls = <String>[];
    final result = await validateChainRuntimeConnectivity(
      testUrl: 'https://probe.example/204',
      probe: (url) async {
        urls.add(url);
        return 80;
      },
    );
    expect(result.isAvailable, isTrue);
    expect(urls, ['https://probe.example/204']);
  });

  test('one failed website does not disable a working chain', () async {
    final urls = <String>[];
    final attempts = <(int, int?, Object?)>[];
    final result = await validateChainRuntimeConnectivity(
      testUrl: 'http://cp.cloudflare.com/generate_204',
      probe: (url) async {
        urls.add(url);
        return urls.length == 1 ? -1 : 120;
      },
      onAttempt: (attempt, delay, error) =>
          attempts.add((attempt, delay, error)),
    );
    expect(result.isAvailable, isTrue);
    expect(urls, [
      'http://cp.cloudflare.com/generate_204',
      'https://www.gstatic.com/generate_204',
    ]);
    expect(attempts, [(1, -1, null), (2, 120, null)]);
  });

  test('probe error is recorded and fallback can verify the chain', () async {
    final failure = StateError('probe unavailable');
    final errors = <Object?>[];
    var calls = 0;
    final result = await validateChainRuntimeConnectivity(
      testUrl: 'https://probe.example/204',
      probe: (_) async {
        if (++calls == 1) throw failure;
        return 200;
      },
      onAttempt: (_, _, error) => errors.add(error),
    );
    expect(result.isAvailable, isTrue);
    expect(errors, [failure, null]);
  });

  test('two unavailable probes still reject the chain', () async {
    var calls = 0;
    final result = await validateChainRuntimeConnectivity(
      testUrl: 'https://probe.example/204',
      probe: (_) async {
        calls++;
        return -1;
      },
    );
    expect(result.status, ChainProxyValidationStatus.unavailable);
    expect(calls, 2);
  });

  test(
    'fallback is on a different host from a gstatic preferred URL',
    () async {
      final urls = <String>[];
      await validateChainRuntimeConnectivity(
        testUrl: 'https://www.gstatic.com/generate_204',
        probe: (url) async {
          urls.add(url);
          return null;
        },
      );
      expect(urls.map((url) => Uri.parse(url).host).toSet().length, 2);
    },
  );
}

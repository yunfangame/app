import 'chain_proxy.dart';
import 'delay_probe.dart';

Future<ChainProxyValidationResult> validateChainRuntimeConnectivity({
  required String testUrl,
  required Future<int?> Function(String url) probe,
  void Function(int attempt, int? delay, Object? error)? onAttempt,
}) async {
  final primary = reliableDelayProbeUrl(testUrl);
  final fallback = Uri.parse(primary).host == 'www.gstatic.com'
      ? 'https://cp.cloudflare.com/generate_204'
      : 'https://www.gstatic.com/generate_204';
  final urls = [primary, fallback];
  for (var index = 0; index < urls.length; index++) {
    int? delay;
    Object? failure;
    try {
      delay = await probe(urls[index]);
    } catch (error) {
      failure = error;
    }
    onAttempt?.call(index + 1, delay, failure);
    if (delay != null && delay > 0) {
      return const ChainProxyValidationResult(
        ChainProxyValidationStatus.available,
      );
    }
  }
  return const ChainProxyValidationResult(
    ChainProxyValidationStatus.unavailable,
  );
}

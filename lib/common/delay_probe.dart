import 'package:fl_clash/common/constant.dart';

/// Returns a stable HTTPS endpoint for latency and health-check probes.
///
/// Clash Meta's unified-delay mode performs a second request. Plain HTTP
/// endpoints such as gstatic's generate_204 can fail during that second
/// request even when the proxy itself is healthy, so they are replaced at
/// runtime without changing the user's saved subscription.
String reliableDelayProbeUrl(String? requested, {String? fallback}) {
  final requestedUri = Uri.tryParse(requested?.trim() ?? '');
  if (requestedUri != null &&
      requestedUri.scheme == 'https' &&
      requestedUri.host.isNotEmpty) {
    return requestedUri.toString();
  }

  final fallbackUri = Uri.tryParse(fallback?.trim() ?? '');
  if (fallbackUri != null &&
      fallbackUri.scheme == 'https' &&
      fallbackUri.host.isNotEmpty) {
    return fallbackUri.toString();
  }
  return defaultTestUrl;
}

/// Rewrites only probe URLs in the runtime copy of a Clash profile.
/// Subscription/provider download addresses are intentionally untouched.
Map<String, dynamic> normalizeRuntimeDelayProbeUrls(
  Map<String, dynamic> config, {
  String fallback = defaultTestUrl,
}) {
  void normalizeEntry(dynamic value) {
    if (value is! Map) return;
    final url = value['url'];
    if (url is String && url.isNotEmpty) {
      value['url'] = reliableDelayProbeUrl(url, fallback: fallback);
    }
  }

  final groups = config['proxy-groups'];
  if (groups is List) {
    for (final group in groups) {
      normalizeEntry(group);
    }
  }

  final providers = config['proxy-providers'];
  if (providers is Map) {
    for (final provider in providers.values) {
      if (provider is! Map) continue;
      normalizeEntry(provider['health-check']);
    }
  }
  return config;
}

/// Native delay-probe diagnostics remain available in the log page but should
/// not be exposed to users as a raw error toast.
bool isNoisyDelayProbeDiagnostic(String payload) {
  final normalized = payload.toLowerCase();
  if (normalized.contains('failed to get the second response')) {
    return true;
  }
  final isGenerate204Probe =
      normalized.contains('generate_204') || normalized.contains('generate204');
  final isExpectedProbeFailure =
      normalized.contains('context deadline exceeded') ||
      normalized.contains('context canceled') ||
      normalized.contains('context cancelled');
  return isGenerate204Probe && isExpectedProbeFailure;
}

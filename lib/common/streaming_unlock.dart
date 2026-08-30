import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:fl_clash/common/request.dart';

enum StreamingPlatform {
  netflix,
  disneyPlus,
  youtubePremium,
  chatGpt,
  gemini,
  claude,
  tikTok,
}

enum StreamingUnlockStatus { unlocked, reachable, restricted, failed }

enum StreamingUnlockFailureReason { timeout, network, service }

class StreamingUnlockResult {
  const StreamingUnlockResult({
    required this.platform,
    required this.status,
    this.region,
    this.failureReason,
  });

  final StreamingPlatform platform;
  final StreamingUnlockStatus status;
  final String? region;
  final StreamingUnlockFailureReason? failureReason;

  bool get isPageAccessible =>
      status == StreamingUnlockStatus.unlocked ||
      status == StreamingUnlockStatus.reachable;

  StreamingUnlockResult copyWith({
    StreamingUnlockStatus? status,
    String? region,
    StreamingUnlockFailureReason? failureReason,
  }) {
    return StreamingUnlockResult(
      platform: platform,
      status: status ?? this.status,
      region: region ?? this.region,
      failureReason: failureReason ?? this.failureReason,
    );
  }
}

class StreamingUnlockResponse {
  const StreamingUnlockResponse({
    required this.statusCode,
    required this.body,
    required this.finalUri,
  });

  final int statusCode;
  final String body;
  final Uri finalUri;
}

typedef StreamingUnlockFetcher =
    Future<StreamingUnlockResponse> Function(Uri uri);

class StreamingUnlockTester {
  StreamingUnlockTester({
    StreamingUnlockFetcher? fetcher,
    this.requestTimeout = const Duration(seconds: 25),
    this.retryDelay = const Duration(milliseconds: 350),
    this.maxAttempts = 2,
  }) : _fetcher = fetcher;

  final StreamingUnlockFetcher? _fetcher;
  final Duration requestTimeout;
  final Duration retryDelay;
  final int maxAttempts;

  Future<StreamingUnlockResult> test(StreamingPlatform platform) async {
    final uris = _urisFor(platform);
    StreamingUnlockResult? preliminary;
    for (var index = 0; index < uris.length; index++) {
      final result = await _testUri(platform, uris[index]);
      final isPreliminary = index < uris.length - 1;
      if (!isPreliminary) {
        if (result.status == StreamingUnlockStatus.failed &&
            preliminary != null) {
          return result.copyWith(
            status: StreamingUnlockStatus.reachable,
            region: preliminary.region,
          );
        }
        return result.region == null && preliminary?.region != null
            ? result.copyWith(region: preliminary?.region)
            : result;
      }
      if (result.status == StreamingUnlockStatus.failed ||
          result.status == StreamingUnlockStatus.restricted) {
        return result;
      }
      preliminary = result;
    }
    return StreamingUnlockResult(
      platform: platform,
      status: StreamingUnlockStatus.failed,
      failureReason: StreamingUnlockFailureReason.network,
    );
  }

  Future<List<StreamingUnlockResult>> testAll(
    Iterable<StreamingPlatform> platforms, {
    int maxConcurrent = 2,
    void Function(StreamingUnlockResult result)? onResult,
  }) async {
    final pending = platforms.toList(growable: false);
    if (pending.isEmpty) return const [];
    final results = List<StreamingUnlockResult?>.filled(pending.length, null);
    var nextIndex = 0;

    Future<void> worker() async {
      while (nextIndex < pending.length) {
        final index = nextIndex++;
        final result = await test(pending[index]);
        results[index] = result;
        onResult?.call(result);
      }
    }

    final workerCount = maxConcurrent.clamp(1, pending.length);
    await Future.wait(List.generate(workerCount, (_) => worker()));
    return results.cast<StreamingUnlockResult>();
  }

  Future<StreamingUnlockResult> _testUri(
    StreamingPlatform platform,
    Uri uri,
  ) async {
    final attempts = maxAttempts < 1 ? 1 : maxAttempts;
    final attemptTimeout = Duration(
      microseconds: requestTimeout.inMicroseconds ~/ attempts,
    );
    StreamingUnlockResult? lastResult;
    for (var attempt = 0; attempt < attempts; attempt++) {
      try {
        final response =
            await (_fetcher?.call(uri) ?? _fetch(uri, attemptTimeout)).timeout(
              attemptTimeout,
            );
        final result = classifyStreamingResponse(platform, response);
        if (result.status != StreamingUnlockStatus.failed ||
            attempt == attempts - 1) {
          return result;
        }
        lastResult = result;
      } catch (error) {
        lastResult = StreamingUnlockResult(
          platform: platform,
          status: StreamingUnlockStatus.failed,
          failureReason: _failureReasonFor(error),
        );
        if (attempt == attempts - 1) return lastResult;
      }
      if (retryDelay > Duration.zero) await Future<void>.delayed(retryDelay);
    }
    return lastResult!;
  }

  Future<StreamingUnlockResponse> _fetch(Uri uri, Duration timeout) async {
    final cancelToken = CancelToken();
    final future = () async {
      final response = await request.getStreamResponseForUrl(
        uri.toString(),
        includeHttpErrors: true,
        cancelToken: cancelToken,
      );
      final body = await _readLimitedText(response.data?.stream);
      return StreamingUnlockResponse(
        statusCode: response.statusCode ?? 0,
        body: body,
        finalUri: response.realUri,
      );
    }();
    try {
      return await future.timeout(
        timeout,
        onTimeout: () {
          cancelToken.cancel('streaming probe timed out');
          throw TimeoutException('Streaming probe timed out');
        },
      );
    } catch (_) {
      if (!cancelToken.isCancelled) cancelToken.cancel();
      rethrow;
    }
  }
}

StreamingUnlockResult classifyStreamingResponse(
  StreamingPlatform platform,
  StreamingUnlockResponse response,
) {
  final statusCode = response.statusCode;
  final content = '${response.finalUri}\n${response.body}'.toLowerCase();
  final region = _detectRegion(platform, content);
  if (statusCode == 0 || statusCode >= 500) {
    return StreamingUnlockResult(
      platform: platform,
      status: StreamingUnlockStatus.failed,
      region: region,
      failureReason: statusCode == 0
          ? StreamingUnlockFailureReason.network
          : StreamingUnlockFailureReason.service,
    );
  }
  if (_isExplicitlyRestricted(platform, response)) {
    return StreamingUnlockResult(
      platform: platform,
      status: StreamingUnlockStatus.restricted,
      region: region,
    );
  }
  if (statusCode >= 400) {
    return StreamingUnlockResult(
      platform: platform,
      status: StreamingUnlockStatus.reachable,
      region: region,
    );
  }
  return StreamingUnlockResult(
    platform: platform,
    status: StreamingUnlockStatus.unlocked,
    region: region,
  );
}

bool _isExplicitlyRestricted(
  StreamingPlatform platform,
  StreamingUnlockResponse response,
) {
  if (response.statusCode == 451) return true;
  final finalUri = response.finalUri.toString().toLowerCase();
  return switch (platform) {
    StreamingPlatform.disneyPlus => const [
      '/welcome/unavailable',
      '/unavailable',
    ].any(finalUri.contains),
    StreamingPlatform.gemini => finalUri.contains('/unsupported-country'),
    StreamingPlatform.claude => finalUri.contains('/app-unavailable-in-region'),
    _ => false,
  };
}

List<Uri> _urisFor(StreamingPlatform platform) {
  return switch (platform) {
    StreamingPlatform.netflix => [
      Uri.parse('https://www.netflix.com/'),
      Uri.parse('https://www.netflix.com/title/81215567'),
    ],
    StreamingPlatform.disneyPlus => [Uri.parse('https://www.disneyplus.com/')],
    StreamingPlatform.youtubePremium => [
      Uri.parse('https://www.youtube.com/'),
      Uri.parse('https://www.youtube.com/premium'),
    ],
    StreamingPlatform.chatGpt => [Uri.parse('https://chatgpt.com/')],
    StreamingPlatform.gemini => [Uri.parse('https://gemini.google.com/')],
    StreamingPlatform.claude => [Uri.parse('https://claude.ai/')],
    StreamingPlatform.tikTok => [Uri.parse('https://www.tiktok.com/')],
  };
}

StreamingUnlockFailureReason _failureReasonFor(Object error) {
  if (error is TimeoutException ||
      error is DioException &&
          {
            DioExceptionType.connectionTimeout,
            DioExceptionType.sendTimeout,
            DioExceptionType.receiveTimeout,
          }.contains(error.type)) {
    return StreamingUnlockFailureReason.timeout;
  }
  return StreamingUnlockFailureReason.network;
}

Future<String> _readLimitedText(
  Stream<Uint8List>? stream, {
  int maxBytes = 512 * 1024,
}) async {
  if (stream == null) return '';
  final bytes = BytesBuilder(copy: false);
  await for (final chunk in stream) {
    final remaining = maxBytes - bytes.length;
    if (remaining <= 0) break;
    bytes.add(chunk.length <= remaining ? chunk : chunk.sublist(0, remaining));
    if (bytes.length >= maxBytes) break;
  }
  return utf8.decode(bytes.takeBytes(), allowMalformed: true);
}

String? _detectRegion(StreamingPlatform platform, String content) {
  final patterns = switch (platform) {
    StreamingPlatform.netflix => [
      RegExp(r'netflix\.com/([a-z]{2})(?:-[a-z]{2})?/'),
    ],
    StreamingPlatform.youtubePremium => [
      RegExp(r'"countrycode"\s*:\s*"([a-z]{2})"'),
      RegExp(r'"gl"\s*:\s*"([a-z]{2})"'),
    ],
    StreamingPlatform.disneyPlus => [
      RegExp(r'disneyplus\.com/(?:[a-z]{2}-)?([a-z]{2})(?:[/#?]|$)'),
    ],
    _ => const <RegExp>[],
  };
  for (final pattern in patterns) {
    final value = pattern.firstMatch(content)?.group(1);
    if (value != null && value.isNotEmpty) return value.toUpperCase();
  }
  return null;
}

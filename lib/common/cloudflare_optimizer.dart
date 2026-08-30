import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:fl_clash/common/api_health.dart';
import 'package:fl_clash/common/request.dart';

const cloudflareOptimizeConfigKey = 'cfOptimize';

class CloudflareOptimizeTarget {
  const CloudflareOptimizeTarget({required this.domain, this.port = 443});

  final String domain;
  final int port;
}

class CloudflareOptimizeConfig {
  const CloudflareOptimizeConfig({
    this.targets = const [],
    this.candidateIps = const [],
    this.candidateCount = 48,
    this.downloadBytes = 2000000,
    this.topCount = 5,
  });

  factory CloudflareOptimizeConfig.fromRemote(Object? remoteConfig) {
    if (remoteConfig is! Map) return const CloudflareOptimizeConfig();
    final value = remoteConfig[cloudflareOptimizeConfigKey];
    if (value is! Map) return const CloudflareOptimizeConfig();
    final targets = <CloudflareOptimizeTarget>[];
    final rawTargets = value['targets'];
    if (rawTargets is List) {
      for (final rawTarget in rawTargets) {
        final domain = switch (rawTarget) {
          final String text => text.trim().toLowerCase(),
          final Map map =>
            (map['domain'] as String? ?? '').trim().toLowerCase(),
          _ => '',
        };
        final port = switch (rawTarget) {
          final Map map => _boundedInt(map['port'], 443, 1, 65535),
          _ => 443,
        };
        if (_validDomain(domain) &&
            !targets.any((target) => target.domain == domain)) {
          targets.add(CloudflareOptimizeTarget(domain: domain, port: port));
        }
      }
    }
    final candidateIps = <String>[];
    final rawCandidateIps = value['candidateIps'];
    if (rawCandidateIps is List) {
      for (final entry in rawCandidateIps) {
        if (entry is! String) continue;
        final ip = InternetAddress.tryParse(entry.trim());
        if (ip?.type == InternetAddressType.IPv4 &&
            !candidateIps.contains(ip!.address)) {
          candidateIps.add(ip.address);
        }
      }
    }
    return CloudflareOptimizeConfig(
      targets: List.unmodifiable(targets),
      candidateIps: List.unmodifiable(candidateIps),
      candidateCount: _boundedInt(value['candidateCount'], 48, 10, 200),
      downloadBytes: _boundedInt(
        value['downloadBytes'],
        2000000,
        250000,
        10000000,
      ),
      topCount: _boundedInt(value['topCount'], 5, 1, 10),
    );
  }

  final List<CloudflareOptimizeTarget> targets;
  final List<String> candidateIps;
  final int candidateCount;
  final int downloadBytes;
  final int topCount;

  bool get canApply => targets.isNotEmpty;
}

class CloudflareOptimizeResult {
  const CloudflareOptimizeResult({
    required this.ip,
    required this.latency,
    required this.downloadBytesPerSecond,
    required this.region,
  });

  final String ip;
  final Duration latency;
  final double downloadBytesPerSecond;
  final String region;
}

class CloudflareOptimizeProgress {
  const CloudflareOptimizeProgress({
    required this.completed,
    required this.total,
    required this.stage,
  });

  final int completed;
  final int total;
  final CloudflareOptimizeStage stage;

  double get value => total == 0 ? 0 : completed / total;
}

enum CloudflareOptimizeStage { loading, latency, download, completed }

class CloudflareOptimizer {
  CloudflareOptimizer({ApiHealthService? apiHealthService, Random? random})
    : _apiHealthService = apiHealthService ?? ApiHealthService(),
      _random = random ?? Random.secure();

  final ApiHealthService _apiHealthService;
  final Random _random;

  Future<CloudflareOptimizeConfig> loadConfig() async {
    try {
      final remoteConfig = await _apiHealthService.loadConfig();
      return CloudflareOptimizeConfig.fromRemote(remoteConfig);
    } catch (_) {
      return const CloudflareOptimizeConfig();
    }
  }

  Future<List<CloudflareOptimizeResult>> optimize(
    CloudflareOptimizeConfig config, {
    void Function(CloudflareOptimizeProgress progress)? onProgress,
  }) async {
    onProgress?.call(
      const CloudflareOptimizeProgress(
        completed: 0,
        total: 1,
        stage: CloudflareOptimizeStage.loading,
      ),
    );
    final candidates = await _loadCandidates(config);
    if (candidates.isEmpty) return const [];
    var completed = 0;
    final latencyResults = await _mapConcurrent<String, _LatencyResult?>(
      candidates,
      16,
      (ip) async {
        final result = await _testLatency(ip);
        completed++;
        onProgress?.call(
          CloudflareOptimizeProgress(
            completed: completed,
            total: candidates.length,
            stage: CloudflareOptimizeStage.latency,
          ),
        );
        return result;
      },
    );
    final available = latencyResults.whereType<_LatencyResult>().toList()
      ..sort((left, right) => left.latency.compareTo(right.latency));
    final downloadCandidates = available.take(12).toList();
    completed = 0;
    final downloadResults =
        await _mapConcurrent<_LatencyResult, CloudflareOptimizeResult?>(
          downloadCandidates,
          3,
          (candidate) async {
            final result = await _testDownload(candidate, config.downloadBytes);
            completed++;
            onProgress?.call(
              CloudflareOptimizeProgress(
                completed: completed,
                total: downloadCandidates.length,
                stage: CloudflareOptimizeStage.download,
              ),
            );
            return result;
          },
        );
    final results =
        downloadResults.whereType<CloudflareOptimizeResult>().toList()
          ..sort((left, right) {
            final speed = right.downloadBytesPerSecond.compareTo(
              left.downloadBytesPerSecond,
            );
            return speed == 0 ? left.latency.compareTo(right.latency) : speed;
          });
    final top = results.take(config.topCount).toList(growable: false);
    onProgress?.call(
      CloudflareOptimizeProgress(
        completed: top.length,
        total: top.length,
        stage: CloudflareOptimizeStage.completed,
      ),
    );
    return top;
  }

  Future<Map<String, String>> validateTargets(
    CloudflareOptimizeConfig config,
    List<CloudflareOptimizeResult> results,
  ) async {
    final mappings = <String, String>{};
    for (
      var targetIndex = 0;
      targetIndex < config.targets.length;
      targetIndex++
    ) {
      final target = config.targets[targetIndex];
      for (var offset = 0; offset < results.length; offset++) {
        final result = results[(targetIndex + offset) % results.length];
        if (await _validateTarget(result.ip, target)) {
          mappings[target.domain] = result.ip;
          break;
        }
      }
    }
    return mappings;
  }

  Future<List<String>> _loadCandidates(CloudflareOptimizeConfig config) async {
    final candidates = <String>{...config.candidateIps};
    try {
      final addresses = await InternetAddress.lookup('speed.cloudflare.com');
      candidates.addAll(
        addresses
            .where((address) => address.type == InternetAddressType.IPv4)
            .map((address) => address.address),
      );
    } catch (_) {}
    if (candidates.length < config.candidateCount) {
      try {
        final response = await request.dio.get<String>(
          'https://www.cloudflare.com/ips-v4',
        );
        final ranges = const LineSplitter()
            .convert(response.data ?? '')
            .map((line) => line.trim())
            .where((line) => line.isNotEmpty)
            .toList();
        while (candidates.length < config.candidateCount && ranges.isNotEmpty) {
          for (final range in ranges) {
            final sampled = _sampleIpv4(range);
            if (sampled != null) candidates.add(sampled);
            if (candidates.length >= config.candidateCount) break;
          }
        }
      } catch (_) {}
    }
    return candidates.take(config.candidateCount).toList(growable: false);
  }

  String? _sampleIpv4(String cidr) {
    final parts = cidr.split('/');
    if (parts.length != 2) return null;
    final address = InternetAddress.tryParse(parts.first);
    final prefix = int.tryParse(parts.last);
    if (address?.type != InternetAddressType.IPv4 ||
        prefix == null ||
        prefix < 8 ||
        prefix > 31) {
      return null;
    }
    final octets = address!.rawAddress;
    final network =
        (octets[0] << 24) | (octets[1] << 16) | (octets[2] << 8) | octets[3];
    final hostCount = 1 << (32 - prefix);
    final offset = hostCount <= 2 ? 0 : 1 + _random.nextInt(hostCount - 2);
    final value = network + offset;
    return [
      (value >> 24) & 255,
      (value >> 16) & 255,
      (value >> 8) & 255,
      value & 255,
    ].join('.');
  }

  Future<_LatencyResult?> _testLatency(String ip) async {
    final samples = <Duration>[];
    for (var index = 0; index < 2; index++) {
      final stopwatch = Stopwatch()..start();
      Socket? socket;
      try {
        socket = await Socket.connect(
          ip,
          443,
          timeout: const Duration(milliseconds: 1500),
        );
        stopwatch.stop();
        samples.add(stopwatch.elapsed);
      } catch (_) {
        stopwatch.stop();
      } finally {
        await socket?.close();
      }
    }
    if (samples.isEmpty) return null;
    final averageMicroseconds =
        samples.fold<int>(
          0,
          (total, sample) => total + sample.inMicroseconds,
        ) ~/
        samples.length;
    return _LatencyResult(
      ip: ip,
      latency: Duration(microseconds: averageMicroseconds),
    );
  }

  Future<CloudflareOptimizeResult?> _testDownload(
    _LatencyResult candidate,
    int downloadBytes,
  ) async {
    Socket? socket;
    SecureSocket? secureSocket;
    StreamSubscription<List<int>>? subscription;
    Timer? timer;
    try {
      socket = await Socket.connect(
        candidate.ip,
        443,
        timeout: const Duration(seconds: 2),
      );
      secureSocket = await SecureSocket.secure(
        socket,
        host: 'speed.cloudflare.com',
        supportedProtocols: const ['http/1.1'],
      ).timeout(const Duration(seconds: 3));
      final completer = Completer<void>();
      var headerParsed = false;
      var pending = <int>[];
      var bodyBytes = 0;
      var region = '';
      final stopwatch = Stopwatch()..start();
      subscription = secureSocket.listen(
        (chunk) {
          if (!headerParsed) {
            pending = [...pending, ...chunk];
            final headerEnd = _headerEnd(pending);
            if (headerEnd < 0) return;
            final header = ascii.decode(pending.take(headerEnd).toList());
            region = _cloudflareRegion(header);
            bodyBytes += pending.length - headerEnd - 4;
            pending = const [];
            headerParsed = true;
          } else {
            bodyBytes += chunk.length;
          }
          if (bodyBytes >= downloadBytes && !completer.isCompleted) {
            completer.complete();
          }
        },
        onDone: () {
          if (!completer.isCompleted) completer.complete();
        },
        onError: (_) {
          if (!completer.isCompleted) completer.complete();
        },
        cancelOnError: true,
      );
      secureSocket.write(
        'GET /__down?bytes=$downloadBytes HTTP/1.1\r\n'
        'Host: speed.cloudflare.com\r\n'
        'Accept: */*\r\n'
        'Accept-Encoding: identity\r\n'
        'Connection: close\r\n\r\n',
      );
      await secureSocket.flush();
      timer = Timer(const Duration(seconds: 4), () {
        if (!completer.isCompleted) completer.complete();
      });
      await completer.future;
      stopwatch.stop();
      if (!headerParsed ||
          bodyBytes < 32768 ||
          stopwatch.elapsedMilliseconds == 0) {
        return null;
      }
      return CloudflareOptimizeResult(
        ip: candidate.ip,
        latency: candidate.latency,
        downloadBytesPerSecond:
            bodyBytes * 1000 / stopwatch.elapsedMilliseconds,
        region: region,
      );
    } catch (_) {
      return null;
    } finally {
      timer?.cancel();
      await subscription?.cancel();
      await secureSocket?.close();
      await socket?.close();
    }
  }

  Future<bool> _validateTarget(
    String ip,
    CloudflareOptimizeTarget target,
  ) async {
    Socket? socket;
    SecureSocket? secureSocket;
    StreamSubscription<List<int>>? subscription;
    Timer? timer;
    try {
      socket = await Socket.connect(
        ip,
        target.port,
        timeout: const Duration(seconds: 2),
      );
      secureSocket = await SecureSocket.secure(
        socket,
        host: target.domain,
        supportedProtocols: const ['http/1.1'],
      ).timeout(const Duration(seconds: 3));
      final completer = Completer<bool>();
      final response = <int>[];
      subscription = secureSocket.listen(
        (chunk) {
          response.addAll(chunk);
          final headerEnd = _headerEnd(response);
          if (headerEnd >= 0 && !completer.isCompleted) {
            final statusLine = ascii
                .decode(response.take(headerEnd).toList())
                .split('\r\n')
                .first;
            completer.complete(statusLine.startsWith('HTTP/'));
          }
        },
        onDone: () {
          if (!completer.isCompleted) completer.complete(false);
        },
        onError: (_) {
          if (!completer.isCompleted) completer.complete(false);
        },
        cancelOnError: true,
      );
      secureSocket.write(
        'HEAD /cdn-cgi/trace HTTP/1.1\r\n'
        'Host: ${target.domain}\r\n'
        'Connection: close\r\n\r\n',
      );
      await secureSocket.flush();
      timer = Timer(const Duration(seconds: 4), () {
        if (!completer.isCompleted) completer.complete(false);
      });
      return await completer.future;
    } catch (_) {
      return false;
    } finally {
      timer?.cancel();
      await subscription?.cancel();
      await secureSocket?.close();
      await socket?.close();
    }
  }
}

class _LatencyResult {
  const _LatencyResult({required this.ip, required this.latency});

  final String ip;
  final Duration latency;
}

Future<List<R>> _mapConcurrent<T, R>(
  List<T> values,
  int concurrency,
  Future<R> Function(T value) mapper,
) async {
  final results = List<R?>.filled(values.length, null);
  var nextIndex = 0;

  Future<void> worker() async {
    while (nextIndex < values.length) {
      final index = nextIndex++;
      results[index] = await mapper(values[index]);
    }
  }

  await Future.wait(
    List.generate(min(concurrency, values.length), (_) => worker()),
  );
  return results.cast<R>();
}

int _headerEnd(List<int> bytes) {
  for (var index = 0; index <= bytes.length - 4; index++) {
    if (bytes[index] == 13 &&
        bytes[index + 1] == 10 &&
        bytes[index + 2] == 13 &&
        bytes[index + 3] == 10) {
      return index;
    }
  }
  return -1;
}

String _cloudflareRegion(String header) {
  final match = RegExp(
    r'^cf-ray:\s*[^\r\n-]+-([a-z0-9]+)',
    caseSensitive: false,
    multiLine: true,
  ).firstMatch(header);
  return match?.group(1)?.toUpperCase() ?? '--';
}

int _boundedInt(Object? value, int fallback, int min, int max) {
  final parsed = switch (value) {
    final int number => number,
    final num number => number.toInt(),
    final String text => int.tryParse(text),
    _ => null,
  };
  return (parsed ?? fallback).clamp(min, max);
}

bool _validDomain(String value) {
  final uri = Uri.tryParse('https://$value');
  return value.isNotEmpty &&
      uri != null &&
      uri.host == value &&
      value.contains('.') &&
      !value.contains('..');
}

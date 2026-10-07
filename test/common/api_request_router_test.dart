import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:fl_clash/common/api_network_diagnostic.dart';
import 'package:fl_clash/common/api_request_router.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final first = Uri.parse('https://one.example.com');
  final second = Uri.parse('https://two.example.com');
  final candidates = [first, second];

  test('failure is shared across paths and candidate order', () {
    final router = ApiRequestRouter();
    expect(
      router.recordFailure(
        first.resolve('/api/v1/user/info'),
        candidates: candidates,
        error: const SocketException('Failed host lookup'),
      ),
      isTrue,
    );
    final gateways = [
      second.resolve('/api/v2/client/entry'),
      first.resolve('/api/v2/client/entry'),
    ];
    expect(router.orderCandidates(gateways).first.host, second.host);
    router.recordSuccess(gateways.first, candidates: gateways);
    expect(router.orderCandidates(candidates, preferred: first).first, second);
  });

  test(
    'cooldown expires and recovers without permanently banning an entry',
    () {
      var now = DateTime.utc(2026, 10, 7);
      final router = ApiRequestRouter(now: () => now);
      router.recordFailure(first, candidates: candidates, statusCode: 503);
      router.recordSuccess(second, candidates: candidates);
      expect(router.orderCandidates(candidates).first, second);
      now = now.add(const Duration(seconds: 15));
      expect(router.orderCandidates(candidates).first, first);
      router.recordFailure(first, candidates: candidates, statusCode: 503);
      now = now.add(const Duration(seconds: 29));
      expect(router.orderCandidates(candidates).first, second);
      now = now.add(const Duration(seconds: 1));
      expect(router.orderCandidates(candidates).first, first);
      router.recordSuccess(first, candidates: candidates);
      expect(router.orderCandidates(candidates).first, first);
    },
  );

  test('unrelated trust sets and unknown hosts cannot poison the route', () {
    final router = ApiRequestRouter();
    final other = Uri.parse('https://untrusted.example.com');
    expect(
      router.recordFailure(other, candidates: candidates, statusCode: 503),
      isFalse,
    );
    router.recordFailure(first, candidates: [first, other], statusCode: 503);
    expect(router.orderCandidates(candidates).first, first);
    expect(router.orderCandidates(candidates, preferred: other), candidates);
  });

  test(
    'only one concurrent dispatch reserves an expired entry probe',
    () async {
      var now = DateTime.utc(2026, 10, 7);
      final router = ApiRequestRouter(now: () => now);
      router.recordFailure(first, candidates: candidates, statusCode: 503);
      router.recordSuccess(second, candidates: candidates);
      now = now.add(const Duration(seconds: 15));
      final selected = await Future.wait(
        List.generate(
          20,
          (_) async => router
              .orderCandidates(candidates, reserveRecoveryProbe: true)
              .first,
        ),
      );
      expect(selected.where((endpoint) => endpoint == first), hasLength(1));
      expect(selected.where((endpoint) => endpoint == second), hasLength(19));
      router.recordFailure(first, candidates: candidates, statusCode: 503);
      expect(
        router.orderCandidates(candidates, reserveRecoveryProbe: true).first,
        second,
      );
      now = now.add(const Duration(seconds: 30));
      expect(
        router.orderCandidates(candidates, reserveRecoveryProbe: true).first,
        first,
      );
      router.recordSuccess(first, candidates: candidates);
      expect(
        router.orderCandidates(candidates, reserveRecoveryProbe: true).first,
        first,
      );
    },
  );

  test('unused probes expire and pure sorting does not reserve them', () {
    var now = DateTime.utc(2026, 10, 7);
    final router = ApiRequestRouter(now: () => now);
    router.recordFailure(first, candidates: candidates, statusCode: 504);
    now = now.add(const Duration(seconds: 15));
    expect(router.orderCandidates(candidates).first, first);
    expect(router.orderCandidates(candidates).first, first);
    expect(
      router.orderCandidates(candidates, reserveRecoveryProbe: true).first,
      first,
    );
    expect(
      router.orderCandidates(candidates, reserveRecoveryProbe: true).first,
      second,
    );
    now = now.add(const Duration(seconds: 45));
    expect(
      router.orderCandidates(candidates, reserveRecoveryProbe: true).first,
      first,
    );
  });

  test('does not expand candidates or retain URI credentials', () {
    final router = ApiRequestRouter();
    expect(
      router.orderCandidates([
        first,
        first.resolve('/duplicate'),
        Uri.parse('https://user:password@evil.example.com'),
        Uri.parse('file:///tmp/config'),
        second,
      ]),
      candidates,
    );
  });

  test(
    'terminal authentication responses release a single-entry probe lease',
    () {
      var now = DateTime.utc(2026, 10, 7);
      final router = ApiRequestRouter(now: () => now);
      router.recordFailure(first, candidates: [first], statusCode: 503);
      now = now.add(const Duration(seconds: 15));
      expect(router.orderCandidates([first], reserveRecoveryProbe: true), [
        first,
      ]);
      expect(
        router.recordFailure(first, candidates: [first], statusCode: 401),
        isFalse,
      );
      expect(router.orderCandidates([first], reserveRecoveryProbe: true), [
        first,
      ]);
      router.releaseRecoveryProbe(first, candidates: [first]);
      expect(router.orderCandidates([first], reserveRecoveryProbe: true), [
        first,
      ]);
    },
  );

  test(
    'eligibility does not change trust scope or reserve skipped entries',
    () {
      var now = DateTime.utc(2026, 10, 7);
      final router = ApiRequestRouter(now: () => now);
      router.recordFailure(first, candidates: candidates, statusCode: 503);
      now = now.add(const Duration(seconds: 15));
      expect(
        router.orderCandidates(
          candidates,
          eligibleCandidates: [second],
          reserveRecoveryProbe: true,
        ),
        [second],
      );
      expect(
        router.orderCandidates(candidates, reserveRecoveryProbe: true).first,
        first,
      );
      expect(
        router.orderCandidates(
          candidates,
          eligibleCandidates: [first],
          reserveRecoveryProbe: true,
        ),
        isEmpty,
      );
      expect(
        router.orderCandidates(
          candidates,
          eligibleCandidates: [Uri.parse('https://untrusted.example.com')],
        ),
        isEmpty,
      );
    },
  );

  test('a completed unleased request cannot release a new probe', () {
    var now = DateTime.utc(2026, 10, 7);
    final router = ApiRequestRouter(now: () => now);
    final unleasedToken = router.recoveryProbeToken(first, candidates: [first]);
    expect(unleasedToken, isNull);
    router.recordFailure(first, candidates: [first], statusCode: 503);
    now = now.add(const Duration(seconds: 15));
    expect(router.orderCandidates([first], reserveRecoveryProbe: true), [
      first,
    ]);
    final probeToken = router.recoveryProbeToken(first, candidates: [first]);
    expect(probeToken, isNotNull);
    router.recordFailure(
      first,
      candidates: [first],
      statusCode: 401,
      probeToken: unleasedToken,
    );
    router.releaseRecoveryProbe(
      first,
      candidates: [first],
      probeToken: unleasedToken,
    );
    expect(
      router.orderCandidates([first], reserveRecoveryProbe: true),
      isEmpty,
    );
    router.releaseRecoveryProbe(
      first,
      candidates: [first],
      probeToken: probeToken,
    );
    expect(router.orderCandidates([first], reserveRecoveryProbe: true), [
      first,
    ]);
  });

  test('an expired probe token cannot release a replacement probe', () {
    var now = DateTime.utc(2026, 10, 7);
    final router = ApiRequestRouter(now: () => now);
    router.recordFailure(first, candidates: [first], statusCode: 503);
    now = now.add(const Duration(seconds: 15));
    router.orderCandidates([first], reserveRecoveryProbe: true);
    final oldToken = router.recoveryProbeToken(first, candidates: [first]);
    now = now.add(const Duration(seconds: 45));
    router.orderCandidates([first], reserveRecoveryProbe: true);
    final newToken = router.recoveryProbeToken(first, candidates: [first]);
    expect(identical(oldToken, newToken), isFalse);
    router.recordFailure(
      first,
      candidates: [first],
      statusCode: 429,
      probeToken: oldToken,
    );
    expect(
      router.orderCandidates([first], reserveRecoveryProbe: true),
      isEmpty,
    );
    router.recordFailure(
      first,
      candidates: [first],
      statusCode: 429,
      probeToken: newToken,
    );
    expect(router.orderCandidates([first], reserveRecoveryProbe: true), [
      first,
    ]);
  });

  for (final status in [502, 503, 504]) {
    test('HTTP $status is a recoverable entry failure', () {
      expect(ApiRequestRouter.isRecoverableFailure(statusCode: status), isTrue);
    });
  }

  for (final status in [200, 302, 400, 401, 403, 404, 422, 429, 500]) {
    test('HTTP $status does not switch entries', () {
      expect(
        ApiRequestRouter.isRecoverableFailure(statusCode: status),
        isFalse,
      );
    });
  }

  for (final error in <Object>[
    const SocketException('Failed host lookup'),
    const SocketException('connection reset', osError: OSError('reset', 10054)),
    const SocketException(
      'connection refused',
      osError: OSError('refused', 61),
    ),
    TimeoutException('request timed out'),
    const ApiNetworkDiagnostic(
      failure: ApiNetworkFailure.dns,
      stage: 'gateway',
    ),
    DioException(
      requestOptions: RequestOptions(),
      type: DioExceptionType.receiveTimeout,
    ),
    DioException(
      requestOptions: RequestOptions(),
      error: const SocketException('reset'),
    ),
  ]) {
    test('${error.runtimeType} network failure can cool an entry', () {
      expect(ApiRequestRouter.isRecoverableFailure(error: error), isTrue);
    });
  }

  for (final error in <Object>[
    const HandshakeException('untrusted certificate'),
    const SocketException('permission denied', osError: OSError('denied', 13)),
    const FormatException('invalid_server_signature'),
    StateError('business rejection'),
    const ApiNetworkDiagnostic(
      failure: ApiNetworkFailure.tls,
      stage: 'gateway',
    ),
    const ApiNetworkDiagnostic(
      failure: ApiNetworkFailure.configSignature,
      stage: 'gateway',
    ),
    DioException(
      requestOptions: RequestOptions(),
      type: DioExceptionType.cancel,
    ),
    DioException(
      requestOptions: RequestOptions(),
      type: DioExceptionType.badCertificate,
    ),
    DioException(
      requestOptions: RequestOptions(),
      error: const FormatException('unexpected payload'),
    ),
    DioException(requestOptions: RequestOptions()),
  ]) {
    test('${error.runtimeType} security or application failure stops', () {
      expect(ApiRequestRouter.isRecoverableFailure(error: error), isFalse);
    });
  }
}

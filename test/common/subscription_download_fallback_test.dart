import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:fl_clash/common/request.dart';
import 'package:fl_clash/common/print.dart';
import 'package:fl_clash/common/xboard_api_request.dart';
import 'package:fl_clash/l10n/l10n.dart';
import 'package:fl_clash/models/profile.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => AppLocalizations.load(const Locale('en')));
  tearDown(() => commonPrint.flushDiagnosticEvents());

  for (final status in [400, 401, 403, 404, 407, 408, 429]) {
    test('HTTP $status never starts a second subscription download', () async {
      final direct = _Adapter((_) async => ResponseBody.fromString('', status));
      final backup = _Adapter((_) async => ResponseBody.fromString('ok', 200));
      final request = _request(direct, backup);
      await expectLater(
        request.getFileResponseForUrl('https://subscription.example/profile'),
        throwsA(anything),
      );
      expect(direct.calls, 1);
      expect(backup.calls, 0);
    });
  }

  for (final status in [500, 502, 503, 504]) {
    test('HTTP $status keeps the alternate subscription route', () async {
      final direct = _Adapter((_) async => ResponseBody.fromString('', status));
      final backup = _Adapter((_) async => ResponseBody.fromString('ok', 200));
      final result = await _request(
        direct,
        backup,
      ).getFileResponseForUrl('https://subscription.example/profile');
      expect(result.data, 'ok'.codeUnits);
      expect(direct.calls, 1);
      expect(backup.calls, 1);
    });
  }

  for (final type in [
    DioExceptionType.connectionTimeout,
    DioExceptionType.sendTimeout,
    DioExceptionType.receiveTimeout,
    DioExceptionType.connectionError,
  ]) {
    test('$type keeps the alternate subscription route', () async {
      final direct = _Adapter(
        (options) async =>
            throw DioException(requestOptions: options, type: type),
      );
      final backup = _Adapter((_) async => ResponseBody.fromString('ok', 200));
      await _request(
        direct,
        backup,
      ).getFileResponseForUrl('https://subscription.example/profile');
      expect(backup.calls, 1);
    });
  }

  for (final error in <Object>[
    const FormatException('invalid'),
    ArgumentError('invalid URL'),
    const HandshakeException('untrusted certificate'),
  ]) {
    test('$error does not qualify for fallback', () {
      expect(canRetrySubscriptionDownload(error), isFalse);
      expect(
        canRetrySubscriptionDownload(
          DioException(requestOptions: RequestOptions(), error: error),
        ),
        isFalse,
      );
    });
  }

  for (final type in [
    DioExceptionType.cancel,
    DioExceptionType.badCertificate,
  ]) {
    test('$type never starts the alternate transport', () async {
      final direct = _Adapter(
        (options) async =>
            throw DioException(requestOptions: options, type: type),
      );
      final backup = _Adapter((_) async => ResponseBody.fromString('ok', 200));
      await expectLater(
        _request(
          direct,
          backup,
        ).getFileResponseForUrl('https://subscription.example/profile'),
        throwsA(isA<DioException>()),
      );
      expect(backup.calls, 0);
    });
  }

  test('an invalidated direct request never starts fallback', () async {
    var current = true;
    final direct = _Adapter((_) async {
      current = false;
      return ResponseBody.fromString('', 503);
    });
    final backup = _Adapter((_) async => ResponseBody.fromString('ok', 200));
    await expectLater(
      _request(direct, backup).getFileResponseForUrl(
        'https://subscription.example/profile',
        canRequest: () => current,
      ),
      throwsA(isA<XboardApiRequestDeferred>()),
    );
    expect(direct.calls, 1);
    expect(backup.calls, 0);
  });

  test('a closed request gate starts no transport', () async {
    final direct = _Adapter((_) async => ResponseBody.fromString('ok', 200));
    final backup = _Adapter((_) async => ResponseBody.fromString('ok', 200));
    await expectLater(
      _request(direct, backup).getFileResponseForUrl(
        'https://subscription.example/profile',
        canRequest: () => false,
      ),
      throwsA(isA<XboardApiRequestDeferred>()),
    );
    expect(direct.calls, 0);
    expect(backup.calls, 0);
  });

  test('a late direct success is deferred without starting fallback', () async {
    var current = true;
    final direct = _Adapter((_) async {
      current = false;
      return ResponseBody.fromString('ok', 200);
    });
    final backup = _Adapter((_) async => ResponseBody.fromString('ok', 200));
    await expectLater(
      _request(direct, backup).getFileResponseForUrl(
        'https://subscription.example/profile',
        canRequest: () => current,
      ),
      throwsA(isA<XboardApiRequestDeferred>()),
    );
    expect(backup.calls, 0);
  });

  test(
    'profile update checks its owner before downloading or saving',
    () async {
      final profile = Profile.normal(
        url: 'https://subscription.example/profile',
      );
      await expectLater(
        profile.update(isCurrent: () => false),
        throwsA(isA<XboardApiRequestDeferred>()),
      );
      await expectLater(
        profile.update(canRequest: () => false),
        throwsA(isA<XboardApiRequestDeferred>()),
      );
    },
  );

  test('direct success does not use the alternate transport', () async {
    final direct = _Adapter((_) async => ResponseBody.fromString('ok', 200));
    final backup = _Adapter((_) async => ResponseBody.fromString('ok', 200));
    await _request(
      direct,
      backup,
    ).getFileResponseForUrl('https://subscription.example/profile');
    expect(direct.calls, 1);
    expect(backup.calls, 0);
  });

  test('wrapped DNS and raw timeouts remain recoverable', () {
    expect(
      canRetrySubscriptionDownload(
        DioException(
          requestOptions: RequestOptions(),
          error: const SocketException('DNS lookup failed'),
        ),
      ),
      isTrue,
    );
    expect(canRetrySubscriptionDownload(TimeoutException('late')), isTrue);
  });
}

Request _request(_Adapter direct, _Adapter backup) {
  final directDio = Dio()..httpClientAdapter = direct;
  final backupDio = Dio()..httpClientAdapter = backup;
  addTearDown(() {
    directDio.close(force: true);
    backupDio.close(force: true);
  });
  return Request.forTesting(directDio: directDio, clashDio: backupDio);
}

class _Adapter implements HttpClientAdapter {
  _Adapter(this.respond);
  final Future<ResponseBody> Function(RequestOptions options) respond;
  int calls = 0;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) {
    calls++;
    return respond(options);
  }

  @override
  void close({bool force = false}) {}
}

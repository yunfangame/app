import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:fl_clash/common/app_update.dart';
import 'package:fl_clash/common/app_update_download.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory temporary;
  final bytes = utf8.encode('FengWo verified installer bytes');

  AppUpdateRelease release({
    String packageKey = 'windows-x64',
    String version = '1.0.5',
    String url = 'https://downloads.example.com/FengWo.exe?token=private',
    String? checksum,
  }) => AppUpdateRelease(
    packageKey: packageKey,
    version: version,
    downloadUri: Uri.parse(url),
    releaseNotesHtml: '',
    sha256: checksum ?? sha256.convert(bytes).toString(),
  );

  AppUpdateDownloadService service({
    AppUpdateDownloadTransport? transport,
    AppUpdateInstallerLauncher? launcher,
    String packageKey = 'windows-x64',
    Dio? dio,
    int maxDownloadBytes = 1024,
  }) {
    final value = AppUpdateDownloadService(
      temporaryDirectoryLoader: () async => temporary,
      transport: transport,
      launcher: launcher ?? (_) async => true,
      packageKeyResolver: () => packageKey,
      dio: dio,
      maxDownloadBytes: maxDownloadBytes,
    );
    addTearDown(value.dispose);
    return value;
  }

  AppUpdateDownloadTransport transportFor(List<int> data, {int? totalBytes}) =>
      (_, _) async => AppUpdateDownloadResponse(
        bytes: Stream.fromIterable([
          data.sublist(0, data.length ~/ 2),
          data.sublist(data.length ~/ 2),
        ]),
        totalBytes: totalBytes,
      );

  Matcher failsWith(AppUpdateDownloadFailure failure) => throwsA(
    isA<AppUpdateDownloadException>().having(
      (error) => error.failure,
      'failure',
      failure,
    ),
  );

  Future<List<FileSystemEntity>> updateFiles() async =>
      temporary.list(recursive: true).toList();

  setUp(() async {
    temporary = await Directory.systemTemp.createTemp('fengwo-update-test-');
  });

  tearDown(() async {
    await temporary.delete(recursive: true);
  });

  test(
    'streams to a verified package before explicitly launching once',
    () async {
      final progress = <(int, int?)>[];
      final launched = <String>[];
      var verified = false;
      final downloader = service(
        transport: transportFor(bytes, totalBytes: bytes.length),
        launcher: (path) async {
          launched.add(path);
          return true;
        },
      );
      final target = release();
      final path = await downloader.download(
        target,
        onProgress: (received, total) => progress.add((received, total)),
        onVerifying: () => verified = true,
      );

      expect(await File(path).readAsBytes(), bytes);
      expect(verified, isTrue);
      expect(progress.first, (0, bytes.length));
      expect(progress.last, (bytes.length, bytes.length));
      expect(path, endsWith('.exe'));
      expect(path, isNot(contains('private')));
      expect(
        (await updateFiles()).any((file) => file.path.endsWith('.part')),
        false,
      );
      expect(launched, isEmpty);

      await downloader.install(target);
      await downloader.install(target);
      expect(launched, [path]);
    },
  );

  test('unknown length stays indeterminate until complete', () async {
    final progress = <(int, int?)>[];
    final downloader = service(transport: transportFor(bytes));
    await downloader.download(
      release(),
      onProgress: (received, total) => progress.add((received, total)),
    );
    expect(progress.first, (0, null));
    expect(progress.last, (bytes.length, bytes.length));
  });

  test('macOS package uses generated safe filename', () async {
    final downloader = service(
      transport: transportFor(bytes),
      packageKey: 'macos-arm64',
    );
    final path = await downloader.download(
      release(
        packageKey: 'macos-arm64',
        version: '../../1.0.5',
        url: 'https://example.com/path/%2e%2e/FengWo.pkg?filename=other.exe',
      ),
    );
    expect(p.isWithin(temporary.path, path), isTrue);
    expect(p.basename(path), startsWith('FengWo-.._.._1.0.5-'));
    expect(p.extension(path), '.pkg');
  });

  test('Android APK is verified and opened only on explicit install', () async {
    var launches = 0;
    final downloader = service(
      packageKey: 'android-arm64-v8a',
      transport: transportFor(bytes),
      launcher: (_) async {
        launches++;
        return true;
      },
    );
    final target = release(
      packageKey: 'android-arm64-v8a',
      url: 'https://example.com/FengWo.apk',
    );
    final path = await downloader.download(target);
    expect(p.extension(path), '.apk');
    expect(await File(path).readAsBytes(), bytes);
    expect(launches, 0);
    await downloader.install(target);
    expect(launches, 1);
  });

  test('Android rejects desktop installer even with valid checksum', () async {
    final downloader = service(
      packageKey: 'android-arm64-v8a',
      transport: transportFor(bytes),
    );
    await expectLater(
      downloader.download(release(packageKey: 'android-arm64-v8a')),
      failsWith(AppUpdateDownloadFailure.unsupportedPackage),
    );
  });

  for (final checksum in ['', 'not-a-checksum', 'a' * 63, 'z' * 64]) {
    test('rejects invalid checksum before network: $checksum', () async {
      var requests = 0;
      final downloader = service(
        transport: (_, _) async {
          requests++;
          return AppUpdateDownloadResponse(bytes: Stream.value(bytes));
        },
      );
      await expectLater(
        downloader.download(release(checksum: checksum)),
        failsWith(AppUpdateDownloadFailure.missingChecksum),
      );
      expect(requests, 0);
      expect(await updateFiles(), isEmpty);
    });
  }

  test('missing checksum cannot launch an installer', () async {
    final downloader = service(transport: transportFor(bytes));
    final target = AppUpdateRelease(
      packageKey: 'windows-x64',
      version: '1.0.5',
      downloadUri: _unusedUri,
      releaseNotesHtml: '',
    );
    await expectLater(
      downloader.download(target),
      failsWith(AppUpdateDownloadFailure.missingChecksum),
    );
    await expectLater(
      downloader.install(target),
      failsWith(AppUpdateDownloadFailure.missingChecksum),
    );
  });

  test(
    'checksum failure removes own package and retains other files',
    () async {
      final unrelated = File(p.join(temporary.path, 'keep.txt'));
      await unrelated.writeAsString('keep');
      final downloader = service(transport: transportFor(bytes));
      await expectLater(
        downloader.download(release(checksum: '0' * 64)),
        failsWith(AppUpdateDownloadFailure.checksumMismatch),
      );
      expect(await unrelated.readAsString(), 'keep');
      expect((await updateFiles()).whereType<File>().length, 1);
    },
  );

  for (final entry in <String, (List<int>, int?)>{
    'empty': ([], null),
    'zero content length': ([], 0),
    'truncated': (bytes.sublist(0, 3), bytes.length),
    'longer than content length': (bytes, 2),
    'oversized known content': (bytes, 2048),
    'oversized unknown content': (List.filled(2048, 1), null),
  }.entries) {
    test('rejects ${entry.key} response', () async {
      final downloader = service(
        transport: transportFor(entry.value.$1, totalBytes: entry.value.$2),
      );
      await expectLater(
        downloader.download(release()),
        failsWith(AppUpdateDownloadFailure.downloadFailed),
      );
      expect((await updateFiles()).whereType<File>(), isEmpty);
    });
  }

  test(
    'cancellation interrupts waiting stream and cleans partial files',
    () async {
      final stream = StreamController<List<int>>();
      final started = Completer<void>();
      final downloader = service(
        transport: (_, _) async =>
            AppUpdateDownloadResponse(bytes: stream.stream),
      );
      final download = downloader.download(
        release(),
        onProgress: (_, _) {
          if (!started.isCompleted) started.complete();
        },
      );
      final failure = expectLater(
        download,
        throwsA(isA<AppUpdateDownloadCancelled>()),
      );
      await started.future;
      stream.add(bytes.sublist(0, 3));
      downloader.cancel();
      await failure;
      await stream.close();
      expect((await updateFiles()).whereType<File>(), isEmpty);
    },
  );

  test('cancellation during checksum verification never finalizes', () async {
    final downloader = service(transport: transportFor(bytes));
    await expectLater(
      downloader.download(release(), onVerifying: downloader.cancel),
      throwsA(isA<AppUpdateDownloadCancelled>()),
    );
    expect((await updateFiles()).whereType<File>(), isEmpty);
  });

  test('network failure cleans partial and retry succeeds', () async {
    var attempts = 0;
    final downloader = service(
      transport: (_, _) async => AppUpdateDownloadResponse(
        bytes: attempts++ == 0
            ? Stream.error(const SocketException('private-url-must-not-leak'))
            : Stream.value(bytes),
      ),
    );
    await expectLater(
      downloader.download(release()),
      failsWith(AppUpdateDownloadFailure.downloadFailed),
    );
    expect((await updateFiles()).whereType<File>(), isEmpty);
    final path = await downloader.download(release());
    expect(await File(path).readAsBytes(), bytes);
  });

  for (final invalid in [
    release(url: 'http://example.com/FengWo.exe'),
    release(url: 'https://user:pass@example.com/FengWo.exe'),
    release(url: 'https://example.com/FengWo.zip'),
    release(packageKey: 'windows-arm64'),
    release(packageKey: 'android-arm64-v8a'),
    release(url: 'https://example.com/FengWo.pkg'),
  ]) {
    test('rejects unsupported package ${invalid.downloadUri}', () async {
      final downloader = service(transport: transportFor(bytes));
      await expectLater(
        downloader.download(invalid),
        failsWith(AppUpdateDownloadFailure.unsupportedPackage),
      );
    });
  }

  test('HTTPS redirects may change host but cannot downgrade', () async {
    final requests = <Uri>[];
    final dio = Dio()
      ..httpClientAdapter = _ResponseAdapter((request) {
        requests.add(request.uri);
        return ResponseBody.fromBytes(
          [],
          302,
          headers: {
            HttpHeaders.locationHeader: ['http://example.com/FengWo.exe'],
          },
        );
      });
    addTearDown(() => dio.close(force: true));
    final downloader = service(dio: dio);
    await expectLater(
      downloader.download(release()),
      failsWith(AppUpdateDownloadFailure.downloadFailed),
    );
    expect(requests.length, 1);
    expect(requests.single.scheme, 'https');
  });

  test('follows HTTPS download redirects and hashes final bytes', () async {
    final requests = <Uri>[];
    final dio = Dio()
      ..httpClientAdapter = _ResponseAdapter((request) {
        requests.add(request.uri);
        if (requests.length == 1) {
          return ResponseBody.fromBytes(
            [],
            302,
            headers: {
              HttpHeaders.locationHeader: ['https://cdn.example.com/asset'],
            },
          );
        }
        return ResponseBody.fromBytes(
          bytes,
          200,
          headers: {
            HttpHeaders.contentLengthHeader: ['${bytes.length}'],
          },
        );
      });
    addTearDown(() => dio.close(force: true));
    final downloader = service(dio: dio);
    final path = await downloader.download(release());
    expect(requests.length, 2);
    expect(requests.last.host, 'cdn.example.com');
    expect(await File(path).readAsBytes(), bytes);
  });

  test(
    'rechecks cached bytes before launching and deletes tampered file',
    () async {
      var launches = 0;
      final downloader = service(
        transport: transportFor(bytes),
        launcher: (_) async {
          launches++;
          return true;
        },
      );
      final target = release();
      final path = await downloader.download(target);
      await File(path).writeAsString('tampered');
      await expectLater(
        downloader.install(target),
        failsWith(AppUpdateDownloadFailure.checksumMismatch),
      );
      expect(launches, 0);
      expect(await File(path).exists(), false);
    },
  );

  test('launcher rejection is retryable with no duplicate launch', () async {
    var launches = 0;
    final downloader = service(
      transport: transportFor(bytes),
      launcher: (_) async => ++launches > 1,
    );
    final target = release();
    final path = await downloader.download(target);
    await expectLater(
      downloader.install(target),
      failsWith(AppUpdateDownloadFailure.launchFailed),
    );
    expect(await File(path).exists(), true);
    await downloader.install(target);
    await downloader.install(target);
    expect(launches, 2);
  });

  test('cannot launch package for a different release', () async {
    final downloader = service(transport: transportFor(bytes));
    await downloader.download(release());
    await expectLater(
      downloader.install(release(version: '1.0.6')),
      failsWith(AppUpdateDownloadFailure.launchFailed),
    );
  });
}

final _unusedUri = Uri.parse('https://example.com/FengWo.exe');

class _ResponseAdapter implements HttpClientAdapter {
  _ResponseAdapter(this.respond);

  final ResponseBody Function(RequestOptions options) respond;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async => respond(options);

  @override
  void close({bool force = false}) {}
}

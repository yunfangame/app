import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:fl_clash/plugins/app.dart' show App, AppUpdateInstallResult;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

import 'app_update.dart';

enum AppUpdateDownloadStatus {
  idle,
  downloading,
  verifying,
  ready,
  cancelled,
  failed,
  installing,
}

enum AppUpdateDownloadFailure {
  missingChecksum,
  checksumMismatch,
  downloadFailed,
  launchFailed,
  unsupportedPackage,
  installPermissionRequired,
  installCancelled,
}

class AppUpdateDownloadException implements Exception {
  const AppUpdateDownloadException(this.failure);

  final AppUpdateDownloadFailure failure;

  @override
  String toString() => 'AppUpdateDownloadException(${failure.name})';
}

class AppUpdateDownloadCancelled implements Exception {
  const AppUpdateDownloadCancelled();
}

class AppUpdateDownloadState {
  const AppUpdateDownloadState({
    this.status = AppUpdateDownloadStatus.idle,
    this.release,
    this.receivedBytes = 0,
    this.totalBytes,
    this.filePath,
    this.failure,
    this.installerLaunched = false,
  });

  final AppUpdateDownloadStatus status;
  final AppUpdateRelease? release;
  final int receivedBytes;
  final int? totalBytes;
  final String? filePath;
  final AppUpdateDownloadFailure? failure;
  final bool installerLaunched;

  double? get progress => totalBytes == null || totalBytes! <= 0
      ? null
      : (receivedBytes / totalBytes!).clamp(0.0, 1.0);

  bool get isBusy =>
      status == AppUpdateDownloadStatus.downloading ||
      status == AppUpdateDownloadStatus.verifying ||
      status == AppUpdateDownloadStatus.installing;
}

class AppUpdateDownloadResponse {
  const AppUpdateDownloadResponse({required this.bytes, this.totalBytes});

  final Stream<List<int>> bytes;
  final int? totalBytes;
}

typedef AppUpdateDownloadTransport =
    Future<AppUpdateDownloadResponse> Function(
      Uri uri,
      CancelToken cancelToken,
    );
typedef AppUpdateInstallerLauncher = Future<bool> Function(String filePath);
typedef AppUpdateDownloadProgress =
    void Function(int receivedBytes, int? totalBytes);

class AppUpdateDownloadService {
  AppUpdateDownloadService({
    Future<Directory> Function()? temporaryDirectoryLoader,
    AppUpdateDownloadTransport? transport,
    AppUpdateInstallerLauncher? launcher,
    AppUpdatePackageKeyResolver? packageKeyResolver,
    Dio? dio,
    this.maxDownloadBytes = 2 * 1024 * 1024 * 1024,
  }) : _temporaryDirectoryLoader =
           temporaryDirectoryLoader ?? getTemporaryDirectory,
       _transport = transport,
       _launcher = launcher ?? _launchInstaller,
       _packageKeyResolver = packageKeyResolver ?? currentAppUpdatePackageKey,
       _dio =
           dio ??
           Dio(
             BaseOptions(
               connectTimeout: const Duration(seconds: 15),
               receiveTimeout: const Duration(seconds: 30),
             ),
           ),
       _ownsDio = dio == null;

  final Future<Directory> Function() _temporaryDirectoryLoader;
  final AppUpdateDownloadTransport? _transport;
  final AppUpdateInstallerLauncher _launcher;
  final AppUpdatePackageKeyResolver _packageKeyResolver;
  final Dio _dio;
  final bool _ownsDio;
  final int maxDownloadBytes;
  final Set<String> _ownedDirectories = {};
  CancelToken? _cancelToken;
  _DownloadedInstaller? _ready;
  bool _busy = false;
  bool _disposed = false;

  Future<String> download(
    AppUpdateRelease release, {
    AppUpdateDownloadProgress? onProgress,
    void Function()? onVerifying,
  }) async {
    if (_busy || _disposed) {
      throw const AppUpdateDownloadException(
        AppUpdateDownloadFailure.downloadFailed,
      );
    }
    final checksum = _checksum(release);
    final extension = _packageExtension(release);
    _busy = true;
    final token = _cancelToken = CancelToken();
    Directory? directory;
    RandomAccessFile? output;
    StreamIterator<List<int>>? input;
    try {
      final previous = _ready;
      _ready = null;
      if (previous != null && !previous.launched) {
        await _cleanDirectory(previous.directory);
      }
      final temporary = await _temporaryDirectoryLoader();
      _checkCancelled(token);
      final root = Directory(p.join(temporary.path, 'fengwo-app-updates'));
      if (await FileSystemEntity.type(root.path, followLinks: false) ==
          FileSystemEntityType.link) {
        throw const AppUpdateDownloadException(
          AppUpdateDownloadFailure.downloadFailed,
        );
      }
      await root.create(recursive: true);
      directory = await root.createTemp('download-');
      _ownedDirectories.add(directory.path);
      _checkCancelled(token);
      final safeVersion = release.version
          .replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_')
          .split('')
          .take(64)
          .join();
      final name = 'FengWo-$safeVersion-${checksum.substring(0, 12)}$extension';
      final partial = File(p.join(directory.path, '$name.part'));
      final completed = File(p.join(directory.path, name));
      final response = await (_transport ?? _openDownload)(
        release.downloadUri,
        token,
      );
      if (token.isCancelled || _disposed) {
        await response.bytes.listen(null).cancel();
        throw const AppUpdateDownloadCancelled();
      }
      final total = response.totalBytes;
      if (total != null && (total <= 0 || total > maxDownloadBytes)) {
        await response.bytes.listen(null).cancel();
        throw const AppUpdateDownloadException(
          AppUpdateDownloadFailure.downloadFailed,
        );
      }
      final iterator = input = StreamIterator(response.bytes);
      unawaited(token.whenCancel.then((_) => iterator.cancel()));
      var received = 0;
      final progressClock = Stopwatch()..start();
      onProgress?.call(received, total);
      var hasBytes = await iterator.moveNext();
      _checkCancelled(token);
      output = await partial.open(mode: FileMode.write);
      while (hasBytes) {
        _checkCancelled(token);
        final bytes = iterator.current;
        received += bytes.length;
        if (received > maxDownloadBytes ||
            (total != null && received > total)) {
          throw const AppUpdateDownloadException(
            AppUpdateDownloadFailure.downloadFailed,
          );
        }
        await output.writeFrom(bytes);
        if (progressClock.elapsedMilliseconds >= 100 || received == total) {
          onProgress?.call(received, total);
          progressClock.reset();
        }
        hasBytes = await iterator.moveNext();
      }
      await output.flush();
      await output.close();
      output = null;
      _checkCancelled(token);
      if (received == 0 || (total != null && received != total)) {
        throw const AppUpdateDownloadException(
          AppUpdateDownloadFailure.downloadFailed,
        );
      }
      onProgress?.call(received, total ?? received);
      onVerifying?.call();
      await _verify(partial, checksum, token);
      _checkCancelled(token);
      await partial.rename(completed.path);
      _checkCancelled(token);
      _ready = _DownloadedInstaller(
        release: release,
        file: completed,
        directory: directory,
        checksum: checksum,
      );
      return completed.path;
    } catch (error) {
      await input?.cancel();
      await output?.close();
      if (directory != null) await _cleanDirectory(directory);
      if (token.isCancelled || error is AppUpdateDownloadCancelled) {
        throw const AppUpdateDownloadCancelled();
      }
      if (error is AppUpdateDownloadException) rethrow;
      throw const AppUpdateDownloadException(
        AppUpdateDownloadFailure.downloadFailed,
      );
    } finally {
      await input?.cancel();
      _cancelToken = null;
      _busy = false;
    }
  }

  void cancel() => _cancelToken?.cancel();

  Future<void> install(
    AppUpdateRelease release, {
    void Function()? onVerified,
  }) async {
    if (_busy || _disposed) return;
    final checksum = _checksum(release);
    _packageExtension(release);
    final ready = _ready;
    if (ready == null ||
        ready.checksum != checksum ||
        ready.release.packageKey != release.packageKey ||
        ready.release.version != release.version ||
        ready.release.downloadUri != release.downloadUri) {
      throw const AppUpdateDownloadException(
        AppUpdateDownloadFailure.launchFailed,
      );
    }
    if (ready.launched) return;
    _busy = true;
    final token = _cancelToken = CancelToken();
    try {
      await _verify(ready.file, checksum, token);
      _checkCancelled(token);
      onVerified?.call();
      _checkCancelled(token);
      if (!await _launcher(ready.file.path)) {
        throw const AppUpdateDownloadException(
          AppUpdateDownloadFailure.launchFailed,
        );
      }
      ready.launched = true;
    } catch (error) {
      if (token.isCancelled || error is AppUpdateDownloadCancelled) {
        throw const AppUpdateDownloadCancelled();
      }
      if (error is AppUpdateDownloadException) {
        if (error.failure == AppUpdateDownloadFailure.checksumMismatch) {
          _ready = null;
          await _cleanDirectory(ready.directory);
        }
        rethrow;
      }
      throw const AppUpdateDownloadException(
        AppUpdateDownloadFailure.launchFailed,
      );
    } finally {
      _cancelToken = null;
      _busy = false;
    }
  }

  void dispose() {
    _disposed = true;
    cancel();
    if (_ownsDio) _dio.close(force: true);
  }

  String _checksum(AppUpdateRelease release) {
    final value = release.sha256?.trim().toLowerCase();
    if (value == null || !RegExp(r'^[0-9a-f]{64}$').hasMatch(value)) {
      throw const AppUpdateDownloadException(
        AppUpdateDownloadFailure.missingChecksum,
      );
    }
    return value;
  }

  String _packageExtension(AppUpdateRelease release) {
    final uri = release.downloadUri;
    final extension = p.posix.extension(uri.path).toLowerCase();
    final supported =
        release.packageKey == _packageKeyResolver() &&
        ((release.packageKey.startsWith('windows-') && extension == '.exe') ||
            (release.packageKey.startsWith('macos-') && extension == '.pkg') ||
            (release.packageKey.startsWith('android-') && extension == '.apk'));
    if (!supported ||
        uri.scheme != 'https' ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty) {
      throw const AppUpdateDownloadException(
        AppUpdateDownloadFailure.unsupportedPackage,
      );
    }
    return extension;
  }

  Future<AppUpdateDownloadResponse> _openDownload(
    Uri uri,
    CancelToken token,
  ) async {
    var current = uri;
    for (var redirects = 0; redirects <= 5; redirects++) {
      _checkCancelled(token);
      if (current.scheme != 'https' ||
          current.host.isEmpty ||
          current.userInfo.isNotEmpty) {
        throw const AppUpdateDownloadException(
          AppUpdateDownloadFailure.downloadFailed,
        );
      }
      final response = await _dio.getUri<ResponseBody>(
        current,
        cancelToken: token,
        options: Options(
          responseType: ResponseType.stream,
          followRedirects: false,
          validateStatus: (_) => true,
          headers: {HttpHeaders.acceptEncodingHeader: 'identity'},
        ),
      );
      final body = response.data;
      if (body == null) {
        throw const AppUpdateDownloadException(
          AppUpdateDownloadFailure.downloadFailed,
        );
      }
      if ({301, 302, 303, 307, 308}.contains(response.statusCode)) {
        await body.stream.listen(null).cancel();
        final location = response.headers.value(HttpHeaders.locationHeader);
        if (location == null) break;
        current = current.resolve(location);
        continue;
      }
      if (response.statusCode != 200) {
        await body.stream.listen(null).cancel();
        break;
      }
      final length = response.headers.value(HttpHeaders.contentLengthHeader);
      final total = length == null ? null : int.tryParse(length);
      if (length != null && total == null) {
        await body.stream.listen(null).cancel();
        break;
      }
      return AppUpdateDownloadResponse(bytes: body.stream, totalBytes: total);
    }
    throw const AppUpdateDownloadException(
      AppUpdateDownloadFailure.downloadFailed,
    );
  }

  Future<void> _verify(File file, String checksum, CancelToken token) async {
    try {
      if (await FileSystemEntity.type(file.path, followLinks: false) !=
          FileSystemEntityType.file) {
        throw const AppUpdateDownloadException(
          AppUpdateDownloadFailure.checksumMismatch,
        );
      }
      final length = await file.length();
      if (length <= 0 || length > maxDownloadBytes) {
        throw const AppUpdateDownloadException(
          AppUpdateDownloadFailure.checksumMismatch,
        );
      }
      final digest = await sha256
          .bind(
            file.openRead().map((bytes) {
              _checkCancelled(token);
              return bytes;
            }),
          )
          .first;
      _checkCancelled(token);
      if (digest.toString() != checksum) {
        throw const AppUpdateDownloadException(
          AppUpdateDownloadFailure.checksumMismatch,
        );
      }
    } on FileSystemException {
      throw const AppUpdateDownloadException(
        AppUpdateDownloadFailure.checksumMismatch,
      );
    }
  }

  void _checkCancelled(CancelToken token) {
    if (token.isCancelled || _disposed) {
      throw const AppUpdateDownloadCancelled();
    }
  }

  Future<void> _cleanDirectory(Directory directory) async {
    if (!_ownedDirectories.remove(directory.path)) return;
    try {
      if (await directory.exists()) await directory.delete(recursive: true);
    } on FileSystemException {
      return;
    }
  }

  static Future<bool> _launchInstaller(String filePath) async {
    if (Platform.isAndroid) {
      return switch (await App().installUpdate(filePath)) {
        AppUpdateInstallResult.opened => true,
        AppUpdateInstallResult.permissionRequired =>
          throw const AppUpdateDownloadException(
            AppUpdateDownloadFailure.installPermissionRequired,
          ),
        AppUpdateInstallResult.invalidPackage =>
          throw const AppUpdateDownloadException(
            AppUpdateDownloadFailure.unsupportedPackage,
          ),
        AppUpdateInstallResult.cancelled =>
          throw const AppUpdateDownloadException(
            AppUpdateDownloadFailure.installCancelled,
          ),
        AppUpdateInstallResult.failed => false,
      };
    }
    if (Platform.isWindows) {
      return launchUrl(
        Uri.file(filePath, windows: true),
        mode: LaunchMode.externalApplication,
      );
    }
    if (Platform.isMacOS) {
      final result = await Process.run('/usr/bin/open', [filePath]);
      return result.exitCode == 0;
    }
    return false;
  }
}

class _DownloadedInstaller {
  _DownloadedInstaller({
    required this.release,
    required this.file,
    required this.directory,
    required this.checksum,
  });

  final AppUpdateRelease release;
  final File file;
  final Directory directory;
  final String checksum;
  bool launched = false;
}

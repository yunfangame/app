import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api_health.dart';
import 'android_update_transport.dart';
import 'api_network_diagnostic.dart';
import 'constant.dart';
import 'remote_config_cipher.dart';

const appUpdateManifestFormat = 'fengwo-update';
const appUpdateManifestVersion = 1;
const appUpdateUrlConfigKey = 'UpdateUrl';
const appUpdateTrustedManifestUrls = [
  'https://house.zryc.tech/fengwoupdate.json',
  'https://zryc.oss-cn-beijing.aliyuncs.com/fengwoupdate.json',
];

typedef AppUpdateMainConfigLoader = Future<Object?> Function();
typedef AppUpdateManifestLoader = Future<Object?> Function(Uri uri);
typedef AppUpdatePackageKeyResolver = String? Function();

class AppUpdateRelease {
  const AppUpdateRelease({
    required this.packageKey,
    required this.version,
    required this.downloadUri,
    required this.releaseNotesHtml,
    this.title,
    this.publishedAt,
    this.sha256,
  });

  final String packageKey;
  final String version;
  final Uri downloadUri;
  final String releaseNotesHtml;
  final String? title;
  final DateTime? publishedAt;
  final String? sha256;
}

enum AppUpdateCheckStatus { available, upToDate, unavailable }

class AppUpdateCheckResult {
  const AppUpdateCheckResult({required this.status, this.release});

  final AppUpdateCheckStatus status;
  final AppUpdateRelease? release;
}

class AppUpdateUnavailableException implements Exception {
  const AppUpdateUnavailableException();
}

class AppUpdateCheckDeferred implements Exception {
  const AppUpdateCheckDeferred();
}

class AppUpdatePreferenceStore {
  AppUpdatePreferenceStore({
    Future<SharedPreferences> Function()? preferencesLoader,
  }) : _preferencesLoader = preferencesLoader ?? SharedPreferences.getInstance;

  static const _keyPrefix = 'fengwo.update.ignored_version.';

  final Future<SharedPreferences> Function() _preferencesLoader;

  Future<bool> isIgnored(String packageKey, String version) async {
    final preferences = await _preferencesLoader();
    return preferences.getString('$_keyPrefix$packageKey') == version;
  }

  Future<void> ignore(String packageKey, String version) async {
    final preferences = await _preferencesLoader();
    await preferences.setString('$_keyPrefix$packageKey', version);
  }
}

class AppUpdateService {
  AppUpdateService({
    AppUpdateMainConfigLoader? mainConfigLoader,
    ApiHealthService? apiHealthService,
    AppUpdateManifestLoader? manifestLoader,
    AppUpdatePackageKeyResolver? packageKeyResolver,
    AppUpdatePreferenceStore? preferenceStore,
    ApiDiagnosticRecorder? diagnosticRecorder,
    Dio? dio,
    AndroidUpdateTransport? androidTransport,
    this.attemptTimeout = const Duration(seconds: 8),
    this.retryDelay = const Duration(milliseconds: 300),
    this.aesKey = remoteConfigAesKey,
    this.signingPublicKey = remoteConfigSigningPublicKey,
  }) : _mainConfigLoader = mainConfigLoader,
       _apiHealthService = apiHealthService,
       _manifestLoader = manifestLoader,
       _packageKeyResolver = packageKeyResolver ?? currentAppUpdatePackageKey,
       _preferenceStore = preferenceStore ?? AppUpdatePreferenceStore(),
       _diagnosticRecorder = diagnosticRecorder ?? recordApiDiagnosticEvent,
       _dio = dio ?? _createDirectUpdateDio(),
       _androidTransport =
           androidTransport ??
           (Platform.isAndroid ? AndroidUpdateTransport() : null);

  final AppUpdateMainConfigLoader? _mainConfigLoader;
  final ApiHealthService? _apiHealthService;
  ApiHealthService? _defaultConfigService;
  final AndroidUpdateTransport? _androidTransport;
  String get _transport =>
      _androidTransport == null ? 'direct_http' : 'android_underlying_network';
  final AppUpdateManifestLoader? _manifestLoader;
  final AppUpdatePackageKeyResolver _packageKeyResolver;
  final AppUpdatePreferenceStore _preferenceStore;
  final ApiDiagnosticRecorder _diagnosticRecorder;
  final Dio _dio;
  final Duration attemptTimeout;
  final Duration retryDelay;
  final String aesKey;
  final String signingPublicKey;
  bool _closed = false;
  static int _refreshSequence = 0;

  Future<AppUpdateCheckResult> discoverUpdate({
    required String currentVersion,
    bool forceRefresh = false,
    bool Function()? canFetch,
  }) async {
    final checkId = newApiDiagnosticAttemptId();
    final watch = Stopwatch()..start();
    var stage = 'main_config';
    _record('app.update.check.started', {
      'check_id': checkId,
      'transport': _transport,
      'current_version': currentVersion,
    });
    try {
      _ensureCanFetch(canFetch);
      final packageKey = _packageKeyResolver();
      if (packageKey == null) throw const AppUpdateUnavailableException();
      final mainConfig =
          await (_mainConfigLoader?.call() ??
              _loadMainConfig(forceRefresh: forceRefresh));
      _ensureCanFetch(canFetch);
      final manifestUris = appUpdateManifestUrisFromConfig(mainConfig);
      if (manifestUris.isEmpty) {
        throw const AppUpdateUnavailableException();
      }
      _record('app.update.config.succeeded', {
        'check_id': checkId,
        'source_count': manifestUris.length,
        'package_key': packageKey,
        'elapsed_ms': watch.elapsedMilliseconds,
      });
      stage = 'update_manifest';
      final release = await _loadRelease(
        manifestUris,
        packageKey,
        checkId,
        canFetch: canFetch,
        refreshNonce: forceRefresh
            ? '${DateTime.now().microsecondsSinceEpoch}-${++_refreshSequence}'
            : null,
      );
      final result = release == null
          ? const AppUpdateCheckResult(status: AppUpdateCheckStatus.unavailable)
          : compareAppUpdateVersions(release.version, currentVersion) <= 0
          ? const AppUpdateCheckResult(status: AppUpdateCheckStatus.upToDate)
          : AppUpdateCheckResult(
              status: AppUpdateCheckStatus.available,
              release: release,
            );
      _record('app.update.check.completed', {
        'check_id': checkId,
        'status': result.status.name,
        'package_key': packageKey,
        if (release != null) 'remote_version': release.version,
        'elapsed_ms': watch.elapsedMilliseconds,
      });
      return result;
    } on AppUpdateCheckDeferred {
      _record('app.update.check.deferred', {'check_id': checkId});
      rethrow;
    } catch (error) {
      _record('app.update.check.failed', {
        'check_id': checkId,
        ..._updateFailureFields(error, stage: stage),
        'elapsed_ms': watch.elapsedMilliseconds,
      });
      rethrow;
    } finally {
      watch.stop();
    }
  }

  Future<AppUpdateRelease?> checkForUpdate({
    required String currentVersion,
    bool respectIgnored = true,
    bool forceRefresh = true,
  }) async {
    final result = await discoverUpdate(
      currentVersion: currentVersion,
      forceRefresh: forceRefresh,
    );
    final release = result.release;
    if (release != null && respectIgnored && await isIgnored(release)) {
      return null;
    }
    return release;
  }

  Future<bool> isIgnored(AppUpdateRelease release) =>
      _preferenceStore.isIgnored(release.packageKey, release.version);

  void close() {
    _closed = true;
    _dio.close(force: true);
    _androidTransport?.close();
  }

  Future<Object?> _loadMainConfig({required bool forceRefresh}) =>
      (_apiHealthService ??
              (_defaultConfigService ??= ApiHealthService(
                configLoader: _androidTransport == null
                    ? null
                    : (uri) => _androidTransport.load(uri, kind: 'main_config'),
                diagnosticRecorder: _diagnosticRecorder,
              )))
          .loadConfig(forceRefresh: forceRefresh);

  Future<void> ignore(AppUpdateRelease release) =>
      _preferenceStore.ignore(release.packageKey, release.version);

  void _record(String event, Map<String, Object?> fields) =>
      emitApiDiagnosticEvent(_diagnosticRecorder, event, fields);

  void _ensureCanFetch(bool Function()? canFetch) {
    if (_closed) throw StateError('Update service is closed');
    if (canFetch?.call() == false) throw const AppUpdateCheckDeferred();
  }

  Future<AppUpdateRelease?> _loadRelease(
    List<Uri> uris,
    String packageKey,
    String checkId, {
    bool Function()? canFetch,
    String? refreshNonce,
  }) async {
    final retryable = uris.toSet();
    Object? selectedError;
    StackTrace? selectedStack;
    for (var round = 0; round < 2 && retryable.isNotEmpty; round++) {
      if (round > 0) {
        _record('app.update.retry.scheduled', {
          'check_id': checkId,
          'round': round + 1,
          'delay_ms': retryDelay.inMilliseconds,
        });
        if (retryDelay > Duration.zero) await Future<void>.delayed(retryDelay);
      }
      for (var index = 0; index < uris.length; index++) {
        _ensureCanFetch(canFetch);
        final uri = uris[index];
        if (!retryable.contains(uri)) continue;
        final fields = {
          'check_id': checkId,
          'source_index': index + 1,
          'endpoint_ref': apiDiagnosticEndpointRef(uri),
          'round': round + 1,
          'transport': _transport,
        };
        if (index > 0) _record('app.update.source.fallback', fields);
        _record('app.update.source.attempt.started', fields);
        final watch = Stopwatch()..start();
        final cancelToken = CancelToken();
        var stage = 'manifest_fetch';
        try {
          final requestUri = refreshNonce == null
              ? uri
              : uri.replace(
                  queryParameters: {
                    ...uri.queryParametersAll,
                    '_fengwo_update_refresh': refreshNonce,
                  },
                );
          final release = await (() async {
            final payload = _manifestLoader != null
                ? await _manifestLoader(requestUri)
                : await _loadManifest(requestUri, cancelToken);
            stage = 'manifest_decode';
            final decoded = await _decodeManifest(payload);
            stage = 'manifest_parse';
            return parseAppUpdateRelease(
              decoded,
              packageKey: packageKey,
              manifestUri: uri,
            );
          })().timeout(attemptTimeout);
          _record('app.update.source.attempt.succeeded', {
            ...fields,
            'stage': stage,
            'elapsed_ms': watch.elapsedMilliseconds,
          });
          return release;
        } catch (error, stack) {
          _record('app.update.source.attempt.failed', {
            ...fields,
            ..._updateFailureFields(error, stage: stage),
            'elapsed_ms': watch.elapsedMilliseconds,
          });
          if (selectedError == null ||
              _updateFailurePriority(error) >
                  _updateFailurePriority(selectedError)) {
            selectedError = error;
            selectedStack = stack;
          }
          if (!_isRetryableUpdateFailure(error)) retryable.remove(uri);
        } finally {
          cancelToken.cancel('Update source attempt finished');
          watch.stop();
        }
      }
    }
    Error.throwWithStackTrace(selectedError!, selectedStack!);
  }

  Future<Object?> _loadManifest(Uri uri, CancelToken cancelToken) async {
    if (_androidTransport != null) {
      return _androidTransport.load(uri, cancelToken: cancelToken);
    }
    final response = await _dio.getUri<List<int>>(
      uri,
      cancelToken: cancelToken,
      options: Options(
        responseType: ResponseType.bytes,
        followRedirects: false,
        headers: const {'Cache-Control': 'no-cache', 'Pragma': 'no-cache'},
        validateStatus: (status) =>
            status != null && status >= 200 && status < 300,
      ),
    );
    final bytes = response.data;
    if (bytes == null || bytes.isEmpty) {
      throw const FormatException('Empty update manifest');
    }
    return utf8.decode(bytes);
  }

  Future<Object?> _decodeManifest(Object? payload) async {
    final normalized = _decodeJsonPayload(payload);
    if (_isEncryptedEnvelope(normalized)) {
      if (aesKey.isEmpty || signingPublicKey.isEmpty) {
        throw const FormatException('Update manifest keys are unavailable');
      }
      return decodeEncryptedRemoteConfig(
        normalized,
        aesKey: aesKey,
        signingPublicKey: signingPublicKey,
      );
    }
    if (aesKey.isNotEmpty || signingPublicKey.isNotEmpty) {
      throw const FormatException('Unsigned update manifest rejected');
    }
    return normalized;
  }
}

Dio _createDirectUpdateDio() {
  final dio = Dio(
    BaseOptions(
      headers: {'User-Agent': browserUa},
      connectTimeout: const Duration(seconds: 4),
      receiveTimeout: const Duration(seconds: 5),
      responseType: ResponseType.bytes,
    ),
  );
  dio.httpClientAdapter = IOHttpClientAdapter(
    createHttpClient: () => HttpClient()..findProxy = (_) => 'DIRECT',
  );
  return dio;
}

Map<String, Object?> _updateFailureFields(
  Object error, {
  required String stage,
}) {
  if (error is ApiRemoteConfigException && error.diagnostic != null) {
    return {...error.diagnostic!.toDiagnosticFields(), 'stage': stage};
  }
  final diagnostic = classifyApiNetworkFailure(error, stage: stage);
  return {
    ...diagnostic.toDiagnosticFields(),
    if (error is RemoteConfigCipherException)
      'reason': switch (error.failure) {
        RemoteConfigCipherFailure.signature ||
        RemoteConfigCipherFailure.keyMismatch => 'config_signature',
        _ => 'config_decrypt',
      }
    else if (error is FormatException)
      'reason': 'manifest_format'
    else if (error is AppUpdateUnavailableException)
      'reason': 'configuration_unavailable',
  };
}

int _updateFailurePriority(Object error) => switch (error) {
  RemoteConfigCipherException() => 3,
  FormatException() => 2,
  _ => 1,
};

bool _isRetryableUpdateFailure(Object error) {
  if (error is DioException) {
    final status = error.response?.statusCode;
    if (status != null) return status == 408 || status == 429 || status >= 500;
    return error.type != DioExceptionType.cancel;
  }
  return error is SocketException ||
      error is TimeoutException ||
      error is TlsException;
}

List<Uri> appUpdateManifestUrisFromConfig(Object? config) {
  final primary = appUpdateManifestUriFromConfig(config);
  if (primary == null) return const [];
  return List.unmodifiable([
    primary,
    if (appUpdateTrustedManifestUrls.contains(primary.toString()))
      ...appUpdateTrustedManifestUrls
          .where((value) => value != primary.toString())
          .map(Uri.parse),
  ]);
}

Uri? appUpdateManifestUriFromConfig(Object? config) {
  if (config is! Map) return null;
  final value = config[appUpdateUrlConfigKey];
  if (value is! String) return null;
  final uri = Uri.tryParse(value.trim());
  if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) return null;
  return uri;
}

AppUpdateRelease? parseAppUpdateRelease(
  Object? payload, {
  required String packageKey,
  required Uri manifestUri,
}) {
  if (payload is! Map ||
      payload['Authentication'] != apiHealthConfigAuthentication ||
      payload['format'] != appUpdateManifestFormat ||
      payload['schemaVersion'] != appUpdateManifestVersion) {
    throw const FormatException('Invalid update manifest');
  }
  final packages = payload['packages'];
  if (packages is! Map) {
    throw const FormatException('Update packages are missing');
  }
  final raw = packages[packageKey];
  if (raw is! Map || raw['enabled'] != true) return null;
  final version = _requiredString(raw['version'], 'version');
  if (!_isValidVersion(version)) {
    throw const FormatException('Invalid update version');
  }
  final downloadValue = _requiredString(raw['downloadUrl'], 'downloadUrl');
  final parsedDownload = Uri.tryParse(downloadValue);
  if (parsedDownload == null) {
    throw const FormatException('Invalid update download URL');
  }
  final downloadUri = parsedDownload.hasScheme
      ? parsedDownload
      : manifestUri.resolveUri(parsedDownload);
  if (downloadUri.scheme != 'https' || downloadUri.host.isEmpty) {
    throw const FormatException('Update download URL must use HTTPS');
  }
  final notes = raw['releaseNotesHtml'];
  final title = _optionalString(raw['title']);
  final sha256 = _optionalString(raw['sha256']);
  final publishedAtValue = _optionalString(raw['publishedAt']);
  return AppUpdateRelease(
    packageKey: packageKey,
    version: version,
    downloadUri: downloadUri,
    releaseNotesHtml: notes is String && notes.trim().isNotEmpty
        ? notes
        : '<p>发现新版本 $version。</p>',
    title: title,
    publishedAt: publishedAtValue == null
        ? null
        : DateTime.tryParse(publishedAtValue),
    sha256: sha256,
  );
}

String? currentAppUpdatePackageKey() =>
    appUpdatePackageKeyForAbi(Abi.current());

String? appUpdatePackageKeyForAbi(Abi abi) => switch (abi) {
  Abi.androidArm => 'android-armeabi-v7a',
  Abi.androidArm64 => 'android-arm64-v8a',
  Abi.androidIA32 => 'android-x86',
  Abi.androidX64 => 'android-x86_64',
  Abi.macosArm64 => 'macos-arm64',
  Abi.macosX64 => 'macos-x64',
  Abi.windowsArm64 => 'windows-arm64',
  Abi.windowsIA32 => 'windows-x86',
  Abi.windowsX64 => 'windows-x64',
  _ => null,
};

int compareAppUpdateVersions(String left, String right) {
  final leftParts = _versionParts(left);
  final rightParts = _versionParts(right);
  final count = leftParts.length > rightParts.length
      ? leftParts.length
      : rightParts.length;
  for (var index = 0; index < count; index++) {
    final leftValue = index < leftParts.length ? leftParts[index] : 0;
    final rightValue = index < rightParts.length ? rightParts[index] : 0;
    if (leftValue != rightValue) return leftValue.compareTo(rightValue);
  }
  return 0;
}

List<int> _versionParts(String value) {
  final normalized = value.trim().replaceFirst(RegExp(r'^[vV]'), '');
  final coreAndBuild = normalized.split('+');
  final core = coreAndBuild.first.split('-').first;
  final parts = core.split('.').map(int.tryParse).toList();
  if (parts.isEmpty || parts.any((part) => part == null)) {
    throw const FormatException('Invalid version');
  }
  final result = parts.cast<int>();
  if (coreAndBuild.length > 1) {
    final build = int.tryParse(coreAndBuild[1].split('.').first);
    if (build != null) result.add(build);
  }
  return result;
}

bool _isValidVersion(String value) {
  try {
    _versionParts(value);
    return true;
  } on FormatException {
    return false;
  }
}

Object? _decodeJsonPayload(Object? payload) {
  if (payload is List<int>) return jsonDecode(utf8.decode(payload));
  if (payload is String) return jsonDecode(payload.trim());
  return payload;
}

bool _isEncryptedEnvelope(Object? value) =>
    value is Map && value['format'] == remoteConfigFormat;

String _requiredString(Object? value, String field) {
  final normalized = _optionalString(value);
  if (normalized == null) throw FormatException('Missing $field');
  return normalized;
}

String? _optionalString(Object? value) {
  if (value is! String || value.trim().isEmpty) return null;
  return value.trim();
}

final appUpdateService = AppUpdateService();

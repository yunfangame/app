import 'dart:convert';
import 'dart:ffi';

import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api_health.dart';
import 'constant.dart';
import 'remote_config_cipher.dart';

const appUpdateManifestFormat = 'fengwo-update';
const appUpdateManifestVersion = 1;
const appUpdateUrlConfigKey = 'UpdateUrl';

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
    AppUpdateManifestLoader? manifestLoader,
    AppUpdatePackageKeyResolver? packageKeyResolver,
    AppUpdatePreferenceStore? preferenceStore,
    Dio? dio,
    this.aesKey = remoteConfigAesKey,
    this.signingPublicKey = remoteConfigSigningPublicKey,
  }) : _mainConfigLoader =
           mainConfigLoader ?? (() => ApiHealthService().loadConfig()),
       _manifestLoader = manifestLoader,
       _packageKeyResolver = packageKeyResolver ?? currentAppUpdatePackageKey,
       _preferenceStore = preferenceStore ?? AppUpdatePreferenceStore(),
       _dio =
           dio ??
           Dio(
             BaseOptions(
               headers: {'User-Agent': browserUa},
               connectTimeout: const Duration(seconds: 6),
               receiveTimeout: const Duration(seconds: 10),
               responseType: ResponseType.bytes,
             ),
           );

  final AppUpdateMainConfigLoader _mainConfigLoader;
  final AppUpdateManifestLoader? _manifestLoader;
  final AppUpdatePackageKeyResolver _packageKeyResolver;
  final AppUpdatePreferenceStore _preferenceStore;
  final Dio _dio;
  final String aesKey;
  final String signingPublicKey;

  Future<AppUpdateRelease?> checkForUpdate({
    required String currentVersion,
    bool respectIgnored = true,
  }) async {
    final packageKey = _packageKeyResolver();
    if (packageKey == null) return null;

    final mainConfig = await _mainConfigLoader();
    final manifestUri = appUpdateManifestUriFromConfig(mainConfig);
    if (manifestUri == null) {
      throw const FormatException('Update manifest URL is not configured');
    }
    final payload = await (_manifestLoader ?? _loadManifest)(manifestUri);
    final decoded = await _decodeManifest(payload);
    final release = parseAppUpdateRelease(
      decoded,
      packageKey: packageKey,
      manifestUri: manifestUri,
    );
    if (release == null ||
        compareAppUpdateVersions(release.version, currentVersion) <= 0) {
      return null;
    }
    if (respectIgnored &&
        await _preferenceStore.isIgnored(packageKey, release.version)) {
      return null;
    }
    return release;
  }

  Future<void> ignore(AppUpdateRelease release) =>
      _preferenceStore.ignore(release.packageKey, release.version);

  Future<Object?> _loadManifest(Uri uri) async {
    final response = await _dio.getUri<List<int>>(
      uri,
      options: Options(
        responseType: ResponseType.bytes,
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

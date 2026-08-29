import 'package:shared_preferences/shared_preferences.dart';

class ApiEndpointPreferenceStore {
  ApiEndpointPreferenceStore({
    Future<SharedPreferences> Function()? preferencesLoader,
  }) : _preferencesLoader = preferencesLoader ?? SharedPreferences.getInstance;

  static const _preferredEndpointKey = 'xboard.preferred_api_endpoint';

  final Future<SharedPreferences> Function() _preferencesLoader;

  Future<Uri?> load() async {
    final preferences = await _preferencesLoader();
    final endpoint = Uri.tryParse(
      preferences.getString(_preferredEndpointKey) ?? '',
    );
    if (!_isValid(endpoint)) {
      await preferences.remove(_preferredEndpointKey);
      return null;
    }
    return endpoint;
  }

  Future<void> save(Uri endpoint) async {
    if (!_isValid(endpoint)) {
      throw ArgumentError.value(endpoint, 'endpoint');
    }
    final preferences = await _preferencesLoader();
    await preferences.setString(
      _preferredEndpointKey,
      normalizeApiEndpoint(endpoint).toString(),
    );
  }

  Future<void> clear() async {
    final preferences = await _preferencesLoader();
    await preferences.remove(_preferredEndpointKey);
  }
}

Uri normalizeApiEndpoint(Uri endpoint) {
  return Uri(
    scheme: endpoint.scheme.toLowerCase(),
    host: endpoint.host,
    port: endpoint.hasPort ? endpoint.port : null,
  );
}

bool isSameApiEndpoint(Uri left, Uri right) {
  final normalizedLeft = normalizeApiEndpoint(left);
  final normalizedRight = normalizeApiEndpoint(right);
  return normalizedLeft.scheme.toLowerCase() ==
          normalizedRight.scheme.toLowerCase() &&
      normalizedLeft.host.toLowerCase() == normalizedRight.host.toLowerCase() &&
      normalizedLeft.port == normalizedRight.port;
}

bool _isValid(Uri? endpoint) {
  return endpoint != null &&
      {'http', 'https'}.contains(endpoint.scheme.toLowerCase()) &&
      endpoint.host.isNotEmpty;
}

import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/profile.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'xboard_auth.dart';

class XboardRoutingSnapshot {
  XboardRoutingSnapshot({
    required this.mode,
    required Map<String, String> selectedMap,
    this.currentGroupName,
  }) : selectedMap = Map.unmodifiable(selectedMap);

  factory XboardRoutingSnapshot.fromProfile(Mode mode, Profile profile) =>
      XboardRoutingSnapshot(
        mode: mode,
        selectedMap: profile.selectedMap,
        currentGroupName: profile.currentGroupName,
      );

  factory XboardRoutingSnapshot.fromJson(Map<String, Object?> json) {
    if (json['version'] is! int || json['version'] != 1) {
      throw const FormatException('Unsupported routing snapshot');
    }
    if (json.keys.any(
      (key) => !{
        'version',
        'mode',
        'selected_map',
        'current_group_name',
      }.contains(key),
    )) {
      throw const FormatException('Invalid routing snapshot fields');
    }
    final rawMode = json['mode'];
    final rawSelectedMap = json['selected_map'];
    final rawGroupName = json['current_group_name'];
    if (rawMode is! String ||
        !Mode.values.any((value) => value.name == rawMode) ||
        rawSelectedMap is! Map ||
        (rawGroupName != null && rawGroupName is! String)) {
      throw const FormatException('Invalid routing snapshot');
    }
    final selectedMap = <String, String>{};
    for (final entry in rawSelectedMap.entries) {
      if (entry.key is! String ||
          (entry.key as String).trim().isEmpty ||
          entry.value is! String) {
        throw const FormatException('Invalid routing selection');
      }
      selectedMap[entry.key as String] = entry.value as String;
    }
    return XboardRoutingSnapshot(
      mode: Mode.values.byName(rawMode),
      selectedMap: selectedMap,
      currentGroupName: rawGroupName is String && rawGroupName.trim().isNotEmpty
          ? rawGroupName
          : null,
    );
  }

  final Mode mode;
  final Map<String, String> selectedMap;
  final String? currentGroupName;

  Profile applyTo(Profile profile) => profile.copyWith(
    selectedMap: selectedMap,
    currentGroupName: currentGroupName,
  );

  Map<String, Object?> toJson() => {
    'version': 1,
    'mode': mode.name,
    'selected_map': selectedMap,
    'current_group_name': currentGroupName,
  };
}

class XboardRoutingStore {
  XboardRoutingStore({Future<SharedPreferences> Function()? preferencesLoader})
    : _preferencesLoader = preferencesLoader ?? SharedPreferences.getInstance;

  static const _keyPrefix = 'xboard.local_routing.v1.';
  static const _profileKeyPrefix = 'xboard.local_routing.profile.v1.';

  final Future<SharedPreferences> Function() _preferencesLoader;
  Future<void> _writeQueue = Future.value();
  Future<void> _lastWrite = Future.value();

  static String? scopeKey(XboardLoginResult session) {
    final subscription = session.subscription;
    final uuid = subscription.uuid?.trim();
    final email = subscription.email?.trim().toLowerCase();
    final identity = uuid != null && uuid.isNotEmpty
        ? 'uuid:$uuid'
        : email != null && email.isNotEmpty
        ? 'email:$email'
        : null;
    if (identity == null) return null;
    final planId = subscription.planId ?? subscription.plan?.id;
    final subscribeUrl = subscription.subscribeUrl?.toString().trim();
    final subscriptionKey = planId != null
        ? 'plan:$planId'
        : subscribeUrl != null && subscribeUrl.isNotEmpty
        ? 'url:$subscribeUrl'
        : null;
    if (subscriptionKey == null) return null;
    final digest = sha256
        .convert(utf8.encode(jsonEncode([identity, subscriptionKey])))
        .toString();
    return '$_keyPrefix$digest';
  }

  Future<XboardRoutingSnapshot?> load(XboardLoginResult session) async {
    final key = scopeKey(session);
    if (key == null) return null;
    await _writeQueue;
    final preferences = await _preferencesLoader();
    try {
      final source = preferences.getString(key);
      if (source == null || source.isEmpty) return null;
      final decoded = jsonDecode(source);
      if (decoded is! Map<String, dynamic>) return null;
      return XboardRoutingSnapshot.fromJson(decoded);
    } on FormatException {
      return null;
    } on TypeError {
      return null;
    }
  }

  Future<void> save(XboardLoginResult session, XboardRoutingSnapshot snapshot) {
    final key = scopeKey(session);
    if (key == null) return Future.value();
    final source = jsonEncode(snapshot.toJson());
    return _write(key, source, 'routing_save_failed');
  }

  Future<bool> ownsProfile(XboardLoginResult session, Profile profile) async {
    final scope = scopeKey(session);
    if (scope == null) return false;
    await _writeQueue;
    final preferences = await _preferencesLoader();
    try {
      return preferences.getString(_profileKey(profile)) == scope;
    } on TypeError {
      return false;
    }
  }

  Future<void> bindProfile(XboardLoginResult session, Profile profile) {
    final scope = scopeKey(session);
    if (scope == null) return Future.value();
    return _write(_profileKey(profile), scope, 'routing_profile_bind_failed');
  }

  String _profileKey(Profile profile) {
    final digest = sha256
        .convert(utf8.encode(jsonEncode([profile.id, profile.url])))
        .toString();
    return '$_profileKeyPrefix$digest';
  }

  Future<void> _write(String key, String source, String failureCode) {
    final operation = _writeQueue.then((_) async {
      final preferences = await _preferencesLoader();
      if (!await preferences.setString(key, source)) {
        throw StateError(failureCode);
      }
    });
    _lastWrite = operation;
    _writeQueue = operation.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return operation;
  }

  Future<void> flush() => _lastWrite;
}

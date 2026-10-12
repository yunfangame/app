import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'local_secret_store.dart';

export 'macos_identity_constants.dart';

const macIdentityChannel = MethodChannel('com.fengwo.accelerator/identity');

class MacIdentityPreparation {
  const MacIdentityPreparation({
    required this.legacyImported,
    required this.status,
    this.requiresLogin = false,
  });

  final bool legacyImported;
  final String status;
  final bool requiresLogin;

  static MacIdentityPreparation fromChannel(Object? value) {
    if (value is Map &&
        value['legacyImported'] is bool &&
        value['status'] is String) {
      return MacIdentityPreparation(
        legacyImported: value['legacyImported'] as bool,
        status: value['status'] as String,
      );
    }
    return const MacIdentityPreparation(
      legacyImported: false,
      status: 'migration_failed',
    );
  }
}

Future<MacIdentityPreparation> prepareMacStartupIdentity({
  Future<Object?> Function()? prepareIdentity,
  Future<void> Function()? acquireLock,
  Future<bool> Function()? migrateSecrets,
}) async {
  MacIdentityPreparation preparation;
  try {
    preparation = MacIdentityPreparation.fromChannel(
      await (prepareIdentity ??
          () => macIdentityChannel.invokeMethod<Object?>('prepareIdentity'))(),
    );
  } catch (_) {
    preparation = const MacIdentityPreparation(
      legacyImported: false,
      status: 'migration_failed',
    );
  }
  await acquireLock?.call();
  if (!preparation.legacyImported) return preparation;
  var migrated = false;
  try {
    migrated = await (migrateSecrets ?? migrateMacIdentitySecrets)();
  } catch (_) {
    migrated = false;
  }
  return MacIdentityPreparation(
    legacyImported: true,
    status: preparation.status,
    requiresLogin: !migrated,
  );
}

Future<bool> migrateMacIdentitySecrets() async {
  final root = await getApplicationSupportDirectory();
  final preferences = await SharedPreferences.getInstance();
  await preferences.reload();
  var successful = false;
  try {
    final target = createPlatformSecretStringStore();
    final copied = EncryptedFileSecretStringStore(
      directoryLoader: () async =>
          Directory(p.join(root.path, '.secure-storage')),
    );
    final copiedSecrets = <String, String>{};
    if (await File(
      p.join(root.path, '.secure-storage', '.master-key'),
    ).exists()) {
      for (final key in MacLegacySecretMigration.accountKeys) {
        final value = await copied.read(key);
        if (value != null) copiedSecrets[key] = value;
      }
    }
    successful = await MacLegacySecretMigration(
      root: root,
      target: target,
      copiedSecrets: copiedSecrets,
      readLegacy: () => const FlutterSecureStorage(
        mOptions: MacOsOptions(accountName: 'flutter_secure_storage_service'),
      ).readAll(),
      requiredKeyGroups: macRequiredSecretGroups({
        for (final key in preferences.getKeys()) key: preferences.get(key),
      }),
    ).run();
  } catch (_) {
    successful = false;
  }
  if (!successful) {
    for (final key in [
      'xboard.auto_login',
      'xboard.offline_mode',
      'xboard.session_enabled',
      'xboard.credentials_enabled',
    ]) {
      await preferences.setBool(key, false);
    }
  }
  return successful;
}

List<Set<String>> macRequiredSecretGroups(Map<String, Object?> preferences) {
  final groups = <Set<String>>[];
  final remembered =
      preferences['xboard.remember_me'] == true &&
      preferences['xboard.forget_requested'] != true;
  if (remembered && preferences['xboard.credentials_enabled'] != false) {
    groups.add({'xboard.credentials_v2', 'xboard.password'});
  }
  if (remembered &&
      preferences['xboard.session_enabled'] != false &&
      preferences['xboard.endpoint'] is String) {
    groups.add({'xboard.token'});
    groups.add({'xboard.auth_data'});
  }
  if (preferences['xboard.secure_subscription'] == true) {
    groups.add({'subscription_v2.device_seed'});
  }
  return groups;
}

class MacLegacySecretMigration {
  MacLegacySecretMigration({
    required this.root,
    required this.target,
    required this.readLegacy,
    this.copiedSecrets = const {},
    this.requiredKeyGroups = const [],
  });

  static const markerName = '.fengwo-identity-secrets-v2.json';
  static const accountKeys = {
    'xboard.token',
    'xboard.auth_data',
    'xboard.password',
    'xboard.credentials_v2',
    'subscription_v2.device_seed',
  };
  static final _credentialKey = RegExp(
    r'^subscription_v2\.credential\.[a-f0-9]{64}$',
  );

  final Directory root;
  final SecretStringStore target;
  final Future<Map<String, String>> Function() readLegacy;
  final Map<String, String> copiedSecrets;
  final List<Set<String>> requiredKeyGroups;

  Future<bool> run() async {
    final marker = File(p.join(root.path, markerName));
    try {
      var pending = false;
      if (await marker.exists()) {
        final record = jsonDecode(await marker.readAsString());
        if (record is! Map || record['version'] != 2) return false;
        if (record['state'] == 'complete') {
          return record['requiresLogin'] != true ||
              await _requiredKeysAvailable(const {});
        }
        if (record['state'] != 'pending') return false;
        pending = true;
      }
      var targetHasValues = false;
      for (final key in accountKeys) {
        if (await target.read(key) != null) targetHasValues = true;
      }
      if (targetHasValues &&
          ((!pending && copiedSecrets.isEmpty) ||
              await _requiredKeysAvailable(const {}))) {
        final available = await _requiredKeysAvailable(const {});
        await _writeMarker(
          marker,
          state: 'complete',
          requiresLogin: !available,
        );
        return available;
      }
      await _writeMarker(marker, state: 'pending');
      final values = Map<String, String>.from(copiedSecrets);
      var requiredAvailable = await _requiredKeysAvailable(values);
      if (copiedSecrets.isEmpty || !requiredAvailable) {
        final Map<String, String> legacy;
        try {
          legacy = await readLegacy();
        } catch (_) {
          await _writeMarker(marker, state: 'complete', requiresLogin: true);
          return false;
        }
        for (final entry in legacy.entries) {
          values.putIfAbsent(entry.key, () => entry.value);
        }
        requiredAvailable = await _requiredKeysAvailable(values);
      }
      for (final entry in values.entries) {
        if (!accountKeys.contains(entry.key) &&
            !_credentialKey.hasMatch(entry.key)) {
          continue;
        }
        if (await target.read(entry.key) != null) continue;
        await target.write(entry.key, entry.value);
        if (await target.read(entry.key) != entry.value) return false;
      }
      await _writeMarker(
        marker,
        state: 'complete',
        requiresLogin: !requiredAvailable,
      );
      return requiredAvailable;
    } catch (_) {
      return false;
    }
  }

  Future<bool> _requiredKeysAvailable(Map<String, String> values) async {
    for (final group in requiredKeyGroups) {
      var available = false;
      for (final key in group) {
        final current = await target.read(key);
        final value = current ?? values[key];
        if (value != null && value.isNotEmpty) available = true;
      }
      if (!available) return false;
    }
    return true;
  }

  Future<void> _writeMarker(
    File marker, {
    required String state,
    bool requiresLogin = false,
  }) async {
    await root.create(recursive: true);
    final temporary = File('${marker.path}.$pid.tmp');
    try {
      await temporary.writeAsString(
        jsonEncode({
          'version': 2,
          'state': state,
          'requiresLogin': requiresLogin,
        }),
        flush: true,
      );
      await temporary.rename(marker.path);
    } finally {
      if (await temporary.exists()) await temporary.delete();
    }
  }
}

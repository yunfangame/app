import 'dart:async';
import 'dart:convert';

import 'package:fl_clash/common/print.dart';
import 'package:fl_clash/common/system_dns.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'constant.dart';
import 'diagnostic_log.dart';
import 'preferences_storage_error.dart';
import 'windows_preferences.dart';

class Preferences {
  static Preferences? _instance;
  final Future<SharedPreferences> Function() _loader;
  Future<SharedPreferences>? _initialization;

  Preferences._internal() : _loader = SharedPreferences.getInstance;

  Preferences.forTesting({required Future<SharedPreferences> Function() loader})
    : _loader = loader;

  factory Preferences() {
    _instance ??= Preferences._internal();
    return _instance!;
  }

  Future<SharedPreferences> get _storage => _initialization ??= _initialize();

  Future<SharedPreferences> _initialize() async {
    try {
      return await _loader();
    } catch (error, stack) {
      _fail('initialize', error, stack);
    }
  }

  Future<bool> get isInit async {
    try {
      await _storage;
      return true;
    } catch (_) {
      return false;
    }
  }

  Never _fail(String operation, Object error, StackTrace stack) {
    final failure = error is PreferenceStorageException
        ? error
        : PreferenceStorageException(operation: operation, cause: error);
    unawaited(
      diagnosticLog.record(
        'preferences.failed',
        fields: {
          'operation': failure.operation,
          'diagnostic_code': failure.code,
          'error_type': failure.cause.runtimeType.toString(),
        },
      ),
    );
    Error.throwWithStackTrace(failure, stack);
  }

  Future<void> recoverForStartup() async {
    await resetWindowsPreferencesForStartup(
      canRestore: (values) {
        try {
          final version = values['flutter.version'];
          if (version != null &&
              (version is! int || version < 0 || version > 1)) {
            return false;
          }
          final raw = values['flutter.$configKey'];
          Map<String, Object?>? configMap;
          if (raw != null) {
            if (raw is! String) return false;
            final decoded = json.decode(raw);
            if (decoded is! Map<String, dynamic> ||
                decoded['proxiesStyle'] != null) {
              return false;
            }
            configMap = decoded;
          }
          if (version == null || version == 0) {
            final clashRaw = values['flutter.$clashConfigKey'];
            if (clashRaw != null) {
              if (clashRaw is! String) return false;
              final clashMap = json.decode(clashRaw);
              if (clashMap is! Map<String, dynamic>) return false;
              configMap = Map<String, Object?>.from(configMap ?? const {});
              configMap.putIfAbsent('patchClashConfig', () => clashMap);
            }
          }
          Config.realFromJson(configMap);
          return true;
        } catch (_) {
          return false;
        }
      },
    );
    _initialization = null;
    final storage = await _storage;
    await storage.reload();
    await diagnosticLog.record('preferences.startup_recovered');
  }

  Future<int> getVersion() async {
    final storage = await _storage;
    try {
      return storage.getInt('version') ?? 0;
    } catch (error, stack) {
      _fail('read', error, stack);
    }
  }

  Future<void> setVersion(int version) async {
    await _write((storage) => storage.setInt('version', version));
  }

  Future<void> saveShareState(SharedState shareState) async {
    await _write(
      (storage) => storage.setString('sharedState', json.encode(shareState)),
    );
  }

  Future<Map<String, Object?>?> getConfigMap() => _readMap(configKey);

  Future<Map<String, Object?>?> getClashConfigMap() => _readMap(clashConfigKey);

  Future<Map<String, Object?>?> _readMap(String key) async {
    final storage = await _storage;
    try {
      final text = storage.getString(key);
      if (text == null) return null;
      final value = json.decode(text);
      if (value is! Map<String, dynamic>) {
        throw const FormatException('Expected a configuration object');
      }
      return value;
    } catch (error, stack) {
      _fail('decode', error, stack);
    }
  }

  Future<void> clearClashConfig() async {
    await _write((storage) => storage.remove(clashConfigKey));
  }

  Future<Config?> getConfig() async {
    final configMap = await getConfigMap();
    if (configMap == null) return null;
    try {
      return Config.fromJson(configMap);
    } catch (error, stack) {
      _fail('decode', error, stack);
    }
  }

  Future<bool> saveConfig(Config config) {
    return _write(
      (storage) => storage.setString(configKey, json.encode(config)),
    );
  }

  Future<bool> _write(
    Future<bool> Function(SharedPreferences) operation,
  ) async {
    final storage = await _storage;
    try {
      if (!await operation(storage)) {
        throw StateError('Preference storage rejected the write');
      }
      return true;
    } catch (error, stack) {
      _fail('write', error, stack);
    }
  }

  Future<SystemDnsRecord?> getSystemDnsRecord() async {
    try {
      final sharedPreferencesIns = await _storage;
      final raw = sharedPreferencesIns.getString(systemDnsRecordKey);
      if (raw == null) {
        return null;
      }
      return SystemDnsRecord.fromJson(json.decode(raw));
    } catch (error) {
      commonPrint.log(
        'getSystemDnsRecord error $error',
        logLevel: LogLevel.warning,
      );
      return null;
    }
  }

  Future<void> saveSystemDnsRecord(SystemDnsRecord record) async {
    await _write(
      (storage) => storage.setString(systemDnsRecordKey, json.encode(record)),
    );
  }

  Future<void> clearSystemDnsRecord() async {
    await _write((storage) => storage.remove(systemDnsRecordKey));
  }

  Future<void> clearPreferences() async {
    await _write((storage) => storage.clear());
  }
}

final preferences = Preferences();

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';

import '../../lib/common/local_secret_store.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    const MaterialApp(home: Scaffold(body: Text('Storage probe running'))),
  );
  final runId =
      Platform.environment['FENGWO_AUTH_PROBE_ID'] ??
      const String.fromEnvironment('FENGWO_AUTH_PROBE_ID');
  var phase =
      Platform.environment['FENGWO_AUTH_PROBE_PHASE'] ??
      const String.fromEnvironment(
        'FENGWO_AUTH_PROBE_PHASE',
        defaultValue: 'auto',
      );
  if (!RegExp(r'^probe-[a-z0-9-]{8,80}$').hasMatch(runId) ||
      !['seed', 'reopen', 'auto'].contains(phase)) {
    stderr.writeln('Invalid isolated probe identity or phase');
    exit(2);
  }
  final support = await getApplicationSupportDirectory();
  final directory = Directory('${support.path}/$runId');
  await directory.create(recursive: true);
  if (phase == 'auto') {
    phase = await File('${directory.path}/seed.json').exists()
        ? 'reopen'
        : 'seed';
  }
  final report = <String, Object?>{
    'runId': runId,
    'phase': phase,
    'os': Platform.operatingSystem,
    'osVersion': Platform.operatingSystemVersion,
    'pid': pid,
    'scope': 'isolated native storage primitives; not application login UI',
    'sourceSha256': const String.fromEnvironment(
      'FENGWO_AUTH_PROBE_SOURCE_SHA',
    ),
    'tests': <Object?>[],
  };
  final tests = report['tests']! as List<Object?>;
  final factories = <String, SecretStringStore Function()>{
    'release_platform_selected': () => createPlatformSecretStringStore(
      directoryLoader: () async => Directory('${directory.path}/encrypted'),
    ),
    'platform_native': () => FlutterSecureSecretStringStore(
      storage: FlutterSecureStorage(
        mOptions: MacOsOptions(
          accountName: 'io.fengwo.auth-storage-probe.$runId',
          authenticationUIBehavior: 'fail',
        ),
        iOptions: IOSOptions(
          accountName: 'io.fengwo.auth-storage-probe.$runId',
        ),
      ),
    ),
  };
  var failures = 0;
  for (final entry in factories.entries) {
    final checks = <String>[];
    final keyPrefix = 'fengwo-isolated-probe.$runId.${entry.key}';
    final result = <String, Object?>{'backend': entry.key, 'checks': checks};
    tests.add(result);
    try {
      final store = entry.value();
      result['implementation'] = store.runtimeType.toString();
      final passwordKey = '$keyPrefix.password';
      final sessionKey = '$keyPrefix.session';
      final otherKey = '$keyPrefix.other';
      final fakePassword = 'isolated-test-only-$runId';
      if (phase == 'seed') {
        _require(await store.read(passwordKey) == null, 'fresh password');
        await store.write(passwordKey, fakePassword);
        _require(await store.read(passwordKey) == fakePassword, 'write/read');
        checks.add('write_read');
        await store.write(sessionKey, 'isolated-session-only');
        await store.delete(sessionKey);
        _require(await store.read(sessionKey) == null, 'session delete');
        _require(
          await store.read(passwordKey) == fakePassword,
          'password survives session delete',
        );
        checks.add('session_delete_preserves_password');
        final recreated = entry.value();
        _require(
          await recreated.read(passwordKey) == fakePassword,
          'recreated store read',
        );
        checks.add('store_recreation');
      } else {
        _require(
          await store.read(passwordKey) == fakePassword,
          'process restart read',
        );
        checks.add('process_restart_retains_password');
        await store.write(otherKey, 'isolated-other-account');
        await store.write(passwordKey, 'isolated-replacement');
        _require(
          await store.read(passwordKey) == 'isolated-replacement',
          'replacement read',
        );
        _require(
          await store.read(otherKey) == 'isolated-other-account',
          'distinct account',
        );
        checks.add('replace_and_distinct_keys');
        await store.delete(passwordKey);
        await store.delete(otherKey);
        _require(await store.read(passwordKey) == null, 'delete password');
        _require(await store.read(otherKey) == null, 'delete other account');
        checks.add('explicit_delete');
        await store.write(passwordKey, 'isolated-recreated');
        _require(
          await entry.value().read(passwordKey) == 'isolated-recreated',
          'recreate after delete',
        );
        await store.delete(passwordKey);
        _require(await store.read(passwordKey) == null, 'final cleanup');
        checks.add('write_after_delete_and_cleanup');
      }
      result['status'] = 'pass';
    } catch (error) {
      failures++;
      result['status'] = 'fail';
      result['errorType'] = error.runtimeType.toString();
      if (error is PlatformException) {
        result['errorCode'] = error.code;
        if (error.details is int) result['nativeStatus'] = error.details;
      }
      if (error is StateError) result['failedCheck'] = error.message;
    }
  }
  report['failures'] = failures;
  final reportFile = File('${directory.path}/$phase.json');
  await reportFile.writeAsString(
    const JsonEncoder.withIndent('  ').convert(report),
    flush: true,
  );
  stdout.writeln(jsonEncode(report));
  stdout.writeln('AUTH_STORAGE_PROBE_REPORT=${reportFile.path}');
  exit(failures == 0 ? 0 : 1);
}

void _require(bool condition, String check) {
  if (!condition) throw StateError(check);
}

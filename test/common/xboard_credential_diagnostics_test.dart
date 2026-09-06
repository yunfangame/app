import 'dart:convert';
import 'dart:io';

import 'package:fl_clash/common/diagnostic_log.dart';
import 'package:fl_clash/common/local_secret_store.dart';
import 'package:fl_clash/common/xboard_auth.dart';
import 'package:fl_clash/common/xboard_login_persistence.dart';
import 'package:fl_clash/common/xboard_session_storage.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  for (final failWrites in [false, true]) {
    test(
      'credential diagnostics survive reopening, failure=$failWrites',
      () async {
        final directory = await Directory.systemTemp.createTemp(
          'fengwo-credential-diagnostics-',
        );
        addTearDown(() => directory.delete(recursive: true));
        final log = DiagnosticLog(directoryLoader: () async => directory);
        final memoryEvents = <String>[];
        void record(String event, Map<String, Object?> fields) {
          memoryEvents.add(event);
          log.record(event, fields: fields);
        }

        final storage = XboardSessionStorage(
          secretStore: _DiagnosticSecretBoundary(failWrites: failWrites),
          onDiagnostic: record,
        );
        final persistence = XboardLoginPersistence(
          storage: storage,
          onDiagnostic: record,
        );
        final endpoint = Uri.parse('https://api.example.com');
        final saved = await persistence.saveAuthenticated(
          session: XboardLoginResult(
            endpoint: endpoint,
            token: 'diagnostic-private-token',
            authData: 'diagnostic-private-auth-data',
            isAdmin: false,
            subscription: XboardSubscriptionData(
              endpoint: endpoint,
              subscribeUrl: Uri.parse('https://subscribe.example.com/client'),
              uploadBytes: 0,
              downloadBytes: 0,
              transferEnableBytes: bytesPerGigabyte,
              rawData: const {},
            ),
          ),
          email: 'diagnostic-private-account@example.com',
          password: 'diagnostic-private-password',
          rememberMe: true,
          autoLogin: true,
        );
        expect(saved, !failWrites);
        final loggedOut = await persistence.prepareForLogout();
        expect(loggedOut.rememberMe, isTrue);
        expect(loggedOut.password, 'diagnostic-private-password');
        expect(loggedOut.hasStorageError, failWrites);
        await log.flush();
        memoryEvents.clear();

        final reopened = DiagnosticLog(directoryLoader: () async => directory);
        final exported = await reopened.readAll();
        final events = const LineSplitter()
            .convert(exported)
            .map((line) => jsonDecode(line) as Map<String, dynamic>)
            .toList();
        expect(memoryEvents, isEmpty);
        expect(
          events.map((entry) => entry['event']),
          containsAll([
            'auth.credentials.save.requested',
            failWrites
                ? 'auth.credentials.save.failed'
                : 'auth.credentials.save.verified',
            'auth.credentials.logout.prefill',
          ]),
        );
        final prefill = events.lastWhere(
          (entry) => entry['event'] == 'auth.credentials.logout.prefill',
        );
        expect(prefill['fields']['storage_error'], failWrites);
        expect(prefill['fields']['password_present'], isTrue);
        if (failWrites) {
          final failures = events.where(
            (entry) => entry['event'] == 'credentials_storage_error',
          );
          expect(failures, isNotEmpty);
          expect(
            failures.any(
              (entry) => entry['fields']['stage'] == 'write_credentials',
            ),
            isTrue,
          );
        }
        for (final secret in [
          'diagnostic-private-account',
          'diagnostic-private-password',
          'diagnostic-private-token',
          'diagnostic-private-auth-data',
        ]) {
          expect(exported, isNot(contains(secret)));
        }
      },
    );
  }
}

class _DiagnosticSecretBoundary implements SecretStringStore {
  _DiagnosticSecretBoundary({required this.failWrites});

  final bool failWrites;
  final values = <String, String>{};

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async {
    if (failWrites) {
      throw PlatformException(
        code: 'write_unavailable',
        message: 'diagnostic-private-password diagnostic-private-token',
        details: 'diagnostic-private-auth-data',
      );
    }
    values[key] = value;
  }

  @override
  Future<void> delete(String key) async => values.remove(key);
}

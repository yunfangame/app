import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:fl_clash/common/windows_auto_launch.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:win32_registry/win32_registry.dart';

void main() {
  final environment = Platform.environment;
  final isolated =
      Platform.isWindows &&
      environment['GITHUB_ACTIONS'] == 'true' &&
      environment['RUNNER_OS'] == 'Windows';

  test(
    'installed Windows auto launch uses the real current-user registry',
    () async {
      final executable = environment['FENGWO_AUTOSTART_TEST_EXECUTABLE'];
      expect(executable, isNotNull);
      expect(File(executable!).existsSync(), isTrue);
      expect(executable, contains(' '));
      final backend = WindowsAutoLaunchBackend(executable: executable);
      final run = CURRENT_USER.create(WindowsAutoLaunchBackend.runPath);
      final approved = CURRENT_USER.create(
        WindowsAutoLaunchBackend.approvedPath,
      );
      const names = ['FengWo', 'FlClash'];
      final original = <(RegistryKey, String), RegistryValue?>{
        for (final key in [run, approved])
          for (final name in names) (key, name): key.getValue(name),
      };
      final results = <String>[];
      var completed = false;
      final operation =
          environment['FENGWO_AUTOSTART_TEST_OPERATION'] ?? 'exercise';

      void assign(RegistryKey key, String name, RegistryValue? value) {
        if (value == null) {
          if (key.getValue(name) != null) key.removeValue(name);
        } else {
          key.setValue(name, value);
        }
      }

      void clear() {
        for (final key in [run, approved]) {
          for (final name in names) {
            assign(key, name, null);
          }
        }
      }

      void restore() {
        for (final entry in original.entries) {
          assign(entry.key.$1, entry.key.$2, entry.value);
        }
      }

      try {
        if (operation == 'exercise') {
          clear();
          expect(await backend.isEnabled(), isFalse);
          expect(run.getValue('FengWo'), isNull);
          expect(approved.getValue('FengWo'), isNull);
          results.add('default-disabled-without-registration');

          await backend.setEnabled(true);
          expect(run.getString('FengWo'), '"$executable"');
          expect(await backend.isEnabled(), isTrue);
          expect(approved.getBinary('FengWo')!.first, 2);
          results.add('enable-quotes-installed-path');

          final disabled = Uint8List(12)..[0] = 3;
          approved.setValue('FengWo', RegistryValue.binary(disabled));
          expect(await backend.isEnabled(), isFalse);
          expect(approved.getBinary('FengWo'), disabled);
          expect(run.getString('FengWo'), backend.command);
          results.add('respects-task-manager-disabled-state');

          await backend.setEnabled(true);
          expect(await backend.isEnabled(), isTrue);
          expect(approved.getBinary('FengWo')!.first, 2);
          await backend.setEnabled(false);
          expect(await backend.isEnabled(), isFalse);
          expect(run.getValue('FengWo'), isNull);
          expect(approved.getValue('FengWo'), isNull);
          results.add('explicit-reenable-and-disable');

          for (final command in [executable, backend.command]) {
            run.setValue('FlClash', RegistryValue.string(command));
            approved.setValue(
              'FlClash',
              RegistryValue.binary(Uint8List(12)..[0] = 2),
            );
            expect(await backend.isEnabled(), isTrue);
            await backend.setEnabled(true);
            expect(run.getString('FengWo'), backend.command);
            expect(run.getValue('FlClash'), isNull);
            expect(approved.getValue('FlClash'), isNull);
            await backend.setEnabled(false);
          }
          results.add('migrates-only-owned-legacy-registration');

          const foreignCommand = r'"C:\Another Installation\FlClash.exe"';
          final foreignApproval = Uint8List(12)..[0] = 3;
          run.setValue('FlClash', const RegistryValue.string(foreignCommand));
          approved.setValue('FlClash', RegistryValue.binary(foreignApproval));
          expect(await backend.isEnabled(), isFalse);
          await backend.setEnabled(true);
          await backend.setEnabled(false);
          expect(run.getString('FlClash'), foreignCommand);
          expect(approved.getBinary('FlClash'), foreignApproval);
          results.add('preserves-unrelated-flclash-registration');
          restore();
          await backend.setEnabled(true);
        } else {
          expect(operation, isIn(['enable', 'disable']));
          await backend.setEnabled(operation == 'enable');
          expect(await backend.isEnabled(), operation == 'enable');
          results.add(operation);
        }
        final reportPath = environment['FENGWO_AUTOSTART_NATIVE_REPORT'];
        if (reportPath != null) {
          await File(reportPath).writeAsString(
            const JsonEncoder.withIndent('  ').convert({
              'operation': operation,
              'executable': executable,
              'cases': results,
              'enabled': await backend.isEnabled(),
              'registered_command': run.getString('FengWo'),
            }),
          );
        }
        completed = true;
      } finally {
        if (!completed || environment['FENGWO_AUTOSTART_KEEP_STATE'] != '1') {
          restore();
        }
        approved.close();
        run.close();
      }
    },
    skip: !isolated,
  );
}

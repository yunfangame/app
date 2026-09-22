import 'dart:async';
import 'dart:typed_data';

import 'package:fl_clash/common/launch.dart';
import 'package:fl_clash/common/windows_auto_launch.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:win32_registry/win32_registry.dart';

void main() {
  test(
    'silent launch keeps unauthenticated login reachable without a tray',
    () {
      expect(
        shouldHideWindowAtStartup(
          silentLaunch: true,
          hasAuthenticatedSession: false,
        ),
        isFalse,
      );
      expect(
        shouldHideWindowAtStartup(
          silentLaunch: true,
          hasAuthenticatedSession: true,
        ),
        isTrue,
      );
      expect(
        shouldHideWindowAtStartup(
          silentLaunch: false,
          hasAuthenticatedSession: true,
        ),
        isFalse,
      );
    },
  );

  const executable = r'C:\Program Files\蜂窝加速器\FengWo.exe';
  const run = WindowsAutoLaunchBackend.runPath;
  const approved = WindowsAutoLaunchBackend.approvedPath;

  late _Registry registry;
  late WindowsAutoLaunchBackend backend;
  late AutoLaunch service;
  setUp(() {
    registry = _Registry();
    backend = WindowsAutoLaunchBackend(
      executable: executable,
      registry: registry,
    );
    service = AutoLaunch.withBackend(
      read: backend.isEnabled,
      write: backend.setEnabled,
      captureRestore: backend.captureRestore,
    );
  });

  test(
    'default status reads disabled without creating registry values',
    () async {
      expect(await service.isEnable, isFalse);
      expect(registry.writes, isEmpty);
      expect(registry.values, isEmpty);
    },
  );

  test('enables quoted executable and disables both own values', () async {
    await service.updateStatus(true);
    expect(registry.read(run, 'FengWo'), const StringValue('"$executable"'));
    expect((registry.read(approved, 'FengWo') as BinaryValue).value.first, 2);
    expect(await service.isEnable, isTrue);
    await service.updateStatus(false);
    expect(await service.isEnable, isFalse);
    expect(registry.values, isEmpty);
  });

  test('reads task manager disable without silently re-enabling it', () async {
    await service.updateStatus(true);
    registry.values[(approved, 'FengWo')] = BinaryValue(Uint8List(12)..[0] = 3);
    registry.writes.clear();
    expect(await service.isEnable, isFalse);
    expect(registry.writes, isEmpty);
  });

  test(
    'keeps unrelated FlClash and similarly named executable untouched',
    () async {
      const foreign = StringValue(r'"C:\FlClash\FlClash.exe"');
      final foreignApproved = BinaryValue(Uint8List(12)..[0] = 3);
      registry.values[(run, 'FlClash')] = foreign;
      registry.values[(approved, 'FlClash')] = foreignApproved;
      await service.updateStatus(true);
      await service.updateStatus(false);
      expect(registry.read(run, 'FlClash'), foreign);
      expect(registry.read(approved, 'FlClash'), foreignApproved);
      expect(registry.writes.every((entry) => entry.$2 == 'FengWo'), isTrue);
    },
  );

  test(
    'recognizes own legacy registration and migrates only on explicit change',
    () async {
      registry.values[(run, 'FlClash')] = const StringValue(executable);
      expect(await service.isEnable, isTrue);
      expect(registry.writes, isEmpty);
      await service.updateStatus(true);
      expect(await service.isEnable, isTrue);
      expect(registry.read(run, 'FlClash'), isNull);
      expect(registry.read(run, 'FengWo'), const StringValue('"$executable"'));
    },
  );

  test(
    'malformed and argument-bearing legacy commands are not owned',
    () async {
      for (final command in ['"', '"$executable" --other', '$executable.old']) {
        registry.values[(run, 'FlClash')] = StringValue(command);
        expect(await service.isEnable, isFalse);
        await service.updateStatus(false);
        expect(registry.read(run, 'FlClash'), StringValue(command));
      }
    },
  );

  test(
    'permission failure restores partial registry changes and skips save',
    () async {
      var saved = false;
      registry.rejected = (approved, 'FengWo');
      await expectLater(
        service.updateStatus(true, persist: (_) async => saved = true),
        throwsA(
          isA<AutoLaunchException>().having(
            (e) => e.code,
            'code',
            'changeFailed',
          ),
        ),
      );
      expect(saved, isFalse);
      expect(registry.values, isEmpty);
    },
  );

  test(
    'persistence failure restores exact values from another install',
    () async {
      const old = StringValue(r'"D:\Previous FengWo\FengWo.exe"');
      final oldApproval = BinaryValue(Uint8List.fromList([3, 1, 2, 3]));
      registry.values[(run, 'FengWo')] = old;
      registry.values[(approved, 'FengWo')] = oldApproval;
      await expectLater(
        service.updateStatus(
          true,
          persist: (_) async => throw StateError('disk full'),
        ),
        throwsA(
          isA<AutoLaunchException>().having(
            (e) => e.code,
            'code',
            'persistenceFailed',
          ),
        ),
      );
      expect(registry.read(run, 'FengWo'), old);
      expect(registry.read(approved, 'FengWo'), oldApproval);
    },
  );

  test(
    'persistence failure restores legacy registration without duplicate entry',
    () async {
      registry.values[(run, 'FlClash')] = const StringValue(executable);
      await expectLater(
        service.updateStatus(
          false,
          persist: (_) async => throw StateError('disk full'),
        ),
        throwsA(isA<AutoLaunchException>()),
      );
      expect(await service.isEnable, isTrue);
      expect(registry.read(run, 'FlClash'), const StringValue(executable));
      expect(registry.read(run, 'FengWo'), isNull);
    },
  );

  test(
    'does not report success when the system rejects the requested state',
    () async {
      var saved = false;
      final rejectedService = AutoLaunch.withBackend(
        read: () async => false,
        write: (_) async {},
      );
      await expectLater(
        rejectedService.updateStatus(true, persist: (_) async => saved = true),
        throwsA(
          isA<AutoLaunchException>().having(
            (e) => e.code,
            'code',
            'verificationFailed',
          ),
        ),
      );
      expect(saved, isFalse);
    },
  );

  test('serializes opposite requests until persistence completes', () async {
    final saving = Completer<void>();
    final saved = <bool>[];
    final enable = service.updateStatus(
      true,
      persist: (value) async {
        await saving.future;
        saved.add(value);
      },
    );
    final disable = service.updateStatus(
      false,
      persist: (value) async => saved.add(value),
    );
    await Future<void>.delayed(Duration.zero);
    expect(await backend.isEnabled(), isTrue);
    expect(saved, isEmpty);
    saving.complete();
    await Future.wait([enable, disable]);
    expect(saved, [true, false]);
    expect(await service.isEnable, isFalse);
  });

  test('read failures do not mutate registration or persist intent', () async {
    var wrote = false;
    final unreadable = AutoLaunch.withBackend(
      read: () async => throw StateError('denied'),
      write: (_) async => wrote = true,
    );
    await expectLater(
      unreadable.updateStatus(true),
      throwsA(
        isA<AutoLaunchException>().having((e) => e.code, 'code', 'readFailed'),
      ),
    );
    expect(wrote, isFalse);
  });

  test('rollback denial is surfaced instead of false success', () async {
    await expectLater(
      service.updateStatus(
        true,
        persist: (_) async {
          registry.rejected = (run, 'FengWo');
          throw StateError('disk full');
        },
      ),
      throwsA(
        isA<AutoLaunchException>().having(
          (e) => e.code,
          'code',
          'rollbackFailed',
        ),
      ),
    );
    expect(await service.isEnable, isTrue);
  });
}

class _Registry implements WindowsAutoLaunchRegistry {
  final values = <(String, String), RegistryValue>{};
  final writes = <(String, String)>[];
  (String, String)? rejected;

  @override
  RegistryValue? read(String path, String name) => values[(path, name)];

  @override
  void write(String path, String name, RegistryValue? value) {
    if (rejected == (path, name)) throw StateError('access denied');
    writes.add((path, name));
    if (value == null) {
      values.remove((path, name));
    } else {
      values[(path, name)] = value;
    }
  }
}

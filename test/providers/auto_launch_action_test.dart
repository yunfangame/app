import 'dart:async';

import 'package:fl_clash/common/launch.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:riverpod/riverpod.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _AutoLaunchAction action;
  late ProviderContainer container;
  setUp(() {
    action = _AutoLaunchAction();
    container = ProviderContainer(
      overrides: [systemActionProvider.overrideWith(() => action)],
    );
    container.listen(appSettingProvider, (_, _) {});
    container.read(systemActionProvider);
  });
  tearDown(() => container.dispose());

  test('default remains off and refresh never enables cached intent', () async {
    expect(container.read(appSettingProvider).autoLaunch, isFalse);
    container
        .read(appSettingProvider.notifier)
        .update((state) => state.copyWith(autoLaunch: true));
    await action.refreshAutoLaunch();
    expect(container.read(appSettingProvider).autoLaunch, isFalse);
    expect(action.writes, isEmpty);
    expect(action.saved, isEmpty);
  });

  test(
    'checks registration and persistence before enabling visible switch',
    () async {
      action.saveBarrier = Completer<void>();
      final operation = action.setAutoLaunch(true);
      await Future<void>.delayed(Duration.zero);
      expect(action.enabled, isTrue);
      expect(container.read(appSettingProvider).autoLaunch, isFalse);
      action.saveBarrier!.complete();
      await operation;
      expect(container.read(appSettingProvider).autoLaunch, isTrue);
      expect(action.saved, [true]);
    },
  );

  test(
    'failed persistence restores registration and leaves switch unchanged',
    () async {
      action.rejectSave = true;
      await expectLater(
        action.setAutoLaunch(true),
        throwsA(isA<AutoLaunchException>()),
      );
      expect(action.enabled, isFalse);
      expect(container.read(appSettingProvider).autoLaunch, isFalse);
      expect(action.writes, [true, false]);
    },
  );

  test(
    'refresh respects externally disabled and enabled startup registration',
    () async {
      action.enabled = true;
      await action.refreshAutoLaunch();
      expect(container.read(appSettingProvider).autoLaunch, isTrue);
      action.enabled = false;
      await action.refreshAutoLaunch();
      expect(container.read(appSettingProvider).autoLaunch, isFalse);
      expect(action.writes, isEmpty);
    },
  );
}

class _AutoLaunchAction extends SystemAction {
  bool enabled = false;
  bool rejectSave = false;
  Completer<void>? saveBarrier;
  final writes = <bool>[];
  final saved = <bool>[];
  late final service = AutoLaunch.withBackend(
    read: () async => enabled,
    write: (value) async {
      writes.add(value);
      enabled = value;
    },
  );

  @override
  AutoLaunch get autoLaunchService => service;

  @override
  Future<void> persistAutoLaunchPreference(bool enabled) async {
    await saveBarrier?.future;
    if (rejectSave) throw StateError('disk full');
    saved.add(enabled);
  }
}

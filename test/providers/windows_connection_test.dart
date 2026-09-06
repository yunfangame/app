import 'dart:async';

import 'package:fl_clash/core/method.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:riverpod/riverpod.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ProviderContainer container;
  late _WindowsSetup action;

  setUp(() {
    container = ProviderContainer(
      overrides: [
        initProvider.overrideWithBuild((_, _) => true),
        commonActionProvider.overrideWith(_QuietCommon.new),
        setupActionProvider.overrideWith(_WindowsSetup.new),
      ],
    );
    action = container.read(setupActionProvider.notifier) as _WindowsSetup;
  });
  tearDown(() => container.dispose());

  test(
    'config and owned listener precede loopback and connected state',
    () async {
      action.prepare = Completer<void>();
      action.start = Completer<bool>();
      action.probe = Completer<void>();
      final pending = action.setRunning(true);
      await action.prepared.future;
      expect(container.read(connectionPendingProvider), isTrue);
      expect(container.read(runTimeProvider), isNull);
      expect(container.read(proxyStateProvider).isStart, isFalse);
      expect(action.events, ['config']);
      action.prepare!.complete();
      await Future<void>.delayed(Duration.zero);
      expect(action.events, ['config', 'start']);
      expect(container.read(isStartProvider), isFalse);
      action.start!.complete(true);
      await Future<void>.delayed(Duration.zero);
      expect(action.events, ['config', 'start', 'probe:7890']);
      expect(container.read(runTimeProvider), isNull);
      action.probe!.complete();
      await pending;
      expect(container.read(connectionPendingProvider), isFalse);
      expect(container.read(isStartProvider), isTrue);
      expect(container.read(proxyStateProvider).isStart, isTrue);
      await action.setRunning(false);
    },
  );

  test(
    'configuration failure never starts and rolls back the switch',
    () async {
      action.prepareFailure = StateError('invalid config');
      container
          .read(networkSettingProvider.notifier)
          .update((value) => value.copyWith(systemProxy: true));
      await action.setRunning(true);
      expect(action.events, ['config', 'stop']);
      expect(action.notifications, 1);
      expect(container.read(runTimeProvider), isNull);
      expect(container.read(connectionPendingProvider), isFalse);
      expect(container.read(networkSettingProvider).systemProxy, isFalse);
    },
  );

  test('false core start never probes or reports connected', () async {
    action.start = Completer<bool>()..complete(false);
    await action.setRunning(true);
    expect(action.events, ['config', 'start', 'stop']);
    expect(action.notifications, 1);
    expect(container.read(isStartProvider), isFalse);
  });

  test('owned listener failure keeps error details and stops', () async {
    action.start = Completer<bool>();
    final pending = action.setRunning(true);
    await Future<void>.delayed(Duration.zero);
    action.start!.completeError(
      const CoreMethodException(
        code: 'listener_not_ready',
        message: 'Listener unavailable',
        details: {'protocol': 'udp', 'port': 7890, 'os_error_code': 10048},
      ),
    );
    await pending;
    expect(action.events, ['config', 'start', 'stop']);
    expect(container.read(isStartProvider), isFalse);
  });

  test('loopback failure stops listener and does not keep counting', () async {
    action.probeFailure = StateError('loopback refused');
    await action.setRunning(true);
    expect(action.events, ['config', 'start', 'probe:7890', 'stop']);
    expect(container.read(runTimeProvider), isNull);
    expect(container.read(connectionPendingProvider), isFalse);
    expect(action.notifications, 1);
  });

  test('stop during config prevents any late listener start', () async {
    action.prepare = Completer<void>();
    final pending = action.setRunning(true);
    await action.prepared.future;
    await action.setRunning(false);
    action.prepare!.complete();
    await pending;
    expect(action.events, ['config', 'stop']);
    expect(container.read(isStartProvider), isFalse);
    expect(action.notifications, 0);
  });

  test('toggle while connecting cancels the current request', () async {
    action.prepare = Completer<void>();
    final pending = action.setRunning(true);
    await action.prepared.future;
    container.read(commonActionProvider.notifier).toggleRunning();
    await Future<void>.delayed(Duration.zero);
    action.prepare!.complete();
    await pending;
    expect(container.read(connectionPendingProvider), isFalse);
    expect(container.read(isStartProvider), isFalse);
    expect(action.events, ['config', 'stop']);
  });

  test('stop during probe cannot become connected on late success', () async {
    action.probe = Completer<void>();
    final pending = action.setRunning(true);
    await Future<void>.delayed(Duration.zero);
    await action.setRunning(false);
    action.probe!.complete();
    await pending;
    expect(container.read(isStartProvider), isFalse);
    expect(container.read(connectionPendingProvider), isFalse);
    expect(action.notifications, 0);
  });

  test('late failure does not roll back a newer successful start', () async {
    final firstProbe = Completer<void>();
    action.probe = firstProbe;
    final first = action.setRunning(true);
    await Future<void>.delayed(Duration.zero);
    await action.setRunning(false);
    action.probe = null;
    await action.setRunning(true);
    expect(container.read(isStartProvider), isTrue);
    firstProbe.completeError(StateError('obsolete refusal'));
    await first;
    expect(container.read(isStartProvider), isTrue);
    expect(action.notifications, 0);
    await action.setRunning(false);
  });

  test('port changed during probe is checked before connection', () async {
    final firstProbe = Completer<void>();
    action.probe = firstProbe;
    final pending = action.setRunning(true);
    await Future<void>.delayed(Duration.zero);
    container
        .read(patchClashConfigProvider.notifier)
        .update((value) => value.copyWith(mixedPort: 7891));
    action.probe = null;
    firstProbe.complete();
    await pending;
    expect(action.events, [
      'config',
      'start',
      'probe:7890',
      'config',
      'start',
      'probe:7891',
    ]);
    expect(container.read(isStartProvider), isTrue);
    await action.setRunning(false);
  });

  test(
    'explicit authorized TUN-only mode does not require a mixed port',
    () async {
      container
          .read(patchClashConfigProvider.notifier)
          .update(
            (value) =>
                value.copyWith(mixedPort: 0, tun: const Tun(enable: true)),
          );
      container.read(authorizedTunEnableProvider.notifier).value =
          TunAuthorizationState.authorized;
      container
          .read(networkSettingProvider.notifier)
          .update((value) => value.copyWith(systemProxy: false));
      await action.setRunning(true);
      expect(action.events, ['config', 'start']);
      expect(container.read(isStartProvider), isTrue);
      await action.setRunning(false);
    },
  );

  test(
    'a failed config update clears the connected state and proxy request',
    () async {
      await action.setRunning(true);
      action.updateFailure = const CoreMethodException(
        code: 'listener_not_ready',
        message: 'Local mixed listener is not ready',
        details: {'protocol': 'udp', 'port': 7891, 'os_error_code': 10048},
      );
      await action.updateConfig();
      expect(action.events.last, 'stop');
      expect(container.read(runTimeProvider), isNull);
      expect(container.read(connectionPendingProvider), isFalse);
      expect(container.read(networkSettingProvider).systemProxy, isFalse);
      expect(action.notifications, 1);
    },
  );

  test('late config failure cannot clear a newer connected request', () async {
    await action.setRunning(true);
    final update = Completer<String>();
    action.update = update;
    final oldUpdate = action.updateConfig();
    await Future<void>.delayed(Duration.zero);
    await action.setRunning(false);
    await action.setRunning(true);
    update.completeError(
      const CoreMethodException(
        code: 'listener_not_ready',
        message: 'Old update failed',
      ),
    );
    await oldUpdate;
    expect(container.read(isStartProvider), isTrue);
    expect(action.notifications, 0);
    await action.setRunning(false);
  });

  test(
    'disposal while connecting does not update disposed providers',
    () async {
      action.prepare = Completer<void>();
      final pending = action.setRunning(true);
      await action.prepared.future;
      container.dispose();
      action.prepare!.complete();
      await pending;
      expect(action.events, ['config']);
      expect(action.notifications, 0);
    },
  );

  test(
    'excluded Wi-Fi preserves intent and resumes through readiness',
    () async {
      container.read(excludeSSIDsProvider.notifier).update((_) => ['excluded']);
      container.read(currentSSIDProvider.notifier).value = 'excluded';
      await action.setRunning(true);
      expect(action.events, ['stop']);
      expect(container.read(connectionPendingProvider), isTrue);
      expect(container.read(isStartProvider), isFalse);
      expect(container.read(networkSettingProvider).systemProxy, isTrue);
      expect(action.notifications, 0);
      container.read(currentSSIDProvider.notifier).value = 'allowed';
      await action.refreshSuspension();
      expect(action.events, ['stop', 'config', 'start', 'probe:7890']);
      expect(container.read(isStartProvider), isTrue);
      await action.setRunning(false);
    },
  );

  test('stop while suspended prevents Wi-Fi change from restarting', () async {
    container.read(excludeSSIDsProvider.notifier).update((_) => ['excluded']);
    container.read(currentSSIDProvider.notifier).value = 'excluded';
    await action.setRunning(true);
    await action.setRunning(false);
    container.read(currentSSIDProvider.notifier).value = 'allowed';
    await action.refreshSuspension();
    expect(action.events, ['stop', 'stop']);
    expect(container.read(isStartProvider), isFalse);
    expect(container.read(connectionPendingProvider), isFalse);
  });

  for (final hadRunningRequest in [false, true]) {
    test(
      'stale authorization cannot apply config, prior=$hadRunningRequest',
      () async {
        if (hadRunningRequest) await action.setRunning(true);
        final authorization = Completer<bool>();
        action.authorization = authorization;
        final oldUpdate = action.updateConfig();
        await Future<void>.delayed(Duration.zero);
        await action.setRunning(false);
        await action.setRunning(true);
        authorization.complete(false);
        await oldUpdate;
        expect(action.updateCalls, 0);
        expect(container.read(isStartProvider), isTrue);
        expect(action.notifications, 0);
        await action.setRunning(false);
      },
    );
  }
}

class _WindowsSetup extends SetupAction {
  final events = <String>[];
  final prepared = Completer<void>();
  Completer<void>? prepare;
  Completer<bool>? start;
  Completer<void>? probe;
  Object? prepareFailure;
  Object? probeFailure;
  Object? updateFailure;
  Completer<String>? update;
  Completer<bool>? authorization;
  int updateCalls = 0;
  int notifications = 0;

  @override
  bool get requiresListenerReadiness => true;

  @override
  Future<void> prepareListenerProfile() async {
    events.add('config');
    if (!prepared.isCompleted) prepared.complete();
    await prepare?.future;
    if (prepareFailure != null) throw prepareFailure!;
  }

  @override
  Future<bool> setCoreRunning(bool running) async {
    events.add(running ? 'start' : 'stop');
    return running ? await start?.future ?? true : true;
  }

  @override
  Future<void> verifyLocalListener(
    int port, {
    required bool Function() isCancelled,
  }) async {
    events.add('probe:$port');
    await probe?.future;
    if (probeFailure != null) throw probeFailure!;
  }

  @override
  void notifyListenerFailure(int port) => notifications++;

  @override
  void resetCoreTraffic() {}

  @override
  Future<String> applyCoreUpdate(UpdateParams params) async {
    updateCalls++;
    if (updateFailure != null) throw updateFailure!;
    return await update?.future ?? '';
  }

  @override
  Future<bool> requestAdmin(bool enableTun) async =>
      await authorization?.future ?? true;
}

class _QuietCommon extends CommonAction {
  @override
  Future<void> updateTraffic() async {}
}

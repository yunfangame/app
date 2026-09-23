import 'dart:async';

import 'package:fl_clash/common/desktop_proxy_failure.dart';
import 'package:fl_clash/core/method.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/widgets/desktop_proxy_failure_dialog.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:riverpod/riverpod.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late ProviderContainer container;
  late _Setup setup;
  late _Recovery recovery;
  late List<String> events;

  setUp(() {
    events = [];
    setup = _Setup(events);
    recovery = _Recovery(events);
    container = ProviderContainer(
      overrides: [
        initProvider.overrideWithBuild((_, _) => true),
        commonActionProvider.overrideWith(_Common.new),
        setupActionProvider.overrideWith(() => setup),
        desktopProxyActionProvider.overrideWith(() => recovery),
      ],
    );
    container.read(desktopProxyActionProvider);
  });
  tearDown(() => container.dispose());

  DesktopProxyFailure failure() => DesktopProxyFailure.fromError(
    const CoreMethodException(
      code: 'listener_not_ready',
      message: 'Local mixed listener is not ready',
      details: {'listener': 'mixed', 'reason': 'address_in_use'},
    ),
    port: 7890,
  );

  test(
    'port change clears old proxy and persists before starting new listener',
    () async {
      await recovery.reconnect(port: 7891);
      expect(
        events,
        containsAllInOrder([
          'stop',
          'cleanup:7890',
          'persist:7891',
          'prepare:7891',
          'start',
          'probe:7891',
        ]),
      );
      expect(container.read(patchClashConfigProvider).mixedPort, 7891);
      expect(container.read(networkSettingProvider).systemProxy, isTrue);
      expect(container.read(isStartProvider), isTrue);
      await setup.setRunning(false);
    },
  );

  test(
    'failed old proxy cleanup leaves the old port and stays stopped',
    () async {
      recovery.cleanupFailure = StateError('cleanup failed');
      await expectLater(recovery.reconnect(port: 7891), throwsStateError);
      expect(container.read(patchClashConfigProvider).mixedPort, 7890);
      expect(events, ['stop', 'cleanup:7890']);
      expect(container.read(isStartProvider), isFalse);
    },
  );

  test(
    'failed persistence does not enable proxy or change the live port',
    () async {
      container
          .read(networkSettingProvider.notifier)
          .update((s) => s.copyWith(systemProxy: false));
      recovery.saveResult = false;
      await expectLater(recovery.reconnect(port: 7891), throwsStateError);
      expect(container.read(patchClashConfigProvider).mixedPort, 7890);
      expect(container.read(networkSettingProvider).systemProxy, isFalse);
      expect(container.read(isStartProvider), isFalse);
      expect(events, isNot(contains('start')));
    },
  );

  test('a newer stop cancels a port change awaiting cleanup', () async {
    recovery.cleanup = Completer<void>();
    final reconnect = recovery.reconnect(port: 7891);
    await recovery.cleanupEntered.future;
    await setup.setRunning(false);
    recovery.cleanup!.complete();
    await reconnect;
    expect(container.read(patchClashConfigProvider).mixedPort, 7890);
    expect(events, isNot(contains('persist:7891')));
    expect(events, isNot(contains('start')));
  });

  test('a newer start is not restarted by an old recovery', () async {
    recovery.cleanup = Completer<void>();
    final reconnect = recovery.reconnect(port: 7891);
    await recovery.cleanupEntered.future;
    await setup.setRunning(true);
    recovery.cleanup!.complete();
    await reconnect;
    expect(container.read(patchClashConfigProvider).mixedPort, 7890);
    expect(events.where((e) => e == 'start'), hasLength(1));
    await setup.setRunning(false);
  });

  test('invalid and reserved ports are rejected before stopping', () async {
    container
        .read(patchClashConfigProvider.notifier)
        .update((s) => s.copyWith(socksPort: 7892));
    for (final port in [0, 1023, 49152, 7892]) {
      await expectLater(recovery.reconnect(port: port), throwsArgumentError);
    }
    expect(events, isEmpty);
  });

  test(
    'an obsolete cleanup exception cannot surface on a newer connection',
    () async {
      recovery.cleanup = Completer<void>();
      recovery.cleanupFailure = StateError('old cleanup failure');
      final reconnect = recovery.reconnect(port: 7891);
      await recovery.cleanupEntered.future;
      await setup.setRunning(true);
      recovery.cleanup!.complete();
      await reconnect;
      expect(recovery.dialogCount, 0);
      expect(container.read(isStartProvider), isTrue);
      expect(container.read(patchClashConfigProvider).mixedPort, 7890);
      await setup.setRunning(false);
    },
  );

  test(
    'an obsolete save failure cannot prompt a new connection to restart',
    () async {
      recovery.saving = Completer<void>();
      recovery.saveResult = false;
      final reconnect = recovery.reconnect(port: 7891);
      await recovery.saveEntered.future;
      await setup.setRunning(true);
      recovery.saving!.complete();
      await reconnect;
      expect(recovery.dialogCount, 0);
      expect(container.read(isStartProvider), isTrue);
      expect(container.read(patchClashConfigProvider).mixedPort, 7890);
      await setup.setRunning(false);
    },
  );

  test(
    'a stop while saving restores the current preferences without starting',
    () async {
      recovery.saving = Completer<void>();
      final reconnect = recovery.reconnect(port: 7891);
      await recovery.saveEntered.future;
      await setup.setRunning(false);
      recovery.saving!.complete();
      await reconnect;
      expect(recovery.savedPorts, [7891, 7890]);
      expect(container.read(patchClashConfigProvider).mixedPort, 7890);
      expect(events, isNot(contains('start')));
    },
  );

  test(
    'saving a port cannot revert a concurrent routing preference change',
    () async {
      recovery.saving = Completer<void>();
      final reconnect = recovery.reconnect(port: 7891);
      await recovery.saveEntered.future;
      container
          .read(patchClashConfigProvider.notifier)
          .update((s) => s.copyWith(mode: Mode.global));
      recovery.saving!.complete();
      await reconnect;
      expect(container.read(patchClashConfigProvider).mixedPort, 7891);
      expect(container.read(patchClashConfigProvider).mode, Mode.global);
      await setup.setRunning(false);
    },
  );

  test('failure dialog dismissal leaves settings unchanged', () async {
    await recovery.reportFailure(failure());
    expect(recovery.dialogCount, 1);
    expect(events, isEmpty);
    expect(container.read(patchClashConfigProvider).mixedPort, 7890);
  });

  test(
    'duplicate failures share one dialog and stale answers are ignored',
    () async {
      recovery.choice = Completer<DesktopProxyFailureChoice?>();
      final prompt = recovery.reportFailure(failure());
      await recovery.reportFailure(failure());
      expect(recovery.dialogCount, 1);
      await setup.setRunning(false);
      recovery.choice!.complete(DesktopProxyFailureChoice.retry);
      await prompt;
      expect(events, ['stop']);
    },
  );

  test('changing the port from the dialog reconnects with that port', () async {
    recovery.choice = Completer<DesktopProxyFailureChoice?>()
      ..complete(DesktopProxyFailureChoice.changePort);
    recovery.selectedPort = 7893;
    await recovery.reportFailure(failure());
    expect(container.read(patchClashConfigProvider).mixedPort, 7893);
    expect(container.read(isStartProvider), isTrue);
    await setup.setRunning(false);
  });

  test(
    'disposing while awaiting a dialog does not restart the connection',
    () async {
      recovery.choice = Completer<DesktopProxyFailureChoice?>();
      final prompt = recovery.reportFailure(failure());
      container.dispose();
      recovery.choice!.complete(DesktopProxyFailureChoice.retry);
      await prompt;
      expect(events, isEmpty);
    },
  );
}

class _Common extends CommonAction {
  @override
  Future<void> updateTraffic() async {}
}

class _Setup extends SetupAction {
  _Setup(this.events);
  final List<String> events;

  @override
  bool get requiresListenerReadiness => true;

  @override
  bool get requiresWindowsTunAuthorization => false;

  @override
  Future<void> prepareListenerProfile() async {
    events.add('prepare:${ref.read(patchClashConfigProvider).mixedPort}');
  }

  @override
  Future<bool> setCoreRunning(bool running) async {
    events.add(running ? 'start' : 'stop');
    return true;
  }

  @override
  Future<void> verifyLocalListener(
    int port, {
    required bool Function() isCancelled,
  }) async {
    events.add('probe:$port');
  }

  @override
  void resetCoreTraffic() {}

  @override
  Future<void> resetResolverConnections() async {}
}

class _Recovery extends DesktopProxyAction {
  _Recovery(this.events);
  final List<String> events;
  final cleanupEntered = Completer<void>();
  Completer<void>? cleanup;
  Object? cleanupFailure;
  bool saveResult = true;
  final saveEntered = Completer<void>();
  Completer<void>? saving;
  final savedPorts = <int>[];
  int dialogCount = 0;
  Completer<DesktopProxyFailureChoice?>? choice;
  int? selectedPort;

  @override
  Future<void> clearPreviousSystemProxy({
    required bool Function() isCurrent,
  }) async {
    events.add('cleanup:${ref.read(patchClashConfigProvider).mixedPort}');
    if (!cleanupEntered.isCompleted) cleanupEntered.complete();
    await cleanup?.future;
    if (cleanupFailure != null) throw cleanupFailure!;
  }

  @override
  Future<bool> persistPort(Config config) async {
    events.add('persist:${config.patchClashConfig.mixedPort}');
    savedPorts.add(config.patchClashConfig.mixedPort);
    if (!saveEntered.isCompleted) saveEntered.complete();
    await saving?.future;
    return saveResult;
  }

  @override
  Future<DesktopProxyFailureChoice?> chooseFailureAction(
    DesktopProxyFailure failure,
  ) async {
    dialogCount++;
    return choice?.future;
  }

  @override
  Future<int?> choosePort(int currentPort) async => selectedPort;
}

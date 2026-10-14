import 'dart:async';

import 'package:fl_clash/providers/action.dart';
import 'package:fl_clash/providers/actions/system_exit.dart';
import 'package:fl_clash/l10n/l10n.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/providers/app.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:riverpod/riverpod.dart';

void main() {
  setUpAll(() => AppLocalizations.load(const Locale('zh', 'CN')));

  testWidgets('a timed-out preparation never exits when it completes late', (
    tester,
  ) async {
    final prepared = Completer<void>();
    var exits = 0;
    final coordinator = SystemExitCoordinator(
      watchdogDuration: const Duration(seconds: 3),
      preparationTimeout: const Duration(seconds: 5),
      prepareExit: () => prepared.future,
      closeWindow: () async {},
      closeCore: () async {},
      exitApplication: () async => exits++,
    );
    final outcome = expectLater(
      coordinator.exit(cleanup: () async {}),
      throwsA(isA<TimeoutException>()),
    );
    await tester.pump(const Duration(seconds: 6));
    await outcome;
    expect(exits, 0);
    prepared.complete();
    await tester.pump(const Duration(seconds: 10));
    expect(exits, 0);
    await coordinator.exit(cleanup: () async {});
    expect(exits, 1);
  });

  for (final connected in [false, true]) {
    test(
      'exit prepares the network before closing: connected=$connected',
      () async {
        final action = _ExitAction();
        final setup = _ExitSetup();
        final container = ProviderContainer(
          overrides: [
            systemActionProvider.overrideWith(() => action),
            setupActionProvider.overrideWith(() => setup),
            coreStatusProvider.overrideWithBuild(
              (_, _) =>
                  connected ? CoreStatus.connected : CoreStatus.disconnected,
            ),
          ],
        );
        addTearDown(container.dispose);
        final operation = container
            .read(systemActionProvider.notifier)
            .handleExit();
        await Future<void>.delayed(Duration.zero);
        expect(action.calls, ['dns', 'proxy:exit']);
        expect(setup.requests, connected ? [false] : isEmpty);
        action.proxyReady.complete();
        if (connected) {
          await Future<void>.delayed(Duration.zero);
          expect(action.calls, ['dns', 'proxy:exit']);
        }
        setup.stopped.complete();
        await operation;
        expect(action.calls, [
          'dns',
          'proxy:exit',
          if (!connected) 'core',
          'residual:exit',
          'cleanup',
          'window',
          'core',
          'exit',
        ]);
      },
    );
  }

  test('exit cleanup failure reports and retries without closing', () async {
    final action = _ExitAction()..failProxy = true;
    final container = ProviderContainer(
      overrides: [
        systemActionProvider.overrideWith(() => action),
        coreStatusProvider.overrideWithBuild((_, _) => CoreStatus.disconnected),
      ],
    );
    addTearDown(container.dispose);
    await expectLater(
      container.read(systemActionProvider.notifier).handleExit(),
      throwsA(isA<NetworkCleanupException>()),
    );
    expect(action.calls, ['dns', 'proxy:exit', 'report']);
    action.failProxy = false;
    action.proxyReady.complete();
    await container.read(systemActionProvider.notifier).handleExit();
    expect(action.calls, [
      'dns',
      'proxy:exit',
      'report',
      'dns',
      'proxy:exit',
      'core',
      'residual:exit',
      'cleanup',
      'window',
      'core',
      'exit',
    ]);
  });

  test('residual verification failure cannot complete exit', () async {
    final action = _ExitAction()..failResidual = true;
    action.proxyReady.complete();
    final container = ProviderContainer(
      overrides: [
        systemActionProvider.overrideWith(() => action),
        coreStatusProvider.overrideWithBuild((_, _) => CoreStatus.disconnected),
      ],
    );
    addTearDown(container.dispose);
    await expectLater(
      container.read(systemActionProvider.notifier).handleExit(),
      throwsA(isA<NetworkCleanupException>()),
    );
    expect(action.calls, [
      'dns',
      'proxy:exit',
      'core',
      'residual:exit',
      'report',
    ]);
    action.failResidual = false;
    await container.read(systemActionProvider.notifier).handleExit();
    expect(action.calls.last, 'exit');
  });

  testWidgets('network preparation is not interrupted by the exit watchdog', (
    tester,
  ) async {
    final prepared = Completer<void>();
    final coreClosed = Completer<void>();
    final calls = <String>[];
    final coordinator = SystemExitCoordinator(
      watchdogDuration: const Duration(seconds: 3),
      prepareExit: () async {
        calls.add('prepare');
        await prepared.future;
      },
      closeWindow: () async => calls.add('window'),
      closeCore: () async {
        calls.add('core');
        await coreClosed.future;
      },
      exitApplication: () async => calls.add('exit'),
    );
    final first = coordinator.exit(cleanup: () async => calls.add('cleanup'));
    final second = coordinator.exit(
      cleanup: () async => calls.add('duplicate'),
    );
    expect(identical(first, second), isTrue);
    await tester.pump(const Duration(seconds: 10));
    expect(calls, ['prepare']);
    expect(coordinator.applicationExitRequested, isFalse);
    prepared.complete();
    await tester.pump(Duration.zero);
    expect(calls, ['prepare', 'cleanup', 'window', 'core']);
    await tester.pump(const Duration(seconds: 3));
    expect(calls.last, 'exit');
    coreClosed.complete();
    await first;
    expect(calls.where((call) => call == 'exit'), hasLength(1));
  });

  test(
    'failed network cleanup cancels exit and allows a verified retry',
    () async {
      var attempts = 0;
      final calls = <String>[];
      final phases = <String>[];
      final coordinator = SystemExitCoordinator(
        watchdogDuration: const Duration(hours: 1),
        prepareExit: () async {
          calls.add('prepare');
          if (++attempts == 1) throw StateError('Proxy restore failed');
        },
        onPhase: phases.add,
        closeWindow: () async => calls.add('window'),
        closeCore: () async => calls.add('core'),
        exitApplication: () async => calls.add('exit'),
      );
      await expectLater(
        coordinator.exit(cleanup: () async => calls.add('cleanup')),
        throwsStateError,
      );
      expect(calls, ['prepare']);
      expect(phases, ['prepare', 'prepare_failed']);
      expect(coordinator.applicationExitRequested, isFalse);
      await coordinator.exit(cleanup: () async => calls.add('cleanup'));
      expect(calls, [
        'prepare',
        'prepare',
        'cleanup',
        'window',
        'core',
        'exit',
      ]);
      expect(coordinator.applicationExitRequested, isTrue);
    },
  );

  test('coalesces repeated exit requests and runs cleanup once', () async {
    final closeCoreCompleter = Completer<void>();
    final calls = <String>[];
    final coordinator = SystemExitCoordinator(
      watchdogDuration: const Duration(hours: 1),
      closeWindow: () async => calls.add('window'),
      closeCore: () async {
        calls.add('core');
        await closeCoreCompleter.future;
      },
      exitApplication: () async => calls.add('exit'),
    );

    final first = coordinator.exit(cleanup: () async => calls.add('cleanup'));
    final second = coordinator.exit(
      cleanup: () async => calls.add('unexpected cleanup'),
    );
    await Future<void>.delayed(Duration.zero);

    expect(identical(first, second), isTrue);
    expect(calls, ['cleanup', 'window', 'core']);

    closeCoreCompleter.complete();
    await Future.wait([first, second]);

    expect(calls, ['cleanup', 'window', 'core', 'exit']);
  });

  test('watchdog and normal completion share one application exit', () async {
    final closeCoreCompleter = Completer<void>();
    var exitCount = 0;
    final coordinator = SystemExitCoordinator(
      watchdogDuration: const Duration(milliseconds: 1),
      closeWindow: () async {},
      closeCore: () => closeCoreCompleter.future,
      exitApplication: () async => exitCount++,
    );

    final operation = coordinator.exit(cleanup: () async {});
    await Future<void>.delayed(const Duration(milliseconds: 10));

    expect(exitCount, 1);
    closeCoreCompleter.complete();
    await operation;
    expect(exitCount, 1);
  });

  test('cleanup failure does not skip window or Core shutdown', () async {
    final calls = <String>[];
    final coordinator = SystemExitCoordinator(
      watchdogDuration: const Duration(hours: 1),
      closeWindow: () async => calls.add('window'),
      closeCore: () async => calls.add('core'),
      exitApplication: () async => calls.add('exit'),
    );

    await expectLater(
      coordinator.exit(
        cleanup: () async {
          calls.add('cleanup');
          throw StateError('cleanup failed');
        },
      ),
      throwsStateError,
    );

    expect(calls, ['cleanup', 'window', 'core', 'exit']);
  });

  test('logout stops runtime and cleans integrations concurrently', () async {
    final stopCompleter = Completer<void>();
    final action = _TestSystemAction(stopCompleter: stopCompleter);
    final container = ProviderContainer(
      overrides: [systemActionProvider.overrideWith(() => action)],
    );
    addTearDown(container.dispose);

    final operation = container
        .read(systemActionProvider.notifier)
        .handleLogout();
    await Future<void>.delayed(Duration.zero);

    expect(action.calls, ['stop', 'integrations']);
    stopCompleter.complete();
    await operation;
  });

  test(
    'logout cleanup failure is reported after runtime stop completes',
    () async {
      final stopped = Completer<void>();
      final action = _TestSystemAction(stopCompleter: stopped)
        ..failIntegrations = true;
      final container = ProviderContainer(
        overrides: [systemActionProvider.overrideWith(() => action)],
      );
      addTearDown(container.dispose);
      var completed = false;
      final operation = container
          .read(systemActionProvider.notifier)
          .handleLogout()
          .whenComplete(() => completed = true);
      final outcome = expectLater(
        operation,
        throwsA(isA<NetworkCleanupException>()),
      );
      await Future<void>.delayed(Duration.zero);
      expect(completed, isFalse);
      expect(action.calls, ['stop', 'integrations']);
      stopped.complete();
      await outcome;
      action.failIntegrations = false;
      await container.read(systemActionProvider.notifier).handleLogout();
      expect(action.calls, ['stop', 'integrations', 'stop', 'integrations']);
    },
  );

  test('tray visibility follows authentication state', () async {
    final action = _TestSystemAction();
    final container = ProviderContainer(
      overrides: [systemActionProvider.overrideWith(() => action)],
    );
    addTearDown(container.dispose);

    await container.read(systemActionProvider.notifier).updateTray();
    expect(action.destroyCount, 1);
    expect(action.renderCount, 0);

    action.authenticated = true;
    await container.read(systemActionProvider.notifier).updateTray();
    expect(action.destroyCount, 1);
    expect(action.renderCount, 1);
  });
}

class _ExitAction extends SystemAction {
  final calls = <String>[];
  final proxyReady = Completer<void>();
  bool failProxy = false;
  bool failResidual = false;

  @override
  Future<void> restoreDnsForExit() async => calls.add('dns');

  @override
  Future<void> repairResidualSystemProxy(String reason) async {
    calls.add('residual:$reason');
    if (failResidual) throw StateError('Residual proxy verification failed');
  }

  @override
  Future<void> cleanupSystemProxy(String reason) async {
    calls.add('proxy:$reason');
    if (failProxy) throw StateError('Proxy restore failed');
    await proxyReady.future;
  }

  @override
  Future<void> reportExitCleanupFailure() async => calls.add('report');

  @override
  Future<void> cleanupExitResources(bool needSave) async =>
      calls.add('cleanup');

  @override
  Future<void> closeWindow() async => calls.add('window');

  @override
  Future<void> closeCore() async => calls.add('core');

  @override
  Future<void> exitApplication() async => calls.add('exit');
}

class _ExitSetup extends SetupAction {
  final requests = <bool>[];
  final stopped = Completer<void>();

  @override
  Future<void> setRunning(
    bool running, {
    bool initialize = false,
    bool propagateErrors = false,
  }) {
    requests.add(running);
    return stopped.future;
  }
}

class _TestSystemAction extends SystemAction {
  final Completer<void>? stopCompleter;
  final calls = <String>[];
  bool authenticated = false;
  bool failIntegrations = false;
  int destroyCount = 0;
  int renderCount = 0;

  _TestSystemAction({this.stopCompleter});

  @override
  bool get hasAuthenticatedSession => authenticated;

  @override
  Future<void> stopRunningForLogout() async {
    calls.add('stop');
    await stopCompleter?.future;
  }

  @override
  Future<void> cleanupLogoutIntegrations() async {
    calls.add('integrations');
    if (failIntegrations) throw StateError('Proxy restore failed');
  }

  @override
  Future<void> repairResidualSystemProxy(String reason) async {}

  @override
  Future<void> destroyTray() async {
    destroyCount++;
  }

  @override
  Future<void> renderTray() async {
    renderCount++;
  }
}

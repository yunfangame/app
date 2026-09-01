import 'dart:async';

import 'package:fl_clash/providers/action.dart';
import 'package:fl_clash/providers/actions/system_exit.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:riverpod/riverpod.dart';

void main() {
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

class _TestSystemAction extends SystemAction {
  final Completer<void>? stopCompleter;
  final calls = <String>[];
  bool authenticated = false;
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
  }

  @override
  Future<void> destroyTray() async {
    destroyCount++;
  }

  @override
  Future<void> renderTray() async {
    renderCount++;
  }
}

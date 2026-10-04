import 'dart:async';
import 'dart:convert';

import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/state.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:riverpod/riverpod.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('autoRun persistence', () {
    test('defaults to disabled for new and existing config', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      expect(const AppSettingProps().autoRun, isFalse);
      expect(container.read(appSettingProvider).autoRun, isFalse);
      expect(container.read(configProvider).appSettingProps.autoRun, isFalse);
      expect(Config.fromJson({}).appSettingProps.autoRun, isFalse);
      expect(
        Config.fromJson({
          'appSettingProps': <String, Object?>{},
        }).appSettingProps.autoRun,
        isFalse,
      );
    });

    for (final autoRun in [false, true]) {
      test('persists autoRun=$autoRun through Config JSON', () {
        final container = ProviderContainer();
        addTearDown(container.dispose);
        container
            .read(appSettingProvider.notifier)
            .update((settings) => settings.copyWith(autoRun: autoRun));

        final json =
            jsonDecode(jsonEncode(container.read(configProvider).toJson()))
                as Map<String, Object?>;
        final restored = Config.fromJson(json);
        final restoredContainer = ProviderContainer(
          overrides: buildConfigOverrides(restored),
        );
        addTearDown(restoredContainer.dispose);

        expect(
          (json['appSettingProps'] as Map<String, Object?>)['autoRun'],
          autoRun,
        );
        expect(restored.appSettingProps.autoRun, autoRun);
        expect(restoredContainer.read(appSettingProvider).autoRun, autoRun);
        expect(
          restoredContainer.read(configProvider).appSettingProps.autoRun,
          autoRun,
        );
      });
    }
  });

  test(
    'initStatus applies the profile without starting when autoRun is on',
    () async {
      final previousNeedInitStatus = globalState.needInitStatus;
      globalState.needInitStatus = true;
      addTearDown(() => globalState.needInitStatus = previousNeedInitStatus);
      final setup = _RecordingSetupAction();
      final container = ProviderContainer(
        overrides: [
          appSettingProvider.overrideWithBuild(
            (_, _) => const AppSettingProps(autoRun: true),
          ),
          setupActionProvider.overrideWith(() => setup),
        ],
      );
      addTearDown(container.dispose);

      await container.read(setupActionProvider.notifier).initStatus();

      expect(container.read(appSettingProvider).autoRun, isTrue);
      expect(setup.profileApplications, [(force: true, silence: false)]);
      expect(setup.preloadInvocations, isEmpty);
      expect(setup.manualStarts, isEmpty);
      expect(setup.automaticStarts, 0);
      expect(container.read(isStartProvider), isFalse);
      expect(container.read(connectionPendingProvider), isFalse);
    },
  );

  group('CommonAction.startAfterLogin', () {
    for (final scenario in [
      (
        name: 'stale session',
        current: false,
        initialized: true,
        running: false,
        pending: false,
      ),
      (
        name: 'uninitialized profile',
        current: true,
        initialized: false,
        running: false,
        pending: false,
      ),
      (
        name: 'already running',
        current: true,
        initialized: true,
        running: true,
        pending: false,
      ),
      (
        name: 'pending connection',
        current: true,
        initialized: true,
        running: false,
        pending: true,
      ),
    ]) {
      test('does not start with ${scenario.name}', () async {
        final setup = _RecordingSetupAction();
        final container = _loginContainer(
          setup,
          initialized: scenario.initialized,
          running: scenario.running,
          pending: scenario.pending,
        );

        await container
            .read(commonActionProvider.notifier)
            .startAfterLogin(isCurrent: () => scenario.current);

        expect(setup.automaticStarts, 0);
        expect(setup.manualStarts, isEmpty);
        expect(container.read(networkSettingProvider).systemProxy, isFalse);
      });
    }

    test('rechecks the session immediately before starting', () async {
      final setup = _RecordingSetupAction();
      final container = _loginContainer(setup);
      var currentChecks = 0;

      await container
          .read(commonActionProvider.notifier)
          .startAfterLogin(isCurrent: () => ++currentChecks == 1);

      expect(currentChecks, 2);
      expect(setup.automaticStarts, 0);
      expect(setup.manualStarts, isEmpty);
      expect(container.read(networkSettingProvider).systemProxy, isFalse);
    });

    test('ignores a request after its provider is disposed', () async {
      final setup = _RecordingSetupAction();
      final container = ProviderContainer(
        overrides: [setupActionProvider.overrideWith(() => setup)],
      );
      final action = container.read(commonActionProvider.notifier);
      container.dispose();
      var currentChecks = 0;

      await action.startAfterLogin(isCurrent: () => ++currentChecks > 0);

      expect(currentChecks, 0);
      expect(setup.automaticStarts, 0);
      expect(setup.manualStarts, isEmpty);
    });

    test(
      'awaits automatic startup without enabling the system proxy',
      () async {
        final completion = Completer<void>();
        final setup = _RecordingSetupAction()..automaticCompletion = completion;
        final container = _loginContainer(setup);
        final systemProxyChanges = <bool>[];
        final subscription = container.listen(
          networkSettingProvider.select((settings) => settings.systemProxy),
          (_, next) => systemProxyChanges.add(next),
        );
        addTearDown(subscription.close);
        var completed = false;

        final operation = container
            .read(commonActionProvider.notifier)
            .startAfterLogin(isCurrent: () => true)
            .then((_) => completed = true);

        expect(setup.automaticStarts, 1);
        expect(setup.manualStarts, isEmpty);
        expect(completed, isFalse);
        expect(container.read(networkSettingProvider).systemProxy, isFalse);
        completion.complete();
        await operation;

        expect(completed, isTrue);
        expect(setup.automaticStarts, 1);
        expect(container.read(networkSettingProvider).systemProxy, isFalse);
        expect(systemProxyChanges, isEmpty);
      },
    );
  });

  test(
    'automatic startup preserves revisions and manual transitions advance them',
    () async {
      final setup = _RunningSetupAction();
      final traffic = _TrafficCommonAction();
      final container = ProviderContainer(
        overrides: [
          initProvider.overrideWithBuild((_, _) => true),
          suspendProvider.overrideWithValue(false),
          networkSettingProvider.overrideWithBuild(
            (_, _) => const NetworkProps(systemProxy: false),
          ),
          setupActionProvider.overrideWith(() => setup),
          commonActionProvider.overrideWith(() => traffic),
        ],
      );
      addTearDown(container.dispose);
      final action = container.read(setupActionProvider.notifier);
      final proxies = container.read(proxiesActionProvider.notifier);
      proxies.cancelHongKongSelection(manual: true);
      final manualRevision = proxies.manualSelectionRevision;
      final selectionRevision = proxies.hongKongSelectionRevision;

      await action.startAutomatically();

      expect(setup.transitions, [true]);
      expect(setup.profileApplications, [(force: true, silence: true)]);
      expect(container.read(isStartProvider), isTrue);
      expect(container.read(networkSettingProvider).systemProxy, isFalse);
      expect(proxies.manualSelectionRevision, manualRevision);
      expect(proxies.hongKongSelectionRevision, selectionRevision);
      expect(traffic.updates, 1);

      await action.setRunning(false);

      expect(setup.transitions, [true, false]);
      expect(container.read(isStartProvider), isFalse);
      expect(setup.trafficResets, 1);
      expect(proxies.manualSelectionRevision, manualRevision + 1);
      expect(proxies.hongKongSelectionRevision, selectionRevision + 1);

      await action.setRunning(true);

      expect(setup.transitions, [true, false, true]);
      expect(container.read(isStartProvider), isTrue);
      expect(proxies.manualSelectionRevision, manualRevision + 2);
      expect(proxies.hongKongSelectionRevision, selectionRevision + 2);
      expect(container.read(networkSettingProvider).systemProxy, isFalse);
    },
  );

  test('exit cancels automatic selection before cleanup completes', () async {
    final system = _ExitSystemAction();
    final container = ProviderContainer(
      overrides: [systemActionProvider.overrideWith(() => system)],
    );
    addTearDown(container.dispose);
    final proxies = container.read(proxiesActionProvider.notifier);
    final manualRevision = proxies.manualSelectionRevision;
    final selectionRevision = proxies.hongKongSelectionRevision;

    final operation = container
        .read(systemActionProvider.notifier)
        .handleExit();

    try {
      expect(proxies.manualSelectionRevision, manualRevision + 1);
      expect(proxies.hongKongSelectionRevision, selectionRevision + 1);
      expect(system.calls, ['cleanup']);
      expect(system.cleanupCompletion.isCompleted, isFalse);
    } finally {
      system.cleanupCompletion.complete();
      await operation;
    }

    expect(system.calls, ['cleanup', 'window', 'core', 'exit']);
  });
}

ProviderContainer _loginContainer(
  _RecordingSetupAction setup, {
  bool initialized = true,
  bool running = false,
  bool pending = false,
}) {
  final container = ProviderContainer(
    overrides: [
      initProvider.overrideWithBuild((_, _) => initialized),
      runTimeProvider.overrideWithBuild((_, _) => running ? 1000 : null),
      connectionPendingProvider.overrideWithBuild((_, _) => pending),
      networkSettingProvider.overrideWithBuild(
        (_, _) => const NetworkProps(systemProxy: false),
      ),
      setupActionProvider.overrideWith(() => setup),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

class _RecordingSetupAction extends SetupAction {
  int automaticStarts = 0;
  final manualStarts = <({bool running, bool initialize})>[];
  final profileApplications = <({bool force, bool silence})>[];
  final preloadInvocations = <Future<void> Function()>[];
  Completer<void>? automaticCompletion;

  @override
  Future<void> startAutomatically() async {
    automaticStarts++;
    await automaticCompletion?.future;
  }

  @override
  Future<void> setRunning(bool running, {bool initialize = false}) async {
    manualStarts.add((running: running, initialize: initialize));
  }

  @override
  Future<void> applyProfile({
    bool silence = false,
    bool force = false,
    Future<void> Function()? preloadInvoke,
  }) async {
    profileApplications.add((force: force, silence: silence));
    if (preloadInvoke != null) preloadInvocations.add(preloadInvoke);
  }
}

class _RunningSetupAction extends SetupAction {
  final transitions = <bool>[];
  final profileApplications = <({bool force, bool silence})>[];
  int trafficResets = 0;

  @override
  bool get requiresListenerReadiness => false;

  @override
  Future<bool> setCoreRunning(bool running) async {
    transitions.add(running);
    return true;
  }

  @override
  void applyProfileDebounce({bool silence = false, bool force = false}) {
    profileApplications.add((force: force, silence: silence));
  }

  @override
  void resetCoreTraffic() {
    trafficResets++;
  }
}

class _TrafficCommonAction extends CommonAction {
  int updates = 0;

  @override
  Future<void> updateTraffic() async {
    updates++;
  }
}

class _ExitSystemAction extends SystemAction {
  final cleanupCompletion = Completer<void>();
  final calls = <String>[];

  @override
  Duration get exitWatchdogDuration => const Duration(hours: 1);

  @override
  Future<void> cleanupExitResources(bool needSave) async {
    calls.add('cleanup');
    await cleanupCompletion.future;
  }

  @override
  Future<void> closeWindow() async {
    calls.add('window');
  }

  @override
  Future<void> closeCore() async {
    calls.add('core');
  }

  @override
  Future<void> exitApplication() async {
    calls.add('exit');
  }
}

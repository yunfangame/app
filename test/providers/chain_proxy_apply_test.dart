import 'dart:async';
import 'dart:io';

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/core/desktop/model.dart';
import 'package:fl_clash/database/database.dart' show database;
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/action.dart';
import 'package:fl_clash/providers/app.dart';
import 'package:fl_clash/providers/state.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:riverpod/riverpod.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;

  setUpAll(() async {
    directory = await Directory.systemTemp.createTemp('chain_proxy_apply_test');
    PathProviderPlatform.instance = _TestPathProvider(directory.path);
  });

  tearDownAll(() async {
    await database.close();
    await commonPrint.flushDiagnosticEvents();
    await directory.delete(recursive: true);
  });

  test(
    'Windows hot applies a running Core without lifecycle changes',
    () async {
      final harness = _Harness(connected: true, running: true);
      addTearDown(harness.container.dispose);
      harness.container.read(windowsTunReadyProvider.notifier).value = true;

      await harness.core.applyChainProxyConfiguration();

      expect(harness.events, ['apply']);
      expect(harness.setup.force, isTrue);
      expect(harness.setup.propagateErrors, isTrue);
      expect(harness.setup.setRunningCount, 0);
      expect(harness.container.read(coreStatusProvider), CoreStatus.connected);
      expect(harness.container.read(isStartProvider), isTrue);
      expect(harness.container.read(windowsTunReadyProvider), isTrue);
    },
  );

  test(
    'Windows hot applies a stopped Core without starting listeners',
    () async {
      final harness = _Harness(connected: true);
      addTearDown(harness.container.dispose);

      await harness.core.applyChainProxyConfiguration();

      expect(harness.events, ['apply']);
      expect(harness.setup.setRunningCount, 0);
      expect(harness.container.read(isStartProvider), isFalse);
      expect(harness.container.read(windowsTunReadyProvider), isFalse);
    },
  );

  test(
    'Windows recovers and initializes a disconnected Core before apply',
    () async {
      final harness = _Harness();
      addTearDown(harness.container.dispose);

      await harness.core.applyChainProxyConfiguration();

      expect(harness.events, ['start', 'init', 'apply']);
      expect(harness.setup.setRunningCount, 0);
      expect(harness.container.read(coreStatusProvider), CoreStatus.connected);
      expect(harness.container.read(isStartProvider), isFalse);
    },
  );

  test('Windows waits for the configuration reply before completing', () async {
    final harness = _Harness(connected: true);
    addTearDown(harness.container.dispose);
    final applied = Completer<void>();
    final entered = Completer<void>();
    harness.setup.onApply = () async {
      entered.complete();
      await applied.future;
    };
    var completed = false;

    final operation = harness.core.applyChainProxyConfiguration().then((_) {
      completed = true;
    });
    await entered.future;
    expect(completed, isFalse);
    applied.complete();
    await operation;
    expect(completed, isTrue);
  });

  test(
    'Windows propagates apply failure so the caller can roll back',
    () async {
      final harness = _Harness(connected: true, running: true);
      addTearDown(harness.container.dispose);
      final failure = StateError('chain configuration rejected');
      harness.setup.onApply = () async => throw failure;

      await expectLater(
        harness.core.applyChainProxyConfiguration(),
        throwsA(same(failure)),
      );

      expect(harness.events, ['apply']);
      expect(harness.setup.setRunningCount, 0);
      expect(harness.container.read(isStartProvider), isTrue);
    },
  );

  test('Windows does not apply when Core initialization fails', () async {
    final harness = _Harness();
    addTearDown(harness.container.dispose);
    harness.core.initialized = false;

    await expectLater(
      harness.core.applyChainProxyConfiguration(),
      throwsA(
        isA<CorePreparationException>().having(
          (error) => error.code,
          'code',
          'core_init_failed',
        ),
      ),
    );

    expect(harness.events, ['start', 'init']);
    expect(harness.container.read(coreStatusProvider), CoreStatus.disconnected);
  });

  test('Windows does not apply after a superseded Core start', () async {
    final harness = _Harness();
    addTearDown(harness.container.dispose);
    harness.core.startOutcome = CoreLifecycleOutcome.superseded;

    await expectLater(
      harness.core.applyChainProxyConfiguration(),
      throwsA(
        isA<CorePreparationException>().having(
          (error) => error.code,
          'code',
          'core_preparation_superseded',
        ),
      ),
    );

    expect(harness.events, ['start']);
  });

  test('other platforms retain the running Core restart path', () async {
    final harness = _Harness(hotApply: false, connected: true, running: true);
    addTearDown(harness.container.dispose);

    await harness.core.applyChainProxyConfiguration();

    expect(harness.events, ['restart', 'restart_init', 'set_running']);
    expect(harness.setup.setRunningCount, 1);
    expect(harness.setup.setRunningInitialize, isTrue);
    expect(harness.setup.setRunningPropagateErrors, isTrue);
  });

  test('other platforms retain the stopped Core restart path', () async {
    final harness = _Harness(hotApply: false, connected: true);
    addTearDown(harness.container.dispose);

    await harness.core.applyChainProxyConfiguration();

    expect(harness.events, ['restart', 'restart_init', 'apply']);
    expect(harness.setup.force, isTrue);
    expect(harness.setup.propagateErrors, isTrue);
    expect(harness.setup.setRunningCount, 0);
  });
}

class _Harness {
  _Harness({
    bool hotApply = true,
    bool connected = false,
    bool running = false,
  }) {
    core = _TestCoreAction(events, hotApply: hotApply);
    setup = _TestSetupAction(events);
    container = ProviderContainer(
      overrides: [
        coreActionProvider.overrideWith(() => core),
        setupActionProvider.overrideWith(() => setup),
      ],
    );
    if (connected) {
      container.read(coreStatusProvider.notifier).value = CoreStatus.connected;
    }
    if (running) container.read(runTimeProvider.notifier).value = 0;
    container.read(coreActionProvider.notifier);
  }

  final events = <String>[];
  late final _TestCoreAction core;
  late final _TestSetupAction setup;
  late final ProviderContainer container;
}

class _TestCoreAction extends CoreAction {
  _TestCoreAction(this.events, {required this.hotApply});

  final List<String> events;
  final bool hotApply;
  bool initialized = true;
  CoreLifecycleOutcome startOutcome = CoreLifecycleOutcome.applied;

  @override
  bool get requiresChainProxyHotApply => hotApply;

  @override
  Future<CoreLifecycleResult> startLifecycle() async {
    events.add('start');
    return CoreLifecycleResult(revision: 1, outcome: startOutcome);
  }

  @override
  Future<bool> initializeCoreForSubscription() async {
    events.add('init');
    return initialized;
  }

  @override
  Future<CoreLifecycleResult> restartLifecycle() async {
    events.add('restart');
    return const CoreLifecycleResult(
      revision: 1,
      outcome: CoreLifecycleOutcome.applied,
    );
  }

  @override
  Future<CoreLifecycleResult> stopLifecycle() async {
    throw StateError('unexpected lifecycle stop');
  }

  @override
  Future<void> initCore() async {
    events.add('restart_init');
  }
}

class _TestSetupAction extends SetupAction {
  _TestSetupAction(this.events);

  final List<String> events;
  Future<void> Function()? onApply;
  bool? force;
  bool? propagateErrors;
  int setRunningCount = 0;
  bool? setRunningInitialize;
  bool? setRunningPropagateErrors;

  @override
  Future<void> applyProfile({
    bool silence = false,
    bool force = false,
    Future<void> Function()? preloadInvoke,
    bool Function()? isCurrent,
    bool propagateErrors = false,
    Profile? profileOverride,
  }) async {
    events.add('apply');
    this.force = force;
    this.propagateErrors = propagateErrors;
    await onApply?.call();
  }

  @override
  Future<void> setRunning(
    bool running, {
    bool initialize = false,
    bool propagateErrors = false,
  }) async {
    events.add('set_running');
    setRunningCount++;
    setRunningInitialize = initialize;
    setRunningPropagateErrors = propagateErrors;
  }
}

class _TestPathProvider extends PathProviderPlatform {
  _TestPathProvider(this.root);

  final String root;

  @override
  Future<String?> getTemporaryPath() async => root;

  @override
  Future<String?> getApplicationSupportPath() async => root;

  @override
  Future<String?> getApplicationCachePath() async => root;
}

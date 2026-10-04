import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/action.dart';
import 'package:fl_clash/providers/app.dart';
import 'package:fl_clash/providers/config.dart';
import 'package:fl_clash/providers/state.dart';
import 'package:fl_clash/state.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:riverpod/riverpod.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory testDirectory;
  late PathProviderPlatform previousPathProvider;
  late bool previousNeedInitStatus;

  setUpAll(() {
    testDirectory = Directory.systemTemp.createTempSync('startup_auto_connect');
    previousPathProvider = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _TestPathProvider(testDirectory.path);
  });

  setUp(() {
    previousNeedInitStatus = globalState.needInitStatus;
    globalState.needInitStatus = true;
  });

  tearDown(() {
    globalState.needInitStatus = previousNeedInitStatus;
  });

  tearDownAll(() async {
    await commonPrint.flushDiagnosticEvents();
    PathProviderPlatform.instance = previousPathProvider;
    await testDirectory.delete(recursive: true);
  });

  test('automatic startup defaults to off in new and older configurations', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    expect(container.read(appSettingProvider).autoRun, isFalse);
    expect(const AppSettingProps().autoRun, isFalse);
    expect(AppSettingProps.fromJson({}).autoRun, isFalse);
    expect(Config.realFromJson(null).appSettingProps.autoRun, isFalse);
  });

  for (final enabled in [true, false]) {
    test('configuration round trip preserves automatic startup $enabled', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container
          .read(appSettingProvider.notifier)
          .update((state) => state.copyWith(autoRun: enabled));
      final config = Config(
        themeProps: defaultThemeProps,
        appSettingProps: container.read(appSettingProvider),
      );

      final restored = Config.fromJson(
        jsonDecode(jsonEncode(config.toJson())) as Map<String, dynamic>,
      );

      expect(restored.appSettingProps.autoRun, enabled);
    });
  }

  test(
    'initStatus applies the profile without starting before login',
    () async {
      final harness = _Harness(autoRun: true);

      await harness.setup.initStatus();

      expect(harness.container.read(appSettingProvider).autoRun, isTrue);
      expect(harness.setup.appliedProfiles, [true]);
      expect(harness.setup.transitions, isEmpty);
      expect(harness.setup.manualRequests, isEmpty);
      expect(harness.setup.automaticStarts, 0);
      expect(harness.container.read(isStartProvider), isFalse);
    },
  );

  for (final guard in ['cancelled', 'not_ready', 'running', 'pending']) {
    test(
      'login startup skips a $guard attempt without changing proxy',
      () async {
        final harness = _Harness(
          initialized: guard != 'not_ready',
          running: guard == 'running',
          pending: guard == 'pending',
        );
        final revision = harness.proxies.manualSelectionRevision;

        await harness.common.startAfterLogin(
          isCurrent: () => guard != 'cancelled',
        );

        expect(harness.setup.automaticStarts, 0);
        expect(harness.setup.manualRequests, isEmpty);
        expect(harness.setup.transitions, isEmpty);
        expect(
          harness.container.read(networkSettingProvider).systemProxy,
          isFalse,
        );
        expect(harness.proxies.manualSelectionRevision, revision);
      },
    );
  }

  test(
    'desktop login startup enables proxy and uses automatic start',
    () async {
      final harness = _Harness();
      final revision = harness.proxies.manualSelectionRevision;

      await harness.common.startAfterLogin(isCurrent: () => true);

      expect(harness.setup.automaticStarts, 1);
      expect(harness.setup.manualRequests, isEmpty);
      expect(harness.setup.transitions, [true]);
      expect(harness.setup.debouncedProfiles, [(force: true, silence: true)]);
      expect(
        harness.container.read(networkSettingProvider).systemProxy,
        isTrue,
      );
      expect(harness.container.read(isStartProvider), isTrue);
      expect(harness.proxies.manualSelectionRevision, revision);
    },
  );

  test(
    'a non-desktop login start preserves the system proxy preference',
    () async {
      final harness = _Harness(desktop: false);

      await harness.common.startAfterLogin(isCurrent: () => true);

      expect(harness.setup.automaticStarts, 1);
      expect(harness.setup.transitions, [true]);
      expect(
        harness.container.read(networkSettingProvider).systemProxy,
        isFalse,
      );
    },
  );

  test('a session cancelled during proxy preparation does not start', () async {
    final harness = _Harness();
    var checks = 0;

    await harness.common.startAfterLogin(isCurrent: () => ++checks == 1);

    expect(checks, 2);
    expect(harness.setup.automaticStarts, 0);
    expect(harness.setup.transitions, isEmpty);
  });

  test(
    'automatic start preserves intent while manual stop and start advance it',
    () async {
      final harness = _Harness();
      final revision = harness.proxies.manualSelectionRevision;

      await harness.setup.startAutomatically();

      expect(harness.setup.transitions, [true]);
      expect(harness.proxies.manualSelectionRevision, revision);
      expect(harness.container.read(isStartProvider), isTrue);

      await harness.setup.setRunning(false);

      expect(harness.proxies.manualSelectionRevision, revision + 1);
      expect(harness.container.read(isStartProvider), isFalse);

      await harness.setup.setRunning(true);

      expect(harness.setup.transitions, [true, false, true]);
      expect(harness.setup.manualRequests, [false, true]);
      expect(harness.proxies.manualSelectionRevision, revision + 2);
      expect(harness.container.read(isStartProvider), isTrue);
    },
  );

  test(
    'direct automatic start still requires completed initialization',
    () async {
      final harness = _Harness(initialized: false);
      final revision = harness.proxies.manualSelectionRevision;

      await harness.setup.startAutomatically();

      expect(harness.setup.transitions, isEmpty);
      expect(harness.setup.debouncedProfiles, isEmpty);
      expect(harness.proxies.manualSelectionRevision, revision);
      expect(harness.container.read(isStartProvider), isFalse);
    },
  );

  test('exit invalidates startup intent before asynchronous cleanup', () async {
    final action = _TestExitAction();
    final container = ProviderContainer(
      overrides: [systemActionProvider.overrideWith(() => action)],
    );
    addTearDown(container.dispose);
    final proxies = container.read(proxiesActionProvider.notifier);
    final revision = proxies.manualSelectionRevision;

    final operation = container
        .read(systemActionProvider.notifier)
        .handleExit();

    try {
      expect(proxies.manualSelectionRevision, revision + 1);
      expect(action.events, ['cleanup']);
    } finally {
      action.cleanup.complete();
      await operation;
    }

    expect(action.events, ['cleanup', 'window', 'core', 'exit']);
  });
}

class _Harness {
  _Harness({
    bool initialized = true,
    bool running = false,
    bool pending = false,
    bool autoRun = false,
    bool desktop = true,
  }) {
    container = ProviderContainer(
      overrides: [
        initProvider.overrideWithBuild((_, _) => initialized),
        runTimeProvider.overrideWithBuild((_, _) => running ? 0 : null),
        connectionPendingProvider.overrideWithBuild((_, _) => pending),
        appSettingProvider.overrideWithBuild(
          (_, _) => AppSettingProps(autoRun: autoRun),
        ),
        networkSettingProvider.overrideWithBuild(
          (_, _) => const NetworkProps(systemProxy: false),
        ),
        commonActionProvider.overrideWith(() => _TestCommonAction(desktop)),
        setupActionProvider.overrideWith(_TestSetupAction.new),
      ],
    );
    addTearDown(container.dispose);
    container.listen(appSettingProvider, (_, _) {});
    container.listen(networkSettingProvider, (_, _) {});
    container.listen(runTimeProvider, (_, _) {});
    common = container.read(commonActionProvider.notifier);
    setup = container.read(setupActionProvider.notifier) as _TestSetupAction;
    proxies = container.read(proxiesActionProvider.notifier);
  }

  late final ProviderContainer container;
  late final CommonAction common;
  late final _TestSetupAction setup;
  late final ProxiesAction proxies;
}

class _TestCommonAction extends CommonAction {
  _TestCommonAction(this.desktop);

  final bool desktop;

  @override
  bool get enablesSystemProxyOnConnect => desktop;

  @override
  Future<void> updateTraffic() async {}
}

class _TestSetupAction extends SetupAction {
  int automaticStarts = 0;
  final manualRequests = <bool>[];
  final transitions = <bool>[];
  final appliedProfiles = <bool>[];
  final debouncedProfiles = <({bool force, bool silence})>[];

  @override
  bool get requiresListenerReadiness => false;

  @override
  bool get requiresWindowsTunAuthorization => false;

  @override
  Future<void> startAutomatically() {
    automaticStarts++;
    return super.startAutomatically();
  }

  @override
  Future<void> setRunning(
    bool running, {
    bool initialize = false,
    bool propagateErrors = false,
  }) {
    manualRequests.add(running);
    return super.setRunning(
      running,
      initialize: initialize,
      propagateErrors: propagateErrors,
    );
  }

  @override
  Future<bool> setCoreRunning(bool running) async {
    transitions.add(running);
    return true;
  }

  @override
  void applyProfileDebounce({bool silence = false, bool force = false}) {
    debouncedProfiles.add((force: force, silence: silence));
  }

  @override
  Future<void> applyProfile({
    bool silence = false,
    bool force = false,
    Future<void> Function()? preloadInvoke,
    bool Function()? isCurrent,
    bool propagateErrors = false,
    Profile? profileOverride,
  }) async {
    appliedProfiles.add(force);
    await preloadInvoke?.call();
  }

  @override
  void resetCoreTraffic() {}
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

class _TestExitAction extends SystemAction {
  final cleanup = Completer<void>();
  final events = <String>[];

  @override
  Duration get exitWatchdogDuration => const Duration(hours: 1);

  @override
  Future<void> cleanupExitResources(bool needSave) {
    events.add('cleanup');
    return cleanup.future;
  }

  @override
  Future<void> closeWindow() async {
    events.add('window');
  }

  @override
  Future<void> closeCore() async {
    events.add('core');
  }

  @override
  Future<void> exitApplication() async {
    events.add('exit');
  }
}

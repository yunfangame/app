import 'dart:async';
import 'dart:io';

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/core/desktop/model.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/action.dart';
import 'package:fl_clash/providers/app.dart';
import 'package:fl_clash/providers/config.dart';
import 'package:fl_clash/providers/state.dart';
import 'package:fl_clash/state.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:riverpod/riverpod.dart';

const _stableProfile = Profile(
  id: 101,
  label: 'Stable account',
  autoUpdateDuration: Duration(days: 1),
  selectedMap: {'GLOBAL': 'Stable node'},
);

const _candidateProfile = Profile(
  id: 202,
  label: 'Candidate account',
  autoUpdateDuration: Duration(days: 1),
  selectedMap: {'GLOBAL': 'Candidate node'},
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory testDirectory;
  late File configFile;
  late DebugPrintCallback previousDebugPrint;
  late String? previousConfigMd5;
  final diagnostics = <String>[];

  setUpAll(() async {
    testDirectory = await Directory.systemTemp.createTemp('startup_setup_test');
    PathProviderPlatform.instance = _TestPathProvider(testDirectory.path);
    configFile = File(await appPath.configFilePath);
  });

  tearDownAll(() async {
    await commonPrint.flushDiagnosticEvents();
    await testDirectory.delete(recursive: true);
  });

  setUp(() async {
    previousDebugPrint = debugPrint;
    previousConfigMd5 = globalState.lastConfigMd5;
    diagnostics.clear();
    debugPrint = (message, {wrapWidth}) {
      if (message != null) diagnostics.add(message);
    };
    globalState.lastConfigMd5 = 'stable-md5';
    await configFile.writeAsString('stable configuration');
  });

  tearDown(() {
    debugPrint = previousDebugPrint;
    globalState.lastConfigMd5 = previousConfigMd5;
  });

  test(
    'TUN authorization inside a restart finishes without self-await',
    () async {
      final harness = _Harness(stableProfile: null);
      addTearDown(harness.container.dispose);
      harness.enableTun();

      await harness.core.restartCore().timeout(const Duration(seconds: 2));

      expect(harness.core.restartCount, 2);
      expect(harness.setup.authorizationCount, 1);
      expect(harness.setup.appliedParams, hasLength(1));
      expect(harness.container.read(coreStatusProvider), CoreStatus.connected);
      expect(
        harness.container.read(authorizedTunEnableProvider),
        TunAuthorizationState.authorized,
      );
      expect(globalState.lastConfigMd5, 'candidate-md5');
    },
  );

  test(
    'authorization restart preserves candidate profile and selections',
    () async {
      final harness = _Harness(stableProfile: _stableProfile);
      addTearDown(harness.container.dispose);
      harness.enableTun();
      var guardChecks = 0;
      var preloadCount = 0;

      await harness.setup.applyProfile(
        force: true,
        silence: true,
        propagateErrors: true,
        profileOverride: _candidateProfile,
        preloadInvoke: () async {
          preloadCount++;
        },
        isCurrent: () {
          guardChecks++;
          return true;
        },
      );

      expect(harness.core.restartCount, 1);
      expect(harness.setup.preparedProfileIds, [_candidateProfile.id]);
      expect(harness.setup.preparedSelections, [_candidateProfile.selectedMap]);
      expect(
        harness.setup.appliedParams.single.selectedMap,
        _candidateProfile.selectedMap,
      );
      expect(harness.container.read(currentProfileProvider), _stableProfile);
      expect(guardChecks, greaterThan(2));
      expect(preloadCount, 1);
    },
  );

  test(
    'a superseded login cannot apply its candidate after authorization',
    () async {
      final harness = _Harness(stableProfile: _stableProfile);
      addTearDown(harness.container.dispose);
      harness.enableTun();
      var current = true;
      final restarting = Completer<void>();
      final releaseRestart = Completer<void>();
      harness.core.onRestart = (count) async {
        if (count == 1) {
          restarting.complete();
          await releaseRestart.future;
        }
      };

      final applying = harness.setup.applyProfile(
        force: true,
        silence: true,
        propagateErrors: true,
        profileOverride: _candidateProfile,
        isCurrent: () => current,
      );
      final rejected = expectLater(
        applying,
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            'configuration_apply_superseded',
          ),
        ),
      );
      await restarting.future;
      current = false;
      releaseRestart.complete();
      await rejected;

      expect(harness.setup.preparedProfileIds, isEmpty);
      expect(
        harness.setup.appliedParams.single.selectedMap,
        _stableProfile.selectedMap,
      );
      expect(await configFile.readAsString(), 'stable configuration');
      expect(globalState.lastConfigMd5, 'stable-md5');
      expect(harness.container.read(currentProfileProvider), _stableProfile);
    },
  );

  test(
    'setup timeout restores config before recovery and rejects late success',
    () async {
      final harness = _Harness(stableProfile: _stableProfile);
      addTearDown(harness.container.dispose);
      final lateSetup = Completer<String>();
      final restartConfigContents = <String>[];
      var preloadCount = 0;
      harness.setup.onApply = (count) =>
          count == 1 ? lateSetup.future : Future.value('');
      harness.core.onRestart = (_) async {
        restartConfigContents.add(await configFile.readAsString());
      };
      final checkIpBefore = harness.container.read(checkIpNumProvider);

      await expectLater(
        harness.setup.applyProfile(
          force: true,
          silence: true,
          propagateErrors: true,
          profileOverride: _candidateProfile,
          isCurrent: () => true,
          preloadInvoke: () async {
            preloadCount++;
          },
        ),
        throwsA(isA<TimeoutException>()),
      );

      expect(restartConfigContents, ['stable configuration']);
      expect(harness.setup.appliedParams.map((params) => params.selectedMap), [
        _candidateProfile.selectedMap,
        _stableProfile.selectedMap,
      ]);
      expect(harness.proxies.refreshCount, 1);
      expect(harness.providers.refreshCount, 1);
      expect(globalState.lastConfigMd5, 'stable-md5');
      expect(harness.container.read(checkIpNumProvider), checkIpBefore);
      expect(preloadCount, 0);
      expect(
        diagnostics.where(
          (line) => line.contains('configuration.apply.failed'),
        ),
        hasLength(1),
      );

      lateSetup.complete('');
      await lateSetup.future;
      await Future<void>.delayed(Duration.zero);

      expect(await configFile.readAsString(), 'stable configuration');
      expect(globalState.lastConfigMd5, 'stable-md5');
      expect(harness.proxies.refreshCount, 1);
      expect(harness.container.read(checkIpNumProvider), checkIpBefore);
      expect(preloadCount, 0);
      expect(
        diagnostics.where(
          (line) => line.contains('configuration.apply.succeeded'),
        ),
        isEmpty,
      );
    },
  );
}

class _Harness {
  _Harness({required Profile? stableProfile}) {
    container = ProviderContainer(
      overrides: [
        currentProfileProvider.overrideWithValue(stableProfile),
        setupStateProvider.overrideWith(
          (_, profileId) => SetupState(
            profileId: profileId,
            profileLastUpdateDate: null,
            overwriteType: OverwriteType.standard,
            rules: const [],
            proxyGroups: const [],
            addedRules: const [],
            script: null,
            overrideDns: false,
            dns: const Dns(),
          ),
        ),
        setupActionProvider.overrideWith(() => setup),
        coreActionProvider.overrideWith(() => core),
        proxiesActionProvider.overrideWith(() => proxies),
        providersProvider.overrideWith(() => providers),
      ],
    );
    container.read(setupActionProvider);
    container.read(coreActionProvider);
  }

  late final ProviderContainer container;
  final setup = _TestSetupAction();
  final core = _TestCoreAction();
  final proxies = _TestProxiesAction();
  final providers = _TestProviders();

  void enableTun() {
    container
        .read(patchClashConfigProvider.notifier)
        .update((state) => state.copyWith.tun(enable: true));
  }
}

class _TestSetupAction extends SetupAction {
  int authorizationCount = 0;
  final preparedProfileIds = <int?>[];
  final preparedSelections = <Map<String, String>?>[];
  final appliedParams = <SetupParams>[];
  Future<String> Function(int count)? onApply;

  @override
  bool get requiresListenerReadiness => true;

  @override
  bool get supportsCoreSetupTimeoutRecovery => true;

  @override
  Duration get configurationPreparationTimeout =>
      const Duration(milliseconds: 100);

  @override
  Future<AuthorizeCode> authorizeCore() async {
    authorizationCount++;
    return AuthorizeCode.success;
  }

  @override
  Future<VM2<String, String>> getProfile({
    required SetupState setupState,
    required PatchClashConfig patchConfig,
    Map<String, String>? selectedMapOverride,
  }) async {
    preparedProfileIds.add(setupState.profileId);
    preparedSelections.add(selectedMapOverride);
    return const VM2('rules:\n  - MATCH,DIRECT\n', 'candidate-md5');
  }

  @override
  Future<String> applyCoreSetup({
    required SetupParams params,
    Future<void> Function()? preloadInvoke,
    Duration? timeout,
  }) async {
    appliedParams.add(params);
    final message =
        await (onApply?.call(appliedParams.length) ?? Future.value(''));
    if (message.isEmpty) await preloadInvoke?.call();
    return message;
  }
}

class _TestCoreAction extends CoreAction {
  int restartCount = 0;
  Future<void> Function(int count)? onRestart;

  @override
  Future<void> initCore() async {}

  @override
  Future<CoreLifecycleResult> restartLifecycle() async {
    restartCount++;
    await onRestart?.call(restartCount);
    return CoreLifecycleResult(
      revision: restartCount,
      outcome: CoreLifecycleOutcome.applied,
    );
  }
}

class _TestProxiesAction extends ProxiesAction {
  int refreshCount = 0;

  @override
  Future<void> updateGroups() async {
    refreshCount++;
  }
}

class _TestProviders extends Providers {
  int refreshCount = 0;

  @override
  Future<void> syncProviders() async {
    refreshCount++;
  }
}

class _TestPathProvider extends PathProviderPlatform {
  _TestPathProvider(this.root);

  final String root;

  @override
  Future<String?> getApplicationSupportPath() async => root;

  @override
  Future<String?> getTemporaryPath() async => root;

  @override
  Future<String?> getApplicationCachePath() async => root;
}

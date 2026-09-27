import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/l10n/l10n.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:riverpod/riverpod.dart';

const _firstProfile = Profile(
  id: 1,
  label: 'First subscription',
  autoUpdateDuration: Duration(days: 1),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;

  setUpAll(() async {
    directory = await Directory.systemTemp.createTemp('macos_auth_update');
    PathProviderPlatform.instance = _TestPathProvider(directory.path);
    await AppLocalizations.load(const Locale('zh', 'CN'));
  });

  tearDownAll(() async {
    await commonPrint.flushDiagnosticEvents();
    await directory.delete(recursive: true);
  });

  test(
    'Mac authorization reloads the profile before restoring listeners',
    () async {
      final rig = _Rig();
      addTearDown(rig.container.dispose);
      await rig.start();

      await rig.enableTun();

      expect(rig.action.updates, isEmpty);
      expect(rig.action.setups, [(profileId: 1, port: 7890, tun: true)]);
      expect(rig.action.events, [
        'authorize',
        'restart',
        'prepare:1:7890:true',
        'setup:1:7890:true',
        'listener:true',
        'verify:7890',
      ]);
      expect(rig.container.read(isStartProvider), isTrue);
      expect(rig.container.read(connectionPendingProvider), isFalse);
      expect(rig.container.read(networkSettingProvider).systemProxy, isTrue);
      expect(rig.action.failures, isEmpty);
    },
  );

  test(
    'stopping while Mac authorization is pending prevents restart',
    () async {
      final rig = _Rig();
      addTearDown(rig.container.dispose);
      await rig.start();
      rig.action.pendingAuthorization = Completer<AuthorizeCode>();

      final updating = rig.enableTun();
      await rig.action.authorizationEntered.future;
      await rig.action.setRunning(false);
      rig.action.pendingAuthorization!.complete(AuthorizeCode.success);
      await updating;

      expect(rig.action.events, ['authorize', 'listener:false']);
      expect(rig.action.setups, isEmpty);
      expect(rig.action.failures, isEmpty);
      expect(rig.container.read(isStartProvider), isFalse);
    },
  );

  test('stopping during Mac restart cannot restore the old listener', () async {
    final rig = _Rig();
    addTearDown(rig.container.dispose);
    await rig.start();
    rig.action.pendingRestart = Completer<void>();

    final updating = rig.enableTun();
    await rig.action.restartEntered.future;
    await rig.action.setRunning(false);
    rig.action.pendingRestart!.complete();
    await updating;

    expect(rig.action.events, ['authorize', 'restart', 'listener:false']);
    expect(rig.action.setups, isEmpty);
    expect(rig.action.updates, isEmpty);
    expect(rig.action.failures, isEmpty);
    expect(rig.container.read(isStartProvider), isFalse);
    expect(rig.container.read(connectionPendingProvider), isFalse);
  });

  test(
    'new start supersedes the Mac authorization restart continuation',
    () async {
      final rig = _Rig();
      addTearDown(rig.container.dispose);
      await rig.start();
      rig.action.pendingRestart = Completer<void>();

      final updating = rig.enableTun();
      await rig.action.restartEntered.future;
      await rig.action.setRunning(false);
      await rig.action.setRunning(true);
      final latestEvents = List<String>.of(rig.action.events);
      rig.action.pendingRestart!.complete();
      await updating;

      expect(rig.action.events, latestEvents);
      expect(rig.action.setups, isEmpty);
      expect(rig.action.failures, isEmpty);
      expect(rig.container.read(isStartProvider), isTrue);
    },
  );

  for (final stage in ['restart', 'preparation', 'setup']) {
    test(
      'Mac reload uses latest profile, port and TUN after $stage changes',
      () async {
        final rig = _Rig();
        addTearDown(rig.container.dispose);
        await rig.start();
        final pending = Completer<void>();
        final Future<void> entered;
        switch (stage) {
          case 'restart':
            rig.action.pendingRestart = pending;
            entered = rig.action.restartEntered.future;
          case 'preparation':
            rig.action.pendingPreparation = pending;
            entered = rig.action.preparationEntered.future;
          default:
            rig.action.pendingSetup = pending;
            entered = rig.action.setupEntered.future;
        }

        final updating = rig.enableTun();
        await entered;
        rig.selectSecondProfile();
        rig.container
            .read(patchClashConfigProvider.notifier)
            .update(
              (state) => state.copyWith(mixedPort: 7891, tun: const Tun()),
            );
        pending.complete();
        await updating;

        expect(rig.action.setups.last, (profileId: 2, port: 7891, tun: false));
        expect(rig.action.setups.length, stage == 'setup' ? 2 : 1);
        expect(
          rig.action.events.where((event) => event == 'restart'),
          hasLength(1),
        );
        expect(
          rig.action.events.where((event) => event == 'listener:true'),
          hasLength(1),
        );
        expect(rig.action.events.last, 'verify:7891');
        expect(rig.action.recoveries, isEmpty);
        expect(rig.action.updates, isEmpty);
        expect(rig.action.failures, isEmpty);
        expect(rig.container.read(isStartProvider), isTrue);
        expect(rig.container.read(connectionPendingProvider), isFalse);
        expect(rig.container.read(networkSettingProvider).systemProxy, isTrue);
      },
    );
  }

  test(
    'stopping during full Mac setup skips stale recovery and restore',
    () async {
      final rig = _Rig();
      addTearDown(rig.container.dispose);
      await rig.start();
      rig.action.pendingSetup = Completer<void>();

      final updating = rig.enableTun();
      await rig.action.setupEntered.future;
      await rig.action.setRunning(false);
      rig.action.pendingSetup!.complete();
      await updating;

      expect(
        rig.action.events.where((event) => event == 'listener:true'),
        isEmpty,
      );
      expect(rig.action.recoveries, isEmpty);
      expect(rig.action.failures, isEmpty);
      expect(rig.container.read(isStartProvider), isFalse);
      expect(rig.container.read(connectionPendingProvider), isFalse);
    },
  );

  test(
    'a queued update yields before the Mac restart handoff releases its lock',
    () async {
      final rig = _Rig();
      addTearDown(rig.container.dispose);
      await rig.start();
      rig.action.pendingAuthorization = Completer<AuthorizeCode>();
      final updating = rig.enableTun();
      await rig.action.authorizationEntered.future;
      final queued = rig.action.updateConfig();
      rig.action.pendingAuthorization!.complete(AuthorizeCode.success);
      await Future.wait([updating, queued]).timeout(const Duration(seconds: 2));

      expect(rig.action.updates, isEmpty);
      expect(rig.action.setups, hasLength(1));
      expect(
        rig.action.events.where((event) => event == 'restart'),
        hasLength(1),
      );
      expect(rig.action.failures, isEmpty);
      expect(rig.container.read(isStartProvider), isTrue);
    },
  );

  for (final stage in ['restart', 'setup']) {
    test(
      'concurrent config updates defer to Mac full reload during $stage',
      () async {
        final rig = _Rig();
        addTearDown(rig.container.dispose);
        await rig.start();
        final pending = Completer<void>();
        if (stage == 'restart') {
          rig.action.pendingRestart = pending;
        } else {
          rig.action.pendingSetup = pending;
        }
        final updating = rig.enableTun();
        await (stage == 'restart'
            ? rig.action.restartEntered.future
            : rig.action.setupEntered.future);
        rig.container
            .read(patchClashConfigProvider.notifier)
            .update(
              (state) => state.copyWith(mixedPort: 7892, tun: const Tun()),
            );

        await rig.action.updateConfig().timeout(const Duration(seconds: 1));
        expect(rig.action.updates, isEmpty);
        expect(rig.action.failures, isEmpty);
        pending.complete();
        await updating;

        expect(rig.action.setups.last, (profileId: 1, port: 7892, tun: false));
        expect(rig.action.events.last, 'verify:7892');
        expect(rig.action.updates, isEmpty);
        expect(rig.action.failures, isEmpty);
        expect(rig.container.read(isStartProvider), isTrue);
      },
    );
  }

  test(
    'Mac full reload retains a newer node within the same subscription',
    () async {
      final rig = _Rig();
      addTearDown(rig.container.dispose);
      await rig.start();
      rig.action.pendingSetup = Completer<void>();
      final updating = rig.enableTun();
      await rig.action.setupEntered.future;
      final profiles =
          rig.container.read(profilesProvider.notifier) as _MemoryProfiles;
      profiles.replace(
        _firstProfile.copyWith(selectedMap: {'GLOBAL': 'new node'}),
      );
      rig.action.pendingSetup!.complete();
      await updating;

      expect(rig.action.setupSelections, [
        {},
        {'GLOBAL': 'new node'},
      ]);
      expect(rig.action.recoveries, isEmpty);
      expect(rig.action.failures, isEmpty);
      expect(rig.container.read(isStartProvider), isTrue);
    },
  );

  test(
    'a stale Mac listener restore failure cannot cancel a newer port',
    () async {
      final rig = _Rig();
      addTearDown(rig.container.dispose);
      await rig.start();
      final restoring = Completer<bool>();
      rig.action.pendingRestore = restoring;
      final updating = rig.enableTun();
      await rig.action.restoreEntered.future;
      rig.container
          .read(patchClashConfigProvider.notifier)
          .update((state) => state.copyWith(mixedPort: 7893));
      restoring.complete(false);
      await updating;

      expect(rig.action.setups.last, (profileId: 1, port: 7893, tun: true));
      expect(rig.action.events.last, 'verify:7893');
      expect(rig.action.failures, isEmpty);
      expect(rig.container.read(isStartProvider), isTrue);
    },
  );

  test(
    'a real Mac configuration failure still reports its original error',
    () async {
      final rig = _Rig();
      addTearDown(rig.container.dispose);
      await rig.start();
      rig.action.setupMessage = 'test configuration cannot be applied';

      await rig.enableTun();

      expect(rig.action.failures, ['test configuration cannot be applied']);
      expect(rig.action.recoveries, ['core_setup_failed']);
      expect(rig.container.read(isStartProvider), isFalse);
      expect(rig.container.read(connectionPendingProvider), isFalse);
      expect(rig.container.read(networkSettingProvider).systemProxy, isFalse);
      final events = const LineSplitter()
          .convert(await commonPrint.readDiagnosticEvents())
          .map((line) => jsonDecode(line) as Map<String, dynamic>);
      final failure = events.lastWhere(
        (event) => event['event'] == 'connection.failed',
      );
      expect(failure['fields']['error_type'], 'String');
      expect(
        failure['fields']['error'],
        'test configuration cannot be applied',
      );

      rig.action.setupMessage = '';
      await rig.action.setRunning(true);
      rig.container
          .read(patchClashConfigProvider.notifier)
          .update((state) => state.copyWith.tun(enable: false));
      await rig.action.updateConfig();
      expect(rig.action.updates, hasLength(1));
      expect(rig.action.failures, hasLength(1));
      expect(rig.container.read(isStartProvider), isTrue);
    },
  );

  test('Windows keeps its original authorization update path', () async {
    final rig = _Rig(macOS: false);
    addTearDown(rig.container.dispose);
    await rig.start();

    await rig.enableTun();

    expect(rig.action.setups, isEmpty);
    expect(rig.action.updates, hasLength(1));
    expect(rig.action.events, [
      'authorize',
      'restart',
      'update',
      'listener:true',
      'verify:7890',
    ]);
    expect(rig.action.failures, isEmpty);
    expect(rig.container.read(isStartProvider), isTrue);
  });
}

class _Rig {
  _Rig({bool macOS = true}) {
    action = _AuthorizationSetup(macOS: macOS);
    container = ProviderContainer(
      overrides: [
        initProvider.overrideWithBuild((_, _) => true),
        currentProfileIdProvider.overrideWithBuild((_, _) => 1),
        profilesProvider.overrideWith(_MemoryProfiles.new),
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
        commonActionProvider.overrideWith(_QuietCommon.new),
        proxiesActionProvider.overrideWith(_QuietProxies.new),
        providersProvider.overrideWith(_QuietProviders.new),
        setupActionProvider.overrideWith(() => action),
      ],
    );
    container.read(setupActionProvider);
    container.listen(currentProfileProvider, (_, _) {});
    container
        .read(patchClashConfigProvider.notifier)
        .update((state) => state.copyWith(mixedPort: 7890, tun: const Tun()));
    container
        .read(networkSettingProvider.notifier)
        .update((state) => state.copyWith(systemProxy: true));
  }

  late final ProviderContainer container;
  late final _AuthorizationSetup action;

  Future<void> start() async {
    await action.setRunning(true);
    action.events.clear();
  }

  Future<void> enableTun() {
    container
        .read(patchClashConfigProvider.notifier)
        .update((state) => state.copyWith.tun(enable: true));
    return action.updateConfig();
  }

  void selectSecondProfile() {
    final profiles =
        container.read(profilesProvider.notifier) as _MemoryProfiles;
    profiles.replace(
      _firstProfile.copyWith(id: 2, label: 'Second subscription'),
    );
    container.read(currentProfileIdProvider.notifier).value = 2;
  }
}

typedef _AppliedConfig = ({int? profileId, int port, bool tun});

class _AuthorizationSetup extends SetupAction {
  _AuthorizationSetup({required this.macOS});

  final bool macOS;
  final events = <String>[];
  final updates = <UpdateParams>[];
  final setups = <_AppliedConfig>[];
  final setupSelections = <Map<String, String>>[];
  final failures = <Object?>[];
  final recoveries = <String>[];
  final authorizationEntered = Completer<void>();
  final restartEntered = Completer<void>();
  final preparationEntered = Completer<void>();
  final setupEntered = Completer<void>();
  final restoreEntered = Completer<void>();
  Completer<AuthorizeCode>? pendingAuthorization;
  Completer<void>? pendingRestart;
  Completer<void>? pendingPreparation;
  Completer<void>? pendingSetup;
  Completer<bool>? pendingRestore;
  String setupMessage = '';
  bool configured = true;

  @override
  bool get requiresListenerReadiness => true;

  @override
  bool get requiresWindowsTunAuthorization => !macOS;

  @override
  bool get requiresFullSetupAfterAuthorization => macOS;

  @override
  Future<bool> isTunServiceReady() async => true;

  @override
  Future<AuthorizeCode> authorizeCore() async {
    events.add('authorize');
    if (!authorizationEntered.isCompleted) authorizationEntered.complete();
    return await pendingAuthorization?.future ?? AuthorizeCode.success;
  }

  @override
  Future<void> restartCoreLifecycleOnly() async {
    events.add('restart');
    configured = !macOS;
    if (!restartEntered.isCompleted) restartEntered.complete();
    await pendingRestart?.future;
  }

  @override
  Future<void> prepareListenerProfile() async {
    configured = true;
  }

  @override
  Future<VM2<String, String>> getProfile({
    required SetupState setupState,
    required PatchClashConfig patchConfig,
    Map<String, String>? selectedMapOverride,
  }) async {
    events.add(
      'prepare:${setupState.profileId}:${patchConfig.mixedPort}:${patchConfig.tun.enable}',
    );
    final config = jsonEncode({
      'profileId': setupState.profileId,
      'port': patchConfig.mixedPort,
      'tun': patchConfig.tun.enable,
    });
    if (!preparationEntered.isCompleted) preparationEntered.complete();
    await pendingPreparation?.future;
    return VM2(config, config);
  }

  @override
  Future<String> applyCoreSetup({
    required SetupParams params,
    Future<void> Function()? preloadInvoke,
    Duration? timeout,
  }) async {
    final config =
        jsonDecode(await File(await appPath.configFilePath).readAsString())
            as Map<String, dynamic>;
    final applied = (
      profileId: config['profileId'] as int?,
      port: config['port'] as int,
      tun: config['tun'] as bool,
    );
    events.add('setup:${applied.profileId}:${applied.port}:${applied.tun}');
    setups.add(applied);
    setupSelections.add(Map<String, String>.of(params.selectedMap));
    if (!setupEntered.isCompleted) setupEntered.complete();
    await pendingSetup?.future;
    configured = true;
    return setupMessage;
  }

  @override
  Future<String> applyCoreUpdate(UpdateParams params) async {
    events.add('update');
    updates.add(params);
    return configured ? '' : 'config is not applied';
  }

  @override
  Future<bool> setCoreRunning(bool running) async {
    events.add('listener:$running');
    if (running && !configured) throw StateError('missing configuration');
    final pending = pendingRestore;
    if (running && pending != null) {
      pendingRestore = null;
      restoreEntered.complete();
      return pending.future;
    }
    return true;
  }

  @override
  Future<void> verifyLocalListener(
    int port, {
    required bool Function() isCancelled,
  }) async {
    if (!isCancelled()) events.add('verify:$port');
  }

  @override
  void resetCoreTraffic() {}

  @override
  void notifyListenerFailure(int port, {Object? error}) {
    failures.add(error);
  }

  @override
  Future<void> recoverStableCoreConfiguration(
    Profile? profile, {
    required String reason,
  }) async {
    recoveries.add(reason);
  }
}

class _MemoryProfiles extends Profiles {
  @override
  List<Profile> build() => [_firstProfile];

  void replace(Profile profile) => state = [profile];
}

class _QuietCommon extends CommonAction {
  @override
  Future<void> updateTraffic() async {}
}

class _QuietProxies extends ProxiesAction {
  @override
  Future<void> updateGroups() async {}
}

class _QuietProviders extends Providers {
  @override
  Future<void> syncProviders() async {}
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

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/common/windows_identity.dart';
import 'package:fl_clash/database/database.dart' show database;
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/l10n/l10n.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:riverpod/riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late bool previousNeedInitStatus;
  late String? previousMd5;

  setUpAll(() async {
    directory = await Directory.systemTemp.createTemp('refresh_continuity');
    PathProviderPlatform.instance = _Paths(directory.path);
    await AppLocalizations.load(const Locale('zh', 'CN'));
  });
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    previousNeedInitStatus = globalState.needInitStatus;
    previousMd5 = globalState.lastConfigMd5;
    globalState.needInitStatus = true;
    globalState.lastConfigMd5 = null;
    globalState.clearXboardSession();
    globalState.setOfflineMode(false);
  });
  tearDown(() {
    globalState.clearXboardSession();
    globalState.setOfflineMode(false);
    globalState.needInitStatus = previousNeedInitStatus;
    globalState.lastConfigMd5 = previousMd5;
  });
  tearDownAll(() async {
    await database.close();
    await commonPrint.flushDiagnosticEvents();
    await directory.delete(recursive: true);
  });

  for (final scenario in [
    'same-source',
    'bound-rotation',
    'unbound-rotation',
  ]) {
    test(
      'connected Windows TUN survives $scenario refresh and cleanup',
      () async {
        final h = await _Harness.create(bound: scenario != 'unbound-rotation');
        final sameSource = scenario == 'same-source';
        final result = await h.refresh(
          source: sameSource ? h.oldProfile.url : _newSource,
        );
        expect(result.id == h.oldProfile.id, scenario != 'unbound-rotation');
        await h.drainSetup();

        expect(h.container.read(currentProfileIdProvider), result.id);
        expect(h.container.read(currentProfileProvider)?.url, result.url);
        expect(
          h.container.read(profilesProvider).map((profile) => profile.id),
          [result.id],
        );
        expect(h.selectedIds, isNot(contains(null)));
        expect(h.selectedProfileIds, isNot(contains(null)));
        expect(h.setup.listeners, [true]);
        expect(h.setup.appliedTun, everyElement(isTrue));
        expect(h.setup.appliedProfiles, isNot(contains(null)));
        expect(h.setup.appliedProfiles.last, result.id);
        expect(h.container.read(isStartProvider), isTrue);
        expect(h.container.read(windowsTunReadyProvider), isTrue);
        expect(h.setup.failures, isEmpty);
      },
    );
  }

  test('user stop during refresh validation remains authoritative', () async {
    final h = await _Harness.create();
    final entered = Completer<void>();
    final release = Completer<void>();
    h.beforeValidation = () async {
      entered.complete();
      await release.future;
    };
    final refreshing = h.refresh();
    await entered.future;
    await h.setup.setRunning(false, propagateErrors: true);
    final afterStop = h.setup.appliedTun.length;
    release.complete();
    final result = await refreshing;
    await h.drainSetup();

    expect(h.container.read(currentProfileIdProvider), result.id);
    expect(h.setup.listeners, [true, false]);
    expect(h.setup.appliedTun.skip(afterStop), isNotEmpty);
    expect(h.setup.appliedTun.skip(afterStop), everyElement(isFalse));
    expect(h.container.read(isStartProvider), isFalse);
    expect(h.container.read(windowsTunReadyProvider), isFalse);
    expect(h.setup.failures, isEmpty);
  });

  test('user stop during candidate Core apply rejects stale refresh', () async {
    final h = await _Harness.create();
    final entered = Completer<void>();
    final release = Completer<void>();
    h.setup.beforeApply = () async {
      entered.complete();
      await release.future;
    };
    final refreshing = h.refresh();
    final rejected = expectLater(
      refreshing,
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          'configuration_apply_superseded',
        ),
      ),
    );
    await entered.future;
    await h.setup.setRunning(false, propagateErrors: true);
    h.setup.beforeApply = null;
    release.complete();
    await rejected;
    await h.drainSetup();

    expect(h.container.read(currentProfileIdProvider), h.oldProfile.id);
    expect(h.container.read(currentProfileProvider)?.url, h.oldProfile.url);
    expect(h.setup.listeners, [true, false]);
    expect(h.setup.appliedTun.last, isFalse);
    expect(h.container.read(isStartProvider), isFalse);
    expect(h.container.read(windowsTunReadyProvider), isFalse);
    expect(h.setup.failures, isEmpty);
  });

  test(
    'different account isolation stops instead of restoring old intent',
    () async {
      final h = await _Harness.create(binding: 'different-account');
      final result = await h.refresh();
      await h.drainSetup();

      expect(result.id, isNot(h.oldProfile.id));
      expect(h.selectedIds, contains(null));
      expect(h.setup.listeners, [true, false]);
      expect(h.setup.appliedTun.skip(1), everyElement(isFalse));
      expect(h.container.read(isStartProvider), isFalse);
      expect(h.container.read(windowsTunReadyProvider), isFalse);
      expect(h.setup.failures, isEmpty);
    },
  );
}

const _account =
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const _oldSource = 'fengwo-v2://fixture/refresh-old';
const _newSource = 'fengwo-v2://fixture/refresh-new';

class _Harness {
  _Harness(this.container, this.setup, this.oldProfile);

  final ProviderContainer container;
  final _Setup setup;
  final Profile oldProfile;
  final selectedIds = <int?>[];
  final selectedProfileIds = <int?>[];
  Future<void> Function()? beforeValidation;

  static Future<_Harness> create({
    bool bound = true,
    String binding = _account,
  }) async {
    globalState.activateXboardSession(_session(), ruleAccountKey: _account);
    expect(globalState.xboardRuleAccountKey, _account);
    final oldProfile = Profile.normal(url: _oldSource);
    await database.profilesDao.setAll([oldProfile]);
    if (bound) {
      await database.rulesDao.bindProfileAccount(oldProfile.id, binding);
    }
    final profileFile = File(
      await appPath.getProfilePath(oldProfile.id.toString()),
    );
    await profileFile.parent.create(recursive: true);
    await profileFile.writeAsString('validated-old-fixture');
    final setup = _Setup();
    final container = ProviderContainer(
      overrides: [
        initProvider.overrideWithBuild((_, _) => true),
        coreStatusProvider.overrideWithBuild((_, _) => CoreStatus.connected),
        currentProfileIdProvider.overrideWithBuild((_, _) => oldProfile.id),
        setupStateProvider.overrideWith(
          (_, id) => SetupState(
            profileId: id,
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
        commonActionProvider.overrideWith(_QuietCommon.new),
        proxiesActionProvider.overrideWith(_QuietProxies.new),
        providersProvider.overrideWith(_QuietProviders.new),
      ],
    );
    addTearDown(container.dispose);
    globalState.container = container;
    final h = _Harness(container, setup, oldProfile);
    container.listen(currentProfileIdProvider, (previous, next) {
      h.selectedIds.add(next);
      if (previous != next) setup.fullSetup();
    });
    container.listen(profilesProvider, (_, _) {});
    await container.read(profilesStreamProvider.future);
    container.listen(currentProfileProvider, (_, next) {
      h.selectedProfileIds.add(next?.id);
    });
    expect(container.read(currentProfileProvider)?.id, oldProfile.id);
    container.read(setupActionProvider);
    container
        .read(patchClashConfigProvider.notifier)
        .update((state) => state.copyWith.tun(enable: true));
    container.read(authorizedTunEnableProvider.notifier).value =
        TunAuthorizationState.authorized;
    await setup.setRunning(true, propagateErrors: true);
    expect(container.read(isStartProvider), isTrue);
    expect(container.read(windowsTunReadyProvider), isTrue);
    return h;
  }

  Future<Profile> refresh({String source = _newSource}) {
    return container
        .read(profilesActionProvider.notifier)
        .syncSubscriptionProfileBytes(
          Uint8List.fromList([1]),
          sourceId: source,
          replacingUrl: oldProfile.url,
          ruleAccountKey: _account,
          removeLegacyXboardProfiles: true,
          isCurrent: () => globalState.xboardRuleAccountKey == _account,
          loader: (profile, _) async {
            await beforeValidation?.call();
            final file = File(
              await appPath.getProfilePath(profile.id.toString()),
            );
            await file.parent.create(recursive: true);
            await file.writeAsString('validated-refreshed-fixture');
            return profile.copyWith(lastUpdateDate: DateTime.now());
          },
          effectClearer: (_) async {},
        );
  }

  Future<void> drainSetup() =>
      setup.applyProfile(force: true, silence: true, propagateErrors: true);
}

class _Setup extends SetupAction {
  final listeners = <bool>[];
  final appliedTun = <bool>[];
  final appliedProfiles = <int?>[];
  final failures = <Object?>[];
  Future<void> Function()? beforeApply;

  @override
  bool get requiresListenerReadiness => true;
  @override
  bool get requiresWindowsTunAuthorization => true;
  @override
  bool get requiresFullSetupAfterAuthorization => false;
  @override
  Future<bool> isTunServiceReady() async => true;
  @override
  Future<VM2<String, String>> getProfile({
    required SetupState setupState,
    required PatchClashConfig patchConfig,
    Map<String, String>? selectedMapOverride,
  }) async {
    final encoded = jsonEncode({
      'tun': patchConfig.tun.enable,
      'profile_id': setupState.profileId,
    });
    return VM2(encoded, encoded);
  }

  @override
  Future<String> applyCoreSetup({
    required SetupParams params,
    Future<void> Function()? preloadInvoke,
    Duration? timeout,
  }) async {
    final data =
        jsonDecode(await File(await appPath.configFilePath).readAsString())
            as Map<String, dynamic>;
    appliedTun.add(data['tun'] as bool);
    appliedProfiles.add(data['profile_id'] as int?);
    await beforeApply?.call();
    await preloadInvoke?.call();
    return '';
  }

  @override
  Future<String> applyCoreUpdate(UpdateParams params) async => '';
  @override
  Future<bool> setCoreRunning(bool running) async {
    listeners.add(running);
    return true;
  }

  @override
  Future<void> verifyLocalListener(
    int port, {
    required bool Function() isCancelled,
  }) async {}
  @override
  void resetCoreTraffic() {}
  @override
  void notifyListenerFailure(int port, {Object? error}) => failures.add(error);
  @override
  void notifyTunFailure(String code) => failures.add(code);
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

class _Paths extends PathProviderPlatform {
  _Paths(this.root);
  final String root;
  @override
  Future<String?> getApplicationSupportPath() async {
    final directory = Directory(
      p.join(root, windowsDataCompany, windowsDataProduct),
    );
    await directory.create(recursive: true);
    return directory.path;
  }

  @override
  Future<String?> getTemporaryPath() async => root;
  @override
  Future<String?> getApplicationCachePath() async => root;
}

XboardLoginResult _session() => XboardLoginResult(
  endpoint: Uri.parse('https://api.example.invalid/login'),
  token: 'synthetic-token',
  authData: 'synthetic-auth',
  isAdmin: false,
  subscription: XboardSubscriptionData(
    endpoint: Uri.parse('https://api.example.invalid/subscription'),
    subscribeUrl: null,
    uploadBytes: 0,
    downloadBytes: 0,
    transferEnableBytes: 100,
    rawData: const {},
  ),
);

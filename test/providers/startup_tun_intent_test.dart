import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/common/windows_identity.dart';
import 'package:fl_clash/common/tun_failure.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/l10n/l10n.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/state.dart';
import 'package:flutter/material.dart';
import 'package:fl_clash/manager/status_manager.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:riverpod/riverpod.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late File configuration;
  late bool previousNeedInitStatus;
  late String? previousMd5;

  setUpAll(() async {
    directory = await Directory.systemTemp.createTemp('startup_tun_intent');
    PathProviderPlatform.instance = _Paths(directory.path);
    configuration = File(await appPath.configFilePath);
    await AppLocalizations.load(const Locale('zh', 'CN'));
  });
  tearDownAll(() async {
    await commonPrint.flushDiagnosticEvents();
    await directory.delete(recursive: true);
  });
  setUp(() async {
    previousNeedInitStatus = globalState.needInitStatus;
    previousMd5 = globalState.lastConfigMd5;
    globalState.needInitStatus = true;
    globalState.lastConfigMd5 = null;
    globalState.clearXboardSession();
    globalState.setOfflineMode(false);
    await configuration.writeAsString('previous configuration');
  });
  tearDown(() {
    globalState.clearXboardSession();
    globalState.setOfflineMode(false);
    globalState.needInitStatus = previousNeedInitStatus;
    globalState.lastConfigMd5 = previousMd5;
  });

  for (final platform in ['windows', 'macos']) {
    test(
      '$platform failed listener stop cannot report cleanup success',
      () async {
        final rig = _Rig(platform);
        addTearDown(rig.container.dispose);
        rig.action.stopResult = false;
        await expectLater(rig.action.setRunning(false), throwsStateError);
        expect(rig.action.listeners, [false]);
        expect(rig.container.read(windowsTunReadyProvider), isFalse);
        rig.action.stopResult = true;
        await rig.action.setRunning(false);
        expect(rig.action.listeners, [false, false]);
      },
    );
    for (final loggedIn in [false, true]) {
      for (final cachedAuthorization in [false, true]) {
        test(
          '$platform startup and update keep saved TUN inactive: login=$loggedIn cached=$cachedAuthorization',
          () async {
            if (loggedIn) globalState.activateXboardSession(_session());
            final rig = _Rig(platform, cached: cachedAuthorization);
            addTearDown(rig.container.dispose);

            await rig.action.initStatus();
            await rig.action.updateConfig();

            expect(rig.action.authorizations, 0);
            expect(rig.action.readinessChecks, 0);
            expect(rig.action.preparedTun, [false]);
            expect(rig.action.appliedTun, [false]);
            expect(rig.action.updatedTun, [false]);
            expect(rig.action.listeners, isEmpty);
            expect(rig.action.failures, isEmpty);
            expect(rig.action.restarts, 0);
            expect(rig.container.read(isStartProvider), isFalse);
            expect(rig.container.read(windowsTunReadyProvider), isFalse);
            expect(
              rig.container.read(patchClashConfigProvider).tun.enable,
              isTrue,
            );
          },
        );
      }
    }
    for (final cachedAuthorization in [false, true]) {
      test(
        '$platform explicit connection activates saved TUN: cached=$cachedAuthorization',
        () async {
          globalState.activateXboardSession(_session());
          final rig = _Rig(platform, cached: cachedAuthorization);
          addTearDown(rig.container.dispose);
          await rig.action.initStatus();

          await rig.action.setRunning(true, propagateErrors: true);

          expect(rig.action.authorizations, cachedAuthorization ? 0 : 1);
          expect(rig.action.appliedTun, [false, true]);
          expect(rig.action.listeners, contains(true));
          expect(rig.container.read(isStartProvider), isTrue);
          expect(rig.container.read(windowsTunReadyProvider), isTrue);
          expect(
            rig.container.read(patchClashConfigProvider).tun.enable,
            isTrue,
          );
          expect(rig.action.failures, isEmpty);
          await rig.action.setRunning(false);
        },
      );
    }
    test(
      '$platform offline connection does not require a login session',
      () async {
        globalState.setOfflineMode(true);
        final rig = _Rig(platform);
        addTearDown(rig.container.dispose);

        await rig.action.setRunning(true, propagateErrors: true);

        expect(rig.action.authorizations, 1);
        expect(rig.action.appliedTun, [true]);
        expect(rig.container.read(isStartProvider), isTrue);
        expect(rig.action.failures, isEmpty);
        await rig.action.setRunning(false);
      },
    );
    for (final failAuthorization in [false, true]) {
      test(
        '$platform logout cancels a late authorization: failure=$failAuthorization',
        () async {
          globalState.activateXboardSession(_session());
          final rig = _Rig(platform);
          addTearDown(rig.container.dispose);
          rig.action.pendingAuthorization = Completer<AuthorizeCode>();
          final starting = rig.action.setRunning(true, propagateErrors: true);
          await rig.action.authorizationEntered.future;

          await rig.action.setRunning(false);
          globalState.clearXboardSession();
          if (failAuthorization) {
            rig.action.pendingAuthorization!.completeError(
              TunFailure.elevation(1223),
            );
          } else {
            rig.action.pendingAuthorization!.complete(AuthorizeCode.none);
          }
          await starting;

          expect(rig.action.listeners.where((value) => value), isEmpty);
          expect(rig.action.appliedTun, isEmpty);
          expect(rig.action.failures, isEmpty);
          expect(rig.action.restarts, 0);
          expect(rig.container.read(isStartProvider), isFalse);
          expect(rig.container.read(connectionPendingProvider), isFalse);
          expect(
            rig.container.read(patchClashConfigProvider).tun.enable,
            isTrue,
          );
        },
      );
    }
    test(
      '$platform stop during configuration preparation prevents stale TUN apply',
      () async {
        final rig = _Rig(platform, cached: true);
        addTearDown(rig.container.dispose);
        rig.action.pendingPreparation = Completer<void>();
        final starting = rig.action.setRunning(true, propagateErrors: true);
        await rig.action.preparationEntered.future;

        await rig.action.setRunning(false);
        rig.action.pendingPreparation!.complete();
        await starting;

        expect(rig.action.appliedTun, isEmpty);
        expect(rig.action.listeners.where((value) => value), isEmpty);
        expect(rig.action.failures, isEmpty);
        expect(await configuration.readAsString(), 'previous configuration');
        expect(rig.container.read(patchClashConfigProvider).tun.enable, isTrue);
      },
    );
    test(
      '$platform same-account refresh does not cancel an explicit connection',
      () async {
        globalState.activateXboardSession(_session());
        final rig = _Rig(platform, cached: true);
        addTearDown(rig.container.dispose);
        rig.action.pendingPreparation = Completer<void>();
        final starting = rig.action.setRunning(true, propagateErrors: true);
        await rig.action.preparationEntered.future;

        globalState.activateXboardSession(_session());
        rig.action.pendingPreparation!.complete();
        await starting;

        expect(rig.action.appliedTun, [true]);
        expect(rig.container.read(isStartProvider), isTrue);
        expect(rig.action.failures, isEmpty);
        await rig.action.setRunning(false);
      },
    );
  }

  for (final platform in ['windows', 'macos']) {
    for (final strict in [false, true]) {
      test(
        '$platform caller cancellation during core setup preserves connection: strict=$strict',
        () async {
          final rig = _Rig(platform);
          addTearDown(rig.container.dispose);
          rig.container
              .read(patchClashConfigProvider.notifier)
              .update((state) => state.copyWith.tun(enable: false));
          await rig.action.setRunning(true, propagateErrors: true);
          rig.action.appliedProfiles.clear();
          rig.action.listeners.clear();
          rig.action.setupEntered = Completer<void>();
          final pending = Completer<String>();
          rig.action.onSetup = (_) => pending.future;
          var current = true;
          final applying = rig.action.applyProfile(
            force: true,
            silence: true,
            propagateErrors: strict,
            isCurrent: () => current,
            profileOverride: const Profile(
              id: 202,
              label: 'Old candidate',
              autoUpdateDuration: Duration(days: 1),
            ),
          );
          final completed = strict
              ? expectLater(
                  applying,
                  throwsA(
                    isA<StateError>().having(
                      (error) => error.message,
                      'message',
                      'configuration_apply_superseded',
                    ),
                  ),
                )
              : applying;
          await rig.action.setupEntered.future;
          current = false;
          rig.action.onSetup = null;
          final latest = rig.action.applyProfile(
            force: true,
            silence: true,
            propagateErrors: true,
            isCurrent: () => true,
            profileOverride: const Profile(
              id: 303,
              label: 'Latest candidate',
              autoUpdateDuration: Duration(days: 1),
            ),
          );
          pending.complete('');
          await completed;
          await latest;

          expect(rig.action.appliedProfiles, [202, 303]);
          expect(rig.action.restarts, 0);
          expect(rig.action.failures, isEmpty);
          expect(rig.action.listeners, isEmpty);
          expect(rig.container.read(currentProfileProvider)?.id, 101);
          expect(rig.container.read(isStartProvider), isTrue);
          expect(rig.container.read(connectionPendingProvider), isFalse);
          expect(
            jsonDecode(await configuration.readAsString())['profile_id'],
            303,
          );
          await rig.action.setRunning(false);
        },
      );
    }
  }

  for (final platform in ['windows', 'macos']) {
    test(
      '$platform current core setup failure remains a real connection failure',
      () async {
        final rig = _Rig(platform);
        addTearDown(rig.container.dispose);
        rig.container
            .read(patchClashConfigProvider.notifier)
            .update((state) => state.copyWith.tun(enable: false));
        await rig.action.setRunning(true, propagateErrors: true);
        rig.action.onSetup = (count) async =>
            count == 2 ? 'current configuration rejected' : '';

        await expectLater(
          rig.action.applyProfile(
            force: true,
            silence: true,
            propagateErrors: true,
            isCurrent: () => true,
          ),
          throwsA('current configuration rejected'),
        );

        expect(rig.action.failures, ['current configuration rejected']);
        expect(rig.action.restarts, 1);
        expect(rig.container.read(isStartProvider), isFalse);
        expect(rig.container.read(connectionPendingProvider), isFalse);
      },
    );
  }

  for (final platform in ['windows', 'macos']) {
    test(
      '$platform strict candidate cannot commit after stop when caller still accepts it',
      () async {
        final rig = _Rig(platform);
        addTearDown(rig.container.dispose);
        rig.container
            .read(patchClashConfigProvider.notifier)
            .update((state) => state.copyWith.tun(enable: false));
        await rig.action.setRunning(true, propagateErrors: true);
        rig.action.setupEntered = Completer<void>();
        final pending = Completer<String>();
        rig.action.onSetup = (_) => pending.future;
        var candidateCommitted = false;
        final applying = rig.action
            .applyProfile(
              force: true,
              silence: true,
              propagateErrors: true,
              isCurrent: () => true,
              profileOverride: const Profile(
                id: 202,
                label: 'Uncommitted candidate',
                autoUpdateDuration: Duration(days: 1),
              ),
            )
            .then((_) => candidateCommitted = true);
        final cancelled = expectLater(
          applying,
          throwsA(
            isA<StateError>().having(
              (error) => error.message,
              'message',
              'configuration_apply_superseded',
            ),
          ),
        );
        await rig.action.setupEntered.future;
        await rig.action.setRunning(false);
        pending.complete('');
        await cancelled;

        expect(candidateCommitted, isFalse);
        expect(rig.container.read(currentProfileProvider)?.id, 101);
        expect(rig.action.restarts, 0);
        expect(rig.action.failures, isEmpty);
        expect(rig.container.read(isStartProvider), isFalse);
        expect(
          jsonDecode(await configuration.readAsString())['profile_id'],
          101,
        );
      },
    );
  }

  testWidgets(
    'Mac caller cancellation does not use the global notifier channel',
    (tester) async {
      final notifications = <String>[];
      await tester.pumpWidget(
        _CapturingStatus(
          notifications: notifications,
          child: MaterialApp(
            navigatorKey: globalState.navigatorKey,
            home: const SizedBox(),
          ),
        ),
      );
      globalState.showNotifier('fixture control');
      expect(notifications, ['fixture control']);
      notifications.clear();
      await tester.runAsync(() async {
        final rig = _Rig('macos');
        try {
          rig.container
              .read(patchClashConfigProvider.notifier)
              .update((state) => state.copyWith.tun(enable: false));
          await rig.action.setRunning(true, propagateErrors: true);
          rig.action.setupEntered = Completer<void>();
          final pending = Completer<String>();
          rig.action.onSetup = (_) => pending.future;
          var current = true;
          final applying = rig.action.applyProfile(
            force: true,
            silence: true,
            isCurrent: () => current,
          );
          await rig.action.setupEntered.future;
          current = false;
          pending.complete('');
          await applying;
          expect(notifications, isEmpty);
          expect(rig.action.failures, isEmpty);
          expect(rig.container.read(isStartProvider), isTrue);
          await rig.action.setRunning(false);
        } finally {
          rig.container.dispose();
        }
      });
      await tester.pumpWidget(const SizedBox());
    },
  );

  for (final platform in ['windows', 'macos']) {
    test(
      '$platform superseded authorization recovery cannot stop a later request',
      () async {
        final rig = _Rig(platform);
        addTearDown(rig.container.dispose);
        rig.container
            .read(patchClashConfigProvider.notifier)
            .update((state) => state.copyWith.tun(enable: false));
        await rig.action.setRunning(true, propagateErrors: true);
        rig.container
            .read(patchClashConfigProvider.notifier)
            .update((state) => state.copyWith.tun(enable: true));
        rig.action.authorizationResult = AuthorizeCode.success;
        final restarted = Completer<void>();
        final releaseRestart = Completer<void>();
        final recovering = Completer<void>();
        final releaseRecovery = Completer<void>();
        rig.action.onRestart = (count) async {
          if (count == 1) {
            restarted.complete();
            await releaseRestart.future;
          } else if (count == 2) {
            recovering.complete();
            await releaseRecovery.future;
          }
        };
        var current = true;
        final applying = rig.action.applyProfile(
          force: true,
          silence: true,
          propagateErrors: true,
          isCurrent: () => current,
        );
        final cancelled = expectLater(
          applying,
          throwsA(
            isA<StateError>().having(
              (error) => error.message,
              'message',
              'configuration_apply_superseded',
            ),
          ),
        );
        await restarted.future;
        current = false;
        releaseRestart.complete();
        await recovering.future;
        await rig.action.setRunning(false);
        releaseRecovery.completeError(
          StateError('obsolete recovery restart failed'),
        );
        await cancelled;

        expect(rig.action.lifecycleStops, 0);
        expect(rig.action.failures, isEmpty);
        expect(rig.container.read(isStartProvider), isFalse);
        expect(rig.container.read(connectionPendingProvider), isFalse);
      },
    );
  }

  test(
    'Windows explicit TUN entry initializes safely before requesting authorization',
    () async {
      final rig = _Rig('windows');
      addTearDown(rig.container.dispose);

      await rig.action.enableWindowsTun();

      expect(rig.action.appliedTun, [false, true]);
      expect(rig.action.authorizations, 1);
      expect(rig.container.read(isStartProvider), isTrue);
      expect(rig.action.failures, isEmpty);
      await rig.action.setRunning(false);
    },
  );

  for (final cached in [false, true]) {
    test(
      'non-desktop apply and update retain previous TUN behavior: cached=$cached',
      () async {
        final rig = _Rig('mobile', cached: cached);
        addTearDown(rig.container.dispose);

        await rig.action.applyProfile(force: true, propagateErrors: true);
        await rig.action.updateConfig();

        expect(rig.action.authorizations, cached ? 0 : 1);
        expect(rig.action.appliedTun, [true]);
        expect(rig.action.updatedTun, [true]);
        expect(rig.container.read(isStartProvider), isFalse);
        expect(rig.container.read(patchClashConfigProvider).tun.enable, isTrue);
      },
    );
  }
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

class _Rig {
  _Rig(String platform, {bool cached = false}) {
    action = _IntentSetup(platform);
    container = ProviderContainer(
      overrides: [
        initProvider.overrideWithBuild((_, _) => true),
        currentProfileProvider.overrideWithValue(
          const Profile(
            id: 101,
            label: 'Local fixture',
            autoUpdateDuration: Duration(days: 1),
          ),
        ),
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
        setupActionProvider.overrideWith(() => action),
        commonActionProvider.overrideWith(_QuietCommon.new),
        proxiesActionProvider.overrideWith(_QuietProxies.new),
        providersProvider.overrideWith(_QuietProviders.new),
      ],
    );
    globalState.container = container;
    container.read(setupActionProvider);
    container
        .read(patchClashConfigProvider.notifier)
        .update((state) => state.copyWith.tun(enable: true));
    container.read(authorizedTunEnableProvider.notifier).value = cached
        ? TunAuthorizationState.authorized
        : TunAuthorizationState.none;
  }
  late final ProviderContainer container;
  late final _IntentSetup action;
}

class _IntentSetup extends SetupAction {
  _IntentSetup(this.platform);
  final String platform;
  int authorizations = 0;
  int readinessChecks = 0;
  int restarts = 0;
  int lifecycleStops = 0;
  bool stopResult = true;
  AuthorizeCode authorizationResult = AuthorizeCode.none;
  Future<void> Function(int count)? onRestart;
  final preparedTun = <bool>[];
  final appliedTun = <bool>[];
  final appliedProfiles = <int?>[];
  var setupEntered = Completer<void>();
  Future<String> Function(int count)? onSetup;
  final updatedTun = <bool>[];
  final listeners = <bool>[];
  final failures = <Object?>[];
  final authorizationEntered = Completer<void>();
  final preparationEntered = Completer<void>();
  Completer<AuthorizeCode>? pendingAuthorization;
  Completer<void>? pendingPreparation;

  @override
  bool get requiresListenerReadiness => platform != 'mobile';
  @override
  bool get requiresWindowsTunAuthorization => platform == 'windows';
  @override
  bool get requiresFullSetupAfterAuthorization => platform == 'macos';
  @override
  Future<bool> isTunServiceReady() async {
    readinessChecks++;
    return true;
  }

  @override
  Future<AuthorizeCode> authorizeCore() async {
    authorizations++;
    if (!authorizationEntered.isCompleted) authorizationEntered.complete();
    return await pendingAuthorization?.future ?? authorizationResult;
  }

  @override
  Future<VM2<String, String>> getProfile({
    required SetupState setupState,
    required PatchClashConfig patchConfig,
    Map<String, String>? selectedMapOverride,
  }) async {
    preparedTun.add(patchConfig.tun.enable);
    if (!preparationEntered.isCompleted) preparationEntered.complete();
    await pendingPreparation?.future;
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
    if (!setupEntered.isCompleted) setupEntered.complete();
    final message =
        await (onSetup?.call(appliedTun.length) ?? Future.value(''));
    if (message.isEmpty) await preloadInvoke?.call();
    return message;
  }

  @override
  Future<String> applyCoreUpdate(UpdateParams params) async {
    updatedTun.add(params.tun.enable);
    return '';
  }

  @override
  Future<void> restartCoreLifecycleOnly() async {
    restarts++;
    await onRestart?.call(restarts);
  }

  @override
  Future<void> stopCoreLifecycleOnly() async {
    lifecycleStops++;
  }

  @override
  Future<bool> setCoreRunning(bool running) async {
    listeners.add(running);
    return running || stopResult;
  }

  @override
  Future<void> verifyLocalListener(
    int port, {
    required bool Function() isCancelled,
  }) async {}
  @override
  Future<void> ensureTunCoreReady() =>
      applyProfile(force: true, propagateErrors: true);
  @override
  VoidCallback showTunProgress() => () {};
  @override
  void resetCoreTraffic() {}
  @override
  void notifyListenerFailure(int port, {Object? error}) {
    failures.add(error);
  }

  @override
  void notifyTunFailure(String code) {
    failures.add(code);
  }
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

class _CapturingStatus extends StatusManager {
  const _CapturingStatus({required this.notifications, required super.child});

  final List<String> notifications;

  @override
  State<StatusManager> createState() => _CapturingStatusState();
}

class _CapturingStatusState extends StatusManagerState {
  List<String> get notifications => (widget as _CapturingStatus).notifications;

  @override
  void message(String text, {MessageActionState? actionState}) {
    notifications.add(text);
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

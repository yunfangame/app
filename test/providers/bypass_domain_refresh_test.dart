import 'dart:async';

import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('disconnected profile refresh never starts VPN', () async {
    final rig = _Rig();
    await rig.action.refresh();
    expect(rig.action.events, ['apply']);
  });

  test('connected refresh applies then syncs before native restart', () async {
    final rig = _Rig(running: true);
    final before = rig.container.read(vpnSettingProvider);
    await rig.action.refresh();
    expect(rig.action.events, ['apply', 'sync', 'restart']);
    expect(rig.container.read(vpnSettingProvider), before);
  });

  test('desktop refresh does not request a VPN restart', () async {
    final rig = _Rig(running: true);
    rig.action.supported = false;
    await rig.action.refresh();
    expect(rig.action.events, ['apply']);
  });

  test('disconnect during apply prevents delayed reconnect', () async {
    final rig = _Rig(running: true);
    rig.action.applyGate = Completer<void>();
    final refreshing = rig.action.refresh();
    await rig.action.applyEntered.future;
    rig.container.read(runTimeProvider.notifier).value = null;
    rig.action.applyGate!.complete();
    await refreshing;
    expect(rig.action.events, ['apply']);
  });

  test('disconnect during synchronization prevents restart', () async {
    final rig = _Rig(running: true);
    rig.action.syncGate = Completer<void>();
    final refreshing = rig.action.refresh();
    await rig.action.syncEntered.future;
    rig.container.read(runTimeProvider.notifier).value = null;
    rig.action.syncGate!.complete();
    await refreshing;
    expect(rig.action.events, ['apply', 'sync']);
  });

  test('disposal during apply never reconnects', () async {
    final rig = _Rig(running: true);
    rig.action.applyGate = Completer<void>();
    final refreshing = rig.action.refresh();
    await rig.action.applyEntered.future;
    rig.container.dispose();
    rig.action.applyGate!.complete();
    await refreshing;
    expect(rig.action.events, ['apply']);
  });

  test('failed sync reports failure without a restart', () async {
    final rig = _Rig(running: true);
    rig.action.syncFailure = StateError('sync failed');
    await rig.action.refresh();
    expect(rig.action.events, ['apply', 'sync', 'failure']);
  });

  test('rejected restart reports failure', () async {
    final rig = _Rig(running: true);
    rig.action.restartAccepted = false;
    await rig.action.refresh();
    expect(rig.action.events, ['apply', 'sync', 'restart', 'failure']);
  });

  test('rapid domain and DNS edits merge into one native refresh', () async {
    final rig = _Rig(running: true);
    final network = rig.container.read(networkSettingProvider.notifier);
    network.update((state) => state.copyWith(bypassDomainRouting: true));
    network.update((state) => state.copyWith(bypassDomain: ['*.corp.example']));
    network.update((state) => state.copyWith(bypassDomainDns: '10.0.0.53'));
    await rig.action.restartEntered.future;
    expect(rig.action.events, ['apply', 'sync', 'restart']);
  });

  test('newer setting supersedes a refresh waiting on apply', () async {
    final rig = _Rig(running: true);
    rig.action.applyGate = Completer<void>();
    final previous = rig.action.refresh();
    await rig.action.applyEntered.future;
    rig.container
        .read(networkSettingProvider.notifier)
        .update((state) => state.copyWith(bypassDomainRouting: true));
    rig.action.applyGate!.complete();
    await previous;
    expect(rig.action.events, ['apply']);
    rig.action.applyGate = null;
    await rig.action.restartEntered.future;
    expect(rig.action.events, ['apply', 'apply', 'sync', 'restart']);
  });
}

class _Rig {
  late final ProviderContainer container;
  late final _RefreshSetup action;

  _Rig({bool running = false}) {
    container = ProviderContainer(
      overrides: [
        initProvider.overrideWithBuild((_, _) => true),
        runTimeProvider.overrideWithBuild((_, _) => running ? 0 : null),
        sharedStateProvider.overrideWithValue(
          const SharedState(
            stopTip: '',
            startTip: '',
            currentProfileName: '',
            stopText: '',
            onlyStatisticsProxy: false,
            crashlytics: false,
          ),
        ),
        setupActionProvider.overrideWith(() => action = _RefreshSetup()),
      ],
    );
    container.read(setupActionProvider);
    addTearDown(container.dispose);
  }
}

class _RefreshSetup extends SetupAction {
  final events = <String>[];
  final applyEntered = Completer<void>();
  final syncEntered = Completer<void>();
  final restartEntered = Completer<void>();
  Completer<void>? applyGate;
  Completer<void>? syncGate;
  Object? syncFailure;
  bool restartAccepted = true;
  bool supported = true;

  Future<void> refresh() => refreshBypassProfile();

  @override
  bool get supportsBypassVpnRefresh => supported;

  @override
  Future<void> applyProfile({
    bool silence = false,
    bool force = false,
    Future<void> Function()? preloadInvoke,
  }) async {
    expect(silence, isTrue);
    expect(force, isTrue);
    events.add('apply');
    if (!applyEntered.isCompleted) applyEntered.complete();
    await applyGate?.future;
  }

  @override
  Future<void> syncBypassVpnState(SharedState state) async {
    events.add('sync');
    if (!syncEntered.isCompleted) syncEntered.complete();
    await syncGate?.future;
    if (syncFailure != null) throw syncFailure!;
  }

  @override
  Future<bool> requestBypassVpnRestart() async {
    events.add('restart');
    if (!restartEntered.isCompleted) restartEntered.complete();
    return restartAccepted;
  }

  @override
  void notifyBypassRefreshFailure() => events.add('failure');
}

import 'dart:async';

import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:riverpod/riverpod.dart';

const _selected = AccessControlProps(
  enable: true,
  rejectList: ['com.example.b', 'com.example.a', 'com.example.a'],
);

void main() {
  test(
    'disconnected save persists normalized lists without starting VPN',
    () async {
      final rig = _Rig();
      final result = await rig.action.applyAccessControl(_selected);

      expect(result, AccessControlApplyResult.saved);
      expect(rig.action.saved.single.vpnProps.accessControlProps.rejectList, [
        'com.example.a',
        'com.example.b',
      ]);
      expect(
        rig.container.read(vpnSettingProvider).accessControlProps.enable,
        isTrue,
      );
      expect(rig.action.events, ['persist']);
      expect(rig.container.read(isStartProvider), isFalse);
    },
  );

  test(
    'failed storage keeps current settings and a retry can succeed',
    () async {
      final rig = _Rig(running: true);
      rig.action.persistResult = false;

      await expectLater(
        rig.action.applyAccessControl(_selected),
        throwsStateError,
      );
      expect(
        rig.container.read(vpnSettingProvider).accessControlProps.enable,
        isFalse,
      );
      expect(rig.action.events, ['persist']);

      rig.action.persistResult = true;
      expect(
        await rig.action.applyAccessControl(_selected),
        AccessControlApplyResult.reconnectRequested,
      );
      expect(rig.action.events, ['persist', 'persist', 'sync', 'restart']);
    },
  );

  test(
    'connected save persists and synchronizes before one restart request',
    () async {
      final rig = _Rig(running: true);
      final result = await rig.action.applyAccessControl(_selected);

      expect(result, AccessControlApplyResult.reconnectRequested);
      expect(rig.action.events, ['persist', 'sync', 'restart']);
      expect(rig.action.transitions, isEmpty);
    },
  );

  test(
    'display-only changes and reordered identical lists do not reconnect',
    () async {
      final rig = _Rig(running: true, initial: _selected);
      final result = await rig.action.applyAccessControl(
        _selected.copyWith(
          rejectList: ['com.example.a', 'com.example.b'],
          isFilterSystemApp: false,
          sort: AccessSortType.name,
        ),
      );

      expect(result, AccessControlApplyResult.saved);
      expect(rig.action.events, ['persist']);
    },
  );

  test(
    'stop during persistence preserves the save and prevents a restart',
    () async {
      final rig = _Rig(running: true);
      rig.action.persistGate = Completer<bool>();
      final saving = rig.action.applyAccessControl(_selected);
      await rig.action.persistEntered.future;

      await rig.action.setRunning(false);
      rig.action.persistGate!.complete(true);

      expect(await saving, AccessControlApplyResult.superseded);
      expect(
        rig.container.read(vpnSettingProvider).accessControlProps.enable,
        isTrue,
      );
      expect(rig.container.read(isStartProvider), isFalse);
      expect(rig.action.events, ['persist']);
      expect(rig.action.transitions, [false]);
    },
  );

  test(
    'stop during state synchronization prevents a delayed restart',
    () async {
      final rig = _Rig(running: true);
      rig.action.syncGate = Completer<void>();
      final saving = rig.action.applyAccessControl(_selected);
      await rig.action.syncEntered.future;

      await rig.action.setRunning(false);
      rig.action.syncGate!.complete();

      expect(await saving, AccessControlApplyResult.superseded);
      expect(rig.action.events, ['persist', 'sync']);
      expect(rig.container.read(isStartProvider), isFalse);
    },
  );

  test('same selection retries state synchronization after failure', () async {
    final rig = _Rig(running: true);
    rig.action.syncFailure = StateError('sync failed');

    await expectLater(
      rig.action.applyAccessControl(_selected),
      throwsStateError,
    );
    expect(rig.action.hasPendingAccessControlReconnect, isTrue);
    expect(
      rig.container
          .read(setupActionProvider.notifier)
          .hasPendingAccessControlReconnect,
      isTrue,
    );
    rig.action.syncFailure = null;

    expect(
      await rig.action.applyAccessControl(_selected),
      AccessControlApplyResult.reconnectRequested,
    );
    expect(rig.action.events, [
      'persist',
      'sync',
      'persist',
      'sync',
      'restart',
    ]);
    expect(rig.action.hasPendingAccessControlReconnect, isFalse);
  });

  test('same selection retries a rejected restart request', () async {
    final rig = _Rig(running: true);
    rig.action.restartResult = false;

    await expectLater(
      rig.action.applyAccessControl(_selected),
      throwsStateError,
    );
    expect(rig.action.hasPendingAccessControlReconnect, isTrue);
    rig.action.restartResult = true;

    expect(
      await rig.action.applyAccessControl(_selected),
      AccessControlApplyResult.reconnectRequested,
    );
    expect(
      rig.action.events.where((event) => event == 'restart'),
      hasLength(2),
    );
    expect(rig.action.hasPendingAccessControlReconnect, isFalse);
  });

  test(
    'saving after a later disconnect clears pending reconnect without starting',
    () async {
      final rig = _Rig(running: true);
      rig.action.restartResult = false;
      await expectLater(
        rig.action.applyAccessControl(_selected),
        throwsStateError,
      );
      expect(rig.action.hasPendingAccessControlReconnect, isTrue);
      await rig.action.setRunning(false);

      expect(
        await rig.action.applyAccessControl(_selected),
        AccessControlApplyResult.saved,
      );
      expect(rig.action.hasPendingAccessControlReconnect, isFalse);
      expect(rig.container.read(isStartProvider), isFalse);
      expect(
        rig.action.events.where((event) => event == 'restart'),
        hasLength(1),
      );
    },
  );

  test(
    'newer duplicate save supersedes the first but still requests restart',
    () async {
      final rig = _Rig(running: true);
      rig.action.persistGate = Completer<bool>();
      final first = rig.action.applyAccessControl(_selected);
      await rig.action.persistEntered.future;
      final second = rig.action.applyAccessControl(_selected);
      rig.action.persistGate!.complete(true);

      expect(await first, AccessControlApplyResult.superseded);
      expect(await second, AccessControlApplyResult.reconnectRequested);
      expect(rig.action.events, ['persist', 'persist', 'sync', 'restart']);
    },
  );

  test('newer save wins on disk and in settings', () async {
    final rig = _Rig(running: true);
    rig.action.persistGate = Completer<bool>();
    final first = rig.action.applyAccessControl(_selected);
    await rig.action.persistEntered.future;
    final second = rig.action.applyAccessControl(
      _selected.copyWith(rejectList: ['com.example.new']),
    );
    rig.action.persistGate!.complete(true);

    expect(await first, AccessControlApplyResult.superseded);
    expect(await second, AccessControlApplyResult.reconnectRequested);
    expect(rig.action.saved.last.vpnProps.accessControlProps.rejectList, [
      'com.example.new',
    ]);
    expect(
      rig.container.read(vpnSettingProvider).accessControlProps.rejectList,
      ['com.example.new'],
    );
    expect(
      rig.action.events.where((event) => event == 'restart'),
      hasLength(1),
    );
  });

  test('disposal while saving never reconnects', () async {
    final rig = _Rig(running: true);
    rig.action.persistGate = Completer<bool>();
    final saving = rig.action.applyAccessControl(_selected);
    await rig.action.persistEntered.future;
    rig.container.dispose();
    rig.action.persistGate!.complete(true);

    expect(await saving, AccessControlApplyResult.superseded);
    expect(rig.action.events, ['persist']);
  });

  test(
    'only managed application changes suppress the VPN restart tip',
    () async {
      final rig = _Rig();
      final previous = VpnState(
        stack: TunStack.mixed,
        vpnProps: rig.container.read(vpnSettingProvider),
      );
      await rig.action.applyAccessControl(_selected);
      final next = previous.copyWith(
        vpnProps: rig.container.read(vpnSettingProvider),
      );

      expect(
        rig.action.consumeHandledAccessControlChange(previous, next),
        isTrue,
      );
      expect(
        rig.action.consumeHandledAccessControlChange(previous, next),
        isFalse,
      );
      await rig.action.applyAccessControl(_selected);
      expect(
        rig.action.consumeHandledAccessControlChange(
          previous,
          next.copyWith(stack: TunStack.system),
        ),
        isFalse,
      );
      await rig.action.applyAccessControl(_selected);
      expect(
        rig.action.consumeHandledAccessControlChange(
          previous,
          next.copyWith.vpnProps(ipv6: !next.vpnProps.ipv6),
        ),
        isFalse,
      );
      await rig.action.applyAccessControl(_selected);
      expect(
        rig.action.consumeHandledAccessControlChange(
          previous,
          next.copyWith.vpnProps(
            accessControlProps: _selected.copyWith(rejectList: ['unmanaged']),
          ),
        ),
        isFalse,
      );
    },
  );

  test(
    'desktop calls fail without persistence or platform mutations',
    () async {
      final rig = _Rig();
      rig.action.supported = false;

      await expectLater(
        rig.action.applyAccessControl(_selected),
        throwsUnsupportedError,
      );
      expect(rig.action.events, isEmpty);
    },
  );
}

class _Rig {
  late final ProviderContainer container;
  late final _AccessControlSetupAction action;

  _Rig({
    bool running = false,
    AccessControlProps initial = const AccessControlProps(),
  }) {
    container = ProviderContainer(
      overrides: [
        vpnSettingProvider.overrideWithBuild(
          (_, _) => VpnProps(accessControlProps: initial),
        ),
        runTimeProvider.overrideWithBuild((_, _) => running ? 0 : null),
        configProvider.overrideWith(
          (ref) => Config(
            vpnProps: ref.watch(vpnSettingProvider),
            themeProps: defaultThemeProps,
          ),
        ),
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
        setupActionProvider.overrideWith(() {
          action = _AccessControlSetupAction();
          return action;
        }),
      ],
    );
    container.read(setupActionProvider);
    addTearDown(container.dispose);
  }
}

class _AccessControlSetupAction extends SetupAction {
  final events = <String>[];
  final saved = <Config>[];
  final transitions = <bool>[];
  final persistEntered = Completer<void>();
  final syncEntered = Completer<void>();
  Completer<bool>? persistGate;
  Completer<void>? syncGate;
  Object? syncFailure;
  bool persistResult = true;
  bool restartResult = true;
  bool supported = true;

  @override
  bool get supportsAppAccessControl => supported;

  @override
  bool get requiresListenerReadiness => false;

  @override
  Future<bool> persistAccessControlConfig(Config config) async {
    events.add('persist');
    saved.add(config);
    if (!persistEntered.isCompleted) persistEntered.complete();
    return await persistGate?.future ?? persistResult;
  }

  @override
  Future<void> syncAccessControlState(SharedState state) async {
    events.add('sync');
    if (!syncEntered.isCompleted) syncEntered.complete();
    await syncGate?.future;
    if (syncFailure != null) throw syncFailure!;
  }

  @override
  Future<bool> requestAccessControlRestart() async {
    events.add('restart');
    return restartResult;
  }

  @override
  Future<bool> setCoreRunning(bool running) async {
    transitions.add(running);
    return true;
  }

  @override
  void resetCoreTraffic() {}
}

import 'dart:async';

import 'package:fl_clash/core/controller.dart';
import 'package:fl_clash/core/interface.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:riverpod/riverpod.dart';

const _sharedNode = Proxy(name: 'Shared node', type: 'Shadowsocks');
const _routeNode = Proxy(name: 'Route old', type: 'Trojan');
const _globalNode = Proxy(name: 'Global old', type: 'VLESS');
const _outerNode = Proxy(name: 'Outer old', type: 'Trojan');
const _innerNode = Proxy(name: 'Inner old', type: 'VLESS');
const _directNode = Proxy(name: 'DIRECT', type: 'Direct');

const _flatGroups = [
  Group(
    name: 'GLOBAL',
    type: GroupType.Selector,
    hidden: true,
    now: 'Global old',
    all: [_globalNode, _sharedNode],
  ),
  Group(
    name: 'Route',
    type: GroupType.Selector,
    hidden: false,
    now: 'Route old',
    all: [_routeNode, _sharedNode, _directNode],
  ),
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    registerFallbackValue(
      const ChangeProxyParams(groupName: 'GLOBAL', proxyName: 'Global old'),
    );
  });

  test('rule to global inherits the active rule leaf', () async {
    final initialProfile = _profile(
      globalSelection: _globalNode.name,
      routeSelection: _sharedNode.name,
    );
    final harness = _Harness(
      initialMode: Mode.rule,
      initialProfile: initialProfile,
    );

    expect(
      await harness.setup.changeModeAndWait(Mode.global),
      ModeSwitchResult.switched,
    );

    expect(harness.mode, Mode.global);
    expect(harness.profile.currentGroupName, 'GLOBAL');
    expect(harness.profile.selectedMap['GLOBAL'], _sharedNode.name);
    expect(harness.coreSelections['GLOBAL'], _sharedNode.name);
    expect(harness.changes, [
      const ChangeProxyParams(groupName: 'GLOBAL', proxyName: 'Shared node'),
    ]);
    expect(harness.modeUpdates.map((params) => params.mode), [Mode.global]);
    expect(
      harness.events.indexOf('select:GLOBAL:Shared node'),
      lessThan(harness.events.indexOf('mode:global')),
    );
  });

  test('global to rule inherits the active global leaf', () async {
    final initialProfile = _profile(
      globalSelection: _sharedNode.name,
      routeSelection: _routeNode.name,
    );
    final harness = _Harness(
      initialMode: Mode.global,
      initialProfile: initialProfile,
    );

    expect(
      await harness.setup.changeModeAndWait(Mode.rule),
      ModeSwitchResult.switched,
    );

    expect(harness.mode, Mode.rule);
    expect(harness.profile.currentGroupName, 'Route');
    expect(harness.profile.selectedMap['Route'], _sharedNode.name);
    expect(harness.coreSelections['Route'], _sharedNode.name);
    expect(harness.changes, [
      const ChangeProxyParams(groupName: 'Route', proxyName: 'Shared node'),
    ]);
    expect(harness.modeUpdates.map((params) => params.mode), [Mode.rule]);
  });

  test('direct MATCH leaf keeps a valid rule display group', () async {
    final initialProfile = _profile(
      globalSelection: _sharedNode.name,
      routeSelection: _routeNode.name,
    ).copyWith(currentGroupName: 'GLOBAL');
    final harness = _Harness(
      initialMode: Mode.global,
      initialProfile: initialProfile,
      ruleGroupName: _sharedNode.name,
    );

    expect(
      await harness.setup.changeModeAndWait(Mode.rule),
      ModeSwitchResult.switched,
    );

    expect(harness.mode, Mode.rule);
    expect(harness.profile.currentGroupName, 'Route');
    expect(harness.profile.selectedMap, initialProfile.selectedMap);
    expect(harness.changes, isEmpty);
  });

  test('nested target selectors are written from inner to outer', () async {
    const groups = [
      Group(
        name: 'GLOBAL',
        type: GroupType.Selector,
        hidden: true,
        now: 'Global old',
        all: [
          _globalNode,
          Proxy(name: 'Outer', type: 'Selector'),
        ],
      ),
      Group(
        name: 'Outer',
        type: GroupType.Selector,
        hidden: true,
        now: 'Outer old',
        all: [
          _outerNode,
          Proxy(name: 'Inner', type: 'Selector'),
        ],
      ),
      Group(
        name: 'Inner',
        type: GroupType.Selector,
        hidden: true,
        now: 'Inner old',
        all: [_innerNode, _sharedNode],
      ),
      Group(
        name: 'Route',
        type: GroupType.Selector,
        hidden: false,
        now: 'Shared node',
        all: [_sharedNode],
      ),
    ];
    const initialProfile = Profile(
      id: 1,
      label: 'Test profile',
      autoUpdateDuration: Duration(days: 1),
      currentGroupName: 'Route',
      selectedMap: {
        'GLOBAL': 'Global old',
        'Outer': 'Outer old',
        'Inner': 'Inner old',
        'Route': 'Shared node',
      },
    );
    final harness = _Harness(
      initialMode: Mode.rule,
      initialProfile: initialProfile,
      groups: groups,
    );

    expect(
      await harness.setup.changeModeAndWait(Mode.global),
      ModeSwitchResult.switched,
    );

    expect(harness.changes, [
      const ChangeProxyParams(groupName: 'Inner', proxyName: 'Shared node'),
      const ChangeProxyParams(groupName: 'Outer', proxyName: 'Inner'),
      const ChangeProxyParams(groupName: 'GLOBAL', proxyName: 'Outer'),
    ]);
    expect(harness.profile.selectedMap, {
      ...initialProfile.selectedMap,
      'GLOBAL': 'Outer',
      'Outer': 'Inner',
      'Inner': 'Shared node',
    });
    expect(harness.mode, Mode.global);
  });

  test(
    'missing source leaf in target preserves target selection and switches mode',
    () async {
      const groups = [
        Group(
          name: 'GLOBAL',
          type: GroupType.Selector,
          hidden: true,
          now: 'Global old',
          all: [_globalNode],
        ),
        Group(
          name: 'Route',
          type: GroupType.Selector,
          hidden: false,
          now: 'Shared node',
          all: [_sharedNode],
        ),
      ];
      final initialProfile = _profile(
        globalSelection: _globalNode.name,
        routeSelection: _sharedNode.name,
      );
      final harness = _Harness(
        initialMode: Mode.rule,
        initialProfile: initialProfile,
        groups: groups,
      );

      expect(
        await harness.setup.changeModeAndWait(Mode.global),
        ModeSwitchResult.switched,
      );

      expect(harness.mode, Mode.global);
      expect(harness.profile.selectedMap, initialProfile.selectedMap);
      expect(harness.coreSelections, initialProfile.selectedMap);
      expect(harness.changes, isEmpty);
      expect(harness.modeUpdates.map((params) => params.mode), [Mode.global]);
      verify(() => harness.core.closeConnections()).called(1);
    },
  );

  test(
    'missing global leaf in rule target preserves rule selection and switches',
    () async {
      const groups = [
        Group(
          name: 'GLOBAL',
          type: GroupType.Selector,
          hidden: true,
          now: 'Global old',
          all: [_globalNode],
        ),
        Group(
          name: 'Route',
          type: GroupType.Selector,
          hidden: false,
          now: 'Route old',
          all: [_routeNode],
        ),
      ];
      final initialProfile = _profile(
        globalSelection: _globalNode.name,
        routeSelection: _routeNode.name,
      );
      final harness = _Harness(
        initialMode: Mode.global,
        initialProfile: initialProfile,
        groups: groups,
      );

      expect(
        await harness.setup.changeModeAndWait(Mode.rule),
        ModeSwitchResult.switched,
      );

      expect(harness.mode, Mode.rule);
      expect(harness.profile.currentGroupName, 'Route');
      expect(harness.profile.selectedMap, initialProfile.selectedMap);
      expect(harness.coreSelections, initialProfile.selectedMap);
      expect(harness.changes, isEmpty);
      expect(harness.modeUpdates.map((params) => params.mode), [Mode.rule]);
    },
  );

  test('direct to rule keeps the legacy mode-only transition', () async {
    final initialProfile = _profile(
      globalSelection: _globalNode.name,
      routeSelection: _sharedNode.name,
    );
    final harness = _Harness(
      initialMode: Mode.direct,
      initialProfile: initialProfile,
    );

    expect(
      await harness.setup.changeModeAndWait(Mode.rule),
      ModeSwitchResult.switched,
    );

    expect(harness.mode, Mode.rule);
    expect(harness.profile.selectedMap, initialProfile.selectedMap);
    expect(harness.coreSelections, initialProfile.selectedMap);
    expect(harness.changes, isEmpty);
    expect(harness.modeUpdates, isEmpty);
  });

  test(
    'direct to global restores the saved global node without Hong Kong selection',
    () async {
      final initialProfile = _profile(
        globalSelection: _globalNode.name,
        routeSelection: _sharedNode.name,
      );
      final harness = _Harness(
        initialMode: Mode.direct,
        initialProfile: initialProfile,
      );
      final proxies =
          harness.container.read(proxiesActionProvider.notifier)
              as _TestProxies;
      proxies.legacyGlobalResult = HongKongSelectionResult.unavailable;

      expect(
        await harness.setup.changeModeAndWait(Mode.global),
        ModeSwitchResult.switched,
      );

      expect(harness.mode, Mode.global);
      expect(harness.profile, initialProfile);
      expect(harness.profile.selectedMap['GLOBAL'], _globalNode.name);
      expect(harness.changes, isEmpty);
      expect(proxies.legacyGlobalRequests, isEmpty);
    },
  );

  test(
    'direct to global rebuilds an active chain around the saved node',
    () async {
      final initialProfile = _profile(
        globalSelection: _globalNode.name,
        routeSelection: _sharedNode.name,
      );
      final harness = _Harness(
        initialMode: Mode.direct,
        initialProfile: initialProfile,
      );
      harness.container
          .read(appSettingProvider.notifier)
          .update(
            (settings) => settings.copyWith(
              activeChainProxyName: 'Chain',
              chainProxies: const [
                ChainProxyConfig(
                  name: 'Chain',
                  server: 'chain.example.test',
                  port: 1080,
                ),
              ],
            ),
          );

      expect(
        await harness.setup.changeModeAndWait(Mode.global),
        ModeSwitchResult.switched,
      );

      expect(harness.mode, Mode.global);
      expect(harness.profile.currentGroupName, GroupName.GLOBAL.name);
      expect(harness.profile.selectedMap['GLOBAL'], _globalNode.name);
      expect(harness.setup.runtimeMode, Mode.global);
      expect(harness.setup.chainRebuilds, [Mode.global]);
    },
  );

  test('unconfirmed connection refresh does not roll back mode', () async {
    final initialProfile = _profile(
      globalSelection: _globalNode.name,
      routeSelection: _sharedNode.name,
    );
    final harness = _Harness(
      initialMode: Mode.rule,
      initialProfile: initialProfile,
    );
    when(() => harness.core.closeConnections()).thenAnswer((_) async => false);

    expect(
      await harness.setup.changeModeAndWait(Mode.global),
      ModeSwitchResult.switched,
    );

    expect(harness.mode, Mode.global);
    expect(harness.profile.selectedMap['GLOBAL'], _sharedNode.name);
    expect(harness.coreSelections['GLOBAL'], _sharedNode.name);
  });

  test('DIRECT selected inside rule mode is not inherited to global', () async {
    final initialProfile = _profile(
      globalSelection: _globalNode.name,
      routeSelection: _directNode.name,
    );
    final harness = _Harness(
      initialMode: Mode.rule,
      initialProfile: initialProfile,
    );

    expect(
      await harness.setup.changeModeAndWait(Mode.global),
      ModeSwitchResult.switched,
    );

    expect(harness.mode, Mode.global);
    expect(harness.profile.selectedMap, initialProfile.selectedMap);
    expect(harness.coreSelections, initialProfile.selectedMap);
    expect(harness.changes, isEmpty);
  });

  test('active chain proxy inherits the node through a full rebuild', () async {
    final initialProfile = _profile(
      globalSelection: _globalNode.name,
      routeSelection: _sharedNode.name,
    );
    final harness = _Harness(
      initialMode: Mode.rule,
      initialProfile: initialProfile,
    );
    harness.container
        .read(appSettingProvider.notifier)
        .update(
          (settings) => settings.copyWith(
            activeChainProxyName: 'Chain',
            chainProxies: const [
              ChainProxyConfig(
                name: 'Chain',
                server: 'chain.example.test',
                port: 1080,
              ),
            ],
          ),
        );

    expect(
      await harness.setup.changeModeAndWait(Mode.global),
      ModeSwitchResult.switched,
    );

    expect(harness.mode, Mode.global);
    expect(harness.profile.currentGroupName, 'GLOBAL');
    expect(harness.profile.selectedMap, {
      ...initialProfile.selectedMap,
      'GLOBAL': _sharedNode.name,
    });
    expect(harness.coreSelections['GLOBAL'], _sharedNode.name);
    expect(harness.coreSelections['Route'], _sharedNode.name);
    expect(harness.changes, isEmpty);
    expect(harness.setup.chainRebuilds, [Mode.global]);
  });

  test(
    'active chain inherits the global node when returning to rule',
    () async {
      final initialProfile = _profile(
        globalSelection: _sharedNode.name,
        routeSelection: _routeNode.name,
      );
      final harness = _Harness(
        initialMode: Mode.global,
        initialProfile: initialProfile,
      );
      harness.container
          .read(appSettingProvider.notifier)
          .update(
            (settings) => settings.copyWith(
              activeChainProxyName: 'Chain',
              chainProxies: const [
                ChainProxyConfig(
                  name: 'Chain',
                  server: 'chain.example.test',
                  port: 1080,
                ),
              ],
            ),
          );

      expect(
        await harness.setup.changeModeAndWait(Mode.rule),
        ModeSwitchResult.switched,
      );

      expect(harness.mode, Mode.rule);
      expect(harness.profile.currentGroupName, 'Route');
      expect(harness.profile.selectedMap, {
        ...initialProfile.selectedMap,
        'Route': _sharedNode.name,
      });
      expect(harness.coreSelections['GLOBAL'], _sharedNode.name);
      expect(harness.coreSelections['Route'], _sharedNode.name);
      expect(harness.changes, isEmpty);
      expect(harness.setup.chainRebuilds, [Mode.rule]);
    },
  );

  test('active chain direct MATCH leaf keeps a rule display group', () async {
    final initialProfile = _profile(
      globalSelection: _sharedNode.name,
      routeSelection: _routeNode.name,
    ).copyWith(currentGroupName: 'GLOBAL');
    final harness = _Harness(
      initialMode: Mode.global,
      initialProfile: initialProfile,
      ruleGroupName: _sharedNode.name,
    );
    harness.container
        .read(appSettingProvider.notifier)
        .update(
          (settings) => settings.copyWith(
            activeChainProxyName: 'Chain',
            chainProxies: const [
              ChainProxyConfig(
                name: 'Chain',
                server: 'chain.example.test',
                port: 1080,
              ),
            ],
          ),
        );

    expect(
      await harness.setup.changeModeAndWait(Mode.rule),
      ModeSwitchResult.switched,
    );

    expect(harness.mode, Mode.rule);
    expect(harness.profile.currentGroupName, 'Route');
    expect(harness.profile.selectedMap, initialProfile.selectedMap);
    expect(harness.setup.chainRebuilds, [Mode.rule]);
  });

  test('active chain preparation waits for the setup transaction', () async {
    const routeOldNode = Proxy(name: 'Route old node', type: 'Trojan');
    const routeNewNode = Proxy(name: 'Route new node', type: 'Trojan');
    const oldGroups = [
      Group(
        name: 'GLOBAL',
        type: GroupType.Selector,
        hidden: true,
        now: 'Shared node',
        all: [_sharedNode],
      ),
      Group(
        name: 'RouteOld',
        type: GroupType.Selector,
        hidden: false,
        now: 'Route old node',
        all: [routeOldNode, _sharedNode],
      ),
    ];
    const newGroups = [
      Group(
        name: 'GLOBAL',
        type: GroupType.Selector,
        hidden: true,
        now: 'Shared node',
        all: [_sharedNode],
      ),
      Group(
        name: 'RouteNew',
        type: GroupType.Selector,
        hidden: false,
        now: 'Route new node',
        all: [routeNewNode, _sharedNode],
      ),
    ];
    const initialProfile = Profile(
      id: 1,
      label: 'Test profile',
      autoUpdateDuration: Duration(days: 1),
      currentGroupName: 'GLOBAL',
      selectedMap: {
        'GLOBAL': 'Shared node',
        'RouteOld': 'Route old node',
        'RouteNew': 'Route new node',
      },
    );
    final harness = _Harness(
      initialMode: Mode.global,
      initialProfile: initialProfile,
      groups: oldGroups,
      ruleGroupName: 'RouteOld',
    );
    harness.container
        .read(appSettingProvider.notifier)
        .update(
          (settings) => settings.copyWith(
            activeChainProxyName: 'Chain',
            chainProxies: const [
              ChainProxyConfig(
                name: 'Chain',
                server: 'chain.example.test',
                port: 1080,
              ),
            ],
          ),
        );
    final setupEntered = Completer<void>();
    final releaseSetup = Completer<void>();
    final activeSetup = harness.setup.runModeSwitchTransaction<void>(() async {
      setupEntered.complete();
      await releaseSetup.future;
    });
    await setupEntered.future;

    final switching = harness.setup.changeModeAndWait(Mode.rule);
    await Future<void>.delayed(Duration.zero);
    expect(harness.mode, Mode.global, reason: '${harness.events}');
    expect(harness.profile, initialProfile);

    harness.setup.ruleTarget = 'RouteNew';
    harness.runtimeGroups = newGroups;
    releaseSetup.complete();
    await activeSetup;

    expect(
      await switching.timeout(const Duration(seconds: 2)),
      ModeSwitchResult.switched,
    );
    expect(harness.mode, Mode.rule);
    expect(harness.profile.currentGroupName, 'RouteNew');
    expect(harness.profile.selectedMap['RouteOld'], routeOldNode.name);
    expect(harness.profile.selectedMap['RouteNew'], _sharedNode.name);
    expect(harness.coreSelections['RouteOld'], routeOldNode.name);
    expect(harness.coreSelections['RouteNew'], _sharedNode.name);
  });

  test(
    'active chain rebuild stays inside its preparation transaction',
    () async {
      final initialProfile = _profile(
        globalSelection: _sharedNode.name,
        routeSelection: _routeNode.name,
      );
      final harness = _Harness(
        initialMode: Mode.global,
        initialProfile: initialProfile,
      );
      harness.container
          .read(appSettingProvider.notifier)
          .update(
            (settings) => settings.copyWith(
              activeChainProxyName: 'Chain',
              chainProxies: const [
                ChainProxyConfig(
                  name: 'Chain',
                  server: 'chain.example.test',
                  port: 1080,
                ),
              ],
            ),
          );
      final groupsLoadEntered = Completer<void>();
      final releaseGroupsLoad = Completer<void>();
      harness.onGroupsLoad = () async {
        harness.events.add('groups:A');
        groupsLoadEntered.complete();
        await releaseGroupsLoad.future;
      };

      final switching = harness.setup.changeModeAndWait(Mode.rule);
      await groupsLoadEntered.future;
      final queuedSetup = harness.setup.runModeSwitchTransaction<void>(
        () async {
          harness.events.add('setup:B');
        },
      );
      await Future<void>.delayed(Duration.zero);
      releaseGroupsLoad.complete();

      expect(await switching, ModeSwitchResult.switched);
      await queuedSetup;
      expect(
        harness.events.indexOf('chain:rule'),
        lessThan(harness.events.indexOf('setup:B')),
        reason: '${harness.events}',
      );
    },
  );

  test(
    'same target coalesces while a failed chain restart rolls back safely',
    () async {
      final initialProfile = _profile(
        globalSelection: _globalNode.name,
        routeSelection: _sharedNode.name,
      );
      final harness = _Harness(
        initialMode: Mode.rule,
        initialProfile: initialProfile,
      );
      harness.container
          .read(appSettingProvider.notifier)
          .update(
            (settings) => settings.copyWith(
              activeChainProxyName: 'Chain',
              chainProxies: const [
                ChainProxyConfig(
                  name: 'Chain',
                  server: 'chain.example.test',
                  port: 1080,
                ),
              ],
            ),
          );
      harness.setup.chainRebuildRequiresRestart = true;
      final firstRestartEntered = Completer<void>();
      final releaseFirstRestart = Completer<void>();
      var restartAttempt = 0;
      harness.setup.onChainRestart = (mode) async {
        restartAttempt++;
        if (restartAttempt != 1) return true;
        firstRestartEntered.complete();
        await releaseFirstRestart.future;
        throw StateError('restart failed');
      };

      final first = harness.setup.changeModeAndWait(Mode.global);
      await firstRestartEntered.future;
      final latest = harness.setup.changeModeAndWait(Mode.global);
      releaseFirstRestart.complete();

      expect(await first, ModeSwitchResult.failed);
      expect(await latest, ModeSwitchResult.failed);
      harness.expectInitialState(initialProfile, Mode.rule);
      expect(harness.setup.runtimeMode, Mode.rule);
      expect(harness.setup.chainRebuilds, [Mode.global, Mode.rule]);
      expect(harness.setup.chainRestarts, [Mode.global, Mode.rule]);

      expect(
        await harness.setup.changeModeAndWait(Mode.global),
        ModeSwitchResult.switched,
      );
      expect(harness.mode, Mode.global);
      expect(harness.setup.runtimeMode, Mode.global);
      expect(harness.profile.selectedMap['GLOBAL'], _sharedNode.name);
      expect(harness.setup.chainRebuilds, [
        Mode.global,
        Mode.rule,
        Mode.global,
      ]);
      expect(harness.setup.chainRestarts, [
        Mode.global,
        Mode.rule,
        Mode.global,
      ]);
    },
  );

  test(
    'chain rollback recovers a listener stopped by target restart',
    () async {
      final initialProfile = _profile(
        globalSelection: _globalNode.name,
        routeSelection: _sharedNode.name,
      );
      final harness = _Harness(
        initialMode: Mode.rule,
        initialProfile: initialProfile,
      );
      harness.container
          .read(appSettingProvider.notifier)
          .update(
            (settings) => settings.copyWith(
              activeChainProxyName: 'Chain',
              chainProxies: const [
                ChainProxyConfig(
                  name: 'Chain',
                  server: 'chain.example.test',
                  port: 1080,
                ),
              ],
            ),
          );
      harness.setup.chainRebuildRestartResults.addAll([true, false]);
      harness.setup.onChainRestart = (mode) async => false;
      harness.setup.recoveryRestoresRuntime = false;

      expect(
        await harness.setup.changeModeAndWait(Mode.global),
        ModeSwitchResult.failed,
      );

      harness.expectInitialState(initialProfile, Mode.rule);
      expect(harness.setup.runtimeMode, Mode.rule);
      expect(harness.setup.runtimeRunning, isTrue);
      expect(harness.setup.recoveryAttempts, 1);
      expect(harness.setup.recoveryStarts, 1);
      expect(harness.setup.chainRebuilds, [Mode.global, Mode.rule]);
      expect(harness.setup.chainRestarts, [Mode.global]);
    },
  );

  test('active chain rebuild failure restores the previous mode', () async {
    final initialProfile = _profile(
      globalSelection: _globalNode.name,
      routeSelection: _sharedNode.name,
    );
    final harness = _Harness(
      initialMode: Mode.rule,
      initialProfile: initialProfile,
    );
    harness.container
        .read(appSettingProvider.notifier)
        .update(
          (settings) => settings.copyWith(
            activeChainProxyName: 'Chain',
            chainProxies: const [
              ChainProxyConfig(
                name: 'Chain',
                server: 'chain.example.test',
                port: 1080,
              ),
            ],
          ),
        );
    var failed = false;
    harness.setup.onChainRebuild = (mode) async {
      if (mode == Mode.global && !failed) {
        failed = true;
        throw StateError('rebuild failed');
      }
    };

    expect(
      await harness.setup.changeModeAndWait(Mode.global),
      ModeSwitchResult.failed,
    );

    harness.expectInitialState(initialProfile, Mode.rule);
    expect(harness.setup.chainRebuilds, [Mode.global, Mode.rule]);
  });

  test('active chain recovery rebuilds after rollback also fails', () async {
    final initialProfile = _profile(
      globalSelection: _globalNode.name,
      routeSelection: _sharedNode.name,
    );
    final harness = _Harness(
      initialMode: Mode.rule,
      initialProfile: initialProfile,
    );
    harness.container
        .read(appSettingProvider.notifier)
        .update(
          (settings) => settings.copyWith(
            activeChainProxyName: 'Chain',
            chainProxies: const [
              ChainProxyConfig(
                name: 'Chain',
                server: 'chain.example.test',
                port: 1080,
              ),
            ],
          ),
        );
    harness.setup.onChainRebuild = (_) async {
      throw StateError('rebuild failed');
    };

    expect(
      await harness.setup.changeModeAndWait(Mode.global),
      ModeSwitchResult.failed,
    );

    harness.expectInitialState(initialProfile, Mode.rule);
    expect(harness.setup.chainRebuilds, [Mode.global, Mode.rule]);
    expect(harness.setup.recoveryAttempts, 1);
  });

  test(
    'offline active chain rejects global mode without a valid target',
    () async {
      final initialProfile = _profile(
        globalSelection: 'Removed node',
        routeSelection: _directNode.name,
      );
      final harness = _Harness(
        initialMode: Mode.rule,
        initialProfile: initialProfile,
        online: false,
        groups: [_flatGroups.first.copyWith(now: null), _flatGroups.last],
      );
      harness.container
          .read(appSettingProvider.notifier)
          .update(
            (settings) => settings.copyWith(
              activeChainProxyName: 'Chain',
              chainProxies: const [
                ChainProxyConfig(
                  name: 'Chain',
                  server: 'chain.example.test',
                  port: 1080,
                ),
              ],
            ),
          );

      expect(
        await harness.setup.changeModeAndWait(Mode.global),
        ModeSwitchResult.failed,
      );

      harness.expectInitialState(initialProfile, Mode.rule);
      expect(harness.setup.chainRebuilds, isEmpty);
    },
  );

  test(
    'offline active chain persists a valid runtime global fallback',
    () async {
      const initialProfile = Profile(
        id: 1,
        label: 'Test profile',
        autoUpdateDuration: Duration(days: 1),
        currentGroupName: 'Route',
        selectedMap: {'Route': 'DIRECT'},
      );
      final harness = _Harness(
        initialMode: Mode.rule,
        initialProfile: initialProfile,
        online: false,
      );
      harness.container
          .read(appSettingProvider.notifier)
          .update(
            (settings) => settings.copyWith(
              activeChainProxyName: 'Chain',
              chainProxies: const [
                ChainProxyConfig(
                  name: 'Chain',
                  server: 'chain.example.test',
                  port: 1080,
                ),
              ],
            ),
          );

      expect(
        await harness.setup.changeModeAndWait(Mode.global),
        ModeSwitchResult.switched,
      );

      expect(harness.mode, Mode.global);
      expect(harness.profile.currentGroupName, 'GLOBAL');
      expect(harness.profile.selectedMap['GLOBAL'], _globalNode.name);
      expect(harness.setup.chainRebuilds, isEmpty);
    },
  );

  test(
    'manual selection during chain rebuild wins and cancels mode switch',
    () async {
      final initialProfile = _profile(
        globalSelection: _globalNode.name,
        routeSelection: _sharedNode.name,
      );
      final harness = _Harness(
        initialMode: Mode.rule,
        initialProfile: initialProfile,
      );
      harness.container
          .read(appSettingProvider.notifier)
          .update(
            (settings) => settings.copyWith(
              activeChainProxyName: 'Chain',
              chainProxies: const [
                ChainProxyConfig(
                  name: 'Chain',
                  server: 'chain.example.test',
                  port: 1080,
                ),
              ],
            ),
          );
      final rebuildStarted = Completer<void>();
      final releaseRebuild = Completer<void>();
      var rebuildCount = 0;
      harness.setup.onChainRebuild = (mode) async {
        rebuildCount++;
        if (rebuildCount != 1) return;
        rebuildStarted.complete();
        await releaseRebuild.future;
      };

      final switchResult = harness.setup.changeModeAndWait(Mode.global);
      await rebuildStarted.future;
      final manualProfile = harness.profile.copyWith(
        currentGroupName: 'Route',
        selectedMap: {...harness.profile.selectedMap, 'Route': _routeNode.name},
      );
      harness.container.read(profilesProvider.notifier).put(manualProfile);
      final manualSelection = harness.container
          .read(proxiesActionProvider.notifier)
          .changeProxy(groupName: 'Route', proxyName: _routeNode.name);
      releaseRebuild.complete();

      expect(await switchResult, ModeSwitchResult.cancelled);
      await manualSelection;
      expect(harness.mode, Mode.rule);
      expect(harness.profile.currentGroupName, 'Route');
      expect(harness.profile.selectedMap, {
        'GLOBAL': _globalNode.name,
        'Route': _routeNode.name,
      });
      expect(harness.coreSelections['Route'], _routeNode.name);
      expect(harness.setup.chainRebuilds, [Mode.global, Mode.rule]);
    },
  );

  test('selection RPC failure restores the target selector', () async {
    final initialProfile = _profile(
      globalSelection: _globalNode.name,
      routeSelection: _sharedNode.name,
    );
    final harness = _Harness(
      initialMode: Mode.rule,
      initialProfile: initialProfile,
    );
    harness.onSelection = (params) async {
      if (params.groupName == 'GLOBAL' &&
          params.proxyName == _sharedNode.name) {
        return 'selection rejected';
      }
      return '';
    };

    expect(
      await harness.setup.changeModeAndWait(Mode.global),
      ModeSwitchResult.failed,
    );

    harness.expectInitialState(initialProfile, Mode.rule);
    expect(harness.modeUpdates, isEmpty);
    expect(harness.changes, [
      const ChangeProxyParams(groupName: 'GLOBAL', proxyName: 'Shared node'),
      const ChangeProxyParams(groupName: 'GLOBAL', proxyName: 'Global old'),
    ]);
  });

  test('mode RPC failure restores mode and target selector', () async {
    final initialProfile = _profile(
      globalSelection: _globalNode.name,
      routeSelection: _sharedNode.name,
    );
    final harness = _Harness(
      initialMode: Mode.rule,
      initialProfile: initialProfile,
    );
    var rejected = false;
    harness.setup.onModeUpdate = (params) async {
      if (!rejected && params.mode == Mode.global) {
        rejected = true;
        return 'mode rejected';
      }
      return '';
    };

    expect(
      await harness.setup.changeModeAndWait(Mode.global),
      ModeSwitchResult.failed,
    );

    harness.expectInitialState(initialProfile, Mode.rule);
    expect(harness.modeUpdates.map((params) => params.mode), [
      Mode.global,
      Mode.rule,
    ]);
    expect(harness.changes, [
      const ChangeProxyParams(groupName: 'GLOBAL', proxyName: 'Shared node'),
      const ChangeProxyParams(groupName: 'GLOBAL', proxyName: 'Global old'),
    ]);
  });

  test('selector rollback failure triggers a full runtime recovery', () async {
    final initialProfile = _profile(
      globalSelection: _globalNode.name,
      routeSelection: _sharedNode.name,
    );
    final harness = _Harness(
      initialMode: Mode.rule,
      initialProfile: initialProfile,
    );
    harness.onSelection = (params) async =>
        params.proxyName == _globalNode.name ? 'restore rejected' : '';
    harness.setup.onModeUpdate = (params) async =>
        params.mode == Mode.global ? 'mode rejected' : '';

    expect(
      await harness.setup.changeModeAndWait(Mode.global),
      ModeSwitchResult.failed,
    );

    harness.expectInitialState(initialProfile, Mode.rule);
    expect(harness.setup.recoveryAttempts, 1);
  });

  test('mode rollback failure triggers a full runtime recovery', () async {
    final initialProfile = _profile(
      globalSelection: _globalNode.name,
      routeSelection: _sharedNode.name,
    );
    final harness = _Harness(
      initialMode: Mode.rule,
      initialProfile: initialProfile,
    );
    harness.setup.onModeUpdate = (params) async => switch (params.mode) {
      Mode.global => 'mode rejected',
      Mode.rule => 'restore rejected',
      Mode.direct => '',
    };

    expect(
      await harness.setup.changeModeAndWait(Mode.global),
      ModeSwitchResult.failed,
    );

    harness.expectInitialState(initialProfile, Mode.rule);
    expect(harness.setup.recoveryAttempts, 1);
  });

  test(
    'rollback uses runtime selection when persisted target is stale',
    () async {
      final initialProfile = _profile(
        globalSelection: 'Removed node',
        routeSelection: _sharedNode.name,
      );
      final harness = _Harness(
        initialMode: Mode.rule,
        initialProfile: initialProfile,
      );
      harness.coreSelections['GLOBAL'] = _globalNode.name;
      harness.setup.onModeUpdate = (params) async =>
          params.mode == Mode.global ? 'mode rejected' : '';

      expect(
        await harness.setup.changeModeAndWait(Mode.global),
        ModeSwitchResult.failed,
      );

      expect(harness.mode, Mode.rule);
      expect(harness.profile, initialProfile);
      expect(harness.coreSelections['GLOBAL'], _globalNode.name);
      expect(harness.changes, [
        const ChangeProxyParams(groupName: 'GLOBAL', proxyName: 'Shared node'),
        const ChangeProxyParams(groupName: 'GLOBAL', proxyName: 'Global old'),
      ]);
    },
  );

  test(
    'rollback loads the current core selection instead of stale groups',
    () async {
      final initialProfile = _profile(
        globalSelection: _sharedNode.name,
        routeSelection: _routeNode.name,
      );
      final harness = _Harness(
        initialMode: Mode.global,
        initialProfile: initialProfile,
        groups: [
          _flatGroups.first,
          _flatGroups.last.copyWith(now: _directNode.name),
        ],
      );
      harness.setup.onModeUpdate = (params) async =>
          params.mode == Mode.rule ? 'mode rejected' : '';

      expect(
        await harness.setup.changeModeAndWait(Mode.rule),
        ModeSwitchResult.failed,
      );

      harness.expectInitialState(initialProfile, Mode.global);
      expect(harness.changes, [
        const ChangeProxyParams(groupName: 'Route', proxyName: 'Shared node'),
        const ChangeProxyParams(groupName: 'Route', proxyName: 'Route old'),
      ]);
    },
  );

  test('rapid same-target requests share one mode switch', () async {
    final initialProfile = _profile(
      globalSelection: _globalNode.name,
      routeSelection: _sharedNode.name,
    );
    final harness = _Harness(
      initialMode: Mode.rule,
      initialProfile: initialProfile,
    );
    final enteredSelection = Completer<void>();
    final releaseSelection = Completer<void>();
    harness.onSelection = (params) async {
      if (params.groupName == 'GLOBAL' &&
          params.proxyName == _sharedNode.name) {
        enteredSelection.complete();
        await releaseSelection.future;
      }
      return '';
    };

    final first = harness.setup.changeModeAndWait(Mode.global);
    await enteredSelection.future;
    final latest = harness.setup.changeModeAndWait(Mode.global);
    releaseSelection.complete();

    expect(await first, ModeSwitchResult.switched);
    expect(await latest, ModeSwitchResult.switched);
    expect(harness.mode, Mode.global);
    expect(harness.profile.selectedMap['GLOBAL'], _sharedNode.name);
    expect(harness.changes, [
      const ChangeProxyParams(groupName: 'GLOBAL', proxyName: 'Shared node'),
    ]);
    expect(harness.modeUpdates.map((params) => params.mode), [Mode.global]);
  });

  test('rapid reverse switch keeps the latest mode intent', () async {
    final initialProfile = _profile(
      globalSelection: _globalNode.name,
      routeSelection: _sharedNode.name,
    );
    final harness = _Harness(
      initialMode: Mode.rule,
      initialProfile: initialProfile,
    );
    final enteredSelection = Completer<void>();
    final releaseSelection = Completer<void>();
    harness.onSelection = (params) async {
      if (params.groupName == 'GLOBAL' &&
          params.proxyName == _sharedNode.name) {
        if (!enteredSelection.isCompleted) enteredSelection.complete();
        await releaseSelection.future;
      }
      return '';
    };

    final first = harness.setup.changeModeAndWait(Mode.global);
    await enteredSelection.future;
    final latest = await harness.setup.changeModeAndWait(Mode.rule);
    releaseSelection.complete();

    expect(latest, ModeSwitchResult.unchanged);
    expect(await first, ModeSwitchResult.cancelled);
    harness.expectInitialState(initialProfile, Mode.rule);
    expect(harness.modeUpdates, isEmpty);
    expect(
      harness.changes.last,
      const ChangeProxyParams(groupName: 'GLOBAL', proxyName: 'Global old'),
    );
  });

  test(
    'manual selection of the inherited value wins during mode RPC',
    () async {
      final initialProfile = _profile(
        globalSelection: _sharedNode.name,
        routeSelection: _routeNode.name,
      ).copyWith(currentGroupName: 'GLOBAL');
      final harness = _Harness(
        initialMode: Mode.global,
        initialProfile: initialProfile,
      );
      final modeUpdateStarted = Completer<void>();
      final releaseModeUpdate = Completer<void>();
      harness.setup.onModeUpdate = (params) async {
        if (params.mode == Mode.rule) {
          modeUpdateStarted.complete();
          await releaseModeUpdate.future;
        }
        return '';
      };

      final switchResult = harness.setup.changeModeAndWait(Mode.rule);
      await modeUpdateStarted.future;
      final manualSelection = harness.container
          .read(proxiesActionProvider.notifier)
          .changeProxy(groupName: 'Route', proxyName: _sharedNode.name);
      releaseModeUpdate.complete();

      expect(await switchResult, ModeSwitchResult.cancelled);
      await manualSelection;
      expect(harness.mode, Mode.global);
      expect(harness.profile.currentGroupName, 'GLOBAL');
      expect(harness.profile.selectedMap, {
        'GLOBAL': _sharedNode.name,
        'Route': _sharedNode.name,
      });
      expect(harness.coreSelections['Route'], _sharedNode.name);
    },
  );

  test('unchanged mode does not cancel a pending node selection', () async {
    final initialProfile = _profile(
      globalSelection: _globalNode.name,
      routeSelection: _routeNode.name,
    );
    final harness = _Harness(
      initialMode: Mode.rule,
      initialProfile: initialProfile,
    );
    final proxies = harness.container.read(proxiesActionProvider.notifier);

    proxies.changeProxyDebounce('Route', _sharedNode.name);
    final manualRevision = proxies.manualSelectionRevision;

    expect(
      await harness.setup.changeModeAndWait(Mode.rule),
      ModeSwitchResult.unchanged,
    );
    expect(proxies.manualSelectionRevision, manualRevision);

    await Future<void>.delayed(const Duration(milliseconds: 700));
    await harness.container.pump();
    expect(harness.coreSelections['Route'], _sharedNode.name);
  });

  test(
    'rapid reverse mode switch does not swallow a pending node selection',
    () async {
      final initialProfile = _profile(
        globalSelection: _globalNode.name,
        routeSelection: _routeNode.name,
      );
      final harness = _Harness(
        initialMode: Mode.rule,
        initialProfile: initialProfile,
      );
      final proxies = harness.container.read(proxiesActionProvider.notifier);
      harness.container
          .read(profilesProvider.notifier)
          .put(
            initialProfile.copyWith(
              selectedMap: {
                ...initialProfile.selectedMap,
                'Route': _sharedNode.name,
              },
            ),
          );
      proxies.changeProxyDebounce('Route', _sharedNode.name);
      final enteredSelection = Completer<void>();
      final releaseSelection = Completer<void>();
      harness.onSelection = (params) async {
        if (params.groupName == 'GLOBAL' &&
            params.proxyName == _sharedNode.name) {
          enteredSelection.complete();
          await releaseSelection.future;
        }
        return '';
      };

      final first = harness.setup.changeModeAndWait(Mode.global);
      await enteredSelection.future;
      final latest = await harness.setup.changeModeAndWait(Mode.rule);
      releaseSelection.complete();

      expect(latest, ModeSwitchResult.unchanged);
      expect(await first, ModeSwitchResult.cancelled);
      await Future<void>.delayed(const Duration(milliseconds: 700));
      await harness.container.pump();
      expect(harness.mode, Mode.rule);
      expect(harness.profile.selectedMap, {
        'GLOBAL': _globalNode.name,
        'Route': _sharedNode.name,
      });
      expect(harness.coreSelections, {
        'GLOBAL': _globalNode.name,
        'Route': _sharedNode.name,
      });
    },
  );

  test('offline switch only persists the inherited selection', () async {
    final initialProfile = _profile(
      globalSelection: _globalNode.name,
      routeSelection: _sharedNode.name,
    );
    final harness = _Harness(
      initialMode: Mode.rule,
      initialProfile: initialProfile,
      online: false,
    );

    expect(
      await harness.setup.changeModeAndWait(Mode.global),
      ModeSwitchResult.switched,
    );

    expect(harness.mode, Mode.global);
    expect(harness.profile.selectedMap['GLOBAL'], _sharedNode.name);
    expect(harness.changes, isEmpty);
    expect(harness.modeUpdates, isEmpty);
    verifyNever(() => harness.core.closeConnections());
    verifyNever(() => harness.core.resetConnections());
  });
}

Profile _profile({
  required String globalSelection,
  required String routeSelection,
}) {
  return Profile(
    id: 1,
    label: 'Test profile',
    autoUpdateDuration: const Duration(days: 1),
    currentGroupName: 'Route',
    selectedMap: {'GLOBAL': globalSelection, 'Route': routeSelection},
  );
}

class _MockCore extends Mock implements CoreHandlerInterface {}

class _Harness {
  _Harness({
    required Mode initialMode,
    required Profile initialProfile,
    List<Group> groups = _flatGroups,
    bool online = true,
    String? ruleGroupName = 'Route',
  }) {
    runtimeGroups = groups;
    coreSelections.addAll(initialProfile.selectedMap);
    container = ProviderContainer(
      overrides: [
        currentProfileIdProvider.overrideWithBuild((_, _) => initialProfile.id),
        profilesProvider.overrideWith(() => _TestProfiles([initialProfile])),
        groupsProvider.overrideWithBuild((_, _) => runtimeGroups),
        coreStatusProvider.overrideWithBuild(
          (_, _) => online ? CoreStatus.connected : CoreStatus.disconnected,
        ),
        runTimeProvider.overrideWithBuild((_, _) => online ? 1000 : null),
        setupActionProvider.overrideWith(
          () => _TestSetup(events, initialMode, ruleGroupName),
        ),
        proxiesActionProvider.overrideWith(
          () => _TestProxies(CoreController.test(core), () async {
            await onGroupsLoad?.call();
            return runtimeGroups
                .map(
                  (group) => group.copyWith(
                    now: coreSelections[group.name] ?? group.now,
                  ),
                )
                .toList();
          }),
        ),
      ],
    );
    addTearDown(container.dispose);
    final modeSubscription = container.listen(
      patchClashConfigProvider,
      (previous, next) {},
    );
    final appSettingSubscription = container.listen(
      appSettingProvider,
      (previous, next) {},
    );
    addTearDown(modeSubscription.close);
    addTearDown(appSettingSubscription.close);
    container
        .read(patchClashConfigProvider.notifier)
        .update((config) => config.copyWith(mode: initialMode));
    setup = container.read(setupActionProvider.notifier) as _TestSetup;
    setup.onChainApplied = () {
      coreSelections
        ..clear()
        ..addAll(profile.selectedMap);
    };
    when(() => core.changeProxy(any())).thenAnswer((invocation) async {
      final params = invocation.positionalArguments.single as ChangeProxyParams;
      changes.add(params);
      events.add('select:${params.groupName}:${params.proxyName}');
      final response = await onSelection(params);
      if (response.isEmpty) {
        coreSelections[params.groupName] = params.proxyName;
      }
      return response;
    });
    when(() => core.closeConnections()).thenAnswer((_) async {
      events.add('close');
      return true;
    });
    when(() => core.resetConnections()).thenAnswer((_) async {
      events.add('reset');
      return true;
    });
  }

  final core = _MockCore();
  final events = <String>[];
  final changes = <ChangeProxyParams>[];
  final coreSelections = <String, String>{};
  late List<Group> runtimeGroups;
  late final ProviderContainer container;
  late final _TestSetup setup;
  Future<void> Function()? onGroupsLoad;
  Future<String> Function(ChangeProxyParams params) onSelection =
      (params) async => '';

  Mode get mode => container.read(patchClashConfigProvider).mode;

  Profile get profile => container.read(currentProfileProvider)!;

  List<UpdateParams> get modeUpdates => setup.updates;

  void expectInitialState(Profile initialProfile, Mode initialMode) {
    expect(mode, initialMode);
    expect(profile, initialProfile);
    expect(coreSelections, initialProfile.selectedMap);
  }
}

class _TestProxies extends ProxiesAction {
  _TestProxies(this.controller, this.groupsLoader);

  final CoreController controller;
  final Future<List<Group>> Function() groupsLoader;
  final List<Mode> legacyGlobalRequests = [];
  HongKongSelectionResult? legacyGlobalResult;

  @override
  CoreController get proxyController => controller;

  @override
  Future<List<Group>> loadModeSwitchGroups() => groupsLoader();

  @override
  Future<HongKongSelectionResult> selectHongKongForMode(
    Mode mode, {
    bool Function()? isCancelled,
  }) async {
    final result = legacyGlobalResult;
    if (result == null) {
      return super.selectHongKongForMode(mode, isCancelled: isCancelled);
    }
    legacyGlobalRequests.add(mode);
    return isCancelled?.call() == true
        ? HongKongSelectionResult.cancelled
        : result;
  }

  @override
  void updateGroupsDebounce([Duration? duration]) {}
}

class _TestSetup extends SetupAction {
  _TestSetup(this.events, this.runtimeMode, this.ruleTarget);

  final List<String> events;
  final List<UpdateParams> updates = [];
  final List<Mode> chainRebuilds = [];
  final List<Mode> chainRestarts = [];
  int recoveryAttempts = 0;
  int recoveryStarts = 0;
  String? ruleTarget;
  Mode runtimeMode;
  bool runtimeRunning = true;
  bool recoveryRestoresRuntime = true;
  bool chainRebuildRequiresRestart = false;
  final List<bool> chainRebuildRestartResults = [];
  Future<String> Function(UpdateParams params)? onModeUpdate;
  Future<void> Function(Mode mode)? onChainRebuild;
  Future<bool> Function(Mode mode)? onChainRestart;
  void Function()? onChainApplied;

  @override
  String? get ruleSelectionGroup => ruleTarget;

  @override
  Future<bool> rebuildActiveChainForModeChangeWithinTransaction() async {
    final mode = ref.read(patchClashConfigProvider).mode;
    chainRebuilds.add(mode);
    events.add('chain:${mode.name}');
    await onChainRebuild?.call(mode);
    final requiresRestart = chainRebuildRestartResults.isNotEmpty
        ? chainRebuildRestartResults.removeAt(0)
        : chainRebuildRequiresRestart;
    if (requiresRestart) return true;
    onChainApplied?.call();
    runtimeMode = mode;
    return false;
  }

  @override
  Future<void> restartActiveChainAfterAuthorization() async {
    final mode = ref.read(patchClashConfigProvider).mode;
    chainRestarts.add(mode);
    events.add('chain-restart:${mode.name}');
    bool applied;
    try {
      applied = await onChainRestart?.call(mode) ?? true;
    } catch (_) {
      runtimeRunning = false;
      rethrow;
    }
    if (!applied) {
      runtimeRunning = false;
      return;
    }
    onChainApplied?.call();
    runtimeMode = mode;
    runtimeRunning = true;
  }

  @override
  bool activeChainModeChangeReady({
    required Mode targetMode,
    required bool wasRunning,
  }) {
    return runtimeRunning && runtimeMode == targetMode;
  }

  @override
  Future<bool> recoverModeSwitchRuntime() async {
    recoveryAttempts++;
    final restoredMode = ref.read(patchClashConfigProvider).mode;
    events.add('recover:${restoredMode.name}');
    if (!recoveryRestoresRuntime) return false;
    onChainApplied?.call();
    runtimeMode = restoredMode;
    runtimeRunning = true;
    return true;
  }

  @override
  Future<void> setRunning(bool running, {bool initialize = false}) async {
    events.add('running:$running');
    runtimeRunning = running;
    if (!running) return;
    recoveryStarts++;
    onChainApplied?.call();
    runtimeMode = ref.read(patchClashConfigProvider).mode;
  }

  @override
  Future<String> applyCoreUpdate(UpdateParams params) async {
    updates.add(params);
    events.add('mode:${params.mode.name}');
    final response = await onModeUpdate?.call(params) ?? '';
    if (response.isEmpty) runtimeMode = params.mode;
    return response;
  }
}

class _TestProfiles extends Profiles {
  _TestProfiles(this.initial);

  final List<Profile> initial;

  @override
  List<Profile> build() => initial;

  @override
  void put(Profile profile) {
    final next = List<Profile>.from(state);
    final index = next.indexWhere((item) => item.id == profile.id);
    if (index == -1) {
      next.add(profile);
    } else {
      next[index] = profile;
    }
    state = next;
  }
}

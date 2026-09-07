import 'dart:async';

import 'package:fl_clash/common/constant.dart';
import 'package:fl_clash/core/controller.dart';
import 'package:fl_clash/core/interface.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:riverpod/riverpod.dart';

const _hongKongOne = Proxy(name: '香港 01', type: 'Shadowsocks');
const _hongKongTwo = Proxy(name: '香港 02', type: 'Trojan');
const _otherNode = Proxy(name: '日本 01', type: 'Shadowsocks');
const _profile = Profile(
  id: 1,
  label: 'Test profile',
  autoUpdateDuration: Duration(days: 1),
  currentGroupName: 'Route',
  selectedMap: {'GLOBAL': '日本 01', 'Route': '日本 01', 'Video': 'DIRECT'},
);
const _groups = [
  Group(
    name: 'GLOBAL',
    type: GroupType.Selector,
    hidden: true,
    now: '日本 01',
    all: [_hongKongOne, _hongKongTwo, _otherNode],
  ),
  Group(
    name: 'Route',
    type: GroupType.Selector,
    hidden: false,
    now: '日本 01',
    all: [_hongKongOne, _hongKongTwo, _otherNode],
  ),
];
const _nestedGroups = [
  Group(
    name: 'GLOBAL',
    type: GroupType.Selector,
    hidden: true,
    now: '日本 01',
    all: [
      Proxy(name: 'Route', type: 'Selector'),
      _otherNode,
    ],
  ),
  Group(
    name: 'Route',
    type: GroupType.Selector,
    hidden: false,
    now: '日本 01',
    all: [_hongKongOne, _otherNode],
  ),
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() {
    registerFallbackValue(
      const ChangeProxyParams(groupName: 'GLOBAL', proxyName: '日本 01'),
    );
  });

  test('fresh proxy probe precedes selection and mode persistence', () async {
    final harness = _Harness();
    final response = Completer<Delay>();
    final entered = Completer<void>();
    harness.probe = (url, name) {
      if (name == _hongKongOne.name) {
        entered.complete();
        return response.future;
      }
      return Future.value(Delay(name: name, url: url, value: -1));
    };

    final operation = harness.action.selectHongKongForMode(Mode.global);
    await entered.future;
    expect(harness.changes, isEmpty);
    expect(harness.setup.updates, isEmpty);
    expect(harness.mode, Mode.rule);
    expect(harness.profile, _profile);
    response.complete(
      Delay(name: _hongKongOne.name, url: defaultTestUrl, value: 45),
    );

    expect(await operation, HongKongSelectionResult.selected);
    expect(harness.changes, [
      const ChangeProxyParams(groupName: 'GLOBAL', proxyName: '香港 01'),
    ]);
    expect(harness.mode, Mode.global);
    expect(harness.setup.runtimeMode, Mode.global);
    expect(harness.profile.currentGroupName, 'GLOBAL');
    expect(harness.profile.selectedMap, {
      ..._profile.selectedMap,
      'GLOBAL': '香港 01',
    });
    expect(
      harness.events.indexOf('select:GLOBAL:香港 01'),
      lessThan(harness.events.indexOf('mode:global')),
    );
  });

  test('rule selection preserves unrelated split routing', () async {
    final harness = _Harness();

    expect(
      await harness.action.selectHongKongForMode(Mode.rule),
      HongKongSelectionResult.selected,
    );

    expect(harness.mode, Mode.rule);
    expect(harness.profile.currentGroupName, 'Route');
    expect(harness.profile.selectedMap, {
      ..._profile.selectedMap,
      'Route': '香港 01',
    });
    expect(
      harness.changes.every((change) => change.groupName == 'Route'),
      isTrue,
    );
  });

  test(
    'applied default rule target wins over the previous Netflix tab',
    () async {
      final initial = _profile.copyWith(
        currentGroupName: 'Netflix',
        selectedMap: {
          ..._profile.selectedMap,
          'Netflix': '日本 01',
          'Main': '日本 01',
        },
      );
      final harness = _Harness(
        initialProfile: initial,
        groups: const [
          Group(
            name: 'Netflix',
            type: GroupType.Selector,
            hidden: false,
            now: '日本 01',
            all: [_hongKongOne, _otherNode],
          ),
          Group(
            name: 'Main',
            type: GroupType.Selector,
            hidden: false,
            now: '日本 01',
            all: [_hongKongTwo, _otherNode],
          ),
        ],
      );
      harness.setup.ruleTarget = 'Main';

      expect(
        await harness.action.selectHongKongForMode(Mode.rule),
        HongKongSelectionResult.selected,
      );

      expect(harness.probes, ['香港 02']);
      expect(harness.changes, [
        const ChangeProxyParams(groupName: 'Main', proxyName: '香港 02'),
      ]);
      expect(harness.profile.currentGroupName, 'Main');
      expect(harness.profile.selectedMap, {
        ...initial.selectedMap,
        'Main': '香港 02',
      });
      expect(harness.mode, Mode.rule);
    },
  );

  test(
    'DIRECT default rule target cannot redirect an unrelated visible group',
    () async {
      final harness = _Harness();
      harness.setup.ruleTarget = 'DIRECT';

      expect(
        await harness.action.selectHongKongForMode(Mode.rule),
        HongKongSelectionResult.unavailable,
      );

      expect(harness.probes, isEmpty);
      harness.expectUnchanged();
    },
  );

  test('all failed fresh probes leave mode and selections unchanged', () async {
    final harness = _Harness();
    harness.probe = (url, name) async => Delay(name: name, url: url, value: -1);

    expect(
      await harness.action.selectHongKongForMode(Mode.global),
      HongKongSelectionResult.unavailable,
    );

    expect(harness.probes, [_hongKongOne.name, _hongKongTwo.name]);
    harness.expectUnchanged();
  });

  test(
    'cached positive latency never substitutes for a fresh failed probe',
    () async {
      final harness = _Harness();
      harness.action.setDelay(
        Delay(name: _hongKongOne.name, url: defaultTestUrl, value: 12),
      );
      harness.probe = (url, name) async =>
          Delay(name: name, url: url, value: -1);

      expect(
        await harness.action.selectHongKongForMode(Mode.global),
        HongKongSelectionResult.unavailable,
      );

      expect(harness.probes, contains(_hongKongOne.name));
      harness.expectUnchanged();
    },
  );

  for (final value in <int?>[0, -1, null]) {
    test('fresh delay $value cannot establish a usable HK candidate', () async {
      final harness = _Harness();
      harness.probe = (url, name) async =>
          Delay(name: name, url: url, value: value);

      expect(
        await harness.action.selectHongKongForMode(Mode.global),
        HongKongSelectionResult.unavailable,
      );

      harness.expectUnchanged();
    });
  }

  for (final mismatch in ['name', 'url']) {
    test('positive delay with a mismatched $mismatch is rejected', () async {
      final harness = _Harness();
      harness.probe = (url, name) async => Delay(
        name: mismatch == 'name' ? '香港 unrelated' : name,
        url: mismatch == 'url' ? 'https://probe.example.test/' : url,
        value: 25,
      );

      expect(
        await harness.action.selectHongKongForMode(Mode.global),
        HongKongSelectionResult.unavailable,
      );

      harness.expectUnchanged();
    });
  }

  test(
    'DIRECT and disguised direct or rejected HK names are not probed',
    () async {
      final harness = _Harness(
        groups: const [
          Group(
            name: 'GLOBAL',
            type: GroupType.Selector,
            all: [
              Proxy(name: 'DIRECT', type: 'Direct'),
              Proxy(name: 'REJECT', type: 'Reject'),
              Proxy(name: '香港 direct', type: 'dIrEcT'),
              Proxy(name: '香港 reject', type: 'REJECT'),
              Proxy(name: '香港 group', type: 'URLTest'),
            ],
          ),
        ],
      );

      expect(
        await harness.action.selectHongKongForMode(Mode.global),
        HongKongSelectionResult.unavailable,
      );

      expect(harness.probes, isEmpty);
      harness.expectUnchanged();
    },
  );

  test('direct mode never probes or changes a selection', () async {
    final harness = _Harness();

    expect(
      await harness.action.selectHongKongForMode(Mode.direct),
      HongKongSelectionResult.unavailable,
    );

    expect(harness.probes, isEmpty);
    harness.expectUnchanged();
  });

  test(
    'manual mode change during a probe cancels any late selection',
    () async {
      final harness = _Harness();
      final response = Completer<Delay>();
      final entered = Completer<void>();
      harness.probe = (url, name) {
        if (!entered.isCompleted) entered.complete();
        return response.future;
      };
      final operation = harness.action.selectHongKongForMode(Mode.global);
      await entered.future;

      harness.setup.changeMode(Mode.direct);
      response.complete(
        Delay(name: _hongKongOne.name, url: defaultTestUrl, value: 20),
      );

      expect(await operation, HongKongSelectionResult.cancelled);
      expect(harness.mode, Mode.direct);
      expect(harness.profile, _profile);
      expect(harness.changes, isEmpty);
      expect(harness.setup.updates, isEmpty);
    },
  );

  test(
    'changing profile during a probe does not mutate either profile',
    () async {
      final harness = _Harness();
      final otherProfile = _profile.copyWith(id: 2, label: 'Other profile');
      harness.container.read(profilesProvider.notifier).put(otherProfile);
      final response = Completer<Delay>();
      final entered = Completer<void>();
      harness.probe = (url, name) {
        if (!entered.isCompleted) entered.complete();
        return response.future;
      };
      final operation = harness.action.selectHongKongForMode(Mode.global);
      await entered.future;

      harness.container.read(currentProfileIdProvider.notifier).value = 2;
      expect(harness.container.read(currentProfileIdProvider), 2);
      response.complete(
        Delay(name: _hongKongOne.name, url: defaultTestUrl, value: 20),
      );

      expect(await operation, HongKongSelectionResult.cancelled);
      expect(harness.container.read(profilesProvider), [
        _profile,
        otherProfile,
      ]);
      expect(harness.changes, isEmpty);
      expect(harness.setup.updates, isEmpty);
      expect(harness.mode, Mode.rule);
    },
  );

  test(
    'cancellation after a nested write compensates before returning',
    () async {
      final harness = _Harness(groups: _nestedGroups);
      final firstWrite = Completer<void>();
      final releaseWrite = Completer<void>();
      harness.change = (params) async {
        if (params.groupName == 'Route' && params.proxyName == '香港 01') {
          firstWrite.complete();
          await releaseWrite.future;
        }
        harness.coreSelections[params.groupName] = params.proxyName;
        return '';
      };
      final operation = harness.action.selectHongKongForMode(Mode.global);
      await firstWrite.future;

      harness.action.cancelHongKongSelection();
      releaseWrite.complete();

      expect(await operation, HongKongSelectionResult.cancelled);
      expect(harness.changes, [
        const ChangeProxyParams(groupName: 'Route', proxyName: '香港 01'),
        const ChangeProxyParams(groupName: 'Route', proxyName: '日本 01'),
      ]);
      expect(harness.coreSelections, _profile.selectedMap);
      expect(harness.profile, _profile);
      expect(harness.mode, Mode.rule);
      expect(harness.setup.updates, isEmpty);
    },
  );

  test(
    'parent selection rejection rolls back a successful nested write',
    () async {
      final harness = _Harness(groups: _nestedGroups);
      harness.change = (params) async {
        if (params.groupName == 'GLOBAL' && params.proxyName == 'Route') {
          return 'Not found proxy';
        }
        harness.coreSelections[params.groupName] = params.proxyName;
        return '';
      };

      expect(
        await harness.action.selectHongKongForMode(Mode.global),
        HongKongSelectionResult.failed,
      );

      expect(harness.changes, [
        const ChangeProxyParams(groupName: 'Route', proxyName: '香港 01'),
        const ChangeProxyParams(groupName: 'GLOBAL', proxyName: 'Route'),
        const ChangeProxyParams(groupName: 'GLOBAL', proxyName: '日本 01'),
        const ChangeProxyParams(groupName: 'Route', proxyName: '日本 01'),
      ]);
      expect(harness.coreSelections, _profile.selectedMap);
      expect(harness.profile, _profile);
      expect(harness.mode, Mode.rule);
      expect(harness.setup.updates, isEmpty);
    },
  );

  for (final failure in ['message', 'exception']) {
    test(
      'mode RPC $failure after applying mode restores Core and profile',
      () async {
        final harness = _Harness();
        harness.setup.onUpdate = (params) async {
          if (params.mode == Mode.global) {
            if (failure == 'exception') throw StateError('transport failed');
            return 'listener not ready';
          }
          return '';
        };

        expect(
          await harness.action.selectHongKongForMode(Mode.global),
          HongKongSelectionResult.failed,
        );

        expect(harness.setup.updates.map((params) => params.mode), [
          Mode.global,
          Mode.rule,
        ]);
        expect(harness.setup.runtimeMode, Mode.rule);
        expect(harness.mode, Mode.rule);
        expect(harness.profile, _profile);
        expect(harness.coreSelections, _profile.selectedMap);
      },
    );
  }

  test(
    'selector RPC failure after mutation restores the attempted write',
    () async {
      final harness = _Harness(groups: _nestedGroups);
      harness.change = (params) async {
        harness.coreSelections[params.groupName] = params.proxyName;
        if (params.proxyName == '香港 01') {
          throw StateError('response disconnected after selector mutation');
        }
        return '';
      };

      expect(
        await harness.action.selectHongKongForMode(Mode.global),
        HongKongSelectionResult.failed,
      );

      expect(harness.coreSelections, _profile.selectedMap);
      expect(harness.profile, _profile);
      expect(harness.mode, Mode.rule);
      expect(harness.setup.updates, isEmpty);
    },
  );

  test(
    'profile switch during selector RPC prevents cross-profile compensation',
    () async {
      final harness = _Harness(groups: _nestedGroups);
      final otherProfile = _profile.copyWith(id: 2, label: 'Other profile');
      harness.container.read(profilesProvider.notifier).put(otherProfile);
      final entered = Completer<void>();
      final release = Completer<void>();
      harness.change = (params) async {
        entered.complete();
        await release.future;
        return '';
      };
      final operation = harness.action.selectHongKongForMode(Mode.global);
      await entered.future;

      harness.container.read(currentProfileIdProvider.notifier).value = 2;
      release.complete();

      expect(await operation, HongKongSelectionResult.cancelled);
      expect(harness.changes, [
        const ChangeProxyParams(groupName: 'Route', proxyName: '香港 01'),
      ]);
      expect(harness.container.read(profilesProvider), [
        _profile,
        otherProfile,
      ]);
      expect(harness.setup.updates, isEmpty);
      expect(harness.mode, Mode.rule);
    },
  );

  test(
    'cancellation during mode RPC restores mode and all selector writes',
    () async {
      final harness = _Harness(groups: _nestedGroups);
      final entered = Completer<void>();
      final release = Completer<void>();
      harness.setup.onUpdate = (params) async {
        if (params.mode == Mode.global) {
          entered.complete();
          await release.future;
        }
        return '';
      };
      final operation = harness.action.selectHongKongForMode(Mode.global);
      await entered.future;

      harness.action.cancelHongKongSelection();
      release.complete();

      expect(await operation, HongKongSelectionResult.cancelled);
      expect(harness.setup.updates.map((params) => params.mode), [
        Mode.global,
        Mode.rule,
      ]);
      expect(harness.setup.runtimeMode, Mode.rule);
      expect(harness.coreSelections, _profile.selectedMap);
      expect(harness.profile, _profile);
      expect(harness.mode, Mode.rule);
    },
  );

  test(
    'successful automatic selection closes existing streams once after commit',
    () async {
      final harness = _Harness(groups: _nestedGroups);
      harness.container
          .read(appSettingProvider.notifier)
          .update((settings) => settings.copyWith(closeConnections: true));

      expect(
        await harness.action.selectHongKongForMode(Mode.global),
        HongKongSelectionResult.selected,
      );

      expect(harness.changes, hasLength(2));
      verify(() => harness.core.closeConnections()).called(1);
      verifyNever(() => harness.core.resetConnections());
      expect(
        harness.events.indexOf('mode:global'),
        lessThan(harness.events.indexOf('close')),
      );
    },
  );

  test(
    'automatic selection resets resolver once when stream closing is disabled',
    () async {
      final harness = _Harness(groups: _nestedGroups);
      harness.container
          .read(appSettingProvider.notifier)
          .update((settings) => settings.copyWith(closeConnections: false));

      expect(
        await harness.action.selectHongKongForMode(Mode.global),
        HongKongSelectionResult.selected,
      );

      expect(harness.changes, hasLength(2));
      verifyNever(() => harness.core.closeConnections());
      verify(() => harness.core.resetConnections()).called(1);
      expect(
        harness.events.indexOf('mode:global'),
        lessThan(harness.events.indexOf('reset')),
      );
    },
  );

  test(
    'connection cleanup failure keeps the committed automatic selection',
    () async {
      final harness = _Harness(groups: _nestedGroups);
      when(
        () => harness.core.closeConnections(),
      ).thenThrow(StateError('cleanup failed'));

      expect(
        await harness.action.selectHongKongForMode(Mode.global),
        HongKongSelectionResult.selected,
      );

      expect(harness.mode, Mode.global);
      expect(harness.profile.currentGroupName, 'GLOBAL');
      expect(harness.profile.selectedMap['GLOBAL'], 'Route');
      expect(harness.profile.selectedMap['Route'], '香港 01');
      expect(harness.coreSelections, harness.profile.selectedMap);
      verify(() => harness.core.closeConnections()).called(1);
      verifyNever(() => harness.core.resetConnections());
    },
  );

  test(
    'late cancellation during cleanup does not partially roll back a commit',
    () async {
      final harness = _Harness(groups: _nestedGroups);
      final entered = Completer<void>();
      final release = Completer<bool>();
      when(() => harness.core.closeConnections()).thenAnswer((_) {
        harness.events.add('close');
        entered.complete();
        return release.future;
      });

      final operation = harness.action.selectHongKongForMode(Mode.global);
      await entered.future;
      harness.action.cancelHongKongSelection(manual: true);
      release.complete(true);

      expect(await operation, HongKongSelectionResult.selected);
      expect(harness.mode, Mode.global);
      expect(harness.profile.currentGroupName, 'GLOBAL');
      expect(harness.profile.selectedMap['GLOBAL'], 'Route');
      expect(harness.profile.selectedMap['Route'], '香港 01');
      expect(harness.coreSelections, harness.profile.selectedMap);
      verify(() => harness.core.closeConnections()).called(1);
      verifyNever(() => harness.core.resetConnections());
    },
  );

  test(
    'manual mode intent during mode RPC wins over automatic rollback',
    () async {
      final harness = _Harness();
      final entered = Completer<void>();
      final release = Completer<void>();
      harness.setup.onUpdate = (params) async {
        if (params.mode == Mode.global) {
          entered.complete();
          await release.future;
        }
        return '';
      };
      final operation = harness.action.selectHongKongForMode(Mode.global);
      await entered.future;

      harness.setup.changeMode(Mode.direct);
      release.complete();

      expect(await operation, HongKongSelectionResult.cancelled);
      expect(harness.setup.runtimeMode, Mode.direct);
      expect(harness.mode, Mode.direct);
      expect(harness.profile, _profile);
      expect(harness.coreSelections, _profile.selectedMap);
      expect(harness.setup.updates.map((params) => params.mode), [
        Mode.global,
        Mode.direct,
      ]);
    },
  );

  test(
    'active chain proxy refuses automatic global selection before probing',
    () async {
      final harness = _Harness();
      harness.container
          .read(appSettingProvider.notifier)
          .update(
            (settings) => settings.copyWith(
              activeChainProxyName: 'Configured chain',
              chainProxies: const [
                ChainProxyConfig(
                  name: 'Configured chain',
                  server: 'chain.example.test',
                  port: 1080,
                ),
              ],
            ),
          );

      expect(
        await harness.action.selectHongKongForMode(Mode.global),
        HongKongSelectionResult.failed,
      );

      expect(harness.probes, isEmpty);
      harness.expectUnchanged();
    },
  );

  test(
    'enabling a chain proxy during a probe cancels automatic global mode',
    () async {
      final harness = _Harness();
      final entered = Completer<void>();
      final response = Completer<Delay>();
      harness.probe = (url, name) {
        if (!entered.isCompleted) entered.complete();
        return response.future;
      };
      final operation = harness.action.selectHongKongForMode(Mode.global);
      await entered.future;

      harness.container
          .read(appSettingProvider.notifier)
          .update(
            (settings) => settings.copyWith(
              activeChainProxyName: 'Configured chain',
              chainProxies: const [
                ChainProxyConfig(
                  name: 'Configured chain',
                  server: 'chain.example.test',
                  port: 1080,
                ),
              ],
            ),
          );
      response.complete(
        Delay(name: _hongKongOne.name, url: defaultTestUrl, value: 20),
      );

      expect(await operation, HongKongSelectionResult.cancelled);
      harness.expectUnchanged();
    },
  );
}

class _MockCore extends Mock implements CoreHandlerInterface {}

class _Harness {
  _Harness({List<Group> groups = _groups, Profile initialProfile = _profile}) {
    coreSelections.addAll(initialProfile.selectedMap);
    container = ProviderContainer(
      overrides: [
        currentProfileIdProvider.overrideWithBuild((_, _) => initialProfile.id),
        profilesProvider.overrideWith(() => _TestProfiles([initialProfile])),
        groupsProvider.overrideWithBuild((_, _) => groups),
        coreStatusProvider.overrideWithBuild((_, _) => CoreStatus.connected),
        runTimeProvider.overrideWithBuild((_, _) => 1000),
        setupActionProvider.overrideWith(() => _TestSetup(events)),
        proxiesActionProvider.overrideWith(
          () => _TestProxies(CoreController.test(core)),
        ),
      ],
    );
    addTearDown(container.dispose);
    action = container.read(proxiesActionProvider.notifier);
    setup = container.read(setupActionProvider.notifier) as _TestSetup;
    container
        .read(patchClashConfigProvider.notifier)
        .update((config) => config.copyWith(mode: Mode.rule));
    when(() => core.asyncTestDelay(any(), any())).thenAnswer((invocation) {
      final url = invocation.positionalArguments[0] as String;
      final name = invocation.positionalArguments[1] as String;
      probes.add(name);
      events.add('probe:$name');
      return probe(url, name);
    });
    when(() => core.changeProxy(any())).thenAnswer((invocation) {
      final params = invocation.positionalArguments.single as ChangeProxyParams;
      changes.add(params);
      events.add('select:${params.groupName}:${params.proxyName}');
      if (change != null) return change!(params);
      coreSelections[params.groupName] = params.proxyName;
      return Future.value('');
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
  final probes = <String>[];
  final changes = <ChangeProxyParams>[];
  final coreSelections = <String, String>{};
  late final ProviderContainer container;
  late final ProxiesAction action;
  late final _TestSetup setup;
  Future<Delay> Function(String url, String name) probe = (url, name) async =>
      Delay(name: name, url: url, value: 30);
  Future<String> Function(ChangeProxyParams params)? change;

  Mode get mode => container.read(patchClashConfigProvider).mode;

  Profile get profile => container.read(currentProfileProvider)!;

  void expectUnchanged() {
    expect(mode, Mode.rule);
    expect(profile, _profile);
    expect(coreSelections, _profile.selectedMap);
    expect(changes, isEmpty);
    expect(setup.updates, isEmpty);
    verifyNever(() => core.closeConnections());
    verifyNever(() => core.resetConnections());
  }
}

class _TestProxies extends ProxiesAction {
  _TestProxies(this.controller);

  final CoreController controller;

  @override
  CoreController get proxyController => controller;

  @override
  Duration get hongKongProbeTimeout => const Duration(milliseconds: 500);

  @override
  void updateGroupsDebounce([Duration? duration]) {}
}

class _TestSetup extends SetupAction {
  _TestSetup(this.events);

  final List<String> events;
  final updates = <UpdateParams>[];
  Mode runtimeMode = Mode.rule;
  String? ruleTarget;
  Future<String> Function(UpdateParams params)? onUpdate;

  @override
  String? get ruleSelectionGroup => ruleTarget;

  @override
  Future<String> applyCoreUpdate(UpdateParams params) async {
    updates.add(params);
    runtimeMode = params.mode;
    events.add('mode:${params.mode.name}');
    return await onUpdate?.call(params) ?? '';
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

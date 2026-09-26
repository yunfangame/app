import 'package:fl_clash/common/chain_proxy.dart';
import 'package:fl_clash/common/saved_node_selection.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:flutter_test/flutter_test.dart';

const hongKong = Proxy(name: 'HK node', type: 'ss');
const unitedStates = Proxy(name: 'US node', type: 'trojan');

Group group(
  String name,
  List<Proxy> members, {
  GroupType type = GroupType.Selector,
  String? now,
  bool hidden = false,
}) {
  return Group(name: name, type: type, all: members, now: now, hidden: hidden);
}

Proxy groupMember(String name, GroupType type) {
  return Proxy(name: name, type: type.value);
}

void main() {
  test('global retains the saved US node when the core defaults to HK', () {
    expect(
      hasValidSavedNodeSelection(
        mode: Mode.global,
        groups: [
          group('GLOBAL', [hongKong, unitedStates], now: hongKong.name),
        ],
        selectedMap: const {'GLOBAL': 'US node'},
      ),
      isTrue,
    );
  });

  test(
    'a removed saved node cannot be replaced by now or the first member',
    () {
      for (final now in [null, hongKong.name]) {
        expect(
          hasValidSavedNodeSelection(
            mode: Mode.global,
            groups: [
              group('GLOBAL', [hongKong], now: now),
            ],
            selectedMap: const {'GLOBAL': 'US node'},
          ),
          isFalse,
        );
      }
    },
  );

  test('a root selector requires an explicit saved selection', () {
    for (final selectedMap in [
      <String, String>{},
      {'GLOBAL': ''},
      {'Other': 'US node'},
    ]) {
      expect(
        hasValidSavedNodeSelection(
          mode: Mode.global,
          groups: [
            group('GLOBAL', [hongKong, unitedStates], now: unitedStates.name),
          ],
          selectedMap: selectedMap,
        ),
        isFalse,
      );
    }
  });

  test('global requires GLOBAL and rejects an automatic GLOBAL root', () {
    expect(
      hasValidSavedNodeSelection(
        mode: Mode.global,
        groups: [
          group('Route', [unitedStates]),
        ],
        selectedMap: const {'Route': 'US node'},
      ),
      isFalse,
    );
    expect(
      hasValidSavedNodeSelection(
        mode: Mode.global,
        groups: [
          group('GLOBAL', [unitedStates], type: GroupType.URLTest),
        ],
        selectedMap: const {'GLOBAL': 'US node'},
      ),
      isFalse,
    );
  });

  test('nested selectors each require a valid saved member', () {
    final groups = [
      group('GLOBAL', [groupMember('Route', GroupType.Selector)]),
      group('Route', [hongKong, unitedStates], now: hongKong.name),
    ];
    expect(
      hasValidSavedNodeSelection(
        mode: Mode.global,
        groups: groups,
        selectedMap: const {'GLOBAL': 'Route', 'Route': 'US node'},
      ),
      isTrue,
    );
    for (final selectedMap in [
      {'GLOBAL': 'Route'},
      {'GLOBAL': 'Route', 'Route': 'Removed node'},
    ]) {
      expect(
        hasValidSavedNodeSelection(
          mode: Mode.global,
          groups: groups,
          selectedMap: selectedMap,
        ),
        isFalse,
      );
    }
  });

  test('a referenced group must still exist and cycles are invalid', () {
    expect(
      hasValidSavedNodeSelection(
        mode: Mode.global,
        groups: [
          group('GLOBAL', [groupMember('Removed', GroupType.Selector)]),
        ],
        selectedMap: const {'GLOBAL': 'Removed', 'Removed': 'US node'},
      ),
      isFalse,
    );
    expect(
      hasValidSavedNodeSelection(
        mode: Mode.rule,
        groups: [
          group('Route', [groupMember('Nested', GroupType.Selector)]),
          group('Nested', [groupMember('Route', GroupType.Selector)]),
        ],
        ruleGroupName: 'Route',
        selectedMap: const {'Route': 'Nested', 'Nested': 'Route'},
      ),
      isFalse,
    );
  });

  test(
    'automatic choices survive without a currently healthy runtime leaf',
    () {
      for (final type in [
        GroupType.URLTest,
        GroupType.Fallback,
        GroupType.LoadBalance,
      ]) {
        for (final now in [null, '', 'Removed runtime node']) {
          final automatic = group(
            'Automatic',
            [unitedStates],
            type: type,
            now: now,
          );
          expect(
            hasValidSavedNodeSelection(
              mode: Mode.global,
              groups: [
                group('GLOBAL', [groupMember('Automatic', type)]),
                automatic,
              ],
              selectedMap: const {'GLOBAL': 'Automatic'},
            ),
            isTrue,
          );
          expect(
            hasValidSavedNodeSelection(
              mode: Mode.rule,
              groups: [automatic],
              ruleGroupName: 'Automatic',
              selectedMap: const {},
            ),
            isTrue,
          );
        }
      }
    },
  );

  test('empty or pseudo-only automatic groups cannot preserve a node', () {
    for (final members in [
      <Proxy>[],
      [const Proxy(name: 'DIRECT', type: 'Direct')],
    ]) {
      expect(
        hasValidSavedNodeSelection(
          mode: Mode.rule,
          groups: [group('Automatic', members, type: GroupType.URLTest)],
          ruleGroupName: 'Automatic',
          selectedMap: const {},
        ),
        isFalse,
      );
    }
  });

  test('automatic groups preserve an explicit pin instead of runtime now', () {
    for (final type in [GroupType.URLTest, GroupType.Fallback]) {
      expect(
        hasValidSavedNodeSelection(
          mode: Mode.global,
          groups: [
            group('GLOBAL', [groupMember('Automatic', type)]),
            group(
              'Automatic',
              [hongKong, unitedStates],
              type: type,
              now: hongKong.name,
            ),
          ],
          selectedMap: const {'GLOBAL': 'Automatic', 'Automatic': 'US node'},
        ),
        isTrue,
      );
    }
  });

  test('a removed automatic-group pin cannot fall back to another member', () {
    for (final type in [GroupType.URLTest, GroupType.Fallback]) {
      final automatic = group(
        'Automatic',
        [hongKong],
        type: type,
        now: hongKong.name,
      );
      expect(
        hasValidSavedNodeSelection(
          mode: Mode.global,
          groups: [
            group('GLOBAL', [groupMember('Automatic', type)]),
            automatic,
          ],
          selectedMap: const {'GLOBAL': 'Automatic', 'Automatic': 'US node'},
        ),
        isFalse,
      );
      expect(
        hasValidSavedNodeSelection(
          mode: Mode.rule,
          groups: [automatic],
          ruleGroupName: 'Automatic',
          selectedMap: const {'Automatic': 'US node'},
        ),
        isFalse,
      );
    }
  });

  test('an empty automatic-group pin leaves automatic selection enabled', () {
    for (final type in [GroupType.URLTest, GroupType.Fallback]) {
      expect(
        hasValidSavedNodeSelection(
          mode: Mode.global,
          groups: [
            group('GLOBAL', [groupMember('Automatic', type)]),
            group('Automatic', [hongKong], type: type),
          ],
          selectedMap: const {'GLOBAL': 'Automatic', 'Automatic': ''},
        ),
        isTrue,
      );
    }
  });

  test('automatic groups respect saved nested selectors', () {
    expect(
      hasValidSavedNodeSelection(
        mode: Mode.rule,
        groups: [
          group('Automatic', [
            groupMember('Nested', GroupType.Selector),
          ], type: GroupType.Fallback),
          group('Nested', [hongKong], now: hongKong.name),
        ],
        ruleGroupName: 'Automatic',
        selectedMap: const {'Nested': 'Removed node'},
      ),
      isFalse,
    );
  });

  test('the actual rule target takes precedence over the current UI group', () {
    final groups = [
      group('Other', [hongKong]),
      group('Actual', [unitedStates], hidden: true),
    ];
    expect(
      hasValidSavedNodeSelection(
        mode: Mode.rule,
        groups: groups,
        ruleGroupName: 'Actual',
        currentGroupName: 'Other',
        selectedMap: const {'Other': 'HK node', 'Actual': 'US node'},
      ),
      isTrue,
    );
    expect(
      hasValidSavedNodeSelection(
        mode: Mode.rule,
        groups: groups,
        ruleGroupName: 'Actual',
        currentGroupName: 'Other',
        selectedMap: const {'Other': 'HK node', 'Actual': 'Removed node'},
      ),
      isFalse,
    );
  });

  test('rule fallback chooses the current visible non-global selector', () {
    expect(
      hasValidSavedNodeSelection(
        mode: Mode.rule,
        groups: [
          group('GLOBAL', [hongKong]),
          group('Hidden', [hongKong], hidden: true),
          group('Automatic', [hongKong], type: GroupType.URLTest),
          group('Other', [hongKong]),
          group('Current', [unitedStates]),
        ],
        currentGroupName: 'Current',
        selectedMap: const {'Current': 'US node'},
      ),
      isTrue,
    );
  });

  test('renamed root without a saved selection requires a default', () {
    expect(
      hasValidSavedNodeSelection(
        mode: Mode.rule,
        groups: [
          group('New route', [hongKong, unitedStates], now: unitedStates.name),
        ],
        ruleGroupName: 'Old route',
        currentGroupName: 'Old route',
        selectedMap: const {'Old route': 'US node'},
      ),
      isFalse,
    );
  });

  test(
    'fallback uses the first visible selector without inventing a choice',
    () {
      final groups = [
        group('GLOBAL', [hongKong]),
        group('Automatic', [hongKong], type: GroupType.URLTest),
        group('Route', [unitedStates]),
      ];
      for (final currentGroupName in ['GLOBAL', 'Automatic', 'Removed']) {
        expect(
          hasValidSavedNodeSelection(
            mode: Mode.rule,
            groups: groups,
            currentGroupName: currentGroupName,
            selectedMap: const {'Route': 'US node'},
          ),
          isTrue,
        );
      }
    },
  );

  test('ambiguous duplicate groups and members are invalid', () {
    for (final groups in [
      [
        group('GLOBAL', [unitedStates]),
        group('GLOBAL', [hongKong]),
      ],
      [
        group('GLOBAL', [unitedStates, unitedStates]),
      ],
    ]) {
      expect(
        hasValidSavedNodeSelection(
          mode: Mode.global,
          groups: groups,
          selectedMap: const {'GLOBAL': 'US node'},
        ),
        isFalse,
      );
    }
  });

  test('pseudo adapters and runtime chain proxies are not saved nodes', () {
    for (final proxy in const [
      Proxy(name: 'DIRECT', type: 'ss'),
      Proxy(name: 'reject-drop', type: 'trojan'),
      Proxy(name: 'PASS_RULE', type: 'ss'),
      Proxy(name: 'Ordinary', type: 'Direct'),
      Proxy(name: 'Ordinary', type: 'Compatible'),
      Proxy(name: 'Ordinary', type: ''),
      Proxy(name: chainProxyRuntimeName, type: 'socks5'),
      Proxy(name: '$chainProxyRuntimeName 2', type: 'http'),
    ]) {
      expect(
        hasValidSavedNodeSelection(
          mode: Mode.global,
          groups: [
            group('GLOBAL', [proxy]),
          ],
          selectedMap: {'GLOBAL': proxy.name},
        ),
        isFalse,
      );
    }
  });

  test('a real leaf does not become a group because of a shared name', () {
    expect(
      hasValidSavedNodeSelection(
        mode: Mode.global,
        groups: [
          group('GLOBAL', [unitedStates]),
          group('US node', [hongKong]),
        ],
        selectedMap: const {'GLOBAL': 'US node'},
      ),
      isTrue,
    );
  });

  test('direct mode restores without any selected node', () {
    expect(
      hasValidSavedNodeSelection(
        mode: Mode.direct,
        groups: const [],
        selectedMap: const {},
      ),
      isTrue,
    );
  });
}

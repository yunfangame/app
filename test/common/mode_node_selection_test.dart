import 'package:fl_clash/common/mode_node_selection.dart';
import 'package:fl_clash/common/chain_proxy.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:flutter_test/flutter_test.dart';

const nodeA = Proxy(name: 'Node A', type: 'ss');
const nodeB = Proxy(name: 'Node B', type: 'trojan');

Group group(
  String name,
  GroupType type,
  List<Proxy> members, {
  String? now,
  bool hidden = false,
}) {
  return Group(name: name, type: type, all: members, now: now, hidden: hidden);
}

Proxy groupMember(String name, GroupType type) {
  return Proxy(name: name, type: type.value);
}

void main() {
  test('rule display uses a visible rule target group', () {
    expect(
      resolveRuleModeDisplayGroup(
        ruleTargetName: 'Target',
        currentGroupName: 'Other',
        groups: [
          group('GLOBAL', GroupType.Selector, [nodeA], hidden: true),
          group('Other', GroupType.Selector, [nodeA]),
          group('Target', GroupType.Selector, [nodeB]),
        ],
      ),
      'Target',
    );
  });

  test('rule display keeps a valid group for a direct MATCH leaf', () {
    expect(
      resolveRuleModeDisplayGroup(
        ruleTargetName: 'Node A',
        currentGroupName: 'Other',
        groups: [
          group('GLOBAL', GroupType.Selector, [nodeA], hidden: true),
          group('Other', GroupType.Selector, [nodeB]),
        ],
      ),
      'Other',
    );
  });

  test('rule display falls back to the first visible rule group', () {
    expect(
      resolveRuleModeDisplayGroup(
        ruleTargetName: 'Node A',
        currentGroupName: 'GLOBAL',
        groups: [
          group('GLOBAL', GroupType.Selector, [nodeA], hidden: true),
          group('Route', GroupType.Selector, [nodeB]),
        ],
      ),
      'Route',
    );
  });

  test('rule display is null when no rule group is visible', () {
    expect(
      resolveRuleModeDisplayGroup(
        ruleTargetName: 'Node A',
        currentGroupName: 'GLOBAL',
        groups: [
          group('GLOBAL', GroupType.Selector, [nodeA], hidden: true),
        ],
      ),
      isNull,
    );
  });

  test('resolves a real source leaf through selector and automatic groups', () {
    final groups = [
      group('Source', GroupType.Selector, [
        groupMember('Automatic', GroupType.URLTest),
      ]),
      group('Automatic', GroupType.URLTest, [
        groupMember('Inner', GroupType.Selector),
      ], now: 'Inner'),
      group('Inner', GroupType.Selector, [nodeA]),
    ];

    expect(
      resolveModeNodeLeaf(
        rootGroupName: 'Source',
        groups: groups,
        selectedMap: const {'Source': 'Automatic', 'Inner': 'Node A'},
      ),
      'Node A',
    );
  });

  test('source cycles and stale members do not invent a selected leaf', () {
    final cyclic = [
      group('Source', GroupType.Selector, [
        groupMember('Inner', GroupType.Selector),
      ], now: 'Inner'),
      group('Inner', GroupType.Selector, [
        groupMember('Source', GroupType.Selector),
      ], now: 'Source'),
    ];

    expect(
      resolveModeNodeLeaf(
        rootGroupName: 'Source',
        groups: cyclic,
        selectedMap: const {},
      ),
      isNull,
    );
    expect(
      resolveModeNodeLeaf(
        rootGroupName: 'Source',
        groups: [
          group('Source', GroupType.Selector, [nodeA], now: 'missing'),
        ],
        selectedMap: const {},
      ),
      isNull,
    );
  });

  test('stale persisted selector falls back to a valid runtime member', () {
    expect(
      resolveModeNodeLeaf(
        rootGroupName: 'Source',
        groups: [
          group('Source', GroupType.Selector, [nodeA], now: 'Node A'),
        ],
        selectedMap: const {'Source': 'Removed node'},
      ),
      'Node A',
    );
  });

  test('valid persisted selector wins over a different runtime member', () {
    expect(
      resolveModeNodeLeaf(
        rootGroupName: 'Source',
        groups: [
          group('Source', GroupType.Selector, [nodeA, nodeB], now: 'Node B'),
        ],
        selectedMap: const {'Source': 'Node A'},
      ),
      'Node A',
    );
  });

  test(
    'a real leaf does not become a nested group only by sharing its name',
    () {
      final groups = [
        group('Source', GroupType.Selector, [nodeA], now: 'Node A'),
        group('Node A', GroupType.Selector, [nodeB], now: 'Node B'),
        group('Target', GroupType.Selector, [nodeA], now: 'Node A'),
      ];

      expect(
        resolveModeNodeLeaf(
          rootGroupName: 'Source',
          groups: groups,
          selectedMap: const {},
        ),
        'Node A',
      );
      expect(
        planModeNodeSelection(
          sourceGroupName: 'Source',
          targetGroupName: 'Target',
          groups: groups,
          selectedMap: const {},
        )?.selections,
        {'Target': 'Node A'},
      );
    },
  );

  test('duplicate group names are rejected as ambiguous', () {
    final groups = [
      group('Source', GroupType.Selector, [nodeA], now: 'Node A'),
      group('Source', GroupType.Selector, [nodeB], now: 'Node B'),
      group('Target', GroupType.Selector, [nodeA], now: 'Node A'),
    ];

    expect(
      resolveModeNodeLeaf(
        rootGroupName: 'Source',
        groups: groups,
        selectedMap: const {},
      ),
      isNull,
    );
    expect(
      planModeNodeSelection(
        sourceGroupName: 'Source',
        targetGroupName: 'Target',
        groups: groups,
        selectedMap: const {},
      ),
      isNull,
    );
  });

  test('pseudo leaves are excluded by reserved name or adapter type', () {
    for (final proxy in const [
      Proxy(name: 'DIRECT', type: 'ss'),
      Proxy(name: 'reject-drop', type: 'trojan'),
      Proxy(name: 'PASS_RULE', type: 'ss'),
      Proxy(name: 'Ordinary', type: 'Direct'),
      Proxy(name: 'Ordinary', type: 'Compatible'),
      Proxy(name: 'Ordinary', type: ''),
      Proxy(name: 'Missing group', type: 'url-test'),
      Proxy(name: chainProxyRuntimeName, type: 'socks5'),
      Proxy(name: '$chainProxyRuntimeName 2', type: 'http'),
    ]) {
      expect(
        resolveModeNodeLeaf(
          rootGroupName: 'Source',
          groups: [
            group('Source', GroupType.Selector, [proxy], now: proxy.name),
          ],
          selectedMap: const {},
        ),
        isNull,
        reason: '${proxy.name}/${proxy.type}',
      );
    }
  });

  test('load-balance and relay sources are ambiguous', () {
    for (final type in [GroupType.LoadBalance, GroupType.Relay]) {
      expect(
        resolveModeNodeLeaf(
          rootGroupName: 'Source',
          groups: [
            group('Source', type, [nodeA], now: 'Node A'),
          ],
          selectedMap: const {},
        ),
        isNull,
      );
    }
  });

  test('plans selector writes from root to inner selector', () {
    final plan = planModeNodeSelection(
      sourceGroupName: 'Source',
      targetGroupName: 'Target',
      groups: [
        group('Source', GroupType.Selector, [nodeA], now: 'Node A'),
        group('Target', GroupType.Selector, [
          groupMember('Region', GroupType.Selector),
        ]),
        group('Region', GroupType.Selector, [nodeA]),
      ],
      selectedMap: const {},
    );

    expect(plan?.nodeName, 'Node A');
    expect(plan?.targetGroupName, 'Target');
    expect(plan?.selections, {'Target': 'Region', 'Region': 'Node A'});
    expect(plan?.selections.entries.map((entry) => entry.key), [
      'Target',
      'Region',
    ]);
    expect(() => plan!.selections['Target'] = 'Node A', throwsUnsupportedError);
  });

  test('a direct MATCH leaf can be inherited into the target group', () {
    final plan = planModeNodeSelection(
      sourceGroupName: 'Node A',
      targetGroupName: 'Target',
      groups: [
        group('Target', GroupType.Selector, [nodeA, nodeB]),
      ],
      selectedMap: const {'Target': 'Node B'},
    );

    expect(plan?.nodeName, 'Node A');
    expect(plan?.selections, {'Target': 'Node A'});
  });

  test('automatic target groups are followed only through runtime now', () {
    final groups = [
      group('Source', GroupType.Selector, [nodeA], now: 'Node A'),
      group('Target', GroupType.Selector, [
        groupMember('Automatic', GroupType.URLTest),
      ]),
      group('Automatic', GroupType.URLTest, [nodeA, nodeB], now: 'Node A'),
    ];
    final plan = planModeNodeSelection(
      sourceGroupName: 'Source',
      targetGroupName: 'Target',
      groups: groups,
      selectedMap: const {'Automatic': 'Node B'},
    );

    expect(plan?.selections, {'Target': 'Automatic'});

    final changedNow = groups
        .map(
          (item) =>
              item.name == 'Automatic' ? item.copyWith(now: 'Node B') : item,
        )
        .toList();
    expect(
      planModeNodeSelection(
        sourceGroupName: 'Source',
        targetGroupName: 'Target',
        groups: changedNow,
        selectedMap: const {'Automatic': 'Node A'},
      ),
      isNull,
    );
  });

  test('automatic target edge may lead to a writable inner selector', () {
    final plan = planModeNodeSelection(
      sourceGroupName: 'Source',
      targetGroupName: 'Target',
      groups: [
        group('Source', GroupType.Selector, [nodeA], now: 'Node A'),
        group('Target', GroupType.Selector, [
          groupMember('Automatic', GroupType.Fallback),
        ]),
        group('Automatic', GroupType.Fallback, [
          groupMember('Inner', GroupType.Selector),
        ], now: 'Inner'),
        group('Inner', GroupType.Selector, [nodeA, nodeB], now: 'Node B'),
      ],
      selectedMap: const {},
    );

    expect(plan?.selections, {'Target': 'Automatic', 'Inner': 'Node A'});
  });

  test('prefers the complete current target path to earlier alternatives', () {
    final plan = planModeNodeSelection(
      sourceGroupName: 'Source',
      targetGroupName: 'Target',
      groups: [
        group('Source', GroupType.Selector, [nodeA], now: 'Node A'),
        group('Target', GroupType.Selector, [
          groupMember('First', GroupType.Selector),
          groupMember('Current', GroupType.Selector),
        ]),
        group('First', GroupType.Selector, [nodeA]),
        group('Current', GroupType.Selector, [nodeA]),
      ],
      selectedMap: const {'Target': 'Current', 'Current': 'Node A'},
    );

    expect(plan?.selections, {'Target': 'Current', 'Current': 'Node A'});
  });

  test('target cycles terminate and leave other branches available', () {
    final plan = planModeNodeSelection(
      sourceGroupName: 'Source',
      targetGroupName: 'Target',
      groups: [
        group('Source', GroupType.Selector, [nodeA], now: 'Node A'),
        group('Target', GroupType.Selector, [
          groupMember('Cycle', GroupType.Selector),
          nodeA,
        ], now: 'Cycle'),
        group('Cycle', GroupType.Selector, [
          groupMember('Target', GroupType.Selector),
        ], now: 'Target'),
      ],
      selectedMap: const {},
    );

    expect(plan?.selections, {'Target': 'Node A'});
  });

  test('ambiguous or unreachable targets produce no plan', () {
    for (final target in [
      group('Target', GroupType.LoadBalance, [nodeA], now: 'Node A'),
      group('Target', GroupType.Relay, [nodeA], now: 'Node A'),
      group('Target', GroupType.Selector, [nodeB], now: 'Node B'),
    ]) {
      expect(
        planModeNodeSelection(
          sourceGroupName: 'Source',
          targetGroupName: 'Target',
          groups: [
            group('Source', GroupType.Selector, [nodeA], now: 'Node A'),
            target,
          ],
          selectedMap: const {},
        ),
        isNull,
        reason: target.type.name,
      );
    }
  });
}

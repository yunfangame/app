import 'package:fl_clash/common/hong_kong_selection.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:flutter_test/flutter_test.dart';

const hongKongOne = Proxy(name: '香港 01', type: 'Shadowsocks');
const hongKongTwo = Proxy(name: '香港 02', type: 'ss');
const otherNode = Proxy(name: '日本 01', type: 'Trojan');

Group selector(
  String name,
  List<Proxy> members, {
  String? now,
  bool? hidden = false,
}) {
  return Group(
    name: name,
    type: GroupType.Selector,
    all: members,
    now: now,
    hidden: hidden,
  );
}

void main() {
  test('global mode only returns members reachable from GLOBAL', () {
    final candidates = hongKongCandidates(
      mode: Mode.global,
      groups: [
        selector('Other', [hongKongTwo]),
        selector('GLOBAL', [hongKongOne], hidden: true),
      ],
      selectedMap: const {},
      currentGroupName: 'Other',
    );

    expect(candidates.map((candidate) => candidate.nodeName), ['香港 01']);
    expect(candidates.single.groupName, 'GLOBAL');
    expect(candidates.single.selections, {'GLOBAL': '香港 01'});
  });

  test('global mode follows nested selectable membership', () {
    final candidates = hongKongCandidates(
      mode: Mode.global,
      groups: [
        selector('GLOBAL', [const Proxy(name: 'Route', type: 'Selector')]),
        selector('Route', [hongKongOne], hidden: true),
      ],
      selectedMap: const {},
    );

    expect(candidates.single.groupName, 'GLOBAL');
    expect(candidates.single.selections, {'GLOBAL': 'Route', 'Route': '香港 01'});
  });

  test('global mode does not fall back when GLOBAL is absent or empty', () {
    for (final groups in [
      [
        selector('Other', [hongKongOne]),
      ],
      [
        selector('GLOBAL', [otherNode]),
        selector('Other', [hongKongOne]),
      ],
    ]) {
      expect(
        hongKongCandidates(
          mode: Mode.global,
          groups: groups,
          selectedMap: const {},
        ),
        isEmpty,
      );
    }
  });

  test('direct mode never plans a selection', () {
    expect(
      hongKongCandidates(
        mode: Mode.direct,
        groups: [
          selector('GLOBAL', [hongKongOne]),
        ],
        selectedMap: const {'GLOBAL': '香港 01'},
      ),
      isEmpty,
    );
  });

  test('rule mode prefers the current visible selector', () {
    final candidates = hongKongCandidates(
      mode: Mode.rule,
      groups: [
        selector('First', [hongKongOne]),
        selector('Current', [hongKongTwo]),
      ],
      selectedMap: const {},
      currentGroupName: 'Current',
    );

    expect(candidates.single.nodeName, '香港 02');
    expect(candidates.single.groupName, 'Current');
  });

  test(
    'rule mode falls back to the first selector with a reachable HK leaf',
    () {
      final candidates = hongKongCandidates(
        mode: Mode.rule,
        groups: [
          selector('Empty', [otherNode]),
          selector('First', [hongKongOne]),
          selector('Last', [hongKongTwo]),
        ],
        selectedMap: const {},
        currentGroupName: 'Empty',
      );

      expect(candidates.single.groupName, 'First');
    },
  );

  test(
    'rule mode excludes hidden, unspecified visibility and GLOBAL roots',
    () {
      for (final currentGroupName in ['Hidden', 'Unspecified', 'GLOBAL']) {
        final candidates = hongKongCandidates(
          mode: Mode.rule,
          groups: [
            selector('Hidden', [hongKongOne], hidden: true),
            selector('Unspecified', [hongKongOne], hidden: null),
            selector('GLOBAL', [hongKongOne]),
            selector('Visible', [hongKongTwo]),
          ],
          selectedMap: const {},
          currentGroupName: currentGroupName,
        );

        expect(candidates.single.groupName, 'Visible');
      }
    },
  );

  test(
    'rule mode includes every nested selector edge including hidden groups',
    () {
      final candidates = hongKongCandidates(
        mode: Mode.rule,
        groups: [
          selector('Route', [const Proxy(name: 'Region', type: 'Selector')]),
          selector('Region', [
            const Proxy(name: '香港组', type: 'select'),
          ], hidden: true),
          selector('香港组', [hongKongOne, hongKongTwo], hidden: true),
        ],
        selectedMap: const {},
      );

      expect(candidates.map((candidate) => candidate.nodeName), [
        '香港 01',
        '香港 02',
      ]);
      expect(candidates.first.groupName, 'Route');
      expect(candidates.first.selections, {
        'Route': 'Region',
        'Region': '香港组',
        '香港组': '香港 01',
      });
    },
  );

  test('a Hong Kong group name does not make its non-HK leaf a candidate', () {
    expect(
      hongKongCandidates(
        mode: Mode.rule,
        groups: [
          selector('Route', [const Proxy(name: '香港组', type: 'ss')]),
          selector('香港组', [otherNode], hidden: true),
        ],
        selectedMap: const {},
      ),
      isEmpty,
    );
  });

  test(
    'HK aliases and an empty graph do not count as literal Hong Kong nodes',
    () {
      for (final groups in [
        <Group>[],
        [
          selector('Route', [
            const Proxy(name: 'HK 01', type: 'ss'),
            const Proxy(name: 'Hong Kong', type: 'ss'),
            otherNode,
          ]),
        ],
      ]) {
        expect(
          hongKongCandidates(
            mode: Mode.rule,
            groups: groups,
            selectedMap: const {},
          ),
          isEmpty,
        );
      }
    },
  );

  test('DIRECT, REJECT and pseudo-adapters never become candidates', () {
    final candidates = hongKongCandidates(
      mode: Mode.rule,
      groups: [
        selector('Route', [
          const Proxy(name: 'DIRECT', type: 'ss'),
          const Proxy(name: 'REJECT', type: 'ss'),
          for (final type in [
            'Direct',
            'DIRECT',
            'rEjEcT',
            'RejectDrop',
            'reject-drop',
            'Compatible',
            'Pass',
            'PassRule',
            'Rematch',
            'Dns',
            'Unknown',
            '',
          ])
            Proxy(name: '香港 $type', type: type),
          hongKongOne,
        ]),
      ],
      selectedMap: const {},
    );

    expect(candidates.map((candidate) => candidate.nodeName), ['香港 01']);
  });

  test('missing group definitions never turn group proxies into HK leaves', () {
    final candidates = hongKongCandidates(
      mode: Mode.rule,
      groups: [
        selector('Route', [
          for (final type in GroupType.values) ...[
            Proxy(name: '香港 ${type.name}', type: type.name),
            Proxy(name: '香港 ${type.value}', type: type.value.toUpperCase()),
          ],
        ]),
      ],
      selectedMap: const {},
    );

    expect(candidates, isEmpty);
  });

  for (final type in GroupType.values.where(
    (type) => type != GroupType.Selector,
  )) {
    test('does not traverse or modify a ${type.name} group', () {
      final candidates = hongKongCandidates(
        mode: Mode.rule,
        groups: [
          selector('Route', [
            Proxy(name: '香港 computed', type: type.name),
            hongKongTwo,
          ]),
          Group(
            name: '香港 computed',
            type: type,
            all: [hongKongOne],
            now: hongKongOne.name,
            hidden: true,
          ),
        ],
        selectedMap: const {'Route': '香港 computed'},
      );

      expect(candidates.single.nodeName, '香港 02');
      expect(candidates.single.selections, {'Route': '香港 02'});
    });

    test('does not use a ${type.name} group as a global or rule root', () {
      final computed = Group(
        name: 'GLOBAL',
        type: type,
        all: [hongKongOne],
        hidden: false,
      );
      expect(
        hongKongCandidates(
          mode: Mode.global,
          groups: [computed],
          selectedMap: const {},
        ),
        isEmpty,
      );
      final candidates = hongKongCandidates(
        mode: Mode.rule,
        groups: [
          computed.copyWith(name: 'Computed'),
          selector('Route', [hongKongTwo]),
        ],
        selectedMap: const {},
        currentGroupName: 'Computed',
      );

      expect(candidates.single.groupName, 'Route');
    });
  }

  test(
    'cycles terminate without hiding reachable leaves on other branches',
    () {
      final candidates = hongKongCandidates(
        mode: Mode.rule,
        groups: [
          selector('Route', [
            const Proxy(name: 'Route', type: 'Selector'),
            const Proxy(name: 'Nested', type: 'Selector'),
            hongKongTwo,
          ]),
          selector('Nested', [
            const Proxy(name: 'Route', type: 'Selector'),
            hongKongOne,
          ], hidden: true),
        ],
        selectedMap: const {'Route': 'Nested', 'Nested': 'Route'},
      );

      expect(candidates.map((candidate) => candidate.nodeName), [
        '香港 01',
        '香港 02',
      ]);
      expect(candidates.first.selections, {
        'Route': 'Nested',
        'Nested': '香港 01',
      });
    },
  );

  test('cycles with no leaf produce no candidates', () {
    expect(
      hongKongCandidates(
        mode: Mode.rule,
        groups: [
          selector('Route', [const Proxy(name: '香港组', type: 'Selector')]),
          selector('香港组', [
            const Proxy(name: 'Route', type: 'Selector'),
          ], hidden: true),
        ],
        selectedMap: const {},
      ),
      isEmpty,
    );
  });

  test(
    'current complete HK path is preferred without reordering alternatives',
    () {
      final candidates = hongKongCandidates(
        mode: Mode.rule,
        groups: [
          selector('Route', [
            hongKongOne,
            const Proxy(name: 'Nested', type: 'Selector'),
            const Proxy(name: '香港 03', type: 'ss'),
          ], now: hongKongOne.name),
          selector('Nested', [hongKongTwo], hidden: true),
        ],
        selectedMap: const {'Route': 'Nested', 'Nested': '香港 02'},
      );

      expect(candidates.map((candidate) => candidate.nodeName), [
        '香港 02',
        '香港 01',
        '香港 03',
      ]);
    },
  );

  test('current group now values are used when no saved selection exists', () {
    final candidates = hongKongCandidates(
      mode: Mode.rule,
      groups: [
        selector('Route', [hongKongOne, hongKongTwo], now: hongKongTwo.name),
      ],
      selectedMap: const {},
    );

    expect(candidates.first.nodeName, '香港 02');
  });

  test('a current HK leaf in an unselected branch is not prioritized', () {
    final candidates = hongKongCandidates(
      mode: Mode.rule,
      groups: [
        selector('Route', [
          hongKongOne,
          const Proxy(name: 'Nested', type: 'Selector'),
          otherNode,
        ], now: otherNode.name),
        selector('Nested', [hongKongTwo], now: hongKongTwo.name, hidden: true),
      ],
      selectedMap: const {},
    );

    expect(candidates.first.nodeName, '香港 01');
  });

  test('stale saved selection cannot invent a currently selected HK leaf', () {
    final candidates = hongKongCandidates(
      mode: Mode.rule,
      groups: [
        selector('Route', [hongKongOne, hongKongTwo]),
      ],
      selectedMap: const {'Route': '香港 missing'},
    );

    expect(candidates.map((candidate) => candidate.nodeName), [
      '香港 01',
      '香港 02',
    ]);
  });

  test(
    'duplicate leaves retain the current reachable path before deduplication',
    () {
      final candidates = hongKongCandidates(
        mode: Mode.rule,
        groups: [
          selector('Route', [
            const Proxy(name: 'First', type: 'Selector'),
            const Proxy(name: 'Current', type: 'Selector'),
          ]),
          selector('First', [hongKongOne], hidden: true),
          selector('Current', [hongKongOne], hidden: true),
        ],
        selectedMap: const {'Route': 'Current', 'Current': '香港 01'},
      );

      expect(candidates, hasLength(1));
      expect(candidates.single.selections, {
        'Route': 'Current',
        'Current': '香港 01',
      });
    },
  );

  test(
    'planning leaves inputs and unrelated split routing selections intact',
    () {
      final selectedMap = <String, String>{
        'Route': '日本 01',
        'Video': 'DIRECT',
        'Work': 'Company proxy',
      };
      final groups = [
        selector('Route', [hongKongOne, otherNode]),
        selector('Video', [hongKongTwo]),
      ];
      final candidates = hongKongCandidates(
        mode: Mode.rule,
        groups: groups,
        selectedMap: selectedMap,
        currentGroupName: 'Route',
      );

      expect(selectedMap, {
        'Route': '日本 01',
        'Video': 'DIRECT',
        'Work': 'Company proxy',
      });
      expect(groups.first.all, [hongKongOne, otherNode]);
      expect(candidates.single.selections, {'Route': '香港 01'});
      expect(
        {...selectedMap, ...candidates.single.selections},
        {'Route': '香港 01', 'Video': 'DIRECT', 'Work': 'Company proxy'},
      );
      expect(
        () => candidates.single.selections['Work'] = '香港 01',
        throwsUnsupportedError,
      );
    },
  );
}

import 'package:fl_clash/common/network_diagnostic_selection.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const groups = [
    Group(
      name: 'GLOBAL',
      type: GroupType.Selector,
      now: 'global-node',
      all: [Proxy(name: 'global-node', type: 'ss')],
    ),
    Group(
      name: 'hidden',
      type: GroupType.Selector,
      hidden: true,
      now: 'hidden-node',
      all: [Proxy(name: 'hidden-node', type: 'ss')],
    ),
    Group(
      name: 'Primary',
      type: GroupType.Selector,
      hidden: false,
      now: 'manual-node',
      all: [
        Proxy(name: 'manual-node', type: 'ss'),
        Proxy(name: 'Auto', type: 'URLTest'),
      ],
    ),
    Group(
      name: 'Auto',
      type: GroupType.URLTest,
      hidden: false,
      now: 'fast-node',
      all: [
        Proxy(name: 'fast-node', type: 'ss'),
        Proxy(name: 'slow-node', type: 'ss'),
      ],
    ),
  ];

  test('rule mode follows preferred visible group and current auto leaf', () {
    final selection = computeNetworkDiagnosticSelection(
      mode: Mode.rule,
      groups: groups,
      currentGroupName: 'Primary',
      selectedMap: {'Primary': 'Auto', 'Auto': 'slow-node'},
    );

    expect(selection.mode, Mode.rule);
    expect(selection.selectedGroup, 'Primary');
    expect(selection.selectedNode, 'fast-node');
  });

  test('rule mode falls back to first visible non-global group', () {
    for (final preferred in [null, 'missing', 'GLOBAL', 'hidden']) {
      final selection = computeNetworkDiagnosticSelection(
        mode: Mode.rule,
        groups: groups,
        currentGroupName: preferred,
        selectedMap: {},
      );

      expect(selection.selectedGroup, 'Primary');
      expect(selection.selectedNode, 'manual-node');
    }
  });

  test('global mode resolves GLOBAL regardless of current visible group', () {
    final selection = computeNetworkDiagnosticSelection(
      mode: Mode.global,
      groups: groups,
      currentGroupName: 'Primary',
      selectedMap: {'Primary': 'Auto'},
    );

    expect(selection.selectedGroup, 'GLOBAL');
    expect(selection.selectedNode, 'global-node');
  });

  test('direct mode identifies DIRECT without claiming a selected proxy', () {
    final selection = computeNetworkDiagnosticSelection(
      mode: Mode.direct,
      groups: groups,
      currentGroupName: 'Primary',
      selectedMap: {'Primary': 'Auto'},
    );

    expect(selection.selectedGroup, isNull);
    expect(selection.selectedNode, 'DIRECT');
  });

  test('empty groups or missing GLOBAL do not invent node names', () {
    for (final mode in [Mode.rule, Mode.global]) {
      final selection = computeNetworkDiagnosticSelection(
        mode: mode,
        groups: mode == Mode.rule ? [] : groups.skip(1).toList(),
        selectedMap: {},
      );

      expect(selection.selectedGroup, isNull);
      expect(selection.selectedNode, isNull);
    }
  });

  test('stale selected node is unknown rather than the old runtime node', () {
    final selection = computeNetworkDiagnosticSelection(
      mode: Mode.rule,
      groups: groups,
      selectedMap: {'Primary': 'removed-node'},
    );

    expect(selection.selectedGroup, 'Primary');
    expect(selection.selectedNode, isNull);
  });

  test('missing nested group and unresolved selection are unknown', () {
    for (final now in ['Missing group', null]) {
      final selection = computeNetworkDiagnosticSelection(
        mode: Mode.rule,
        groups: [
          Group(
            name: 'Primary',
            type: GroupType.Selector,
            hidden: false,
            now: now,
            all: const [Proxy(name: 'Missing group', type: 'url-test')],
          ),
        ],
        selectedMap: {},
      );

      expect(selection.selectedGroup, 'Primary');
      expect(selection.selectedNode, isNull);
    }
  });

  test('cyclic group selection terminates without claiming a leaf', () {
    final selection = computeNetworkDiagnosticSelection(
      mode: Mode.rule,
      groups: const [
        Group(
          name: 'Primary',
          type: GroupType.Selector,
          hidden: false,
          now: 'Nested',
          all: [Proxy(name: 'Nested', type: 'Selector')],
        ),
        Group(
          name: 'Nested',
          type: GroupType.Selector,
          now: 'Primary',
          all: [Proxy(name: 'Primary', type: 'Selector')],
        ),
      ],
      selectedMap: {},
    );

    expect(selection.selectedNode, isNull);
  });

  test('load balance and relay do not claim one actual selected node', () {
    for (final type in [GroupType.LoadBalance, GroupType.Relay]) {
      final selection = computeNetworkDiagnosticSelection(
        mode: Mode.rule,
        groups: [
          Group(
            name: 'Multi-node',
            type: type,
            hidden: false,
            now: 'some-node',
            all: const [Proxy(name: 'some-node', type: 'ss')],
          ),
        ],
        selectedMap: {},
      );

      expect(selection.selectedGroup, 'Multi-node');
      expect(selection.selectedNode, isNull);
    }
  });
}

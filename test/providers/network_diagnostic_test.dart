import 'package:fl_clash/common/diagnostic_log.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/l10n/l10n.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => AppLocalizations.load(const Locale('en')));

  test(
    'diagnostic provider snapshots raw auto selection and safe fields',
    () async {
      final container = ProviderContainer(
        overrides: [
          currentProfileProvider.overrideWithValue(
            const Profile(
              id: 1,
              autoUpdateDuration: Duration.zero,
              currentGroupName: 'Primary',
              selectedMap: {'Primary': 'Auto', 'Auto': 'old-node'},
            ),
          ),
        ],
      );
      addTearDown(container.dispose);
      container
          .read(patchClashConfigProvider.notifier)
          .update((config) => config.copyWith(mode: Mode.rule));
      container.read(groupsProvider.notifier).value = const [
        Group(
          name: 'Primary',
          hidden: false,
          type: GroupType.Selector,
          now: 'Auto',
          all: [Proxy(name: 'Auto', type: 'URLTest')],
        ),
        Group(
          name: 'Auto',
          hidden: false,
          type: GroupType.URLTest,
          now: 'live-node',
          all: [
            Proxy(name: 'old-node', type: 'ss'),
            Proxy(name: 'live-node', type: 'ss'),
          ],
        ),
      ];

      final report = await container
          .read(logsProvider.notifier)
          .runNetworkDiagnostics();

      expect(report.selectedNode, 'live-node');
      expect(report.selectedGroup, 'Primary');
      expect(report.mode, 'rule');
      expect(report.success, isFalse);
      final fields = report.toDiagnosticFields();
      expect(fields['selected_node_ref'], diagnosticFingerprint('live-node'));
      expect(fields['selected_group_ref'], diagnosticFingerprint('Primary'));
      expect(fields.toString(), isNot(contains('live-node')));
      expect(fields.toString(), isNot(contains('Primary')));
    },
  );

  test(
    'diagnostic provider preserves direct mode without a selected group',
    () async {
      final container = ProviderContainer(
        overrides: [currentProfileProvider.overrideWithValue(null)],
      );
      addTearDown(container.dispose);
      container
          .read(patchClashConfigProvider.notifier)
          .update((config) => config.copyWith(mode: Mode.direct));

      final report = await container
          .read(logsProvider.notifier)
          .runNetworkDiagnostics();

      expect(report.selectedNode, 'DIRECT');
      expect(report.selectedGroup, isNull);
      expect(report.mode, 'direct');
    },
  );
}

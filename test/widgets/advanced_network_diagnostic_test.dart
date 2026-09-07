import 'dart:async';

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/l10n/l10n.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/state.dart';
import 'package:fl_clash/views/settings/fengwo_advanced_settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const _runButtonKey = ValueKey('advanced-run-network-diagnostics');
const _resultKey = ValueKey('advanced-network-diagnostic-result');
const _selectionKey = ValueKey('advanced-network-diagnostic-selection');

void main() {
  testWidgets('diagnostic report retains tested node while preview changes', (
    tester,
  ) async {
    final pending = Completer<NetworkDiagnosticReport>();
    var runs = 0;
    final container = await _pumpSettings(
      tester,
      runner: () {
        runs++;
        return pending.future;
      },
    );
    expect(_selectionText(tester), contains('Node A'));

    await _tapDiagnostics(tester);
    expect(runs, 1);
    expect(
      tester.widget<FilledButton>(find.byKey(_runButtonKey)).onPressed,
      isNull,
    );
    await tester.tap(find.byKey(_runButtonKey));
    expect(runs, 1);

    container.read(groupsProvider.notifier).value = [_group('Node B')];
    await tester.pump();
    expect(_selectionText(tester), contains('Node B'));

    pending.complete(_report(tester));
    await tester.pumpAndSettle();
    final result = _resultText(tester);
    expect(result, contains('Node A'));
    expect(result, contains('Primary'));
    expect(result, contains('YouTube HTTPS'));
    expect(result, contains('123 ms'));
    expect(result, contains('W-NET-OK'));
    expect(result, isNot(contains('Node B')));
    expect(tester.takeException(), isNull);
  });

  testWidgets('failed YouTube check is visible and retry clears old result', (
    tester,
  ) async {
    final pending = Completer<NetworkDiagnosticReport>();
    var runs = 0;
    await _pumpSettings(
      tester,
      runner: () async {
        runs++;
        if (runs == 1) return _report(tester, success: false);
        return pending.future;
      },
    );

    await _tapDiagnostics(tester);
    await tester.pumpAndSettle();
    expect(_resultText(tester), contains('W-YOUTUBE-01'));
    expect(_resultText(tester), contains('timeout'));

    await _tapDiagnostics(tester);
    expect(find.byKey(_resultKey), findsNothing);
    pending.complete(_report(tester));
    await tester.pumpAndSettle();
    expect(_resultText(tester), contains('W-NET-OK'));
    expect(_resultText(tester), isNot(contains('W-YOUTUBE-01')));
    expect(runs, 2);
    expect(tester.takeException(), isNull);
  });

  testWidgets('throwing diagnostic runner restores button for retry', (
    tester,
  ) async {
    var runs = 0;
    await _pumpSettings(
      tester,
      runner: () async {
        if (++runs == 1) throw StateError('diagnostic unavailable');
        return _report(tester);
      },
    );

    await _tapDiagnostics(tester);
    await tester.pumpAndSettle();
    expect(find.byKey(_resultKey), findsNothing);
    expect(
      tester.widget<FilledButton>(find.byKey(_runButtonKey)).onPressed,
      isNotNull,
    );
    await _tapDiagnostics(tester);
    await tester.pumpAndSettle();
    expect(_resultText(tester), contains('123 ms'));
    expect(tester.takeException(), isNull);
  });

  testWidgets('pending diagnostic can complete after view disposal', (
    tester,
  ) async {
    final pending = Completer<NetworkDiagnosticReport>();
    await _pumpSettings(tester, runner: () => pending.future);
    final report = _report(tester);
    await _tapDiagnostics(tester);
    await tester.pumpWidget(const SizedBox.shrink());
    pending.complete(report);
    await tester.pump();

    expect(tester.takeException(), isNull);
  });

  testWidgets('node names and YouTube result wrap on a narrow screen', (
    tester,
  ) async {
    const node = 'Hong Kong Node with a very long selected node label 01';
    await _pumpSettings(
      tester,
      size: const Size(320, 844),
      node: node,
      runner: () async => _report(tester, node: node),
    );
    await _tapDiagnostics(tester);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(_resultKey));
    await tester.pumpAndSettle();

    expect(_resultText(tester), contains(node));
    expect(_resultText(tester), contains('123 ms'));
    expect(tester.takeException(), isNull);
  });
}

Future<ProviderContainer> _pumpSettings(
  WidgetTester tester, {
  required NetworkDiagnosticRunner runner,
  Size size = const Size(1280, 1000),
  String node = 'Node A',
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final container = ProviderContainer(
    overrides: [currentProfileProvider.overrideWithValue(null)],
  );
  addTearDown(container.dispose);
  globalState.container = container;
  container.read(viewSizeProvider.notifier).value = size;
  container.read(groupsProvider.notifier).value = [_group(node)];
  container
      .read(patchClashConfigProvider.notifier)
      .update((config) => config.copyWith(mode: Mode.rule));
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.delegate.supportedLocales,
        home: FengWoAdvancedSettingsView(networkDiagnosticRunner: runner),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

Group _group(String node) => Group(
  name: 'Primary',
  type: GroupType.Selector,
  hidden: false,
  now: node,
  all: [Proxy(name: node, type: 'ss')],
);

Future<void> _tapDiagnostics(WidgetTester tester) async {
  await tester.ensureVisible(find.byKey(_runButtonKey));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(_runButtonKey));
  await tester.pump();
}

NetworkDiagnosticReport _report(
  WidgetTester tester, {
  bool success = true,
  String node = 'Node A',
}) {
  final l10n = tester
      .element(find.byType(FengWoAdvancedSettingsView))
      .appLocalizations;
  return NetworkDiagnosticReport(
    code: success ? 'W-NET-OK' : 'W-YOUTUBE-01',
    summary: success ? 'YouTube reachable' : 'YouTube unavailable',
    selectedNode: node,
    selectedGroup: 'Primary',
    mode: 'rule',
    steps: [
      NetworkDiagnosticStep(
        name: l10n.networkDiagnosticYouTube,
        success: success,
        detail: success ? '123 ms' : 'timeout',
        latencyMs: success ? 123 : null,
      ),
    ],
  );
}

String _selectionText(WidgetTester tester) => tester
    .widget<Text>(
      find.descendant(
        of: find.byKey(_selectionKey),
        matching: find.byType(Text),
      ),
    )
    .data!;

String _resultText(WidgetTester tester) => tester
    .widget<SelectableText>(
      find.descendant(
        of: find.byKey(_resultKey),
        matching: find.byType(SelectableText),
      ),
    )
    .data!;

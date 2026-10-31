import 'dart:async';

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/common/theme.dart';
import 'package:fl_clash/core/controller.dart';
import 'package:fl_clash/core/interface.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/l10n/l10n.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/state.dart';
import 'package:fl_clash/views/dashboard/fengwo_node_selector.dart';
import 'package:fl_clash/views/proxies/common.dart';
import 'package:fl_clash/views/proxies/fengwo_node_status.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    globalState.clearXboardSession();
    globalState.setOfflineMode(false);
    SharedPreferences.setMockInitialValues({});
  });

  tearDown(() {
    globalState.clearXboardSession();
    globalState.setOfflineMode(false);
    CoreController.resetInstance();
  });

  final allowedCases =
      <({String name, List<XboardNodeData> nodes, bool fresh})>[
        (name: 'missing raw status', nodes: [_node()], fresh: true),
        (
          name: 'invalid raw status',
          nodes: [_node(raw: 'invalid')],
          fresh: true,
        ),
        (name: 'stale explicit offline', nodes: [_node(raw: 0)], fresh: false),
        (
          name: 'string online with false legacy bool',
          nodes: [_node(raw: 'true')],
          fresh: true,
        ),
        (
          name: 'explicit online with false legacy bool',
          nodes: [_node(raw: 1)],
          fresh: true,
        ),
        (
          name: 'duplicate exact names',
          nodes: [_node(raw: 0), _node(raw: 1)],
          fresh: true,
        ),
        (
          name: 'normalized name collision',
          nodes: [
            _node(name: 'Node-A', raw: 0),
            _node(name: 'Node_A', raw: 1),
          ],
          fresh: true,
        ),
      ];

  for (final surface in ['node status', 'selector']) {
    for (final sample in allowedCases) {
      testWidgets('$surface really probes ${sample.name}', (tester) async {
        final harness = await _Harness.pump(
          tester,
          surface: surface,
          nodes: sample.nodes,
          fresh: sample.fresh,
        );
        await _expectRealProbe(tester, harness, surface);
      });
    }

    for (final raw in <Object>[false, 0, '0', 'false']) {
      testWidgets('$surface blocks fresh explicit offline $raw', (
        tester,
      ) async {
        final harness = await _Harness.pump(
          tester,
          surface: surface,
          nodes: [_node(raw: raw, legacyOnline: true)],
          fresh: true,
        );
        if (surface == 'selector') {
          expect(
            tester.widget<OutlinedButton>(_probeButton(surface)).onPressed,
            isNull,
          );
          await proxyDelayTest(const Proxy(name: 'Node A', type: 'trojan'));
        } else {
          await tester.tap(_probeButton(surface));
        }
        await tester.pump();
        verifyNever(() => harness.core.asyncTestDelay(any(), any()));
        expect(harness.container.read(delayProvider(proxyName: 'Node A')), -1);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('$surface probes a real restored offline cache', (
      tester,
    ) async {
      final storage = XboardSessionStorage();
      await storage.saveOfflineCache(
        session: _session(),
        nodes: [_node(raw: 0)],
      );
      final cache = (await storage.loadOfflineCache())!;
      expect(cache.nodes.single.isOnline, isFalse);
      expect(cache.nodes.single.rawData, isEmpty);
      final harness = await _Harness.pump(
        tester,
        surface: surface,
        nodes: cache.nodes,
        fresh: false,
      );
      await _expectRealProbe(tester, harness, surface);
    });
  }

  testWidgets(
    'selector notices freshness changes and batch probes stale offline nodes',
    (tester) async {
      final harness = await _Harness.pump(
        tester,
        surface: 'selector',
        nodes: [_node(raw: 0)],
        fresh: true,
      );
      expect(
        tester.widget<OutlinedButton>(_probeButton('selector')).onPressed,
        isNull,
      );
      final session = globalState.xboardSession!;
      globalState.markXboardNodesStaleForSession(
        session,
        globalState.xboardSessionRevision,
      );
      await tester.pump();
      expect(
        tester.widget<OutlinedButton>(_probeButton('selector')).onPressed,
        isNotNull,
      );
      final all = find.widgetWithText(
        FilledButton,
        currentAppLocalizations.delayTest,
      );
      expect(tester.widget<FilledButton>(all).onPressed, isNotNull);
      await tester.tap(all);
      await tester.pump();
      verify(
        () => harness.core.asyncTestDelay(defaultTestUrl, 'Node A'),
      ).called(1);
      expect(harness.container.read(delayProvider(proxyName: 'Node A')), 0);
      harness.complete(180);
      await tester.pump();
      expect(harness.container.read(delayProvider(proxyName: 'Node A')), 180);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('manual probe blocks a fresh offline leaf behind a group alias', (
    tester,
  ) async {
    final harness = await _Harness.pump(
      tester,
      surface: 'selector',
      nodes: [_node(raw: 0)],
      fresh: true,
    );
    harness.container.read(groupsProvider.notifier).value = const [
      Group(
        name: 'Automatic',
        type: GroupType.URLTest,
        now: 'Node A',
        all: [Proxy(name: 'Node A', type: 'trojan')],
      ),
    ];
    await proxyDelayTest(const Proxy(name: 'Automatic', type: 'url-test'));
    verifyNever(() => harness.core.asyncTestDelay(any(), any()));
    expect(harness.container.read(delayProvider(proxyName: 'Node A')), -1);
  });
}

Future<void> _expectRealProbe(
  WidgetTester tester,
  _Harness harness,
  String surface,
) async {
  await tester.tap(_probeButton(surface));
  await tester.pump();
  verify(() => harness.core.asyncTestDelay(defaultTestUrl, 'Node A')).called(1);
  expect(harness.container.read(delayProvider(proxyName: 'Node A')), 0);
  final button = _probeButton(surface);
  if (surface == 'selector') {
    expect(tester.widget<OutlinedButton>(button).onPressed, isNull);
  } else {
    expect(tester.widget<IconButton>(button).onPressed, isNull);
  }
  expect(
    find.descendant(
      of: button,
      matching: find.byType(CircularProgressIndicator),
    ),
    findsOneWidget,
  );
  harness.complete(180);
  await tester.pump();
  expect(harness.container.read(delayProvider(proxyName: 'Node A')), 180);
  expect(
    find.descendant(
      of: button,
      matching: find.byType(CircularProgressIndicator),
    ),
    findsNothing,
  );
  expect(tester.takeException(), isNull);
}

Finder _probeButton(String surface) => surface == 'selector'
    ? find.byKey(const ValueKey('fengwo-selector-test-Node A'))
    : find.descendant(
        of: find.byKey(const ValueKey('fengwo-node-row-Node A')),
        matching: find.byType(IconButton),
      );

XboardNodeData _node({
  String name = 'Node A',
  Object? raw,
  bool legacyOnline = false,
}) => XboardNodeData(
  name: name,
  type: 'trojan',
  rate: 1,
  tags: const [],
  isOnline: legacyOnline,
  rawData: {'is_online': ?raw},
);

XboardLoginResult _session() {
  final endpoint = Uri.parse('https://api.example.com');
  return XboardLoginResult(
    endpoint: endpoint,
    token: 'fixture-token',
    authData: 'fixture-auth',
    isAdmin: false,
    subscription: XboardSubscriptionData(
      endpoint: endpoint,
      subscribeUrl: Uri.parse('https://api.example.com/subscribe'),
      uploadBytes: 0,
      downloadBytes: 0,
      transferEnableBytes: 1,
      rawData: const {},
    ),
  );
}

class _MockCore extends Mock implements CoreHandlerInterface {}

class _Proxies extends ProxiesAction {
  _Proxies(this.controller);
  final CoreController controller;
  @override
  CoreController get proxyController => controller;
}

class _Harness {
  _Harness(this.core, this.container, this.pending);
  final _MockCore core;
  final ProviderContainer container;
  final Completer<Delay> pending;

  void complete(int value) => pending.complete(
    Delay(url: defaultTestUrl, name: 'Node A', value: value),
  );

  static Future<_Harness> pump(
    WidgetTester tester, {
    required String surface,
    required List<XboardNodeData> nodes,
    required bool fresh,
  }) async {
    tester.view.physicalSize = const Size(1100, 760);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    const group = Group(
      name: 'Test group',
      type: GroupType.Selector,
      now: 'Node A',
      all: [Proxy(name: 'Node A', type: 'trojan')],
    );
    final core = _MockCore();
    final pending = Completer<Delay>();
    when(
      () => core.asyncTestDelay(any(), any()),
    ).thenAnswer((_) => pending.future);
    final container = ProviderContainer(
      overrides: [
        groupsProvider.overrideWithBuild((_, _) => [group]),
        currentGroupsStateProvider.overrideWithValue(
          const GroupsState(value: [group]),
        ),
        currentProfileProvider.overrideWithValue(
          const Profile(
            id: 1,
            autoUpdateDuration: Duration.zero,
            currentGroupName: 'Test group',
            selectedMap: {'Test group': 'Node A'},
          ),
        ),
        isStartProvider.overrideWithValue(false),
        proxiesActionProvider.overrideWith(
          () => _Proxies(CoreController.test(core)),
        ),
      ],
    );
    addTearDown(container.dispose);
    globalState.container = container;
    globalState.activateXboardSession(
      _session(),
      nodes: nodes,
      nodesStatusFresh: fresh,
    );
    container
        .read(proxiesActionProvider.notifier)
        .setDelay(const Delay(url: defaultTestUrl, name: 'Node A', value: -1));
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: _App(
          child: surface == 'selector'
              ? const FengWoNodeSelectorView()
              : FengWoNodeStatusView(
                  nodesLoader: (_, _) async => globalState.xboardNodes,
                ),
        ),
      ),
    );
    await tester.pump();
    return _Harness(core, container, pending);
  }
}

class _App extends StatelessWidget {
  const _App({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => MaterialApp(
    navigatorKey: globalState.navigatorKey,
    locale: const Locale('en'),
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
    ],
    supportedLocales: AppLocalizations.delegate.supportedLocales,
    builder: (context, child) {
      globalState.measure = Measure.of(context, 1);
      globalState.theme = CommonTheme.of(context, 1);
      return child!;
    },
    home: Scaffold(body: child),
  );
}

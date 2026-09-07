import 'dart:async';

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/common/theme.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/l10n/l10n.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/state.dart';
import 'package:fl_clash/views/dashboard/fengwo_desktop_dashboard.dart';
import 'package:fl_clash/views/dashboard/fengwo_node_selector.dart';
import 'package:fl_clash/views/proxies/card.dart';
import 'package:fl_clash/views/proxies/fengwo_node_status.dart';
import 'package:fl_clash/widgets/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(() {
    globalState.clearXboardSession();
    globalState.setOfflineMode(false);
    globalState.xboardNodes = const [];
  });

  tearDown(() {
    globalState.clearXboardSession();
    globalState.setOfflineMode(false);
  });

  Future<ProviderContainer> pumpView(
    WidgetTester tester, {
    required Widget child,
    required Map<String, int?> delays,
    Size size = const Size(1100, 760),
    Locale locale = const Locale('en'),
    List<XboardNodeData> backendNodes = const [],
    List<Group> additionalGroups = const [],
    bool offlineMode = false,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final group = Group(
      name: 'Reference test group',
      type: GroupType.Selector,
      now: delays.keys.first,
      all: delays.keys.map((name) => Proxy(name: name, type: 'ss')).toList(),
    );
    final profile = Profile(
      id: 1,
      autoUpdateDuration: Duration.zero,
      currentGroupName: group.name,
      selectedMap: {group.name: delays.keys.first},
    );
    final container = ProviderContainer(
      overrides: [
        groupsProvider.overrideWithValue([group, ...additionalGroups]),
        currentGroupsStateProvider.overrideWithValue(
          GroupsState(value: [group]),
        ),
        currentProfileProvider.overrideWithValue(profile),
        isStartProvider.overrideWithValue(false),
        for (final entry in delays.entries)
          delayProvider(proxyName: entry.key).overrideWithValue(entry.value),
      ],
    );
    addTearDown(container.dispose);
    globalState.container = container;
    globalState.xboardNodes = backendNodes;
    globalState.setOfflineMode(offlineMode);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: _TestApp(locale: locale, child: child),
      ),
    );
    await tester.pump();
    return container;
  }

  for (final type in ProxyCardType.values) {
    for (final measured in <int>[80, 100, 101, 150, 151, 350, 500]) {
      testWidgets('proxy card $type displays raw delay $measured once', (
        tester,
      ) async {
        final container = await pumpView(
          tester,
          delays: {'Node A': measured},
          child: Center(
            child: SizedBox(
              width: 300,
              height: 140,
              child: ProxyCard(
                groupName: 'Reference test group',
                testUrl: null,
                proxy: const Proxy(name: 'Node A', type: 'ss'),
                groupType: GroupType.Selector,
                type: type,
              ),
            ),
          ),
        );
        final l10n = tester.element(find.byType(ProxyCard)).appLocalizations;
        final expected = l10n.referenceDelayValue(measured);
        expect(find.text(expected), findsOneWidget);
        expect(
          tester.widget<Text>(find.text(expected)).style?.color,
          utils.getDelayColor(measured),
        );
        expect(container.read(delayProvider(proxyName: 'Node A')), measured);
        expect(tester.takeException(), isNull);
      });
    }
  }

  for (final measured in <int?>[null, 0, -1]) {
    testWidgets('proxy card preserves nonmeasurement state $measured', (
      tester,
    ) async {
      final container = await pumpView(
        tester,
        delays: {'Node A': measured},
        child: const Center(
          child: SizedBox(
            width: 300,
            height: 140,
            child: ProxyCard(
              groupName: 'Reference test group',
              testUrl: null,
              proxy: Proxy(name: 'Node A', type: 'ss'),
              groupType: GroupType.Selector,
              type: ProxyCardType.expand,
            ),
          ),
        ),
      );

      expect(find.textContaining(' ms'), findsNothing);
      switch (measured) {
        case null:
          expect(find.byIcon(Icons.bolt), findsOneWidget);
        case 0:
          expect(find.byType(CommonCircleLoading), findsOneWidget);
        default:
          expect(find.text(currentAppLocalizations.timeout), findsOneWidget);
      }
      expect(container.read(delayProvider(proxyName: 'Node A')), measured);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('selector displays raw delays and orders by measured values', (
    tester,
  ) async {
    final container = await pumpView(
      tester,
      delays: {'Node 140': 140, 'Node 120': 120, 'Node 500': 500},
      child: const FengWoNodeSelectorView(),
    );
    final l10n = tester
        .element(find.byType(FengWoNodeSelectorView))
        .appLocalizations;
    expect(find.text(l10n.referenceDelayValue(140)), findsOneWidget);
    expect(find.text(l10n.referenceDelayValue(120)), findsOneWidget);
    expect(find.text(l10n.referenceDelayValue(500)), findsOneWidget);

    await tester.tap(find.byIcon(Icons.sort_rounded));
    await tester.pumpAndSettle();
    await tester.tap(find.text('${l10n.delay} ↑'));
    await tester.pumpAndSettle();

    Finder button(String name) =>
        find.byKey(ValueKey('fengwo-selector-test-$name'));
    expect(
      tester.getTopLeft(button('Node 120')).dy,
      lessThan(tester.getTopLeft(button('Node 140')).dy),
    );
    expect(
      tester.getTopLeft(button('Node 140')).dy,
      lessThan(tester.getTopLeft(button('Node 500')).dy),
    );
    expect(container.read(delayProvider(proxyName: 'Node 140')), 140);
    expect(container.read(delayProvider(proxyName: 'Node 120')), 120);
    expect(tester.takeException(), isNull);
  });

  for (final width in [390.0, 1100.0]) {
    testWidgets('node status references values and keeps raw map data $width', (
      tester,
    ) async {
      await pumpView(
        tester,
        size: Size(width, 1000),
        locale: width < 640 ? const Locale('zh', 'CN') : const Locale('en'),
        delays: {'Japan 350': 350, 'Singapore 80': 80},
        child: const FengWoNodeStatusView(),
      );
      final l10n = tester
          .element(find.byType(FengWoNodeStatusView))
          .appLocalizations;
      expect(find.text(l10n.referenceDelayValue(350)), findsWidgets);
      expect(find.text(l10n.referenceDelayValue(80)), findsWidgets);
      expect(find.byTooltip(l10n.referenceDelayValue(350)), findsOneWidget);
      final map = tester.widget<FengWoWorldMap>(find.byType(FengWoWorldMap));
      expect(map.nodes.first.delay, 350);
      expect(map.nodes.last.delay, 80);
      expect(tester.takeException(), isNull);
    });
  }

  for (final sample
      in <(String, List<XboardNodeData>, bool, XboardNodeDisplayStatus)>[
        ('online', [_backendNode(true)], false, XboardNodeDisplayStatus.online),
        (
          'offline',
          [_backendNode(false)],
          false,
          XboardNodeDisplayStatus.offline,
        ),
        ('absent', [], false, XboardNodeDisplayStatus.unknown),
        (
          'missing field',
          [_backendNode(null)],
          false,
          XboardNodeDisplayStatus.unknown,
        ),
        (
          'malformed field',
          [_backendNode('invalid')],
          false,
          XboardNodeDisplayStatus.unknown,
        ),
        (
          'ambiguous',
          [_backendNode(true), _backendNode(false)],
          false,
          XboardNodeDisplayStatus.unknown,
        ),
        (
          'offline cache',
          [_backendNode(true)],
          true,
          XboardNodeDisplayStatus.unknown,
        ),
      ]) {
    for (final surface in ['card', 'selector', 'node status']) {
      testWidgets('$surface failed delay ignores ${sample.$1} backend status', (
        tester,
      ) async {
        final child = switch (surface) {
          'card' => const Center(
            child: SizedBox(
              width: 300,
              height: 140,
              child: ProxyCard(
                groupName: 'Reference test group',
                testUrl: null,
                proxy: Proxy(name: 'Node A', type: 'ss'),
                groupType: GroupType.Selector,
                type: ProxyCardType.expand,
              ),
            ),
          ),
          'selector' => const FengWoNodeSelectorView(),
          _ => const FengWoNodeStatusView(),
        };
        final container = await pumpView(
          tester,
          delays: {'Node A': -1},
          backendNodes: sample.$2,
          offlineMode: sample.$3,
          child: child,
        );

        expect(find.text(currentAppLocalizations.timeout), findsWidgets);
        expect(
          find.text(formatXboardNodeDisplayStatus(sample.$4)),
          findsNothing,
        );
        expect(
          find.text(currentAppLocalizations.nodeLocallyUnreachable),
          findsNothing,
        );
        expect(find.textContaining(' ms'), findsNothing);
        expect(container.read(delayProvider(proxyName: 'Node A')), -1);
        if (surface == 'node status') {
          final map = tester.widget<FengWoWorldMap>(
            find.byType(FengWoWorldMap),
          );
          expect(map.nodes.single.delay, -1);
          expect(map.nodes.single.backendStatus, sample.$4);
          expect(
            find.text(currentAppLocalizations.nodeAvailable),
            findsNothing,
          );
          final testButton = tester.widget<IconButton>(
            find.descendant(
              of: find.byKey(const ValueKey('fengwo-node-row-Node A')),
              matching: find.byType(IconButton),
            ),
          );
          expect(testButton.onPressed == null, isFalse);
        }
        expect(tester.takeException(), isNull);
      });
    }
  }

  for (final surface in ['card', 'selector']) {
    testWidgets('$surface keeps failed group delay as timeout', (tester) async {
      await pumpView(
        tester,
        delays: {'Automatic': -1},
        backendNodes: [_backendNode(true)],
        additionalGroups: const [
          Group(
            name: 'Automatic',
            type: GroupType.URLTest,
            now: 'Node A',
            all: [Proxy(name: 'Node A', type: 'ss')],
          ),
        ],
        child: surface == 'card'
            ? const Center(
                child: SizedBox(
                  width: 300,
                  height: 140,
                  child: ProxyCard(
                    groupName: 'Reference test group',
                    testUrl: null,
                    proxy: Proxy(name: 'Automatic', type: 'url-test'),
                    groupType: GroupType.Selector,
                    type: ProxyCardType.expand,
                  ),
                ),
              )
            : const FengWoNodeSelectorView(),
      );
      expect(find.text(currentAppLocalizations.timeout), findsWidgets);
      expect(
        find.text(currentAppLocalizations.nodeBackendOnline),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
    });
  }

  for (final fails in [false, true]) {
    testWidgets(
      'node status discards old session ${fails ? 'failure' : 'success'}',
      (tester) async {
        final request = Completer<XboardLoginResponse>();
        globalState.activateXboardSession(_session('old'));
        await pumpView(
          tester,
          delays: {'Node A': -1},
          child: FengWoNodeStatusView(
            authService: XboardAuthService(
              nodesRequester: (_, _) => request.future,
            ),
          ),
        );
        final newNode = _backendNode(true, name: 'New account node');
        final newSession = _session('new');
        globalState.activateXboardSession(newSession, nodes: [newNode]);
        if (fails) {
          request.completeError(StateError('old request failed'));
        } else {
          request.complete(
            const XboardLoginResponse(
              statusCode: 200,
              data: {
                'data': [
                  {'name': 'Old account node', 'is_online': false},
                ],
              },
            ),
          );
        }
        await tester.pump();
        await tester.pump();

        expect(globalState.xboardSession, same(newSession));
        expect(globalState.xboardNodes, [newNode]);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('node status clears failed fresh backend cache', (tester) async {
    final request = Completer<XboardLoginResponse>();
    globalState.activateXboardSession(_session('active'));
    await pumpView(
      tester,
      delays: {'Node A': null},
      backendNodes: [_backendNode(true)],
      child: FengWoNodeStatusView(
        authService: XboardAuthService(
          nodesRequester: (_, _) => request.future,
        ),
      ),
    );
    expect(find.text(currentAppLocalizations.nodeBackendOnline), findsWidgets);
    request.completeError(StateError('current request failed'));
    await tester.pump();
    await tester.pump();

    expect(globalState.xboardNodes, isEmpty);
    expect(find.text(currentAppLocalizations.nodeStatusUnknown), findsWidgets);
    expect(find.text(currentAppLocalizations.nodeBackendOnline), findsNothing);
    expect(tester.takeException(), isNull);
  });
}

XboardNodeData _backendNode(Object? status, {String name = 'Node A'}) {
  return XboardNodeData(
    name: name,
    type: 'ss',
    rate: 1,
    tags: const [],
    isOnline: status == true,
    rawData: {'is_online': ?status},
  );
}

XboardLoginResult _session(String token) {
  final endpoint = Uri.parse('https://api.example.com');
  return XboardLoginResult(
    endpoint: endpoint,
    token: token,
    authData: token,
    isAdmin: false,
    subscription: XboardSubscriptionData(
      endpoint: endpoint,
      subscribeUrl: Uri.parse('https://api.example.com/subscribe/$token'),
      uploadBytes: 0,
      downloadBytes: 0,
      transferEnableBytes: 0,
      rawData: const {},
    ),
  );
}

class _TestApp extends StatelessWidget {
  final Widget child;
  final Locale locale;

  const _TestApp({required this.child, required this.locale});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: globalState.navigatorKey,
      locale: locale,
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
}

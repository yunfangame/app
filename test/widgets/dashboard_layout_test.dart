import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/common/theme.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/l10n/l10n.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/state.dart';
import 'package:fl_clash/views/dashboard/dashboard.dart';
import 'package:fl_clash/views/dashboard/fengwo_desktop_dashboard.dart';
import 'package:fl_clash/views/dashboard/fengwo_mobile_dashboard.dart';
import 'package:fl_clash/views/dashboard/fengwo_node_selector.dart';
import 'package:fl_clash/views/proxies/fengwo_node_status.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('dashboard chooses the desktop layout for a wide viewport', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final container = ProviderContainer(
      overrides: [
        dashboardStateProvider.overrideWithValue(
          const DashboardState(dashboardWidgets: []),
        ),
        viewSizeProvider.overrideWithBuild((_, _) => const Size(1600, 1000)),
      ],
    );
    addTearDown(container.dispose);
    globalState.container = container;

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const _TestApp(child: DashboardView()),
      ),
    );
    await tester.pump();

    expect(find.byType(FengWoDesktopDashboard), findsOneWidget);
    expect(find.byType(FengWoMobileDashboard), findsNothing);
    expect(tester.takeException(), null);
  });

  testWidgets('desktop traffic card fits the minimum-height macOS layout', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(864, 677);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final container = ProviderContainer(
      overrides: [
        profilesProvider.overrideWithValue([
          const Profile(id: 1, autoUpdateDuration: Duration.zero),
        ]),
      ],
    );
    addTearDown(container.dispose);
    addTearDown(globalState.clearXboardSession);
    globalState.container = container;
    globalState.xboardSession = _testTrafficSession();

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const _TestApp(
          platform: TargetPlatform.macOS,
          child: FengWoDesktopDashboard(),
        ),
      ),
    );
    await tester.pump();

    expect(
      find.byKey(const ValueKey('fengwo-desktop-traffic-details')),
      findsOneWidget,
    );
    expect(tester.takeException(), null);
  });

  testWidgets('desktop dashboard uses the shared running state', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final container = ProviderContainer(
      overrides: [
        dashboardStateProvider.overrideWithValue(
          const DashboardState(dashboardWidgets: []),
        ),
        viewSizeProvider.overrideWithBuild((_, _) => const Size(1440, 900)),
        initProvider.overrideWithBuild((_, _) => true),
        profilesProvider.overrideWithValue([
          const Profile(id: 1, autoUpdateDuration: Duration.zero),
        ]),
        setupActionProvider.overrideWith(_RecordingSetupAction.new),
      ],
    );
    addTearDown(container.dispose);
    globalState.container = container;

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const _TestApp(child: DashboardView()),
      ),
    );
    await tester.pump();

    expect(find.byType(FengWoDesktopDashboard), findsOneWidget);
    expect(find.byKey(const ValueKey('fengwo-power-button')), findsOneWidget);

    final action =
        container.read(setupActionProvider.notifier) as _RecordingSetupAction;
    await tester.tap(find.byKey(const ValueKey('fengwo-power-button')));
    await tester.pump();

    expect(action.requests, [true]);
    expect(container.read(isStartProvider), isTrue);
    expect(tester.takeException(), null);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const _TestApp(
          themeMode: ThemeMode.dark,
          child: DashboardView(),
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(FengWoDesktopDashboard), findsOneWidget);
    expect(find.byKey(const ValueKey('fengwo-power-button')), findsOneWidget);
    expect(tester.takeException(), null);
  });

  testWidgets(
    'desktop global mode asks for confirmation and starts with DIRECT',
    (tester) async {
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      const profile = Profile(
        id: 1,
        autoUpdateDuration: Duration.zero,
        selectedMap: {'GLOBAL': '旧节点'},
      );
      final container = ProviderContainer(
        overrides: [
          dashboardStateProvider.overrideWithValue(
            const DashboardState(dashboardWidgets: []),
          ),
          viewSizeProvider.overrideWithBuild((_, _) => const Size(1440, 900)),
          initProvider.overrideWithBuild((_, _) => true),
          profilesProvider.overrideWith(() => _TestProfiles([profile])),
          currentProfileIdProvider.overrideWithBuild((_, _) => profile.id),
          patchClashConfigProvider.overrideWithBuild(
            (_, _) => const PatchClashConfig(mode: Mode.rule),
          ),
          setupActionProvider.overrideWith(_RecordingSetupAction.new),
        ],
      );
      addTearDown(container.dispose);
      globalState.container = container;

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const _TestApp(child: DashboardView()),
        ),
      );
      await tester.pump();

      final globalMode = find.byKey(
        const ValueKey('fengwo-desktop-global-mode'),
      );
      await tester.tap(globalMode);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(
        find.byKey(const ValueKey('global-mode-confirmation-dialog')),
        findsOneWidget,
      );
      expect(container.read(patchClashConfigProvider).mode, Mode.rule);

      await tester.tap(
        find.byKey(const ValueKey('global-mode-dont-show-checkbox')),
      );
      await tester.pump();
      expect(
        tester
            .widget<Checkbox>(
              find.byKey(const ValueKey('global-mode-dont-show-checkbox')),
            )
            .value,
        isTrue,
      );
      await tester.tap(find.byKey(const ValueKey('global-mode-confirm')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(container.read(patchClashConfigProvider).mode, Mode.global);
      expect(
        container.read(appSettingProvider).skipGlobalModeConfirmation,
        isTrue,
      );
      expect(
        container.read(profilesProvider).single.selectedMap['GLOBAL'],
        'DIRECT',
      );

      container
          .read(patchClashConfigProvider.notifier)
          .update((state) => state.copyWith(mode: Mode.rule));
      await tester.pump();
      await tester.tap(globalMode);
      await tester.pump();

      expect(
        find.byKey(const ValueKey('global-mode-confirmation-dialog')),
        findsNothing,
      );
      expect(container.read(patchClashConfigProvider).mode, Mode.global);
      expect(tester.takeException(), null);
    },
  );

  testWidgets('mobile global mode dialog adapts to a narrow dark viewport', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final container = ProviderContainer(
      overrides: [
        dashboardStateProvider.overrideWithValue(
          const DashboardState(dashboardWidgets: []),
        ),
        viewSizeProvider.overrideWithBuild((_, _) => const Size(390, 844)),
        patchClashConfigProvider.overrideWithBuild(
          (_, _) => const PatchClashConfig(mode: Mode.rule),
        ),
      ],
    );
    addTearDown(container.dispose);
    globalState.container = container;

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const _TestApp(
          themeMode: ThemeMode.dark,
          platform: TargetPlatform.android,
          child: DashboardView(),
        ),
      ),
    );
    await tester.pump();

    final globalMode = find.byKey(const ValueKey('fengwo-mobile-global-mode'));
    await tester.ensureVisible(globalMode);
    await tester.tap(globalMode);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(
      find.byKey(const ValueKey('global-mode-confirmation-dialog')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('global-mode-confirm')), findsOneWidget);
    expect(find.byKey(const ValueKey('global-mode-cancel')), findsOneWidget);
    expect(tester.takeException(), null);

    await tester.tap(find.byKey(const ValueKey('global-mode-cancel')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(container.read(patchClashConfigProvider).mode, Mode.rule);
  });

  testWidgets('mobile dashboard uses real node state without overflowing', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(393, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    const nodeName = '新加坡专线节点';
    const profile = Profile(
      id: 1,
      autoUpdateDuration: Duration.zero,
      currentGroupName: '自动选择',
      selectedMap: {'自动选择': nodeName},
    );
    const group = Group(
      name: '自动选择',
      type: GroupType.Selector,
      hidden: false,
      now: nodeName,
      testUrl: 'https://node-test.example/generate_204',
      all: [
        Proxy(name: nodeName, type: 'ss'),
        Proxy(name: '新加坡备用节点', type: 'hysteria2'),
      ],
    );
    final container = ProviderContainer(
      overrides: [
        viewSizeProvider.overrideWithBuild((_, _) => const Size(393, 800)),
        initProvider.overrideWithBuild((_, _) => true),
        profilesProvider.overrideWithValue([profile]),
        groupsProvider.overrideWithValue([group]),
        currentProfileProvider.overrideWithValue(profile),
        delayProvider(
          proxyName: nodeName,
          testUrl: group.testUrl,
        ).overrideWithValue(128),
        setupActionProvider.overrideWith(_RecordingSetupAction.new),
      ],
    );
    addTearDown(container.dispose);
    addTearDown(globalState.clearXboardSession);
    globalState.container = container;
    globalState.xboardSession = _testTrafficSession();

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const _TestApp(child: DashboardView()),
      ),
    );
    await tester.pump();

    expect(find.byType(FengWoMobileDashboard), findsOneWidget);
    expect(find.byType(FengWoDesktopDashboard), findsNothing);
    final mobileMap = find.byKey(const ValueKey('fengwo-mobile-world-map'));
    expect(
      find.descendant(
        of: mobileMap,
        matching: find.byKey(const ValueKey('fengwo-flutter-map')),
      ),
      findsOneWidget,
    );
    final l10n = tester
        .element(find.byType(FengWoMobileDashboard))
        .appLocalizations;
    expect(find.text(nodeName), findsWidgets);
    expect(find.text('128 ms'), findsOneWidget);
    final trafficDetails = find.byKey(
      const ValueKey('fengwo-mobile-traffic-details'),
    );
    expect(trafficDetails, findsOneWidget);
    expect(
      find.descendant(
        of: trafficDetails,
        matching: find.text(l10n.usedTrafficLabel),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(of: trafficDetails, matching: find.text('658 GB')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: trafficDetails, matching: find.text('1342 GB')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: trafficDetails, matching: find.text('2000 GB')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('fengwo-mobile-dashboard-scroll')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('fengwo-mobile-language')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('subscription-status-indicator')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('fengwo-mobile-theme')), findsOneWidget);
    expect(find.byKey(const ValueKey('fengwo-mobile-support')), findsOneWidget);

    final action =
        container.read(setupActionProvider.notifier) as _RecordingSetupAction;
    await tester.tap(find.byKey(const ValueKey('fengwo-mobile-power-button')));
    await tester.pump();

    expect(action.requests, [true]);

    final switchNode = find.byKey(const ValueKey('fengwo-mobile-switch-node'));
    await tester.ensureVisible(switchNode);
    await tester.tap(switchNode);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byType(FengWoNodeSelectorView), findsOneWidget);
    expect(
      tester.getSize(find.byType(FengWoNodeSelectorView)).width,
      lessThan(393),
    );
    expect(tester.takeException(), null);
  });

  for (final size in const [
    Size(360, 640),
    Size(393, 800),
    Size(412, 915),
    Size(600, 1024),
  ]) {
    testWidgets(
      'mobile dashboard stays stable at ${size.width.toInt()}x${size.height.toInt()}',
      (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        const nodeName = '新加坡 AWS 2x';
        const profile = Profile(
          id: 1,
          autoUpdateDuration: Duration.zero,
          currentGroupName: '自动选择',
          selectedMap: {'自动选择': nodeName},
        );
        const group = Group(
          name: '自动选择',
          type: GroupType.Selector,
          hidden: false,
          now: nodeName,
          all: [Proxy(name: nodeName, type: 'hysteria2')],
        );
        final container = ProviderContainer(
          overrides: [
            dashboardStateProvider.overrideWithValue(
              const DashboardState(dashboardWidgets: []),
            ),
            viewSizeProvider.overrideWithBuild((_, _) => size),
            initProvider.overrideWithBuild((_, _) => true),
            profilesProvider.overrideWithValue([profile]),
            groupsProvider.overrideWithValue([group]),
            currentProfileProvider.overrideWithValue(profile),
            patchClashConfigProvider.overrideWithBuild(
              (_, _) => const PatchClashConfig(mode: Mode.rule),
            ),
            delayProvider(proxyName: nodeName).overrideWithValue(86),
            networkDetectionProvider.overrideWithValue(
              const NetworkDetectionState(
                isLoading: false,
                ipInfo: IpInfo(
                  ip: '198.51.100.8',
                  countryCode: 'CN',
                  latitude: 31.2304,
                  longitude: 121.4737,
                ),
                originIpInfo: IpInfo(
                  ip: '198.51.100.8',
                  countryCode: 'CN',
                  latitude: 31.2304,
                  longitude: 121.4737,
                ),
              ),
            ),
            setupActionProvider.overrideWith(_RecordingSetupAction.new),
          ],
        );
        addTearDown(container.dispose);
        addTearDown(globalState.clearXboardSession);
        globalState.container = container;

        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: const _TestApp(
              platform: TargetPlatform.android,
              child: DashboardView(),
            ),
          ),
        );
        await tester.pump();

        expect(find.byType(FengWoMobileDashboard), findsOneWidget);
        expect(find.byType(FengWoWorldMap), findsOneWidget);
        final l10n = tester
            .element(find.byType(FengWoMobileDashboard))
            .appLocalizations;
        final nodeCount = find.byKey(
          const ValueKey('fengwo-mobile-map-country-count'),
        );
        expect(nodeCount, findsOneWidget);
        expect(tester.widget<Text>(nodeCount).data, l10n.countriesCount(1));
        final scrollFinder = find.byKey(
          const ValueKey('fengwo-mobile-dashboard-scroll'),
        );
        final scrollView = tester.widget<SingleChildScrollView>(scrollFinder);
        expect(scrollView.physics, isA<ClampingScrollPhysics>());
        expect(tester.takeException(), null);

        await tester.drag(scrollFinder, const Offset(0, -1200));
        await tester.pump();

        expect(find.byType(FengWoWorldMap), findsOneWidget);
        expect(tester.takeException(), null);
      },
    );
  }

  testWidgets('rule mode ignores a stale GLOBAL profile group on mobile', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(393, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    const globalNode = 'GLOBAL 默认节点';
    const ruleNode = '新加坡专线节点';
    const profile = Profile(
      id: 1,
      autoUpdateDuration: Duration.zero,
      currentGroupName: 'GLOBAL',
      selectedMap: {'GLOBAL': globalNode, '自动选择': ruleNode},
    );
    const globalGroup = Group(
      name: 'GLOBAL',
      type: GroupType.Selector,
      hidden: false,
      now: globalNode,
      all: [Proxy(name: globalNode, type: 'ss')],
    );
    const ruleGroup = Group(
      name: '自动选择',
      type: GroupType.Selector,
      hidden: false,
      now: ruleNode,
      all: [Proxy(name: ruleNode, type: 'hysteria2')],
    );
    final container = ProviderContainer(
      overrides: [
        dashboardStateProvider.overrideWithValue(
          const DashboardState(dashboardWidgets: []),
        ),
        viewSizeProvider.overrideWithBuild((_, _) => const Size(393, 800)),
        initProvider.overrideWithBuild((_, _) => true),
        profilesProvider.overrideWithValue([profile]),
        groupsProvider.overrideWithValue([globalGroup, ruleGroup]),
        currentProfileProvider.overrideWithValue(profile),
        patchClashConfigProvider.overrideWithBuild(
          (_, _) => const PatchClashConfig(mode: Mode.rule),
        ),
        delayProvider(proxyName: ruleNode).overrideWithValue(128),
        setupActionProvider.overrideWith(_RecordingSetupAction.new),
      ],
    );
    addTearDown(container.dispose);
    addTearDown(globalState.clearXboardSession);
    globalState.container = container;

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const _TestApp(
          platform: TargetPlatform.android,
          child: DashboardView(),
        ),
      ),
    );
    await tester.pump();

    expect(find.text(ruleNode), findsWidgets);
    expect(find.text(globalNode), findsNothing);

    final switchNode = find.byKey(const ValueKey('fengwo-mobile-switch-node'));
    await tester.ensureVisible(switchNode);
    await tester.tap(switchNode);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    final selector = find.byType(FengWoNodeSelectorView);
    expect(selector, findsOneWidget);
    expect(
      find.descendant(of: selector, matching: find.text('GLOBAL')),
      findsNothing,
    );
    expect(
      find.descendant(of: selector, matching: find.text(ruleNode)),
      findsWidgets,
    );
    expect(tester.takeException(), null);
  });

  testWidgets('desktop map shows directional route endpoints', (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    const nodeName = '新加坡专线节点';
    const profile = Profile(
      id: 1,
      autoUpdateDuration: Duration.zero,
      currentGroupName: '自动选择',
      selectedMap: {'自动选择': nodeName},
    );
    const group = Group(
      name: '自动选择',
      type: GroupType.Selector,
      hidden: false,
      now: nodeName,
      all: [
        Proxy(name: nodeName, type: 'ss'),
        Proxy(name: '新加坡备用节点', type: 'hysteria2'),
      ],
    );
    final container = ProviderContainer(
      overrides: [
        profilesProvider.overrideWithValue([profile]),
        groupsProvider.overrideWithValue([group]),
        currentProfileProvider.overrideWithValue(profile),
        runTimeProvider.overrideWithBuild((_, _) => 1000),
        networkDetectionProvider.overrideWithValue(
          const NetworkDetectionState(
            isLoading: false,
            ipInfo: IpInfo(
              ip: '198.51.100.1',
              countryCode: 'CN',
              latitude: 31.2304,
              longitude: 121.4737,
            ),
            originIpInfo: IpInfo(
              ip: '198.51.100.1',
              countryCode: 'CN',
              latitude: 31.2304,
              longitude: 121.4737,
            ),
          ),
        ),
      ],
    );
    addTearDown(container.dispose);
    addTearDown(globalState.clearXboardSession);
    globalState.container = container;
    globalState.xboardSession = _testTrafficSession();
    globalState.xboardNodes = const [
      XboardNodeData(
        name: nodeName,
        type: 'shadowsocks',
        rate: 1,
        tags: ['SG'],
        isOnline: true,
        rawData: {},
      ),
      XboardNodeData(
        name: '新加坡备用节点',
        type: 'hysteria2',
        rate: 1.5,
        tags: ['SG'],
        isOnline: true,
        rawData: {},
      ),
      XboardNodeData(
        name: '日本专线节点',
        type: 'hysteria2',
        rate: 2,
        tags: ['JP'],
        isOnline: true,
        rawData: {},
      ),
    ];

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const _TestApp(child: FengWoDesktopDashboard()),
      ),
    );
    await tester.pump();

    final userEndpoint = find.byKey(const ValueKey('fengwo-route-user'));
    final nodeEndpoint = find.byKey(const ValueKey('fengwo-route-node'));
    final globalMap = find.byKey(const ValueKey('fengwo-global-network-map'));
    final focusedMap = tester.widget<FlutterMap>(
      find.descendant(of: globalMap, matching: find.byType(FlutterMap)),
    );
    expect(
      focusedMap.mapController!.camera.center.latitude,
      closeTo(31.2304, 0.001),
    );
    expect(
      focusedMap.mapController!.camera.center.longitude,
      closeTo(121.4737, 0.001),
    );
    expect(
      find.descendant(
        of: globalMap,
        matching: find.byKey(const ValueKey('fengwo-user-focus-pulse')),
      ),
      findsOneWidget,
    );
    final singaporeLabel = find.descendant(
      of: globalMap,
      matching: find.byKey(const ValueKey('fengwo-map-country-SG')),
    );
    expect(singaporeLabel, findsOneWidget);
    expect(
      find.descendant(of: singaporeLabel, matching: find.text('Singapore')),
      findsOneWidget,
    );
    expect(
      find.byWidgetPredicate(
        (widget) => widget.runtimeType.toString() == '_MapLabel',
      ),
      findsNothing,
    );
    expect(userEndpoint, findsOneWidget);
    expect(nodeEndpoint, findsOneWidget);
    final userContext = tester.element(userEndpoint);
    expect(
      find.descendant(
        of: userEndpoint,
        matching: find.text(userContext.appLocalizations.userMapLabel),
        matchRoot: true,
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: nodeEndpoint,
        matching: find.textContaining(nodeName),
        matchRoot: true,
      ),
      findsNothing,
    );
    expect(find.byKey(const ValueKey('fengwo-map-zoom-in')), findsOneWidget);
    final l10n = tester
        .element(find.byType(FengWoDesktopDashboard))
        .appLocalizations;
    final trafficDetails = find.byKey(
      const ValueKey('fengwo-desktop-traffic-details'),
    );
    expect(trafficDetails, findsOneWidget);
    expect(
      find.descendant(
        of: trafficDetails,
        matching: find.text(l10n.usedTrafficLabel),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(of: trafficDetails, matching: find.text('658 GB')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: trafficDetails, matching: find.text('1342 GB')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: trafficDetails, matching: find.text('2000 GB')),
      findsOneWidget,
    );
    expect(find.text(l10n.nodesCount(3)), findsOneWidget);
    expect(find.text(l10n.countriesCount(2)), findsOneWidget);
    final networkNodeCount = find.byKey(
      const ValueKey('fengwo-desktop-network-country-count'),
    );
    expect(networkNodeCount, findsOneWidget);
    expect(tester.widget<Text>(networkNodeCount).data, l10n.countriesCount(2));
    final map = tester.widget<FlutterMap>(find.byType(FlutterMap).first);
    final initialZoom = map.mapController!.camera.zoom;
    await tester.tap(find.byKey(const ValueKey('fengwo-map-zoom-in')));
    await tester.pump();
    expect(map.mapController!.camera.zoom, greaterThan(initialZoom));
    expect(find.byType(RichAttributionWidget), findsOneWidget);
    expect(tester.takeException(), null);
  });

  testWidgets('world map centers a country-only IP result', (tester) async {
    tester.view.physicalSize = const Size(820, 520);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      const _TestApp(
        child: SizedBox.expand(
          child: FengWoWorldMap(
            isStart: true,
            showRoute: true,
            interactive: false,
            opacity: 0.8,
            nodeName: '新加坡专线节点',
            ipInfo: IpInfo(ip: '203.0.113.7', countryCode: 'sg'),
            nodes: [FengWoWorldMapNode(name: '新加坡专线节点', delay: 82)],
          ),
        ),
      ),
    );
    await tester.pump();

    final map = tester.widget<FlutterMap>(find.byType(FlutterMap));
    expect(map.mapController!.camera.center.latitude, closeTo(1.35, 0.001));
    expect(map.mapController!.camera.center.longitude, closeTo(103.8, 0.001));
    expect(
      find.byKey(const ValueKey('fengwo-user-focus-pulse')),
      findsOneWidget,
    );
    expect(tester.takeException(), null);
  });

  testWidgets('route map falls back to Beijing when public IP is unavailable', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(820, 520);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      const _TestApp(
        child: SizedBox.expand(
          child: FengWoWorldMap(
            isStart: true,
            showRoute: true,
            interactive: false,
            opacity: 0.8,
            nodeName: '新加坡专线节点',
            nodes: [FengWoWorldMapNode(name: '新加坡专线节点', delay: 82)],
          ),
        ),
      ),
    );
    await tester.pump();

    final map = tester.widget<FlutterMap>(find.byType(FlutterMap));
    expect(map.mapController!.camera.center.latitude, closeTo(39.9042, 0.001));
    expect(
      map.mapController!.camera.center.longitude,
      closeTo(116.4074, 0.001),
    );
    expect(find.byKey(const ValueKey('fengwo-route-user')), findsOneWidget);
    expect(find.byKey(const ValueKey('fengwo-route-node')), findsOneWidget);
    expect(find.byKey(const ValueKey('fengwo-route-progress')), findsOneWidget);
    expect(tester.takeException(), null);
  });

  testWidgets('world map reveals a compact node label only after tapping', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(520, 320);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    const nodeName = '新加坡 AWS 2x';
    await tester.pumpWidget(
      const _TestApp(
        child: SizedBox.expand(
          child: FengWoWorldMap(
            isStart: false,
            showRoute: false,
            interactive: false,
            opacity: 0.8,
            nodes: [FengWoWorldMapNode(name: nodeName, delay: 82)],
          ),
        ),
      ),
    );
    await tester.pump();

    final marker = find.byKey(const ValueKey('fengwo-map-node-$nodeName'));
    final dot = find.byKey(const ValueKey('fengwo-map-node-dot-$nodeName'));
    final pulse = find.byKey(const ValueKey('fengwo-map-node-pulse-$nodeName'));
    final label = find.byKey(const ValueKey('fengwo-map-node-label-$nodeName'));
    expect(marker, findsOneWidget);
    expect(dot, findsOneWidget);
    expect(tester.getSize(dot), const Size.square(9));
    expect(pulse, findsNothing);
    expect(label, findsNothing);

    await tester.tap(marker);
    await tester.pump();

    expect(label, findsOneWidget);
    expect(
      find.descendant(of: label, matching: find.text(nodeName)),
      findsOneWidget,
    );
    expect(
      find.descendant(of: label, matching: find.text('82 ms')),
      findsOneWidget,
    );

    await tester.tap(marker);
    await tester.pump();

    expect(label, findsNothing);
    expect(tester.takeException(), null);
  });

  testWidgets('world map distinguishes actual and standardized latency', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(620, 360);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    const nodeName = '日本双延迟节点';
    await tester.pumpWidget(
      const _TestApp(
        child: SizedBox.expand(
          child: FengWoWorldMap(
            isStart: false,
            showRoute: false,
            interactive: true,
            opacity: 0.8,
            nodes: [
              FengWoWorldMapNode(
                name: nodeName,
                delay: 96,
                connectionDelay: 96,
                standardDelay: 42,
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey('fengwo-map-node-$nodeName')));
    await tester.pump();

    final label = find.byKey(const ValueKey('fengwo-map-node-label-$nodeName'));
    expect(
      find.descendant(of: label, matching: find.textContaining('96 ms')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: label, matching: find.textContaining('42 ms')),
      findsOneWidget,
    );
    expect(tester.takeException(), null);
  });

  testWidgets('world map colors markers by the required latency thresholds', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(720, 420);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    const delays = <String, int>{
      '美国超时节点': -1,
      '日本低延迟节点': 250,
      '新加坡中延迟节点': 400,
      '澳大利亚高延迟节点': 401,
      '仅通过标签定位的节点': 120,
    };
    await tester.pumpWidget(
      const _TestApp(
        child: SizedBox.expand(
          child: FengWoWorldMap(
            isStart: false,
            showRoute: false,
            interactive: true,
            opacity: 0.8,
            nodes: [
              FengWoWorldMapNode(name: '美国超时节点', delay: -1),
              FengWoWorldMapNode(name: '日本低延迟节点', delay: 250),
              FengWoWorldMapNode(name: '新加坡中延迟节点', delay: 400),
              FengWoWorldMapNode(name: '澳大利亚高延迟节点', delay: 401),
              FengWoWorldMapNode(
                name: '仅通过标签定位的节点',
                delay: 120,
                countryCode: 'NP',
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pump();

    final expectedColors = <String, Color>{
      '美国超时节点': const Color(0xFFE84C4C),
      '日本低延迟节点': const Color(0xFF15BF70),
      '新加坡中延迟节点': const Color(0xFF3B82F6),
      '澳大利亚高延迟节点': const Color(0xFFF29C38),
      '仅通过标签定位的节点': const Color(0xFF15BF70),
    };
    for (final entry in delays.entries) {
      final dot = tester.widget<Container>(
        find.byKey(ValueKey('fengwo-map-node-dot-${entry.key}')),
      );
      final decoration = dot.decoration! as BoxDecoration;
      expect(decoration.color, expectedColors[entry.key]);
    }
    expect(find.byKey(const ValueKey('fengwo-map-zoom-in')), findsOneWidget);
    expect(tester.takeException(), null);
  });

  testWidgets('world map animates a node while latency testing is active', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(520, 320);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    const nodeName = '日本测速节点';
    await tester.pumpWidget(
      const _TestApp(
        child: SizedBox.expand(
          child: FengWoWorldMap(
            isStart: false,
            showRoute: false,
            interactive: true,
            opacity: 0.8,
            nodes: [FengWoWorldMapNode(name: nodeName, delay: 0)],
          ),
        ),
      ),
    );
    await tester.pump();

    final pulse = find.byKey(const ValueKey('fengwo-map-node-pulse-$nodeName'));
    expect(pulse, findsOneWidget);
    final initialSize = tester.getSize(pulse);

    await tester.pump(const Duration(milliseconds: 500));

    expect(tester.getSize(pulse).width, greaterThan(initialSize.width));
    expect(tester.takeException(), null);
  });

  testWidgets('node status keeps the page fixed and scrolls preferred nodes', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final nodes = List.generate(
      14,
      (index) => Proxy(
        name: switch (index % 4) {
          0 => '美国节点 ${index + 1}x',
          1 => '日本大阪节点 ${index + 1}x',
          2 => '新加坡节点 ${index + 1}x',
          _ => '韩国首尔节点 ${index + 1}x',
        },
        type: index.isEven ? 'ss' : 'hysteria2',
      ),
    );
    const metadataNode = Proxy(name: '剩余流量：100 GB', type: 'ss');
    final group = Group(
      name: '优选线路',
      type: GroupType.Selector,
      hidden: false,
      now: nodes[2].name,
      all: [metadataNode, ...nodes],
    );
    final profile = Profile(
      id: 1,
      autoUpdateDuration: Duration.zero,
      currentGroupName: group.name,
      selectedMap: {group.name: nodes[2].name},
    );
    final container = ProviderContainer(
      overrides: [
        groupsProvider.overrideWithValue([group]),
        currentGroupsStateProvider.overrideWithValue(
          GroupsState(value: [group]),
        ),
        currentProfileProvider.overrideWithValue(profile),
        isStartProvider.overrideWithValue(true),
        networkDetectionProvider.overrideWithValue(
          const NetworkDetectionState(
            isLoading: false,
            ipInfo: IpInfo(
              ip: '198.51.100.1',
              countryCode: 'CN',
              latitude: 39.9042,
              longitude: 116.4074,
            ),
            originIpInfo: IpInfo(
              ip: '198.51.100.1',
              countryCode: 'CN',
              latitude: 39.9042,
              longitude: 116.4074,
            ),
          ),
        ),
        for (var index = 0; index < nodes.length; index++)
          delayProvider(proxyName: nodes[index].name).overrideWithValue(
            switch (index % 4) {
              0 => 120,
              1 => 310,
              2 => 520,
              _ => -1,
            },
          ),
      ],
    );
    addTearDown(container.dispose);
    globalState.container = container;
    globalState.xboardNodes = [
      XboardNodeData(
        name: nodes.first.name,
        type: nodes.first.type,
        rate: 1,
        tags: const ['US'],
        isOnline: false,
        rawData: const {},
      ),
    ];
    addTearDown(() => globalState.xboardNodes = const []);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const _TestApp(child: FengWoNodeStatusView()),
      ),
    );
    await tester.pump();

    final page = find.byType(FengWoNodeStatusView);
    expect(page, findsOneWidget);
    final localizations = tester.element(page).appLocalizations;
    expect(find.text(localizations.nodeBackendOffline), findsOneWidget);
    expect(find.text(localizations.nodeAvailable), findsWidgets);
    expect(find.text(localizations.nodeLocallyUnreachable), findsWidgets);
    expect(
      find.descendant(of: page, matching: find.byType(SingleChildScrollView)),
      findsNothing,
    );
    final mapPanel = find.byKey(const ValueKey('fengwo-node-status-map'));
    final nodesPanel = find.byKey(const ValueKey('fengwo-node-status-list'));
    expect(mapPanel, findsOneWidget);
    expect(nodesPanel, findsOneWidget);
    expect(
      tester.getRect(mapPanel).center.dx,
      lessThan(tester.getRect(nodesPanel).center.dx),
    );
    expect(
      tester.getRect(mapPanel).top,
      closeTo(tester.getRect(nodesPanel).top, 1),
    );
    expect(find.byType(FlutterMap), findsOneWidget);
    expect(find.byKey(const ValueKey('fengwo-route-user')), findsOneWidget);
    expect(find.byKey(const ValueKey('fengwo-route-node')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('fengwo-user-focus-pulse')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('fengwo-route-progress')), findsOneWidget);
    expect(find.text(metadataNode.name), findsNothing);
    expect(
      find.byKey(const ValueKey('fengwo-node-status-scrollable-list')),
      findsOneWidget,
    );
    expect(find.text(nodes.last.name), findsNothing);

    await tester.drag(
      find.byKey(const ValueKey('fengwo-node-status-scrollable-list')),
      const Offset(0, -800),
    );
    await tester.pump();

    expect(find.text(nodes.last.name), findsOneWidget);
    expect(tester.takeException(), null);
  });

  testWidgets('node status shows XBoard state without fabricated latency', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1000, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    const proxy = Proxy(name: '日本东京节点', type: 'hysteria2');
    final group = Group(
      name: '优选线路',
      type: GroupType.Selector,
      hidden: false,
      now: proxy.name,
      all: [proxy],
    );
    final profile = Profile(
      id: 1,
      autoUpdateDuration: Duration.zero,
      currentGroupName: group.name,
      selectedMap: {group.name: proxy.name},
    );
    final container = ProviderContainer(
      overrides: [
        groupsProvider.overrideWithValue([group]),
        currentGroupsStateProvider.overrideWithValue(
          GroupsState(value: [group]),
        ),
        currentProfileProvider.overrideWithValue(profile),
      ],
    );
    addTearDown(container.dispose);
    globalState.container = container;
    globalState.xboardNodes = [
      XboardNodeData(
        name: proxy.name,
        type: proxy.type,
        rate: 1,
        tags: ['JP'],
        isOnline: true,
        rawData: {},
      ),
    ];
    addTearDown(() => globalState.xboardNodes = const []);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const _TestApp(child: FengWoNodeStatusView()),
      ),
    );
    await tester.pump();

    final page = find.byType(FengWoNodeStatusView);
    final localizations = tester.element(page).appLocalizations;
    expect(find.text(localizations.nodeBackendOnline), findsOneWidget);
    expect(find.text(localizations.notTested), findsOneWidget);
    expect(find.textContaining(' ms'), findsNothing);
    expect(tester.takeException(), null);
  });

  testWidgets('node selector uses real groups and filters node names', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1100, 760);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    const group = Group(
      name: '自动选择',
      type: GroupType.Selector,
      hidden: false,
      now: '日本大阪 1x',
      all: [
        Proxy(name: '日本大阪 1x', type: 'ss'),
        Proxy(name: '新加坡 AWS 2x', type: 'hysteria2'),
      ],
    );
    final container = ProviderContainer(
      overrides: [
        groupsProvider.overrideWithValue([group]),
        currentProfileProvider.overrideWithValue(
          const Profile(
            id: 1,
            autoUpdateDuration: Duration.zero,
            currentGroupName: '自动选择',
            selectedMap: {'自动选择': '日本大阪 1x'},
          ),
        ),
        delayProvider(proxyName: '日本大阪 1x').overrideWithValue(168),
        delayProvider(proxyName: '新加坡 AWS 2x').overrideWithValue(420),
      ],
    );
    addTearDown(container.dispose);
    globalState.container = container;
    globalState.xboardNodes = const [
      XboardNodeData(
        name: '新加坡 AWS 2x',
        type: 'hysteria2',
        rate: 1,
        tags: ['SG'],
        isOnline: false,
        rawData: {},
      ),
    ];
    addTearDown(() => globalState.xboardNodes = const []);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const _TestApp(child: FengWoNodeSelectorView()),
      ),
    );
    await tester.pump();

    expect(find.text('自动选择'), findsWidgets);
    expect(find.text('日本大阪 1x'), findsWidgets);
    expect(find.text('新加坡 AWS 2x'), findsOneWidget);
    expect(find.text('168 ms'), findsOneWidget);
    final localizations = tester
        .element(find.byType(FengWoNodeSelectorView))
        .appLocalizations;
    expect(find.text(localizations.nodeBackendOffline), findsOneWidget);
    final offlineTestButton = tester.widget<OutlinedButton>(
      find.byKey(const ValueKey('fengwo-selector-test-新加坡 AWS 2x')),
    );
    expect(offlineTestButton.onPressed, isNull);

    await tester.enterText(find.byType(TextField), '新加坡');
    await tester.pump();

    expect(find.text('新加坡 AWS 2x'), findsOneWidget);
    expect(find.text('日本大阪 1x'), findsOneWidget);
    expect(tester.takeException(), null);
  });
}

XboardLoginResult _testTrafficSession() {
  final endpoint = Uri.parse('https://api.example.com');
  return XboardLoginResult(
    endpoint: endpoint,
    token: 'subscription-token',
    authData: 'Bearer login-token',
    isAdmin: false,
    subscription: XboardSubscriptionData(
      endpoint: endpoint,
      subscribeUrl: Uri.parse('https://subscribe.example.com/client/token'),
      uploadBytes: bytesPerGigabyte * 300,
      downloadBytes: bytesPerGigabyte * 358,
      transferEnableBytes: bytesPerGigabyte * 2000,
      rawData: const {},
    ),
  );
}

class _RecordingSetupAction extends SetupAction {
  final requests = <bool>[];

  @override
  Future<void> setRunning(bool running, {bool initialize = false}) {
    requests.add(running);
    ref.read(runTimeProvider.notifier).value = running ? 1 : null;
    return Future.value();
  }
}

class _TestProfiles extends Profiles {
  final List<Profile> initial;

  _TestProfiles(this.initial);

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

class _TestApp extends StatelessWidget {
  final Widget child;
  final ThemeMode themeMode;
  final TargetPlatform? platform;

  const _TestApp({
    required this.child,
    this.themeMode = ThemeMode.light,
    this.platform,
  });

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: globalState.navigatorKey,
      theme: ThemeData(
        platform: platform,
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF0969DA)),
      ),
      darkTheme: ThemeData(
        platform: platform,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF63A5FF),
          brightness: Brightness.dark,
        ),
      ),
      themeMode: themeMode,
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
      home: child,
    );
  }
}

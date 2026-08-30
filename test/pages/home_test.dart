import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/common/theme.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/l10n/l10n.dart';
import 'package:fl_clash/manager/app_manager.dart';
import 'package:fl_clash/manager/theme_manager.dart';
import 'package:fl_clash/manager/window_manager.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/pages/home.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/state.dart';
import 'package:fl_clash/views/account/fengwo_personal_center.dart';
import 'package:fl_clash/views/settings/fengwo_advanced_settings.dart';
import 'package:fl_clash/views/tools.dart';
import 'package:fl_clash/widgets/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(() {
    globalState.setOfflineMode(false);
    globalState.enableOfflineMode = null;
    globalState.restoreOnlineMode = null;
  });

  tearDown(() {
    globalState.setOfflineMode(false);
    globalState.enableOfflineMode = null;
    globalState.restoreOnlineMode = null;
  });

  testWidgets('initial desktop layout does not animate mobile navigation out', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final container = ProviderContainer(
      overrides: [
        navigationItemsStateProvider.overrideWithValue(
          NavigationItemsState(
            value: [
              NavigationItem(
                icon: const Icon(Icons.space_dashboard),
                label: PageLabel.dashboard,
                builder: (_) => const SizedBox.shrink(),
              ),
              NavigationItem(
                icon: const Icon(Icons.construction),
                label: PageLabel.tools,
                builder: (_) => const SizedBox.shrink(),
              ),
            ],
          ),
        ),
      ],
    );
    addTearDown(container.dispose);
    globalState.container = container;
    expect(container.read(viewSizeProvider), Size.zero);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const _ThemeManagedTestApp(),
      ),
    );

    expect(globalState.navigatorKey.currentContext, isNotNull);
    expect(container.read(viewSizeProvider), const Size(1200, 800));
    expect(find.byType(NavigationBar), findsNothing);

    await tester.pump();

    expect(find.byType(NavigationRail), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
    expect(
      find.byKey(const ValueKey('fengwo-sidebar-offline-mode')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('fengwo-sidebar-logout')), findsOneWidget);

    final offlineSwitch = find.descendant(
      of: find.byKey(const ValueKey('fengwo-sidebar-offline-mode')),
      matching: find.byType(Switch),
    );
    expect(tester.widget<Switch>(offlineSwitch).value, isFalse);
    expect(tester.widget<Switch>(offlineSwitch).onChanged, isNotNull);

    await tester.pump(const Duration(milliseconds: 150));

    expect(find.byType(NavigationBar), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('sidebar confirms and enables offline mode', (tester) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    globalState.enableOfflineMode = () async {
      globalState.setOfflineMode(true);
      return true;
    };

    final container = ProviderContainer(
      overrides: [
        navigationItemsStateProvider.overrideWithValue(
          NavigationItemsState(
            value: [
              NavigationItem(
                icon: const Icon(Icons.home_outlined),
                label: PageLabel.dashboard,
                builder: (_) => const SizedBox.shrink(),
              ),
            ],
          ),
        ),
      ],
    );
    addTearDown(container.dispose);
    globalState.container = container;
    container.read(viewSizeProvider.notifier).value = const Size(1200, 800);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const _TestApp(child: HomePage()),
      ),
    );
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey('fengwo-sidebar-offline-mode')));
    await tester.pumpAndSettle();
    final dialogContext = tester.element(
      find.byKey(const ValueKey('enable-offline-mode-button')),
    );
    expect(
      find.text(dialogContext.appLocalizations.enableOfflineTitle),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey('enable-offline-mode-button')));
    await tester.pumpAndSettle();

    expect(globalState.isOfflineMode, isTrue);
    expect(find.byKey(const ValueKey('offline-mode-banner')), findsOneWidget);
  });

  testWidgets('sidebar logout opens a confirmation dialog', (tester) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final container = ProviderContainer(
      overrides: [
        navigationItemsStateProvider.overrideWithValue(
          NavigationItemsState(
            value: [
              NavigationItem(
                icon: const Icon(Icons.home_outlined),
                label: PageLabel.dashboard,
                builder: (_) => const SizedBox.shrink(),
              ),
            ],
          ),
        ),
      ],
    );
    addTearDown(container.dispose);
    globalState.container = container;
    container.read(viewSizeProvider.notifier).value = const Size(1200, 800);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const _TestApp(child: HomePage()),
      ),
    );
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey('fengwo-sidebar-logout')));
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsOneWidget);
    final dialogContext = tester.element(find.byType(AlertDialog));
    expect(
      find.text(dialogContext.appLocalizations.logoutConfirmTitle),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('desktop account header stays mounted across menu changes', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final container = ProviderContainer(
      overrides: [
        navigationItemsStateProvider.overrideWithValue(
          NavigationItemsState(
            value: [
              for (final label in [
                PageLabel.dashboard,
                PageLabel.tools,
                PageLabel.traffic,
              ])
                NavigationItem(
                  icon: const Icon(Icons.circle_outlined),
                  label: label,
                  builder: (_) => Text('page:${label.name}'),
                ),
            ],
          ),
        ),
      ],
    );
    addTearDown(container.dispose);
    globalState.container = container;
    container.read(viewSizeProvider.notifier).value = const Size(1200, 800);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const _TestApp(child: HomePage()),
      ),
    );
    await tester.pump();

    final header = find.byKey(const ValueKey('fengwo-global-account-header'));
    expect(header, findsOneWidget);
    expect(
      find.byKey(const ValueKey('fengwo-global-account-avatar')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('subscription-status-indicator')),
      findsOneWidget,
    );
    final mountedHeader = tester.element(header);

    for (final label in [PageLabel.tools, PageLabel.traffic]) {
      container.read(currentPageLabelProvider.notifier).toPage(label);
      await tester.pumpAndSettle();
      expect(header, findsOneWidget);
      expect(identical(tester.element(header), mountedHeader), isTrue);
      expect(find.text('page:${label.name}'), findsOneWidget);
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'screen-size transition preserves current content and animates navigation',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final container = ProviderContainer(
        overrides: [
          navigationItemsStateProvider.overrideWithValue(
            NavigationItemsState(
              value: [
                NavigationItem(
                  icon: const Icon(Icons.space_dashboard),
                  label: PageLabel.dashboard,
                  builder: (_) => const _StatefulContent(
                    key: GlobalObjectKey(PageLabel.dashboard),
                  ),
                ),
                NavigationItem(
                  icon: const Icon(Icons.construction),
                  label: PageLabel.tools,
                  builder: (_) => const SizedBox.shrink(),
                ),
              ],
            ),
          ),
        ],
      );
      addTearDown(container.dispose);
      globalState.container = container;
      container.read(viewSizeProvider.notifier).value = const Size(1200, 800);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const _TestApp(child: HomePage()),
        ),
      );
      await tester.pump();

      final sidebarBackground = find.descendant(
        of: find.byType(AppSidebarContainer),
        matching: find.byWidgetPredicate(
          (widget) => widget is Container && widget.child is Row,
        ),
      );
      final sidebarContainer = tester.widget<Container>(
        sidebarBackground.first,
      );
      expect(
        sidebarContainer.color,
        Theme.of(
          tester.element(find.byType(AppSidebarContainer)),
        ).colorScheme.surfaceContainer,
      );

      await tester.tap(find.text('count: 0'));
      await tester.pump();
      expect(find.text('count: 1'), findsOneWidget);
      expect(find.byType(NavigationRail), findsOneWidget);
      expect(find.byType(NavigationBar), findsNothing);

      for (var width = 1180.0; width >= 500; width -= 20) {
        tester.view.physicalSize = Size(width, 800);
        container.read(viewSizeProvider.notifier).value = Size(width, 800);
        await tester.pump(const Duration(milliseconds: 16));
        expect(tester.takeException(), isNull, reason: 'width: $width');
      }

      expect(find.text('count: 1'), findsOneWidget);
      expect(find.byType(NavigationRail), findsOneWidget);
      expect(find.byType(NavigationBar), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 150));
      expect(tester.takeException(), isNull);

      final outgoingTools = find.descendant(
        of: find.byType(NavigationRail),
        matching: find.byIcon(Icons.construction),
      );
      await tester.tap(outgoingTools, warnIfMissed: false);
      await tester.pump();
      expect(container.read(currentPageLabelProvider), PageLabel.dashboard);

      await tester.pump(const Duration(milliseconds: 301));
      expect(find.byType(NavigationRail), findsNothing);
      expect(find.byType(NavigationBar), findsOneWidget);

      tester.view.physicalSize = const Size(1200, 800);
      container.read(viewSizeProvider.notifier).value = const Size(1200, 800);
      await tester.pump();

      expect(find.text('count: 1'), findsOneWidget);
      expect(find.byType(NavigationRail), findsOneWidget);
      expect(find.byType(NavigationBar), findsOneWidget);

      await tester.pump(const Duration(milliseconds: 301));
      expect(find.byType(NavigationRail), findsOneWidget);
      expect(find.byType(NavigationBar), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'list content stays valid while resizing through the breakpoint',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final container = ProviderContainer(
        overrides: [
          navigationItemsStateProvider.overrideWithValue(
            NavigationItemsState(
              value: [
                NavigationItem(
                  icon: const Icon(Icons.space_dashboard),
                  label: PageLabel.dashboard,
                  builder: (_) => const ToolsView(
                    key: GlobalObjectKey(PageLabel.dashboard),
                  ),
                ),
                NavigationItem(
                  icon: const Icon(Icons.construction),
                  label: PageLabel.tools,
                  builder: (_) => const SizedBox.shrink(),
                ),
              ],
            ),
          ),
        ],
      );
      addTearDown(container.dispose);
      globalState.container = container;
      container.read(viewSizeProvider.notifier).value = const Size(1200, 800);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const _TestApp(child: HomePage()),
        ),
      );
      await tester.pump();

      for (var width = 1180.0; width >= 380; width -= 20) {
        tester.view.physicalSize = Size(width, 800);
        container.read(viewSizeProvider.notifier).value = Size(width, 800);
        await tester.pump(const Duration(milliseconds: 16));
        expect(tester.takeException(), isNull, reason: 'width: $width');
      }
    },
  );

  testWidgets(
    'profile trailing controls stay valid while a maximized window restores',
    (tester) async {
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final profile = Profile.normal();
      final container = ProviderContainer(
        overrides: [
          profilesProvider.overrideWith(() => _HomeTestProfiles([profile])),
          currentProfileIdProvider.overrideWithBuild((_, _) => profile.id),
          versionProvider.overrideWithBuild((_, _) => 15),
        ],
      );
      addTearDown(container.dispose);
      globalState.container = container;
      container
          .read(currentPageLabelProvider.notifier)
          .toPage(PageLabel.profiles);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const _TestApp(
            child: ThemeManager(
              child: WindowHeaderContainer(child: HomePage()),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
      expect(tester.takeException(), isNull);

      tester.view.physicalSize = const Size(380, 900);
      await tester.pump(const Duration(milliseconds: 16));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'desktop tools route renders the personal center when logs are enabled',
    (tester) async {
      tester.view.physicalSize = const Size(1400, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final container = ProviderContainer();
      addTearDown(container.dispose);
      globalState.container = container;
      container.read(viewSizeProvider.notifier).value = const Size(1400, 1000);
      container.read(currentPageLabelProvider.notifier).toPage(PageLabel.tools);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const _TestApp(child: HomePage()),
        ),
      );
      await tester.pump();

      expect(find.byType(FengWoPersonalCenterView), findsOneWidget);
      container
          .read(appSettingProvider.notifier)
          .update((state) => state.copyWith(openLogs: true));
      await tester.pumpAndSettle();

      expect(container.read(appSettingProvider).openLogs, isTrue);
      expect(find.byType(FengWoPersonalCenterView), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('desktop resources route renders advanced settings', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final container = ProviderContainer();
    addTearDown(container.dispose);
    globalState.container = container;
    container.read(viewSizeProvider.notifier).value = const Size(1400, 1000);
    container
        .read(currentPageLabelProvider.notifier)
        .toPage(PageLabel.resources);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const _TestApp(child: HomePage()),
      ),
    );
    await tester.pump();

    expect(find.byType(FengWoAdvancedSettingsView), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'desktop navigation keeps arrow traversal after keyboard page changes',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final container = ProviderContainer(
        overrides: [
          navigationItemsStateProvider.overrideWithValue(
            NavigationItemsState(
              value: [
                NavigationItem(
                  icon: const Icon(Icons.space_dashboard),
                  label: PageLabel.dashboard,
                  builder: (_) => Align(
                    alignment: Alignment.topLeft,
                    child: IconButton(
                      onPressed: () {},
                      icon: const Icon(Icons.more_horiz),
                    ),
                  ),
                ),
                NavigationItem(
                  icon: const Icon(Icons.article),
                  label: PageLabel.proxies,
                  builder: (_) => Align(
                    alignment: Alignment.topLeft,
                    child: IconButton(
                      onPressed: () {},
                      icon: const Icon(Icons.more_vert),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      );
      addTearDown(container.dispose);
      globalState.container = container;
      container.read(viewSizeProvider.notifier).value = const Size(1200, 800);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const _TestApp(child: HomePage()),
        ),
      );
      await tester.pump();
      expect(find.byType(NavigationRail), findsOneWidget);

      bool focusInRail() {
        final context = FocusManager.instance.primaryFocus?.context;
        return context?.findAncestorWidgetOfExactType<NavigationRail>() != null;
      }

      IconData? focusedRailIcon() {
        final focusNode = FocusManager.instance.primaryFocus;
        if (!focusInRail() || focusNode == null) {
          return null;
        }
        return [Icons.space_dashboard, Icons.article].reduce((closest, icon) {
          final closestDistance =
              (tester.getCenter(find.byIcon(closest)).dy -
                      focusNode.rect.center.dy)
                  .abs();
          final distance =
              (tester.getCenter(find.byIcon(icon)).dy -
                      focusNode.rect.center.dy)
                  .abs();
          return distance < closestDistance ? icon : closest;
        });
      }

      for (var i = 0; i < 30 && !focusInRail(); i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();
      }
      expect(focusInRail(), isTrue);
      expect(focusedRailIcon(), Icons.space_dashboard);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      expect(focusedRailIcon(), Icons.article);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();

      expect(container.read(currentPageLabelProvider), PageLabel.proxies);
      final rail = tester.widget<NavigationRail>(find.byType(NavigationRail));
      expect(rail.selectedIndex, 1);
      expect(focusedRailIcon(), Icons.article);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pump();
      expect(focusedRailIcon(), Icons.space_dashboard);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();

      expect(container.read(currentPageLabelProvider), PageLabel.dashboard);
      expect(focusedRailIcon(), Icons.space_dashboard);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();

      expect(focusedRailIcon(), Icons.article);
      expect(container.read(currentPageLabelProvider), PageLabel.dashboard);
    },
  );

  testWidgets('mobile bottom navigation keeps page and highlight consistent', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(500, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    Widget page(String label) {
      return Stack(
        clipBehavior: Clip.none,
        children: [
          Text('page:$label'),
          Positioned(
            left: 200,
            bottom: 0,
            child: IconButton(
              key: const ValueKey('content-action'),
              onPressed: () {},
              icon: const Icon(Icons.more_horiz),
            ),
          ),
        ],
      );
    }

    final container = ProviderContainer(
      overrides: [
        navigationItemsStateProvider.overrideWithValue(
          NavigationItemsState(
            value: [
              NavigationItem(
                icon: const Icon(Icons.space_dashboard),
                label: PageLabel.dashboard,
                builder: (_) => page('dashboard'),
              ),
              NavigationItem(
                icon: const Icon(Icons.folder),
                label: PageLabel.profiles,
                builder: (_) => page('profiles'),
              ),
              NavigationItem(
                icon: const Icon(Icons.construction),
                label: PageLabel.tools,
                builder: (_) => page('tools'),
              ),
              NavigationItem(
                icon: const Icon(Icons.article),
                label: PageLabel.logs,
                builder: (_) => page('logs'),
              ),
            ],
          ),
        ),
      ],
    );
    addTearDown(container.dispose);
    globalState.container = container;
    container.read(viewSizeProvider.notifier).value = const Size(500, 800);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const _TestApp(child: HomePage()),
      ),
    );
    await tester.pump();
    expect(find.byType(NavigationBar), findsOneWidget);

    NavigationBar navBar() =>
        tester.widget<NavigationBar>(find.byType(NavigationBar));

    Finder menuIcon(IconData icon) => find.descendant(
      of: find.byKey(const ValueKey('fengwo-mobile-business-menu')),
      matching: find.byIcon(icon),
    );

    Future<void> tapMenu(IconData icon) async {
      final finder = menuIcon(icon);
      await tester.tap(finder);
      await tester.pumpAndSettle();
    }

    Future<void> tapMineEntry(IconData icon) async {
      await tapMenu(Icons.grid_view_rounded);
      expect(
        find.byKey(const ValueKey('fengwo-mobile-mine-sheet')),
        findsOneWidget,
      );
      final finder = find.descendant(
        of: find.byKey(const ValueKey('fengwo-mobile-mine-sheet')),
        matching: find.byIcon(icon),
      );
      await tester.tap(finder);
      await tester.pumpAndSettle();
    }

    await tapMineEntry(Icons.person_outline_rounded);
    expect(container.read(currentPageLabelProvider), PageLabel.tools);
    expect(navBar().selectedIndex, 2);
    expect(find.text('page:tools'), findsOneWidget);

    bool focusInNav() {
      final context = FocusManager.instance.primaryFocus?.context;
      return context?.findAncestorWidgetOfExactType<NavigationBar>() != null;
    }

    for (var i = 0; i < 20 && !focusInNav(); i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
    }
    expect(focusInNav(), isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(container.read(currentPageLabelProvider), PageLabel.dashboard);
    expect(navBar().selectedIndex, 1);
    expect(find.text('page:dashboard'), findsOneWidget);

    await tapMineEntry(Icons.person_outline_rounded);
    await tapMenu(Icons.home_outlined);
    await tapMenu(Icons.shopping_cart_outlined);
    expect(container.read(currentPageLabelProvider), PageLabel.profiles);
    expect(navBar().selectedIndex, 0);
    expect(find.text('page:profiles'), findsOneWidget);
    expect(focusInNav(), isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pump();
    final focusedIconButton = FocusManager.instance.primaryFocus?.context
        ?.findAncestorWidgetOfExactType<IconButton>();
    expect(
      focusedIconButton?.key,
      const ValueKey('content-action'),
      reason: 'up from the bottom bar must enter the current page',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'mobile navigation keeps three primary entries and opens the rest in My',
    (tester) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      NavigationItem item(
        PageLabel label,
        IconData icon, {
        List<NavigationItemMode> modes = const [
          NavigationItemMode.mobile,
          NavigationItemMode.desktop,
        ],
      }) {
        return NavigationItem(
          icon: Icon(icon),
          label: label,
          modes: modes,
          builder: (_) => Text('page:${label.name}'),
        );
      }

      final container = ProviderContainer(
        overrides: [
          navigationItemsStateProvider.overrideWithValue(
            NavigationItemsState(
              value: [
                item(PageLabel.dashboard, Icons.space_dashboard),
                item(PageLabel.profiles, Icons.folder),
                item(
                  PageLabel.requests,
                  Icons.view_timeline,
                  modes: const [NavigationItemMode.desktop],
                ),
                item(
                  PageLabel.connections,
                  Icons.ballot,
                  modes: const [NavigationItemMode.desktop],
                ),
                item(PageLabel.traffic, Icons.pie_chart_outline_rounded),
                item(PageLabel.orders, Icons.receipt_long_outlined),
                item(PageLabel.invite, Icons.card_giftcard_outlined),
                item(PageLabel.resources, Icons.storage),
                item(PageLabel.tools, Icons.construction),
              ],
            ),
          ),
        ],
      );
      addTearDown(container.dispose);
      globalState.container = container;
      container.read(viewSizeProvider.notifier).value = const Size(360, 640);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const _TestApp(child: HomePage()),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 301));

      final navigationBar = tester.widget<NavigationBar>(
        find.byType(NavigationBar),
      );
      expect(navigationBar.selectedIndex, 1);
      final destinations = navigationBar.destinations
          .cast<NavigationDestination>()
          .toList();
      final l10n = tester.element(find.byType(NavigationBar)).appLocalizations;
      expect(
        find.byKey(const ValueKey('fengwo-mobile-floating-menu')),
        findsOneWidget,
      );
      final viewportSize = tester.getSize(
        find.byKey(const ValueKey('fengwo-mobile-floating-menu-viewport')),
      );
      final menuSize = tester.getSize(
        find.byKey(const ValueKey('fengwo-mobile-business-menu')),
      );
      expect(viewportSize.width, closeTo(328, .01));
      expect(menuSize.width, closeTo(viewportSize.width, .01));
      expect(destinations, hasLength(3));
      expect(
        destinations.map((destination) => (destination.icon as Icon).icon),
        [
          Icons.shopping_cart_outlined,
          Icons.home_outlined,
          Icons.grid_view_rounded,
        ],
      );
      expect(destinations.map((destination) => destination.label), [
        l10n.purchasePlan,
        l10n.acceleratorHome,
        l10n.mine,
      ]);
      expect(find.byIcon(Icons.storage), findsNothing);

      Future<void> tapMineEntry(IconData icon) async {
        await tester.tap(find.byIcon(Icons.grid_view_rounded));
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('fengwo-mobile-mine-grid')),
          findsOneWidget,
        );
        final finder = find.descendant(
          of: find.byKey(const ValueKey('fengwo-mobile-mine-sheet')),
          matching: find.byIcon(icon),
        );
        await tester.tap(finder);
        await tester.pumpAndSettle();
      }

      await tester.tap(find.byIcon(Icons.grid_view_rounded));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('fengwo-mobile-mine-grid')),
        findsOneWidget,
      );
      for (final label in [
        PageLabel.proxies,
        PageLabel.connections,
        PageLabel.traffic,
        PageLabel.orders,
        PageLabel.invite,
        PageLabel.tools,
        PageLabel.resources,
        PageLabel.practicalTools,
      ]) {
        expect(
          find.byKey(ValueKey('fengwo-mobile-mine-${label.name}')),
          findsOneWidget,
        );
      }
      await tester.tap(find.byKey(const ValueKey('fengwo-mobile-mine-close')));
      await tester.pumpAndSettle();

      await tapMineEntry(Icons.pie_chart_outline_rounded);
      await tester.pumpAndSettle();
      expect(container.read(currentPageLabelProvider), PageLabel.traffic);
      expect(find.text('page:traffic'), findsOneWidget);
      expect(
        tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
        2,
      );

      await tapMineEntry(Icons.card_giftcard_outlined);
      expect(container.read(currentPageLabelProvider), PageLabel.invite);
      expect(find.text('page:invite'), findsOneWidget);

      await tapMineEntry(Icons.settings_outlined);
      expect(container.read(currentPageLabelProvider), PageLabel.resources);
      expect(find.text('page:resources'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('switching home pages exits a generic search layer', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(500, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    var query = '';
    final container = ProviderContainer(
      overrides: [
        navigationItemsStateProvider.overrideWithValue(
          NavigationItemsState(
            value: [
              NavigationItem(
                icon: const Icon(Icons.space_dashboard),
                label: PageLabel.dashboard,
                builder: (_) => CommonScaffold(
                  title: 'Search page',
                  searchState: AppBarSearchState(
                    onSearch: (value) {
                      query = value;
                    },
                  ),
                  body: const SizedBox(),
                ),
              ),
              NavigationItem(
                icon: const Icon(Icons.construction),
                label: PageLabel.tools,
                builder: (_) => const SizedBox.shrink(),
              ),
            ],
          ),
        ),
      ],
    );
    addTearDown(container.dispose);
    globalState.container = container;
    container.read(viewSizeProvider.notifier).value = const Size(500, 800);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const _TestApp(child: HomePage()),
      ),
    );
    await tester.pump();

    await tester.tap(find.byIcon(Icons.search));
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'needle');
    expect(query, 'needle');

    final businessMenu = find.byKey(
      const ValueKey('fengwo-mobile-business-menu'),
    );
    await tester.tap(
      find.descendant(
        of: businessMenu,
        matching: find.byIcon(Icons.grid_view_rounded),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byKey(const ValueKey('fengwo-mobile-mine-sheet')),
        matching: find.byIcon(Icons.person_outline_rounded),
      ),
    );
    await tester.pumpAndSettle();
    expect(query, isEmpty);
    final homeIcon = find.descendant(
      of: businessMenu,
      matching: find.byIcon(Icons.home_outlined),
    );
    await tester.tap(homeIcon);
    await tester.pumpAndSettle();

    expect(find.byType(TextField), findsNothing);
  });

  testWidgets('desktop nested route inherits home page activity', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    var query = '';
    final container = ProviderContainer(
      overrides: [
        navigationItemsStateProvider.overrideWithValue(
          NavigationItemsState(
            value: [
              NavigationItem(
                icon: const Icon(Icons.space_dashboard),
                label: PageLabel.dashboard,
                builder: (_) => _NestedSearchLauncher(
                  onSearch: (value) {
                    query = value;
                  },
                ),
              ),
              NavigationItem(
                icon: const Icon(Icons.construction),
                label: PageLabel.tools,
                builder: (_) => const SizedBox.shrink(),
              ),
            ],
          ),
        ),
      ],
    );
    addTearDown(container.dispose);
    globalState.container = container;
    container.read(viewSizeProvider.notifier).value = const Size(1200, 800);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const _TestApp(child: HomePage()),
      ),
    );
    await tester.pump();

    await tester.tap(find.text('Open nested search'));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.search));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'needle');
    expect(query, 'needle');

    final navigationRail = find.byType(NavigationRail);
    await tester.tap(
      find.descendant(
        of: navigationRail,
        matching: find.byIcon(Icons.construction),
      ),
    );
    await tester.pumpAndSettle();
    expect(query, isEmpty);

    await tester.tap(
      find.descendant(
        of: navigationRail,
        matching: find.byIcon(Icons.space_dashboard),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Nested search'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
  });

  testWidgets(
    'desktop tabbing past page content does not scroll the PageView',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      Widget pageContent(String label) {
        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('page:$label'),
              const SizedBox(height: 16),
              TextButton(onPressed: () {}, child: const Text('button')),
            ],
          ),
        );
      }

      final container = ProviderContainer(
        overrides: [
          navigationItemsStateProvider.overrideWithValue(
            NavigationItemsState(
              value: [
                NavigationItem(
                  icon: const Icon(Icons.space_dashboard),
                  label: PageLabel.dashboard,
                  builder: (_) => pageContent('dashboard'),
                ),
                NavigationItem(
                  icon: const Icon(Icons.folder),
                  label: PageLabel.profiles,
                  builder: (_) => pageContent('profiles'),
                ),
              ],
            ),
          ),
        ],
      );
      addTearDown(container.dispose);
      globalState.container = container;
      container.read(viewSizeProvider.notifier).value = const Size(1200, 800);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const _TestApp(child: HomePage()),
        ),
      );
      await tester.pump();
      expect(find.byType(NavigationRail), findsOneWidget);

      Finder railIcon(IconData icon) => find.descendant(
        of: find.byType(NavigationRail),
        matching: find.byIcon(icon),
      );

      // Visit another page so its content stays alive in the PageView cache.
      await tester.tap(railIcon(Icons.folder));
      await tester.pumpAndSettle();
      expect(container.read(currentPageLabelProvider), PageLabel.profiles);
      await tester.tap(railIcon(Icons.space_dashboard));
      await tester.pumpAndSettle();
      expect(container.read(currentPageLabelProvider), PageLabel.dashboard);

      bool focusInRail() {
        final context = FocusManager.instance.primaryFocus?.context;
        return context?.findAncestorWidgetOfExactType<NavigationRail>() != null;
      }

      for (var i = 0; i < 40 && !focusInRail(); i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();
        expect(
          container.read(currentPageLabelProvider),
          PageLabel.dashboard,
          reason: 'tab $i flipped the page',
        );
      }
      expect(focusInRail(), isTrue);
      expect(
        find.text('page:profiles').hitTestable(),
        findsNothing,
        reason: 'focus traversal scrolled the PageView to another page',
      );
      expect(tester.takeException(), isNull);
    },
  );
}

class _TestApp extends StatelessWidget {
  final Widget child;

  const _TestApp({required this.child});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
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

class _ThemeManagedTestApp extends StatelessWidget {
  const _ThemeManagedTestApp();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: globalState.navigatorKey,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.delegate.supportedLocales,
      builder: (_, child) => ThemeManager(child: child!),
      home: const HomePage(),
    );
  }
}

class _StatefulContent extends StatefulWidget {
  const _StatefulContent({super.key});

  @override
  State<_StatefulContent> createState() => _StatefulContentState();
}

class _StatefulContentState extends State<_StatefulContent> {
  var _count = 0;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
      leading: const SizedBox(width: 80),
      title: TextButton(
        onPressed: () {
          setState(() {
            _count++;
          });
        },
        child: Text('count: $_count'),
      ),
    );
  }
}

class _NestedSearchLauncher extends StatelessWidget {
  final ValueChanged<String> onSearch;

  const _NestedSearchLauncher({required this.onSearch});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: FilledButton(
        onPressed: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => CommonScaffold(
                title: 'Nested search',
                searchState: AppBarSearchState(onSearch: onSearch),
                body: const SizedBox(),
              ),
            ),
          );
        },
        child: const Text('Open nested search'),
      ),
    );
  }
}

class _HomeTestProfiles extends Profiles {
  final List<Profile> initial;

  _HomeTestProfiles(this.initial);

  @override
  List<Profile> build() => initial;
}

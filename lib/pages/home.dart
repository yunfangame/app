import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/manager/app_manager.dart';
import 'package:fl_clash/models/common.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/state.dart';
import 'package:fl_clash/widgets/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

typedef OnSelected = void Function(int index);

class HomePage extends ConsumerWidget {
  const HomePage({super.key});

  void _handleToPage(PageLabel pageLabel) {
    globalState.container
        .read(currentPageLabelProvider.notifier)
        .toPage(pageLabel);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hasViewSize = ref.watch(
      viewSizeProvider.select((size) => !size.isEmpty),
    );
    if (!hasViewSize) {
      return const SizedBox.shrink();
    }
    return XboardAnnouncementCenterHost(
      child: HomeBackScopeContainer(
        child: AppSidebarContainer(
          child: Material(
            color: context.colorScheme.surface,
            child: Consumer(
              builder: (context, ref, child) {
                final state = ref.watch(navigationStateProvider);
                final isMobile = state.viewMode == ViewMode.mobile;
                final navigationItems = state.navigationItems;
                final currentIndex = state.currentIndex;
                final bottomNavigationBar = NavigationBarTheme(
                  data: _NavigationBarDefaultsM3(context),
                  child: _FengWoMobileNavigationBar(
                    navigationItems: navigationItems,
                    currentIndex: currentIndex,
                    onSelected: _handleToPage,
                  ),
                );
                return Column(
                  children: [
                    if (!isMobile)
                      ValueListenableBuilder<int>(
                        valueListenable:
                            globalState.xboardSessionRevisionNotifier,
                        builder: (context, revision, _) =>
                            FengWoGlobalAccountHeader(
                              key: ValueKey(
                                'fengwo-global-account-header-$revision',
                              ),
                              subscription: globalState.xboardSubscription,
                            ),
                      ),
                    ValueListenableBuilder<bool>(
                      valueListenable: globalState.offlineModeNotifier,
                      builder: (context, offline, _) => offline
                          ? const _OfflineModeBanner()
                          : const SizedBox.shrink(),
                    ),
                    Flexible(
                      flex: 1,
                      child: FocusTraversalGroup(
                        policy: PageTraversalPolicy(),
                        child: MediaQuery.removePadding(
                          removeTop: false,
                          removeBottom: isMobile,
                          removeLeft: isMobile,
                          removeRight: isMobile,
                          context: context,
                          child: child!,
                        ),
                      ),
                    ),
                    AnimatedVisibility.bottomNavigation(
                      visible: isMobile,
                      child: MediaQuery.removePadding(
                        removeTop: true,
                        removeBottom: false,
                        removeLeft: true,
                        removeRight: true,
                        context: context,
                        child: bottomNavigationBar,
                      ),
                    ),
                  ],
                );
              },
              child: Consumer(
                builder: (_, ref, _) {
                  final navigationItems = ref
                      .watch(currentNavigationItemsStateProvider)
                      .value;
                  final isMobile = ref.watch(isMobileViewProvider);
                  return ValueListenableBuilder<bool>(
                    valueListenable: globalState.offlineModeNotifier,
                    builder: (context, offline, _) => _HomePageView(
                      key: ValueKey('home-page-view-$offline'),
                      navigationItems: navigationItems,
                      pageBuilder: (_, index) {
                        final navigationItem = navigationItems[index];
                        final navigationView = navigationItem.builder(context);
                        final scopedView = PageFocusScope(
                          child: navigationView,
                        );
                        final view = KeepScope(
                          key: ValueKey(navigationItem.label),
                          keep: navigationItem.keep,
                          child: isMobile
                              ? scopedView
                              : Navigator(
                                  key: ValueKey(
                                    '${navigationItem.label.name}_navigator',
                                  ),
                                  pages: [MaterialPage(child: scopedView)],
                                  onDidRemovePage: (_) {},
                                ),
                        );
                        return Consumer(
                          key: ValueKey(navigationItem.label),
                          builder: (_, ref, child) {
                            final isActive = ref.watch(
                              currentPageLabelProvider.select(
                                (label) => label == navigationItem.label,
                              ),
                            );
                            return PageActivityScope(
                              isActive: isActive,
                              child: ExcludeFocus(
                                excluding: !isActive,
                                child: child!,
                              ),
                            );
                          },
                          child: view,
                        );
                      },
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _OfflineModeBanner extends StatefulWidget {
  const _OfflineModeBanner();

  @override
  State<_OfflineModeBanner> createState() => _OfflineModeBannerState();
}

class _OfflineModeBannerState extends State<_OfflineModeBanner> {
  bool _busy = false;

  Future<void> _restore() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await globalState.restoreOnlineMode?.call();
    } catch (error) {
      if (mounted) context.showNotifier(error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colorScheme;
    return Material(
      key: const ValueKey('offline-mode-banner'),
      color: const Color(0xFFFFB020).withValues(alpha: .14),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            const Icon(Icons.wifi_off_rounded, color: Color(0xFFE09300)),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                context.appLocalizations.offlineModeBanner,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: context.textTheme.bodyMedium?.copyWith(
                  color: colors.onSurface,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            TextButton(
              key: const ValueKey('offline-banner-restore-button'),
              onPressed: _busy ? null : _restore,
              child: Text(
                _busy
                    ? context.appLocalizations.restoringOnline
                    : context.appLocalizations.restoreOnline,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FengWoMobileMenuItem {
  final IconData icon;
  final String label;
  final PageLabel? pageLabel;

  const _FengWoMobileMenuItem({
    required this.icon,
    required this.label,
    this.pageLabel,
  });
}

class _FengWoMobileNavigationBar extends StatefulWidget {
  final List<NavigationItem> navigationItems;
  final int currentIndex;
  final ValueChanged<PageLabel> onSelected;

  const _FengWoMobileNavigationBar({
    required this.navigationItems,
    required this.currentIndex,
    required this.onSelected,
  });

  @override
  State<_FengWoMobileNavigationBar> createState() =>
      _FengWoMobileNavigationBarState();
}

class _FengWoMobileNavigationBarState
    extends State<_FengWoMobileNavigationBar> {
  late final ScrollController _scrollController;
  double _itemExtent = 96;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
  }

  @override
  void didUpdateWidget(covariant _FengWoMobileNavigationBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.currentIndex != widget.currentIndex ||
        oldWidget.navigationItems != widget.navigationItems) {
      _scheduleSelectedItemVisibility();
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  PageLabel get _currentLabel {
    return widget.currentIndex >= 0 &&
            widget.currentIndex < widget.navigationItems.length
        ? widget.navigationItems[widget.currentIndex].label
        : PageLabel.dashboard;
  }

  List<_FengWoMobileMenuItem> _entries(BuildContext context) {
    final l10n = context.appLocalizations;
    return <_FengWoMobileMenuItem>[
      _FengWoMobileMenuItem(
        icon: Icons.home_outlined,
        label: l10n.acceleratorHome,
        pageLabel: PageLabel.dashboard,
      ),
      _FengWoMobileMenuItem(
        icon: Icons.shopping_cart_outlined,
        label: l10n.purchasePlan,
        pageLabel: PageLabel.profiles,
      ),
      _FengWoMobileMenuItem(
        icon: Icons.tune_rounded,
        label: l10n.nodeStatus,
        pageLabel: PageLabel.proxies,
      ),
      _FengWoMobileMenuItem(
        icon: Icons.show_chart_rounded,
        label: l10n.realTimeConnections,
        pageLabel: PageLabel.connections,
      ),
      _FengWoMobileMenuItem(
        icon: Icons.pie_chart_outline_rounded,
        label: l10n.trafficDetails,
        pageLabel: PageLabel.traffic,
      ),
      _FengWoMobileMenuItem(
        icon: Icons.receipt_long_outlined,
        label: l10n.myOrders,
        pageLabel: PageLabel.orders,
      ),
      _FengWoMobileMenuItem(
        icon: Icons.card_giftcard_outlined,
        label: l10n.invitePromotion,
        pageLabel: PageLabel.invite,
      ),
      _FengWoMobileMenuItem(
        icon: Icons.person_outline_rounded,
        label: l10n.personalCenter,
        pageLabel: PageLabel.tools,
      ),
      _FengWoMobileMenuItem(
        icon: Icons.settings_outlined,
        label: l10n.advancedSettings,
        pageLabel: PageLabel.resources,
      ),
      _FengWoMobileMenuItem(
        icon: Icons.business_center_outlined,
        label: l10n.practicalTools,
        pageLabel: PageLabel.practicalTools,
      ),
    ];
  }

  void _scheduleSelectedItemVisibility() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      final selectedIndex = _entries(
        context,
      ).indexWhere((entry) => entry.pageLabel == _currentLabel);
      if (selectedIndex < 0) return;
      final position = _scrollController.position;
      final itemStart = selectedIndex * _itemExtent;
      final itemEnd = itemStart + _itemExtent;
      final viewportStart = position.pixels;
      final viewportEnd = viewportStart + position.viewportDimension;
      double? target;
      if (itemStart < viewportStart) {
        target = itemStart - 8;
      } else if (itemEnd > viewportEnd) {
        target = itemEnd - position.viewportDimension + 8;
      }
      if (target == null) return;
      _scrollController.animateTo(
        target.clamp(position.minScrollExtent, position.maxScrollExtent),
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.appLocalizations;
    final entries = _entries(context);
    final selectedIndex = entries.indexWhere(
      (entry) => entry.pageLabel == _currentLabel,
    );
    final viewportWidth = MediaQuery.sizeOf(context).width;
    final baseExtent = Localizations.localeOf(context).languageCode == 'zh'
        ? 92.0
        : 104.0;
    _itemExtent = MediaQuery.textScalerOf(
      context,
    ).scale(baseExtent).clamp(92.0, 126.0);
    final contentWidth = entries.length * _itemExtent;
    final barWidth = viewportWidth > contentWidth
        ? viewportWidth
        : contentWidth;
    _scheduleSelectedItemVisibility();
    return SingleChildScrollView(
      key: const ValueKey('fengwo-mobile-business-menu-scroll'),
      controller: _scrollController,
      scrollDirection: Axis.horizontal,
      physics: const ClampingScrollPhysics(),
      child: SizedBox(
        width: barWidth,
        child: NavigationBar(
          key: const ValueKey('fengwo-mobile-business-menu'),
          destinations: entries
              .map(
                (entry) => NavigationDestination(
                  icon: Icon(entry.icon),
                  label: entry.label,
                ),
              )
              .toList(growable: false),
          selectedIndex: selectedIndex < 0 ? 0 : selectedIndex,
          onDestinationSelected: (index) {
            final target = entries[index].pageLabel;
            final available =
                target != null &&
                widget.navigationItems.any((item) => item.label == target);
            if (!available) {
              globalState.showNotifier(l10n.featureComingSoon);
              return;
            }
            widget.onSelected(target);
          },
        ),
      ),
    );
  }
}

class _HomePageView extends ConsumerStatefulWidget {
  final IndexedWidgetBuilder pageBuilder;
  final List<NavigationItem> navigationItems;

  const _HomePageView({
    super.key,
    required this.pageBuilder,
    required this.navigationItems,
  });

  @override
  ConsumerState createState() => _HomePageViewState();
}

class _HomePageViewState extends ConsumerState<_HomePageView> {
  late PageController _pageController;

  @override
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: _pageIndex);
    ref.listenManual(currentPageLabelProvider, (prev, next) {
      if (prev != next) {
        _toPage(next);
      }
    });
  }

  @override
  void didUpdateWidget(covariant _HomePageView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.navigationItems.length != widget.navigationItems.length) {
      _updatePageController();
    }
  }

  int get _pageIndex {
    final pageLabel = ref.read(currentPageLabelProvider);
    return widget.navigationItems.indexWhere((item) => item.label == pageLabel);
  }

  Future<void> _toPage(
    PageLabel pageLabel, [
    bool ignoreAnimateTo = false,
  ]) async {
    if (!mounted) {
      return;
    }
    final index = widget.navigationItems.indexWhere(
      (item) => item.label == pageLabel,
    );
    if (index == -1) {
      return;
    }
    final isAnimateToPage = ref.read(appSettingProvider).isAnimateToPage;
    final isMobile = ref.read(isMobileViewProvider);
    if (isAnimateToPage && isMobile && !ignoreAnimateTo) {
      await _pageController.animateToPage(
        index,
        duration: kTabScrollDuration,
        curve: Curves.easeOut,
      );
    } else {
      _pageController.jumpToPage(index);
    }
  }

  void _updatePageController() {
    final pageLabel = ref.read(currentPageLabelProvider);
    _toPage(pageLabel, true);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final itemCount = ref.watch(
      currentNavigationItemsStateProvider.select((state) => state.value.length),
    );
    return PageView.builder(
      controller: _pageController,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: itemCount,
      findChildIndexCallback: (key) {
        if (key is! ValueKey<PageLabel>) {
          return null;
        }
        final index = widget.navigationItems.indexWhere(
          (item) => item.label == key.value,
        );
        return index == -1 ? null : index;
      },
      itemBuilder: (context, index) {
        return widget.pageBuilder(context, index);
      },
    );
  }
}

class _NavigationBarDefaultsM3 extends NavigationBarThemeData {
  _NavigationBarDefaultsM3(this.context)
    : super(
        height: 80.0,
        elevation: 3.0,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      );

  final BuildContext context;
  late final ColorScheme _colors = Theme.of(context).colorScheme;
  late final TextTheme _textTheme = Theme.of(context).textTheme;

  @override
  Color? get backgroundColor => _colors.surfaceContainer;

  @override
  Color? get shadowColor => Colors.transparent;

  @override
  Color? get surfaceTintColor => Colors.transparent;

  @override
  WidgetStateProperty<IconThemeData?>? get iconTheme {
    return WidgetStateProperty.resolveWith((Set<WidgetState> states) {
      return IconThemeData(
        size: 24.0,
        color: states.contains(WidgetState.disabled)
            ? _colors.onSurfaceVariant.opacity38
            : states.contains(WidgetState.selected)
            ? _colors.onSecondaryContainer
            : _colors.onSurfaceVariant,
      );
    });
  }

  @override
  Color? get indicatorColor => _colors.secondaryContainer;

  @override
  ShapeBorder? get indicatorShape => const StadiumBorder();

  @override
  WidgetStateProperty<TextStyle?>? get labelTextStyle {
    return WidgetStateProperty.resolveWith((Set<WidgetState> states) {
      final TextStyle style = _textTheme.labelMedium!;
      return style.apply(
        overflow: TextOverflow.ellipsis,
        color: states.contains(WidgetState.disabled)
            ? _colors.onSurfaceVariant.opacity38
            : states.contains(WidgetState.selected)
            ? _colors.onSurface
            : _colors.onSurfaceVariant,
      );
    });
  }
}

class HomeBackScopeContainer extends ConsumerWidget {
  final Widget child;

  const HomeBackScopeContainer({super.key, required this.child});

  @override
  Widget build(BuildContext context, ref) {
    return CommonPopScope(
      onPop: (context) async {
        final pageLabel = ref.read(currentPageLabelProvider);
        final realContext =
            GlobalObjectKey(pageLabel).currentContext ?? context;
        final canPop = Navigator.canPop(realContext);
        if (canPop) {
          Navigator.of(realContext).pop();
        } else {
          await globalState.container
              .read(systemActionProvider.notifier)
              .handleClose();
        }
        return false;
      },
      child: child,
    );
  }
}

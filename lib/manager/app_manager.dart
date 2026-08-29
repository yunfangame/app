import 'dart:async';

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/core/controller.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/state.dart';
import 'package:fl_clash/widgets/animated_visibility.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

String fengWoNavigationLabel(PageLabel pageLabel) {
  return Intl.message(switch (pageLabel) {
    PageLabel.dashboard => 'acceleratorHome',
    PageLabel.proxies => 'nodeStatus',
    PageLabel.profiles => 'purchasePlan',
    PageLabel.connections => 'realTimeConnections',
    PageLabel.traffic => 'trafficDetails',
    PageLabel.orders => 'myOrders',
    PageLabel.invite => 'invitePromotion',
    PageLabel.tools => 'personalCenter',
    PageLabel.resources => 'advancedSettings',
    PageLabel.practicalTools => 'practicalTools',
    _ => pageLabel.name,
  });
}

class AppStateManager extends ConsumerStatefulWidget {
  final Widget child;

  const AppStateManager({super.key, required this.child});

  @override
  ConsumerState<AppStateManager> createState() => _AppStateManagerState();
}

class _AppStateManagerState extends ConsumerState<AppStateManager>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    ref.listenManual(checkIpProvider, (prev, next) {
      if (prev != next && next.a && next.c) {
        ref.read(networkDetectionProvider.notifier).startCheck();
      }
    });
    ref.listenManual(configProvider, (prev, next) {
      if (prev != next) {
        globalState.container
            .read(storeActionProvider.notifier)
            .savePreferencesDebounce();
      }
    });
    ref.listenManual(needUpdateGroupsProvider, (prev, next) {
      if (prev != next) {
        globalState.container
            .read(proxiesActionProvider.notifier)
            .updateGroupsDebounce();
      }
    });
    ref.listenManual(suspendProvider, (prev, next) {
      final isStart = ref.read(isStartProvider);
      if (prev != next && isStart) {
        debouncer.call(FunctionTag.suspend, () async {
          if (next == true) {
            await coreController.stopListener();
          } else {
            await coreController.startListener();
          }
          ref.read(checkIpNumProvider.notifier).add();
        });
      }
    });
    if (system.isMacOS) {
      ref.listenManual(autoSetSystemDnsStateProvider, (prev, next) async {
        if (prev == next) {
          return;
        }
        if (next.a == true && next.b == true) {
          macOS?.updateDns(false);
        } else {
          macOS?.updateDns(true);
        }
      });
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Future<void> didChangeAppLifecycleState(AppLifecycleState state) async {
    commonPrint.log('$state');
    if (state == AppLifecycleState.resumed) {
      permissions.check();
      render?.resume();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final ref = globalState.container;
        ref.read(setupActionProvider.notifier).tryCheckIp();
      });
    }
  }

  @override
  void didChangePlatformBrightness() {
    globalState.container.read(themeActionProvider.notifier).updateBrightness();
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerHover: (_) {
        render?.resume();
      },
      child: widget.child,
    );
  }
}

class AppEnvManager extends StatelessWidget {
  final Widget child;

  const AppEnvManager({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    if (kDebugMode) {
      if (globalState.isPre) {
        return Banner(
          message: 'DEBUG',
          location: BannerLocation.topEnd,
          child: child,
        );
      }
    }
    if (globalState.isPre) {
      return Banner(
        message: globalState.appEnv.toUpperCase(),
        location: BannerLocation.topEnd,
        child: child,
      );
    }
    return child;
  }
}

class AppSidebarContainer extends ConsumerWidget {
  final Widget child;

  const AppSidebarContainer({super.key, required this.child});

  Widget _buildBackground({
    required BuildContext context,
    required Widget child,
  }) {
    return Material(color: context.colorScheme.surfaceContainer, child: child);
  }

  void _updateSideBarWidth(WidgetRef ref, double contentWidth) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(sideWidthProvider.notifier).value =
          ref.read(viewSizeProvider.select((state) => state.width)) -
          contentWidth;
    });
  }

  void _handleToPage(PageLabel pageLabel) {
    final focusNode = FocusManager.instance.primaryFocus;
    final preserveNavigationFocus =
        focusNode?.context?.findAncestorWidgetOfExactType<NavigationRail>() !=
        null;
    globalState.container
        .read(currentPageLabelProvider.notifier)
        .toPage(pageLabel);
    if (!preserveNavigationFocus || focusNode == null) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (focusNode.context != null && focusNode.canRequestFocus) {
        focusNode.requestFocus();
      }
    });
  }

  Future<void> _handleLogout(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        icon: const Icon(Icons.logout_rounded),
        title: Text(dialogContext.appLocalizations.logoutConfirmTitle),
        content: Text(dialogContext.appLocalizations.logoutConfirmMessage),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(dialogContext.appLocalizations.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(dialogContext.appLocalizations.logoutAccount),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    try {
      final logout = globalState.logoutXboard;
      if (logout != null) {
        await logout();
      } else {
        globalState.clearXboardSession();
      }
    } catch (error) {
      if (context.mounted) context.showNotifier(error.toString());
    }
  }

  Widget _buildSidebarFooter(BuildContext context) {
    final colors = context.colorScheme;
    final border = colors.outlineVariant.withValues(alpha: .65);
    final tileColor = Color.alphaBlend(
      colors.primary.withValues(alpha: .025),
      colors.surface,
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _OfflineModeControl(tileColor: tileColor, borderColor: border),
          const SizedBox(height: 10),
          Material(
            color: tileColor,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
              side: BorderSide(color: border),
            ),
            child: InkWell(
              key: const ValueKey('fengwo-sidebar-logout'),
              onTap: () => _handleLogout(context),
              borderRadius: BorderRadius.circular(20),
              child: SizedBox(
                height: 56,
                child: Row(
                  children: [
                    const SizedBox(width: 14),
                    Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: colors.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        Icons.logout_rounded,
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        context.appLocalizations.logoutAccount,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: context.textTheme.labelLarge?.copyWith(
                          color: colors.onSurfaceVariant,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final navigationState = ref.watch(navigationStateProvider);
    final navigationItems = navigationState.navigationItems;
    final isMobileView = navigationState.viewMode == ViewMode.mobile;
    final currentIndex = navigationState.currentIndex;
    return Container(
      color: context.colorScheme.surfaceContainer,
      child: Row(
        children: [
          AnimatedVisibility.sidebar(
            visible: !isMobileView,
            child: SizedBox(
              width: 222,
              child: _buildBackground(
                context: context,
                child: SafeArea(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      if (system.isMacOS) const SizedBox(height: 22),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(18, 14, 18, 18),
                        child: Row(
                          children: [
                            Image.asset(
                              'assets/images/brand_logo.png',
                              width: 46,
                              height: 46,
                              fit: BoxFit.contain,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                Intl.message('brandName'),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: context.textTheme.titleMedium?.copyWith(
                                  color: context.colorScheme.onSurface,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Expanded(
                        child: ScrollConfiguration(
                          behavior: HiddenBarScrollBehavior(),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: NavigationRail(
                                  scrollable: true,
                                  extended: true,
                                  minWidth: 72,
                                  minExtendedWidth: 222,
                                  backgroundColor: Colors.transparent,
                                  selectedLabelTextStyle: context
                                      .textTheme
                                      .labelLarge!
                                      .copyWith(
                                        color: context.colorScheme.primary,
                                        fontWeight: FontWeight.w800,
                                      ),
                                  unselectedLabelTextStyle: context
                                      .textTheme
                                      .labelLarge!
                                      .copyWith(
                                        color: context
                                            .colorScheme
                                            .onSurfaceVariant,
                                        fontWeight: FontWeight.w600,
                                      ),
                                  selectedIconTheme: IconThemeData(
                                    color: context.colorScheme.primary,
                                    size: 26,
                                  ),
                                  unselectedIconTheme: IconThemeData(
                                    color: context.colorScheme.onSurfaceVariant,
                                    size: 25,
                                  ),
                                  indicatorColor: context
                                      .colorScheme
                                      .primaryContainer
                                      .withValues(alpha: .8),
                                  destinations: navigationItems
                                      .map(
                                        (e) => NavigationRailDestination(
                                          icon: e.icon,
                                          label: Text(
                                            fengWoNavigationLabel(e.label),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      )
                                      .toList(),
                                  onDestinationSelected: (index) {
                                    _handleToPage(navigationItems[index].label);
                                  },
                                  selectedIndex: currentIndex,
                                  labelType: NavigationRailLabelType.none,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      _buildSidebarFooter(context),
                    ],
                  ),
                ),
              ),
            ),
          ),
          Expanded(
            flex: 1,
            child: ClipRect(
              child: LayoutBuilder(
                builder: (_, constraints) {
                  _updateSideBarWidth(ref, constraints.maxWidth);
                  return child;
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _OfflineModeControl extends StatefulWidget {
  const _OfflineModeControl({
    required this.tileColor,
    required this.borderColor,
  });

  final Color tileColor;
  final Color borderColor;

  @override
  State<_OfflineModeControl> createState() => _OfflineModeControlState();
}

class _OfflineModeControlState extends State<_OfflineModeControl> {
  bool _busy = false;

  Future<void> _toggle(bool offline) async {
    if (_busy) return;
    final confirmed = offline
        ? await showDialog<bool>(
            context: context,
            builder: (_) => const _EnableOfflineModeDialog(),
          )
        : await showDialog<bool>(
            context: context,
            builder: (dialogContext) => AlertDialog(
              icon: const Icon(Icons.cloud_sync_outlined),
              title: Text(dialogContext.appLocalizations.restoreOnline),
              content: Text(dialogContext.appLocalizations.offlineEntryHint),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext, false),
                  child: Text(dialogContext.appLocalizations.cancel),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(dialogContext, true),
                  child: Text(dialogContext.appLocalizations.restoreOnline),
                ),
              ],
            ),
          );
    if (confirmed != true || !mounted) return;
    setState(() => _busy = true);
    try {
      final callback = offline
          ? globalState.enableOfflineMode
          : globalState.restoreOnlineMode;
      final changed = await callback?.call() ?? false;
      if (!changed && mounted && offline) {
        context.showNotifier(context.appLocalizations.offlineCacheUnavailable);
      }
    } catch (error) {
      if (mounted) context.showNotifier(error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colorScheme;
    return ValueListenableBuilder<bool>(
      valueListenable: globalState.offlineModeNotifier,
      builder: (context, offline, _) => Material(
        key: const ValueKey('fengwo-sidebar-offline-mode'),
        color: widget.tileColor,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: widget.borderColor),
        ),
        child: InkWell(
          onTap: _busy ? null : () => _toggle(!offline),
          borderRadius: BorderRadius.circular(20),
          child: SizedBox(
            height: 70,
            child: Row(
              children: [
                const SizedBox(width: 12),
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: offline
                        ? const Color(0xFFFFB020).withValues(alpha: .16)
                        : colors.primaryContainer.withValues(alpha: .65),
                    borderRadius: BorderRadius.circular(13),
                  ),
                  child: Icon(
                    Icons.wifi_off_rounded,
                    color: offline ? const Color(0xFFE09300) : colors.primary,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        context.appLocalizations.offlineMode,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: context.textTheme.labelLarge?.copyWith(
                          color: colors.onSurface,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        _busy
                            ? context.appLocalizations.restoringOnline
                            : offline
                            ? context.appLocalizations.offlineModeEnabled
                            : context.appLocalizations.notEnabled,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: context.textTheme.labelSmall?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                Switch(
                  value: offline,
                  onChanged: _busy ? null : (_) => _toggle(!offline),
                ),
                const SizedBox(width: 6),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _EnableOfflineModeDialog extends StatelessWidget {
  const _EnableOfflineModeDialog();

  @override
  Widget build(BuildContext context) {
    final colors = context.colorScheme;
    final l10n = context.appLocalizations;
    return Dialog(
      insetPadding: const EdgeInsets.all(20),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(34)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 620),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(38, 32, 38, 30),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      color: colors.primaryContainer.withValues(alpha: .45),
                      shape: BoxShape.circle,
                      border: Border.all(color: colors.primaryContainer),
                    ),
                    child: Icon(
                      Icons.wifi_off_rounded,
                      color: colors.primary,
                      size: 38,
                    ),
                  ),
                  IconButton.filledTonal(
                    key: const ValueKey('offline-dialog-close'),
                    onPressed: () => Navigator.pop(context, false),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
              const SizedBox(height: 26),
              Text(
                l10n.enableOfflineTitle,
                textAlign: TextAlign.center,
                style: context.textTheme.headlineMedium?.copyWith(
                  color: colors.onSurface,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 18),
              Text(
                l10n.enableOfflineDescription,
                style: context.textTheme.titleMedium?.copyWith(
                  color: colors.onSurfaceVariant,
                  height: 1.55,
                ),
              ),
              const SizedBox(height: 24),
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: colors.primaryContainer.withValues(alpha: .22),
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(color: colors.primaryContainer),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.offlineModeDescriptionTitle,
                      style: context.textTheme.titleMedium?.copyWith(
                        color: colors.primary,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 14),
                    _OfflineDialogLine(
                      icon: Icons.storage_rounded,
                      text: l10n.offlineCacheContinues,
                    ),
                    _OfflineDialogLine(
                      icon: Icons.wifi_off_rounded,
                      text: l10n.offlineNoUpdates,
                    ),
                    _OfflineDialogLine(
                      icon: Icons.check_circle_outline_rounded,
                      text: l10n.offlineNetworkTools,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 28),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: Text(l10n.cancel),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: FilledButton.icon(
                      key: const ValueKey('enable-offline-mode-button'),
                      onPressed: () => Navigator.pop(context, true),
                      icon: const Icon(Icons.wifi_off_rounded),
                      label: Text(l10n.enableOfflineAction),
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFFE9A000),
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _OfflineDialogLine extends StatelessWidget {
  const _OfflineDialogLine({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 21, color: context.colorScheme.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: context.textTheme.bodyMedium?.copyWith(
                color: context.colorScheme.onSurfaceVariant,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

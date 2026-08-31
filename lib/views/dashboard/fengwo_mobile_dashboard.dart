import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/pages/customer_service.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/state.dart';
import 'package:fl_clash/views/dashboard/fengwo_desktop_dashboard.dart';
import 'package:fl_clash/views/dashboard/fengwo_node_selector.dart';
import 'package:fl_clash/views/dashboard/widgets/global_mode_confirmation.dart';
import 'package:fl_clash/views/proxies/common.dart';
import 'package:fl_clash/views/tools.dart';
import 'package:fl_clash/widgets/subscription_status_indicator.dart';
import 'package:fl_clash/widgets/fengwo_marquee.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

class FengWoMobileDashboard extends ConsumerWidget {
  const FengWoMobileDashboard({super.key});

  Group? _currentGroup(WidgetRef ref, Profile? profile) {
    final rawGroups = ref.watch(groupsProvider);
    final visibleGroups = ref.watch(currentGroupsStateProvider).value;
    if (visibleGroups.isEmpty) return null;
    final preferredName = profile?.currentGroupName;
    final visibleGroup = preferredName == null
        ? visibleGroups.first
        : visibleGroups.getGroup(preferredName) ?? visibleGroups.first;
    return rawGroups.getGroup(visibleGroup.name) ?? visibleGroup;
  }

  String _currentNode(Group? group, Profile? profile) {
    if (group == null) return '';
    return group
        .getCurrentSelectedName(profile?.selectedMap[group.name] ?? '')
        .takeFirstValid([group.realNow, group.name]);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.appLocalizations;
    final colors = _MobileDashboardColors.of(context);
    final isStart = ref.watch(isStartProvider);
    final profiles = ref.watch(profilesProvider);
    final profile = ref.watch(currentProfileProvider);
    final currentGroup = _currentGroup(ref, profile);
    final rawNodeName = _currentNode(currentGroup, profile);
    final nodeName = rawNodeName.takeFirstValid([l10n.proxiesEmpty]);
    final connectionDelay = rawNodeName.isEmpty
        ? null
        : ref.watch(
            connectionDelayProvider(
              proxyName: rawNodeName,
              testUrl: currentGroup?.testUrl,
            ),
          );
    final standardDelay = rawNodeName.isEmpty
        ? null
        : ref.watch(
            standardDelayProvider(
              proxyName: rawNodeName,
              testUrl: currentGroup?.testUrl,
            ),
          );
    final fallbackDelay = rawNodeName.isEmpty
        ? null
        : ref.watch(
            delayProvider(
              proxyName: rawNodeName,
              testUrl: currentGroup?.testUrl,
            ),
          );
    final delay = connectionDelay ?? standardDelay ?? fallbackDelay;
    final traffic = ref.watch(trafficsProvider).list.safeLast(const Traffic());
    final ipInfo = ref.watch(
      networkDetectionProvider.select((state) => state.originIpInfo),
    );
    final mapNodes = currentGroup == null
        ? const <FengWoWorldMapNode>[]
        : currentGroup.all.map((proxy) {
            final connectionDelay = ref.watch(
              connectionDelayProvider(
                proxyName: proxy.name,
                testUrl: currentGroup.testUrl,
              ),
            );
            final standardDelay = ref.watch(
              standardDelayProvider(
                proxyName: proxy.name,
                testUrl: currentGroup.testUrl,
              ),
            );
            final fallbackDelay = ref.watch(
              delayProvider(
                proxyName: proxy.name,
                testUrl: currentGroup.testUrl,
              ),
            );
            return FengWoWorldMapNode(
              name: proxy.name,
              delay: connectionDelay ?? standardDelay ?? fallbackDelay,
              connectionDelay: connectionDelay,
              standardDelay: standardDelay,
            );
          }).toList();
    final subscription = globalState.xboardSubscription;
    final xboardNodes = globalState.xboardNodes;
    final countryCount = xboardNodes.isEmpty
        ? mapNodes
              .map((node) => node.countryCode ?? node.name)
              .map(fengWoNodeCountryCode)
              .whereType<String>()
              .toSet()
              .length
        : xboardTagCount(xboardNodes);
    return Material(
      color: colors.background,
      child: SafeArea(
        bottom: false,
        child: ScrollConfiguration(
          behavior: const _MobileDashboardScrollBehavior(),
          child: SingleChildScrollView(
            key: const ValueKey('fengwo-mobile-dashboard-scroll'),
            physics: const ClampingScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _MobileHeader(colors: colors, subscription: subscription),
                const SizedBox(height: 14),
                _AccountStatusCard(
                  colors: colors,
                  subscription: subscription,
                  onPurchase: () => ref
                      .read(currentPageLabelProvider.notifier)
                      .toPage(PageLabel.profiles),
                ),
                FengWoMarqueeBar(
                  controller: globalState.xboardMarqueeController,
                  compact: true,
                  margin: const EdgeInsets.only(top: 14),
                  onMessageTap: (message) => openFengWoMarqueeMessage(
                    context: context,
                    ref: ref,
                    controller: globalState.xboardMarqueeController,
                    message: message,
                  ),
                ),
                const SizedBox(height: 22),
                Center(
                  child: _MobilePowerButton(
                    colors: colors,
                    isStart: isStart,
                    hasProfile: profiles.isNotEmpty,
                    onTap: profiles.isEmpty
                        ? null
                        : () => ref
                              .read(commonActionProvider.notifier)
                              .toggleRunning(),
                  ),
                ),
                const SizedBox(height: 12),
                _MobileRunningStatus(
                  colors: colors,
                  isStart: isStart,
                  hasProfile: profiles.isNotEmpty,
                ),
                const SizedBox(height: 16),
                _MobileModeSelector(colors: colors),
                const SizedBox(height: 14),
                _MobileWorldMapCard(
                  colors: colors,
                  isStart: isStart,
                  nodeName: rawNodeName,
                  ipInfo: ipInfo,
                  nodes: mapNodes,
                  countryCount: countryCount,
                ),
                const SizedBox(height: 16),
                _MobileNodeCard(
                  colors: colors,
                  isStart: isStart,
                  nodeName: nodeName,
                  delay: delay,
                  connectionDelay: connectionDelay,
                  standardDelay: standardDelay,
                  onOpenNodes: () => FengWoNodeSelector.show(context),
                  onRefresh: currentGroup == null
                      ? null
                      : () => delayTest(currentGroup.all, currentGroup.testUrl),
                ),
                const SizedBox(height: 14),
                _MobileTrafficCard(
                  colors: colors,
                  traffic: traffic,
                  subscription: subscription,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MobileDashboardScrollBehavior extends MaterialScrollBehavior {
  const _MobileDashboardScrollBehavior();

  @override
  Widget buildOverscrollIndicator(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) {
    return child;
  }

  @override
  ScrollPhysics getScrollPhysics(BuildContext context) {
    return const ClampingScrollPhysics();
  }
}

class _MobileDashboardColors {
  final Color background;
  final Color surface;
  final Color surfaceStrong;
  final Color primary;
  final Color primarySoft;
  final Color text;
  final Color muted;
  final Color outline;
  final Color success;
  final Color shadow;

  const _MobileDashboardColors({
    required this.background,
    required this.surface,
    required this.surfaceStrong,
    required this.primary,
    required this.primarySoft,
    required this.text,
    required this.muted,
    required this.outline,
    required this.success,
    required this.shadow,
  });

  factory _MobileDashboardColors.of(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dark = scheme.brightness == Brightness.dark;
    return _MobileDashboardColors(
      background: dark
          ? scheme.surfaceContainerLowest
          : Color.alphaBlend(
              scheme.primary.withValues(alpha: 0.035),
              scheme.surface,
            ),
      surface: dark ? scheme.surfaceContainer : scheme.surface,
      surfaceStrong: dark
          ? scheme.surfaceContainerHigh
          : scheme.surfaceContainerLow,
      primary: scheme.primary,
      primarySoft: scheme.primary.withValues(alpha: dark ? 0.24 : 0.11),
      text: scheme.onSurface,
      muted: scheme.onSurfaceVariant,
      outline: scheme.outlineVariant.withValues(alpha: dark ? 0.72 : 0.88),
      success: dark ? const Color(0xFF46E39C) : const Color(0xFF15BF70),
      shadow: Colors.black.withValues(alpha: dark ? 0.28 : 0.07),
    );
  }
}

class _MobileHeader extends StatelessWidget {
  final _MobileDashboardColors colors;
  final XboardSubscriptionData? subscription;

  const _MobileHeader({required this.colors, required this.subscription});

  @override
  Widget build(BuildContext context) {
    final email = subscription?.email.takeFirstValid(['--']) ?? '--';
    return Row(
      children: [
        Image.asset(
          'assets/images/brand_logo.png',
          width: 42,
          height: 42,
          fit: BoxFit.contain,
        ),
        const SizedBox(width: 9),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                context.appLocalizations.brandName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: colors.text,
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                email,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: colors.muted, fontSize: 11),
              ),
            ],
          ),
        ),
        SubscriptionStatusIndicator(subscription: subscription, size: 38),
        _MobileHeaderAction(
          key: const ValueKey('fengwo-mobile-language'),
          colors: colors,
          icon: Icons.translate_rounded,
          onTap: () => ToolLocaleSelector.show(context),
        ),
        _MobileHeaderAction(
          key: const ValueKey('fengwo-mobile-theme'),
          colors: colors,
          icon: Icons.palette_outlined,
          onTap: () => ToolThemeSelector.show(context),
        ),
        _MobileHeaderAction(
          key: const ValueKey('fengwo-mobile-support'),
          colors: colors,
          icon: Icons.headset_mic_outlined,
          onTap: () => CustomerServiceSheet.show(context),
        ),
        _MobileHeaderAction(
          key: const ValueKey('fengwo-mobile-announcements'),
          colors: colors,
          icon: Icons.notifications_none_rounded,
          onTap: () =>
              globalState.showXboardAnnouncements?.call(automatic: false),
        ),
      ],
    );
  }
}

class _MobileHeaderAction extends StatelessWidget {
  final _MobileDashboardColors colors;
  final IconData icon;
  final VoidCallback onTap;

  const _MobileHeaderAction({
    super.key,
    required this.colors,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return IconButton(
      visualDensity: VisualDensity.compact,
      constraints: const BoxConstraints.tightFor(width: 38, height: 42),
      padding: EdgeInsets.zero,
      color: colors.text,
      onPressed: onTap,
      icon: Icon(icon, size: 22),
    );
  }
}

class _AccountStatusCard extends StatelessWidget {
  final _MobileDashboardColors colors;
  final XboardSubscriptionData? subscription;
  final VoidCallback onPurchase;

  const _AccountStatusCard({
    required this.colors,
    required this.subscription,
    required this.onPurchase,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = context.appLocalizations;
    final planName =
        subscription?.plan?.name.takeFirstValid([l10n.noActivePlan]) ??
        l10n.noActivePlan;
    final expiresAt = subscription?.expiresAt;
    final expiry = subscription == null
        ? l10n.noActivePlan
        : subscription!.isUnlimitedTime
        ? l10n.unlimitedTime
        : DateFormat.yMd(
            Localizations.localeOf(context).toLanguageTag(),
          ).format(expiresAt!);
    final nextResetAt = subscription?.shouldShowNextPlanReset ?? false
        ? subscription!.nextResetAt
        : null;
    final nextReset = nextResetAt == null
        ? null
        : DateFormat.yMd(
            Localizations.localeOf(context).toLanguageTag(),
          ).format(nextResetAt);
    return _MobileCard(
      colors: colors,
      padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: colors.success.withValues(alpha: 0.14),
              shape: BoxShape.circle,
            ),
            child: Icon(
              subscription == null
                  ? Icons.person_outline_rounded
                  : Icons.check_circle_outline_rounded,
              color: subscription == null ? colors.muted : colors.success,
              size: 23,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  subscription == null ? l10n.noActivePlan : l10n.loggedIn,
                  style: TextStyle(
                    color: colors.text,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '$planName · $expiry',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: colors.muted, fontSize: 11),
                ),
                if (nextReset != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    l10n.nextPlanResetAt(nextReset),
                    key: const ValueKey('fengwo-mobile-next-plan-reset'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: colors.primary,
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          FilledButton.tonalIcon(
            key: const ValueKey('fengwo-mobile-purchase'),
            style: FilledButton.styleFrom(
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            ),
            onPressed: onPurchase,
            icon: const Icon(Icons.workspace_premium_outlined, size: 17),
            label: Text(l10n.purchasePlan),
          ),
        ],
      ),
    );
  }
}

class _MobilePowerButton extends StatelessWidget {
  final _MobileDashboardColors colors;
  final bool isStart;
  final bool hasProfile;
  final VoidCallback? onTap;

  const _MobilePowerButton({
    required this.colors,
    required this.isStart,
    required this.hasProfile,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = isStart ? colors.success : colors.primary;
    return Semantics(
      button: true,
      enabled: hasProfile,
      label: isStart
          ? context.appLocalizations.stopAcceleration
          : context.appLocalizations.startAcceleration,
      child: InkWell(
        key: const ValueKey('fengwo-mobile-power-button'),
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: AnimatedContainer(
          width: 154,
          height: 154,
          duration: const Duration(milliseconds: 260),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(
              colors: [
                color.withValues(alpha: isStart ? 0.96 : 0.24),
                color.withValues(alpha: isStart ? 0.64 : 0.06),
              ],
            ),
            border: Border.all(
              color: color.withValues(alpha: isStart ? 0.9 : 0.5),
              width: 3,
            ),
            boxShadow: [
              BoxShadow(
                color: color.withValues(alpha: isStart ? 0.42 : 0.14),
                blurRadius: isStart ? 40 : 22,
                spreadRadius: isStart ? 8 : 2,
              ),
            ],
          ),
          child: Icon(
            Icons.power_settings_new_rounded,
            color: isStart ? Colors.white : color,
            size: 56,
          ),
        ),
      ),
    );
  }
}

class _MobileRunningStatus extends ConsumerWidget {
  final _MobileDashboardColors colors;
  final bool isStart;
  final bool hasProfile;

  const _MobileRunningStatus({
    required this.colors,
    required this.isStart,
    required this.hasProfile,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.appLocalizations;
    final runTime = ref.watch(runTimeProvider);
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: isStart ? colors.success : colors.muted,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 7),
            Text(
              isStart ? l10n.connected : l10n.disconnected,
              style: TextStyle(
                color: isStart ? colors.success : colors.muted,
                fontSize: 17,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
        const SizedBox(height: 3),
        Text(
          hasProfile ? utils.getTimeText(runTime) : l10n.proxiesEmpty,
          style: TextStyle(color: colors.muted, fontSize: 12),
        ),
      ],
    );
  }
}

class _MobileModeSelector extends ConsumerWidget {
  final _MobileDashboardColors colors;

  const _MobileModeSelector({required this.colors});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.appLocalizations;
    final mode = ref.watch(
      patchClashConfigProvider.select((config) => config.mode),
    );
    final tunEnabled = ref.watch(
      patchClashConfigProvider.select((config) => config.tun.enable),
    );
    final skipGlobalModeConfirmation = ref.watch(
      appSettingProvider.select((state) => state.skipGlobalModeConfirmation),
    );
    return _MobileCard(
      colors: colors,
      padding: const EdgeInsets.all(5),
      child: Row(
        children: [
          Expanded(
            child: _MobileModeItem(
              colors: colors,
              icon: Icons.route_rounded,
              label: l10n.rule,
              selected: mode == Mode.rule,
              onTap: () =>
                  ref.read(setupActionProvider.notifier).changeMode(Mode.rule),
            ),
          ),
          Expanded(
            child: _MobileModeItem(
              key: const ValueKey('fengwo-mobile-global-mode'),
              colors: colors,
              icon: Icons.public_rounded,
              label: l10n.global,
              selected: mode == Mode.global,
              onTap: () {
                requestGlobalModeSwitch(
                  context,
                  ref,
                  skipConfirmation: skipGlobalModeConfirmation,
                );
              },
            ),
          ),
          Expanded(
            child: _MobileModeItem(
              colors: colors,
              icon: Icons.account_tree_outlined,
              label: l10n.tun,
              selected: tunEnabled,
              onTap: () => ref.read(systemActionProvider.notifier).updateTun(),
            ),
          ),
        ],
      ),
    );
  }
}

class _MobileModeItem extends StatelessWidget {
  final _MobileDashboardColors colors;
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _MobileModeItem({
    super.key,
    required this.colors,
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final foreground = selected ? Colors.white : colors.muted;
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: onTap,
      child: AnimatedContainer(
        height: 43,
        duration: const Duration(milliseconds: 180),
        decoration: BoxDecoration(
          color: selected ? colors.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 17, color: foreground),
            const SizedBox(width: 5),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: foreground,
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MobileWorldMapCard extends StatelessWidget {
  final _MobileDashboardColors colors;
  final bool isStart;
  final String nodeName;
  final IpInfo? ipInfo;
  final List<FengWoWorldMapNode> nodes;
  final int countryCount;

  const _MobileWorldMapCard({
    required this.colors,
    required this.isStart,
    required this.nodeName,
    required this.ipInfo,
    required this.nodes,
    required this.countryCount,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = context.appLocalizations;
    return _MobileCard(
      key: const ValueKey('fengwo-mobile-world-map-card'),
      colors: colors,
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.shield_outlined, color: colors.primary, size: 22),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  l10n.globalAccelerationNetwork,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: colors.text,
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                l10n.countriesCount(countryCount),
                key: const ValueKey('fengwo-mobile-map-country-count'),
                maxLines: 1,
                style: TextStyle(
                  color: colors.muted,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          AspectRatio(
            aspectRatio: 16 / 9,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: ColoredBox(
                color: colors.primarySoft.withValues(alpha: 0.34),
                child: FengWoWorldMap(
                  key: const ValueKey('fengwo-mobile-world-map'),
                  isStart: isStart,
                  showRoute: true,
                  interactive: true,
                  opacity: 0.82,
                  nodeName: nodeName,
                  ipInfo: ipInfo,
                  nodes: nodes,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MobileNodeCard extends StatelessWidget {
  final _MobileDashboardColors colors;
  final bool isStart;
  final String nodeName;
  final int? delay;
  final int? connectionDelay;
  final int? standardDelay;
  final VoidCallback onOpenNodes;
  final VoidCallback? onRefresh;

  const _MobileNodeCard({
    required this.colors,
    required this.isStart,
    required this.nodeName,
    required this.delay,
    required this.connectionDelay,
    required this.standardDelay,
    required this.onOpenNodes,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = context.appLocalizations;
    final delayText = switch (delay) {
      null || 0 => l10n.notTested,
      < 0 => l10n.timeout,
      final value => '$value ms',
    };
    final delayColor = switch (delay) {
      null || 0 => colors.muted,
      < 0 => const Color(0xFFE84C4C),
      <= 250 => colors.success,
      <= 400 => colors.primary,
      _ => const Color(0xFFF29C38),
    };
    return _MobileCard(
      key: const ValueKey('fengwo-mobile-node-card'),
      colors: colors,
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.wifi_rounded, color: colors.success, size: 24),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  l10n.connectionStatus,
                  style: TextStyle(
                    color: colors.text,
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                tooltip: l10n.delayTest,
                onPressed: onRefresh,
                icon: const Icon(Icons.refresh_rounded, size: 19),
              ),
              _MobileStatusPill(colors: colors, connected: isStart),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Container(
                width: 39,
                height: 39,
                decoration: BoxDecoration(
                  color: colors.primarySoft,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(Icons.public_rounded, color: colors.primary),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.currentNode,
                      style: TextStyle(color: colors.muted, fontSize: 11),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      nodeName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: colors.text,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 88),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      delayText,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: delayColor,
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    if (connectionDelay != null && standardDelay != null)
                      Text(
                        '${l10n.standardizedDelay} $standardDelay ms',
                        key: const ValueKey('fengwo-mobile-standardized-delay'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: colors.muted, fontSize: 9),
                      ),
                    TextButton(
                      key: const ValueKey('fengwo-mobile-switch-node'),
                      style: TextButton.styleFrom(
                        minimumSize: Size.zero,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 4,
                        ),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        visualDensity: VisualDensity.compact,
                      ),
                      onPressed: onOpenNodes,
                      child: Text(
                        l10n.switchNode,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MobileStatusPill extends StatelessWidget {
  final _MobileDashboardColors colors;
  final bool connected;

  const _MobileStatusPill({required this.colors, required this.connected});

  @override
  Widget build(BuildContext context) {
    final color = connected ? colors.success : colors.muted;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 5),
          Text(
            connected
                ? context.appLocalizations.connected
                : context.appLocalizations.disconnected,
            style: TextStyle(
              color: color,
              fontSize: 10,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _MobileTrafficCard extends StatelessWidget {
  final _MobileDashboardColors colors;
  final Traffic traffic;
  final XboardSubscriptionData? subscription;

  const _MobileTrafficCard({
    required this.colors,
    required this.traffic,
    required this.subscription,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = context.appLocalizations;
    final used = subscription?.usedGb;
    final remaining = subscription?.remainingGb;
    final total = subscription?.transferEnableGb;
    final progress = subscription == null || total == null || total <= 0
        ? null
        : (subscription!.usedGb / total).clamp(0, 1).toDouble();
    return _MobileCard(
      colors: colors,
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(
                Icons.pie_chart_outline_rounded,
                color: colors.primary,
                size: 22,
              ),
              const SizedBox(width: 8),
              Text(
                l10n.trafficDetails,
                style: TextStyle(
                  color: colors.text,
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          const SizedBox(height: 13),
          Row(
            children: [
              Expanded(
                child: _MobileTrafficMetric(
                  colors: colors,
                  icon: Icons.arrow_downward_rounded,
                  color: colors.primary,
                  label: l10n.download,
                  value: '${traffic.down.traffic.show}/s',
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _MobileTrafficMetric(
                  colors: colors,
                  icon: Icons.arrow_upward_rounded,
                  color: const Color(0xFF8A4DFF),
                  label: l10n.upload,
                  value: '${traffic.up.traffic.show}/s',
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            key: const ValueKey('fengwo-mobile-traffic-details'),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
            decoration: BoxDecoration(
              color: colors.surfaceStrong.withValues(alpha: 0.62),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: colors.outline),
            ),
            child: Row(
              children: [
                Expanded(
                  child: _MobileTrafficQuota(
                    colors: colors,
                    label: l10n.usedTrafficLabel,
                    value: used,
                  ),
                ),
                VerticalDivider(width: 14, color: colors.outline),
                Expanded(
                  child: _MobileTrafficQuota(
                    colors: colors,
                    label: l10n.remainingTrafficLabel,
                    value: remaining,
                  ),
                ),
                VerticalDivider(width: 14, color: colors.outline),
                Expanded(
                  child: _MobileTrafficQuota(
                    colors: colors,
                    label: l10n.totalTrafficLabel,
                    value: total,
                  ),
                ),
              ],
            ),
          ),
          if (progress != null) ...[
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                minHeight: 7,
                value: progress,
                backgroundColor: colors.outline.withValues(alpha: 0.5),
                color: colors.primary,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _MobileTrafficMetric extends StatelessWidget {
  final _MobileDashboardColors colors;
  final IconData icon;
  final Color color;
  final String label;
  final String value;

  const _MobileTrafficMetric({
    required this.colors,
    required this.icon,
    required this.color,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: colors.surfaceStrong.withValues(alpha: 0.72),
        border: Border.all(color: colors.outline),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            child: Icon(icon, color: Colors.white, size: 18),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: colors.muted, fontSize: 11),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: colors.text,
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MobileTrafficQuota extends StatelessWidget {
  final _MobileDashboardColors colors;
  final String label;
  final double? value;

  const _MobileTrafficQuota({
    required this.colors,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    final value = this.value;
    final valueText = value == null
        ? '--'
        : value.toStringAsFixed(value >= 100 ? 0 : 1);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(color: colors.muted, fontSize: 10),
        ),
        const SizedBox(height: 2),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            '$valueText GB',
            maxLines: 1,
            style: TextStyle(
              color: colors.text,
              fontSize: 14,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
      ],
    );
  }
}

class _MobileCard extends StatelessWidget {
  final _MobileDashboardColors colors;
  final EdgeInsetsGeometry padding;
  final Widget child;

  const _MobileCard({
    super.key,
    required this.colors,
    required this.padding,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: colors.surface.withValues(alpha: 0.96),
        border: Border.all(color: colors.outline),
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: colors.shadow,
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: child,
    );
  }
}

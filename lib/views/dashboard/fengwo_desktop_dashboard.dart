import 'dart:math' as math;

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/state.dart';
import 'package:fl_clash/views/dashboard/fengwo_node_selector.dart';
import 'package:fl_clash/views/dashboard/widgets/global_mode_confirmation.dart';
import 'package:fl_clash/views/proxies/common.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart' hide Path;

const _neonRouteColor = Color(0xFF39FF14);
const _staticWorldMapAsset = 'assets/images/world_map_static.png';
final _staticWorldMapBounds = LatLngBounds(
  const LatLng(-85.05112878, -180),
  const LatLng(85.05112878, 180),
);

class _NonRepeatingWebMercator extends Epsg3857 {
  const _NonRepeatingWebMercator();

  @override
  bool get replicatesWorldLongitude => false;
}

class FengWoWorldMapNode {
  final String name;
  final int? delay;
  final int? connectionDelay;
  final int? standardDelay;
  final String? countryCode;

  const FengWoWorldMapNode({
    required this.name,
    required this.delay,
    this.connectionDelay,
    this.standardDelay,
    this.countryCode,
  });
}

class FengWoWorldMap extends StatelessWidget {
  final bool isStart;
  final bool showRoute;
  final bool interactive;
  final double opacity;
  final String nodeName;
  final IpInfo? ipInfo;
  final List<FengWoWorldMapNode> nodes;

  const FengWoWorldMap({
    super.key,
    required this.isStart,
    required this.showRoute,
    required this.opacity,
    this.interactive = false,
    this.nodeName = '',
    this.ipInfo,
    this.nodes = const [],
  });

  @override
  Widget build(BuildContext context) {
    return _ThemedWorldMap(
      colors: _DashboardColors.of(context),
      isStart: isStart,
      showRoute: showRoute,
      interactive: interactive,
      opacity: opacity,
      nodeName: nodeName,
      ipInfo: ipInfo,
      nodes: nodes
          .map(
            (node) => _WorldNode(
              name: node.name,
              delay: node.delay,
              connectionDelay: node.connectionDelay,
              standardDelay: node.standardDelay,
              countryCode: node.countryCode,
            ),
          )
          .toList(growable: false),
    );
  }
}

class FengWoDesktopDashboard extends ConsumerWidget {
  const FengWoDesktopDashboard({super.key});

  Group? _currentGroup(WidgetRef ref, Profile? profile) {
    final groups = ref.watch(groupsProvider);
    if (groups.isEmpty) return null;
    final groupName = profile?.currentGroupName;
    return groupName == null
        ? groups.first
        : groups.getGroup(groupName) ?? groups.first;
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
    final colors = _DashboardColors.of(context);
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
    final trafficHistory = ref.watch(trafficsProvider).list;
    final traffic = trafficHistory.safeLast(const Traffic());
    final ipInfo = ref.watch(
      networkDetectionProvider.select((state) => state.ipInfo),
    );
    final subscription = globalState.xboardSubscription;
    final xboardNodes = globalState.xboardNodes;
    final totalNodeCount = xboardNodes.isEmpty
        ? currentGroup?.all.length ?? 0
        : xboardNodes.length;
    final countryCount = xboardNodes.isEmpty
        ? currentGroup?.all
                  .map((proxy) => fengWoNodeCountryCode(proxy.name))
                  .whereType<String>()
                  .toSet()
                  .length ??
              0
        : xboardTagCount(xboardNodes);
    return Material(
      color: colors.background,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final panelHeight = (constraints.maxHeight * 0.45).clamp(
            330.0,
            620.0,
          );
          return ClipRRect(
            borderRadius: const BorderRadius.only(
              bottomLeft: Radius.circular(34),
            ),
            child: ColoredBox(
              color: colors.contentBackground,
              child: Column(
                children: [
                  Expanded(
                    child: Stack(
                      children: [
                        Positioned.fill(
                          child: _HeroPanel(
                            colors: colors,
                            isStart: isStart,
                            hasProfile: profiles.isNotEmpty,
                            nodeCount: totalNodeCount,
                            reservedBottom: panelHeight + 24,
                            onToggle: profiles.isEmpty
                                ? null
                                : () => ref
                                      .read(commonActionProvider.notifier)
                                      .toggleRunning(),
                          ),
                        ),
                        Positioned(
                          left: 30,
                          right: 30,
                          bottom: 24,
                          height: panelHeight,
                          child: Row(
                            children: [
                              Expanded(
                                flex: 47,
                                child: _ConnectionStatusPanel(
                                  colors: colors,
                                  isStart: isStart,
                                  nodeName: nodeName,
                                  delay: delay,
                                  connectionDelay: connectionDelay,
                                  standardDelay: standardDelay,
                                  traffic: traffic,
                                  trafficHistory: trafficHistory,
                                  subscription: subscription,
                                  onOpenNodes: () =>
                                      FengWoNodeSelector.show(context),
                                  onRefresh: currentGroup == null
                                      ? null
                                      : () => delayTest(
                                          currentGroup.all,
                                          currentGroup.testUrl,
                                        ),
                                ),
                              ),
                              const SizedBox(width: 18),
                              Expanded(
                                flex: 53,
                                child: _GlobalNetworkPanel(
                                  colors: colors,
                                  nodeName: nodeName,
                                  isStart: isStart,
                                  ipInfo: ipInfo,
                                  countryCount: countryCount,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _DashboardColors {
  final Color background;
  final Color contentBackground;
  final Color surface;
  final Color surfaceStrong;
  final Color heroStart;
  final Color heroEnd;
  final Color primary;
  final Color primarySoft;
  final Color text;
  final Color muted;
  final Color outline;
  final Color success;
  final Color shadow;

  const _DashboardColors({
    required this.background,
    required this.contentBackground,
    required this.surface,
    required this.surfaceStrong,
    required this.heroStart,
    required this.heroEnd,
    required this.primary,
    required this.primarySoft,
    required this.text,
    required this.muted,
    required this.outline,
    required this.success,
    required this.shadow,
  });

  factory _DashboardColors.of(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dark = scheme.brightness == Brightness.dark;
    final primary = scheme.primary;
    final background = dark
        ? scheme.surface
        : Color.alphaBlend(primary.withValues(alpha: 0.025), scheme.surface);
    final contentBackground = dark
        ? scheme.surfaceContainerLowest
        : Color.alphaBlend(
            primary.withValues(alpha: 0.04),
            scheme.surfaceContainerLowest,
          );
    return _DashboardColors(
      background: background,
      contentBackground: contentBackground,
      surface: dark
          ? scheme.surfaceContainer
          : scheme.surfaceContainerLowest.withValues(alpha: 0.96),
      surfaceStrong: dark
          ? scheme.surfaceContainerHigh
          : scheme.surfaceContainerLow,
      heroStart: Color.alphaBlend(
        primary.withValues(alpha: dark ? 0.16 : 0.1),
        contentBackground,
      ),
      heroEnd: Color.alphaBlend(
        scheme.tertiary.withValues(alpha: dark ? 0.1 : 0.06),
        contentBackground,
      ),
      primary: primary,
      primarySoft: primary.withValues(alpha: dark ? 0.22 : 0.12),
      text: scheme.onSurface,
      muted: scheme.onSurfaceVariant,
      outline: scheme.outlineVariant.withValues(alpha: dark ? 0.7 : 0.8),
      success: dark ? const Color(0xFF46E39C) : const Color(0xFF15BF70),
      shadow: Colors.black.withValues(alpha: dark ? 0.32 : 0.08),
    );
  }
}

class _HeroPanel extends ConsumerWidget {
  final _DashboardColors colors;
  final bool isStart;
  final bool hasProfile;
  final int nodeCount;
  final double reservedBottom;
  final VoidCallback? onToggle;

  const _HeroPanel({
    required this.colors,
    required this.isStart,
    required this.hasProfile,
    required this.nodeCount,
    required this.reservedBottom,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.appLocalizations;
    final runTime = ref.watch(runTimeProvider);
    final groups = ref.watch(groupsProvider);
    final firstGroup = groups.isEmpty ? null : groups.first;
    final firstGroupSelected = firstGroup == null
        ? ''
        : (ref.watch(selectedProxyNameProvider(firstGroup.name)) ?? '')
              .takeFirstValid([firstGroup.realNow]);
    final mapNodes = firstGroup == null
        ? const <_WorldNode>[]
        : firstGroup.all
              .map(
                (proxy) => _WorldNode(
                  name: proxy.name,
                  delay: ref.watch(
                    delayProvider(
                      proxyName: proxy.name,
                      testUrl: firstGroup.testUrl,
                    ),
                  ),
                ),
              )
              .toList();
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [colors.heroStart, colors.heroEnd],
        ),
      ),
      child: Stack(
        alignment: Alignment.topCenter,
        children: [
          Positioned.fill(
            child: _ThemedWorldMap(
              colors: colors,
              isStart: isStart,
              showRoute: false,
              interactive: true,
              showAttribution: false,
              opacity: 0.3,
              nodeName: firstGroupSelected,
              nodeCount: nodeCount,
              nodes: mapNodes,
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            top: 8,
            bottom: reservedBottom + 12,
            child: Align(
              alignment: Alignment.topCenter,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Column(
                  children: [
                    _PowerButton(
                      colors: colors,
                      isStart: isStart,
                      onTap: onToggle,
                    ),
                    const SizedBox(height: 10),
                    Text(
                      isStart ? l10n.connected : l10n.disconnected,
                      style: TextStyle(
                        color: isStart ? colors.success : colors.muted,
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      hasProfile
                          ? utils.getTimeText(runTime)
                          : l10n.proxiesEmpty,
                      style: TextStyle(color: colors.muted, fontSize: 12),
                    ),
                    const SizedBox(height: 8),
                    _ModeSelector(colors: colors),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PowerButton extends StatelessWidget {
  final _DashboardColors colors;
  final bool isStart;
  final VoidCallback? onTap;

  const _PowerButton({
    required this.colors,
    required this.isStart,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = isStart ? colors.success : colors.primary;
    return Semantics(
      button: true,
      label: isStart
          ? context.appLocalizations.stopAcceleration
          : context.appLocalizations.startAcceleration,
      child: InkWell(
        key: const ValueKey('fengwo-power-button'),
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: AnimatedContainer(
          width: 190,
          height: 190,
          duration: const Duration(milliseconds: 280),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(
              colors: [
                color.withValues(alpha: isStart ? 0.95 : 0.26),
                color.withValues(alpha: isStart ? 0.66 : 0.08),
              ],
            ),
            border: Border.all(
              color: color.withValues(alpha: isStart ? 0.9 : 0.45),
              width: 3,
            ),
            boxShadow: [
              BoxShadow(
                color: color.withValues(alpha: isStart ? 0.46 : 0.14),
                blurRadius: isStart ? 46 : 24,
                spreadRadius: isStart ? 10 : 3,
              ),
            ],
          ),
          child: Icon(
            Icons.power_settings_new_rounded,
            color: isStart ? Colors.white : color,
            size: 62,
          ),
        ),
      ),
    );
  }
}

class _ModeSelector extends ConsumerWidget {
  final _DashboardColors colors;

  const _ModeSelector({required this.colors});

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
    return Container(
      height: 49,
      padding: const EdgeInsets.all(5),
      decoration: BoxDecoration(
        color: colors.surface.withValues(alpha: 0.9),
        border: Border.all(color: colors.outline),
        borderRadius: BorderRadius.circular(25),
        boxShadow: [
          BoxShadow(
            color: colors.shadow,
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _ModeItem(
            colors: colors,
            icon: Icons.route_rounded,
            label: l10n.rule,
            selected: mode == Mode.rule,
            onTap: () =>
                ref.read(setupActionProvider.notifier).changeMode(Mode.rule),
          ),
          _ModeItem(
            key: const ValueKey('fengwo-desktop-global-mode'),
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
          _ModeItem(
            colors: colors,
            icon: Icons.account_tree_outlined,
            label: l10n.tun,
            selected: tunEnabled,
            onTap: () => ref.read(systemActionProvider.notifier).updateTun(),
          ),
        ],
      ),
    );
  }
}

class _ModeItem extends StatelessWidget {
  final _DashboardColors colors;
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _ModeItem({
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
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? colors.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          children: [
            Icon(icon, size: 18, color: foreground),
            const SizedBox(width: 7),
            Text(
              label,
              style: TextStyle(color: foreground, fontWeight: FontWeight.w700),
            ),
          ],
        ),
      ),
    );
  }
}

class _ConnectionStatusPanel extends StatelessWidget {
  final _DashboardColors colors;
  final bool isStart;
  final String nodeName;
  final int? delay;
  final int? connectionDelay;
  final int? standardDelay;
  final Traffic traffic;
  final List<Traffic> trafficHistory;
  final XboardSubscriptionData? subscription;
  final VoidCallback onOpenNodes;
  final VoidCallback? onRefresh;

  const _ConnectionStatusPanel({
    required this.colors,
    required this.isStart,
    required this.nodeName,
    required this.delay,
    required this.connectionDelay,
    required this.standardDelay,
    required this.traffic,
    required this.trafficHistory,
    required this.subscription,
    required this.onOpenNodes,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = context.appLocalizations;
    final used = subscription?.usedGb ?? 0;
    final remaining = subscription?.remainingGb ?? 0;
    final total = subscription?.transferEnableGb ?? 0;
    return _GlassPanel(
      colors: colors,
      padding: const EdgeInsets.all(18),
      child: Column(
        children: [
          Row(
            children: [
              Icon(Icons.wifi_rounded, color: colors.success, size: 28),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  l10n.connectionStatus,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: colors.text,
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              IconButton(
                onPressed: onRefresh,
                tooltip: l10n.delayTest,
                icon: const Icon(Icons.refresh_rounded, size: 20),
              ),
              const SizedBox(width: 3),
              _StatusPill(colors: colors, connected: isStart),
            ],
          ),
          const SizedBox(height: 11),
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: colors.primarySoft,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(Icons.public_rounded, color: colors.primary),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.currentNode,
                      style: TextStyle(color: colors.muted, fontSize: 12),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      nodeName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: colors.text,
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
              TextButton(onPressed: onOpenNodes, child: Text(l10n.switchNode)),
            ],
          ),
          Divider(height: 20, color: colors.outline),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final cellWidth = (constraints.maxWidth - 10) / 2;
                final cellHeight = (constraints.maxHeight - 10) / 2;
                return GridView.count(
                  physics: const NeverScrollableScrollPhysics(),
                  crossAxisCount: 2,
                  childAspectRatio: cellWidth / cellHeight,
                  crossAxisSpacing: 10,
                  mainAxisSpacing: 10,
                  children: [
                    _MetricCard(
                      colors: colors,
                      icon: Icons.equalizer_rounded,
                      color: _delayColor(delay, colors),
                      label: connectionDelay == null
                          ? l10n.standardizedDelay
                          : l10n.actualConnectionDelay,
                      value: delay == null || delay! < 0 ? '--' : '$delay',
                      unit: 'ms',
                      footer: delay == null
                          ? l10n.notTested
                          : delay! < 0
                          ? l10n.timeout
                          : connectionDelay != null && standardDelay != null
                          ? '${l10n.standardizedDelay} $standardDelay ms'
                          : null,
                      latency: delay,
                    ),
                    _MetricCard(
                      colors: colors,
                      icon: Icons.arrow_downward_rounded,
                      color: colors.primary,
                      label: l10n.download,
                      value: traffic.down.traffic.show,
                      unit: '/s',
                      samples: trafficHistory.map((item) => item.down).toList(),
                    ),
                    _MetricCard(
                      colors: colors,
                      icon: Icons.arrow_upward_rounded,
                      color: const Color(0xFF8A4DFF),
                      label: l10n.upload,
                      value: traffic.up.traffic.show,
                      unit: '/s',
                      samples: trafficHistory.map((item) => item.up).toList(),
                    ),
                    _TrafficDetailsMetricCard(
                      colors: colors,
                      used: used,
                      remaining: remaining,
                      total: total,
                      progress: total > 0
                          ? (used / total).clamp(0, 1).toDouble()
                          : 0,
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  final _DashboardColors colors;
  final bool connected;

  const _StatusPill({required this.colors, required this.connected});

  @override
  Widget build(BuildContext context) {
    final color = connected ? colors.success : colors.muted;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 7),
          Text(
            connected
                ? context.appLocalizations.connected
                : context.appLocalizations.disconnected,
            style: TextStyle(color: color, fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }
}

class _MetricCard extends StatelessWidget {
  final _DashboardColors colors;
  final IconData icon;
  final Color color;
  final String label;
  final String value;
  final String unit;
  final String? footer;
  final List<num> samples;
  final int? latency;

  const _MetricCard({
    required this.colors,
    required this.icon,
    required this.color,
    required this.label,
    required this.value,
    required this.unit,
    this.footer,
    this.samples = const [],
    this.latency,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
      decoration: BoxDecoration(
        color: colors.surfaceStrong.withValues(alpha: 0.72),
        border: Border.all(color: colors.outline),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 35,
            height: 35,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(color: color.withValues(alpha: 0.28), blurRadius: 12),
              ],
            ),
            child: Icon(icon, color: Colors.white, size: 19),
          ),
          const SizedBox(width: 8),
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
                const SizedBox(height: 1),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Flexible(
                      child: Text(
                        value,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: colors.text,
                          fontSize: 20,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 3),
                      child: Text(unit, style: TextStyle(color: colors.muted)),
                    ),
                  ],
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 3),
                    child: CustomPaint(
                      painter: _MetricChartPainter(
                        color: color,
                        muted: colors.outline,
                        samples: samples,
                        latency: latency,
                      ),
                      size: Size.infinite,
                    ),
                  ),
                ),
                if (footer != null) ...[
                  const SizedBox(height: 1),
                  Text(
                    footer!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: colors.muted, fontSize: 8.5),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TrafficDetailsMetricCard extends StatelessWidget {
  final _DashboardColors colors;
  final double used;
  final double remaining;
  final double total;
  final double progress;

  const _TrafficDetailsMetricCard({
    required this.colors,
    required this.used,
    required this.remaining,
    required this.total,
    required this.progress,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = context.appLocalizations;
    const accent = Color(0xFF20BFC8);
    return Container(
      key: const ValueKey('fengwo-desktop-traffic-details'),
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
      decoration: BoxDecoration(
        color: colors.surfaceStrong.withValues(alpha: 0.72),
        border: Border.all(color: colors.outline),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  color: accent,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: accent.withValues(alpha: 0.28),
                      blurRadius: 10,
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.pie_chart_outline_rounded,
                  color: Colors.white,
                  size: 15,
                ),
              ),
              const SizedBox(width: 7),
              Text(
                l10n.trafficDetails,
                style: TextStyle(
                  color: colors.muted,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 3),
          Expanded(
            child: Row(
              children: [
                Expanded(
                  child: _TrafficQuotaValue(
                    colors: colors,
                    label: l10n.usedTrafficLabel,
                    value: used,
                  ),
                ),
                VerticalDivider(width: 8, color: colors.outline),
                Expanded(
                  child: _TrafficQuotaValue(
                    colors: colors,
                    label: l10n.remainingTrafficLabel,
                    value: remaining,
                  ),
                ),
                VerticalDivider(width: 8, color: colors.outline),
                Expanded(
                  child: _TrafficQuotaValue(
                    colors: colors,
                    label: l10n.totalTrafficLabel,
                    value: total,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 3),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              minHeight: 5,
              value: progress,
              backgroundColor: colors.outline.withValues(alpha: 0.5),
              color: accent,
            ),
          ),
        ],
      ),
    );
  }
}

class _TrafficQuotaValue extends StatelessWidget {
  final _DashboardColors colors;
  final String label;
  final double value;

  const _TrafficQuotaValue({
    required this.colors,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    final valueText = value.toStringAsFixed(value >= 100 ? 0 : 1);
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(color: colors.muted, fontSize: 8.5),
        ),
        const SizedBox(height: 1),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            '$valueText GB',
            maxLines: 1,
            style: TextStyle(
              color: colors.text,
              fontSize: 13,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
      ],
    );
  }
}

Color _delayColor(int? delay, _DashboardColors colors) {
  if (delay == null || delay == 0) return colors.muted;
  if (delay < 0) return const Color(0xFFE84C4C);
  if (delay <= 250) return colors.success;
  if (delay <= 400) return const Color(0xFF3B82F6);
  return const Color(0xFFF29C38);
}

class _MetricChartPainter extends CustomPainter {
  final Color color;
  final Color muted;
  final List<num> samples;
  final int? latency;

  const _MetricChartPainter({
    required this.color,
    required this.muted,
    required this.samples,
    required this.latency,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    if (latency != null) {
      const gap = 4.0;
      final segmentWidth = (size.width - gap * 3) / 4;
      final colors = [
        const Color(0xFF20CC76),
        const Color(0xFF20CC76),
        const Color(0xFF3385E8),
        const Color(0xFFF29C38),
      ];
      for (var index = 0; index < colors.length; index++) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(
              index * (segmentWidth + gap),
              size.height * 0.55,
              segmentWidth,
              5,
            ),
            const Radius.circular(3),
          ),
          Paint()..color = colors[index],
        );
      }
      final value = latency! < 0 ? 600 : latency!.clamp(0, 600);
      final x = size.width * (value / 600);
      canvas.drawCircle(
        Offset(x.clamp(5, size.width - 5), size.height * 0.55 + 2.5),
        5,
        Paint()..color = color,
      );
      return;
    }
    if (samples.isEmpty) return;
    final values = samples.length > 60
        ? samples.sublist(samples.length - 60)
        : samples;
    final maxValue = values.fold<num>(
      1,
      (max, item) => item > max ? item : max,
    );
    final path = Path();
    for (var index = 0; index < values.length; index++) {
      final x = values.length == 1
          ? size.width
          : size.width * index / (values.length - 1);
      final y = size.height - size.height * values[index] / maxValue;
      if (index == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    canvas.drawLine(
      Offset(0, size.height - 1),
      Offset(size.width, size.height - 1),
      Paint()..color = muted.withValues(alpha: 0.55),
    );
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(covariant _MetricChartPainter oldDelegate) {
    return oldDelegate.color != color ||
        oldDelegate.muted != muted ||
        oldDelegate.samples != samples ||
        oldDelegate.latency != latency;
  }
}

class _GlobalNetworkPanel extends ConsumerWidget {
  final _DashboardColors colors;
  final String nodeName;
  final bool isStart;
  final IpInfo? ipInfo;
  final int countryCount;

  const _GlobalNetworkPanel({
    required this.colors,
    required this.nodeName,
    required this.isStart,
    required this.ipInfo,
    required this.countryCount,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final groups = ref.watch(groupsProvider);
    final firstGroup = groups.isEmpty ? null : groups.first;
    final mapNodes = firstGroup == null
        ? const <_WorldNode>[]
        : firstGroup.all
              .map((proxy) {
                final connectionDelay = ref.watch(
                  connectionDelayProvider(
                    proxyName: proxy.name,
                    testUrl: firstGroup.testUrl,
                  ),
                );
                final standardDelay = ref.watch(
                  standardDelayProvider(
                    proxyName: proxy.name,
                    testUrl: firstGroup.testUrl,
                  ),
                );
                final fallbackDelay = ref.watch(
                  delayProvider(
                    proxyName: proxy.name,
                    testUrl: firstGroup.testUrl,
                  ),
                );
                return _WorldNode(
                  name: proxy.name,
                  delay: connectionDelay ?? standardDelay ?? fallbackDelay,
                  connectionDelay: connectionDelay,
                  standardDelay: standardDelay,
                );
              })
              .toList(growable: false);
    final l10n = context.appLocalizations;
    return _GlassPanel(
      colors: colors,
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.shield_outlined, color: colors.primary, size: 27),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  l10n.globalAccelerationNetwork,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: colors.text,
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Text(
                l10n.countriesCount(countryCount),
                key: const ValueKey('fengwo-desktop-network-country-count'),
                maxLines: 1,
                style: TextStyle(
                  color: colors.muted,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Expanded(
            child: _ThemedWorldMap(
              key: const ValueKey('fengwo-global-network-map'),
              colors: colors,
              isStart: isStart,
              showRoute: true,
              opacity: 0.7,
              nodeName: nodeName,
              ipInfo: ipInfo,
              nodes: mapNodes,
            ),
          ),
        ],
      ),
    );
  }
}

class _ThemedWorldMap extends StatefulWidget {
  final _DashboardColors colors;
  final bool isStart;
  final bool showRoute;
  final bool interactive;
  final double opacity;
  final String nodeName;
  final IpInfo? ipInfo;
  final int? nodeCount;
  final List<_WorldNode> nodes;
  final bool showAttribution;

  const _ThemedWorldMap({
    super.key,
    required this.colors,
    required this.isStart,
    required this.showRoute,
    required this.opacity,
    this.interactive = false,
    this.nodeName = '',
    this.ipInfo,
    this.nodeCount,
    this.nodes = const [],
    this.showAttribution = true,
  });

  @override
  State<_ThemedWorldMap> createState() => _ThemedWorldMapState();
}

class _ThemedWorldMapState extends State<_ThemedWorldMap>
    with SingleTickerProviderStateMixin {
  static const _initialCenter = LatLng(20, 0);
  static const _initialZoom = 1.35;
  static const _userFocusZoom = 1.75;
  static const _minZoom = 1.0;
  static const _maxZoom = 5.0;

  late final AnimationController _controller;
  late final MapController _mapController;
  late double _mapZoom;
  bool _mapReady = false;
  String? _revealedNodeName;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2600),
    )..repeat();
    _mapController = MapController();
    _mapZoom = _geoLatLng(widget.ipInfo) == null
        ? _initialZoom
        : _userFocusZoom;
  }

  @override
  void dispose() {
    _controller.dispose();
    _mapController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant _ThemedWorldMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    final revealedNodeName = _revealedNodeName;
    if (revealedNodeName != null &&
        !widget.nodes.any((node) => node.name == revealedNodeName)) {
      _revealedNodeName = null;
    }
    final oldUserPosition = _geoLatLng(oldWidget.ipInfo);
    final userPosition = _geoLatLng(widget.ipInfo);
    if (userPosition != null &&
        !_sameLatLng(userPosition, oldUserPosition) &&
        _mapReady) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _mapController.move(userPosition, math.max(_mapZoom, _userFocusZoom));
        }
      });
    }
  }

  void _toggleNodeLabel(String nodeName) {
    setState(() {
      _revealedNodeName = _revealedNodeName == nodeName ? null : nodeName;
    });
  }

  void _moveMap(double zoom, {bool resetCenter = false}) {
    final target = zoom.clamp(_minZoom, _maxZoom).toDouble();
    final center = resetCenter
        ? _geoLatLng(widget.ipInfo) ?? _initialCenter
        : _mapController.camera.center;
    _mapController.move(center, target);
    if ((target - _mapZoom).abs() > 0.001) {
      setState(() => _mapZoom = target);
    }
  }

  @override
  Widget build(BuildContext context) {
    final nodeCode = fengWoNodeCountryCode(widget.nodeName);
    final userPosition = _geoLatLng(widget.ipInfo);
    final nodePosition = _countryLatLng(nodeCode);
    final canDrawRoute =
        widget.showRoute && userPosition != null && nodePosition != null;
    final countryIndexes = <String, int>{};
    final nodeNames = <String>{};
    final positionedNodes = <({LatLng point, _WorldNode node})>[];
    for (final node in widget.nodes) {
      if (!nodeNames.add(node.name)) continue;
      final code = node.countryCode ?? fengWoNodeCountryCode(node.name);
      final center = _countryLatLng(code);
      if (code == null || center == null) continue;
      final index = countryIndexes.update(
        code,
        (value) => value + 1,
        ifAbsent: () => 0,
      );
      final angle = index * math.pi * (3 - math.sqrt(5));
      final radius = index == 0 ? 0.0 : 1.3 + math.sqrt(index) * 0.75;
      final latitude = (center.latitude + math.sin(angle) * radius)
          .clamp(-80.0, 80.0)
          .toDouble();
      final longitude = _wrapLongitude(
        center.longitude + math.cos(angle) * radius,
      );
      positionedNodes.add((node: node, point: LatLng(latitude, longitude)));
    }

    final sortedNodes = [...positionedNodes]
      ..sort(
        (left, right) => (left.node.name == _revealedNodeName ? 1 : 0)
            .compareTo(right.node.name == _revealedNodeName ? 1 : 0),
      );
    final countryCodes = <String>{};
    if (nodeCode != null) countryCodes.add(nodeCode);
    for (final node in widget.nodes) {
      final code = node.countryCode ?? fengWoNodeCountryCode(node.name);
      if (code != null) countryCodes.add(code);
    }
    final countryLabelMarkers = [
      for (final code in countryCodes)
        if (_countryLatLng(code) case final point?)
          Marker(
            point: point,
            width: 86,
            height: 34,
            alignment: Alignment.topCenter,
            child: _CountryMapLabel(
              key: ValueKey('fengwo-map-country-$code'),
              colors: widget.colors,
              name: _countryDisplayNames[code] ?? code,
            ),
          ),
    ];
    final nodeMarkers = [
      for (final item in sortedNodes)
        Marker(
          point: item.point,
          width: item.node.name == _revealedNodeName ? 280 : 40,
          height: item.node.name == _revealedNodeName ? 82 : 40,
          alignment: item.node.name == _revealedNodeName
              ? Alignment.bottomCenter
              : Alignment.center,
          child: _NodeMapMarker(
            key: ValueKey('fengwo-map-node-${item.node.name}'),
            colors: widget.colors,
            node: item.node,
            selected: item.node.name == widget.nodeName,
            revealed: item.node.name == _revealedNodeName,
            animation: _controller,
            onTap: () => _toggleNodeLabel(item.node.name),
          ),
        ),
    ];
    final endpointMarkers = <Marker>[
      if (widget.showRoute && userPosition != null)
        Marker(
          point: userPosition,
          width: 150,
          height: 42,
          alignment: Alignment.center,
          child: _MapEndpointMarker(
            key: const ValueKey('fengwo-route-user'),
            colors: widget.colors,
            label: context.appLocalizations.userMapLabel,
            showLabel: true,
          ),
        ),
      if (widget.showRoute && nodePosition != null)
        Marker(
          point: nodePosition,
          width: 24,
          height: 24,
          alignment: Alignment.center,
          child: _MapEndpointMarker(
            key: const ValueKey('fengwo-route-node'),
            colors: widget.colors,
            label: widget.nodeName,
            showLabel: false,
          ),
        ),
    ];
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final nodeCount = widget.nodeCount ?? widget.nodes.length;

    return Stack(
      clipBehavior: Clip.hardEdge,
      children: [
        Positioned.fill(
          child: FlutterMap(
            key: const ValueKey('fengwo-flutter-map'),
            mapController: _mapController,
            options: MapOptions(
              crs: const _NonRepeatingWebMercator(),
              initialCenter: userPosition ?? _initialCenter,
              initialZoom: userPosition == null ? _initialZoom : _userFocusZoom,
              minZoom: _minZoom,
              maxZoom: _maxZoom,
              backgroundColor: widget.colors.surfaceStrong,
              keepAlive: true,
              interactionOptions: InteractionOptions(
                flags: widget.interactive
                    ? InteractiveFlag.all & ~InteractiveFlag.rotate
                    : InteractiveFlag.none,
              ),
              onMapReady: () {
                _mapReady = true;
                final focus = _geoLatLng(widget.ipInfo);
                if (focus != null) {
                  _mapController.move(focus, _userFocusZoom);
                }
              },
              onPositionChanged: (camera, _) {
                if ((camera.zoom - _mapZoom).abs() > 0.01 && mounted) {
                  setState(() => _mapZoom = camera.zoom);
                }
              },
            ),
            children: [
              Opacity(
                opacity: widget.opacity.clamp(0.0, 1.0).toDouble(),
                child: ColorFiltered(
                  colorFilter: isDark
                      ? const ColorFilter.matrix([
                          -0.62,
                          0,
                          0,
                          0,
                          255,
                          0,
                          -0.62,
                          0,
                          0,
                          255,
                          0,
                          0,
                          -0.62,
                          0,
                          255,
                          0,
                          0,
                          0,
                          1,
                          0,
                        ])
                      : const ColorFilter.mode(
                          Colors.transparent,
                          BlendMode.dst,
                        ),
                  child: OverlayImageLayer(
                    overlayImages: [
                      OverlayImage(
                        bounds: _staticWorldMapBounds,
                        imageProvider: const AssetImage(_staticWorldMapAsset),
                        gaplessPlayback: true,
                        filterQuality: FilterQuality.high,
                      ),
                    ],
                  ),
                ),
              ),
              if (canDrawRoute)
                PolylineLayer(
                  polylines: [
                    Polyline(
                      points: [userPosition, nodePosition],
                      strokeWidth: 3,
                      borderStrokeWidth: 1,
                      borderColor: Colors.white.withValues(alpha: 0.72),
                      gradientColors: [
                        _neonRouteColor.withValues(alpha: 0.5),
                        _neonRouteColor,
                      ],
                    ),
                  ],
                ),
              if (countryLabelMarkers.isNotEmpty)
                MarkerLayer(markers: countryLabelMarkers),
              MarkerLayer(markers: nodeMarkers),
              if (endpointMarkers.isNotEmpty)
                MarkerLayer(markers: endpointMarkers),
              if (widget.isStart && userPosition != null)
                AnimatedBuilder(
                  animation: _controller,
                  builder: (context, _) {
                    return MarkerLayer(
                      markers: [
                        Marker(
                          point: userPosition,
                          width: 42,
                          height: 42,
                          child: _UserFocusPulse(
                            key: const ValueKey('fengwo-user-focus-pulse'),
                            progress: _controller.value,
                          ),
                        ),
                        if (canDrawRoute)
                          Marker(
                            point: _interpolateGeo(
                              userPosition,
                              nodePosition,
                              _controller.value,
                            ),
                            width: 18,
                            height: 18,
                            child: const _RouteProgressMarker(),
                          ),
                      ],
                    );
                  },
                ),
              if (widget.showAttribution)
                const RichAttributionWidget(
                  showFlutterMapAttribution: false,
                  attributions: [
                    TextSourceAttribution('Natural Earth (offline map)'),
                  ],
                ),
            ],
          ),
        ),
        if (widget.interactive)
          Positioned(
            top: 14,
            right: 18,
            child: _MapControls(
              colors: widget.colors,
              nodeCount: nodeCount,
              scale: _mapZoom,
              minScale: _minZoom,
              maxScale: _maxZoom,
              onZoomIn: () => _moveMap(_mapZoom + 0.5),
              onZoomOut: () => _moveMap(_mapZoom - 0.5),
              onReset: () => _moveMap(
                userPosition == null ? _initialZoom : _userFocusZoom,
                resetCenter: true,
              ),
            ),
          ),
      ],
    );
  }
}

class _WorldNode {
  final String name;
  final int? delay;
  final int? connectionDelay;
  final int? standardDelay;
  final String? countryCode;

  const _WorldNode({
    required this.name,
    required this.delay,
    this.connectionDelay,
    this.standardDelay,
    this.countryCode,
  });
}

class _NodeMapMarker extends StatelessWidget {
  final _DashboardColors colors;
  final _WorldNode node;
  final bool selected;
  final bool revealed;
  final Animation<double> animation;
  final VoidCallback onTap;

  const _NodeMapMarker({
    super.key,
    required this.colors,
    required this.node,
    required this.selected,
    required this.revealed,
    required this.animation,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final markerColor = _delayColor(node.delay, colors);
    final diameter = selected ? 12.0 : 9.0;
    final animated = selected || node.delay == 0;
    return Semantics(
      button: true,
      label: node.name,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.bottomCenter,
          children: [
            if (revealed)
              Positioned(
                left: 0,
                right: 0,
                bottom: 42,
                child: _NodeNameCallout(
                  key: ValueKey('fengwo-map-node-label-${node.name}'),
                  colors: colors,
                  node: node,
                ),
              ),
            Positioned(
              bottom: 4,
              child: SizedBox.square(
                dimension: 32,
                child: AnimatedBuilder(
                  animation: animation,
                  builder: (context, child) {
                    final progress = animated ? animation.value : 0.0;
                    return Stack(
                      alignment: Alignment.center,
                      children: [
                        if (animated)
                          Container(
                            key: ValueKey('fengwo-map-node-pulse-${node.name}'),
                            width: diameter + 16 * progress,
                            height: diameter + 16 * progress,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: markerColor.withValues(
                                  alpha: 0.48 * (1 - progress),
                                ),
                              ),
                            ),
                          ),
                        child!,
                      ],
                    );
                  },
                  child: Container(
                    key: ValueKey('fengwo-map-node-dot-${node.name}'),
                    width: diameter,
                    height: diameter,
                    decoration: BoxDecoration(
                      color: markerColor,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: selected
                            ? Colors.white
                            : markerColor.withValues(alpha: 0.5),
                        width: selected ? 1.8 : 1.2,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: markerColor.withValues(
                            alpha: selected ? 0.55 : 0.3,
                          ),
                          blurRadius: selected ? 8 : 5,
                          spreadRadius: selected ? 1.5 : 0.5,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NodeNameCallout extends StatelessWidget {
  final _DashboardColors colors;
  final _WorldNode node;

  const _NodeNameCallout({super.key, required this.colors, required this.node});

  @override
  Widget build(BuildContext context) {
    final l10n = context.appLocalizations;
    final effectiveDetail = switch (node.delay) {
      null => l10n.notTested,
      0 => l10n.testingStatus,
      < 0 => l10n.timeout,
      final delay => '$delay ms',
    };
    final connectionDetail = switch (node.connectionDelay) {
      null => null,
      0 => l10n.testingStatus,
      < 0 => l10n.timeout,
      final delay => '$delay ms',
    };
    final standardDetail = switch (node.standardDelay) {
      null || 0 => null,
      < 0 => l10n.timeout,
      final delay => '$delay ms',
    };
    final detail = connectionDetail == null && standardDetail == null
        ? effectiveDetail
        : [
            if (connectionDetail != null)
              '${l10n.actualConnectionDelay} $connectionDetail',
            if (standardDetail != null)
              '${l10n.standardizedDelay} $standardDetail',
          ].join(' · ');
    return IgnorePointer(
      child: Container(
        height: 36,
        margin: const EdgeInsets.symmetric(horizontal: 4),
        padding: const EdgeInsets.symmetric(horizontal: 10),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: colors.surface.withValues(alpha: 0.97),
          borderRadius: BorderRadius.circular(15),
          border: Border.all(color: colors.outline),
          boxShadow: [BoxShadow(color: colors.shadow, blurRadius: 10)],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Flexible(
              child: Text(
                node.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: colors.text,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            const SizedBox(width: 6),
            Container(
              width: 4,
              height: 4,
              decoration: BoxDecoration(
                color: _delayColor(node.delay, colors),
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 5),
            Flexible(
              child: Text(
                detail,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: colors.muted,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MapEndpointMarker extends StatelessWidget {
  final _DashboardColors colors;
  final String label;
  final bool showLabel;

  const _MapEndpointMarker({
    super.key,
    required this.colors,
    required this.label,
    required this.showLabel,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: _neonRouteColor,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 1.6),
            boxShadow: [
              BoxShadow(
                color: _neonRouteColor.withValues(alpha: 0.58),
                blurRadius: 8,
                spreadRadius: 1,
              ),
            ],
          ),
        ),
        if (showLabel) ...[
          const SizedBox(width: 7),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: colors.text,
                fontSize: 11,
                fontWeight: FontWeight.w800,
                shadows: [
                  Shadow(color: colors.surface, blurRadius: 5),
                  Shadow(color: colors.surface, blurRadius: 5),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _CountryMapLabel extends StatelessWidget {
  final _DashboardColors colors;
  final String name;

  const _CountryMapLabel({super.key, required this.colors, required this.name});

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Padding(
        padding: const EdgeInsets.only(top: 12),
        child: Text(
          name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: colors.text.withValues(alpha: 0.86),
            fontSize: 10,
            fontWeight: FontWeight.w800,
            shadows: [
              Shadow(color: colors.surface, blurRadius: 4),
              Shadow(color: colors.surface, blurRadius: 4),
              const Shadow(color: Colors.white, blurRadius: 2),
            ],
          ),
        ),
      ),
    );
  }
}

class _UserFocusPulse extends StatelessWidget {
  final double progress;

  const _UserFocusPulse({super.key, required this.progress});

  @override
  Widget build(BuildContext context) {
    final eased = Curves.easeOut.transform(progress);
    return Stack(
      alignment: Alignment.center,
      children: [
        Container(
          width: 16 + 24 * eased,
          height: 16 + 24 * eased,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: _neonRouteColor.withValues(alpha: 0.08 * (1 - eased)),
            border: Border.all(
              color: _neonRouteColor.withValues(alpha: 0.75 * (1 - eased)),
              width: 1.8,
            ),
          ),
        ),
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: _neonRouteColor,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 1.4),
            boxShadow: [
              BoxShadow(
                color: _neonRouteColor.withValues(alpha: 0.68),
                blurRadius: 10,
                spreadRadius: 2,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _RouteProgressMarker extends StatelessWidget {
  const _RouteProgressMarker();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: _neonRouteColor,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 1.4),
        boxShadow: [
          BoxShadow(
            color: _neonRouteColor.withValues(alpha: 0.55),
            blurRadius: 9,
            spreadRadius: 2,
          ),
        ],
      ),
    );
  }
}

class _MapControls extends StatelessWidget {
  final _DashboardColors colors;
  final int nodeCount;
  final double scale;
  final double minScale;
  final double maxScale;
  final VoidCallback onZoomIn;
  final VoidCallback onZoomOut;
  final VoidCallback onReset;

  const _MapControls({
    required this.colors,
    required this.nodeCount,
    required this.scale,
    required this.minScale,
    required this.maxScale,
    required this.onZoomIn,
    required this.onZoomOut,
    required this.onReset,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = context.appLocalizations;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 7, 6, 7),
      decoration: BoxDecoration(
        color: colors.surface.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: colors.outline),
        boxShadow: [BoxShadow(color: colors.shadow, blurRadius: 14)],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.public_rounded, size: 17, color: colors.primary),
          const SizedBox(width: 6),
          Text(
            l10n.nodesCount(nodeCount),
            key: const ValueKey('fengwo-map-node-count'),
            style: TextStyle(
              color: colors.text,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(width: 8),
          _MapControlButton(
            key: const ValueKey('fengwo-map-zoom-out'),
            icon: Icons.remove_rounded,
            tooltip: l10n.zoomOut,
            enabled: scale > minScale + 0.01,
            colors: colors,
            onTap: onZoomOut,
          ),
          _MapControlButton(
            key: const ValueKey('fengwo-map-reset'),
            icon: Icons.center_focus_strong_rounded,
            tooltip: l10n.reset,
            enabled: true,
            colors: colors,
            onTap: onReset,
          ),
          _MapControlButton(
            key: const ValueKey('fengwo-map-zoom-in'),
            icon: Icons.add_rounded,
            tooltip: l10n.zoomIn,
            enabled: scale < maxScale - 0.01,
            colors: colors,
            onTap: onZoomIn,
          ),
        ],
      ),
    );
  }
}

class _MapControlButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final bool enabled;
  final _DashboardColors colors;
  final VoidCallback onTap;

  const _MapControlButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.enabled,
    required this.colors,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return IconButton(
      visualDensity: VisualDensity.compact,
      constraints: const BoxConstraints.tightFor(width: 31, height: 31),
      padding: EdgeInsets.zero,
      tooltip: tooltip,
      onPressed: enabled ? onTap : null,
      icon: Icon(
        icon,
        size: 18,
        color: enabled ? colors.primary : colors.muted.withValues(alpha: 0.45),
      ),
    );
  }
}

const _countryCoordinates = <String, ({double latitude, double longitude})>{
  'AR': (latitude: -38.4, longitude: -63.6),
  'AT': (latitude: 47.5, longitude: 14.6),
  'AZ': (latitude: 40.1, longitude: 47.6),
  'BE': (latitude: 50.5, longitude: 4.5),
  'BG': (latitude: 42.7, longitude: 25.5),
  'BO': (latitude: -16.3, longitude: -63.6),
  'US': (latitude: 39.8, longitude: -98.6),
  'CA': (latitude: 56.1, longitude: -106.3),
  'BR': (latitude: -14.2, longitude: -51.9),
  'CL': (latitude: -35.7, longitude: -71.5),
  'CO': (latitude: 4.6, longitude: -74.3),
  'CR': (latitude: 9.7, longitude: -83.8),
  'CU': (latitude: 21.5, longitude: -79.4),
  'DO': (latitude: 18.7, longitude: -70.2),
  'EC': (latitude: -1.8, longitude: -78.2),
  'GT': (latitude: 15.8, longitude: -90.2),
  'MX': (latitude: 23.6, longitude: -102.5),
  'PA': (latitude: 8.5, longitude: -80.8),
  'PE': (latitude: -9.2, longitude: -75.0),
  'PR': (latitude: 18.2, longitude: -66.5),
  'PY': (latitude: -23.4, longitude: -58.4),
  'UY': (latitude: -32.5, longitude: -55.8),
  'VE': (latitude: 6.4, longitude: -66.6),
  'GB': (latitude: 55.4, longitude: -3.4),
  'CH': (latitude: 46.8, longitude: 8.2),
  'CZ': (latitude: 49.8, longitude: 15.5),
  'DK': (latitude: 56.3, longitude: 9.5),
  'EE': (latitude: 58.6, longitude: 25.0),
  'ES': (latitude: 40.5, longitude: -3.7),
  'FI': (latitude: 61.9, longitude: 25.7),
  'FR': (latitude: 46.2, longitude: 2.2),
  'DE': (latitude: 51.2, longitude: 10.4),
  'GR': (latitude: 39.1, longitude: 21.8),
  'HR': (latitude: 45.1, longitude: 15.2),
  'HU': (latitude: 47.2, longitude: 19.5),
  'IE': (latitude: 53.1, longitude: -8.2),
  'IS': (latitude: 65.0, longitude: -19.0),
  'IT': (latitude: 41.9, longitude: 12.6),
  'LT': (latitude: 55.2, longitude: 23.9),
  'LU': (latitude: 49.8, longitude: 6.1),
  'LV': (latitude: 56.9, longitude: 24.6),
  'NL': (latitude: 52.1, longitude: 5.3),
  'NO': (latitude: 60.5, longitude: 8.5),
  'PL': (latitude: 51.9, longitude: 19.1),
  'PT': (latitude: 39.4, longitude: -8.2),
  'RO': (latitude: 45.9, longitude: 24.9),
  'RS': (latitude: 44.0, longitude: 21.0),
  'RU': (latitude: 61.5, longitude: 105.3),
  'SE': (latitude: 60.1, longitude: 18.6),
  'SI': (latitude: 46.2, longitude: 14.8),
  'SK': (latitude: 48.7, longitude: 19.7),
  'TR': (latitude: 39.0, longitude: 35.2),
  'UA': (latitude: 48.4, longitude: 31.2),
  'AE': (latitude: 23.4, longitude: 53.8),
  'AM': (latitude: 40.1, longitude: 45.0),
  'BD': (latitude: 23.7, longitude: 90.4),
  'GE': (latitude: 42.3, longitude: 43.4),
  'IL': (latitude: 31.0, longitude: 34.9),
  'IN': (latitude: 20.6, longitude: 79.0),
  'IR': (latitude: 32.4, longitude: 53.7),
  'KZ': (latitude: 48.0, longitude: 67.0),
  'KH': (latitude: 12.6, longitude: 105.0),
  'LK': (latitude: 7.9, longitude: 80.8),
  'MN': (latitude: 46.9, longitude: 103.8),
  'NP': (latitude: 28.4, longitude: 84.1),
  'PK': (latitude: 30.4, longitude: 69.3),
  'QA': (latitude: 25.4, longitude: 51.2),
  'SA': (latitude: 23.9, longitude: 45.1),
  'CN': (latitude: 35.9, longitude: 104.2),
  'HK': (latitude: 22.3, longitude: 114.2),
  'TW': (latitude: 23.7, longitude: 121.0),
  'JP': (latitude: 36.2, longitude: 138.3),
  'KR': (latitude: 35.9, longitude: 127.8),
  'SG': (latitude: 1.35, longitude: 103.8),
  'MY': (latitude: 4.2, longitude: 101.9),
  'TH': (latitude: 15.9, longitude: 100.9),
  'VN': (latitude: 16.0, longitude: 108.3),
  'PH': (latitude: 12.9, longitude: 121.8),
  'ID': (latitude: -2.5, longitude: 118.0),
  'AU': (latitude: -25.3, longitude: 133.8),
  'NZ': (latitude: -40.9, longitude: 174.9),
  'DZ': (latitude: 28.0, longitude: 1.7),
  'EG': (latitude: 26.8, longitude: 30.8),
  'ET': (latitude: 9.1, longitude: 40.5),
  'GH': (latitude: 7.9, longitude: -1.0),
  'KE': (latitude: -0.02, longitude: 37.9),
  'MA': (latitude: 31.8, longitude: -7.1),
  'NG': (latitude: 9.1, longitude: 8.7),
  'TN': (latitude: 33.9, longitude: 9.5),
  'ZA': (latitude: -30.6, longitude: 22.9),
};

const _countryDisplayNames = <String, String>{
  'AR': 'Argentina',
  'AT': 'Austria',
  'AZ': 'Azerbaijan',
  'BE': 'Belgium',
  'BG': 'Bulgaria',
  'BO': 'Bolivia',
  'US': 'United States',
  'CA': 'Canada',
  'BR': 'Brazil',
  'CL': 'Chile',
  'CO': 'Colombia',
  'CR': 'Costa Rica',
  'CU': 'Cuba',
  'DO': 'Dominican Rep.',
  'EC': 'Ecuador',
  'GT': 'Guatemala',
  'MX': 'Mexico',
  'PA': 'Panama',
  'PE': 'Peru',
  'PR': 'Puerto Rico',
  'PY': 'Paraguay',
  'UY': 'Uruguay',
  'VE': 'Venezuela',
  'GB': 'United Kingdom',
  'CH': 'Switzerland',
  'CZ': 'Czechia',
  'DK': 'Denmark',
  'EE': 'Estonia',
  'ES': 'Spain',
  'FI': 'Finland',
  'FR': 'France',
  'DE': 'Germany',
  'GR': 'Greece',
  'HR': 'Croatia',
  'HU': 'Hungary',
  'IE': 'Ireland',
  'IS': 'Iceland',
  'IT': 'Italy',
  'LT': 'Lithuania',
  'LU': 'Luxembourg',
  'LV': 'Latvia',
  'NL': 'Netherlands',
  'NO': 'Norway',
  'PL': 'Poland',
  'PT': 'Portugal',
  'RO': 'Romania',
  'RS': 'Serbia',
  'RU': 'Russia',
  'SE': 'Sweden',
  'SI': 'Slovenia',
  'SK': 'Slovakia',
  'TR': 'Türkiye',
  'UA': 'Ukraine',
  'AE': 'UAE',
  'AM': 'Armenia',
  'BD': 'Bangladesh',
  'GE': 'Georgia',
  'IL': 'Israel',
  'IN': 'India',
  'IR': 'Iran',
  'KZ': 'Kazakhstan',
  'KH': 'Cambodia',
  'LK': 'Sri Lanka',
  'MN': 'Mongolia',
  'NP': 'Nepal',
  'PK': 'Pakistan',
  'QA': 'Qatar',
  'SA': 'Saudi Arabia',
  'CN': 'China',
  'HK': 'Hong Kong',
  'TW': 'Taiwan',
  'JP': 'Japan',
  'KR': 'South Korea',
  'SG': 'Singapore',
  'MY': 'Malaysia',
  'TH': 'Thailand',
  'VN': 'Vietnam',
  'PH': 'Philippines',
  'ID': 'Indonesia',
  'AU': 'Australia',
  'NZ': 'New Zealand',
  'DZ': 'Algeria',
  'EG': 'Egypt',
  'ET': 'Ethiopia',
  'GH': 'Ghana',
  'KE': 'Kenya',
  'MA': 'Morocco',
  'NG': 'Nigeria',
  'TN': 'Tunisia',
  'ZA': 'South Africa',
};

LatLng? _geoLatLng(IpInfo? ipInfo) {
  final latitude = ipInfo?.latitude;
  final longitude = ipInfo?.longitude;
  if (latitude != null &&
      longitude != null &&
      latitude.isFinite &&
      longitude.isFinite &&
      latitude >= -90 &&
      latitude <= 90 &&
      longitude >= -180 &&
      longitude <= 180) {
    return LatLng(latitude, longitude);
  }
  final countryCode = ipInfo?.countryCode.trim().toUpperCase();
  if (countryCode == null || countryCode.isEmpty) return null;
  return _countryLatLng(countryCode);
}

bool _sameLatLng(LatLng? left, LatLng? right) {
  if (left == null || right == null) return left == right;
  return (left.latitude - right.latitude).abs() < 0.000001 &&
      (left.longitude - right.longitude).abs() < 0.000001;
}

LatLng? _countryLatLng(String? countryCode) {
  final coordinates = _countryCoordinates[countryCode];
  if (coordinates == null) return null;
  return LatLng(coordinates.latitude, coordinates.longitude);
}

double _wrapLongitude(double longitude) {
  var value = longitude;
  while (value > 180) {
    value -= 360;
  }
  while (value < -180) {
    value += 360;
  }
  return value;
}

LatLng _interpolateGeo(LatLng start, LatLng end, double progress) {
  var longitudeDelta = end.longitude - start.longitude;
  if (longitudeDelta > 180) longitudeDelta -= 360;
  if (longitudeDelta < -180) longitudeDelta += 360;
  return LatLng(
    start.latitude + (end.latitude - start.latitude) * progress,
    _wrapLongitude(start.longitude + longitudeDelta * progress),
  );
}

String? fengWoNodeCountryCode(String nodeName) {
  final value = nodeName.toLowerCase();
  final runes = nodeName.runes.toList();
  for (var index = 0; index + 1 < runes.length; index++) {
    final first = runes[index];
    final second = runes[index + 1];
    if (first >= 0x1F1E6 &&
        first <= 0x1F1FF &&
        second >= 0x1F1E6 &&
        second <= 0x1F1FF) {
      return String.fromCharCodes([
        first - 0x1F1E6 + 0x41,
        second - 0x1F1E6 + 0x41,
      ]);
    }
  }
  const tokens = <String, List<String>>{
    'HK': ['香港', 'hong kong', '🇭🇰'],
    'TW': ['台湾', '臺灣', 'taiwan', '🇹🇼'],
    'JP': ['日本', '东京', '大阪', 'japan', 'tokyo', 'osaka', '🇯🇵'],
    'KR': ['韩国', '韓國', '首尔', '首爾', 'korea', 'seoul', '🇰🇷'],
    'SG': ['新加坡', 'singapore', '🇸🇬'],
    'US': ['美国', '美國', '洛杉矶', '洛杉磯', '西雅图', 'united states', 'usa', '🇺🇸'],
    'CA': ['加拿大', 'canada', 'toronto', 'vancouver', '🇨🇦'],
    'GB': ['英国', '英國', 'united kingdom', 'london', '🇬🇧'],
    'DE': ['德国', '德國', 'germany', 'frankfurt', '🇩🇪'],
    'FR': ['法国', '法國', 'france', 'paris', '🇫🇷'],
    'NL': ['荷兰', '荷蘭', 'netherlands', '🇳🇱'],
    'RU': ['俄罗斯', '俄羅斯', 'russia', 'moscow', '🇷🇺'],
    'IN': ['印度', 'india', '🇮🇳'],
    'TH': ['泰国', '泰國', 'thailand', '🇹🇭'],
    'VN': ['越南', 'vietnam', '🇻🇳'],
    'MY': ['马来西亚', '馬來西亞', 'malaysia', '🇲🇾'],
    'PH': ['菲律宾', '菲律賓', 'philippines', '🇵🇭'],
    'ID': ['印度尼西亚', '印尼', 'indonesia', '🇮🇩'],
    'AU': ['澳大利亚', '澳洲', 'australia', 'sydney', '🇦🇺'],
    'CN': ['中国', '中國', 'china', '🇨🇳'],
  };
  for (final entry in tokens.entries) {
    if (entry.value.any((token) => value.contains(token))) return entry.key;
  }
  return null;
}

class _GlassPanel extends StatelessWidget {
  final _DashboardColors colors;
  final EdgeInsetsGeometry padding;
  final Widget child;

  const _GlassPanel({
    required this.colors,
    required this.padding,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: colors.surface.withValues(alpha: 0.94),
        border: Border.all(color: colors.outline),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: colors.shadow,
            blurRadius: 26,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: child,
    );
  }
}

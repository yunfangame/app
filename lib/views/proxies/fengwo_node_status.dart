import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/state.dart';
import 'package:fl_clash/views/dashboard/fengwo_desktop_dashboard.dart';
import 'package:fl_clash/views/proxies/common.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

class FengWoNodeStatusView extends ConsumerStatefulWidget {
  const FengWoNodeStatusView({super.key});

  @override
  ConsumerState<FengWoNodeStatusView> createState() =>
      _FengWoNodeStatusViewState();
}

class _FengWoNodeStatusViewState extends ConsumerState<FengWoNodeStatusView> {
  final _nodesScrollController = ScrollController();
  final _xboardAuthService = XboardAuthService();
  List<XboardNodeData> _xboardNodes = const [];
  final Set<String> _testingNodes = {};
  bool _loadingXboardNodes = false;
  bool _xboardStatusFresh = false;
  bool _testingAll = false;

  @override
  void initState() {
    super.initState();
    _xboardNodes = globalState.xboardNodes;
    _xboardStatusFresh = _xboardNodes.isNotEmpty;
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadXboardNodes());
  }

  @override
  void dispose() {
    _nodesScrollController.dispose();
    super.dispose();
  }

  Group? _currentGroup(List<Group> groups, Profile? profile) {
    if (groups.isEmpty) return null;
    final preferredName = profile?.currentGroupName;
    return preferredName == null
        ? groups.first
        : groups.getGroup(preferredName) ?? groups.first;
  }

  String _currentNode(Group? group, Profile? profile) {
    if (group == null) return '';
    return group
        .getCurrentSelectedName(profile?.selectedMap[group.name] ?? '')
        .takeFirstValid([group.realNow, group.name]);
  }

  Future<void> _loadXboardNodes([XboardLoginResult? activeSession]) async {
    if (globalState.isOfflineMode) {
      if (mounted) setState(() => _xboardNodes = globalState.xboardNodes);
      return;
    }
    final session = activeSession ?? globalState.xboardSession;
    if (session == null || _loadingXboardNodes) return;
    if (mounted) setState(() => _loadingXboardNodes = true);
    try {
      final nodes = await _xboardAuthService.fetchNodes(
        endpoint: session.endpoint,
        authData: session.authData,
      );
      globalState.xboardNodes = nodes;
      if (mounted) {
        setState(() {
          _xboardNodes = nodes;
          _xboardStatusFresh = true;
        });
      }
    } catch (error, stackTrace) {
      if (mounted) setState(() => _xboardStatusFresh = false);
      commonPrint.log(
        'load XBoard nodes failed: $error, $stackTrace',
        logLevel: LogLevel.warning,
      );
    } finally {
      if (mounted) setState(() => _loadingXboardNodes = false);
    }
  }

  Future<void> _refreshNodes(Group group, List<Proxy> nodes) async {
    if (_testingAll || nodes.isEmpty) return;
    setState(() => _testingAll = true);
    try {
      await _loadXboardNodes();
      final metadata = _matchXboardNodes(nodes, _xboardNodes);
      final testableNodes = nodes
          .where(
            (proxy) =>
                !_xboardStatusFresh || metadata[proxy.name]?.isOnline != false,
          )
          .toList(growable: false);
      await delayTest(testableNodes, group.testUrl);
    } catch (error, stackTrace) {
      commonPrint.log(
        'refresh node delays failed: $error, $stackTrace',
        logLevel: LogLevel.warning,
      );
    } finally {
      if (mounted) setState(() => _testingAll = false);
    }
  }

  Future<void> _testNode(Group group, Proxy proxy) async {
    if (_testingAll || _testingNodes.contains(proxy.name)) return;
    final metadata = _matchXboardNodes([proxy], _xboardNodes)[proxy.name];
    if (_xboardStatusFresh && metadata?.isOnline == false) return;
    setState(() => _testingNodes.add(proxy.name));
    try {
      await proxyDelayTest(proxy, group.testUrl);
    } finally {
      if (mounted) setState(() => _testingNodes.remove(proxy.name));
    }
  }

  void _selectProxy(Group group, Proxy proxy) {
    if (!group.type.isComputedSelected && group.type != GroupType.Selector) {
      globalState.showNotifier(context.appLocalizations.notSelectedTip);
      return;
    }
    final currentName = ref.read(proxyNameProvider(group.name));
    final nextName = group.type.isComputedSelected
        ? currentName == proxy.name
              ? ''
              : proxy.name
        : proxy.name;
    ref.read(proxiesActionProvider.notifier).updateCurrentGroupName(group.name);
    ref
        .read(profilesActionProvider.notifier)
        .updateCurrentSelectedMap(group.name, nextName);
    ref
        .read(proxiesActionProvider.notifier)
        .changeProxyDebounce(group.name, nextName);
  }

  @override
  Widget build(BuildContext context) {
    final rawGroups = ref.watch(groupsProvider);
    final visibleGroups = ref.watch(currentGroupsStateProvider).value;
    final groups = visibleGroups
        .map((group) => rawGroups.getGroup(group.name) ?? group)
        .toList();
    final profile = ref.watch(currentProfileProvider);
    final group = _currentGroup(groups, profile);
    final currentNode = _currentNode(group, profile);
    final isStart = ref.watch(isStartProvider);
    final nodes = _xboardDisplayNodes(group?.all ?? const <Proxy>[], rawGroups);
    final nodeMetadata = _matchXboardNodes(nodes, _xboardNodes);
    final measuredDelays = <String, int?>{
      for (final proxy in nodes)
        proxy.name: ref.watch(
          delayProvider(proxyName: proxy.name, testUrl: group?.testUrl),
        ),
    };
    final connectionDelays = <String, int?>{
      for (final proxy in nodes)
        proxy.name: ref.watch(
          connectionDelayProvider(
            proxyName: proxy.name,
            testUrl: group?.testUrl,
          ),
        ),
    };
    final standardDelays = <String, int?>{
      for (final proxy in nodes)
        proxy.name: ref.watch(
          standardDelayProvider(proxyName: proxy.name, testUrl: group?.testUrl),
        ),
    };
    final nodeStatuses = <String, _NodePresentationStatus>{
      for (final proxy in nodes)
        proxy.name: _resolveNodeStatus(
          measuredDelay: measuredDelays[proxy.name],
          metadata: nodeMetadata[proxy.name],
          xboardStatusFresh: _xboardStatusFresh,
          isTesting: _testingNodes.contains(proxy.name),
        ),
    };
    final mapNodes = nodes
        .map(
          (proxy) => FengWoWorldMapNode(
            name: proxy.name,
            delay: nodeStatuses[proxy.name]?.mapDelay,
            connectionDelay: connectionDelays[proxy.name],
            standardDelay: standardDelays[proxy.name],
            countryCode: _countryCodeFromTags(
              nodeMetadata[proxy.name]?.tags ?? const [],
            ),
          ),
        )
        .toList(growable: false);
    final selectedName = group == null
        ? null
        : ref.watch(selectedProxyNameProvider(group.name));
    final onlineCount = nodeStatuses.values
        .where((status) => status.countsAsAvailable)
        .length;
    final countryCount = _xboardTagCount(_xboardNodes);
    final availability = nodes.isEmpty ? 0.0 : onlineCount / nodes.length;
    final colors = _NodeStatusColors.of(context);
    return Material(
      color: colors.background,
      child: ClipRRect(
        borderRadius: const BorderRadius.only(bottomLeft: Radius.circular(34)),
        child: Column(
          children: [
            Expanded(
              child: _NodeStatusBody(
                colors: colors,
                group: group,
                nodes: nodes,
                nodeStatuses: nodeStatuses,
                nodeMetadata: nodeMetadata,
                mapNodes: mapNodes,
                currentNode: currentNode,
                selectedName: selectedName,
                isStart: isStart,
                testingAll: _testingAll,
                countryCount: countryCount,
                availability: availability,
                nodesScrollController: _nodesScrollController,
                onRefresh: group == null
                    ? null
                    : () => _refreshNodes(group, nodes),
                onSelect: group == null
                    ? null
                    : (proxy) => _selectProxy(group, proxy),
                onTest: group == null
                    ? null
                    : (proxy) => _testNode(group, proxy),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NodeStatusColors {
  final Color background;
  final Color surface;
  final Color surfaceStrong;
  final Color primary;
  final Color primarySoft;
  final Color text;
  final Color muted;
  final Color outline;
  final Color success;
  final Color successSoft;
  final Color danger;
  final Color dangerSoft;
  final Color shadow;

  const _NodeStatusColors({
    required this.background,
    required this.surface,
    required this.surfaceStrong,
    required this.primary,
    required this.primarySoft,
    required this.text,
    required this.muted,
    required this.outline,
    required this.success,
    required this.successSoft,
    required this.danger,
    required this.dangerSoft,
    required this.shadow,
  });

  factory _NodeStatusColors.of(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dark = scheme.brightness == Brightness.dark;
    final success = dark ? const Color(0xFF46E39C) : const Color(0xFF15B968);
    final danger = dark ? const Color(0xFFFF7389) : const Color(0xFFE74261);
    return _NodeStatusColors(
      background: dark
          ? scheme.surfaceContainerLowest
          : Color.alphaBlend(
              scheme.primary.withValues(alpha: 0.045),
              scheme.surface,
            ),
      surface: dark ? scheme.surfaceContainer : scheme.surface,
      surfaceStrong: dark
          ? scheme.surfaceContainerHigh
          : Color.alphaBlend(
              scheme.primary.withValues(alpha: 0.035),
              scheme.surfaceContainerLowest,
            ),
      primary: scheme.primary,
      primarySoft: scheme.primary.withValues(alpha: dark ? 0.22 : 0.1),
      text: scheme.onSurface,
      muted: scheme.onSurfaceVariant,
      outline: scheme.outlineVariant.withValues(alpha: dark ? 0.7 : 0.82),
      success: success,
      successSoft: success.withValues(alpha: dark ? 0.2 : 0.12),
      danger: danger,
      dangerSoft: danger.withValues(alpha: dark ? 0.2 : 0.11),
      shadow: Colors.black.withValues(alpha: dark ? 0.28 : 0.08),
    );
  }
}

class _NodeStatusBody extends StatelessWidget {
  final _NodeStatusColors colors;
  final Group? group;
  final List<Proxy> nodes;
  final Map<String, _NodePresentationStatus> nodeStatuses;
  final Map<String, XboardNodeData> nodeMetadata;
  final List<FengWoWorldMapNode> mapNodes;
  final String currentNode;
  final String? selectedName;
  final bool isStart;
  final bool testingAll;
  final int countryCount;
  final double availability;
  final ScrollController nodesScrollController;
  final VoidCallback? onRefresh;
  final ValueChanged<Proxy>? onSelect;
  final ValueChanged<Proxy>? onTest;

  const _NodeStatusBody({
    required this.colors,
    required this.group,
    required this.nodes,
    required this.nodeStatuses,
    required this.nodeMetadata,
    required this.mapNodes,
    required this.currentNode,
    required this.selectedName,
    required this.isStart,
    required this.testingAll,
    required this.countryCount,
    required this.availability,
    required this.nodesScrollController,
    required this.onRefresh,
    required this.onSelect,
    required this.onTest,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 640;
        final horizontalPadding = compact ? 16.0 : 30.0;
        final verticalPadding = compact ? 14.0 : 24.0;
        return Stack(
          children: [
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      colors.background,
                      Color.alphaBlend(
                        colors.primary.withValues(alpha: 0.09),
                        colors.background,
                      ),
                      colors.background,
                    ],
                    stops: const [0, 0.58, 1],
                  ),
                ),
              ),
            ),
            Positioned(
              right: compact ? 18 : 70,
              top: compact ? 18 : 30,
              child: _BackgroundOrb(
                colors: colors,
                icon: Icons.shield_outlined,
                size: compact ? 76 : 118,
              ),
            ),
            Positioned(
              right: compact ? 108 : 250,
              top: compact ? 44 : 94,
              child: _BackgroundOrb(
                colors: colors,
                icon: Icons.wifi_rounded,
                size: compact ? 44 : 68,
              ),
            ),
            Positioned.fill(
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  horizontalPadding,
                  verticalPadding,
                  horizontalPadding,
                  verticalPadding,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _NodeStatusTitle(colors: colors, compact: compact),
                    SizedBox(height: compact ? 12 : 20),
                    Expanded(
                      child: LayoutBuilder(
                        builder: (context, bodyConstraints) {
                          final mapPanel = _NodeDistributionPanel(
                            key: const ValueKey('fengwo-node-status-map'),
                            colors: colors,
                            isStart: isStart,
                            currentNode: currentNode,
                            mapNodes: mapNodes,
                            countryCount: countryCount,
                            nodeCount: nodes.length,
                            availability: availability,
                            compact: compact,
                          );
                          final nodesPanel = _PreferredNodesPanel(
                            key: const ValueKey('fengwo-node-status-list'),
                            colors: colors,
                            group: group,
                            nodes: nodes,
                            nodeStatuses: nodeStatuses,
                            nodeMetadata: nodeMetadata,
                            selectedName: selectedName,
                            testingAll: testingAll,
                            scrollController: nodesScrollController,
                            onRefresh: onRefresh,
                            onSelect: onSelect,
                            onTest: onTest,
                            compact: compact,
                          );
                          if (compact) {
                            final mapHeight = (bodyConstraints.maxHeight * 0.42)
                                .clamp(184.0, 300.0);
                            return Column(
                              children: [
                                SizedBox(height: mapHeight, child: mapPanel),
                                const SizedBox(height: 12),
                                Expanded(child: nodesPanel),
                              ],
                            );
                          }
                          return Row(
                            children: [
                              Expanded(flex: 36, child: mapPanel),
                              const SizedBox(width: 18),
                              Expanded(flex: 64, child: nodesPanel),
                            ],
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _BackgroundOrb extends StatelessWidget {
  final _NodeStatusColors colors;
  final IconData icon;
  final double size;

  const _BackgroundOrb({
    required this.colors,
    required this.icon,
    required this.size,
  });

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: colors.surface.withValues(alpha: 0.24),
          shape: BoxShape.circle,
          border: Border.all(color: colors.primary.withValues(alpha: 0.12)),
        ),
        child: Icon(
          icon,
          color: colors.primary.withValues(alpha: 0.16),
          size: size * 0.48,
        ),
      ),
    );
  }
}

class _NodeStatusTitle extends StatelessWidget {
  final _NodeStatusColors colors;
  final bool compact;

  const _NodeStatusTitle({required this.colors, required this.compact});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: compact ? 72 : 108,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            context.appLocalizations.nodeStatus,
            style: TextStyle(
              color: colors.text,
              fontSize: compact ? 28 : 38,
              fontWeight: FontWeight.w900,
              letterSpacing: -0.8,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            context.appLocalizations.nodeStatusSubtitle,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: colors.muted,
              fontSize: compact ? 13 : 17,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

class _NodeStatusPanel extends StatelessWidget {
  final _NodeStatusColors colors;
  final EdgeInsetsGeometry padding;
  final Widget child;

  const _NodeStatusPanel({
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
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: colors.outline),
        boxShadow: [
          BoxShadow(
            color: colors.shadow,
            blurRadius: 30,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: child,
    );
  }
}

class _NodeDistributionPanel extends StatelessWidget {
  final _NodeStatusColors colors;
  final bool isStart;
  final String currentNode;
  final List<FengWoWorldMapNode> mapNodes;
  final int countryCount;
  final int nodeCount;
  final double availability;
  final bool compact;

  const _NodeDistributionPanel({
    super.key,
    required this.colors,
    required this.isStart,
    required this.currentNode,
    required this.mapNodes,
    required this.countryCount,
    required this.nodeCount,
    required this.availability,
    required this.compact,
  });

  @override
  Widget build(BuildContext context) {
    return _NodeStatusPanel(
      colors: colors,
      padding: EdgeInsets.all(compact ? 14 : 20),
      child: Column(
        children: [
          _PanelTitle(
            colors: colors,
            icon: Icons.shield_outlined,
            label: context.appLocalizations.globalNodeDistribution,
            compact: compact,
          ),
          SizedBox(height: compact ? 2 : 8),
          Expanded(
            child: FengWoWorldMap(
              isStart: isStart,
              showRoute: false,
              interactive: true,
              opacity: 0.54,
              nodeName: currentNode,
              nodes: mapNodes,
            ),
          ),
          SizedBox(height: compact ? 5 : 10),
          Row(
            children: [
              Expanded(
                child: _NodeStat(
                  colors: colors,
                  icon: Icons.public_rounded,
                  label: context.appLocalizations.countriesAndRegions,
                  value: '$countryCount',
                  compact: compact,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _NodeStat(
                  colors: colors,
                  icon: Icons.dns_outlined,
                  label: context.appLocalizations.qualityNodes,
                  value: '$nodeCount',
                  compact: compact,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _NodeStat(
                  colors: colors,
                  icon: Icons.bolt_rounded,
                  label: context.appLocalizations.availabilityRate,
                  value: NumberFormat.percentPattern(
                    Localizations.localeOf(context).toLanguageTag(),
                  ).format(availability),
                  compact: compact,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PanelTitle extends StatelessWidget {
  final _NodeStatusColors colors;
  final IconData icon;
  final String label;
  final bool compact;

  const _PanelTitle({
    required this.colors,
    required this.icon,
    required this.label,
    required this.compact,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: colors.primary, size: compact ? 22 : 28),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: colors.text,
              fontSize: compact ? 16 : 21,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
      ],
    );
  }
}

class _NodeStat extends StatelessWidget {
  final _NodeStatusColors colors;
  final IconData icon;
  final String label;
  final String value;
  final bool compact;

  const _NodeStat({
    required this.colors,
    required this.icon,
    required this.label,
    required this.value,
    required this.compact,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: compact ? 62 : 112,
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 4 : 8,
        vertical: compact ? 6 : 8,
      ),
      decoration: BoxDecoration(
        color: colors.surfaceStrong,
        borderRadius: BorderRadius.circular(compact ? 14 : 20),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (!compact)
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: colors.primarySoft,
                borderRadius: BorderRadius.circular(11),
              ),
              child: Icon(icon, color: colors.primary, size: 20),
            ),
          if (!compact) const SizedBox(height: 6),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: colors.muted,
              fontSize: compact ? 9 : 11,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            maxLines: 1,
            style: TextStyle(
              color: colors.primary,
              fontSize: compact ? 17 : 22,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class _PreferredNodesPanel extends StatelessWidget {
  final _NodeStatusColors colors;
  final Group? group;
  final List<Proxy> nodes;
  final Map<String, _NodePresentationStatus> nodeStatuses;
  final Map<String, XboardNodeData> nodeMetadata;
  final String? selectedName;
  final bool testingAll;
  final ScrollController scrollController;
  final VoidCallback? onRefresh;
  final ValueChanged<Proxy>? onSelect;
  final ValueChanged<Proxy>? onTest;
  final bool compact;

  const _PreferredNodesPanel({
    super.key,
    required this.colors,
    required this.group,
    required this.nodes,
    required this.nodeStatuses,
    required this.nodeMetadata,
    required this.selectedName,
    required this.testingAll,
    required this.scrollController,
    required this.onRefresh,
    required this.onSelect,
    required this.onTest,
    required this.compact,
  });

  @override
  Widget build(BuildContext context) {
    return _NodeStatusPanel(
      colors: colors,
      padding: EdgeInsets.all(compact ? 14 : 20),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: _PanelTitle(
                  colors: colors,
                  icon: Icons.shield_outlined,
                  label: context.appLocalizations.preferredNodes,
                  compact: compact,
                ),
              ),
              if (!compact && group != null) ...[
                Container(
                  constraints: const BoxConstraints(maxWidth: 180),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 7,
                  ),
                  decoration: BoxDecoration(
                    color: colors.primarySoft,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Text(
                    group!.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: colors.primary,
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
              ],
              TextButton.icon(
                key: const ValueKey('fengwo-node-status-refresh'),
                onPressed: testingAll ? null : onRefresh,
                icon: testingAll
                    ? const SizedBox.square(
                        dimension: 17,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.refresh_rounded),
                label: Text(context.appLocalizations.refreshNodes),
              ),
            ],
          ),
          SizedBox(height: compact ? 10 : 16),
          Expanded(
            child: Container(
              padding: EdgeInsets.all(compact ? 7 : 12),
              decoration: BoxDecoration(
                color: colors.surfaceStrong,
                borderRadius: BorderRadius.circular(22),
              ),
              child: nodes.isEmpty
                  ? Center(
                      child: Text(
                        context.appLocalizations.proxyGroupEmpty,
                        style: TextStyle(color: colors.muted),
                      ),
                    )
                  : Scrollbar(
                      controller: scrollController,
                      thumbVisibility: true,
                      radius: const Radius.circular(8),
                      child: ListView.separated(
                        key: const ValueKey(
                          'fengwo-node-status-scrollable-list',
                        ),
                        controller: scrollController,
                        padding: EdgeInsets.only(right: compact ? 8 : 13),
                        physics: const ClampingScrollPhysics(),
                        itemCount: nodes.length,
                        separatorBuilder: (_, _) =>
                            SizedBox(height: compact ? 7 : 10),
                        itemBuilder: (context, index) {
                          final proxy = nodes[index];
                          final metadata = nodeMetadata[proxy.name];
                          return _PreferredNodeRow(
                            key: ValueKey('fengwo-node-row-${proxy.name}'),
                            colors: colors,
                            proxy: proxy,
                            status:
                                nodeStatuses[proxy.name] ??
                                const _NodePresentationStatus(
                                  state: _NodeConnectivityState.unknown,
                                ),
                            rate: metadata?.rate,
                            tags: metadata?.tags ?? const [],
                            selected: selectedName == proxy.name,
                            compact: compact,
                            onSelect: onSelect == null
                                ? null
                                : () => onSelect!(proxy),
                            onTest:
                                onTest == null ||
                                    testingAll ||
                                    nodeStatuses[proxy.name]?.state ==
                                        _NodeConnectivityState.backendOffline
                                ? null
                                : () => onTest!(proxy),
                          );
                        },
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PreferredNodeRow extends StatelessWidget {
  final _NodeStatusColors colors;
  final Proxy proxy;
  final _NodePresentationStatus status;
  final double? rate;
  final List<String> tags;
  final bool selected;
  final bool compact;
  final VoidCallback? onSelect;
  final VoidCallback? onTest;

  const _PreferredNodeRow({
    super.key,
    required this.colors,
    required this.proxy,
    required this.status,
    required this.rate,
    required this.tags,
    required this.selected,
    required this.compact,
    required this.onSelect,
    required this.onTest,
  });

  @override
  Widget build(BuildContext context) {
    final isTesting = status.state == _NodeConnectivityState.testing;
    final statusColor = switch (status.state) {
      _NodeConnectivityState.available => colors.success,
      _NodeConnectivityState.backendOffline ||
      _NodeConnectivityState.unreachable => colors.danger,
      _ => colors.muted,
    };
    final statusBackground = switch (status.state) {
      _NodeConnectivityState.available => colors.successSoft,
      _NodeConnectivityState.backendOffline ||
      _NodeConnectivityState.unreachable => colors.dangerSoft,
      _ => colors.primarySoft,
    };
    final statusText = switch (status.state) {
      _NodeConnectivityState.backendOffline =>
        context.appLocalizations.nodeBackendOffline,
      _NodeConnectivityState.backendOnlineUntested =>
        context.appLocalizations.nodeBackendOnline,
      _NodeConnectivityState.testing => context.appLocalizations.delayTest,
      _NodeConnectivityState.available =>
        context.appLocalizations.nodeAvailable,
      _NodeConnectivityState.unreachable =>
        context.appLocalizations.nodeLocallyUnreachable,
      _NodeConnectivityState.unknown =>
        context.appLocalizations.nodeStatusUnknown,
    };
    final detailText = switch (status.state) {
      _NodeConnectivityState.available when status.delay != null =>
        '${status.delay} ms',
      _NodeConnectivityState.backendOnlineUntested =>
        context.appLocalizations.notTested,
      _ => null,
    };
    return Material(
      color: selected ? colors.primarySoft : colors.surface,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onSelect,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          constraints: BoxConstraints(minHeight: compact ? 70 : 88),
          padding: EdgeInsets.symmetric(
            horizontal: compact ? 10 : 16,
            vertical: compact ? 9 : 12,
          ),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: selected ? colors.primary : Colors.transparent,
              width: selected ? 1.4 : 1,
            ),
            boxShadow: [
              BoxShadow(
                color: colors.shadow.withValues(alpha: 0.55),
                blurRadius: 15,
                offset: const Offset(0, 7),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: compact ? 38 : 44,
                height: compact ? 38 : 44,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: colors.surfaceStrong,
                  shape: BoxShape.circle,
                ),
                child: Text(
                  _nodeFlag(proxy.name, tags),
                  style: TextStyle(fontSize: compact ? 19 : 22),
                ),
              ),
              SizedBox(width: compact ? 9 : 14),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      proxy.name,
                      maxLines: compact ? 1 : 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: colors.text,
                        fontSize: compact ? 13 : 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    if (!compact &&
                        (tags.isNotEmpty || proxy.type.trim().isNotEmpty)) ...[
                      const SizedBox(height: 5),
                      Row(
                        children:
                            (tags.isEmpty
                                    ? [proxy.type.toUpperCase()]
                                    : tags.take(2))
                                .map(
                                  (tag) => Flexible(
                                    child: Container(
                                      margin: const EdgeInsets.only(right: 5),
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 3,
                                      ),
                                      decoration: BoxDecoration(
                                        color: colors.primarySoft,
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Text(
                                        tag,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          color: colors.primary,
                                          fontSize: 10,
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                    ),
                                  ),
                                )
                                .toList(growable: false),
                      ),
                    ],
                  ],
                ),
              ),
              SizedBox(width: compact ? 5 : 10),
              IconButton(
                tooltip: _delayText(context),
                onPressed: isTesting ? null : onTest,
                style: IconButton.styleFrom(
                  backgroundColor: colors.primarySoft,
                  foregroundColor: colors.primary,
                ),
                icon: isTesting
                    ? const SizedBox.square(
                        dimension: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.bolt_rounded),
              ),
              if (!compact) ...[
                const SizedBox(width: 2),
                SizedBox(
                  width: 58,
                  child: Text(
                    _formatNodeRate(rate),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: colors.primary,
                      fontSize: 19,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                Container(width: 1, height: 38, color: colors.outline),
                const SizedBox(width: 14),
              ],
              Container(
                width: compact ? 102 : 132,
                height: compact ? 40 : 48,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: statusBackground,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: isTesting
                    ? SizedBox.square(
                        dimension: compact ? 14 : 16,
                        child: CircularProgressIndicator(
                          color: colors.primary,
                          strokeWidth: 2,
                        ),
                      )
                    : Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 7),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Container(
                                  width: 7,
                                  height: 7,
                                  decoration: BoxDecoration(
                                    color: statusColor,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Flexible(
                                  child: Text(
                                    statusText,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: statusColor,
                                      fontSize: compact ? 10 : 11,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            if (detailText != null)
                              Text(
                                detailText,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: statusColor,
                                  fontSize: compact ? 9 : 10,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                          ],
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _delayText(BuildContext context) {
    return switch (status.state) {
      _NodeConnectivityState.available => '${status.delay} ms',
      _NodeConnectivityState.backendOffline =>
        context.appLocalizations.nodeBackendOffline,
      _NodeConnectivityState.backendOnlineUntested =>
        context.appLocalizations.notTested,
      _NodeConnectivityState.testing => context.appLocalizations.delayTest,
      _NodeConnectivityState.unreachable => context.appLocalizations.timeout,
      _ => context.appLocalizations.nodeStatusUnknown,
    };
  }
}

enum _NodeConnectivityState {
  backendOffline,
  backendOnlineUntested,
  testing,
  available,
  unreachable,
  unknown,
}

class _NodePresentationStatus {
  const _NodePresentationStatus({required this.state, this.delay});

  final _NodeConnectivityState state;
  final int? delay;

  bool get countsAsAvailable =>
      state == _NodeConnectivityState.available ||
      state == _NodeConnectivityState.backendOnlineUntested;

  int? get mapDelay => switch (state) {
    _NodeConnectivityState.available => delay,
    _NodeConnectivityState.backendOffline ||
    _NodeConnectivityState.unreachable => -1,
    _ => null,
  };
}

_NodePresentationStatus _resolveNodeStatus({
  required int? measuredDelay,
  required XboardNodeData? metadata,
  required bool xboardStatusFresh,
  required bool isTesting,
}) {
  if (xboardStatusFresh && metadata?.isOnline == false) {
    return const _NodePresentationStatus(
      state: _NodeConnectivityState.backendOffline,
    );
  }
  if (isTesting || measuredDelay == 0) {
    return const _NodePresentationStatus(state: _NodeConnectivityState.testing);
  }
  if (measuredDelay != null && measuredDelay > 0) {
    return _NodePresentationStatus(
      state: _NodeConnectivityState.available,
      delay: measuredDelay,
    );
  }
  if (measuredDelay != null && measuredDelay < 0) {
    return const _NodePresentationStatus(
      state: _NodeConnectivityState.unreachable,
    );
  }
  if (xboardStatusFresh && metadata?.isOnline == true) {
    return const _NodePresentationStatus(
      state: _NodeConnectivityState.backendOnlineUntested,
    );
  }
  return const _NodePresentationStatus(state: _NodeConnectivityState.unknown);
}

String _formatNodeRate(double? rate) {
  if (rate == null) return '--';
  final value = rate == rate.roundToDouble()
      ? rate.toStringAsFixed(0)
      : rate.toStringAsFixed(2).replaceFirst(RegExp(r'0+$'), '');
  return '${value}x';
}

List<Proxy> _xboardDisplayNodes(List<Proxy> proxies, List<Group> groups) {
  final groupNames = groups.map((group) => group.name).toSet();
  return proxies
      .where((proxy) => _isXboardNode(proxy, groupNames))
      .toList(growable: false);
}

Map<String, XboardNodeData> _matchXboardNodes(
  List<Proxy> proxies,
  List<XboardNodeData> nodes,
) {
  final matches = <String, XboardNodeData>{};
  for (final proxy in proxies) {
    final metadata = matchXboardNodeByName(proxy.name, nodes);
    if (metadata != null) matches[proxy.name] = metadata;
  }
  return matches;
}

int _xboardTagCount(List<XboardNodeData> nodes) {
  return xboardTagCount(nodes);
}

String? _countryCodeFromTags(List<String> tags) {
  for (final tag in tags) {
    final normalized = tag.trim().toUpperCase();
    if (RegExp(r'^[A-Z]{2}$').hasMatch(normalized)) return normalized;
  }
  return _nodeCountryCode(tags.join(' '));
}

bool _isXboardNode(Proxy proxy, Set<String> groupNames) {
  if (groupNames.contains(proxy.name)) return false;
  final type = proxy.type.toLowerCase().replaceAll(RegExp(r'[-_\s]'), '');
  const groupTypes = {
    'select',
    'selector',
    'urltest',
    'fallback',
    'loadbalance',
    'relay',
  };
  if (groupTypes.contains(type)) return false;
  final name = proxy.name.trim().toLowerCase();
  if (const {
    'direct',
    'reject',
    'reject-drop',
    'pass',
    'global',
  }.contains(name)) {
    return false;
  }
  const metadataTokens = <String>[
    '剩余流量',
    '流量剩余',
    '套餐到期',
    '到期时间',
    '长期有效',
    '续费:',
    '续费：',
    '官网:',
    '官网：',
    '商城http',
    '客服:',
    '客服：',
    '订阅地址',
    '更新订阅',
    'http://',
    'https://',
  ];
  return !metadataTokens.any(name.contains);
}

String _nodeFlag(String name, List<String> tags) {
  final code = _countryCodeFromTags(tags) ?? _nodeCountryCode(name);
  if (code == null || code.length != 2) return '🌐';
  return String.fromCharCodes([
    code.codeUnitAt(0) - 0x41 + 0x1F1E6,
    code.codeUnitAt(1) - 0x41 + 0x1F1E6,
  ]);
}

String? _nodeCountryCode(String name) {
  final value = name.toLowerCase();
  final runes = name.runes.toList();
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
    'HK': ['香港', 'hong kong'],
    'TW': ['台湾', '臺灣', 'taiwan'],
    'JP': ['日本', '东京', '大阪', 'japan', 'tokyo', 'osaka'],
    'KR': ['韩国', '韓國', '首尔', '首爾', 'korea', 'seoul'],
    'SG': ['新加坡', 'singapore'],
    'US': ['美国', '美國', '洛杉矶', '洛杉磯', '西雅图', 'united states', 'usa'],
    'CA': ['加拿大', 'canada', 'toronto', 'vancouver'],
    'GB': ['英国', '英國', 'united kingdom', 'london'],
    'DE': ['德国', '德國', 'germany', 'frankfurt'],
    'FR': ['法国', '法國', 'france', 'paris'],
    'NL': ['荷兰', '荷蘭', 'netherlands'],
    'RU': ['俄罗斯', '俄羅斯', 'russia', 'moscow'],
    'IN': ['印度', 'india'],
    'TH': ['泰国', '泰國', 'thailand'],
    'VN': ['越南', 'vietnam'],
    'MY': ['马来西亚', '馬來西亞', 'malaysia'],
    'PH': ['菲律宾', '菲律賓', 'philippines'],
    'ID': ['印度尼西亚', '印尼', 'indonesia'],
    'AU': ['澳大利亚', '澳洲', 'australia', 'sydney'],
    'CN': ['中国', '中國', 'china'],
  };
  for (final entry in tokens.entries) {
    if (entry.value.any(value.contains)) return entry.key;
  }
  return null;
}

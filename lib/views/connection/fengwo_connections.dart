import 'dart:math' as math;

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/core/controller.dart';
import 'package:fl_clash/core/method.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/state.dart';
import 'package:fl_clash/widgets/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:super_sliver_list/super_sliver_list.dart';

import 'item.dart';

typedef FengWoConnectionRuleApplier =
    Future<void> Function({
      required TrackerInfo connection,
      required Rule rule,
      required String? fallbackTarget,
      required bool switchToRuleMode,
    });

enum _ConnectionSort {
  destination,
  downloadSpeed,
  uploadSpeed,
  download,
  upload,
  start,
}

enum _ConnectionAction { details, addRule, close }

class FengWoConnectionsView extends ConsumerStatefulWidget {
  final Future<List<TrackerInfo>> Function()? connectionsReader;
  final Future<void> Function(String id)? connectionCloser;
  final Future<void> Function()? allConnectionsCloser;
  final FengWoConnectionRuleApplier? ruleApplier;
  final DateTime Function()? now;

  const FengWoConnectionsView({
    super.key,
    @visibleForTesting this.connectionsReader,
    @visibleForTesting this.connectionCloser,
    @visibleForTesting this.allConnectionsCloser,
    @visibleForTesting this.ruleApplier,
    @visibleForTesting this.now,
  });

  @override
  ConsumerState<FengWoConnectionsView> createState() =>
      _FengWoConnectionsViewState();
}

class _FengWoConnectionsViewState extends ConsumerState<FengWoConnectionsView>
    with WidgetsBindingObserver, ActivePollingMixin<FengWoConnectionsView> {
  final _searchController = TextEditingController();
  final _desktopVerticalController = ScrollController();
  final _desktopHorizontalController = ScrollController();
  final Map<String, _ConnectionSample> _samples = {};

  List<TrackerInfo> _connections = const [];
  String _query = '';
  bool _autoRefresh = true;
  bool _loading = true;
  bool _refreshing = false;
  bool _closingAll = false;
  _ConnectionSort _sort = _ConnectionSort.start;
  bool _ascending = false;

  @override
  Duration get pollInterval => const Duration(seconds: 1);

  @override
  bool get canPoll => _autoRefresh && super.canPoll;

  DateTime get _now => widget.now?.call() ?? DateTime.now();

  @override
  Future<void> poll(PollGuard isCurrent) async {
    final connections = await _readConnections();
    if (connections == null || !isCurrent()) return;
    _applySnapshot(connections);
  }

  Future<List<TrackerInfo>?> _readConnections() async {
    try {
      return widget.connectionsReader != null
          ? await widget.connectionsReader!()
          : await coreController.getConnections();
    } catch (error) {
      commonPrint.log(
        'load live connections failed: $error',
        logLevel: coreFailureLogLevel(error),
      );
      return null;
    }
  }

  void _applySnapshot(List<TrackerInfo> rawConnections) {
    final sampledAt = _now;
    final nextSamples = <String, _ConnectionSample>{};
    final nextConnections = rawConnections
        .map((connection) {
          final previous = _samples[connection.id];
          final elapsedMicros = previous == null
              ? 0
              : sampledAt.difference(previous.sampledAt).inMicroseconds;
          final downloadSpeed = elapsedMicros <= 0
              ? connection.downloadSpeed ?? 0
              : math.max(
                  0,
                  ((connection.download - previous!.download) *
                          Duration.microsecondsPerSecond /
                          elapsedMicros)
                      .round(),
                );
          final uploadSpeed = elapsedMicros <= 0
              ? connection.uploadSpeed ?? 0
              : math.max(
                  0,
                  ((connection.upload - previous!.upload) *
                          Duration.microsecondsPerSecond /
                          elapsedMicros)
                      .round(),
                );
          nextSamples[connection.id] = _ConnectionSample(
            download: connection.download,
            upload: connection.upload,
            sampledAt: sampledAt,
          );
          return connection.copyWith(
            downloadSpeed: downloadSpeed,
            uploadSpeed: uploadSpeed,
          );
        })
        .toList(growable: false);
    if (!mounted) return;
    setState(() {
      _samples
        ..clear()
        ..addAll(nextSamples);
      _connections = nextConnections;
      _loading = false;
      _refreshing = false;
    });
  }

  Future<void> _refresh({bool userInitiated = true}) async {
    if (_refreshing) return;
    setState(() => _refreshing = true);
    final connections = await _readConnections();
    if (!mounted) return;
    if (connections == null) {
      setState(() {
        _loading = false;
        _refreshing = false;
      });
      if (userInitiated) {
        context.showNotifier(context.appLocalizations.liveConnectionsFailed);
      }
      return;
    }
    _applySnapshot(connections);
  }

  void _toggleAutoRefresh(bool value) {
    if (_autoRefresh == value) return;
    setState(() => _autoRefresh = value);
    if (value) {
      startPolling();
    } else {
      stopPolling();
    }
  }

  void _changeSort(_ConnectionSort sort) {
    setState(() {
      if (_sort == sort) {
        _ascending = !_ascending;
      } else {
        _sort = sort;
        _ascending = sort == _ConnectionSort.destination;
      }
    });
  }

  List<TrackerInfo> get _visibleConnections {
    final query = _query.trim().toLowerCase();
    final filtered = query.isEmpty
        ? List<TrackerInfo>.from(_connections)
        : _connections.where((connection) {
            final metadata = connection.metadata;
            return <String>[
              metadata.host,
              metadata.destinationIP,
              metadata.destinationPort,
              metadata.process,
              connection.rule,
              connection.rulePayload,
              ...connection.chains,
            ].any((value) => value.toLowerCase().contains(query));
          }).toList();
    filtered.sort((left, right) {
      final result = switch (_sort) {
        _ConnectionSort.destination => _destination(
          left,
        ).compareTo(_destination(right)),
        _ConnectionSort.downloadSpeed => (left.downloadSpeed ?? 0).compareTo(
          right.downloadSpeed ?? 0,
        ),
        _ConnectionSort.uploadSpeed => (left.uploadSpeed ?? 0).compareTo(
          right.uploadSpeed ?? 0,
        ),
        _ConnectionSort.download => left.download.compareTo(right.download),
        _ConnectionSort.upload => left.upload.compareTo(right.upload),
        _ConnectionSort.start => left.start.compareTo(right.start),
      };
      return _ascending ? result : -result;
    });
    return filtered;
  }

  String _destination(TrackerInfo connection) {
    final metadata = connection.metadata;
    final host = metadata.host.takeFirstValid([metadata.destinationIP]);
    return metadata.destinationPort.isEmpty
        ? host
        : '$host:${metadata.destinationPort}';
  }

  String _node(TrackerInfo connection) {
    return connection.chains.firstOrNull?.takeFirstValid([
          RuleTarget.DIRECT.name,
        ]) ??
        RuleTarget.DIRECT.name;
  }

  int get _downloadSpeed => _connections.fold(
    0,
    (total, connection) => total + (connection.downloadSpeed ?? 0),
  );

  int get _uploadSpeed => _connections.fold(
    0,
    (total, connection) => total + (connection.uploadSpeed ?? 0),
  );

  Future<void> _closeConnection(TrackerInfo connection) async {
    try {
      if (widget.connectionCloser != null) {
        await widget.connectionCloser!(connection.id);
      } else {
        await coreController.closeConnection(connection.id);
      }
      _samples.remove(connection.id);
      await _refresh(userInitiated: false);
    } catch (error) {
      if (mounted) context.showNotifier(error.toString());
    }
  }

  Future<void> _closeAllConnections() async {
    if (_connections.isEmpty || _closingAll) return;
    final confirmed = await globalState.showMessage(
      title: context.appLocalizations.closeAllConnections,
      message: TextSpan(
        text: context.appLocalizations.closeAllConnectionsDescription,
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _closingAll = true);
    try {
      if (widget.allConnectionsCloser != null) {
        await widget.allConnectionsCloser!();
      } else {
        await coreController.closeConnections();
      }
      _samples.clear();
      await _refresh(userInitiated: false);
    } catch (error) {
      if (mounted) context.showNotifier(error.toString());
    } finally {
      if (mounted) setState(() => _closingAll = false);
    }
  }

  Future<void> _showDetails(TrackerInfo connection) async {
    await showExtend(
      context,
      builder: (_) => AdaptiveSheetScaffold(
        body: TrackerInfoDetailView(trackerInfo: connection),
        title: context.appLocalizations.connectionDetails,
      ),
    );
  }

  Future<void> _showRuleDialog(TrackerInfo connection) async {
    final groups = ref.read(groupsProvider);
    final groupTargets = groups
        .where((group) => group.name != GroupName.GLOBAL.name)
        .map((group) => group.name)
        .where((name) => name.isNotEmpty)
        .toSet()
        .toList(growable: false);
    final allTargets = <String>[
      RuleTarget.DIRECT.name,
      RuleTarget.REJECT.name,
      ...groupTargets,
    ];
    final mode = ref.read(patchClashConfigProvider).mode;
    await showDialog<void>(
      context: context,
      builder: (_) => _AddConnectionRuleDialog(
        connection: connection,
        policyTargets: allTargets,
        fallbackTargets: groupTargets,
        switchToRuleMode: mode == Mode.global,
        onApply:
            ({
              required rule,
              required fallbackTarget,
              required switchToRuleMode,
            }) async {
              if (widget.ruleApplier != null) {
                await widget.ruleApplier!(
                  connection: connection,
                  rule: rule,
                  fallbackTarget: fallbackTarget,
                  switchToRuleMode: switchToRuleMode,
                );
              } else {
                await _applyRule(
                  connection: connection,
                  rule: rule,
                  fallbackTarget: fallbackTarget,
                  switchToRuleMode: switchToRuleMode,
                );
              }
            },
      ),
    );
  }

  Future<void> _applyRule({
    required TrackerInfo connection,
    required Rule rule,
    required String? fallbackTarget,
    required bool switchToRuleMode,
  }) async {
    final profile = ref.read(currentProfileProvider);
    if (profile == null) {
      throw context.appLocalizations.noProfileForRule;
    }
    final provider = profileAddedRulesProvider(profile.id);
    final notifier = ref.read(provider.notifier);
    final existingRules = ref.read(provider).value ?? const <Rule>[];
    var changed = false;
    if (switchToRuleMode && fallbackTarget?.isNotEmpty == true) {
      final existingMatch = existingRules
          .where((item) => item.ruleAction == RuleAction.MATCH)
          .firstOrNull;
      final lastOrder = existingRules.lastOrNull?.order;
      final fallbackRule = Rule(
        id: existingMatch?.id ?? snowflake.id,
        ruleAction: RuleAction.MATCH,
        ruleTarget: fallbackTarget,
        order: indexing.generateKeyBetween(lastOrder, null),
      );
      if (existingMatch?.ruleTarget != fallbackTarget ||
          existingMatch?.order != fallbackRule.order) {
        await notifier.putAndWait(fallbackRule);
        changed = true;
      }
    }
    final currentRules = ref.read(provider).value ?? const <Rule>[];
    final duplicate = currentRules.any(
      (item) =>
          item.ruleAction == rule.ruleAction &&
          item.realContent == rule.realContent &&
          item.realTarget == rule.realTarget,
    );
    if (!duplicate) {
      await notifier.putAndWait(rule);
      changed = true;
    }
    if (switchToRuleMode) {
      ref.read(setupActionProvider.notifier).changeMode(Mode.rule);
    }
    await ref
        .read(setupActionProvider.notifier)
        .applyProfile(force: true, silence: true);
    await _closeConnection(connection);
    if (!mounted) return;
    context.showNotifier(
      !changed
          ? context.appLocalizations.connectionRuleAlreadyExists
          : switchToRuleMode
          ? context.appLocalizations.connectionRuleAppliedAndSwitched
          : context.appLocalizations.connectionRuleApplied,
    );
  }

  void _handleAction(_ConnectionAction action, TrackerInfo connection) {
    switch (action) {
      case _ConnectionAction.details:
        _showDetails(connection);
      case _ConnectionAction.addRule:
        _showRuleDialog(connection);
      case _ConnectionAction.close:
        _closeConnection(connection);
    }
  }

  int? _currentDelay(WidgetRef ref) {
    final groups = ref.watch(groupsProvider);
    final profile = ref.watch(currentProfileProvider);
    if (groups.isEmpty) return null;
    final group =
        groups.getGroup(profile?.currentGroupName ?? '') ?? groups.first;
    final proxyName = group.getCurrentSelectedName(
      profile?.selectedMap[group.name] ?? '',
    );
    if (proxyName.isEmpty) return null;
    return ref.watch(
      delayProvider(proxyName: proxyName, testUrl: group.testUrl),
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    _desktopVerticalController.dispose();
    _desktopHorizontalController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = _ConnectionColors.of(context);
    final delay = _currentDelay(ref);
    final connections = _visibleConnections;
    return Material(
      color: colors.background,
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth >= 1050) {
            return _buildDesktop(colors, connections, delay);
          }
          return _buildMobile(colors, connections, delay);
        },
      ),
    );
  }

  Widget _buildDesktop(
    _ConnectionColors colors,
    List<TrackerInfo> connections,
    int? delay,
  ) {
    return Column(
      children: [
        _ConnectionHero(colors: colors),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 22),
            child: Column(
              children: [
                Expanded(
                  child: _ConnectionPanel(
                    colors: colors,
                    connectionCount: _connections.length,
                    searchController: _searchController,
                    query: _query,
                    autoRefresh: _autoRefresh,
                    refreshing: _refreshing,
                    closingAll: _closingAll,
                    onQueryChanged: (value) => setState(() => _query = value),
                    onAutoRefreshChanged: _toggleAutoRefresh,
                    onRefresh: _refresh,
                    onCloseAll: _closeAllConnections,
                    child: _buildDesktopTable(colors, connections),
                  ),
                ),
                const SizedBox(height: 14),
                _ConnectionSummaryRow(
                  colors: colors,
                  active: _connections.length,
                  downloadSpeed: _downloadSpeed,
                  uploadSpeed: _uploadSpeed,
                  delay: delay,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildMobile(
    _ConnectionColors colors,
    List<TrackerInfo> connections,
    int? delay,
  ) {
    return RefreshIndicator(
      onRefresh: _refresh,
      child: CustomScrollView(
        key: const ValueKey('fengwo-connections-mobile-scroll'),
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverToBoxAdapter(child: _ConnectionHero(colors: colors)),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
            sliver: SliverToBoxAdapter(
              child: _ConnectionMobileControls(
                colors: colors,
                connectionCount: _connections.length,
                controller: _searchController,
                autoRefresh: _autoRefresh,
                refreshing: _refreshing,
                closingAll: _closingAll,
                onQueryChanged: (value) => setState(() => _query = value),
                onAutoRefreshChanged: _toggleAutoRefresh,
                onRefresh: _refresh,
                onCloseAll: _closeAllConnections,
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
            sliver: SliverToBoxAdapter(
              child: _ConnectionSummaryRow(
                colors: colors,
                active: _connections.length,
                downloadSpeed: _downloadSpeed,
                uploadSpeed: _uploadSpeed,
                delay: delay,
                compact: true,
              ),
            ),
          ),
          if (_loading)
            const SliverFillRemaining(
              hasScrollBody: false,
              child: Center(child: CircularProgressIndicator()),
            )
          else if (connections.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: _ConnectionEmptyState(
                colors: colors,
                hasQuery: _query.trim().isNotEmpty,
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 24),
              sliver: SliverList.separated(
                itemCount: connections.length,
                separatorBuilder: (_, _) => const SizedBox(height: 10),
                itemBuilder: (context, index) {
                  final connection = connections[index];
                  return _MobileConnectionCard(
                    key: ValueKey('fengwo-mobile-connection-${connection.id}'),
                    colors: colors,
                    connection: connection,
                    destination: _destination(connection),
                    node: _node(connection),
                    now: _now,
                    onAction: (action) => _handleAction(action, connection),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildDesktopTable(
    _ConnectionColors colors,
    List<TrackerInfo> connections,
  ) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (connections.isEmpty) {
      return _ConnectionEmptyState(
        colors: colors,
        hasQuery: _query.trim().isNotEmpty,
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final tableWidth = math.max(1180.0, constraints.maxWidth);
        return Scrollbar(
          controller: _desktopHorizontalController,
          thumbVisibility: tableWidth > constraints.maxWidth,
          notificationPredicate: (notification) => notification.depth == 0,
          child: SingleChildScrollView(
            controller: _desktopHorizontalController,
            scrollDirection: Axis.horizontal,
            child: SizedBox(
              width: tableWidth,
              height: constraints.maxHeight,
              child: Column(
                children: [
                  _ConnectionTableHeader(
                    colors: colors,
                    sort: _sort,
                    ascending: _ascending,
                    onSort: _changeSort,
                  ),
                  Expanded(
                    child: SuperListView.separated(
                      controller: _desktopVerticalController,
                      itemCount: connections.length,
                      separatorBuilder: (_, _) =>
                          Divider(height: 1, color: colors.outline),
                      itemBuilder: (context, index) {
                        final connection = connections[index];
                        return _ConnectionTableRow(
                          key: ValueKey(
                            'fengwo-desktop-connection-${connection.id}',
                          ),
                          colors: colors,
                          connection: connection,
                          destination: _destination(connection),
                          node: _node(connection),
                          now: _now,
                          onAction: (action) =>
                              _handleAction(action, connection),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _ConnectionSample {
  final int download;
  final int upload;
  final DateTime sampledAt;

  const _ConnectionSample({
    required this.download,
    required this.upload,
    required this.sampledAt,
  });
}

class _ConnectionColors {
  final Color background;
  final Color surface;
  final Color surfaceSoft;
  final Color primary;
  final Color primarySoft;
  final Color text;
  final Color muted;
  final Color outline;
  final Color success;
  final Color successSoft;
  final Color danger;
  final Color dangerSoft;
  final Color blue;
  final Color cyan;
  final Color purple;
  final Color shadow;

  const _ConnectionColors({
    required this.background,
    required this.surface,
    required this.surfaceSoft,
    required this.primary,
    required this.primarySoft,
    required this.text,
    required this.muted,
    required this.outline,
    required this.success,
    required this.successSoft,
    required this.danger,
    required this.dangerSoft,
    required this.blue,
    required this.cyan,
    required this.purple,
    required this.shadow,
  });

  factory _ConnectionColors.of(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dark = scheme.brightness == Brightness.dark;
    final success = dark ? const Color(0xFF49E39D) : const Color(0xFF19B96B);
    final danger = dark ? const Color(0xFFFF7C91) : const Color(0xFFE74762);
    return _ConnectionColors(
      background: Color.alphaBlend(
        scheme.primary.withValues(alpha: dark ? 0.055 : 0.035),
        scheme.surface,
      ),
      surface: dark ? scheme.surfaceContainer : scheme.surfaceContainerLowest,
      surfaceSoft: dark
          ? scheme.surfaceContainerHigh
          : Color.alphaBlend(
              scheme.primary.withValues(alpha: 0.035),
              scheme.surfaceContainerLowest,
            ),
      primary: scheme.primary,
      primarySoft: scheme.primary.withValues(alpha: dark ? 0.22 : 0.1),
      text: scheme.onSurface,
      muted: scheme.onSurfaceVariant,
      outline: scheme.outlineVariant.withValues(alpha: dark ? 0.68 : 0.82),
      success: success,
      successSoft: success.withValues(alpha: dark ? 0.2 : 0.12),
      danger: danger,
      dangerSoft: danger.withValues(alpha: dark ? 0.2 : 0.11),
      blue: dark ? const Color(0xFF68A8FF) : const Color(0xFF0878EE),
      cyan: dark ? const Color(0xFF45DCE4) : const Color(0xFF16BFCB),
      purple: dark ? const Color(0xFFAE83FF) : const Color(0xFF8055ED),
      shadow: Colors.black.withValues(alpha: dark ? 0.28 : 0.08),
    );
  }
}

class _ConnectionHero extends StatelessWidget {
  final _ConnectionColors colors;

  const _ConnectionHero({required this.colors});

  @override
  Widget build(BuildContext context) {
    final l10n = context.appLocalizations;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(28, 24, 28, 30),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            colors.primarySoft,
            colors.background,
            colors.purple.withValues(alpha: 0.07),
          ],
        ),
      ),
      child: Stack(
        children: [
          PositionedDirectional(
            top: -36,
            end: 20,
            child: IgnorePointer(
              child: Icon(
                Icons.shield_outlined,
                size: 178,
                color: colors.primary.withValues(alpha: 0.08),
              ),
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l10n.realTimeConnections,
                style: TextStyle(
                  color: colors.text,
                  fontSize: 34,
                  height: 1.08,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 7),
              Row(
                children: [
                  Icon(
                    Icons.verified_user_outlined,
                    size: 20,
                    color: colors.muted,
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      l10n.realTimeConnectionsSubtitle,
                      style: TextStyle(
                        color: colors.muted,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ConnectionPanel extends StatelessWidget {
  final _ConnectionColors colors;
  final int connectionCount;
  final TextEditingController searchController;
  final String query;
  final bool autoRefresh;
  final bool refreshing;
  final bool closingAll;
  final ValueChanged<String> onQueryChanged;
  final ValueChanged<bool> onAutoRefreshChanged;
  final VoidCallback onRefresh;
  final VoidCallback onCloseAll;
  final Widget child;

  const _ConnectionPanel({
    required this.colors,
    required this.connectionCount,
    required this.searchController,
    required this.query,
    required this.autoRefresh,
    required this.refreshing,
    required this.closingAll,
    required this.onQueryChanged,
    required this.onAutoRefreshChanged,
    required this.onRefresh,
    required this.onCloseAll,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = context.appLocalizations;
    return Container(
      decoration: BoxDecoration(
        color: colors.surface.withValues(alpha: 0.98),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: colors.outline),
        boxShadow: [BoxShadow(color: colors.shadow, blurRadius: 28)],
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 18, 14),
            child: Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: colors.primarySoft,
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: Icon(
                    Icons.shield_outlined,
                    color: colors.primary,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  l10n.liveConnectionList,
                  style: TextStyle(
                    color: colors.text,
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(width: 10),
                _CountBadge(colors: colors, count: connectionCount),
                const Spacer(),
                SizedBox(
                  width: 285,
                  height: 44,
                  child: TextField(
                    controller: searchController,
                    onChanged: onQueryChanged,
                    decoration: InputDecoration(
                      hintText: l10n.searchConnectionsHint,
                      prefixIcon: const Icon(Icons.search_rounded),
                      suffixIcon: query.isEmpty
                          ? null
                          : IconButton(
                              onPressed: () {
                                searchController.clear();
                                onQueryChanged('');
                              },
                              icon: const Icon(Icons.close_rounded),
                            ),
                      filled: true,
                      fillColor: colors.surfaceSoft,
                      contentPadding: EdgeInsets.zero,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide(color: colors.outline),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide(color: colors.outline),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  l10n.autoRefresh,
                  style: TextStyle(
                    color: colors.text,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Switch(value: autoRefresh, onChanged: onAutoRefreshChanged),
                IconButton.filledTonal(
                  tooltip: l10n.refreshData,
                  onPressed: refreshing ? null : onRefresh,
                  icon: refreshing
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.refresh_rounded),
                ),
                const SizedBox(width: 6),
                IconButton(
                  tooltip: l10n.closeAllConnections,
                  onPressed: connectionCount == 0 || closingAll
                      ? null
                      : onCloseAll,
                  icon: closingAll
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.delete_sweep_outlined),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: colors.outline),
          Expanded(child: child),
        ],
      ),
    );
  }
}

class _ConnectionMobileControls extends StatelessWidget {
  final _ConnectionColors colors;
  final int connectionCount;
  final TextEditingController controller;
  final bool autoRefresh;
  final bool refreshing;
  final bool closingAll;
  final ValueChanged<String> onQueryChanged;
  final ValueChanged<bool> onAutoRefreshChanged;
  final VoidCallback onRefresh;
  final VoidCallback onCloseAll;

  const _ConnectionMobileControls({
    required this.colors,
    required this.connectionCount,
    required this.controller,
    required this.autoRefresh,
    required this.refreshing,
    required this.closingAll,
    required this.onQueryChanged,
    required this.onAutoRefreshChanged,
    required this.onRefresh,
    required this.onCloseAll,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = context.appLocalizations;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: colors.outline),
        boxShadow: [BoxShadow(color: colors.shadow, blurRadius: 20)],
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  l10n.liveConnectionList,
                  style: TextStyle(
                    color: colors.text,
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              _CountBadge(colors: colors, count: connectionCount),
              IconButton(
                tooltip: l10n.closeAllConnections,
                onPressed: connectionCount == 0 || closingAll
                    ? null
                    : onCloseAll,
                icon: const Icon(Icons.delete_sweep_outlined),
              ),
            ],
          ),
          const SizedBox(height: 10),
          TextField(
            controller: controller,
            onChanged: onQueryChanged,
            decoration: InputDecoration(
              hintText: l10n.searchConnectionsHint,
              prefixIcon: const Icon(Icons.search_rounded),
              filled: true,
              fillColor: colors.surfaceSoft,
              contentPadding: EdgeInsets.zero,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(color: colors.outline),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(color: colors.outline),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        l10n.autoRefresh,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: colors.text,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    Transform.scale(
                      scale: 0.86,
                      child: Switch(
                        value: autoRefresh,
                        onChanged: onAutoRefreshChanged,
                      ),
                    ),
                  ],
                ),
              ),
              FilledButton.tonalIcon(
                onPressed: refreshing ? null : onRefresh,
                icon: const Icon(Icons.refresh_rounded),
                label: Text(l10n.refreshNodes),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CountBadge extends StatelessWidget {
  final _ConnectionColors colors;
  final int count;

  const _CountBadge({required this.colors, required this.count});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
      decoration: BoxDecoration(
        color: colors.primarySoft,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Text(
        context.appLocalizations.liveConnectionsCount(count),
        style: TextStyle(
          color: colors.primary,
          fontSize: 12,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _ConnectionSummaryRow extends StatelessWidget {
  final _ConnectionColors colors;
  final int active;
  final int downloadSpeed;
  final int uploadSpeed;
  final int? delay;
  final bool compact;

  const _ConnectionSummaryRow({
    required this.colors,
    required this.active,
    required this.downloadSpeed,
    required this.uploadSpeed,
    required this.delay,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = context.appLocalizations;
    final cards = [
      _ConnectionSummaryCard(
        colors: colors,
        icon: Icons.monitor_heart_outlined,
        accent: colors.blue,
        label: l10n.currentActiveConnections,
        value: '$active',
      ),
      _ConnectionSummaryCard(
        colors: colors,
        icon: Icons.arrow_downward_rounded,
        accent: colors.cyan,
        label: l10n.downloadSpeed,
        value: _formatRate(downloadSpeed),
      ),
      _ConnectionSummaryCard(
        colors: colors,
        icon: Icons.arrow_upward_rounded,
        accent: colors.purple,
        label: l10n.uploadSpeed,
        value: _formatRate(uploadSpeed),
      ),
      _ConnectionSummaryCard(
        colors: colors,
        icon: Icons.sensors_rounded,
        accent: colors.success,
        label: l10n.currentNodeDelay,
        value: delay != null && delay! > 0 ? '${delay!} ms' : '-- ms',
      ),
    ];
    if (!compact) {
      return Row(
        children: [
          for (var index = 0; index < cards.length; index++) ...[
            Expanded(child: cards[index]),
            if (index != cards.length - 1) const SizedBox(width: 12),
          ],
        ],
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = (constraints.maxWidth - 10) / 2;
        return Wrap(
          spacing: 10,
          runSpacing: 10,
          children: cards
              .map((card) => SizedBox(width: width, child: card))
              .toList(growable: false),
        );
      },
    );
  }
}

class _ConnectionSummaryCard extends StatelessWidget {
  final _ConnectionColors colors;
  final IconData icon;
  final Color accent;
  final String label;
  final String value;

  const _ConnectionSummaryCard({
    required this.colors,
    required this.icon,
    required this.accent,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      key: ValueKey('connection-summary-$label'),
      constraints: const BoxConstraints(minHeight: 88),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: colors.outline),
        boxShadow: [BoxShadow(color: colors.shadow, blurRadius: 18)],
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.13),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: accent),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: colors.muted,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: colors.text,
                    fontSize: 22,
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

class _ConnectionTableHeader extends StatelessWidget {
  final _ConnectionColors colors;
  final _ConnectionSort sort;
  final bool ascending;
  final ValueChanged<_ConnectionSort> onSort;

  const _ConnectionTableHeader({
    required this.colors,
    required this.sort,
    required this.ascending,
    required this.onSort,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = context.appLocalizations;
    return Container(
      height: 54,
      color: colors.surfaceSoft,
      child: Row(
        children: [
          _SortableHeaderCell(
            colors: colors,
            width: 260,
            label: l10n.domainOrService,
            field: _ConnectionSort.destination,
            active: sort == _ConnectionSort.destination,
            ascending: ascending,
            onSort: onSort,
          ),
          _HeaderCell(colors: colors, width: 105, label: l10n.status),
          _HeaderCell(colors: colors, width: 155, label: l10n.nodeLabel),
          _SortableHeaderCell(
            colors: colors,
            width: 130,
            label: l10n.downloadSpeed,
            field: _ConnectionSort.downloadSpeed,
            active: sort == _ConnectionSort.downloadSpeed,
            ascending: ascending,
            onSort: onSort,
          ),
          _SortableHeaderCell(
            colors: colors,
            width: 130,
            label: l10n.uploadSpeed,
            field: _ConnectionSort.uploadSpeed,
            active: sort == _ConnectionSort.uploadSpeed,
            ascending: ascending,
            onSort: onSort,
          ),
          _SortableHeaderCell(
            colors: colors,
            width: 120,
            label: l10n.downloaded,
            field: _ConnectionSort.download,
            active: sort == _ConnectionSort.download,
            ascending: ascending,
            onSort: onSort,
          ),
          _SortableHeaderCell(
            colors: colors,
            width: 120,
            label: l10n.uploaded,
            field: _ConnectionSort.upload,
            active: sort == _ConnectionSort.upload,
            ascending: ascending,
            onSort: onSort,
          ),
          _SortableHeaderCell(
            colors: colors,
            width: 105,
            label: l10n.accessTime,
            field: _ConnectionSort.start,
            active: sort == _ConnectionSort.start,
            ascending: ascending,
            onSort: onSort,
          ),
          _HeaderCell(colors: colors, width: 55, label: l10n.actions),
        ],
      ),
    );
  }
}

class _HeaderCell extends StatelessWidget {
  final _ConnectionColors colors;
  final double width;
  final String label;

  const _HeaderCell({
    required this.colors,
    required this.width,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(color: colors.muted, fontWeight: FontWeight.w800),
        ),
      ),
    );
  }
}

class _SortableHeaderCell extends StatelessWidget {
  final _ConnectionColors colors;
  final double width;
  final String label;
  final _ConnectionSort field;
  final bool active;
  final bool ascending;
  final ValueChanged<_ConnectionSort> onSort;

  const _SortableHeaderCell({
    required this.colors,
    required this.width,
    required this.label,
    required this.field,
    required this.active,
    required this.ascending,
    required this.onSort,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      height: double.infinity,
      child: InkWell(
        onTap: () => onSort(field),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: active ? colors.primary : colors.muted,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(width: 4),
              Icon(
                active
                    ? ascending
                          ? Icons.arrow_upward_rounded
                          : Icons.arrow_downward_rounded
                    : Icons.unfold_more_rounded,
                size: 16,
                color: active ? colors.primary : colors.muted,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ConnectionTableRow extends StatelessWidget {
  final _ConnectionColors colors;
  final TrackerInfo connection;
  final String destination;
  final String node;
  final DateTime now;
  final ValueChanged<_ConnectionAction> onAction;

  const _ConnectionTableRow({
    super.key,
    required this.colors,
    required this.connection,
    required this.destination,
    required this.node,
    required this.now,
    required this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = context.appLocalizations;
    return SizedBox(
      height: 68,
      child: Row(
        children: [
          SizedBox(
            width: 260,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [
                  Container(
                    width: 9,
                    height: 9,
                    decoration: BoxDecoration(
                      color: colors.success,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(color: colors.successSoft, blurRadius: 6),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  _ConnectionFavicon(colors: colors, destination: destination),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Tooltip(
                      message: destination,
                      child: Text(
                        destination,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: colors.text,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          SizedBox(
            width: 105,
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: colors.successSoft,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Text(
                  l10n.connected,
                  style: TextStyle(
                    color: colors.success,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
          ),
          _ValueCell(colors: colors, width: 155, value: node),
          _ValueCell(
            colors: colors,
            width: 130,
            value: _formatRate(connection.downloadSpeed ?? 0),
            color: colors.blue,
            icon: Icons.arrow_downward_rounded,
          ),
          _ValueCell(
            colors: colors,
            width: 130,
            value: _formatRate(connection.uploadSpeed ?? 0),
            color: colors.success,
            icon: Icons.arrow_upward_rounded,
          ),
          _ValueCell(
            colors: colors,
            width: 120,
            value: _formatBytes(connection.download),
            color: colors.blue,
          ),
          _ValueCell(
            colors: colors,
            width: 120,
            value: _formatBytes(connection.upload),
            color: colors.success,
          ),
          _ValueCell(
            colors: colors,
            width: 105,
            value: _formatDuration(now.difference(connection.start)),
          ),
          SizedBox(
            width: 55,
            child: _ConnectionActionMenu(colors: colors, onSelected: onAction),
          ),
        ],
      ),
    );
  }
}

class _ValueCell extends StatelessWidget {
  final _ConnectionColors colors;
  final double width;
  final String value;
  final Color? color;
  final IconData? icon;

  const _ValueCell({
    required this.colors,
    required this.width,
    required this.value,
    this.color,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(
          children: [
            if (icon != null) ...[
              Icon(icon, size: 17, color: color ?? colors.text),
              const SizedBox(width: 4),
            ],
            Expanded(
              child: Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: color ?? colors.text,
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

class _ConnectionFavicon extends StatelessWidget {
  final _ConnectionColors colors;
  final String destination;

  const _ConnectionFavicon({required this.colors, required this.destination});

  @override
  Widget build(BuildContext context) {
    final normalized = destination.split(':').first;
    final label = normalized
        .split('.')
        .where((part) => part.isNotEmpty)
        .map((part) => part.characters.first.toUpperCase())
        .take(2)
        .join();
    return Container(
      width: 38,
      height: 38,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [colors.primary, colors.cyan],
        ),
        borderRadius: BorderRadius.circular(11),
      ),
      child: Text(
        label.takeFirstValid(['IP']),
        style: const TextStyle(
          color: Colors.white,
          fontSize: 11,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _ConnectionActionMenu extends StatelessWidget {
  final _ConnectionColors colors;
  final ValueChanged<_ConnectionAction> onSelected;

  const _ConnectionActionMenu({required this.colors, required this.onSelected});

  @override
  Widget build(BuildContext context) {
    final l10n = context.appLocalizations;
    return PopupMenuButton<_ConnectionAction>(
      tooltip: l10n.actions,
      onSelected: onSelected,
      itemBuilder: (_) => [
        PopupMenuItem(
          value: _ConnectionAction.details,
          child: ListTile(
            dense: true,
            leading: const Icon(Icons.visibility_outlined),
            title: Text(l10n.viewDetails),
          ),
        ),
        PopupMenuItem(
          value: _ConnectionAction.addRule,
          child: ListTile(
            dense: true,
            leading: Icon(Icons.add_task_rounded, color: colors.primary),
            title: Text(l10n.addRule),
          ),
        ),
        PopupMenuItem(
          value: _ConnectionAction.close,
          child: ListTile(
            dense: true,
            leading: Icon(Icons.link_off_rounded, color: colors.danger),
            title: Text(
              l10n.closeConnection,
              style: TextStyle(color: colors.danger),
            ),
          ),
        ),
      ],
      icon: Icon(Icons.more_vert_rounded, color: colors.muted),
    );
  }
}

class _MobileConnectionCard extends StatelessWidget {
  final _ConnectionColors colors;
  final TrackerInfo connection;
  final String destination;
  final String node;
  final DateTime now;
  final ValueChanged<_ConnectionAction> onAction;

  const _MobileConnectionCard({
    super.key,
    required this.colors,
    required this.connection,
    required this.destination,
    required this.node,
    required this.now,
    required this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = context.appLocalizations;
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: colors.outline),
      ),
      child: Column(
        children: [
          Row(
            children: [
              _ConnectionFavicon(colors: colors, destination: destination),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      destination,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: colors.text,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '${l10n.nodeLabel}: $node · ${_formatDuration(now.difference(connection.start))}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: colors.muted, fontSize: 12),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                decoration: BoxDecoration(
                  color: colors.successSoft,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  l10n.connected,
                  style: TextStyle(
                    color: colors.success,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              _ConnectionActionMenu(colors: colors, onSelected: onAction),
            ],
          ),
          const SizedBox(height: 13),
          Row(
            children: [
              Expanded(
                child: _MobileMetric(
                  colors: colors,
                  icon: Icons.arrow_downward_rounded,
                  label: l10n.downloadSpeed,
                  value: _formatRate(connection.downloadSpeed ?? 0),
                  color: colors.blue,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _MobileMetric(
                  colors: colors,
                  icon: Icons.arrow_upward_rounded,
                  label: l10n.uploadSpeed,
                  value: _formatRate(connection.uploadSpeed ?? 0),
                  color: colors.success,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _MobileMetric(
                  colors: colors,
                  icon: Icons.download_done_rounded,
                  label: l10n.downloaded,
                  value: _formatBytes(connection.download),
                  color: colors.blue,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _MobileMetric(
                  colors: colors,
                  icon: Icons.upload_rounded,
                  label: l10n.uploaded,
                  value: _formatBytes(connection.upload),
                  color: colors.success,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MobileMetric extends StatelessWidget {
  final _ConnectionColors colors;
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  const _MobileMetric({
    required this.colors,
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: colors.surfaceSoft,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 7),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: colors.muted, fontSize: 10),
                ),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: colors.text,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
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

class _ConnectionEmptyState extends StatelessWidget {
  final _ConnectionColors colors;
  final bool hasQuery;

  const _ConnectionEmptyState({required this.colors, required this.hasQuery});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              hasQuery ? Icons.search_off_rounded : Icons.link_off_rounded,
              size: 58,
              color: colors.primary.withValues(alpha: 0.55),
            ),
            const SizedBox(height: 12),
            Text(
              hasQuery
                  ? context.appLocalizations.noMatchingConnections
                  : context.appLocalizations.noActiveConnections,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: colors.muted,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

typedef _RuleDialogApplier =
    Future<void> Function({
      required Rule rule,
      required String? fallbackTarget,
      required bool switchToRuleMode,
    });

class _AddConnectionRuleDialog extends StatefulWidget {
  final TrackerInfo connection;
  final List<String> policyTargets;
  final List<String> fallbackTargets;
  final bool switchToRuleMode;
  final _RuleDialogApplier onApply;

  const _AddConnectionRuleDialog({
    required this.connection,
    required this.policyTargets,
    required this.fallbackTargets,
    required this.switchToRuleMode,
    required this.onApply,
  });

  @override
  State<_AddConnectionRuleDialog> createState() =>
      _AddConnectionRuleDialogState();
}

class _AddConnectionRuleDialogState extends State<_AddConnectionRuleDialog> {
  late final TextEditingController _contentController;
  late final List<RuleAction> _ruleTypes;
  late RuleAction _ruleType;
  late String _target;
  String? _fallbackTarget;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    final metadata = widget.connection.metadata;
    final host = metadata.host.trim();
    final destinationIP = metadata.destinationIP.trim();
    if (host.isNotEmpty) {
      _ruleTypes = const [
        RuleAction.DOMAIN,
        RuleAction.DOMAIN_SUFFIX,
        RuleAction.DOMAIN_KEYWORD,
      ];
      _ruleType = RuleAction.DOMAIN;
      _contentController = TextEditingController(text: host);
    } else {
      final ipv6 = destinationIP.contains(':');
      _ruleTypes = [ipv6 ? RuleAction.IP_CIDR6 : RuleAction.IP_CIDR];
      _ruleType = _ruleTypes.first;
      _contentController = TextEditingController(
        text: destinationIP.isEmpty ? '' : '$destinationIP/${ipv6 ? 128 : 32}',
      );
    }
    _target = widget.policyTargets.contains(RuleTarget.DIRECT.name)
        ? RuleTarget.DIRECT.name
        : widget.policyTargets.firstOrNull ?? RuleTarget.DIRECT.name;
    _fallbackTarget = widget.fallbackTargets.firstOrNull;
  }

  @override
  void dispose() {
    _contentController.dispose();
    super.dispose();
  }

  Future<void> _apply() async {
    final content = _contentController.text.trim();
    if (content.isEmpty || _submitting) return;
    if (widget.switchToRuleMode && _fallbackTarget == null) {
      context.showNotifier(context.appLocalizations.noProxyGroupForFallback);
      return;
    }
    setState(() => _submitting = true);
    try {
      await widget.onApply(
        rule: Rule(
          id: snowflake.id,
          ruleAction: _ruleType,
          content: content,
          ruleTarget: _target,
        ),
        fallbackTarget: widget.switchToRuleMode ? _fallbackTarget : null,
        switchToRuleMode: widget.switchToRuleMode,
      );
      if (mounted) Navigator.of(context).pop();
    } catch (error) {
      if (mounted) context.showNotifier(error.toString());
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = _ConnectionColors.of(context);
    final l10n = context.appLocalizations;
    final preview = Rule(
      ruleAction: _ruleType,
      content: _contentController.text.trim(),
      ruleTarget: _target,
    ).rawValue;
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
      backgroundColor: colors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 680, maxHeight: 760),
        child: SingleChildScrollView(
          padding: EdgeInsets.zero,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(22, 18, 14, 16),
                child: Row(
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: colors.primarySoft,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.rule_folder_outlined,
                        color: colors.primary,
                      ),
                    ),
                    const SizedBox(width: 13),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            l10n.addRule,
                            style: TextStyle(
                              color: colors.text,
                              fontSize: 22,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          Text(
                            l10n.generateMihomoRule,
                            style: TextStyle(color: colors.muted),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: _submitting
                          ? null
                          : () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
              ),
              Divider(height: 1, color: colors.outline),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 20, 24, 22),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _RuleFieldLabel(
                      colors: colors,
                      label: l10n.ruleType,
                      help: l10n.ruleTypeHelp,
                    ),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<RuleAction>(
                      initialValue: _ruleType,
                      decoration: _ruleInputDecoration(colors),
                      items: _ruleTypes
                          .map(
                            (type) => DropdownMenuItem(
                              value: type,
                              child: Text(type.value),
                            ),
                          )
                          .toList(growable: false),
                      onChanged: _submitting
                          ? null
                          : (value) {
                              if (value == null) return;
                              setState(() => _ruleType = value);
                            },
                    ),
                    const SizedBox(height: 18),
                    _RuleFieldLabel(colors: colors, label: l10n.matchContent),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _contentController,
                      enabled: !_submitting,
                      onChanged: (_) => setState(() {}),
                      decoration: _ruleInputDecoration(colors),
                    ),
                    const SizedBox(height: 18),
                    _RuleFieldLabel(colors: colors, label: l10n.targetPolicy),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<String>(
                      initialValue: _target,
                      decoration: _ruleInputDecoration(colors),
                      items: widget.policyTargets
                          .map(
                            (target) => DropdownMenuItem(
                              value: target,
                              child: Text(_targetLabel(context, target)),
                            ),
                          )
                          .toList(growable: false),
                      onChanged: _submitting
                          ? null
                          : (value) {
                              if (value == null) return;
                              setState(() => _target = value);
                            },
                    ),
                    if (widget.switchToRuleMode) ...[
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: colors.primarySoft,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: colors.primary.withValues(alpha: 0.25),
                          ),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              Icons.info_outline_rounded,
                              color: colors.primary,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                l10n.globalRuleModeSwitchHint,
                                style: TextStyle(
                                  color: colors.text,
                                  height: 1.45,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      _RuleFieldLabel(
                        colors: colors,
                        label: l10n.otherTrafficPolicy,
                      ),
                      const SizedBox(height: 8),
                      DropdownButtonFormField<String>(
                        initialValue: _fallbackTarget,
                        decoration: _ruleInputDecoration(colors),
                        hint: Text(l10n.selectProxyGroup),
                        items: widget.fallbackTargets
                            .map(
                              (target) => DropdownMenuItem(
                                value: target,
                                child: Text(target),
                              ),
                            )
                            .toList(growable: false),
                        onChanged: _submitting
                            ? null
                            : (value) =>
                                  setState(() => _fallbackTarget = value),
                      ),
                    ],
                    const SizedBox(height: 20),
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: colors.surfaceSoft,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            l10n.preview,
                            style: TextStyle(
                              color: colors.muted,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 8),
                          SelectableText(
                            preview,
                            style: TextStyle(
                              color: colors.text,
                              fontFamily: 'monospace',
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          if (widget.switchToRuleMode &&
                              _fallbackTarget != null) ...[
                            const SizedBox(height: 5),
                            SelectableText(
                              'MATCH,$_fallbackTarget',
                              style: TextStyle(
                                color: colors.text,
                                fontFamily: 'monospace',
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 22),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: _submitting
                              ? null
                              : () => Navigator.of(context).pop(),
                          child: Text(l10n.cancel),
                        ),
                        const SizedBox(width: 10),
                        FilledButton.icon(
                          key: const ValueKey('apply-connection-rule'),
                          onPressed:
                              _contentController.text.trim().isEmpty ||
                                  _submitting
                              ? null
                              : _apply,
                          icon: _submitting
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.add_rounded),
                          label: Text(l10n.add),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  InputDecoration _ruleInputDecoration(_ConnectionColors colors) {
    return InputDecoration(
      filled: true,
      fillColor: colors.surfaceSoft,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(15),
        borderSide: BorderSide(color: colors.outline),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(15),
        borderSide: BorderSide(color: colors.outline),
      ),
    );
  }

  String _targetLabel(BuildContext context, String target) {
    return switch (target) {
      'DIRECT' => context.appLocalizations.direct,
      'REJECT' => context.appLocalizations.reject,
      _ => target,
    };
  }
}

class _RuleFieldLabel extends StatelessWidget {
  final _ConnectionColors colors;
  final String label;
  final String? help;

  const _RuleFieldLabel({required this.colors, required this.label, this.help});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          label,
          style: TextStyle(color: colors.text, fontWeight: FontWeight.w800),
        ),
        if (help != null) ...[
          const SizedBox(width: 5),
          Tooltip(
            message: help,
            child: Icon(
              Icons.help_outline_rounded,
              size: 18,
              color: colors.success,
            ),
          ),
        ],
      ],
    );
  }
}

String _formatBytes(int bytes) {
  final traffic = math.max(0, bytes).traffic;
  return '${traffic.value} ${traffic.unit}';
}

String _formatRate(int bytes) => '${_formatBytes(bytes)}/s';

String _formatDuration(Duration duration) {
  final safe = duration.isNegative ? Duration.zero : duration;
  final hours = safe.inHours.toString().padLeft(2, '0');
  final minutes = (safe.inMinutes % 60).toString().padLeft(2, '0');
  final seconds = (safe.inSeconds % 60).toString().padLeft(2, '0');
  return '$hours:$minutes:$seconds';
}

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/state.dart';
import 'package:fl_clash/widgets/subscription_status_indicator.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class FengWoTrafficDetailsView extends StatefulWidget {
  final XboardAuthService? authService;
  final VoidCallback? onUpgradePlan;

  const FengWoTrafficDetailsView({
    super.key,
    this.authService,
    this.onUpgradePlan,
  });

  @override
  State<FengWoTrafficDetailsView> createState() =>
      _FengWoTrafficDetailsViewState();
}

class _FengWoTrafficDetailsViewState extends State<FengWoTrafficDetailsView> {
  late final XboardAuthService _authService;
  XboardSubscriptionData? _subscription;
  List<XboardTrafficLog> _records = const [];
  bool _loading = true;
  bool _refreshing = false;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _authService = widget.authService ?? XboardAuthService();
    _subscription = globalState.xboardSubscription;
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadData());
  }

  Future<void> _loadData({bool refreshSubscription = false}) async {
    if (globalState.isOfflineMode) {
      if (!mounted) return;
      setState(() {
        _subscription = globalState.xboardSubscription;
        _loading = false;
        _refreshing = false;
        _failed = false;
      });
      return;
    }
    final session = globalState.xboardSession;
    if (session == null) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _refreshing = false;
        _failed = true;
      });
      return;
    }
    setState(() {
      if (_records.isEmpty) _loading = true;
      _refreshing = refreshSubscription;
      _failed = false;
    });
    try {
      final results = await Future.wait<Object>([
        _authService.fetchTrafficLogs(
          endpoint: session.endpoint,
          authData: session.authData,
        ),
        refreshSubscription
            ? _authService.fetchSubscription(
                endpoint: session.endpoint,
                authData: session.authData,
                userToken: session.token,
                secureSubscription: session.secureSubscription,
              )
            : Future<XboardSubscriptionData>.value(session.subscription),
      ]);
      final records = results[0] as List<XboardTrafficLog>;
      final subscription = results[1] as XboardSubscriptionData;
      if (!mounted) return;
      if (refreshSubscription &&
          globalState.xboardSession?.authData == session.authData) {
        globalState.xboardSession = XboardLoginResult(
          endpoint: session.endpoint,
          token: session.token,
          authData: session.authData,
          isAdmin: session.isAdmin,
          subscription: subscription,
          secureSubscription: session.secureSubscription,
          rawData: session.rawData,
        );
      }
      setState(() {
        _records = records;
        _subscription = subscription;
      });
    } catch (error, stackTrace) {
      commonPrint.log(
        'load XBoard traffic details failed: $error, $stackTrace',
        logLevel: LogLevel.warning,
      );
      if (mounted) setState(() => _failed = true);
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
          _refreshing = false;
        });
      }
    }
  }

  double get _todayTraffic {
    final today = DateTime.now();
    return _records
        .where((record) => _isSameDay(record.recordedAt, today))
        .fold(0, (total, record) => total + record.billedBytes);
  }

  double get _monthTraffic {
    final today = DateTime.now();
    return _records
        .where(
          (record) =>
              record.recordedAt.year == today.year &&
              record.recordedAt.month == today.month,
        )
        .fold(0, (total, record) => total + record.billedBytes);
  }

  bool _isSameDay(DateTime left, DateTime right) {
    return left.year == right.year &&
        left.month == right.month &&
        left.day == right.day;
  }

  @override
  Widget build(BuildContext context) {
    final colors = _TrafficColors.of(context);
    return Material(
      color: colors.background,
      child: RefreshIndicator(
        onRefresh: () => _loadData(refreshSubscription: true),
        child: CustomScrollView(
          key: const ValueKey('fengwo-traffic-details-scroll'),
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverToBoxAdapter(child: _buildOverview(colors)),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(24, 18, 24, 0),
              sliver: SliverToBoxAdapter(
                child: SubscriptionPlanActionBar(
                  subscription: _subscription,
                  authService: _authService,
                  onUpgrade: widget.onUpgradePlan,
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(24, 14, 24, 32),
              sliver: SliverToBoxAdapter(child: _buildDetailsPanel(colors)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOverview(_TrafficColors colors) {
    final l10n = context.appLocalizations;
    final subscription = _subscription;
    return Container(
      padding: const EdgeInsets.fromLTRB(28, 26, 28, 24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [colors.primarySoft, colors.background, colors.secondarySoft],
        ),
        border: Border(bottom: BorderSide(color: colors.outline)),
      ),
      child: Stack(
        children: [
          PositionedDirectional(
            top: -18,
            end: 4,
            child: IgnorePointer(
              child: Icon(
                Icons.cloud_sync_outlined,
                size: 168,
                color: colors.primary.withValues(alpha: 0.07),
              ),
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l10n.trafficDetails,
                style: TextStyle(
                  color: colors.text,
                  fontSize: 34,
                  height: 1.1,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 7),
              Text(
                l10n.trafficDetailsSubtitle,
                style: TextStyle(
                  color: colors.muted,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 24),
              LayoutBuilder(
                builder: (context, constraints) {
                  final columns = constraints.maxWidth >= 1050
                      ? 4
                      : constraints.maxWidth >= 520
                      ? 2
                      : 2;
                  const spacing = 14.0;
                  final width =
                      (constraints.maxWidth - spacing * (columns - 1)) /
                      columns;
                  final cards = [
                    _TrafficSummaryCard(
                      key: const ValueKey('traffic-summary-today'),
                      colors: colors,
                      icon: Icons.calendar_month_rounded,
                      accent: colors.blue,
                      label: l10n.todayTraffic,
                      value: _formatBytes(_todayTraffic),
                    ),
                    _TrafficSummaryCard(
                      key: const ValueKey('traffic-summary-month'),
                      colors: colors,
                      icon: Icons.bar_chart_rounded,
                      accent: colors.green,
                      label: l10n.currentMonthTraffic,
                      value: _formatBytes(_monthTraffic),
                    ),
                    _TrafficSummaryCard(
                      key: const ValueKey('traffic-summary-remaining'),
                      colors: colors,
                      icon: Icons.pie_chart_outline_rounded,
                      accent: colors.purple,
                      label: l10n.remainingTraffic,
                      value: _formatQuota(subscription?.remainingBytes ?? 0),
                    ),
                    _TrafficSummaryCard(
                      key: const ValueKey('traffic-summary-total'),
                      colors: colors,
                      icon: Icons.inventory_2_outlined,
                      accent: colors.orange,
                      label: l10n.totalTrafficLabel,
                      value: _formatQuota(
                        subscription?.transferEnableBytes ?? 0,
                      ),
                    ),
                  ];
                  return Wrap(
                    spacing: spacing,
                    runSpacing: spacing,
                    children: cards
                        .map((card) => SizedBox(width: width, child: card))
                        .toList(growable: false),
                  );
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDetailsPanel(_TrafficColors colors) {
    final l10n = context.appLocalizations;
    return Container(
      key: const ValueKey('traffic-records-panel'),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: colors.surface.withValues(alpha: 0.97),
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: colors.outline),
        boxShadow: [BoxShadow(color: colors.shadow, blurRadius: 24)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  l10n.trafficDetailRecords,
                  style: TextStyle(
                    color: colors.text,
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              OutlinedButton.icon(
                key: const ValueKey('refresh-traffic-data'),
                onPressed: _refreshing
                    ? null
                    : () => _loadData(refreshSubscription: true),
                icon: _refreshing
                    ? const SizedBox(
                        width: 17,
                        height: 17,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.refresh_rounded),
                label: Text(l10n.refreshData),
              ),
            ],
          ),
          const SizedBox(height: 18),
          if (_loading)
            const SizedBox(
              height: 280,
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_failed)
            _TrafficStatus(
              colors: colors,
              icon: Icons.cloud_off_outlined,
              label: l10n.trafficRecordsFailed,
              actionLabel: l10n.retry,
              onPressed: _loadData,
            )
          else if (_records.isEmpty)
            _TrafficStatus(
              colors: colors,
              icon: Icons.data_usage_rounded,
              label: l10n.noTrafficRecords,
            )
          else
            LayoutBuilder(
              builder: (context, constraints) {
                if (constraints.maxWidth >= 720) {
                  return _buildDesktopTable(colors);
                }
                return _buildMobileRecords(colors);
              },
            ),
        ],
      ),
    );
  }

  Widget _buildDesktopTable(_TrafficColors colors) {
    final l10n = context.appLocalizations;
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border.all(color: colors.outline),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          children: [
            _TrafficTableRow(
              colors: colors,
              header: true,
              date: l10n.dateLabel,
              download: l10n.downloadTraffic,
              upload: l10n.uploadTraffic,
              rate: l10n.trafficRate,
              total: l10n.totalTrafficLabel,
            ),
            for (var index = 0; index < _records.length; index++)
              _TrafficTableRow(
                key: ValueKey('traffic-record-$index'),
                colors: colors,
                date: DateFormat(
                  'yyyy-MM-dd',
                ).format(_records[index].recordedAt),
                download: _formatBytes(_records[index].downloadBytes),
                upload: _formatBytes(_records[index].uploadBytes),
                rate: '${_records[index].serverRate.fixed()}x',
                total: _formatBytes(_records[index].billedBytes),
                isLast: index == _records.length - 1,
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildMobileRecords(_TrafficColors colors) {
    return Column(
      children: [
        for (var index = 0; index < _records.length; index++) ...[
          _MobileTrafficRecord(
            key: ValueKey('traffic-record-$index'),
            colors: colors,
            record: _records[index],
          ),
          if (index != _records.length - 1) const SizedBox(height: 12),
        ],
      ],
    );
  }
}

class _TrafficColors {
  final Color background;
  final Color surface;
  final Color surfaceSoft;
  final Color primary;
  final Color primarySoft;
  final Color secondarySoft;
  final Color text;
  final Color muted;
  final Color outline;
  final Color shadow;
  final Color blue;
  final Color green;
  final Color purple;
  final Color orange;

  const _TrafficColors({
    required this.background,
    required this.surface,
    required this.surfaceSoft,
    required this.primary,
    required this.primarySoft,
    required this.secondarySoft,
    required this.text,
    required this.muted,
    required this.outline,
    required this.shadow,
    required this.blue,
    required this.green,
    required this.purple,
    required this.orange,
  });

  factory _TrafficColors.of(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dark = scheme.brightness == Brightness.dark;
    return _TrafficColors(
      background: Color.alphaBlend(
        scheme.primary.withValues(alpha: dark ? 0.055 : 0.035),
        scheme.surface,
      ),
      surface: scheme.surfaceContainerLowest,
      surfaceSoft: scheme.surfaceContainerLow,
      primary: scheme.primary,
      primarySoft: scheme.primary.withValues(alpha: dark ? 0.2 : 0.1),
      secondarySoft: scheme.tertiary.withValues(alpha: dark ? 0.11 : 0.055),
      text: scheme.onSurface,
      muted: scheme.onSurfaceVariant,
      outline: scheme.outlineVariant.withValues(alpha: 0.82),
      shadow: Colors.black.withValues(alpha: dark ? 0.3 : 0.075),
      blue: scheme.primary,
      green: dark ? const Color(0xFF62E1B3) : const Color(0xFF22B884),
      purple: dark ? const Color(0xFFC6A1FF) : const Color(0xFF8C5DE8),
      orange: dark ? const Color(0xFFFFB86A) : const Color(0xFFF08A36),
    );
  }
}

class _TrafficSummaryCard extends StatelessWidget {
  final _TrafficColors colors;
  final IconData icon;
  final Color accent;
  final String label;
  final String value;

  const _TrafficSummaryCard({
    super.key,
    required this.colors,
    required this.icon,
    required this.accent,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 126),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 17),
      decoration: BoxDecoration(
        color: colors.surface.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: colors.outline),
        boxShadow: [BoxShadow(color: colors.shadow, blurRadius: 20)],
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 180;
          final iconBox = Container(
            width: compact ? 40 : 54,
            height: compact ? 40 : 54,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.13),
              borderRadius: BorderRadius.circular(compact ? 13 : 18),
            ),
            child: Icon(icon, color: accent, size: compact ? 22 : 28),
          );
          final content = Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: colors.muted,
                  fontSize: compact ? 12 : 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 7),
              Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: colors.text,
                  fontSize: compact ? 19 : 25,
                  height: 1,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          );
          if (compact) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [iconBox, const SizedBox(height: 11), content],
            );
          }
          return Row(
            children: [
              iconBox,
              const SizedBox(width: 14),
              Expanded(child: content),
            ],
          );
        },
      ),
    );
  }
}

class _TrafficTableRow extends StatelessWidget {
  final _TrafficColors colors;
  final String date;
  final String download;
  final String upload;
  final String rate;
  final String total;
  final bool header;
  final bool isLast;

  const _TrafficTableRow({
    super.key,
    required this.colors,
    required this.date,
    required this.download,
    required this.upload,
    required this.rate,
    required this.total,
    this.header = false,
    this.isLast = false,
  });

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(
      color: header ? colors.muted : colors.text,
      fontSize: header ? 13 : 14,
      fontWeight: header ? FontWeight.w800 : FontWeight.w600,
    );
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 17),
      decoration: BoxDecoration(
        color: header ? colors.surfaceSoft : Colors.transparent,
        border: isLast
            ? null
            : Border(bottom: BorderSide(color: colors.outline)),
      ),
      child: Row(
        children: [
          Expanded(flex: 22, child: Text(date, style: style)),
          Expanded(flex: 22, child: Text(download, style: style)),
          Expanded(flex: 22, child: Text(upload, style: style)),
          Expanded(flex: 14, child: Text(rate, style: style)),
          Expanded(
            flex: 20,
            child: Text(
              total,
              style: style.copyWith(
                color: header ? colors.muted : colors.primary,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MobileTrafficRecord extends StatelessWidget {
  final _TrafficColors colors;
  final XboardTrafficLog record;

  const _MobileTrafficRecord({
    super.key,
    required this.colors,
    required this.record,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = context.appLocalizations;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.surfaceSoft,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: colors.outline),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  DateFormat('yyyy-MM-dd').format(record.recordedAt),
                  style: TextStyle(
                    color: colors.text,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              Text(
                _formatBytes(record.billedBytes),
                style: TextStyle(
                  color: colors.primary,
                  fontSize: 17,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _MobileMetric(
                  colors: colors,
                  label: l10n.downloadTraffic,
                  value: _formatBytes(record.downloadBytes),
                ),
              ),
              Expanded(
                child: _MobileMetric(
                  colors: colors,
                  label: l10n.uploadTraffic,
                  value: _formatBytes(record.uploadBytes),
                ),
              ),
              Expanded(
                child: _MobileMetric(
                  colors: colors,
                  label: l10n.trafficRate,
                  value: '${record.serverRate.fixed()}x',
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
  final _TrafficColors colors;
  final String label;
  final String value;

  const _MobileMetric({
    required this.colors,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(color: colors.muted, fontSize: 11),
        ),
        const SizedBox(height: 4),
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
    );
  }
}

class _TrafficStatus extends StatelessWidget {
  final _TrafficColors colors;
  final IconData icon;
  final String label;
  final String? actionLabel;
  final VoidCallback? onPressed;

  const _TrafficStatus({
    required this.colors,
    required this.icon,
    required this.label,
    this.actionLabel,
    this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 280,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: colors.muted, size: 52),
            const SizedBox(height: 12),
            Text(label, style: TextStyle(color: colors.muted)),
            if (actionLabel != null && onPressed != null) ...[
              const SizedBox(height: 14),
              FilledButton.tonalIcon(
                onPressed: onPressed,
                icon: const Icon(Icons.refresh_rounded),
                label: Text(actionLabel!),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

String _formatBytes(num bytes) {
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  var value = bytes.toDouble().clamp(0, double.infinity);
  var unitIndex = 0;
  while (value >= 1024 && unitIndex < units.length - 1) {
    value /= 1024;
    unitIndex++;
  }
  final decimals = value >= 100 ? 0 : 2;
  return '${value.fixed(decimals: decimals)} ${units[unitIndex]}';
}

String _formatQuota(num bytes) {
  if (bytes >= bytesPerGigabyte) {
    final gigabytes = bytes / bytesPerGigabyte;
    final decimals = gigabytes >= 100 ? 0 : 2;
    return '${gigabytes.fixed(decimals: decimals)} GB';
  }
  return _formatBytes(bytes);
}

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/state.dart';
import 'package:fl_clash/views/plans/fengwo_purchase_plans.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class FengWoOrdersView extends StatefulWidget {
  final XboardAuthService? authService;
  final int pageSize;

  const FengWoOrdersView({super.key, this.authService, this.pageSize = 6});

  @override
  State<FengWoOrdersView> createState() => _FengWoOrdersViewState();
}

class _FengWoOrdersViewState extends State<FengWoOrdersView> {
  late final XboardAuthService _authService;
  List<XboardOrderData> _orders = const [];
  bool _loading = true;
  bool _refreshing = false;
  bool _failed = false;
  bool _offline = false;
  String? _loadingDetailTradeNo;
  String? _cancellingTradeNo;
  int _page = 0;

  @override
  void initState() {
    super.initState();
    _authService = widget.authService ?? XboardAuthService();
    globalState.xboardSessionRevisionNotifier.addListener(
      _handleSessionChanged,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadOrders());
  }

  @override
  void dispose() {
    globalState.xboardSessionRevisionNotifier.removeListener(
      _handleSessionChanged,
    );
    super.dispose();
  }

  void _handleSessionChanged() {
    if (!mounted) return;
    setState(() {
      _orders = const [];
      _page = 0;
      _loading = true;
      _failed = false;
    });
    _loadOrders();
  }

  int get _pageCount {
    if (_orders.isEmpty) return 1;
    return (_orders.length / widget.pageSize).ceil();
  }

  List<XboardOrderData> get _visibleOrders {
    final start = _page * widget.pageSize;
    if (start >= _orders.length) return const [];
    final end = (start + widget.pageSize).clamp(0, _orders.length);
    return _orders.sublist(start, end);
  }

  Future<void> _loadOrders({bool refresh = false}) async {
    if (globalState.isOfflineMode) {
      if (!mounted) return;
      setState(() {
        _orders = const [];
        _loading = false;
        _refreshing = false;
        _failed = false;
        _offline = true;
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
        _offline = false;
      });
      return;
    }
    setState(() {
      _loading = _orders.isEmpty;
      _refreshing = refresh;
      _failed = false;
      _offline = false;
    });
    try {
      final orders = await _authService.fetchOrders(
        endpoint: session.endpoint,
        authData: session.authData,
      );
      if (!mounted || globalState.xboardSession?.authData != session.authData) {
        return;
      }
      setState(() {
        _orders = orders;
        _page = _page.clamp(0, _pageCount - 1);
      });
    } catch (error, stackTrace) {
      commonPrint.log(
        'load XBoard orders failed: $error, $stackTrace',
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

  Future<void> _showOrderDetails(XboardOrderData order) async {
    if (_loadingDetailTradeNo != null || globalState.isOfflineMode) return;
    final session = globalState.xboardSession;
    if (session == null) return;
    setState(() => _loadingDetailTradeNo = order.tradeNo);
    try {
      final detail = await _authService.fetchOrderDetail(
        endpoint: session.endpoint,
        authData: session.authData,
        tradeNo: order.tradeNo,
      );
      if (!mounted || globalState.xboardSession?.authData != session.authData) {
        return;
      }
      setState(() => _loadingDetailTradeNo = null);
      await showDialog<void>(
        context: context,
        builder: (_) => _OrderDetailsDialog(order: detail),
      );
    } catch (error, stackTrace) {
      commonPrint.log(
        'load XBoard order detail failed: $error, $stackTrace',
        logLevel: LogLevel.warning,
      );
      if (mounted) {
        context.showNotifier(
          error is XboardAuthException
              ? error.message
              : context.appLocalizations.requestFailed,
        );
      }
    } finally {
      if (mounted) setState(() => _loadingDetailTradeNo = null);
    }
  }

  Future<void> _cancelOrder(XboardOrderData order) async {
    if (!order.canCancel || _cancellingTradeNo != null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        icon: const Icon(Icons.cancel_outlined),
        title: Text(dialogContext.appLocalizations.cancelOrderTitle),
        content: Text(dialogContext.appLocalizations.cancelOrderMessage),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(dialogContext.appLocalizations.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(dialogContext.appLocalizations.cancelOrder),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final session = globalState.xboardSession;
    if (session == null || globalState.isOfflineMode) return;
    setState(() => _cancellingTradeNo = order.tradeNo);
    try {
      await _authService.cancelOrder(
        endpoint: session.endpoint,
        authData: session.authData,
        tradeNo: order.tradeNo,
      );
      if (!mounted || globalState.xboardSession?.authData != session.authData) {
        return;
      }
      context.showNotifier(context.appLocalizations.orderCancelledSuccess);
      await _loadOrders(refresh: true);
    } catch (error, stackTrace) {
      commonPrint.log(
        'cancel XBoard order failed: $error, $stackTrace',
        logLevel: LogLevel.warning,
      );
      if (mounted) {
        context.showNotifier(
          error is XboardAuthException
              ? error.message
              : context.appLocalizations.requestFailed,
        );
      }
    } finally {
      if (mounted) setState(() => _cancellingTradeNo = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = _OrderColors.of(context);
    return Material(
      color: colors.background,
      child: RefreshIndicator(
        onRefresh: () => _loadOrders(refresh: true),
        child: CustomScrollView(
          key: const ValueKey('fengwo-orders-scroll'),
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverToBoxAdapter(child: _buildHeader(colors)),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(24, 18, 24, 32),
              sliver: SliverToBoxAdapter(child: _buildOrdersPanel(colors)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(_OrderColors colors) {
    final l10n = context.appLocalizations;
    return Container(
      padding: const EdgeInsets.fromLTRB(28, 26, 28, 26),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [colors.primarySoft, colors.background, colors.accentSoft],
        ),
        border: Border(bottom: BorderSide(color: colors.outline)),
      ),
      child: Stack(
        children: [
          PositionedDirectional(
            top: -30,
            end: 8,
            child: Icon(
              Icons.receipt_long_rounded,
              size: 176,
              color: colors.primary.withValues(alpha: 0.07),
            ),
          ),
          Row(
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: colors.primarySoft,
                  borderRadius: BorderRadius.circular(22),
                ),
                child: Icon(
                  Icons.receipt_long_rounded,
                  color: colors.primary,
                  size: 34,
                ),
              ),
              const SizedBox(width: 18),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.myOrders,
                      style: TextStyle(
                        color: colors.text,
                        fontSize: 34,
                        height: 1.05,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      l10n.orderCenterSubtitle,
                      style: TextStyle(
                        color: colors.muted,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
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

  Widget _buildOrdersPanel(_OrderColors colors) {
    final l10n = context.appLocalizations;
    return Container(
      key: const ValueKey('orders-panel'),
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
          Wrap(
            spacing: 12,
            runSpacing: 10,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                l10n.myOrders,
                style: TextStyle(
                  color: colors.text,
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 7,
                ),
                decoration: BoxDecoration(
                  color: colors.primarySoft,
                  borderRadius: BorderRadius.circular(99),
                ),
                child: Text(
                  l10n.totalOrders(_orders.length),
                  style: TextStyle(
                    color: colors.primary,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              OutlinedButton.icon(
                key: const ValueKey('refresh-orders'),
                onPressed: _refreshing
                    ? null
                    : () => _loadOrders(refresh: true),
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
              height: 360,
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_offline)
            _OrderStatus(
              colors: colors,
              icon: Icons.wifi_off_rounded,
              label: l10n.onlineFeaturesUnavailableOffline,
            )
          else if (_failed)
            _OrderStatus(
              colors: colors,
              icon: Icons.cloud_off_outlined,
              label: l10n.orderListFailed,
              actionLabel: l10n.retry,
              onPressed: _loadOrders,
            )
          else if (_orders.isEmpty)
            _OrderStatus(
              colors: colors,
              icon: Icons.receipt_long_outlined,
              label: l10n.noOrders,
            )
          else ...[
            LayoutBuilder(
              builder: (context, constraints) => constraints.maxWidth >= 920
                  ? _buildDesktopTable(colors)
                  : _buildMobileCards(colors),
            ),
            const SizedBox(height: 18),
            _buildPagination(colors),
          ],
        ],
      ),
    );
  }

  Widget _buildDesktopTable(_OrderColors colors) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border.all(color: colors.outline),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          children: [
            _OrderTableHeader(colors: colors),
            for (var index = 0; index < _visibleOrders.length; index++)
              _OrderTableRow(
                key: ValueKey('order-row-${_visibleOrders[index].tradeNo}'),
                colors: colors,
                order: _visibleOrders[index],
                detailLoading:
                    _loadingDetailTradeNo == _visibleOrders[index].tradeNo,
                cancelling: _cancellingTradeNo == _visibleOrders[index].tradeNo,
                onDetails: () => _showOrderDetails(_visibleOrders[index]),
                onCancel: _visibleOrders[index].canCancel
                    ? () => _cancelOrder(_visibleOrders[index])
                    : null,
                isLast: index == _visibleOrders.length - 1,
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildMobileCards(_OrderColors colors) {
    return Column(
      children: [
        for (var index = 0; index < _visibleOrders.length; index++) ...[
          _MobileOrderCard(
            key: ValueKey('order-card-${_visibleOrders[index].tradeNo}'),
            colors: colors,
            order: _visibleOrders[index],
            detailLoading:
                _loadingDetailTradeNo == _visibleOrders[index].tradeNo,
            cancelling: _cancellingTradeNo == _visibleOrders[index].tradeNo,
            onDetails: () => _showOrderDetails(_visibleOrders[index]),
            onCancel: _visibleOrders[index].canCancel
                ? () => _cancelOrder(_visibleOrders[index])
                : null,
          ),
          if (index != _visibleOrders.length - 1) const SizedBox(height: 12),
        ],
      ],
    );
  }

  Widget _buildPagination(_OrderColors colors) {
    final l10n = context.appLocalizations;
    return Wrap(
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 14,
      runSpacing: 10,
      children: [
        OutlinedButton.icon(
          key: const ValueKey('orders-previous-page'),
          onPressed: _page == 0 ? null : () => setState(() => _page--),
          icon: const Icon(Icons.chevron_left_rounded),
          label: Text(l10n.previousPage),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
          decoration: BoxDecoration(
            color: colors.surfaceSoft,
            borderRadius: BorderRadius.circular(99),
            border: Border.all(color: colors.outline),
          ),
          child: Text(
            l10n.orderPageIndicator(_page + 1, _pageCount),
            key: const ValueKey('orders-page-indicator'),
            style: TextStyle(color: colors.text, fontWeight: FontWeight.w800),
          ),
        ),
        OutlinedButton.icon(
          key: const ValueKey('orders-next-page'),
          onPressed: _page >= _pageCount - 1
              ? null
              : () => setState(() => _page++),
          icon: const Icon(Icons.chevron_right_rounded),
          label: Text(l10n.nextPage),
        ),
      ],
    );
  }
}

class _OrderTableHeader extends StatelessWidget {
  final _OrderColors colors;

  const _OrderTableHeader({required this.colors});

  @override
  Widget build(BuildContext context) {
    final l10n = context.appLocalizations;
    final style = TextStyle(
      color: colors.muted,
      fontSize: 13,
      fontWeight: FontWeight.w800,
    );
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 17),
      color: colors.surfaceSoft,
      child: Row(
        children: [
          Expanded(flex: 24, child: Text(l10n.orderNumber, style: style)),
          Expanded(flex: 18, child: Text(l10n.createdAt, style: style)),
          Expanded(flex: 14, child: Text(l10n.orderPeriod, style: style)),
          Expanded(flex: 12, child: Text(l10n.orderAmount, style: style)),
          Expanded(flex: 12, child: Text(l10n.status, style: style)),
          Expanded(flex: 20, child: Text(l10n.actions, style: style)),
        ],
      ),
    );
  }
}

class _OrderTableRow extends StatelessWidget {
  final _OrderColors colors;
  final XboardOrderData order;
  final bool detailLoading;
  final bool cancelling;
  final VoidCallback onDetails;
  final VoidCallback? onCancel;
  final bool isLast;

  const _OrderTableRow({
    super.key,
    required this.colors,
    required this.order,
    required this.detailLoading,
    required this.cancelling,
    required this.onDetails,
    required this.onCancel,
    required this.isLast,
  });

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(
      color: colors.text,
      fontSize: 13,
      fontWeight: FontWeight.w600,
    );
    return Container(
      constraints: const BoxConstraints(minHeight: 82),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
      decoration: BoxDecoration(
        border: isLast
            ? null
            : Border(bottom: BorderSide(color: colors.outline)),
      ),
      child: Row(
        children: [
          Expanded(
            flex: 24,
            child: Text(
              order.tradeNo,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: style,
            ),
          ),
          Expanded(
            flex: 18,
            child: Text(_formatOrderTime(order.createdAt), style: style),
          ),
          Expanded(
            flex: 14,
            child: Text(xboardPeriodLabel(context, order.period), style: style),
          ),
          Expanded(
            flex: 12,
            child: Text(
              _formatOrderMoney(order.totalAmount),
              style: style.copyWith(
                color: colors.amount,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          Expanded(
            flex: 12,
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: _OrderStatusBadge(order: order),
            ),
          ),
          Expanded(
            flex: 20,
            child: Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                FilledButton.tonalIcon(
                  key: ValueKey('order-detail-${order.tradeNo}'),
                  onPressed: detailLoading ? null : onDetails,
                  icon: detailLoading
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.visibility_outlined, size: 18),
                  label: Text(context.appLocalizations.viewOrderDetails),
                ),
                TextButton.icon(
                  key: ValueKey('order-cancel-${order.tradeNo}'),
                  onPressed: cancelling ? null : onCancel,
                  icon: cancelling
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.close_rounded, size: 18),
                  label: Text(context.appLocalizations.cancelOrder),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MobileOrderCard extends StatelessWidget {
  final _OrderColors colors;
  final XboardOrderData order;
  final bool detailLoading;
  final bool cancelling;
  final VoidCallback onDetails;
  final VoidCallback? onCancel;

  const _MobileOrderCard({
    super.key,
    required this.colors,
    required this.order,
    required this.detailLoading,
    required this.cancelling,
    required this.onDetails,
    required this.onCancel,
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
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      order.planName ??
                          xboardPeriodLabel(context, order.period),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: colors.text,
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      order.tradeNo,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: colors.muted, fontSize: 12),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              _OrderStatusBadge(order: order),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _OrderMetric(
                  colors: colors,
                  label: l10n.createdAt,
                  value: _formatOrderTime(order.createdAt),
                ),
              ),
              Expanded(
                child: _OrderMetric(
                  colors: colors,
                  label: l10n.orderPeriod,
                  value: xboardPeriodLabel(context, order.period),
                ),
              ),
              Expanded(
                child: _OrderMetric(
                  colors: colors,
                  label: l10n.orderAmount,
                  value: _formatOrderMoney(order.totalAmount),
                  valueColor: colors.amount,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: FilledButton.tonalIcon(
                  key: ValueKey('order-detail-${order.tradeNo}'),
                  onPressed: detailLoading ? null : onDetails,
                  icon: detailLoading
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.visibility_outlined),
                  label: Text(l10n.viewOrderDetails),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  key: ValueKey('order-cancel-${order.tradeNo}'),
                  onPressed: cancelling ? null : onCancel,
                  icon: cancelling
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.close_rounded),
                  label: Text(l10n.cancelOrder),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _OrderMetric extends StatelessWidget {
  final _OrderColors colors;
  final String label;
  final String value;
  final Color? valueColor;

  const _OrderMetric({
    required this.colors,
    required this.label,
    required this.value,
    this.valueColor,
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
        const SizedBox(height: 5),
        Text(
          value,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: valueColor ?? colors.text,
            fontSize: 12,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }
}

class _OrderStatusBadge extends StatelessWidget {
  final XboardOrderData order;

  const _OrderStatusBadge({required this.order});

  @override
  Widget build(BuildContext context) {
    final color = _orderStatusColor(context, order.status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        _orderStatusLabel(context, order.status),
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _OrderDetailsDialog extends StatelessWidget {
  final XboardOrderData order;

  const _OrderDetailsDialog({required this.order});

  @override
  Widget build(BuildContext context) {
    final l10n = context.appLocalizations;
    final fields = <(String, String)>[
      (l10n.orderNumber, order.tradeNo),
      if (order.planName != null) (l10n.orderPlan, order.planName!),
      (l10n.orderPeriod, xboardPeriodLabel(context, order.period)),
      (l10n.orderAmount, _formatOrderMoney(order.totalAmount)),
      (l10n.status, _orderStatusLabel(context, order.status)),
      (l10n.createdAt, _formatOrderTime(order.createdAt)),
      if (order.paymentName != null) (l10n.paymentMethod, order.paymentName!),
      if (order.paidAt != null) (l10n.paidAt, _formatOrderTime(order.paidAt!)),
    ];
    return AlertDialog(
      icon: const Icon(Icons.receipt_long_rounded),
      title: Text(l10n.orderDetailsTitle),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var index = 0; index < fields.length; index++)
              Container(
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  border: index == fields.length - 1
                      ? null
                      : Border(
                          bottom: BorderSide(
                            color: context.colorScheme.outlineVariant,
                          ),
                        ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 110,
                      child: Text(
                        fields[index].$1,
                        style: TextStyle(
                          color: context.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        fields[index].$2,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.done),
        ),
      ],
    );
  }
}

class _OrderStatus extends StatelessWidget {
  final _OrderColors colors;
  final IconData icon;
  final String label;
  final String? actionLabel;
  final VoidCallback? onPressed;

  const _OrderStatus({
    required this.colors,
    required this.icon,
    required this.label,
    this.actionLabel,
    this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 360,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: colors.muted, size: 54),
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

class _OrderColors {
  final Color background;
  final Color surface;
  final Color surfaceSoft;
  final Color primary;
  final Color primarySoft;
  final Color accentSoft;
  final Color text;
  final Color muted;
  final Color outline;
  final Color shadow;
  final Color amount;

  const _OrderColors({
    required this.background,
    required this.surface,
    required this.surfaceSoft,
    required this.primary,
    required this.primarySoft,
    required this.accentSoft,
    required this.text,
    required this.muted,
    required this.outline,
    required this.shadow,
    required this.amount,
  });

  factory _OrderColors.of(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dark = scheme.brightness == Brightness.dark;
    return _OrderColors(
      background: Color.alphaBlend(
        scheme.primary.withValues(alpha: dark ? 0.055 : 0.035),
        scheme.surface,
      ),
      surface: scheme.surfaceContainerLowest,
      surfaceSoft: scheme.surfaceContainerLow,
      primary: scheme.primary,
      primarySoft: scheme.primary.withValues(alpha: dark ? 0.2 : 0.1),
      accentSoft: scheme.tertiary.withValues(alpha: dark ? 0.12 : 0.06),
      text: scheme.onSurface,
      muted: scheme.onSurfaceVariant,
      outline: scheme.outlineVariant.withValues(alpha: 0.82),
      shadow: Colors.black.withValues(alpha: dark ? 0.3 : 0.075),
      amount: dark ? const Color(0xFFFF8E86) : const Color(0xFFF04438),
    );
  }
}

String _formatOrderMoney(int cents) {
  return NumberFormat.currency(
    locale: 'zh_CN',
    symbol: '¥',
    decimalDigits: 2,
  ).format(cents / 100);
}

String _formatOrderTime(DateTime value) {
  return DateFormat('yyyy/MM/dd HH:mm').format(value);
}

String _orderStatusLabel(BuildContext context, int status) {
  final l10n = context.appLocalizations;
  return switch (status) {
    0 => l10n.orderStatusPending,
    1 => l10n.orderStatusProcessing,
    2 => l10n.orderStatusCancelled,
    3 => l10n.orderStatusCompleted,
    _ => l10n.orderStatusUnknown,
  };
}

Color _orderStatusColor(BuildContext context, int status) {
  final scheme = Theme.of(context).colorScheme;
  final dark = scheme.brightness == Brightness.dark;
  return switch (status) {
    0 => dark ? const Color(0xFFFFC260) : const Color(0xFFE58B00),
    1 => scheme.primary,
    2 => scheme.error,
    3 => dark ? const Color(0xFF5CDB9B) : const Color(0xFF24A862),
    _ => scheme.onSurfaceVariant,
  };
}

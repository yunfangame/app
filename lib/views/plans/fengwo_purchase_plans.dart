import 'dart:async';

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/state.dart';
import 'package:fl_clash/widgets/offline_mode_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_html/flutter_html.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

enum _PlanType { all, recurring, oneTime }

const xboardRecurringPeriodKeys = [
  'month_price',
  'quarter_price',
  'half_year_price',
  'year_price',
  'two_year_price',
  'three_year_price',
];

const _periodOrder = [
  ...xboardRecurringPeriodKeys,
  'onetime_price',
  'reset_price',
];

Future<bool?> showXboardPaymentDialog({
  required BuildContext context,
  required XboardAuthService authService,
  required XboardLoginResult session,
  required XboardAvailablePlan plan,
  required String period,
}) {
  return showDialog<bool>(
    context: context,
    builder: (context) => _XboardPaymentDialog(
      authService: authService,
      session: session,
      plan: plan,
      period: period,
    ),
  );
}

class FengWoPurchasePlansView extends StatefulWidget {
  final XboardAuthService? authService;

  const FengWoPurchasePlansView({super.key, this.authService});

  @override
  State<FengWoPurchasePlansView> createState() =>
      _FengWoPurchasePlansViewState();
}

class _FengWoPurchasePlansViewState extends State<FengWoPurchasePlansView> {
  late final XboardAuthService _authService;
  List<XboardAvailablePlan> _plans = const [];
  _PlanType _planType = _PlanType.all;
  bool _loading = true;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _authService = widget.authService ?? XboardAuthService();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadPlans());
  }

  Future<void> _loadPlans() async {
    if (globalState.isOfflineMode) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    final session = globalState.xboardSession;
    if (session == null) {
      if (mounted) {
        setState(() {
          _loading = false;
          _failed = true;
        });
      }
      return;
    }
    setState(() {
      _loading = true;
      _failed = false;
    });
    try {
      final plans = await _authService.fetchPlans(
        endpoint: session.endpoint,
        authData: session.authData,
      );
      if (!mounted) return;
      setState(() => _plans = plans);
    } catch (error, stackTrace) {
      commonPrint.log(
        'load XBoard plans failed: $error, $stackTrace',
        logLevel: LogLevel.warning,
      );
      if (mounted) setState(() => _failed = true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  bool _matchesType(XboardAvailablePlan plan) {
    final hasRecurring = xboardRecurringPeriodKeys.any(plan.prices.containsKey);
    final hasOneTime = plan.prices.containsKey('onetime_price');
    return switch (_planType) {
      _PlanType.all => true,
      _PlanType.recurring => hasRecurring,
      _PlanType.oneTime => hasOneTime,
    };
  }

  Future<void> _showPayment(XboardAvailablePlan plan, String period) async {
    final session = globalState.xboardSession;
    if (session == null) return;
    final paid = await showXboardPaymentDialog(
      context: context,
      authService: _authService,
      session: session,
      plan: plan,
      period: period,
    );
    if (paid == true) await _loadPlans();
  }

  @override
  Widget build(BuildContext context) {
    if (globalState.isOfflineMode) {
      return const OfflineModeFeaturePanel();
    }
    final colors = _PlanColors.of(context);
    final visiblePlans = _plans
        .where((plan) => plan.prices.isNotEmpty)
        .where(_matchesType)
        .toList(growable: false);
    final currentPlanId = globalState.xboardSubscription?.planId;
    return Material(
      color: colors.background,
      child: RefreshIndicator(
        onRefresh: _loadPlans,
        child: CustomScrollView(
          key: const ValueKey('fengwo-plan-store-scroll'),
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverToBoxAdapter(
              child: _PlanStoreHeader(
                colors: colors,
                selectedType: _planType,
                onTypeChanged: (value) => setState(() => _planType = value),
                onRefresh: _loadPlans,
              ),
            ),
            if (_loading)
              const SliverFillRemaining(
                hasScrollBody: false,
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_failed)
              SliverFillRemaining(
                hasScrollBody: false,
                child: _PlanStoreStatus(
                  icon: Icons.cloud_off_rounded,
                  label: context.appLocalizations.planCatalogFailed,
                  onRetry: _loadPlans,
                ),
              )
            else if (visiblePlans.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: _PlanStoreStatus(
                  icon: Icons.inventory_2_outlined,
                  label: context.appLocalizations.planCatalogEmpty,
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(28, 24, 28, 34),
                sliver: SliverLayoutBuilder(
                  builder: (context, constraints) {
                    final width = constraints.crossAxisExtent;
                    final columns = width >= 1180
                        ? 3
                        : width >= 720
                        ? 2
                        : 1;
                    return SliverGrid(
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: columns,
                        mainAxisSpacing: 20,
                        crossAxisSpacing: 20,
                        mainAxisExtent: columns == 1 ? 590 : 620,
                      ),
                      delegate: SliverChildBuilderDelegate((context, index) {
                        final plan = visiblePlans[index];
                        return _PlanCard(
                          key: ValueKey('fengwo-plan-${plan.id}'),
                          colors: colors,
                          plan: plan,
                          isCurrent: plan.id == currentPlanId,
                          onPurchase: (period) => _showPayment(plan, period),
                        );
                      }, childCount: visiblePlans.length),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _PlanColors {
  final Color background;
  final Color surface;
  final Color surfaceSoft;
  final Color primary;
  final Color primarySoft;
  final Color text;
  final Color muted;
  final Color outline;
  final Color success;
  final Color shadow;

  const _PlanColors({
    required this.background,
    required this.surface,
    required this.surfaceSoft,
    required this.primary,
    required this.primarySoft,
    required this.text,
    required this.muted,
    required this.outline,
    required this.success,
    required this.shadow,
  });

  factory _PlanColors.of(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dark = scheme.brightness == Brightness.dark;
    return _PlanColors(
      background: Color.alphaBlend(
        scheme.primary.withValues(alpha: dark ? 0.05 : 0.035),
        scheme.surface,
      ),
      surface: scheme.surfaceContainerLowest,
      surfaceSoft: scheme.surfaceContainerLow,
      primary: scheme.primary,
      primarySoft: scheme.primary.withValues(alpha: dark ? 0.22 : 0.11),
      text: scheme.onSurface,
      muted: scheme.onSurfaceVariant,
      outline: scheme.outlineVariant.withValues(alpha: 0.78),
      success: dark ? const Color(0xFF4BE29B) : const Color(0xFF16B96B),
      shadow: Colors.black.withValues(alpha: dark ? 0.3 : 0.08),
    );
  }
}

class _PlanStoreHeader extends StatelessWidget {
  final _PlanColors colors;
  final _PlanType selectedType;
  final ValueChanged<_PlanType> onTypeChanged;
  final VoidCallback onRefresh;

  const _PlanStoreHeader({
    required this.colors,
    required this.selectedType,
    required this.onTypeChanged,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = context.appLocalizations;
    return Container(
      padding: const EdgeInsets.fromLTRB(30, 26, 24, 22),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            colors.primarySoft,
            colors.background,
            colors.surfaceSoft.withValues(alpha: 0.45),
          ],
        ),
        border: Border(bottom: BorderSide(color: colors.outline)),
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
                      l10n.purchasePlan,
                      style: TextStyle(
                        color: colors.text,
                        fontSize: 34,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Icon(
                          Icons.verified_user_outlined,
                          color: colors.primary,
                          size: 21,
                        ),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            l10n.planStoreSubtitle,
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
              ),
              IconButton(
                onPressed: onRefresh,
                tooltip: l10n.refreshNodes,
                icon: const Icon(Icons.refresh_rounded, size: 28),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Center(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SegmentedButton<_PlanType>(
                key: const ValueKey('fengwo-plan-type-filter'),
                showSelectedIcon: false,
                segments: [
                  ButtonSegment(
                    value: _PlanType.all,
                    icon: const Icon(Icons.all_inclusive_rounded),
                    label: Text(l10n.allPlans),
                  ),
                  ButtonSegment(
                    value: _PlanType.recurring,
                    icon: const Icon(Icons.sync_alt_rounded),
                    label: Text(l10n.recurringPlans),
                  ),
                  ButtonSegment(
                    value: _PlanType.oneTime,
                    icon: const Icon(Icons.event_available_outlined),
                    label: Text(l10n.oneTimePlans),
                  ),
                ],
                selected: {selectedType},
                onSelectionChanged: (selection) {
                  if (selection.isNotEmpty) onTypeChanged(selection.first);
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PlanStoreStatus extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onRetry;

  const _PlanStoreStatus({
    required this.icon,
    required this.label,
    this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 48, color: Theme.of(context).colorScheme.outline),
          const SizedBox(height: 12),
          Text(label),
          if (onRetry != null) ...[
            const SizedBox(height: 12),
            FilledButton.tonal(
              onPressed: onRetry,
              child: Text(context.appLocalizations.refreshNodes),
            ),
          ],
        ],
      ),
    );
  }
}

class _PlanCard extends StatefulWidget {
  final _PlanColors colors;
  final XboardAvailablePlan plan;
  final bool isCurrent;
  final ValueChanged<String> onPurchase;

  const _PlanCard({
    super.key,
    required this.colors,
    required this.plan,
    required this.isCurrent,
    required this.onPurchase,
  });

  @override
  State<_PlanCard> createState() => _PlanCardState();
}

class _PlanCardState extends State<_PlanCard> {
  late String _period;

  @override
  void initState() {
    super.initState();
    _period = _availablePeriods.first;
  }

  @override
  void didUpdateWidget(covariant _PlanCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_availablePeriods.contains(_period)) _period = _availablePeriods.first;
  }

  List<String> get _availablePeriods => _periodOrder
      .where(widget.plan.prices.containsKey)
      .toList(growable: false);

  bool get _isOneTime => _period == 'onetime_price';

  @override
  Widget build(BuildContext context) {
    final l10n = context.appLocalizations;
    final colors = widget.colors;
    final plan = widget.plan;
    final price = plan.prices[_period] ?? 0;
    final disabled = !plan.sell || plan.isSoldOut;
    final cardAccent = _isOneTime ? const Color(0xFFFF7B9C) : colors.primary;
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: colors.surface.withValues(alpha: 0.96),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(
          color: widget.isCurrent ? colors.primary : colors.outline,
          width: widget.isCurrent ? 2 : 1,
        ),
        boxShadow: [BoxShadow(color: colors.shadow, blurRadius: 24)],
      ),
      child: Column(
        children: [
          Container(
            height: 12,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [cardAccent, cardAccent.withValues(alpha: 0.3)],
              ),
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        _isOneTime
                            ? Icons.event_available_rounded
                            : Icons.calendar_month_rounded,
                        color: cardAccent,
                        size: 34,
                      ),
                      if (widget.isCurrent) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 9,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: colors.primarySoft,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            l10n.currentPlanLabel,
                            style: TextStyle(
                              color: colors.primary,
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    plan.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: colors.text,
                      fontSize: 23,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 10),
                  _BillingPeriods(
                    colors: colors,
                    periods: _availablePeriods,
                    selected: _period,
                    onSelected: (value) => setState(() => _period = value),
                  ),
                  const SizedBox(height: 14),
                  _PlanPrice(colors: colors, price: price, period: _period),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: _PlanMetric(
                          colors: colors,
                          icon: Icons.water_drop_outlined,
                          color: colors.primary,
                          value: _formatGb(plan.transferEnableGb),
                          label: l10n.planTrafficLabel,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _PlanMetric(
                          colors: colors,
                          icon: Icons.speed_rounded,
                          color: colors.primary,
                          value: plan.speedLimit == null
                              ? l10n.noLimit
                              : '${plan.speedLimit} Mbps',
                          label: l10n.planSpeedLabel,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _PlanMetric(
                          colors: colors,
                          icon: Icons.phone_android_rounded,
                          color: colors.success,
                          value: plan.deviceLimit == null
                              ? l10n.noLimit
                              : '${plan.deviceLimit}',
                          label: l10n.planDevicesLabel,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      decoration: BoxDecoration(
                        color: colors.surfaceSoft.withValues(alpha: 0.35),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: SingleChildScrollView(
                        child: Html(
                          data: plan.content,
                          style: {
                            'body': Style(
                              margin: Margins.zero,
                              padding: HtmlPaddings.symmetric(
                                horizontal: 8,
                                vertical: 6,
                              ),
                              color: colors.muted,
                              fontSize: FontSize(12),
                            ),
                            'p': Style(margin: Margins.only(bottom: 6)),
                            'li': Style(margin: Margins.only(bottom: 4)),
                          },
                          onLinkTap: (url, _, _) async {
                            final target = Uri.tryParse(url ?? '');
                            if (target != null &&
                                {'http', 'https'}.contains(target.scheme)) {
                              await launchUrl(
                                target,
                                mode: LaunchMode.externalApplication,
                              );
                            }
                          },
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    height: 46,
                    child: FilledButton(
                      onPressed: disabled
                          ? null
                          : () => widget.onPurchase(_period),
                      style: FilledButton.styleFrom(
                        backgroundColor: cardAccent,
                        foregroundColor: Colors.white,
                      ),
                      child: Text(
                        plan.isSoldOut ? l10n.soldOut : l10n.buyNow,
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BillingPeriods extends StatelessWidget {
  final _PlanColors colors;
  final List<String> periods;
  final String selected;
  final ValueChanged<String> onSelected;

  const _BillingPeriods({
    required this.colors,
    required this.periods,
    required this.selected,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (final period in periods) ...[
            ChoiceChip(
              label: Text(xboardPeriodLabel(context, period)),
              selected: period == selected,
              showCheckmark: false,
              visualDensity: VisualDensity.compact,
              labelStyle: TextStyle(
                color: period == selected ? colors.primary : colors.muted,
                fontWeight: FontWeight.w700,
              ),
              onSelected: (_) => onSelected(period),
            ),
            if (period != periods.last) const SizedBox(width: 6),
          ],
        ],
      ),
    );
  }
}

class _PlanPrice extends StatelessWidget {
  final _PlanColors colors;
  final int price;
  final String period;

  const _PlanPrice({
    required this.colors,
    required this.price,
    required this.period,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = context.appLocalizations;
    if (price == 0) {
      return Text(
        l10n.freeLabel,
        style: TextStyle(
          color: colors.primary,
          fontSize: 36,
          fontWeight: FontWeight.w900,
        ),
      );
    }
    final amount = price / 100;
    final amountText = amount == amount.roundToDouble()
        ? amount.toStringAsFixed(0)
        : amount.toStringAsFixed(2);
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Text(
            '¥',
            style: TextStyle(
              color: colors.primary,
              fontSize: 18,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
        const SizedBox(width: 4),
        Text(
          amountText,
          style: TextStyle(
            color: colors.primary,
            fontSize: 42,
            height: 1,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(width: 6),
        Padding(
          padding: const EdgeInsets.only(bottom: 5),
          child: Text(
            '/ ${xboardPeriodLabel(context, period)}',
            style: TextStyle(
              color: colors.muted,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }
}

class _PlanMetric extends StatelessWidget {
  final _PlanColors colors;
  final IconData icon;
  final Color color;
  final String value;
  final String label;

  const _PlanMetric({
    required this.colors,
    required this.icon,
    required this.color,
    required this.value,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 92,
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
      decoration: BoxDecoration(
        color: colors.surfaceSoft.withValues(alpha: 0.62),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.outline),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(height: 4),
          Expanded(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                value,
                maxLines: 1,
                style: TextStyle(
                  color: colors.text,
                  fontSize: 15,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ),
          Text(label, style: TextStyle(color: colors.muted, fontSize: 10)),
        ],
      ),
    );
  }
}

enum _PaymentStage { loading, ready, submitting, waiting, success, failure }

class _XboardPaymentDialog extends StatefulWidget {
  final XboardAuthService authService;
  final XboardLoginResult session;
  final XboardAvailablePlan plan;
  final String period;

  const _XboardPaymentDialog({
    required this.authService,
    required this.session,
    required this.plan,
    required this.period,
  });

  @override
  State<_XboardPaymentDialog> createState() => _XboardPaymentDialogState();
}

class _XboardPaymentDialogState extends State<_XboardPaymentDialog> {
  _PaymentStage _stage = _PaymentStage.loading;
  List<XboardPaymentMethod> _methods = const [];
  int? _selectedMethodId;
  String? _tradeNo;
  String? _paymentPayload;
  String? _error;
  Timer? _statusTimer;
  bool _checking = false;
  bool _subscriptionRefreshStarted = false;

  int get _price => widget.plan.prices[widget.period] ?? 0;

  bool get _isFree => _price == 0;

  XboardPaymentMethod? get _selectedMethod {
    for (final method in _methods) {
      if (method.id == _selectedMethodId) return method;
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    _loadPaymentMethods();
  }

  @override
  void dispose() {
    _statusTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadPaymentMethods() async {
    if (mounted) {
      setState(() {
        _stage = _PaymentStage.loading;
        _error = null;
      });
    }
    try {
      final methods = await widget.authService.fetchPaymentMethods(
        endpoint: widget.session.endpoint,
        authData: widget.session.authData,
      );
      if (!mounted) return;
      setState(() {
        _methods = methods;
        _selectedMethodId = methods.isEmpty ? null : methods.first.id;
        if (methods.isEmpty && !_isFree) {
          _stage = _PaymentStage.failure;
          _error = context.appLocalizations.noPaymentMethods;
        } else {
          _stage = _PaymentStage.ready;
        }
      });
    } catch (error) {
      _showFailure(_messageFor(error));
    }
  }

  Future<void> _createAndCheckout() async {
    if (!_isFree && _selectedMethod == null) return;
    setState(() {
      _stage = _PaymentStage.submitting;
      _error = null;
    });
    try {
      final tradeNo =
          _tradeNo ??
          await widget.authService.createOrder(
            endpoint: widget.session.endpoint,
            authData: widget.session.authData,
            planId: widget.plan.id,
            period: widget.period,
          );
      _tradeNo = tradeNo;
      final checkout = await widget.authService.checkoutOrder(
        endpoint: widget.session.endpoint,
        authData: widget.session.authData,
        tradeNo: tradeNo,
        methodId: _selectedMethodId ?? 0,
      );
      if (!mounted) return;
      if (checkout.isFree) {
        _showSuccess();
        return;
      }
      setState(() {
        _paymentPayload = checkout.paymentPayload;
        _stage = _PaymentStage.waiting;
      });
      _statusTimer?.cancel();
      _statusTimer = Timer.periodic(
        const Duration(seconds: 3),
        (_) => _checkOrderStatus(),
      );
    } catch (error) {
      _showFailure(_messageFor(error));
    }
  }

  Future<void> _checkOrderStatus() async {
    final tradeNo = _tradeNo;
    if (tradeNo == null || _checking || !mounted) return;
    _checking = true;
    try {
      final status = await widget.authService.checkOrder(
        endpoint: widget.session.endpoint,
        authData: widget.session.authData,
        tradeNo: tradeNo,
      );
      if (!mounted) return;
      if (status == 1 || status == 3) {
        _showSuccess();
      } else if (status == 2) {
        _showFailure(context.appLocalizations.orderCancelled);
      }
    } catch (error, stackTrace) {
      commonPrint.log(
        'check XBoard payment status failed: $error, $stackTrace',
        logLevel: LogLevel.warning,
      );
    } finally {
      _checking = false;
    }
  }

  void _showSuccess() {
    _statusTimer?.cancel();
    if (!mounted) return;
    setState(() {
      _stage = _PaymentStage.success;
      _error = null;
    });
    if (!_subscriptionRefreshStarted) {
      _subscriptionRefreshStarted = true;
      unawaited(_refreshSubscription());
    }
  }

  Future<void> _refreshSubscription() async {
    final refreshed = await globalState.refreshXboardSubscription?.call();
    if (refreshed != true) {
      commonPrint.log(
        'XBoard payment succeeded but subscription refresh is pending',
        logLevel: LogLevel.warning,
      );
    }
  }

  void _showFailure(String message) {
    _statusTimer?.cancel();
    if (!mounted) return;
    setState(() {
      _stage = _PaymentStage.failure;
      _error = message;
    });
  }

  String _messageFor(Object error) {
    if (error is XboardAuthException && error.message.trim().isNotEmpty) {
      return error.message;
    }
    return context.appLocalizations.paymentFailed;
  }

  @override
  Widget build(BuildContext context) {
    final colors = _PlanColors.of(context);
    final l10n = context.appLocalizations;
    return Dialog(
      insetPadding: const EdgeInsets.all(20),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520, maxHeight: 700),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 18, 14, 14),
              child: Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: colors.primarySoft,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(Icons.qr_code_2_rounded, color: colors.primary),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          l10n.inAppPayment,
                          style: TextStyle(
                            color: colors.text,
                            fontSize: 20,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        Text(
                          l10n.paymentStaysInApp,
                          style: TextStyle(color: colors.muted, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    tooltip: MaterialLocalizations.of(
                      context,
                    ).closeButtonTooltip,
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
            ),
            Divider(height: 1, color: colors.outline),
            Flexible(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 220),
                child: switch (_stage) {
                  _PaymentStage.loading => _paymentLoading(colors),
                  _PaymentStage.ready => _paymentReady(colors),
                  _PaymentStage.submitting => _paymentSubmitting(colors),
                  _PaymentStage.waiting => _paymentQr(colors),
                  _PaymentStage.success => _paymentSuccess(colors),
                  _PaymentStage.failure => _paymentFailure(colors),
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _paymentLoading(_PlanColors colors) {
    return _PaymentCenteredStatus(
      key: const ValueKey('payment-loading'),
      icon: const CircularProgressIndicator(),
      title: context.appLocalizations.loadingPaymentMethods,
      colors: colors,
    );
  }

  Widget _paymentReady(_PlanColors colors) {
    final l10n = context.appLocalizations;
    return SingleChildScrollView(
      key: const ValueKey('payment-ready'),
      padding: const EdgeInsets.all(22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _PaymentOrderSummary(
            colors: colors,
            planName: widget.plan.name,
            period: xboardPeriodLabel(context, widget.period),
            price: _price,
          ),
          const SizedBox(height: 20),
          Text(
            l10n.selectPaymentMethod,
            style: TextStyle(
              color: colors.text,
              fontSize: 15,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 10),
          if (_isFree && _methods.isEmpty)
            _PaymentMethodTile(
              colors: colors,
              icon: Icons.redeem_rounded,
              name: l10n.freeOrder,
              subtitle: l10n.noPaymentRequired,
              selected: true,
            )
          else
            for (final method in _methods) ...[
              _PaymentMethodTile(
                key: ValueKey('payment-method-${method.id}'),
                colors: colors,
                icon: _paymentIcon(method),
                name: method.name,
                subtitle: _paymentFeeText(method),
                selected: method.id == _selectedMethodId,
                onTap: () => setState(() => _selectedMethodId = method.id),
              ),
              if (method != _methods.last) const SizedBox(height: 8),
            ],
          const SizedBox(height: 22),
          FilledButton.icon(
            key: const ValueKey('create-payment-qr'),
            onPressed: _isFree || _selectedMethod != null
                ? _createAndCheckout
                : null,
            icon: Icon(_isFree ? Icons.check_rounded : Icons.qr_code_rounded),
            label: Text(_isFree ? l10n.activateNow : l10n.generatePaymentQr),
          ),
          const SizedBox(height: 8),
          Text(
            l10n.paymentSecurityHint,
            textAlign: TextAlign.center,
            style: TextStyle(color: colors.muted, fontSize: 11),
          ),
        ],
      ),
    );
  }

  Widget _paymentSubmitting(_PlanColors colors) {
    return _PaymentCenteredStatus(
      key: const ValueKey('payment-submitting'),
      icon: const CircularProgressIndicator(),
      title: context.appLocalizations.creatingOrder,
      subtitle: context.appLocalizations.pleaseWait,
      colors: colors,
    );
  }

  Widget _paymentQr(_PlanColors colors) {
    final l10n = context.appLocalizations;
    final payload = _paymentPayload ?? '';
    return SingleChildScrollView(
      key: const ValueKey('payment-qr'),
      padding: const EdgeInsets.fromLTRB(24, 18, 24, 24),
      child: Column(
        children: [
          Text(
            l10n.scanToPay,
            style: TextStyle(
              color: colors.text,
              fontSize: 20,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            l10n.scanWithPaymentApp,
            textAlign: TextAlign.center,
            style: TextStyle(color: colors.muted),
          ),
          const SizedBox(height: 18),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(22),
              boxShadow: [BoxShadow(color: colors.shadow, blurRadius: 20)],
            ),
            child: QrImageView(
              key: const ValueKey('payment-qr-code'),
              data: payload,
              version: QrVersions.auto,
              size: 230,
              backgroundColor: Colors.white,
              eyeStyle: const QrEyeStyle(
                eyeShape: QrEyeShape.square,
                color: Colors.black,
              ),
              dataModuleStyle: const QrDataModuleStyle(
                dataModuleShape: QrDataModuleShape.square,
                color: Colors.black,
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            '${l10n.orderNumber}: ${_tradeNo ?? ''}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: colors.muted, fontSize: 11),
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: colors.primarySoft,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: colors.primary,
                  ),
                ),
                const SizedBox(width: 9),
                Text(
                  l10n.waitingForPayment,
                  style: TextStyle(
                    color: colors.primary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          OutlinedButton.icon(
            onPressed: _checking ? null : _checkOrderStatus,
            icon: const Icon(Icons.refresh_rounded),
            label: Text(l10n.iHavePaid),
          ),
        ],
      ),
    );
  }

  Widget _paymentSuccess(_PlanColors colors) {
    return _PaymentCenteredStatus(
      key: const ValueKey('payment-success'),
      icon: Icon(Icons.check_circle_rounded, color: colors.success, size: 68),
      title: context.appLocalizations.paymentSuccessful,
      subtitle: context.appLocalizations.paymentSuccessfulHint,
      colors: colors,
      action: FilledButton(
        onPressed: () => Navigator.of(context).pop(true),
        child: Text(context.appLocalizations.done),
      ),
    );
  }

  Widget _paymentFailure(_PlanColors colors) {
    final hasOrder = _tradeNo != null;
    return _PaymentCenteredStatus(
      key: const ValueKey('payment-failure'),
      icon: Icon(
        Icons.error_outline_rounded,
        color: Theme.of(context).colorScheme.error,
        size: 62,
      ),
      title: context.appLocalizations.paymentFailed,
      subtitle: _error,
      colors: colors,
      action: FilledButton.tonalIcon(
        onPressed: hasOrder ? _createAndCheckout : _loadPaymentMethods,
        icon: const Icon(Icons.refresh_rounded),
        label: Text(context.appLocalizations.retry),
      ),
    );
  }

  String _paymentFeeText(XboardPaymentMethod method) {
    final parts = <String>[];
    if (method.handlingFeePercent > 0) {
      parts.add('${method.handlingFeePercent.toStringAsFixed(2)}%');
    }
    if (method.handlingFeeFixed > 0) {
      parts.add(_formatMoney(method.handlingFeeFixed));
    }
    if (parts.isEmpty) return context.appLocalizations.noHandlingFee;
    return '${context.appLocalizations.handlingFee}: ${parts.join(' + ')}';
  }
}

class _PaymentOrderSummary extends StatelessWidget {
  final _PlanColors colors;
  final String planName;
  final String period;
  final int price;

  const _PaymentOrderSummary({
    required this.colors,
    required this.planName,
    required this.period,
    required this.price,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.primarySoft,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: colors.primary.withValues(alpha: 0.18)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  planName,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: colors.text,
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                Text(period, style: TextStyle(color: colors.muted)),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Text(
            price == 0
                ? context.appLocalizations.freeLabel
                : _formatMoney(price),
            style: TextStyle(
              color: colors.primary,
              fontSize: 23,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class _PaymentMethodTile extends StatelessWidget {
  final _PlanColors colors;
  final IconData icon;
  final String name;
  final String subtitle;
  final bool selected;
  final VoidCallback? onTap;

  const _PaymentMethodTile({
    super.key,
    required this.colors,
    required this.icon,
    required this.name,
    required this.subtitle,
    required this.selected,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? colors.primarySoft : colors.surfaceSoft,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: selected ? colors.primary : colors.outline,
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: colors.surface,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: colors.primary),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: TextStyle(
                        color: colors.text,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      subtitle,
                      style: TextStyle(color: colors.muted, fontSize: 11),
                    ),
                  ],
                ),
              ),
              Icon(
                selected
                    ? Icons.radio_button_checked_rounded
                    : Icons.radio_button_off_rounded,
                color: selected ? colors.primary : colors.muted,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PaymentCenteredStatus extends StatelessWidget {
  final Widget icon;
  final String title;
  final String? subtitle;
  final _PlanColors colors;
  final Widget? action;

  const _PaymentCenteredStatus({
    super.key,
    required this.icon,
    required this.title,
    required this.colors,
    this.subtitle,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(32),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 300),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            icon,
            const SizedBox(height: 20),
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: colors.text,
                fontSize: 20,
                fontWeight: FontWeight.w900,
              ),
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 8),
              Text(
                subtitle!,
                textAlign: TextAlign.center,
                style: TextStyle(color: colors.muted),
              ),
            ],
            if (action != null) ...[const SizedBox(height: 22), action!],
          ],
        ),
      ),
    );
  }
}

IconData _paymentIcon(XboardPaymentMethod method) {
  final value = '${method.name} ${method.payment}'.toLowerCase();
  if (value.contains('alipay') || value.contains('支付宝')) {
    return Icons.account_balance_wallet_rounded;
  }
  if (value.contains('wechat') || value.contains('微信')) {
    return Icons.chat_bubble_rounded;
  }
  if (value.contains('usdt') ||
      value.contains('crypto') ||
      value.contains('coin')) {
    return Icons.currency_bitcoin_rounded;
  }
  if (value.contains('stripe') ||
      value.contains('card') ||
      value.contains('信用卡')) {
    return Icons.credit_card_rounded;
  }
  return Icons.payments_rounded;
}

String _formatMoney(int cents) {
  final value = cents / 100;
  final text = value == value.roundToDouble()
      ? value.toStringAsFixed(0)
      : value.toStringAsFixed(2);
  return '¥$text';
}

String xboardPeriodLabel(BuildContext context, String period) {
  final l10n = context.appLocalizations;
  return switch (period) {
    'month_price' => l10n.monthlyBilling,
    'quarter_price' => l10n.quarterlyBilling,
    'half_year_price' => l10n.halfYearBilling,
    'year_price' => l10n.yearlyBilling,
    'two_year_price' => l10n.twoYearBilling,
    'three_year_price' => l10n.threeYearBilling,
    'onetime_price' => l10n.oneTimeBilling,
    'reset_price' => l10n.trafficResetBilling,
    _ => period,
  };
}

String _formatGb(double value) {
  final text = value == value.roundToDouble()
      ? value.toStringAsFixed(0)
      : value.toStringAsFixed(1);
  return '$text GB';
}

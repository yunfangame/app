import 'dart:math' as math;

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/state.dart';
import 'package:fl_clash/views/plans/fengwo_purchase_plans.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

const subscriptionLowTrafficThresholdBytes = 10 * bytesPerGigabyte;
const subscriptionExpiryWarningWindow = Duration(days: 3);

@immutable
class SubscriptionStatusEvaluation {
  const SubscriptionStatusEvaluation({
    required this.lowTraffic,
    required this.expiringSoon,
    required this.expired,
  });

  final bool lowTraffic;
  final bool expiringSoon;
  final bool expired;

  bool get hasWarning => lowTraffic || expiringSoon || expired;
}

enum SubscriptionPlanAction { renew, upgrade, reset }

List<SubscriptionPlanAction> subscriptionPlanActions(
  XboardSubscriptionData? subscription,
) {
  if (subscription == null) return const [];
  return [
    if (subscription.isMonthlyPlan) SubscriptionPlanAction.renew,
    SubscriptionPlanAction.upgrade,
    SubscriptionPlanAction.reset,
  ];
}

Future<XboardAvailablePlan?> _loadSubscriptionPlan({
  required XboardAuthService authService,
  required XboardSubscriptionData? subscription,
}) async {
  final session = globalState.xboardSession;
  if (session == null || globalState.isOfflineMode) return null;
  final planId = subscription?.planId;
  if (planId != null) {
    try {
      final planById = await authService.fetchPlans(
        endpoint: session.endpoint,
        authData: session.authData,
        planId: planId,
      );
      for (final plan in planById) {
        if (plan.id == planId) return plan;
      }
    } on XboardAuthException catch (error) {
      if (error.failure == XboardAuthFailure.authenticationRejected) rethrow;
    }
  }
  final plans = await authService.fetchPlans(
    endpoint: session.endpoint,
    authData: session.authData,
  );
  for (final plan in plans) {
    if (planId != null && plan.id == planId) return plan;
  }
  final planName = subscription?.plan?.name?.trim();
  for (final plan in plans) {
    if (planName != null && plan.name.trim() == planName) return plan;
  }
  return null;
}

Future<void> _executeSubscriptionPlanAction({
  required BuildContext context,
  required SubscriptionPlanAction action,
  required XboardSubscriptionData? subscription,
  required XboardAuthService authService,
  VoidCallback? onUpgrade,
}) async {
  if (action == SubscriptionPlanAction.upgrade) {
    if (onUpgrade != null) {
      onUpgrade();
    } else {
      globalState.container
          .read(currentPageLabelProvider.notifier)
          .toPage(PageLabel.profiles);
    }
    return;
  }
  final session = globalState.xboardSession;
  if (session == null || globalState.isOfflineMode) {
    if (context.mounted) {
      context.showNotifier(
        context.appLocalizations.subscriptionPlanUnavailable,
      );
    }
    return;
  }
  try {
    final plan = await _loadSubscriptionPlan(
      authService: authService,
      subscription: subscription,
    );
    if (!context.mounted) return;
    if (plan == null) {
      context.showNotifier(
        context.appLocalizations.subscriptionPlanUnavailable,
      );
      return;
    }
    if (action == SubscriptionPlanAction.reset) {
      if (!plan.prices.containsKey('reset_price')) {
        context.showNotifier(context.appLocalizations.trafficResetUnavailable);
        return;
      }
      await showXboardPaymentDialog(
        context: context,
        authService: authService,
        session: session,
        plan: plan,
        period: 'reset_price',
      );
      return;
    }
    final periods = xboardRecurringPeriodKeys
        .where(plan.prices.containsKey)
        .toList(growable: false);
    if (!plan.renew || periods.isEmpty) {
      context.showNotifier(context.appLocalizations.renewalUnavailable);
      return;
    }
    final period = await showDialog<String>(
      context: context,
      builder: (context) => _RenewalPeriodDialog(plan: plan, periods: periods),
    );
    if (!context.mounted || period == null) return;
    await showXboardPaymentDialog(
      context: context,
      authService: authService,
      session: session,
      plan: plan,
      period: period,
    );
  } catch (error, stackTrace) {
    commonPrint.log(
      'open subscription order failed: $error, $stackTrace',
      logLevel: LogLevel.warning,
    );
    if (context.mounted) {
      final message = error is XboardAuthException
          ? error.message
          : context.appLocalizations.planCatalogFailed;
      context.showNotifier(message);
    }
  }
}

SubscriptionStatusEvaluation evaluateSubscriptionStatus(
  XboardSubscriptionData? subscription, {
  DateTime? now,
}) {
  if (subscription == null) {
    return const SubscriptionStatusEvaluation(
      lowTraffic: false,
      expiringSoon: false,
      expired: false,
    );
  }
  final expiresAt = subscription.expiresAt;
  final currentTime = now ?? DateTime.now();
  final expired = expiresAt?.isAfter(currentTime) == false;
  final expiringSoon =
      expiresAt != null &&
      !expired &&
      expiresAt.difference(currentTime) < subscriptionExpiryWarningWindow;
  return SubscriptionStatusEvaluation(
    lowTraffic:
        subscription.remainingBytes < subscriptionLowTrafficThresholdBytes,
    expiringSoon: expiringSoon,
    expired: expired,
  );
}

class SubscriptionStatusIndicator extends StatefulWidget {
  const SubscriptionStatusIndicator({
    super.key,
    required this.subscription,
    this.authService,
    this.onChangePlan,
    this.size = 42,
    this.now,
  });

  final XboardSubscriptionData? subscription;
  final XboardAuthService? authService;
  final VoidCallback? onChangePlan;
  final double size;
  final DateTime? now;

  @override
  State<SubscriptionStatusIndicator> createState() =>
      _SubscriptionStatusIndicatorState();
}

class _SubscriptionStatusIndicatorState
    extends State<SubscriptionStatusIndicator>
    with SingleTickerProviderStateMixin {
  late final XboardAuthService _authService;
  late final AnimationController _rotationController;
  bool _dialogOpen = false;
  bool _processingAction = false;

  SubscriptionStatusEvaluation get _status =>
      evaluateSubscriptionStatus(widget.subscription, now: widget.now);

  @override
  void initState() {
    super.initState();
    _authService = widget.authService ?? XboardAuthService();
    _rotationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 460),
    );
    _syncAnimation();
  }

  @override
  void didUpdateWidget(covariant SubscriptionStatusIndicator oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncAnimation();
  }

  void _syncAnimation() {
    if (_status.hasWarning && !_dialogOpen && !_processingAction) {
      if (!_rotationController.isAnimating) {
        _rotationController.repeat(reverse: true);
      }
      return;
    }
    _rotationController
      ..stop()
      ..value = 0;
  }

  Future<void> _showStatus() async {
    if (_dialogOpen || _processingAction) return;
    setState(() => _dialogOpen = true);
    _syncAnimation();
    try {
      final action = await showDialog<SubscriptionPlanAction>(
        context: context,
        builder: (context) => _SubscriptionStatusDialog(
          subscription: widget.subscription,
          status: _status,
        ),
      );
      if (action != null && mounted) await _handleAction(action);
    } finally {
      if (mounted) {
        setState(() => _dialogOpen = false);
        _syncAnimation();
      }
    }
  }

  Future<void> _handleAction(SubscriptionPlanAction action) async {
    setState(() => _processingAction = true);
    _syncAnimation();
    try {
      await _executeSubscriptionPlanAction(
        context: context,
        action: action,
        subscription: widget.subscription,
        authService: _authService,
        onUpgrade: widget.onChangePlan,
      );
    } finally {
      if (mounted) {
        setState(() => _processingAction = false);
        _syncAnimation();
      }
    }
  }

  @override
  void dispose() {
    _rotationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final warning = _status.hasWarning;
    final color = warning ? const Color(0xFFFF3B57) : const Color(0xFF17B86A);
    final tooltip = warning
        ? context.appLocalizations.subscriptionWarningTooltip
        : context.appLocalizations.subscriptionNormalTooltip;
    return IconButton(
      key: const ValueKey('subscription-status-indicator'),
      tooltip: tooltip,
      onPressed: _processingAction ? null : _showStatus,
      style: IconButton.styleFrom(
        backgroundColor: color.withValues(alpha: 0.13),
        foregroundColor: color,
        fixedSize: Size.square(widget.size),
        side: BorderSide(color: color.withValues(alpha: 0.34)),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(widget.size * 0.34),
        ),
      ),
      icon: _processingAction
          ? SizedBox.square(
              dimension: widget.size * 0.48,
              child: CircularProgressIndicator(strokeWidth: 2.2, color: color),
            )
          : AnimatedBuilder(
              key: const ValueKey('subscription-status-light'),
              animation: _rotationController,
              builder: (context, child) => Transform.rotate(
                angle: warning
                    ? (_rotationController.value * 2 - 1) * math.pi / 18
                    : 0,
                child: child,
              ),
              child: Icon(
                Icons.notifications_active_rounded,
                size: widget.size * 0.55,
                shadows: warning
                    ? [
                        Shadow(
                          color: color.withValues(alpha: 0.55),
                          blurRadius: 8,
                        ),
                      ]
                    : null,
              ),
            ),
    );
  }
}

class _SubscriptionStatusDialog extends StatelessWidget {
  const _SubscriptionStatusDialog({
    required this.subscription,
    required this.status,
  });

  final XboardSubscriptionData? subscription;
  final SubscriptionStatusEvaluation status;

  String _remainingTraffic(XboardSubscriptionData subscription) {
    final value = subscription.remainingGb;
    if (value < 1) return value.toStringAsFixed(2);
    return value.toStringAsFixed(1);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.appLocalizations;
    final scheme = context.colorScheme;
    final warning = status.hasWarning;
    final statusColor = warning
        ? const Color(0xFFFF3B57)
        : const Color(0xFF17B86A);
    final headerWidth = (MediaQuery.sizeOf(context).width - 80).clamp(
      220.0,
      430.0,
    );
    final messages = <({IconData icon, String text})>[];
    if (status.lowTraffic && subscription != null) {
      messages.add((
        icon: Icons.data_usage_rounded,
        text: l10n.subscriptionLowTrafficWarning(
          _remainingTraffic(subscription!),
        ),
      ));
    }
    final expiresAt = subscription?.expiresAt;
    if (status.expired && expiresAt != null) {
      messages.add((
        icon: Icons.event_busy_rounded,
        text: l10n.subscriptionExpiredWarning(
          DateFormat.yMd(
            Localizations.localeOf(context).toLanguageTag(),
          ).format(expiresAt),
        ),
      ));
    } else if (status.expiringSoon && expiresAt != null) {
      messages.add((
        icon: Icons.event_rounded,
        text: l10n.subscriptionExpiringWarning(
          DateFormat.yMd(
            Localizations.localeOf(context).toLanguageTag(),
          ).format(expiresAt),
        ),
      ));
    }
    if (messages.isEmpty) {
      messages.add((
        icon: Icons.verified_rounded,
        text: l10n.subscriptionStatusNormalMessage,
      ));
    }

    return AlertDialog(
      key: const ValueKey('subscription-status-dialog'),
      scrollable: true,
      iconPadding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      icon: SizedBox(
        width: headerWidth,
        height: 64,
        child: Stack(
          children: [
            Align(
              child: Container(
                width: 58,
                height: 58,
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.13),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  warning
                      ? Icons.notifications_active_rounded
                      : Icons.verified_rounded,
                  color: statusColor,
                  size: 31,
                ),
              ),
            ),
            Align(
              alignment: Alignment.topRight,
              child: IconButton.filledTonal(
                key: const ValueKey('subscription-status-close'),
                tooltip: l10n.closeAction,
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close_rounded),
              ),
            ),
          ],
        ),
      ),
      title: Text(
        warning
            ? l10n.subscriptionWarningTitle
            : l10n.subscriptionStatusNormalTitle,
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 430),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final message in messages)
              Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: scheme.outlineVariant),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(message.icon, color: statusColor, size: 22),
                    const SizedBox(width: 11),
                    Expanded(
                      child: Text(
                        message.text,
                        style: TextStyle(color: scheme.onSurface, height: 1.45),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
      actions: [
        if (warning && subscription != null && subscription!.isMonthlyPlan)
          FilledButton.icon(
            key: const ValueKey('subscription-renew-button'),
            onPressed: () =>
                Navigator.pop(context, SubscriptionPlanAction.renew),
            icon: const Icon(Icons.event_repeat_rounded),
            label: Text(l10n.renewPlanAction),
          ),
        if (warning && subscription != null)
          FilledButton.tonalIcon(
            key: const ValueKey('subscription-change-plan-button'),
            onPressed: () =>
                Navigator.pop(context, SubscriptionPlanAction.upgrade),
            icon: const Icon(Icons.upgrade_rounded),
            label: Text(l10n.upgradePlanAction),
          ),
        if (warning && subscription != null)
          OutlinedButton.icon(
            key: const ValueKey('subscription-reset-traffic-button'),
            onPressed: () =>
                Navigator.pop(context, SubscriptionPlanAction.reset),
            icon: const Icon(Icons.restart_alt_rounded),
            label: Text(l10n.resetTrafficAction),
          ),
      ],
    );
  }
}

class SubscriptionPlanActionBar extends StatefulWidget {
  const SubscriptionPlanActionBar({
    super.key,
    required this.subscription,
    this.authService,
    this.onUpgrade,
  });

  final XboardSubscriptionData? subscription;
  final XboardAuthService? authService;
  final VoidCallback? onUpgrade;

  @override
  State<SubscriptionPlanActionBar> createState() =>
      _SubscriptionPlanActionBarState();
}

class _SubscriptionPlanActionBarState extends State<SubscriptionPlanActionBar> {
  SubscriptionPlanAction? _processingAction;

  Future<void> _handleAction(SubscriptionPlanAction action) async {
    if (_processingAction != null) return;
    setState(() => _processingAction = action);
    try {
      await _executeSubscriptionPlanAction(
        context: context,
        action: action,
        subscription: widget.subscription,
        authService: widget.authService ?? XboardAuthService(),
        onUpgrade: widget.onUpgrade,
      );
    } finally {
      if (mounted) setState(() => _processingAction = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final actions = subscriptionPlanActions(widget.subscription);
    if (actions.isEmpty) return const SizedBox.shrink();
    final scheme = context.colorScheme;
    return Container(
      key: const ValueKey('subscription-plan-actions'),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLowest.withValues(alpha: 0.96),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: scheme.outlineVariant),
        boxShadow: [
          BoxShadow(
            color: scheme.shadow.withValues(alpha: 0.08),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          for (var index = 0; index < actions.length; index++) ...[
            Expanded(child: _buildButton(context, actions[index])),
            if (index != actions.length - 1) const SizedBox(width: 10),
          ],
        ],
      ),
    );
  }

  Widget _buildButton(BuildContext context, SubscriptionPlanAction action) {
    final l10n = context.appLocalizations;
    final processing = _processingAction == action;
    final onPressed = _processingAction == null
        ? () => _handleAction(action)
        : null;
    final content = _SubscriptionActionContent(
      processing: processing,
      icon: switch (action) {
        SubscriptionPlanAction.renew => Icons.event_repeat_rounded,
        SubscriptionPlanAction.upgrade => Icons.upgrade_rounded,
        SubscriptionPlanAction.reset => Icons.restart_alt_rounded,
      },
      label: switch (action) {
        SubscriptionPlanAction.renew => l10n.renewPlanAction,
        SubscriptionPlanAction.upgrade => l10n.upgradePlanAction,
        SubscriptionPlanAction.reset => l10n.resetTrafficAction,
      },
    );
    final key = switch (action) {
      SubscriptionPlanAction.renew => const ValueKey('traffic-renew-plan'),
      SubscriptionPlanAction.upgrade => const ValueKey('traffic-upgrade-plan'),
      SubscriptionPlanAction.reset => const ValueKey('traffic-reset-plan'),
    };
    final style = ButtonStyle(
      minimumSize: const WidgetStatePropertyAll(Size.fromHeight(52)),
      padding: const WidgetStatePropertyAll(
        EdgeInsets.symmetric(horizontal: 8),
      ),
      shape: WidgetStatePropertyAll(
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      ),
    );
    return switch (action) {
      SubscriptionPlanAction.renew => FilledButton(
        key: key,
        onPressed: onPressed,
        style: style,
        child: content,
      ),
      SubscriptionPlanAction.upgrade => FilledButton.tonal(
        key: key,
        onPressed: onPressed,
        style: style,
        child: content,
      ),
      SubscriptionPlanAction.reset => OutlinedButton(
        key: key,
        onPressed: onPressed,
        style: style,
        child: content,
      ),
    };
  }
}

class _SubscriptionActionContent extends StatelessWidget {
  const _SubscriptionActionContent({
    required this.processing,
    required this.icon,
    required this.label,
  });

  final bool processing;
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (processing)
          const SizedBox.square(
            dimension: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        else
          Icon(icon, size: 19),
        const SizedBox(width: 7),
        Flexible(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              label,
              maxLines: 1,
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
        ),
      ],
    );
  }
}

class _RenewalPeriodDialog extends StatelessWidget {
  const _RenewalPeriodDialog({required this.plan, required this.periods});

  final XboardAvailablePlan plan;
  final List<String> periods;

  String _price(int value) {
    final amount = value / 100;
    final text = amount == amount.roundToDouble()
        ? amount.toStringAsFixed(0)
        : amount.toStringAsFixed(2);
    return '¥$text';
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.appLocalizations;
    final scheme = context.colorScheme;
    return AlertDialog(
      key: const ValueKey('subscription-renewal-period-dialog'),
      icon: Container(
        width: 58,
        height: 58,
        decoration: BoxDecoration(
          color: scheme.primaryContainer,
          shape: BoxShape.circle,
        ),
        child: Icon(
          Icons.event_repeat_rounded,
          color: scheme.onPrimaryContainer,
          size: 31,
        ),
      ),
      title: Text(l10n.renewalNoticeTitle),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 430),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFA000).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: const Color(0xFFFFA000).withValues(alpha: 0.35),
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      Icons.info_outline_rounded,
                      color: Color(0xFFE28A00),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        l10n.renewalDoesNotResetTraffic,
                        style: TextStyle(color: scheme.onSurface, height: 1.45),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              Text(
                l10n.selectRenewalPeriod,
                style: TextStyle(
                  color: scheme.onSurface,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 10),
              for (final period in periods) ...[
                OutlinedButton(
                  key: ValueKey('subscription-renewal-period-$period'),
                  onPressed: () => Navigator.pop(context, period),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(50),
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(15),
                    ),
                  ),
                  child: Row(
                    children: [
                      Expanded(child: Text(xboardPeriodLabel(context, period))),
                      const SizedBox(width: 12),
                      Text(
                        _price(plan.prices[period] ?? 0),
                        style: TextStyle(
                          color: scheme.primary,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
                  ),
                ),
                if (period != periods.last) const SizedBox(height: 8),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.cancel),
        ),
      ],
    );
  }
}

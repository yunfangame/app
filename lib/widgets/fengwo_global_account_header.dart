import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/pages/customer_service.dart';
import 'package:fl_clash/state.dart';
import 'package:fl_clash/views/tools.dart';
import 'package:fl_clash/widgets/fengwo_account_avatar.dart';
import 'package:fl_clash/widgets/subscription_status_indicator.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class FengWoGlobalAccountHeader extends StatelessWidget {
  final XboardSubscriptionData? subscription;

  const FengWoGlobalAccountHeader({super.key, required this.subscription});

  @override
  Widget build(BuildContext context) {
    final scheme = context.colorScheme;
    final l10n = context.appLocalizations;
    final email = subscription?.email.takeFirstValid(['--']) ?? '--';
    final planName =
        subscription?.plan?.name.takeFirstValid([l10n.noActivePlan]) ??
        l10n.noActivePlan;
    final expiresAt = subscription?.expiresAt;
    final expiry = subscription?.isUnlimitedTime ?? true
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
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 720;
        final tight = constraints.maxWidth < 360;
        final textColor = scheme.onSurface;
        final muted = scheme.onSurfaceVariant;
        return ClipRRect(
          borderRadius: const BorderRadius.only(topLeft: Radius.circular(34)),
          child: Container(
            key: const ValueKey('fengwo-global-account-header'),
            height: tight ? 60 : (compact ? 68 : 82),
            padding: EdgeInsets.symmetric(
              horizontal: tight ? 8 : (compact ? 16 : 30),
            ),
            decoration: BoxDecoration(
              color: scheme.surface,
              border: Border(bottom: BorderSide(color: scheme.outlineVariant)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                FengWoAccountAvatar(
                  key: const ValueKey('fengwo-global-account-avatar'),
                  size: tight ? 36 : (compact ? 44 : 52),
                ),
                SizedBox(width: tight ? 6 : 11),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        email,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: textColor,
                          fontSize: compact ? 14 : 16,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      if (!compact) ...[
                        const SizedBox(height: 3),
                        Text(
                          '$planName · $expiry',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: muted, fontSize: 12),
                        ),
                        if (nextReset != null) ...[
                          const SizedBox(height: 2),
                          Text(
                            l10n.nextPlanResetAt(nextReset),
                            key: const ValueKey(
                              'fengwo-global-next-plan-reset',
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: scheme.primary,
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ],
                    ],
                  ),
                ),
                SubscriptionStatusIndicator(
                  subscription: subscription,
                  size: tight ? 36 : (compact ? 40 : 44),
                ),
                SizedBox(width: tight ? 2 : (compact ? 4 : 10)),
                if (!compact)
                  Container(
                    constraints: const BoxConstraints(maxWidth: 150),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 15,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: scheme.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: Text(
                      planName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: scheme.primary,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                SizedBox(width: compact ? 2 : 12),
                if (!compact)
                  _GlobalHeaderIcon(
                    icon: Icons.translate_rounded,
                    compact: compact,
                    onPressed: () => ToolLocaleSelector.show(context),
                  ),
                _GlobalHeaderIcon(
                  icon: Icons.palette_outlined,
                  compact: compact,
                  onPressed: () => ToolThemeSelector.show(context),
                ),
                if (!compact)
                  const _GlobalHeaderIcon(icon: Icons.card_giftcard_rounded),
                if (!tight)
                  _GlobalHeaderIcon(
                    icon: Icons.headset_mic_outlined,
                    compact: compact,
                    onPressed: () => CustomerServiceSheet.show(context),
                  ),
                if (!tight)
                  _GlobalHeaderIcon(
                    icon: Icons.notifications_none_rounded,
                    compact: compact,
                    tooltip: l10n.announcementTooltip,
                    onPressed: () => globalState.showXboardAnnouncements?.call(
                      automatic: false,
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _GlobalHeaderIcon extends StatelessWidget {
  final IconData icon;
  final bool compact;
  final VoidCallback? onPressed;
  final String? tooltip;

  const _GlobalHeaderIcon({
    required this.icon,
    this.compact = false,
    this.onPressed,
    this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      color: context.colorScheme.onSurface,
      disabledColor: context.colorScheme.onSurfaceVariant,
      visualDensity: VisualDensity.compact,
      constraints: BoxConstraints.tightFor(
        width: compact ? 38 : 48,
        height: compact ? 42 : 48,
      ),
      padding: EdgeInsets.zero,
      iconSize: compact ? 21 : 23,
      icon: Icon(icon),
    );
  }
}

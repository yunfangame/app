import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/common/subscription_entry_reminder.dart';
import 'package:fl_clash/widgets/subscription_status_indicator.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

@immutable
class SubscriptionEntryReminderChoice {
  const SubscriptionEntryReminderChoice({this.dontRemind = false});

  final bool dontRemind;
}

class SubscriptionEntryReminderDialog extends StatelessWidget {
  const SubscriptionEntryReminderDialog({
    super.key,
    required this.subscription,
    required this.evaluation,
    required this.now,
  });

  final XboardSubscriptionData subscription;
  final SubscriptionEntryReminderEvaluation evaluation;
  final DateTime now;

  DateTime? _readTime(int? epochSeconds, DateTime? Function() read) {
    if (epochSeconds == null ||
        epochSeconds <= 0 ||
        epochSeconds > 8640000000000) {
      return null;
    }
    try {
      return read();
    } on ArgumentError {
      return null;
    }
  }

  String _remainingTraffic(double remaining) {
    if (remaining > 0 && remaining < 0.01) return '<0.01';
    final digits = remaining < 1 ? 2 : 1;
    final factor = digits == 2 ? 100 : 10;
    return ((remaining * factor).floor() / factor).toStringAsFixed(digits);
  }

  void _close(BuildContext context, {required bool dontRemind}) {
    Navigator.pop(
      context,
      SubscriptionEntryReminderChoice(dontRemind: dontRemind),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.appLocalizations;
    final scheme = context.colorScheme;
    final remaining = subscription.remainingGb;
    final expiresAt = _readTime(
      subscription.expiredAtEpochSeconds,
      () => subscription.expiresAt,
    );
    final candidateResetAt = _readTime(
      subscription.nextResetAtEpochSeconds,
      () => subscription.nextResetAt,
    );
    final resetAt =
        subscription.isMonthlyPlan &&
            expiresAt != null &&
            candidateResetAt != null &&
            candidateResetAt.isAfter(now) &&
            !candidateResetAt.isAfter(expiresAt)
        ? candidateResetAt
        : null;

    return AlertDialog(
      key: const ValueKey('subscription-entry-reminder-dialog'),
      scrollable: true,
      surfaceTintColor: Colors.transparent,
      icon: Icon(Icons.notifications_active_rounded, color: scheme.primary),
      title: Text(l10n.subscriptionEntryReminderTitle),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.subscriptionEntryReminderRemaining(
                _remainingTraffic(remaining),
              ),
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            if (evaluation.lowTraffic) ...[
              const SizedBox(height: 8),
              Text(l10n.subscriptionEntryReminderLowTraffic),
            ],
            if (evaluation.expiringSoon && expiresAt != null) ...[
              const SizedBox(height: 8),
              Text(
                l10n.subscriptionEntryReminderExpiring(
                  DateFormat.yMd(
                    Localizations.localeOf(context).toLanguageTag(),
                  ).add_Hm().format(expiresAt),
                ),
                key: const ValueKey('subscription-entry-reminder-expiry'),
              ),
            ],
            if (subscription.isMonthlyPlan && resetAt != null) ...[
              const SizedBox(height: 8),
              Text(
                subscriptionResetRemaining(context, resetAt, now: now),
                key: const ValueKey('subscription-entry-reminder-reset'),
              ),
            ],
            const SizedBox(height: 16),
            Text(
              l10n.subscriptionEntryReminderDontRemindScope,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          key: const ValueKey('subscription-entry-reminder-dont-remind'),
          onPressed: () => _close(context, dontRemind: true),
          child: Text(l10n.subscriptionEntryReminderDontRemind),
        ),
        FilledButton(
          key: const ValueKey('subscription-entry-reminder-close'),
          onPressed: () => _close(context, dontRemind: false),
          child: Text(l10n.subscriptionEntryReminderDismiss),
        ),
      ],
    );
  }
}

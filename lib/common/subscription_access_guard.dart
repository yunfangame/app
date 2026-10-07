import 'dart:async';

import 'xboard_auth.dart';

enum SubscriptionAccessIssue { expired, exhausted }

bool hasValidSubscriptionUsage(XboardSubscriptionData subscription) {
  return ['transfer_enable', 'u', 'd'].every((key) {
    final value = subscription.rawData[key];
    if (value is num) {
      return value.isFinite && value >= 0 && value == value.truncateToDouble();
    }
    if (value is String) {
      final number = int.tryParse(value.trim());
      return number != null && number >= 0;
    }
    return false;
  });
}

SubscriptionAccessIssue? subscriptionAccessIssue(
  XboardSubscriptionData subscription, {
  DateTime? now,
}) {
  if (!hasValidSubscriptionUsage(subscription)) return null;
  if (subscription.expiresAt?.isAfter(now ?? DateTime.now()) == false) {
    return SubscriptionAccessIssue.expired;
  }
  if (subscription.remainingBytes <= 0) {
    return SubscriptionAccessIssue.exhausted;
  }
  return null;
}

class SubscriptionAccessGuard {
  final _notified = <String, SubscriptionAccessIssue>{};
  final _pending = <String, Future<bool>>{};

  Future<bool> check({
    required String account,
    String? requestKey,
    required Future<XboardSubscriptionData> Function() fetch,
    required bool Function() isCurrent,
    required Future<void> Function(
      XboardSubscriptionData subscription,
      SubscriptionAccessIssue issue,
    )
    notify,
  }) {
    final pendingKey = '$account|${requestKey ?? ''}';
    final pending = _pending[pendingKey];
    if (pending != null) return pending;
    final completer = Completer<bool>();
    _pending[pendingKey] = completer.future;
    unawaited(() async {
      var unavailable = false;
      try {
        final subscription = await fetch();
        if (!hasValidSubscriptionUsage(subscription)) {
          throw const FormatException('invalid_subscription_usage');
        }
        if (!isCurrent()) {
          completer.complete(false);
          return;
        }
        final issue = subscriptionAccessIssue(subscription);
        if (issue == null) {
          _notified.remove(account);
          completer.complete(true);
          return;
        }
        unavailable = true;
        if (_notified[account] != issue) {
          await notify(subscription, issue);
          if (isCurrent()) _notified[account] = issue;
        }
        completer.complete(false);
      } catch (_) {
        completer.complete(isCurrent() && !unavailable);
      } finally {
        _pending.remove(pendingKey);
      }
    }());
    return completer.future;
  }
}

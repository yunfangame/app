import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'xboard_auth.dart';

class SubscriptionEntryReminderEvaluation {
  const SubscriptionEntryReminderEvaluation({
    required this.lowTraffic,
    required this.expiringSoon,
  });

  final bool lowTraffic;
  final bool expiringSoon;
}

SubscriptionEntryReminderEvaluation? evaluateSubscriptionEntryReminder(
  XboardSubscriptionData? subscription, {
  DateTime? now,
}) {
  if (subscription == null) return null;
  final quota = subscription.transferEnableBytes;
  final upload = subscription.uploadBytes;
  final download = subscription.downloadBytes;
  if (quota <= 0 || upload < 0 || download < 0 || upload >= quota) {
    return null;
  }
  final afterUpload = quota - upload;
  if (download >= afterUpload) return null;
  final lowRemainingTraffic = afterUpload - download < 10 * bytesPerGigabyte;
  if (subscription.isUnlimitedTime) {
    return lowRemainingTraffic
        ? const SubscriptionEntryReminderEvaluation(
            lowTraffic: true,
            expiringSoon: false,
          )
        : null;
  }
  final currentTime = now ?? DateTime.now();
  final expiresAt = _validEpochSeconds(subscription.expiredAtEpochSeconds);
  if (expiresAt == null || !expiresAt.isAfter(currentTime)) return null;
  final expiringSoon =
      expiresAt.difference(currentTime) < const Duration(days: 3);
  final nextResetAt = _validEpochSeconds(subscription.nextResetAtEpochSeconds);
  final lowTraffic =
      lowRemainingTraffic &&
      nextResetAt != null &&
      nextResetAt.isAfter(currentTime) &&
      !nextResetAt.isAfter(expiresAt) &&
      nextResetAt.difference(currentTime) > const Duration(days: 7);
  if (!lowTraffic && !expiringSoon) return null;
  return SubscriptionEntryReminderEvaluation(
    lowTraffic: lowTraffic,
    expiringSoon: expiringSoon,
  );
}

DateTime? _validEpochSeconds(int? value) {
  if (value == null || value <= 0 || value > 8640000000000) return null;
  return DateTime.fromMillisecondsSinceEpoch(value * 1000, isUtc: true);
}

class SubscriptionEntryReminderStore {
  SubscriptionEntryReminderStore({
    Future<SharedPreferences> Function()? preferencesLoader,
  }) : _preferencesLoader = preferencesLoader ?? SharedPreferences.getInstance;

  static const _accountNamespace =
      'fengwo.subscription-entry-reminder.account.v1';
  static const _preferencePrefix =
      'xboard.subscription_entry_reminder.disabled.';

  final Future<SharedPreferences> Function() _preferencesLoader;
  final Set<String> _disabled = {};
  Future<void> _writeQueue = Future<void>.value();

  static String? accountKey(
    XboardLoginResult session, {
    String? fallbackAccountKey,
  }) {
    final email = session.subscription.email?.trim().toLowerCase();
    if (email != null && email.isNotEmpty) {
      final ruleAccountKey = _hash('fengwo.local-account-rules.v1\u0000$email');
      return _hash('$_accountNamespace\u0000account:$ruleAccountKey');
    }
    if (fallbackAccountKey != null &&
        RegExp(r'^[a-f0-9]{64}$').hasMatch(fallbackAccountKey)) {
      return _hash('$_accountNamespace\u0000account:$fallbackAccountKey');
    }
    final uuid = session.subscription.uuid?.trim().toLowerCase();
    if (uuid != null && uuid.isNotEmpty) {
      return _hash('$_accountNamespace\u0000uuid:$uuid');
    }
    return null;
  }

  Future<bool> isDisabled(String accountKey) async {
    final key = _storageKey(accountKey);
    if (_disabled.contains(key)) return true;
    final preferences = await _preferencesLoader();
    if (_disabled.contains(key)) return true;
    final disabled = preferences.get(key) == true;
    if (disabled) _disabled.add(key);
    return disabled;
  }

  Future<void> disable(String accountKey) {
    final key = _storageKey(accountKey);
    _disabled.add(key);
    final operation = _writeQueue.then((_) async {
      final preferences = await _preferencesLoader();
      if (!await preferences.setBool(key, true)) {
        throw StateError('subscription_entry_reminder_write_failed');
      }
    });
    _writeQueue = operation.catchError(
      (Object error, StackTrace stackTrace) {},
    );
    return operation;
  }

  static String _storageKey(String accountKey) {
    final normalized = accountKey.trim();
    if (normalized.isEmpty) {
      throw ArgumentError('subscription_entry_reminder_account_key_missing');
    }
    return '$_preferencePrefix${_hash('$_preferencePrefix\u0000$normalized')}';
  }

  static String _hash(String value) =>
      sha256.convert(utf8.encode(value)).toString();
}

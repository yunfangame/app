import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:fl_clash/l10n/l10n.dart';

import 'api_network_diagnostic.dart';
import 'subscription_v2.dart';
import 'xboard_auth.dart';

enum SubscriptionAccess {
  available,
  notPurchased,
  expired,
  unknown;

  bool get blocksProfileSync => this == notPurchased || this == expired;

  String? message(AppLocalizations l10n) => switch (this) {
    notPurchased => l10n.subscriptionNotPurchased,
    expired => l10n.subscriptionPlanExpired,
    _ => null,
  };
}

SubscriptionAccess evaluateSubscriptionAccess(
  XboardSubscriptionData subscription, {
  DateTime? now,
}) {
  final raw = subscription.rawData;
  final rawPlanId = raw['plan_id'];
  final explicitPlanId = _summaryInteger(rawPlanId);
  if (rawPlanId != null && explicitPlanId == null ||
      raw['plan'] != null && raw['plan'] is! Map) {
    return SubscriptionAccess.unknown;
  }
  final hasPlan =
      (subscription.planId ?? 0) > 0 ||
      (explicitPlanId ?? 0) > 0 ||
      (subscription.plan?.id ?? 0) > 0 ||
      subscription.plan?.name?.trim().isNotEmpty == true;
  final rawExpiry = raw['expired_at'];
  final explicitExpiry = _summaryInteger(rawExpiry);
  final expiry = subscription.expiredAtEpochSeconds;
  final currentSeconds = (now ?? DateTime.now()).millisecondsSinceEpoch ~/ 1000;
  if (expiry != null && expiry <= currentSeconds ||
      hasPlan && explicitExpiry != null && explicitExpiry <= 0) {
    return SubscriptionAccess.expired;
  }
  if (rawExpiry != null && explicitExpiry == null) {
    return SubscriptionAccess.unknown;
  }
  final rawQuota = raw['transfer_enable'];
  final explicitQuota = _summaryInteger(rawQuota);
  final hasExplicitEmptyPlan =
      (raw.containsKey('plan_id') &&
          (rawPlanId == null || explicitPlanId == 0)) ||
      (raw.containsKey('plan') && raw['plan'] == null);
  if (!hasPlan &&
      hasExplicitEmptyPlan &&
      explicitQuota == 0 &&
      subscription.transferEnableBytes == 0) {
    return SubscriptionAccess.notPurchased;
  }
  if (subscription.transferEnableBytes > 0 &&
      (expiry != null || raw.containsKey('expired_at'))) {
    return SubscriptionAccess.available;
  }
  return SubscriptionAccess.unknown;
}

int? _summaryInteger(Object? value) {
  if (value is int) return value;
  if (value is num && value.isFinite && value == value.truncate()) {
    return value.toInt();
  }
  if (value is String) return int.tryParse(value.trim());
  return null;
}

Future<T?> syncAccessibleSubscriptionProfile<T>({
  required XboardSubscriptionData subscription,
  required bool Function() isCurrent,
  required Future<T?> Function() sync,
  required void Function(SubscriptionAccess access) onBlocked,
  required ApiDiagnosticRecorder onDiagnostic,
}) async {
  if (!isCurrent()) return null;
  final access = evaluateSubscriptionAccess(subscription);
  emitApiDiagnosticEvent(onDiagnostic, 'subscription.access.evaluated', {
    'access': access.name,
  });
  if (access.blocksProfileSync) {
    emitApiDiagnosticEvent(onDiagnostic, 'subscription.profile.sync.skipped', {
      'reason': access.name,
    });
    if (isCurrent()) onBlocked(access);
    return null;
  }
  if (!isCurrent()) return null;
  final profile = await sync();
  return isCurrent() ? profile : null;
}

class SubscriptionDownloadException implements Exception {
  const SubscriptionDownloadException({
    required this.message,
    required this.diagnostic,
  });

  final String message;
  final ApiNetworkDiagnostic diagnostic;

  @override
  String toString() => message;
}

Object preserveSubscriptionDownloadError(
  Object error,
  AppLocalizations l10n,
  Uri? endpoint,
) {
  if (error is DioException &&
      error.type != DioExceptionType.unknown &&
      error.type != DioExceptionType.badResponse) {
    return error;
  }
  return SubscriptionDownloadException(
    message: error is DioException && error.type == DioExceptionType.badResponse
        ? l10n.networkException
        : l10n.unknownNetworkError,
    diagnostic: classifyApiNetworkFailure(
      error,
      stage: 'subscription_download',
      endpoint: endpoint,
    ),
  );
}

ApiNetworkDiagnostic? subscriptionProfileDiagnostic(Object error) {
  if (error is SubscriptionDownloadException) return error.diagnostic;
  if (error is SubscriptionV2Exception) {
    return error.diagnostic ??
        (error.statusCode == null
            ? null
            : ApiNetworkDiagnostic(
                failure: ApiNetworkFailure.http,
                stage: 'subscription_profile',
                statusCode: error.statusCode,
              ));
  }
  if (error is XboardAuthException) {
    return error.diagnostic ??
        (error.statusCode == null
            ? null
            : ApiNetworkDiagnostic(
                failure: ApiNetworkFailure.http,
                stage: 'subscription_profile',
                statusCode: error.statusCode,
              ));
  }
  if (error is DioException ||
      error is SocketException ||
      error is TlsException ||
      error is TimeoutException ||
      error is HttpException) {
    return classifyApiNetworkFailure(error, stage: 'subscription_profile');
  }
  return null;
}

String subscriptionProfileFailureMessage(Object error, AppLocalizations l10n) {
  final diagnostic = subscriptionProfileDiagnostic(error);
  final networkFailure = switch (diagnostic?.failure) {
    ApiNetworkFailure.dns ||
    ApiNetworkFailure.timeout ||
    ApiNetworkFailure.tls ||
    ApiNetworkFailure.connectionRefused ||
    ApiNetworkFailure.connectionReset ||
    ApiNetworkFailure.permissionDenied ||
    ApiNetworkFailure.network => true,
    _ => false,
  };
  return networkFailure
      ? l10n.subscriptionImportFailed
      : l10n.subscriptionProfileUnavailable;
}

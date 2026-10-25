import 'dart:async';

import 'package:fl_clash/common/api_health.dart' show ApiHealthService;
import 'package:fl_clash/common/app_update.dart'
    show
        AppUpdateCheckStatus,
        AppUpdateCheckDeferred,
        AppUpdateRelease,
        AppUpdateService,
        AppUpdateUnavailableException;
import 'package:fl_clash/common/print.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/state.dart';
import 'package:flutter/foundation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'generated/app_update.g.dart';

enum AppUpdateStatus {
  idle,
  checking,
  available,
  upToDate,
  unavailable,
  failed,
}

class AppUpdateState {
  const AppUpdateState({
    this.status = AppUpdateStatus.idle,
    this.release,
    this.checkedAt,
    this.isAutomaticCheck = false,
  });

  final AppUpdateStatus status;
  final AppUpdateRelease? release;
  final DateTime? checkedAt;
  final bool isAutomaticCheck;

  bool get isChecking => status == AppUpdateStatus.checking;
  bool get hasUpdate => release != null;
  bool get isManualChecking => isChecking && !isAutomaticCheck;
}

class _AppUpdateCheckRequest {
  _AppUpdateCheckRequest(this.revision, this.forceRefresh);

  final int revision;
  final bool forceRefresh;
  final completer = Completer<AppUpdateState>();
  Future<AppUpdateState> get future => completer.future;
}

@Riverpod(name: 'appUpdateServiceProvider', keepAlive: true)
AppUpdateService updateService(Ref ref) {
  final service = AppUpdateService();
  ref.onDispose(service.close);
  return service;
}

@Riverpod(keepAlive: true)
String? appUpdateCurrentVersion(Ref ref) {
  try {
    final packageInfo = globalState.packageInfo;
    return packageInfo.buildNumber.trim().isEmpty
        ? packageInfo.version
        : '${packageInfo.version}+${packageInfo.buildNumber}';
  } catch (_) {
    return null;
  }
}

@Riverpod(keepAlive: true)
class AppUpdate extends _$AppUpdate {
  _AppUpdateCheckRequest? _automaticCheck;
  _AppUpdateCheckRequest? _forcedCheck;
  int _revision = 0;
  int _failures = 0;
  DateTime? _successAt;
  DateTime? _failedAt;
  DateTime? _retryAfter;
  String? _checkedVersion;
  Completer<AppUpdateState>? _pendingAutomatic;

  @override
  AppUpdateState build() {
    final availability = createUpdateAvailabilityService();
    availability.addAvailabilityListener(_resumeAutomaticCheck);
    ref.onDispose(() {
      availability.removeAvailabilityListener(_resumeAutomaticCheck);
      final pending = _pendingAutomatic;
      _pendingAutomatic = null;
      if (pending != null && !pending.isCompleted) {
        pending.complete(const AppUpdateState());
      }
    });
    return const AppUpdateState();
  }

  @visibleForTesting
  ApiHealthService createUpdateAvailabilityService() => ApiHealthService();

  Future<AppUpdateState> _deferAutomaticCheck() {
    final pending = _pendingAutomatic ??= Completer<AppUpdateState>();
    scheduleMicrotask(_resumeAutomaticCheck);
    return pending.future;
  }

  void _resumeAutomaticCheck() {
    final pending = _pendingAutomatic;
    if (!ref.mounted ||
        pending == null ||
        !canAutomaticallyCheckUpdates ||
        _automaticCheck != null ||
        _forcedCheck != null) {
      return;
    }
    _pendingAutomatic = null;
    pending.complete(check(forceRefresh: false));
  }

  @visibleForTesting
  DateTime get updateCheckNow => DateTime.now();

  @visibleForTesting
  Duration get automaticResultTtl => const Duration(minutes: 10);

  @visibleForTesting
  bool get canAutomaticallyCheckUpdates =>
      ApiHealthService.automaticRequestsAvailable && !globalState.isOfflineMode;

  Future<AppUpdateState> check({bool forceRefresh = true}) {
    final forced = _forcedCheck;
    if (forced != null) return forced.future;
    final currentVersion = ref.read(appUpdateCurrentVersionProvider);
    final automatic = _automaticCheck;
    if (!forceRefresh) {
      if (!canAutomaticallyCheckUpdates) return _deferAutomaticCheck();
      if (automatic != null) return automatic.future;
      if (_checkedVersion == currentVersion) {
        final now = updateCheckNow;
        final successAt = _successAt;
        if (successAt != null) {
          final age = now.difference(successAt);
          if (!age.isNegative && age < automaticResultTtl) {
            return Future.value(state);
          }
        }
        final failedAt = _failedAt;
        final retryAfter = _retryAfter;
        if (failedAt != null &&
            retryAfter != null &&
            !now.isBefore(failedAt) &&
            now.isBefore(retryAfter)) {
          return Future.value(state);
        }
      }
    }
    final request = _AppUpdateCheckRequest(++_revision, forceRefresh);
    if (forceRefresh) {
      _forcedCheck = request;
      _automaticCheck = null;
      final pending = _pendingAutomatic;
      _pendingAutomatic = null;
      if (pending != null && !pending.isCompleted) {
        pending.complete(request.future);
      }
      if (automatic != null && !automatic.completer.isCompleted) {
        automatic.completer.complete(request.future);
      }
    } else {
      _automaticCheck = request;
    }
    final previous = state;
    state = AppUpdateState(
      status: AppUpdateStatus.checking,
      release: previous.release,
      checkedAt: previous.checkedAt,
      isAutomaticCheck: !forceRefresh,
    );
    unawaited(_completeCheck(request, previous, currentVersion));
    return request.future;
  }

  Future<void> _completeCheck(
    _AppUpdateCheckRequest request,
    AppUpdateState previous,
    String? currentVersion,
  ) async {
    late final AppUpdateState next;
    var failed = false;
    var deferred = false;
    try {
      if (currentVersion == null || currentVersion.trim().isEmpty) {
        throw const AppUpdateUnavailableException();
      }
      final result = await ref
          .read(appUpdateServiceProvider)
          .discoverUpdate(
            currentVersion: currentVersion,
            forceRefresh: request.forceRefresh,
            canFetch: request.forceRefresh
                ? null
                : () =>
                      ref.mounted &&
                      request.revision == _revision &&
                      canAutomaticallyCheckUpdates,
          );
      next = AppUpdateState(
        status: switch (result.status) {
          AppUpdateCheckStatus.available => AppUpdateStatus.available,
          AppUpdateCheckStatus.upToDate => AppUpdateStatus.upToDate,
          AppUpdateCheckStatus.unavailable => AppUpdateStatus.unavailable,
        },
        release: result.release,
        checkedAt: updateCheckNow,
      );
    } on AppUpdateCheckDeferred {
      deferred = true;
      next = previous;
    } on AppUpdateUnavailableException {
      failed = true;
      next = AppUpdateState(
        status: AppUpdateStatus.unavailable,
        release: previous.release,
        checkedAt: updateCheckNow,
      );
    } catch (error) {
      failed = true;
      commonPrint.log(
        'check app update failed: $error',
        logLevel: LogLevel.warning,
      );
      next = AppUpdateState(
        status: AppUpdateStatus.failed,
        release: previous.release,
        checkedAt: updateCheckNow,
      );
    }
    if (ref.mounted && request.revision == _revision) {
      state = next;
      if (!deferred) {
        if (_checkedVersion != currentVersion) _failures = 0;
        _checkedVersion = currentVersion;
        if (failed) {
          const delays = [30, 60, 120, 300];
          _failures++;
          _successAt = null;
          _failedAt = updateCheckNow;
          _retryAfter = _failedAt!.add(
            Duration(seconds: delays[(_failures - 1).clamp(0, 3)]),
          );
        } else {
          _failures = 0;
          _failedAt = null;
          _retryAfter = null;
          _successAt = updateCheckNow;
        }
      }
    }
    if (identical(_automaticCheck, request)) _automaticCheck = null;
    if (identical(_forcedCheck, request)) _forcedCheck = null;
    if (!request.completer.isCompleted) {
      if (deferred && ref.mounted && request.revision == _revision) {
        request.completer.complete(_deferAutomaticCheck());
      } else {
        request.completer.complete(next);
      }
    }
    if (_pendingAutomatic != null) scheduleMicrotask(_resumeAutomaticCheck);
  }
}

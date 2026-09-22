import 'dart:async';
import 'dart:io';

import 'package:fl_clash/common/app_update.dart'
    show
        AppUpdateCheckStatus,
        AppUpdateRelease,
        AppUpdateService,
        AppUpdateUnavailableException;
import 'package:fl_clash/common/print.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/state.dart';
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
  });

  final AppUpdateStatus status;
  final AppUpdateRelease? release;
  final DateTime? checkedAt;

  bool get isChecking => status == AppUpdateStatus.checking;
  bool get hasUpdate => release != null;
}

@Riverpod(name: 'appUpdateServiceProvider', keepAlive: true)
AppUpdateService updateService(Ref ref) {
  final service = AppUpdateService();
  ref.onDispose(service.close);
  return service;
}

@Riverpod(keepAlive: true)
String appUpdatePlatform(Ref ref) => Platform.operatingSystem;

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
  Future<AppUpdateState>? _activeCheck;

  @override
  AppUpdateState build() => const AppUpdateState();

  Future<AppUpdateState> check() {
    final running = _activeCheck;
    if (running != null) return running;
    final completer = Completer<AppUpdateState>();
    _activeCheck = completer.future;
    final previous = state;
    state = AppUpdateState(
      status: AppUpdateStatus.checking,
      release: previous.release,
      checkedAt: previous.checkedAt,
    );
    unawaited(
      _performCheck(previous).then((result) {
        _activeCheck = null;
        completer.complete(result);
      }),
    );
    return completer.future;
  }

  Future<AppUpdateState> _performCheck(AppUpdateState previous) async {
    late final AppUpdateState next;
    try {
      final currentVersion = ref.read(appUpdateCurrentVersionProvider);
      if (currentVersion == null || currentVersion.trim().isEmpty) {
        throw const AppUpdateUnavailableException();
      }
      final result = await ref
          .read(appUpdateServiceProvider)
          .discoverUpdate(currentVersion: currentVersion);
      next = AppUpdateState(
        status: switch (result.status) {
          AppUpdateCheckStatus.available => AppUpdateStatus.available,
          AppUpdateCheckStatus.upToDate => AppUpdateStatus.upToDate,
          AppUpdateCheckStatus.unavailable => AppUpdateStatus.unavailable,
        },
        release: result.release,
        checkedAt: DateTime.now(),
      );
    } on AppUpdateUnavailableException {
      next = AppUpdateState(
        status: AppUpdateStatus.unavailable,
        release: previous.release,
        checkedAt: DateTime.now(),
      );
    } catch (error) {
      commonPrint.log(
        'check app update failed: $error',
        logLevel: LogLevel.warning,
      );
      next = AppUpdateState(
        status: AppUpdateStatus.failed,
        release: previous.release,
        checkedAt: DateTime.now(),
      );
    }
    if (ref.mounted) state = next;
    return next;
  }
}

part of '../action.dart';

@Riverpod(keepAlive: true)
class CommonAction extends _$CommonAction {
  Future<void>? _appUpdatePrompt;
  Future<AppUpdateState>? _appUpdateCheck;
  bool _manualAppUpdateRequested = false;
  bool _appUpdateDialogVisible = false;

  @override
  void build() {}

  Future<void> startAfterLogin({required bool Function() isCurrent}) async {
    if (!ref.mounted ||
        !isCurrent() ||
        !ref.read(initProvider) ||
        ref.read(isStartProvider) ||
        ref.read(connectionPendingProvider)) {
      return;
    }
    if (!isCurrent()) return;
    commonPrint.event('connection.auto.requested');
    await ref.read(setupActionProvider.notifier).startAutomatically();
  }

  Future<void> toggleRunning() async {
    final running =
        !ref.read(isStartProvider) && !ref.read(connectionPendingProvider);
    ref
        .read(setupActionProvider.notifier)
        .setRunning(running, initialize: running && !ref.read(initProvider));
  }

  void updateSpeedStatistics() {
    ref
        .read(appSettingProvider.notifier)
        .update((state) => state.copyWith(showTrayTitle: !state.showTrayTitle));
  }

  void updateMode() {
    final setup = ref.read(setupActionProvider.notifier);
    final mode = setup.requestedMode;
    final index = Mode.values.indexOf(mode);
    final nextIndex = (index + 1) % Mode.values.length;
    setup.changeMode(Mode.values[nextIndex]);
  }

  Future<void> updateTraffic() async {
    final onlyStatisticsProxy = ref.read(
      appSettingProvider.select((state) => state.onlyStatisticsProxy),
    );
    try {
      final traffic = await coreController.getTraffic(onlyStatisticsProxy);
      ref.read(trafficsProvider.notifier).addTraffic(traffic);
      ref.read(totalTrafficProvider.notifier).value = await coreController
          .getTotalTraffic(onlyStatisticsProxy);
    } catch (error) {
      commonPrint.log(
        'updateTraffic error: $error',
        logLevel: coreFailureLogLevel(error),
      );
    }
  }

  Future<void> autoCheckUpdate() async {
    if (const {
      'android',
      'windows',
      'macos',
    }.contains(ref.read(appUpdatePlatformProvider))) {
      await checkAppUpdate(showPrompt: false);
      return;
    }
    if (!ref.read(appSettingProvider).autoCheckUpdate) return;
    await checkAppUpdate();
  }

  Future<void> checkAppUpdate({bool isUser = false, bool showPrompt = true}) {
    if (!showPrompt && !isUser) {
      return ref
          .read(appUpdateProvider.notifier)
          .check(forceRefresh: false)
          .then((_) {});
    }
    final running = _appUpdatePrompt;
    if (running != null) {
      if (isUser && !_manualAppUpdateRequested) {
        _manualAppUpdateRequested = true;
        if (!_appUpdateDialogVisible) {
          _appUpdateCheck = ref
              .read(appUpdateProvider.notifier)
              .check(forceRefresh: true);
        }
      }
      return running;
    }
    final completer = Completer<void>();
    _appUpdatePrompt = completer.future;
    _manualAppUpdateRequested = isUser;
    _appUpdateCheck = ref
        .read(appUpdateProvider.notifier)
        .check(forceRefresh: isUser);
    unawaited(
      _checkAndPromptAppUpdate().then(
        (_) {
          _appUpdatePrompt = null;
          _manualAppUpdateRequested = false;
          _appUpdateCheck = null;
          _appUpdateDialogVisible = false;
          completer.complete();
        },
        onError: (Object error, StackTrace stackTrace) {
          _appUpdatePrompt = null;
          _manualAppUpdateRequested = false;
          _appUpdateCheck = null;
          _appUpdateDialogVisible = false;
          completer.completeError(error, stackTrace);
        },
      ),
    );
    return completer.future;
  }

  Future<void> _checkAndPromptAppUpdate() async {
    try {
      var checking = _appUpdateCheck;
      var result = await _latestAppUpdateResult();
      while (ref.mounted && !identical(checking, _appUpdateCheck)) {
        checking = _appUpdateCheck;
        result = await _latestAppUpdateResult();
      }
      if (!ref.mounted || result == null) return;
      if (result.status != AppUpdateStatus.available) {
        if (_manualAppUpdateRequested) {
          await _showAppUpdateMessage(switch (result.status) {
            AppUpdateStatus.upToDate =>
              currentAppLocalizations.checkUpdateError,
            AppUpdateStatus.unavailable =>
              currentAppLocalizations.appUpdateUnavailable,
            _ => currentAppLocalizations.appUpdateFailed,
          });
        }
        return;
      }
      final release = result.release!;
      final service = ref.read(appUpdateServiceProvider);
      if (!_manualAppUpdateRequested &&
          (!ApiHealthService.automaticRequestsAvailable ||
              globalState.isOfflineMode)) {
        return;
      }
      final context = globalState.navigatorKey.currentContext;
      if (context == null || !context.mounted) return;
      final currentVersion = ref.read(appUpdateCurrentVersionProvider) ?? '';
      _appUpdateDialogVisible = true;
      final decision = await showAppUpdateDialog(
        context: context,
        release: release,
        currentVersion: currentVersion.split('+').first,
      ).whenComplete(() => _appUpdateDialogVisible = false);
      if (!ref.mounted || !context.mounted) return;
      switch (decision) {
        case AppUpdateDecision.update:
          if (const {
            'android',
            'windows',
            'macos',
          }.contains(ref.read(appUpdatePlatformProvider))) {
            await showAppUpdateDownloadDialog(
              context: context,
              release: release,
            );
          } else {
            final opened = await launchUrl(
              release.downloadUri,
              mode: LaunchMode.externalApplication,
            );
            if (!opened && ref.mounted) {
              await _showAppUpdateMessage(
                currentAppLocalizations.appUpdateOpenFailed,
              );
            }
          }
        case AppUpdateDecision.ignoreVersion:
          await service.ignore(release);
        case AppUpdateDecision.later:
        case null:
          break;
      }
    } catch (error, stackTrace) {
      commonPrint.log(
        'check app update action failed: $error, $stackTrace',
        logLevel: LogLevel.warning,
      );
      if (ref.mounted && _manualAppUpdateRequested) {
        await _showAppUpdateMessage(currentAppLocalizations.appUpdateFailed);
      }
    }
  }

  Future<AppUpdateState?> _latestAppUpdateResult() async {
    while (ref.mounted) {
      final check = _appUpdateCheck!;
      final result = await check;
      if (!ref.mounted) return null;
      if (!identical(check, _appUpdateCheck)) continue;
      if (!_manualAppUpdateRequested &&
          result.status == AppUpdateStatus.available) {
        bool ignored;
        try {
          ignored = await ref
              .read(appUpdateServiceProvider)
              .isIgnored(result.release!);
        } catch (_) {
          if (!identical(check, _appUpdateCheck)) continue;
          rethrow;
        }
        if (!ref.mounted) return null;
        if (!identical(check, _appUpdateCheck)) continue;
        if (ignored && !_manualAppUpdateRequested) return null;
      }
      return result;
    }
    return null;
  }

  Future<void> _showAppUpdateMessage(String message) async {
    final context = globalState.navigatorKey.currentContext;
    if (context == null || !context.mounted) return;
    await globalState.showMessage(
      title: currentAppLocalizations.checkUpdate,
      message: TextSpan(text: message),
    );
  }
}

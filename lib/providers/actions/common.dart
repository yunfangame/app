part of '../action.dart';

@Riverpod(keepAlive: true)
class CommonAction extends _$CommonAction {
  Future<void>? _appUpdatePrompt;
  bool _manualAppUpdateRequested = false;

  @override
  void build() {}

  void toggleRunning() {
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
      return ref.read(appUpdateProvider.notifier).check().then((_) {});
    }
    final running = _appUpdatePrompt;
    if (running != null) {
      _manualAppUpdateRequested |= isUser;
      return running;
    }
    final completer = Completer<void>();
    _appUpdatePrompt = completer.future;
    _manualAppUpdateRequested = isUser;
    unawaited(
      _checkAndPromptAppUpdate().then(
        (_) {
          _appUpdatePrompt = null;
          _manualAppUpdateRequested = false;
          completer.complete();
        },
        onError: (Object error, StackTrace stackTrace) {
          _appUpdatePrompt = null;
          _manualAppUpdateRequested = false;
          completer.completeError(error, stackTrace);
        },
      ),
    );
    return completer.future;
  }

  Future<void> _checkAndPromptAppUpdate() async {
    try {
      final result = await ref.read(appUpdateProvider.notifier).check();
      if (!ref.mounted) return;
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
      if (!_manualAppUpdateRequested) {
        final ignored = await service.isIgnored(release);
        if (!ref.mounted || (ignored && !_manualAppUpdateRequested)) return;
      }
      final context = globalState.navigatorKey.currentContext;
      if (context == null || !context.mounted) return;
      final currentVersion = ref.read(appUpdateCurrentVersionProvider) ?? '';
      final decision = await showAppUpdateDialog(
        context: context,
        release: release,
        currentVersion: currentVersion.split('+').first,
      );
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

  Future<void> _showAppUpdateMessage(String message) async {
    final context = globalState.navigatorKey.currentContext;
    if (context == null || !context.mounted) return;
    await globalState.showMessage(
      title: currentAppLocalizations.checkUpdate,
      message: TextSpan(text: message),
    );
  }
}

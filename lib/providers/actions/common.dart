part of '../action.dart';

@Riverpod(keepAlive: true)
class CommonAction extends _$CommonAction {
  bool _checkingAppUpdate = false;

  @override
  void build() {}

  void toggleRunning() {
    final running = !ref.read(isStartProvider);
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
    ref.read(patchClashConfigProvider.notifier).update((state) {
      final index = Mode.values.indexWhere((item) => item == state.mode);
      if (index == -1) return state;
      final nextIndex = index + 1 > Mode.values.length - 1 ? 0 : index + 1;
      return state.copyWith(mode: Mode.values[nextIndex]);
    });
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
    if (!ref.read(appSettingProvider).autoCheckUpdate) return;
    await checkAppUpdate();
  }

  Future<void> checkAppUpdate({bool isUser = false}) async {
    if (_checkingAppUpdate) return;
    _checkingAppUpdate = true;
    try {
      final packageInfo = globalState.packageInfo;
      final currentVersion = packageInfo.buildNumber.trim().isEmpty
          ? packageInfo.version
          : '${packageInfo.version}+${packageInfo.buildNumber}';
      final release = await appUpdateService.checkForUpdate(
        currentVersion: currentVersion,
        respectIgnored: !isUser,
      );
      if (release == null) {
        if (isUser) {
          await globalState.showMessage(
            title: currentAppLocalizations.checkUpdate,
            message: TextSpan(text: currentAppLocalizations.checkUpdateError),
          );
        }
        return;
      }
      final context = globalState.navigatorKey.currentContext;
      if (context == null || !context.mounted) return;
      final decision = await showAppUpdateDialog(
        context: context,
        release: release,
        currentVersion: currentVersion,
      );
      switch (decision) {
        case AppUpdateDecision.update:
          await launchUrl(
            release.downloadUri,
            mode: LaunchMode.externalApplication,
          );
        case AppUpdateDecision.ignoreVersion:
          await appUpdateService.ignore(release);
        case AppUpdateDecision.later:
        case null:
          break;
      }
    } catch (error, stackTrace) {
      commonPrint.log(
        'check app update failed: $error, $stackTrace',
        logLevel: LogLevel.warning,
      );
      if (isUser) {
        await globalState.showMessage(
          title: currentAppLocalizations.checkUpdate,
          message: TextSpan(text: currentAppLocalizations.requestFailed),
        );
      }
    } finally {
      _checkingAppUpdate = false;
    }
  }
}

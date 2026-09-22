part of '../action.dart';

@Riverpod(keepAlive: true)
class SystemAction extends _$SystemAction {
  SystemExitCoordinator? _exitCoordinator;
  final _trayScheduler = SerialTaskScheduler();

  @override
  void build() {}

  Future<List<Package>> getPackages() async {
    if (ref.read(isMobileViewProvider)) {
      await Future.delayed(commonDuration);
    }
    final packages = await app?.getPackages() ?? <Package>[];
    if (ref.mounted) {
      ref.read(packagesProvider.notifier).value = packages;
    }
    return packages;
  }

  Future<void> handleExit([bool needSave = false]) {
    final coordinator = _exitCoordinator ??= SystemExitCoordinator(
      watchdogDuration: exitWatchdogDuration,
      closeWindow: closeWindow,
      closeCore: closeCore,
      exitApplication: exitApplication,
    );
    return coordinator.exit(cleanup: () => cleanupExitResources(needSave));
  }

  Future<void> handleLogout() async {
    await Future.wait([stopRunningForLogout(), cleanupLogoutIntegrations()]);
  }

  @protected
  Future<void> stopRunningForLogout() {
    return ref.read(setupActionProvider.notifier).setRunning(false);
  }

  @protected
  Future<void> cleanupLogoutIntegrations() async {
    await Future.wait([
      if (systemDnsCoordinator != null) systemDnsCoordinator!.sync(false),
      cleanupSystemProxy('logout'),
      hideTray(),
    ]);
  }

  @protected
  Future<void> cleanupSystemProxy(String reason) async {
    final proxyService = proxy;
    if (proxyService == null) return;
    final port = ref.read(patchClashConfigProvider).mixedPort;
    final result = await proxyService.stopProxyDetailed(
      expectedPort: system.isWindows || system.isMacOS ? port : null,
    );
    commonPrint.event(
      'system_proxy.cleanup.completed',
      fields: {'reason': reason, ...result.toDiagnosticFields()},
    );
    if (!result.success) {
      throw StateError('system proxy cleanup failed: ${result.diagnosticCode}');
    }
  }

  @protected
  Duration get exitWatchdogDuration => const Duration(seconds: 3);

  @protected
  Future<void> cleanupExitResources(bool needSave) async {
    await Future.wait([
      if (needSave) preferences.saveConfig(ref.read(configProvider)),
      if (systemDnsCoordinator != null) systemDnsCoordinator!.shutdown(),
      cleanupSystemProxy('exit'),
      if (tray != null) tray!.destroy(),
    ]);
  }

  @protected
  Future<void> closeWindow() async {
    await window?.close();
  }

  @protected
  Future<void> closeCore() async {
    await coreController.close();
    commonPrint.log('exit');
  }

  @protected
  Future<void> exitApplication() {
    return system.exit();
  }

  Future<void> handleClose([bool exit = true]) async {
    if (ref.read(appSettingProvider).minimizeOnExit || !exit) {
      if (system.isDesktop) {
        await preferences.saveConfig(ref.read(configProvider));
      }
      await system.back();
    } else {
      await handleExit();
    }
  }

  Future<void> updateVisible() async {
    final visible = await window?.isVisible;
    if (visible != null && !visible) {
      window?.show();
    } else {
      window?.hide();
    }
  }

  void updateTun() {
    if (ref.read(windowsTunActivatingProvider)) return;
    final previous = ref.read(patchClashConfigProvider).tun.enable;
    final next = system.isWindows ? !ref.read(tunActiveProvider) : !previous;
    commonPrint.event(
      'tun.toggle.requested',
      fields: {'previous': previous, 'next': next},
    );
    if (system.isWindows && next) {
      unawaited(ref.read(setupActionProvider.notifier).enableWindowsTun());
      return;
    }
    ref
        .read(patchClashConfigProvider.notifier)
        .update((state) => state.copyWith.tun(enable: next));
  }

  void updateSystemProxy() {
    final previous = ref.read(networkSettingProvider).systemProxy;
    commonPrint.event(
      'system_proxy.toggle.requested',
      fields: {'previous': previous, 'next': !previous},
    );
    ref
        .read(networkSettingProvider.notifier)
        .update((state) => state.copyWith(systemProxy: !state.systemProxy));
  }

  @protected
  AutoLaunch? get autoLaunchService => autoLaunch;

  @protected
  Future<void> persistAutoLaunchPreference(bool enabled) async {
    debouncer.cancel(FunctionTag.savePreferences);
    final config = ref.read(configProvider);
    final saved = await preferences.saveConfig(
      config.copyWith(
        appSettingProps: config.appSettingProps.copyWith(autoLaunch: enabled),
      ),
    );
    if (!saved) throw const AutoLaunchException('persistenceFailed');
  }

  Future<void> refreshAutoLaunch() async {
    final service = autoLaunchService;
    if (service == null) throw const AutoLaunchException('unavailable');
    final enabled = await service.isEnable;
    if (!ref.mounted) return;
    ref
        .read(appSettingProvider.notifier)
        .update((state) => state.copyWith(autoLaunch: enabled));
  }

  Future<void> setAutoLaunch(bool enabled) async {
    final service = autoLaunchService;
    if (service == null) throw const AutoLaunchException('unavailable');
    try {
      await service.updateStatus(
        enabled,
        persist: (value) async {
          if (!ref.mounted) throw const AutoLaunchException('unavailable');
          await persistAutoLaunchPreference(value);
          if (!ref.mounted) return;
          ref
              .read(appSettingProvider.notifier)
              .update((state) => state.copyWith(autoLaunch: value));
        },
      );
      commonPrint.event('autostart.changed', fields: {'enabled': enabled});
    } on AutoLaunchException catch (error) {
      commonPrint.event(
        'autostart.failed',
        fields: {'code': error.code, 'requested_enabled': enabled},
      );
      if (error.code == 'rollbackFailed' && ref.mounted) {
        try {
          await refreshAutoLaunch();
        } catch (_) {}
      }
      rethrow;
    }
  }

  Future<void> updateAutoLaunch() async {
    try {
      final service = autoLaunchService;
      if (service == null) throw const AutoLaunchException('unavailable');
      await setAutoLaunch(!await service.isEnable);
    } catch (_) {
      globalState.showNotifier(currentAppLocalizations.autoLaunchFailed);
    }
  }

  @protected
  bool get hasAuthenticatedSession => globalState.xboardSession != null;

  @protected
  Future<void> destroyTray() async {
    await tray?.destroy();
  }

  @protected
  Future<void> renderTray() async {
    await tray?.update(
      trayState: ref.read(trayStateProvider),
      traffic: ref.read(
        trafficsProvider.select(
          (state) => state.list.safeLast(const Traffic()),
        ),
      ),
    );
  }

  Future<void> hideTray() {
    return _trayScheduler.run(destroyTray);
  }

  Future<void> updateTray() {
    final shouldRender = hasAuthenticatedSession;
    return _trayScheduler.run(shouldRender ? renderTray : destroyTray);
  }

  Future<void> updateLocalIp() async {
    ref.read(localIpProvider.notifier).value = null;
    await Future.delayed(commonDuration);
    ref.read(localIpProvider.notifier).value = await utils.getLocalIpAddress();
  }
}

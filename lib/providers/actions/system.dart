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
    if (ref.read(packagesProvider).isEmpty) {
      ref.read(packagesProvider.notifier).value =
          await app?.getPackages() ?? [];
    }
    return ref.read(packagesProvider);
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
      if (macOS != null) macOS!.updateDns(true),
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
      expectedPort: system.isWindows ? port : null,
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
      if (macOS != null) macOS!.updateDns(true),
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
    final previous = ref.read(patchClashConfigProvider).tun.enable;
    commonPrint.event(
      'tun.toggle.requested',
      fields: {'previous': previous, 'next': !previous},
    );
    ref
        .read(patchClashConfigProvider.notifier)
        .update((state) => state.copyWith.tun(enable: !state.tun.enable));
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

  void updateAutoLaunch() {
    ref
        .read(appSettingProvider.notifier)
        .update((state) => state.copyWith(autoLaunch: !state.autoLaunch));
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

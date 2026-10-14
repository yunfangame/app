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

  Future<void> handleExit([bool needSave = false]) async {
    ref
        .read(proxiesActionProvider.notifier)
        .cancelHongKongSelection(manual: true);
    final coordinator = _exitCoordinator ??= SystemExitCoordinator(
      watchdogDuration: exitWatchdogDuration,
      closeWindow: closeWindow,
      closeCore: closeCore,
      exitApplication: exitApplication,
      prepareExit: prepareExitResources,
      onPhase: (phase) =>
          commonPrint.event('app.exit.phase', fields: {'phase': phase}),
    );
    try {
      await coordinator.exit(cleanup: () => cleanupExitResources(needSave));
    } catch (error) {
      commonPrint.event(
        'app.exit.failed',
        fields: {
          'error_type': error.runtimeType.toString(),
          'exit_requested': coordinator.applicationExitRequested,
        },
      );
      if (coordinator.applicationExitRequested) rethrow;
      await commonPrint.flushDiagnosticEvents();
      await reportExitCleanupFailure();
      throw NetworkCleanupException(
        currentAppLocalizations.networkCleanupFailed,
      );
    }
  }

  @protected
  Future<void> reportExitCleanupFailure() async {
    try {
      await window?.show();
    } catch (error) {
      commonPrint.event(
        'app.exit.recovery_window.failed',
        fields: {'error_type': error.runtimeType.toString()},
      );
    }
    globalState.showNotifier(currentAppLocalizations.networkCleanupFailed);
  }

  Future<void> handleLogout() async {
    commonPrint.event('app.logout.cleanup.started');
    try {
      await Future.wait([stopRunningForLogout(), cleanupLogoutIntegrations()]);
      await repairResidualSystemProxy('logout');
      commonPrint.event('app.logout.cleanup.completed');
      await commonPrint.flushDiagnosticEvents();
    } catch (error) {
      commonPrint.event(
        'app.logout.cleanup.failed',
        fields: {'error_type': error.runtimeType.toString()},
      );
      await commonPrint.flushDiagnosticEvents();
      throw NetworkCleanupException(
        currentAppLocalizations.networkCleanupFailed,
      );
    }
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
    final queued = reason == 'exit' || reason == 'logout'
        ? await systemProxyCleanupSignal.shutdown(
            port,
            terminal: reason == 'exit',
          )
        : null;
    final result =
        queued ??
        await proxyService.stopProxyDetailed(
          expectedPort:
              (system.isWindows || system.isMacOS) && port >= 1 && port <= 65535
              ? port
              : null,
        );
    commonPrint.event(
      'system_proxy.cleanup.completed',
      fields: {'reason': reason, ...result.toDiagnosticFields()},
    );
    if (system.isWindows) {
      await commonPrint.flushDiagnosticEvents();
    }
    if (!result.success) {
      throw StateError('system proxy cleanup failed: ${result.diagnosticCode}');
    }
  }

  @protected
  Duration get exitWatchdogDuration => const Duration(seconds: 3);

  @protected
  Future<void> repairResidualSystemProxy(String reason) async {
    final proxyService = proxy;
    if (proxyService == null || (!system.isWindows && !system.isMacOS)) return;
    final port = ref.read(patchClashConfigProvider).mixedPort;
    if (port < 1 || port > 65535) return;
    final result = await proxyService.repairStaleProxyDetailed(port);
    commonPrint.event(
      'system_proxy.cleanup.residual_checked',
      fields: {'reason': reason, 'port': port, ...result.toDiagnosticFields()},
    );
    if (!result.success) {
      throw StateError(
        'system proxy residual cleanup failed: ${result.diagnosticCode}',
      );
    }
  }

  @protected
  Future<void> prepareExitResources() async {
    await Future.wait([
      stopRunningForExit(),
      restoreDnsForExit(),
      cleanupSystemProxy('exit'),
    ]);
    if (system.isDesktop &&
        ref.read(coreStatusProvider) != CoreStatus.connected) {
      await closeCore();
    }
    await repairResidualSystemProxy('exit');
  }

  @protected
  Future<void> stopRunningForExit() {
    if (system.isDesktop &&
        ref.read(coreStatusProvider) != CoreStatus.connected) {
      return Future.value();
    }
    return ref.read(setupActionProvider.notifier).setRunning(false);
  }

  @protected
  Future<void> restoreDnsForExit() async {
    await systemDnsCoordinator?.shutdown();
  }

  @protected
  Future<void> cleanupExitResources(bool needSave) async {
    await Future.wait([
      if (needSave) preferences.saveConfig(ref.read(configProvider)),
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
  Future<void> exitApplication() async {
    commonPrint.event('app.exit.process_exit');
    await commonPrint.flushDiagnosticEvents();
    await system.exit();
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

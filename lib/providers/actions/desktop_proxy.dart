part of '../action.dart';

@Riverpod(keepAlive: true)
class DesktopProxyAction extends _$DesktopProxyAction {
  bool _showingFailure = false;
  VoidCallback? _closeDialog;

  @override
  void build() {
    ref.onDispose(() => _closeDialog?.call());
    ref.listen(isStartProvider, (_, _) => _closeDialog?.call());
    ref.listen(connectionPendingProvider, (_, _) => _closeDialog?.call());
    ref.listen(currentProfileIdProvider, (_, _) => _closeDialog?.call());
    ref.listen(
      patchClashConfigProvider.select((state) => state.mixedPort),
      (_, _) => _closeDialog?.call(),
    );
  }

  Set<int> get _reservedPorts {
    final config = ref.read(patchClashConfigProvider);
    return {config.port, config.socksPort, config.redirPort, config.tproxyPort}
      ..remove(0);
  }

  Future<T?> _present<T>(Widget child) async {
    final context = globalState.navigatorKey.currentContext;
    if (context == null || !ref.mounted) return null;
    final navigator = Navigator.of(context);
    final route = DialogRoute<T>(context: context, builder: (_) => child);
    void close() {
      if (navigator.mounted && route.isActive) navigator.removeRoute(route);
    }

    _closeDialog = close;
    try {
      return await navigator.push(route);
    } finally {
      if (identical(_closeDialog, close)) _closeDialog = null;
    }
  }

  @protected
  Future<DesktopProxyFailureChoice?> chooseFailureAction(
    DesktopProxyFailure failure,
  ) => _present(DesktopProxyFailureDialog(failure: failure));

  @protected
  Future<int?> choosePort(int currentPort) => _present(
    DesktopProxyPortDialog(
      currentPort: currentPort,
      reservedPorts: _reservedPorts,
    ),
  );

  Future<void> reportFailure(DesktopProxyFailure failure) async {
    if (!ref.mounted ||
        _showingFailure ||
        failure.port != ref.read(patchClashConfigProvider).mixedPort) {
      return;
    }
    final setup = ref.read(setupActionProvider.notifier);
    final request = setup._latestRunRequest;
    final profile = ref.read(currentProfileIdProvider);
    bool current() =>
        ref.mounted &&
        identical(request, setup._latestRunRequest) &&
        profile == ref.read(currentProfileIdProvider) &&
        failure.port == ref.read(patchClashConfigProvider).mixedPort;
    DesktopProxyFailureChoice? choice;
    int? port;
    _showingFailure = true;
    try {
      choice = await chooseFailureAction(failure);
      if (!current()) return;
      if (choice == DesktopProxyFailureChoice.changePort) {
        port = await choosePort(failure.port);
        if (!current() || port == null) return;
      }
    } finally {
      _showingFailure = false;
    }
    if (!current()) return;
    try {
      if (choice == DesktopProxyFailureChoice.logs) {
        await ref.read(logsProvider.notifier).exportLogs();
      } else if (choice == DesktopProxyFailureChoice.retry || port != null) {
        await reconnect(port: port);
      }
    } catch (error) {
      commonPrint.event(
        'system_proxy.recovery.failed',
        fields: {
          'port': port ?? failure.port,
          'error_type': error.runtimeType.toString(),
        },
      );
      if (ref.mounted) {
        unawaited(
          reportFailure(
            DesktopProxyFailure.fromError(
              error,
              port: ref.read(patchClashConfigProvider).mixedPort,
            ),
          ),
        );
      }
    }
  }

  @protected
  Future<void> clearPreviousSystemProxy({
    required bool Function() isCurrent,
  }) async {
    if (!isCurrent()) return;
    final cleared = await systemProxyCleanupSignal.request(
      ref.read(patchClashConfigProvider).mixedPort,
      isCancelled: () => !isCurrent(),
    );
    if (!cleared && isCurrent()) {
      throw StateError('proxy_cleanup_failed');
    }
  }

  @protected
  Future<bool> persistPort(Config config) => preferences.saveConfig(config);

  Future<void> reconnect({int? port}) async {
    if (!system.isDesktop) return;
    final previous = ref.read(patchClashConfigProvider).mixedPort;
    if (port != null &&
        (port < 1024 || port > 49151 || _reservedPorts.contains(port))) {
      throw ArgumentError.value(port, 'port');
    }
    final setup = ref.read(setupActionProvider.notifier);
    final profile = ref.read(currentProfileIdProvider);
    final stop = setup.setRunning(false);
    final request = setup._latestRunRequest;
    bool current() =>
        ref.mounted &&
        identical(request, setup._latestRunRequest) &&
        !ref.read(isStartProvider) &&
        !ref.read(connectionPendingProvider) &&
        profile == ref.read(currentProfileIdProvider) &&
        previous == ref.read(patchClashConfigProvider).mixedPort;
    try {
      await stop;
      if (!current()) return;
      await clearPreviousSystemProxy(isCurrent: current);
      if (!current()) return;
      if (port != null && port != previous) {
        final config = ref.read(configProvider);
        final patch = config.patchClashConfig.copyWith(mixedPort: port);
        debouncer.cancel(FunctionTag.savePreferences);
        if (!await persistPort(config.copyWith(patchClashConfig: patch))) {
          throw StateError('proxy_port_save_failed');
        }
        if (!current()) {
          if (ref.mounted && !await persistPort(ref.read(configProvider))) {
            throw StateError('proxy_port_restore_failed');
          }
          return;
        }
        ref
            .read(patchClashConfigProvider.notifier)
            .update((state) => state.copyWith(mixedPort: port));
        commonPrint.event(
          'system_proxy.port.changed',
          fields: {'previous_port': previous, 'port': port},
        );
      }
    } catch (error) {
      if (!current()) {
        commonPrint.event(
          'system_proxy.recovery.superseded',
          fields: {
            'port': previous,
            'error_type': error.runtimeType.toString(),
          },
        );
        return;
      }
      rethrow;
    }
    ref
        .read(networkSettingProvider.notifier)
        .update((state) => state.copyWith(systemProxy: true));
    await setup.setRunning(true, initialize: !ref.read(initProvider));
  }
}

part of '../action.dart';

enum _SetupTaskResult { completed, handoffToCoreRestart }

class _RunRequest {
  final bool running;
  final bool initialize;

  const _RunRequest({required this.running, required this.initialize});
}

@Riverpod(keepAlive: true)
class SetupAction extends _$SetupAction {
  Timer? _runtimeTimer;
  final _setupScheduler = SerialTaskScheduler();
  final _listenerScheduler = SerialTaskScheduler();
  _RunRequest? _latestRunRequest;
  bool? _lastPhysicalNetworkAvailable;
  int _physicalNetworkRecoveryRevision = 0;
  DateTime? _startTime;
  int? _appliedRuleProfileId;
  String? _appliedRuleTarget;

  String? get ruleSelectionGroup =>
      ref.read(currentProfileIdProvider) == _appliedRuleProfileId
      ? _appliedRuleTarget
      : null;

  bool get _isRunning => _startTime != null && _startTime!.isBeforeNow;

  @override
  void build() {
    ref.onDispose(() {
      _runtimeTimer?.cancel();
      _physicalNetworkRecoveryRevision++;
    });
  }

  @protected
  bool get requiresListenerReadiness => system.isWindows;

  SetupParams get _setupParams {
    final settings = ref.read(appSettingProvider);
    final selectedMap = Map<String, String>.from(ref.read(selectedMapProvider));
    final mode = ref.read(patchClashConfigProvider).mode;
    if (activeChainProxy(settings) != null && mode == Mode.global) {
      final current = selectedMap[GroupName.GLOBAL.name];
      if (current?.isNotEmpty == true && current != chainProxyRuntimeName) {
        selectedMap[GroupName.GLOBAL.name] = chainProxyRuntimeName;
      }
    }
    final testUrl = settings.testUrl;
    return SetupParams(selectedMap: selectedMap, testUrl: testUrl);
  }

  void fullSetup() {
    if (!ref.read(initProvider)) return;
    ref.read(delayDataSourceProvider.notifier).value = {};
    ref.read(connectionDelayDataSourceProvider.notifier).value = {};
    unawaited(_runSetup(force: true));
    ref.read(requestsProvider.notifier).value = FixedList(500);
  }

  void _setLocalRunning(bool running) {
    _runtimeTimer?.cancel();
    _runtimeTimer = null;
    if (!running) {
      _startTime = null;
      debouncer.cancel(FunctionTag.applyProfile);
      _updateRunTime();
      return;
    }

    _startTime ??= DateTime.now();
    _refreshRunningState();
    _runtimeTimer = Timer.periodic(
      const Duration(seconds: 1),
      (_) => _refreshRunningState(),
    );
  }

  void _refreshRunningState() {
    _updateRunTime();
    unawaited(ref.read(commonActionProvider.notifier).updateTraffic());
  }

  void _updateRunTime() {
    final startTime = _startTime;
    ref.read(runTimeProvider.notifier).value = startTime == null
        ? null
        : DateTime.now().millisecondsSinceEpoch -
              startTime.millisecondsSinceEpoch;
  }

  Future<void> _updateStartTime() async {
    _startTime = await service?.getRunTime();
  }

  Future<void> initStatus() async {
    if (!globalState.needInitStatus) {
      commonPrint.log('init status cancel');
      return;
    }
    commonPrint.log('init status');
    if (system.isAndroid) {
      await _updateStartTime();
    }
    final shouldRun = _isRunning || ref.read(appSettingProvider).autoRun;
    if (shouldRun) {
      await setRunning(true, initialize: true);
    } else {
      await applyProfile(force: true);
    }
  }

  Future<void> setRunning(bool running, {bool initialize = false}) {
    _physicalNetworkRecoveryRevision++;
    if (!initialize) {
      ref
          .read(proxiesActionProvider.notifier)
          .cancelHongKongSelection(manual: true);
    }
    if (running && !initialize && !ref.read(initProvider)) {
      return Future.value();
    }

    final request = _RunRequest(
      running: running,
      initialize: running && initialize,
    );
    final patchConfig = ref.read(patchClashConfigProvider);
    commonPrint.event(
      'connection.requested',
      fields: {
        'running': running,
        'initialize': request.initialize,
        'has_profile': ref.read(currentProfileIdProvider) != null,
        'system_proxy_requested': ref.read(networkSettingProvider).systemProxy,
        'tun_requested': patchConfig.tun.enable,
        'mode': patchConfig.mode.name,
      },
    );
    _latestRunRequest = request;
    ref.read(connectionPendingProvider.notifier).value =
        running && requiresListenerReadiness;
    _setLocalRunning(running && !requiresListenerReadiness);
    if (request.initialize) {
      globalState.needInitStatus = false;
    }
    return running
        ? requiresListenerReadiness
              ? _startVerified(request)
              : _start(request)
        : _stop(request);
  }

  @protected
  Future<void> prepareListenerProfile() {
    return _runSetup(force: true, silence: true, propagateErrors: true);
  }

  @protected
  Future<void> verifyLocalListener(
    int port, {
    required bool Function() isCancelled,
  }) async {
    final guard = WindowsProxyGuard(
      inspector: (port) => proxy!.inspectProxy(port),
      stopper: (port) => proxy!.stopProxyDetailed(expectedPort: port),
    );
    final result = await guard.waitUntilReadyDetailed(
      port,
      isCancelled: isCancelled,
    );
    commonPrint.event(
      'connection.listener.readiness',
      fields: result.toDiagnosticData(),
    );
    if (!result.ready && !isCancelled()) {
      throw CoreMethodException(
        code: 'local_port_unavailable',
        message: 'Local proxy endpoint is unavailable',
        details: result.toDiagnosticData(),
      );
    }
  }

  Future<void> _startVerified(_RunRequest request) async {
    try {
      for (var attempt = 0; attempt < 3; attempt++) {
        if (!_isCurrent(request)) return;
        if (await _pauseIfSuspended(request)) return;
        if (!_isCurrent(request)) return;
        final config = ref.read(patchClashConfigProvider);
        final port = config.mixedPort;
        await prepareListenerProfile();
        if (!_isCurrent(request)) return;
        if (await _pauseIfSuspended(request)) return;
        if (!_isCurrent(request)) return;
        if (config != ref.read(patchClashConfigProvider)) continue;
        await _setCoreRunning(request);
        if (!_isCurrent(request)) return;
        if (await _pauseIfSuspended(request)) return;
        if (!_isCurrent(request)) return;
        if (config != ref.read(patchClashConfigProvider)) continue;
        final tunOnly =
            port == 0 &&
            !ref.read(networkSettingProvider).systemProxy &&
            config.tun.enable &&
            ref.read(authorizedTunEnableProvider) ==
                TunAuthorizationState.authorized;
        if (!tunOnly) {
          await verifyLocalListener(
            port,
            isCancelled: () =>
                !_isCurrent(request) ||
                ref.read(suspendProvider) ||
                config != ref.read(patchClashConfigProvider),
          );
        }
        if (!_isCurrent(request)) return;
        if (await _pauseIfSuspended(request)) return;
        if (!_isCurrent(request)) return;
        if (config != ref.read(patchClashConfigProvider)) continue;
        ref.read(connectionPendingProvider.notifier).value = false;
        _setLocalRunning(true);
        commonPrint.event('connection.ready', fields: {'port': port});
        return;
      }
      throw StateError('Listener configuration changed during startup');
    } catch (error) {
      await _failConnection(request, error);
    }
  }

  Future<bool> _pauseIfSuspended(_RunRequest request) async {
    if (!ref.read(suspendProvider)) return false;
    await _listenerScheduler.run(() async {
      if (!_isCurrent(request) || !ref.read(suspendProvider)) return;
      await setCoreRunning(false);
      commonPrint.event(
        'connection.suspended',
        fields: {'reason': 'excluded_ssid'},
      );
    });
    return true;
  }

  Future<void> refreshSuspension() async {
    final request = _latestRunRequest;
    if (!requiresListenerReadiness || request?.running != true) return;
    await setRunning(true, initialize: request!.initialize);
  }

  @protected
  void notifyListenerFailure(int port) {
    globalState.showNotifier(
      currentAppLocalizations.listenerStartFailed(port, 'W-PORT-02'),
    );
  }

  Future<void> _failConnection(_RunRequest request, Object error) async {
    if (!_isCurrent(request)) return;
    final port = ref.read(patchClashConfigProvider).mixedPort;
    commonPrint.event(
      'connection.failed',
      fields: {
        'port': port,
        'error_type': error.runtimeType.toString(),
        if (error is CoreMethodException) ...{
          'error_code': error.code,
          'details': error.details,
        },
      },
    );
    final settings = ref.read(networkSettingProvider);
    if (settings.systemProxy) {
      ref.read(networkSettingProvider.notifier).value = settings.copyWith(
        systemProxy: false,
      );
    }
    notifyListenerFailure(port);
    try {
      await setRunning(false);
    } catch (stopError) {
      commonPrint.event(
        'connection.failure_cleanup.failed',
        fields: {'error_type': stopError.runtimeType.toString()},
      );
    }
  }

  Future<void> _start(_RunRequest request) async {
    if (request.initialize) {
      try {
        await applyProfile(
          force: true,
          preloadInvoke: () => _setCoreRunning(request),
        );
      } catch (_) {
        if (_isCurrent(request)) {
          await setRunning(false);
        }
      }
      return;
    }

    await _setCoreRunning(request);
    if (_isCurrent(request)) {
      applyProfileDebounce(force: true, silence: true);
    }
  }

  Future<void> _stop(_RunRequest request) async {
    final watch = Stopwatch()..start();
    commonPrint.event(
      'connection.cleanup.started',
      fields: {
        'reason': 'connection_stop',
        'strategy': 'core_listener_stop',
        'separate_close_requested': false,
      },
    );
    try {
      await _setCoreRunning(request);
    } catch (error) {
      commonPrint.event(
        'connection.cleanup.failed',
        fields: {
          'reason': 'connection_stop',
          'strategy': 'core_listener_stop',
          'elapsed_ms': watch.elapsedMilliseconds,
          'error_type': error.runtimeType.toString(),
        },
      );
      rethrow;
    }
    if (!_isCurrent(request)) {
      commonPrint.event(
        'connection.cleanup.superseded',
        fields: {
          'reason': 'connection_stop',
          'strategy': 'core_listener_stop',
          'elapsed_ms': watch.elapsedMilliseconds,
        },
      );
      return;
    }
    commonPrint.event(
      'connection.cleanup.completed',
      fields: {
        'reason': 'connection_stop',
        'strategy': 'core_listener_stop',
        'elapsed_ms': watch.elapsedMilliseconds,
      },
    );
    resetCoreTraffic();
    ref.read(trafficsProvider.notifier).clear();
    ref.read(totalTrafficProvider.notifier).value = const Traffic();
    ref.read(checkIpNumProvider.notifier).add();
  }

  Future<void> _setCoreRunning(_RunRequest request) {
    return _listenerScheduler.run(() async {
      if (!_isCurrent(request)) {
        commonPrint.event(
          'connection.core_transition.skipped',
          fields: {'running': request.running, 'reason': 'stale_request'},
        );
        return;
      }
      if (request.running && ref.read(suspendProvider)) {
        commonPrint.event(
          'connection.core_transition.skipped',
          fields: {'running': request.running, 'reason': 'suspended'},
        );
        return;
      }
      try {
        final succeeded = await setCoreRunning(request.running);
        commonPrint.event(
          'connection.core_transition.completed',
          fields: {'running': request.running, 'success': succeeded},
        );
        if (!succeeded && request.running && requiresListenerReadiness) {
          throw StateError('Core listener did not start');
        }
      } catch (error) {
        commonPrint.event(
          'connection.core_transition.failed',
          fields: {
            'running': request.running,
            'error_type': error.runtimeType.toString(),
            'error': '$error',
          },
        );
        rethrow;
      }
    });
  }

  bool _isCurrent(_RunRequest request) =>
      ref.mounted && identical(_latestRunRequest, request);

  Future<void> updateConfigDebounce() async {
    debouncer.call(FunctionTag.updateConfig, updateConfig);
  }

  @protected
  Future<bool> setCoreRunning(bool running) {
    return running
        ? coreController.startListener()
        : coreController.stopListener();
  }

  @protected
  void resetCoreTraffic() {
    coreController.resetTraffic();
  }

  @protected
  Future<void> resetResolverConnections() {
    return coreController.resetConnections();
  }

  @protected
  Future<void> closeTrackedConnectionsForNetworkRecovery() {
    return coreController.closeConnections();
  }

  @protected
  Future<void> waitForPhysicalNetworkRecovery() {
    return Future<void>.delayed(const Duration(milliseconds: 800));
  }

  @protected
  Future<NetworkDiagnosticReport> runPhysicalNetworkRecoveryDiagnostic() {
    return ref.read(logsProvider.notifier).runNetworkDiagnostics();
  }

  String _selectedMapSignature(int? profileId) {
    if (profileId == null) return '[]';
    final entries = ref.read(selectedMapProvider).entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    return jsonEncode(
      entries.map((entry) => [entry.key, entry.value]).toList(),
    );
  }

  String? _physicalNetworkRecoverySkipReason({
    required _RunRequest? request,
    required int revision,
    required bool Function() isConfigurationCurrent,
  }) {
    if (!ref.mounted) return 'provider_disposed';
    if (revision != _physicalNetworkRecoveryRevision) {
      return 'newer_network_or_connection_event';
    }
    if (_lastPhysicalNetworkAvailable != true) {
      return 'physical_network_unavailable';
    }
    if (request == null || !_isCurrent(request) || !request.running) {
      return 'connection_request_changed';
    }
    if (!isConfigurationCurrent()) return 'configuration_changed';
    if (!ref.read(isStartProvider)) return 'proxy_not_running';
    if (ref.read(connectionPendingProvider)) return 'connection_pending';
    if (ref.read(suspendProvider)) return 'connection_suspended';
    if (ref.read(coreStatusProvider) != CoreStatus.connected) {
      return 'core_not_connected';
    }
    return null;
  }

  void _logPhysicalNetworkRecoverySkipped(String reason) {
    commonPrint.event(
      'network.recovery.skipped',
      fields: {
        'reason': 'physical_network_restored',
        'strategy': 'diagnose_close_reset',
        'skip_reason': reason,
      },
    );
  }

  Future<void> handlePhysicalNetworkAvailability(bool available) async {
    final previous = _lastPhysicalNetworkAvailable;
    if (previous == available) return;
    _lastPhysicalNetworkAvailable = available;
    final revision = ++_physicalNetworkRecoveryRevision;
    commonPrint.event(
      'network.physical_availability.changed',
      fields: {'available': available, 'previous': previous},
    );
    if (!available || previous != false) return;

    final request = _latestRunRequest;
    final profileId = ref.read(currentProfileIdProvider);
    final config = ref.read(patchClashConfigProvider);
    final networkSettings = ref.read(networkSettingProvider);
    final selectedMapSignature = _selectedMapSignature(profileId);
    bool configurationCurrent() =>
        ref.read(currentProfileIdProvider) == profileId &&
        ref.read(patchClashConfigProvider) == config &&
        ref.read(networkSettingProvider) == networkSettings &&
        _selectedMapSignature(profileId) == selectedMapSignature;

    var skipReason = _physicalNetworkRecoverySkipReason(
      request: request,
      revision: revision,
      isConfigurationCurrent: configurationCurrent,
    );
    if (skipReason != null) {
      _logPhysicalNetworkRecoverySkipped(skipReason);
      return;
    }

    try {
      await waitForPhysicalNetworkRecovery();
    } catch (error) {
      commonPrint.event(
        'network.recovery.failed',
        fields: {
          'reason': 'physical_network_restored',
          'strategy': 'settle_delay',
          'error_type': error.runtimeType.toString(),
        },
      );
      return;
    }

    skipReason = _physicalNetworkRecoverySkipReason(
      request: request,
      revision: revision,
      isConfigurationCurrent: configurationCurrent,
    );
    if (skipReason != null) {
      _logPhysicalNetworkRecoverySkipped(skipReason);
      return;
    }

    final watch = Stopwatch()..start();
    commonPrint.event(
      'network.recovery.diagnostic.started',
      fields: {
        'reason': 'physical_network_restored',
        'required_code': 'W-NET-OK',
      },
    );
    late final NetworkDiagnosticReport report;
    try {
      report = await runPhysicalNetworkRecoveryDiagnostic();
    } catch (error) {
      commonPrint.event(
        'network.recovery.failed',
        fields: {
          'reason': 'physical_network_restored',
          'strategy': 'network_diagnostic',
          'elapsed_ms': watch.elapsedMilliseconds,
          'error_type': error.runtimeType.toString(),
        },
      );
      return;
    }

    skipReason = _physicalNetworkRecoverySkipReason(
      request: request,
      revision: revision,
      isConfigurationCurrent: configurationCurrent,
    );
    if (skipReason != null) {
      _logPhysicalNetworkRecoverySkipped(skipReason);
      return;
    }
    if (!report.success) {
      _logPhysicalNetworkRecoverySkipped(
        'diagnostic_${report.code.toLowerCase()}',
      );
      return;
    }

    var cleanupStarted = false;
    var closeSucceeded = false;
    var resolverResetSucceeded = false;
    await _listenerScheduler.run(() async {
      final serializedSkipReason = _physicalNetworkRecoverySkipReason(
        request: request,
        revision: revision,
        isConfigurationCurrent: configurationCurrent,
      );
      if (serializedSkipReason != null) {
        _logPhysicalNetworkRecoverySkipped(serializedSkipReason);
        return;
      }
      cleanupStarted = true;
      commonPrint.event(
        'network.recovery.cleanup.started',
        fields: {
          'reason': 'physical_network_restored',
          'strategy': 'close_then_resolver_reset',
          'diagnostic_code': report.code,
        },
      );
      try {
        await closeTrackedConnectionsForNetworkRecovery();
        closeSucceeded = true;
      } catch (error) {
        commonPrint.event(
          'network.recovery.connection_close.failed',
          fields: {'error_type': error.runtimeType.toString()},
        );
      }
      try {
        await resetResolverConnections();
        resolverResetSucceeded = true;
      } catch (error) {
        commonPrint.event(
          'network.recovery.resolver_reset.failed',
          fields: {'error_type': error.runtimeType.toString()},
        );
      }
    });
    if (!cleanupStarted) return;
    commonPrint.event(
      'network.recovery.cleanup.completed',
      fields: {
        'reason': 'physical_network_restored',
        'strategy': 'close_then_resolver_reset',
        'diagnostic_code': report.code,
        'close_succeeded': closeSucceeded,
        'resolver_reset_succeeded': resolverResetSucceeded,
        'elapsed_ms': watch.elapsedMilliseconds,
      },
    );
  }

  @visibleForTesting
  Future<void> updateConfig() async {
    final request = _latestRunRequest;
    await globalState.safeRun(() async {
      await _inspectSystemProxy('before_update');
      try {
        final updateParams = ref.read(updateParamsProvider);
        final shouldContinueSetup = await requestAdmin(updateParams.tun.enable);
        if (!ref.mounted || !identical(request, _latestRunRequest)) return;
        if (!shouldContinueSetup) {
          await _restartCoreAfterAuthorization();
          return;
        }
        final message = await applyCoreUpdate(
          updateParams.copyWith.tun(
            enable: _getEffectiveTunEnable(updateParams.tun.enable),
          ),
        );
        ref.read(checkIpNumProvider.notifier).add();
        if (message.isNotEmpty) throw message;
      } catch (error) {
        if (requiresListenerReadiness && request?.running == true) {
          await _failConnection(request!, error);
        } else {
          rethrow;
        }
      } finally {
        await _inspectSystemProxy('after_update');
      }
    });
  }

  @protected
  Future<String> applyCoreUpdate(UpdateParams params) {
    return coreController.updateConfig(params);
  }

  Future<void> _inspectSystemProxy(String phase) async {
    if (!system.isWindows || proxy == null) return;
    try {
      final config = ref.read(patchClashConfigProvider);
      final result = await proxy!.inspectProxy(config.mixedPort);
      commonPrint.event(
        'system_proxy.configuration_snapshot',
        fields: {
          'phase': phase,
          'tun_requested': config.tun.enable,
          'system_proxy_requested': ref
              .read(networkSettingProvider)
              .systemProxy,
          ...result.toDiagnosticFields(),
        },
      );
    } catch (error) {
      commonPrint.event(
        'system_proxy.configuration_snapshot.failed',
        fields: {'phase': phase, 'error_type': error.runtimeType.toString()},
      );
    }
  }

  void tryCheckIp() {
    final isTimeout = ref.read(
      networkDetectionProvider.select(
        (state) => state.ipInfo == null && state.isLoading == false,
      ),
    );
    if (!isTimeout) return;
    ref.read(checkIpNumProvider.notifier).add();
  }

  void applyProfileDebounce({bool silence = false, bool force = false}) {
    debouncer.call(FunctionTag.applyProfile, (silence, force) {
      applyProfile(silence: silence, force: force);
    }, args: [silence, force]);
  }

  void changeMode(Mode mode) {
    ref
        .read(proxiesActionProvider.notifier)
        .cancelHongKongSelection(manual: true);
    if (mode == Mode.global) {
      unawaited(_selectGlobalHongKong());
      return;
    }
    ref
        .read(patchClashConfigProvider.notifier)
        .update((state) => state.copyWith(mode: mode));
  }

  Future<void> _selectGlobalHongKong() async {
    final result = await ref
        .read(proxiesActionProvider.notifier)
        .selectHongKongForMode(Mode.global);
    if (!ref.mounted) return;
    switch (result) {
      case HongKongSelectionResult.unavailable:
        globalState.showNotifier(
          currentAppLocalizations.hongKongNodesUnavailable,
        );
      case HongKongSelectionResult.failed:
        globalState.showNotifier(
          currentAppLocalizations.hongKongSelectionFailed,
        );
      case HongKongSelectionResult.selected:
      case HongKongSelectionResult.cancelled:
        break;
    }
  }

  Future<bool> applySelectedProxyMode(
    Mode mode, {
    required bool Function() isCancelled,
    bool Function()? canRestore,
  }) {
    return _setupScheduler.run(() async {
      if (!ref.mounted || isCancelled()) return false;
      final params = ref.read(updateParamsProvider);
      Future<void> restoreMode() async {
        if (!ref.mounted || canRestore?.call() == false) return;
        final current = ref.read(updateParamsProvider);
        final restored = await applyCoreUpdate(
          current.copyWith.tun(
            enable: _getEffectiveTunEnable(current.tun.enable),
          ),
        );
        if (restored.isNotEmpty) {
          throw StateError('proxy_mode_restore_rejected');
        }
      }

      try {
        final message = await applyCoreUpdate(
          params.copyWith(
            mode: mode,
            tun: params.tun.copyWith(
              enable: _getEffectiveTunEnable(params.tun.enable),
            ),
          ),
        );
        if (message.isNotEmpty) throw StateError('proxy_mode_update_rejected');
        if (!ref.mounted) return false;
        if (isCancelled() || params != ref.read(updateParamsProvider)) {
          await restoreMode();
          return false;
        }
      } catch (error) {
        try {
          await restoreMode();
        } catch (restoreError) {
          commonPrint.event(
            'proxy.hong_kong_selection.mode_restore_failed',
            fields: {'error_type': restoreError.runtimeType.toString()},
          );
        }
        rethrow;
      }
      ref
          .read(patchClashConfigProvider.notifier)
          .update((state) => state.copyWith(mode: mode));
      return true;
    });
  }

  void autoApplyProfile() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      applyProfile();
    });
  }

  Future<void> applyProfile({
    bool silence = false,
    bool force = false,
    Future<void> Function()? preloadInvoke,
  }) {
    return _runSetup(
      force: force,
      silence: silence,
      preloadInvoke: preloadInvoke,
    );
  }

  Future<void> _runSetup({
    bool silence = false,
    bool force = false,
    Future<void> Function()? preloadInvoke,
    bool propagateErrors = false,
  }) async {
    final request = _latestRunRequest;
    try {
      final result = await _setupScheduler.run(() {
        return _setupConfig(
          force: force,
          silence: silence,
          preloadInvoke: preloadInvoke,
          onUpdated: () async {
            await ref.read(proxiesActionProvider.notifier).updateGroups();
            await ref.read(providersProvider.notifier).syncProviders();
          },
        );
      });
      if (result == _SetupTaskResult.handoffToCoreRestart) {
        await _restartCoreAfterAuthorization();
      }
    } catch (error) {
      if (!requiresListenerReadiness) rethrow;
      if (request?.running == true) {
        await _failConnection(request!, error);
      } else if (!propagateErrors) {
        notifyListenerFailure(ref.read(patchClashConfigProvider).mixedPort);
      }
      if (propagateErrors) rethrow;
    }
  }

  Future<void> _applyWithFeedback(
    Future<void> Function() apply, {
    required bool silence,
  }) async {
    if (!requiresListenerReadiness) {
      await globalState.loadingRun(
        apply,
        silence: true,
        tag: !silence ? LoadingTag.proxies : null,
      );
      return;
    }
    if (!silence) {
      ref.read(loadingProvider(LoadingTag.proxies).notifier).start();
    }
    try {
      await apply();
    } finally {
      if (!silence && ref.mounted) {
        unawaited(
          ref.read(loadingProvider(LoadingTag.proxies).notifier).stop(),
        );
      }
    }
  }

  Future<void> _restartCoreAfterAuthorization() async {
    try {
      await ref.read(coreActionProvider.notifier).restartCore();
    } catch (_) {
      ref.read(authorizedTunEnableProvider.notifier).value =
          TunAuthorizationState.none;
      rethrow;
    }
  }

  Future<VM2<String, String>> getProfile({
    required SetupState setupState,
    required PatchClashConfig patchConfig,
  }) async {
    final profileId = setupState.profileId;
    if (profileId == null) return const VM2('', '');
    final defaultUA = globalState.packageInfo.ua;
    final networkVM2 = ref.read(
      networkSettingProvider.select(
        (state) => VM2(state.appendSystemDns, state.routeMode),
      ),
    );
    final overrideDns = ref.read(overrideDnsProvider);
    final appSettings = ref.read(appSettingProvider);
    final appendSystemDns = networkVM2.a;
    final routeMode = networkVM2.b;
    final selectedMap = ref.read(selectedMapProvider);
    final chainProxyBypassDomains = ref
        .read(profilesProvider)
        .map((profile) => Uri.tryParse(profile.url)?.host ?? '')
        .where((host) => host.isNotEmpty)
        .toSet()
        .toList();
    final configMap = await coreController.getConfig(profileId);
    String? scriptContent;
    final List<Rule> addedRules = [];
    final List<ProxyGroup> proxyGroups = [];
    final List<Rule> rules = [];
    if (setupState.overwriteType == OverwriteType.script) {
      scriptContent = await setupState.script?.content;
    } else if (setupState.overwriteType == OverwriteType.standard) {
      addedRules.addAll(setupState.addedRules);
    } else {
      proxyGroups.addAll(setupState.proxyGroups);
      rules.addAll(setupState.rules);
    }
    final realPatchConfig = applyCampusNetworkConfig(
      patchConfig.copyWith(tun: patchConfig.tun.getRealTun(routeMode)),
      appSettings,
    );
    Map<String, dynamic> rawConfig = configMap;
    if (scriptContent?.isNotEmpty == true) {
      rawConfig = await handleEvaluate(scriptContent!, rawConfig);
    }
    final directory = await appPath.profilesPath;
    final res = makeRealProfileTask(
      MakeRealProfileState(
        rules: rules,
        proxyGroups: proxyGroups,
        profilesPath: directory,
        profileId: profileId,
        rawConfig: rawConfig,
        realPatchConfig: realPatchConfig,
        overrideDns: overrideDns || hasActiveCampusNetworkConfig(appSettings),
        appendSystemDns: appendSystemDns,
        addedRules: addedRules,
        defaultUA: defaultUA,
        chainProxy: activeChainProxy(appSettings),
        chainProxyGlobalTarget: selectedMap[GroupName.GLOBAL.name],
        chainProxyBypassDomains: chainProxyBypassDomains,
      ),
    );
    return res;
  }

  Future<String> getProfileWithId(int profileId) async {
    try {
      final setupState = await ref.read(setupStateProvider(profileId).future);
      final patchClashConfig = ref.read(patchClashConfigProvider);
      final res = await getProfile(
        setupState: setupState,
        patchConfig: patchClashConfig,
      );
      return res.a;
    } catch (e) {
      globalState.showNotifier(e.toString());
    }
    return '';
  }

  bool _getEffectiveTunEnable(bool enableTun) {
    final authorizationState = ref.read(authorizedTunEnableProvider);
    return enableTun && authorizationState == TunAuthorizationState.authorized;
  }

  @protected
  Future<AuthorizeCode> authorizeCore() {
    return system.authorizeCore();
  }

  @visibleForTesting
  Future<bool> requestAdmin(bool enableTun) async {
    if (!enableTun) {
      return true;
    }
    final authorizationState = ref.read(authorizedTunEnableProvider);
    if (authorizationState != TunAuthorizationState.none) {
      return true;
    }

    final authorizationNotifier = ref.read(
      authorizedTunEnableProvider.notifier,
    );
    authorizationNotifier.value = TunAuthorizationState.unauthorized;

    final code = await authorizeCore();
    commonPrint.event(
      'tun.authorization.completed',
      fields: {
        'platform': Platform.operatingSystem,
        'result': code.name,
        'tun_requested': enableTun,
      },
    );

    switch (code) {
      case AuthorizeCode.success:
        authorizationNotifier.value = TunAuthorizationState.authorized;
        return false;
      case AuthorizeCode.none:
        authorizationNotifier.value = TunAuthorizationState.authorized;
        return true;
      case AuthorizeCode.error:
        return true;
    }
  }

  Future<_SetupTaskResult> _setupConfig({
    bool force = false,
    bool silence = false,
    Future<void> Function()? preloadInvoke,
    FutureOr Function()? onUpdated,
  }) async {
    var profile = ref.read(currentProfileProvider);
    final nextProfile = await profile?.checkAndUpdateAndCopy();
    if (nextProfile != null) {
      profile = nextProfile;
      ref.read(profilesProvider.notifier).put(nextProfile);
    }
    commonPrint.log('setup ===> ${profile?.realLabel}');
    await _inspectSystemProxy('before_setup');
    final patchConfig = ref.read(patchClashConfigProvider);
    final shouldContinueSetup = await requestAdmin(patchConfig.tun.enable);
    if (!shouldContinueSetup) {
      return _SetupTaskResult.handoffToCoreRestart;
    }
    final effectiveTunEnable = _getEffectiveTunEnable(patchConfig.tun.enable);
    final realPatchConfig = patchConfig.copyWith.tun(
      enable: effectiveTunEnable,
    );
    commonPrint.event(
      'configuration.apply.started',
      fields: {
        'force': force,
        'has_profile': profile != null,
        'tun_requested': patchConfig.tun.enable,
        'tun_effective': effectiveTunEnable,
        'mode': patchConfig.mode.name,
      },
    );
    final setupState = await ref.read(setupStateProvider(profile?.id).future);
    final vm2 = await getProfile(
      setupState: setupState,
      patchConfig: realPatchConfig,
    );
    final yamlString = vm2.a;
    final yamlMd5 = vm2.b;
    if (yamlMd5 == globalState.lastConfigMd5 && force == false) {
      return _SetupTaskResult.completed;
    }
    if (system.isAndroid) {
      globalState.lastVpnState = ref.read(vpnStateProvider);
      final sharedState = ref.read(sharedStateProvider);
      await preferences.saveShareState(sharedState);
    }
    await _applyWithFeedback(() async {
      try {
        final configFilePath = await appPath.configFilePath;
        await File(configFilePath).safeWriteAsString(yamlString);
        final message = await coreController.setupConfig(
          params: _setupParams,
          preloadInvoke: preloadInvoke,
        );
        if (message.isNotEmpty && !message.endsWith('is empty')) {
          throw message;
        }
        globalState.lastConfigMd5 = yamlMd5;
        _appliedRuleProfileId = profile?.id;
        _appliedRuleTarget = defaultRuleTarget(yamlString);
        ref.read(checkIpNumProvider.notifier).add();
        await onUpdated?.call();
        commonPrint.event(
          'configuration.apply.succeeded',
          fields: {
            'has_profile': profile != null,
            'tun_effective': effectiveTunEnable,
          },
        );
      } catch (error) {
        commonPrint.event(
          'configuration.apply.failed',
          fields: {
            'error_type': error.runtimeType.toString(),
            'error': '$error',
            'tun_effective': effectiveTunEnable,
          },
        );
        rethrow;
      } finally {
        await _inspectSystemProxy('after_setup');
      }
    }, silence: silence);
    return _SetupTaskResult.completed;
  }
}

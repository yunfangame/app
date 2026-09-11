part of '../action.dart';

enum _SetupTaskResult { completed, handoffToCoreRestart }

enum _ActiveChainPostAction { none, restartTarget, restartOriginal, recover }

class _ActiveChainModeOutcome {
  const _ActiveChainModeOutcome(
    this.result, {
    this.postAction = _ActiveChainPostAction.none,
  });

  final ModeSwitchResult result;
  final _ActiveChainPostAction postAction;
}

enum AccessControlApplyResult { saved, reconnectRequested, superseded }

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
  final _accessControlScheduler = SerialTaskScheduler();
  final _modeRestartScheduler = SerialTaskScheduler();
  int _accessControlRevision = 0;
  bool _accessControlReconnectNeeded = false;
  AccessControlProps? _managedAccessControl;
  _RunRequest? _latestRunRequest;
  bool? _lastPhysicalNetworkAvailable;
  int _physicalNetworkRecoveryRevision = 0;
  int _modeChangeRevision = 0;
  Mode? _pendingMode;
  Future<ModeSwitchResult>? _pendingModeChange;
  String? _lastConfigurationFailureStage;
  DateTime? _startTime;
  int? _appliedRuleProfileId;
  String? _appliedRuleTarget;

  String? get ruleSelectionGroup =>
      ref.read(currentProfileIdProvider) == _appliedRuleProfileId
      ? _appliedRuleTarget
      : null;

  Mode get requestedMode =>
      _pendingMode ?? ref.read(patchClashConfigProvider).mode;

  bool get _isRunning => _startTime != null && _startTime!.isBeforeNow;

  bool get hasPendingAccessControlReconnect => _accessControlReconnectNeeded;

  bool consumeHandledAccessControlChange(VpnState? previous, VpnState next) {
    if (next.vpnProps.accessControlProps != _managedAccessControl) return false;
    _managedAccessControl = null;
    return previous != null &&
        previous.copyWith.vpnProps(
              accessControlProps: next.vpnProps.accessControlProps,
            ) ==
            next;
  }

  @protected
  bool get supportsAppAccessControl => system.isAndroid;

  @protected
  Future<bool> persistAccessControlConfig(Config config) {
    return preferences.saveConfig(config);
  }

  @protected
  Future<void> syncAccessControlState(SharedState state) async {
    await preferences.saveShareState(state);
    final error = await service?.syncState(state.needSyncSharedState);
    if (error == null || error.isNotEmpty) {
      throw StateError(error ?? 'Android VPN service is unavailable');
    }
  }

  @protected
  Future<bool> requestAccessControlRestart() async {
    return await service?.restart() ?? false;
  }

  Future<AccessControlApplyResult> applyAccessControl(
    AccessControlProps props,
  ) {
    if (!supportsAppAccessControl) {
      return Future.error(
        UnsupportedError('App access control requires Android'),
      );
    }
    final revision = ++_accessControlRevision;
    final runRequest = _latestRunRequest;
    final wasRunning = ref.read(isStartProvider);
    return _accessControlScheduler.run(() async {
      if (!ref.mounted || revision != _accessControlRevision) {
        return AccessControlApplyResult.superseded;
      }
      final previous = ref.read(vpnSettingProvider).accessControlProps;
      final next = props.copyWith(
        acceptList: props.acceptList.toSet().toList()..sort(),
        rejectList: props.rejectList.toSet().toList()..sort(),
      );
      final config = ref.read(configProvider);
      if (!await persistAccessControlConfig(
        config.copyWith.vpnProps(accessControlProps: next),
      )) {
        throw StateError('Unable to save app access control');
      }
      if (!ref.mounted) return AccessControlApplyResult.superseded;
      _managedAccessControl = next;
      ref
          .read(vpnSettingProvider.notifier)
          .update((state) => state.copyWith(accessControlProps: next));
      final behaviorChanged =
          previous.enable != next.enable ||
          (next.enable &&
              (previous.mode != next.mode ||
                  previous.currentList.toSet().length !=
                      next.currentList.toSet().length ||
                  !previous.currentList.toSet().containsAll(next.currentList)));
      _accessControlReconnectNeeded |= wasRunning && behaviorChanged;
      if (revision != _accessControlRevision) {
        return AccessControlApplyResult.superseded;
      }
      if (!wasRunning || !_accessControlReconnectNeeded) {
        if (!wasRunning) _accessControlReconnectNeeded = false;
        return AccessControlApplyResult.saved;
      }
      bool stillCurrent() =>
          ref.mounted &&
          revision == _accessControlRevision &&
          identical(runRequest, _latestRunRequest) &&
          ref.read(isStartProvider);
      if (!stillCurrent()) return AccessControlApplyResult.superseded;
      final sharedState = ref.read(sharedStateProvider);
      await syncAccessControlState(sharedState);
      if (!stillCurrent()) return AccessControlApplyResult.superseded;
      if (!await requestAccessControlRestart()) {
        throw StateError('Unable to request VPN reconnection');
      }
      if (!stillCurrent()) return AccessControlApplyResult.superseded;
      _accessControlReconnectNeeded = false;
      commonPrint.event(
        'vpn.access_control.reconnect_requested',
        fields: {
          'mode': next.mode.name,
          'selected_count': next.currentList.length,
        },
      );
      return AccessControlApplyResult.reconnectRequested;
    });
  }

  @override
  void build() {
    ref.onDispose(() {
      _runtimeTimer?.cancel();
      _physicalNetworkRecoveryRevision++;
    });
  }

  @protected
  bool get requiresListenerReadiness => system.isWindows;

  @protected
  Duration get configurationCoreReadTimeout => const Duration(seconds: 10);

  @protected
  Duration get configurationPreparationTimeout => const Duration(seconds: 15);

  @protected
  bool get supportsCoreSetupTimeoutRecovery => system.isDesktop;

  @protected
  bool get allowsStartupConfigurationDegrade => system.isMacOS;

  @protected
  bool shouldDegradeStartupConfiguration(Object error) {
    return allowsStartupConfigurationDegrade &&
        const {
          'profile_refresh',
          'setup_state',
          'profile_prepare',
        }.contains(_lastConfigurationFailureStage);
  }

  SetupParams _setupParams(Profile? profile) {
    final settings = ref.read(appSettingProvider);
    final selectedMap = Map<String, String>.from(
      profile?.selectedMap ?? ref.read(selectedMapProvider),
    );
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
    try {
      if (shouldRun) {
        await setRunning(true, initialize: true);
      } else {
        await applyProfile(force: true);
      }
    } catch (error, stackTrace) {
      if (!shouldDegradeStartupConfiguration(error)) rethrow;
      commonPrint.event(
        'configuration.startup.degraded',
        fields: {
          'should_run': shouldRun,
          'has_profile': ref.read(currentProfileIdProvider) != null,
          'stage': _lastConfigurationFailureStage,
          'error_type': error.runtimeType.toString(),
          'error': '$error',
        },
      );
      commonPrint.log(
        'macOS startup configuration degraded: $error, $stackTrace',
        logLevel: LogLevel.warning,
      );
    }
  }

  Future<void> setRunning(
    bool running, {
    bool initialize = false,
    bool propagateErrors = false,
  }) {
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
              ? _startVerified(request, propagateErrors: propagateErrors)
              : _start(request, propagateErrors: propagateErrors)
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

  Future<void> _startVerified(
    _RunRequest request, {
    bool propagateErrors = false,
  }) async {
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
    } catch (error, stackTrace) {
      await _failConnection(request, error);
      if (propagateErrors) {
        Error.throwWithStackTrace(error, stackTrace);
      }
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

  Future<void> _start(
    _RunRequest request, {
    bool propagateErrors = false,
  }) async {
    if (request.initialize) {
      try {
        await applyProfile(
          force: true,
          preloadInvoke: () => _setCoreRunning(request),
          propagateErrors: propagateErrors,
        );
      } catch (error, stackTrace) {
        if (_isCurrent(request)) {
          await setRunning(false);
        }
        if (propagateErrors) {
          Error.throwWithStackTrace(error, stackTrace);
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

    if ((system.isWindows || system.isMacOS) && networkSettings.systemProxy) {
      await systemProxyRefreshSignal.request();
      skipReason = _physicalNetworkRecoverySkipReason(
        request: request,
        revision: revision,
        isConfigurationCurrent: configurationCurrent,
      );
      if (skipReason != null) {
        _logPhysicalNetworkRecoverySkipped(skipReason);
        return;
      }
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
    var restartAfterAuthorization = false;
    await _setupScheduler.run(() async {
      await globalState.safeRun(() async {
        await _inspectSystemProxy('before_update');
        try {
          final updateParams = ref.read(updateParamsProvider);
          final shouldContinueSetup = await requestAdmin(
            updateParams.tun.enable,
          );
          if (!ref.mounted || !identical(request, _latestRunRequest)) return;
          if (!shouldContinueSetup) {
            restartAfterAuthorization = true;
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
    });
    if (restartAfterAuthorization) {
      await _restartCoreAfterAuthorization();
      await updateConfig();
      await _restoreListenerAfterRestart(request);
    }
  }

  @protected
  Future<String> applyCoreUpdate(UpdateParams params) {
    return coreController.updateConfig(params);
  }

  @protected
  Future<String> applyCoreSetup({
    required SetupParams params,
    Future<void> Function()? preloadInvoke,
    Duration? timeout,
  }) {
    return coreController.setupConfig(
      params: params,
      preloadInvoke: preloadInvoke,
      timeout: timeout,
    );
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
    unawaited(_changeModeWithFeedback(mode));
  }

  Future<void> _changeModeWithFeedback(Mode mode) async {
    final result = await changeModeAndWait(mode);
    if (!ref.mounted || result != ModeSwitchResult.failed) return;
    globalState.showNotifier(currentAppLocalizations.modeSwitchFailed);
  }

  void changeModeOnly(Mode mode) {
    _modeChangeRevision++;
    _pendingMode = null;
    _pendingModeChange = null;
    ref
        .read(proxiesActionProvider.notifier)
        .cancelHongKongSelection(manual: true);
    if (ref.read(patchClashConfigProvider).mode == mode) return;
    ref
        .read(patchClashConfigProvider.notifier)
        .update((state) => state.copyWith(mode: mode));
  }

  @protected
  Future<bool> rebuildActiveChainForModeChangeWithinTransaction() async {
    final result = await _setupConfig(
      force: true,
      silence: true,
      onUpdated: () async {
        await ref.read(proxiesActionProvider.notifier).updateGroups();
        await ref.read(providersProvider.notifier).syncProviders();
      },
    );
    return result == _SetupTaskResult.handoffToCoreRestart;
  }

  @protected
  Future<void> rebuildActiveChainForModeChange() async {
    var requiresRestart = await _setupScheduler.run(
      rebuildActiveChainForModeChangeWithinTransaction,
    );
    if (requiresRestart) {
      await _restartCoreAfterAuthorization();
      requiresRestart = await _setupScheduler.run(
        rebuildActiveChainForModeChangeWithinTransaction,
      );
      if (requiresRestart) {
        throw StateError('configuration_authorization_handoff_repeated');
      }
      await _restoreListenerAfterRestart(_latestRunRequest);
    }
  }

  @protected
  Future<void> restartActiveChainAfterAuthorization() async {
    final request = _latestRunRequest;
    await _restartCoreAfterAuthorization();
    final requiresRestart = await _setupScheduler.run(
      rebuildActiveChainForModeChangeWithinTransaction,
    );
    if (requiresRestart) {
      throw StateError('configuration_authorization_handoff_repeated');
    }
    await _restoreListenerAfterRestart(request);
  }

  @protected
  bool activeChainModeChangeReady({
    required Mode targetMode,
    required bool wasRunning,
  }) {
    if (ref.read(patchClashConfigProvider).mode != targetMode ||
        ref.read(coreStatusProvider) != CoreStatus.connected) {
      return false;
    }
    if (wasRunning &&
        (!ref.read(isStartProvider) || ref.read(runTimeProvider) == null)) {
      return false;
    }
    if (targetMode == Mode.direct) return true;
    final groups = ref.read(groupsProvider);
    final hasRuntimeProxy = groups.any(
      (group) => group.all.any(
        (proxy) =>
            proxy.name == chainProxyRuntimeName ||
            proxy.name.startsWith('$chainProxyRuntimeName '),
      ),
    );
    if (!hasRuntimeProxy) return false;
    return targetMode != Mode.global ||
        groups.getGroup(GroupName.GLOBAL.name)?.realNow ==
            chainProxyRuntimeName;
  }

  Future<ModeSwitchResult> changeModeAndWait(
    Mode mode, {
    bool Function()? isCancelled,
  }) async {
    final pending = _pendingModeChange;
    if (_pendingMode == mode && pending != null) return pending;
    if (_pendingMode == null &&
        ref.read(patchClashConfigProvider).mode == mode) {
      return ModeSwitchResult.unchanged;
    }
    final revision = ++_modeChangeRevision;
    _pendingMode = mode;
    final operation = _performModeChange(
      mode,
      revision: revision,
      isCancelled: isCancelled,
    );
    _pendingModeChange = operation;
    try {
      return await operation;
    } finally {
      if (revision == _modeChangeRevision) {
        _pendingMode = null;
        _pendingModeChange = null;
      }
    }
  }

  Future<ModeSwitchResult> _performModeChange(
    Mode mode, {
    required int revision,
    bool Function()? isCancelled,
  }) async {
    ref.read(proxiesActionProvider.notifier).cancelHongKongSelection();
    final originalMode = ref.read(patchClashConfigProvider).mode;
    if (originalMode == mode) return ModeSwitchResult.unchanged;
    final syncsRuleAndGlobal =
        originalMode == Mode.rule && mode == Mode.global ||
        originalMode == Mode.global && mode == Mode.rule;
    final activeChain = activeChainProxy(ref.read(appSettingProvider));
    final restoresGlobalChain =
        activeChain != null &&
        originalMode == Mode.direct &&
        mode == Mode.global;
    if (!syncsRuleAndGlobal && !restoresGlobalChain) {
      bool cancelled() {
        return !ref.mounted ||
            revision != _modeChangeRevision ||
            isCancelled?.call() == true;
      }

      if (cancelled()) return ModeSwitchResult.cancelled;
      ref
          .read(patchClashConfigProvider.notifier)
          .update((state) => state.copyWith(mode: mode));
      return ModeSwitchResult.switched;
    }
    if (activeChain != null) {
      return ref
          .read(proxiesActionProvider.notifier)
          .runSelectionTransaction(
            () => _modeRestartScheduler.run(
              () => _changeActiveChainMode(
                mode,
                revision: revision,
                isCancelled: isCancelled,
              ),
            ),
          );
    }
    bool cancelled() {
      return !ref.mounted ||
          revision != _modeChangeRevision ||
          isCancelled?.call() == true;
    }

    if (mode == Mode.direct) {
      if (cancelled()) return ModeSwitchResult.cancelled;
      ref
          .read(patchClashConfigProvider.notifier)
          .update((state) => state.copyWith(mode: mode));
      return ModeSwitchResult.switched;
    }
    return ref
        .read(proxiesActionProvider.notifier)
        .switchModePreservingNode(
          mode,
          ruleGroupName: ruleSelectionGroup,
          isCancelled: cancelled,
        );
  }

  Future<ModeSwitchResult> _changeActiveChainMode(
    Mode targetMode, {
    required int revision,
    bool Function()? isCancelled,
  }) async {
    if (!ref.mounted ||
        revision != _modeChangeRevision ||
        isCancelled?.call() == true) {
      return ModeSwitchResult.cancelled;
    }
    late Mode originalMode;
    ChainProxyConfig? initialChain;
    Profile? initialProfile;
    Profile? committedProfile;
    late int sessionRevision;
    late int initialManualSelectionRevision;
    String? ruleGroupName;
    String? targetGroupName;
    var groups = const <Group>[];
    ModeNodeSelectionPlan? selectionPlan;
    var fields = <String, Object>{};
    var wasRunning = false;
    var coreActive = false;
    var modeCommitted = false;

    bool ownsIntent() => ref.mounted && revision == _modeChangeRevision;

    bool ownsContext() {
      if (!ownsIntent() ||
          isCancelled?.call() == true ||
          sessionRevision != globalState.xboardSessionRevision ||
          ref.read(proxiesActionProvider.notifier).manualSelectionRevision !=
              initialManualSelectionRevision ||
          activeChainProxy(ref.read(appSettingProvider)) != initialChain ||
          ruleSelectionGroup != ruleGroupName) {
        return false;
      }
      return ref.read(currentProfileProvider) ==
          (committedProfile ?? initialProfile);
    }

    Future<_ActiveChainPostAction> restoreWithinTransaction() async {
      if (!ref.mounted) return _ActiveChainPostAction.none;
      final committed = committedProfile;
      final original = initialProfile;
      if (committed != null && original != null) {
        final currentProfile = ref.read(currentProfileProvider);
        if (currentProfile != null) {
          final proxies = ref.read(proxiesActionProvider.notifier);
          final preservedSelectionKeys = {
            for (final key in committed.selectedMap.keys)
              if (proxies.hasManualSelectionAfter(
                key,
                initialManualSelectionRevision,
              ))
                key,
          };
          final restoredProfile = _restoredModeProfile(
            original: original,
            committed: committed,
            current: currentProfile,
            preservedSelectionKeys: preservedSelectionKeys,
          );
          if (restoredProfile != null) {
            ref.read(profilesProvider.notifier).put(restoredProfile);
          }
        }
      }
      if (ref.read(patchClashConfigProvider).mode != targetMode) {
        return _ActiveChainPostAction.none;
      }
      ref
          .read(patchClashConfigProvider.notifier)
          .update((state) => state.copyWith(mode: originalMode));
      debouncer.cancel(FunctionTag.updateConfig);
      modeCommitted = false;
      if (!coreActive) return _ActiveChainPostAction.none;
      try {
        final requiresRestart =
            await rebuildActiveChainForModeChangeWithinTransaction();
        if (requiresRestart) return _ActiveChainPostAction.restartOriginal;
        return activeChainModeChangeReady(
              targetMode: originalMode,
              wasRunning: wasRunning,
            )
            ? _ActiveChainPostAction.none
            : _ActiveChainPostAction.recover;
      } catch (error) {
        commonPrint.event(
          'proxy.mode_switch.restore_failed',
          fields: {...fields, 'error_type': error.runtimeType.toString()},
        );
        return _ActiveChainPostAction.recover;
      }
    }

    Future<ModeSwitchResult> finishOutcome(
      _ActiveChainModeOutcome outcome,
    ) async {
      switch (outcome.postAction) {
        case _ActiveChainPostAction.none:
          return outcome.result;
        case _ActiveChainPostAction.recover:
          await recoverActiveChainModeRuntime(
            expectedMode: originalMode,
            wasRunning: wasRunning,
          );
          return outcome.result;
        case _ActiveChainPostAction.restartOriginal:
          try {
            await restartActiveChainAfterAuthorization();
            if (!activeChainModeChangeReady(
              targetMode: originalMode,
              wasRunning: wasRunning,
            )) {
              await recoverActiveChainModeRuntime(
                expectedMode: originalMode,
                wasRunning: wasRunning,
              );
            }
          } catch (error) {
            commonPrint.event(
              'proxy.mode_switch.restore_failed',
              fields: {...fields, 'error_type': error.runtimeType.toString()},
            );
            await recoverActiveChainModeRuntime(
              expectedMode: originalMode,
              wasRunning: wasRunning,
            );
          }
          return outcome.result;
        case _ActiveChainPostAction.restartTarget:
          try {
            await restartActiveChainAfterAuthorization();
          } catch (error) {
            commonPrint.event(
              'proxy.mode_switch.failed',
              fields: {...fields, 'error_type': error.runtimeType.toString()},
            );
          }
          if (activeChainModeChangeReady(
                targetMode: targetMode,
                wasRunning: wasRunning,
              ) &&
              ownsContext()) {
            final connectionRefreshSucceeded = await ref
                .read(proxiesActionProvider.notifier)
                .applyModeSwitchConnectionPolicy(fields);
            commonPrint.event(
              'proxy.mode_switch.succeeded',
              fields: {
                ...fields,
                'core_active': true,
                'connection_refresh_succeeded': connectionRefreshSucceeded,
              },
            );
            return ModeSwitchResult.switched;
          }
          final postAction = await runModeSwitchTransaction(
            restoreWithinTransaction,
          );
          final result = !ownsIntent() || isCancelled?.call() == true
              ? ModeSwitchResult.cancelled
              : ModeSwitchResult.failed;
          return finishOutcome(
            _ActiveChainModeOutcome(result, postAction: postAction),
          );
      }
    }

    try {
      final outcome = await runModeSwitchTransaction(() async {
        if (!ownsIntent() || isCancelled?.call() == true) {
          return const _ActiveChainModeOutcome(ModeSwitchResult.cancelled);
        }
        originalMode = ref.read(patchClashConfigProvider).mode;
        initialChain = activeChainProxy(ref.read(appSettingProvider));
        if (initialChain == null) {
          return const _ActiveChainModeOutcome(ModeSwitchResult.cancelled);
        }
        if (originalMode == targetMode) {
          return const _ActiveChainModeOutcome(ModeSwitchResult.unchanged);
        }
        initialProfile = ref.read(currentProfileProvider);
        sessionRevision = globalState.xboardSessionRevision;
        final proxies = ref.read(proxiesActionProvider.notifier);
        initialManualSelectionRevision = proxies.manualSelectionRevision;
        ruleGroupName = ruleSelectionGroup;
        final sourceGroupName = switch ((originalMode, targetMode)) {
          (Mode.rule, Mode.global) => ruleGroupName,
          (Mode.global, Mode.rule) => GroupName.GLOBAL.name,
          _ => null,
        };
        targetGroupName = switch (targetMode) {
          Mode.global => GroupName.GLOBAL.name,
          Mode.rule => ruleGroupName,
          Mode.direct => null,
        };
        coreActive =
            ref.read(coreStatusProvider) == CoreStatus.connected &&
            ref.read(runTimeProvider) != null;
        groups = coreActive
            ? await proxies.loadModeSwitchGroups()
            : ref.read(groupsProvider);
        if (!ownsContext() ||
            ref.read(patchClashConfigProvider).mode != originalMode) {
          return const _ActiveChainModeOutcome(ModeSwitchResult.cancelled);
        }
        final inheritedPlan =
            initialProfile == null ||
                sourceGroupName == null ||
                targetGroupName == null
            ? null
            : planModeNodeSelection(
                sourceGroupName: sourceGroupName,
                targetGroupName: targetGroupName!,
                groups: groups,
                selectedMap: initialProfile!.selectedMap,
              );
        selectionPlan = inheritedPlan;
        if (targetMode == Mode.global) {
          final targetSelections = {
            ...?initialProfile?.selectedMap,
            ...?selectionPlan?.selections,
          };
          final globalTarget = resolveModeNodeLeaf(
            rootGroupName: GroupName.GLOBAL.name,
            groups: groups,
            selectedMap: targetSelections,
          );
          if (globalTarget != null && selectionPlan == null) {
            selectionPlan = planModeNodeSelection(
              sourceGroupName: globalTarget,
              targetGroupName: GroupName.GLOBAL.name,
              groups: groups,
              selectedMap: targetSelections,
            );
          }
          if (selectionPlan == null) {
            commonPrint.event(
              'proxy.mode_switch.failed',
              fields: {
                'from_mode': originalMode.name,
                'to_mode': targetMode.name,
                'chain_rebuild': true,
                'reason': 'chain_global_target_unavailable',
              },
            );
            return const _ActiveChainModeOutcome(ModeSwitchResult.failed);
          }
        }
        fields = <String, Object>{
          'from_mode': originalMode.name,
          'to_mode': targetMode.name,
          'chain_rebuild': true,
          'selection_inherited': inheritedPlan != null,
          if (initialProfile != null) 'profile_id': initialProfile!.id,
          if (selectionPlan != null)
            'node_ref': diagnosticFingerprint(selectionPlan!.nodeName),
        };
        wasRunning = ref.read(isStartProvider);
        commonPrint.event('proxy.mode_switch.started', fields: fields);
        committedProfile = _createActiveChainModeProfile(
          initialProfile,
          targetGroupName,
          selectionPlan?.selections ?? const {},
          groups,
        );
        if (committedProfile != null) {
          ref.read(profilesProvider.notifier).put(committedProfile!);
        }
        ref
            .read(patchClashConfigProvider.notifier)
            .update((state) => state.copyWith(mode: targetMode));
        debouncer.cancel(FunctionTag.updateConfig);
        modeCommitted = true;
        if (!ownsContext()) {
          final postAction = await restoreWithinTransaction();
          return _ActiveChainModeOutcome(
            ModeSwitchResult.cancelled,
            postAction: postAction,
          );
        }
        if (!coreActive) {
          commonPrint.event(
            'proxy.mode_switch.succeeded',
            fields: {...fields, 'core_active': false},
          );
          return const _ActiveChainModeOutcome(ModeSwitchResult.switched);
        }
        bool requiresRestart;
        try {
          requiresRestart =
              await rebuildActiveChainForModeChangeWithinTransaction();
        } catch (error) {
          final postAction = await restoreWithinTransaction();
          commonPrint.event(
            'proxy.mode_switch.failed',
            fields: {...fields, 'error_type': error.runtimeType.toString()},
          );
          return _ActiveChainModeOutcome(
            ownsIntent() ? ModeSwitchResult.failed : ModeSwitchResult.cancelled,
            postAction: postAction,
          );
        }
        if (requiresRestart) {
          return const _ActiveChainModeOutcome(
            ModeSwitchResult.switched,
            postAction: _ActiveChainPostAction.restartTarget,
          );
        }
        if (!activeChainModeChangeReady(
          targetMode: targetMode,
          wasRunning: wasRunning,
        )) {
          final postAction = await restoreWithinTransaction();
          commonPrint.event(
            'proxy.mode_switch.failed',
            fields: {...fields, 'reason': 'chain_rebuild_not_ready'},
          );
          return _ActiveChainModeOutcome(
            ownsIntent() ? ModeSwitchResult.failed : ModeSwitchResult.cancelled,
            postAction: postAction,
          );
        }
        if (!ownsContext()) {
          final postAction = ownsIntent()
              ? await restoreWithinTransaction()
              : _ActiveChainPostAction.none;
          return _ActiveChainModeOutcome(
            ModeSwitchResult.cancelled,
            postAction: postAction,
          );
        }
        final connectionRefreshSucceeded = await proxies
            .applyModeSwitchConnectionPolicy(fields);
        commonPrint.event(
          'proxy.mode_switch.succeeded',
          fields: {
            ...fields,
            'core_active': true,
            'connection_refresh_succeeded': connectionRefreshSucceeded,
          },
        );
        return const _ActiveChainModeOutcome(ModeSwitchResult.switched);
      });
      return finishOutcome(outcome);
    } catch (error) {
      var postAction = _ActiveChainPostAction.none;
      if (modeCommitted && ref.mounted) {
        try {
          postAction = await runModeSwitchTransaction(restoreWithinTransaction);
        } catch (_) {
          postAction = _ActiveChainPostAction.recover;
        }
      }
      commonPrint.event(
        'proxy.mode_switch.failed',
        fields: {
          ...fields,
          'to_mode': targetMode.name,
          'chain_rebuild': true,
          'error_type': error.runtimeType.toString(),
        },
      );
      final result = ownsIntent()
          ? ModeSwitchResult.failed
          : ModeSwitchResult.cancelled;
      return finishOutcome(
        _ActiveChainModeOutcome(result, postAction: postAction),
      );
    }
  }

  Profile? _createActiveChainModeProfile(
    Profile? profile,
    String? groupName,
    Map<String, String> selections,
    List<Group> groups,
  ) {
    if (profile == null) return null;
    final nextGroupName = groupName == GroupName.GLOBAL.name
        ? GroupName.GLOBAL.name
        : groupName == null
        ? profile.currentGroupName
        : resolveRuleModeDisplayGroup(
            ruleTargetName: groupName,
            currentGroupName: profile.currentGroupName,
            groups: groups,
          );
    final nextSelections = {...profile.selectedMap, ...selections};
    final next = profile.copyWith(
      currentGroupName: nextGroupName,
      selectedMap: nextSelections,
    );
    return next == profile ? null : next;
  }

  Future<bool> applySelectedProxyMode(
    Mode mode, {
    required bool Function() isCancelled,
    bool Function()? canRestore,
  }) {
    return _setupScheduler.run(
      () => applySelectedProxyModeWithinTransaction(
        mode,
        isCancelled: isCancelled,
        canRestore: canRestore,
      ),
    );
  }

  Future<T> runModeSwitchTransaction<T>(Future<T> Function() transaction) {
    return _setupScheduler.run(transaction);
  }

  Future<bool> recoverModeSwitchRuntime() async {
    try {
      await _runSetup(force: true, silence: true, propagateErrors: true);
      return true;
    } catch (error) {
      commonPrint.event(
        'proxy.mode_switch.recovery_failed',
        fields: {'error_type': error.runtimeType.toString()},
      );
      if (!ref.mounted || !ref.read(isStartProvider)) return false;
      try {
        await setRunning(false);
      } catch (stopError) {
        commonPrint.event(
          'proxy.mode_switch.recovery_disconnect_failed',
          fields: {'error_type': stopError.runtimeType.toString()},
        );
      }
      return false;
    }
  }

  @protected
  Future<bool> recoverActiveChainModeRuntime({
    required Mode expectedMode,
    required bool wasRunning,
  }) async {
    await recoverModeSwitchRuntime();
    if (!ref.mounted) return false;
    if (wasRunning &&
        !activeChainModeChangeReady(
          targetMode: expectedMode,
          wasRunning: true,
        )) {
      try {
        await setRunning(true);
      } catch (error) {
        commonPrint.event(
          'proxy.mode_switch.recovery_restart_failed',
          fields: {'error_type': error.runtimeType.toString()},
        );
      }
    }
    final ready = activeChainModeChangeReady(
      targetMode: expectedMode,
      wasRunning: wasRunning,
    );
    if (!ready) {
      commonPrint.event(
        'proxy.mode_switch.recovery_not_ready',
        fields: {'mode': expectedMode.name, 'was_running': wasRunning},
      );
    }
    return ready;
  }

  Future<bool> applySelectedProxyModeWithinTransaction(
    Mode mode, {
    required bool Function() isCancelled,
    bool Function()? canRestore,
  }) async {
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
          'proxy.mode_switch.mode_restore_failed',
          fields: {'error_type': restoreError.runtimeType.toString()},
        );
        throw ModeSwitchRecoveryException(restoreError);
      }
      rethrow;
    }
    ref
        .read(patchClashConfigProvider.notifier)
        .update((state) => state.copyWith(mode: mode));
    debouncer.cancel(FunctionTag.updateConfig);
    return true;
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
    bool Function()? isCurrent,
    bool propagateErrors = false,
    Profile? profileOverride,
  }) {
    return _runSetup(
      force: force,
      silence: silence,
      preloadInvoke: preloadInvoke,
      isCurrent: isCurrent,
      propagateErrors: propagateErrors,
      profileOverride: profileOverride,
    );
  }

  Future<void> _runSetup({
    bool silence = false,
    bool force = false,
    Future<void> Function()? preloadInvoke,
    bool propagateErrors = false,
    bool Function()? isCurrent,
    Profile? profileOverride,
  }) async {
    final request = _latestRunRequest;
    final stableProfile = ref.read(currentProfileProvider);
    var handedOffToCoreRestart = false;
    var authorizationRestartCompleted = false;
    Future<_SetupTaskResult> runAttempt({required bool forceApply}) {
      return _setupScheduler.run(() {
        return _setupConfig(
          force: forceApply,
          silence: silence,
          preloadInvoke: preloadInvoke,
          isCurrent: isCurrent,
          profileOverride: profileOverride,
          onUpdated: () async {
            await ref.read(proxiesActionProvider.notifier).updateGroups();
            await ref.read(providersProvider.notifier).syncProviders();
          },
        );
      });
    }

    try {
      var result = await runAttempt(forceApply: force);
      if (result == _SetupTaskResult.handoffToCoreRestart) {
        handedOffToCoreRestart = true;
        if (isCurrent?.call() == false) {
          throw StateError('configuration_apply_superseded');
        }
        await _restartCoreAfterAuthorization();
        authorizationRestartCompleted = true;
        if (isCurrent?.call() == false) {
          throw StateError('configuration_apply_superseded');
        }
        result = await runAttempt(forceApply: true);
        if (result == _SetupTaskResult.handoffToCoreRestart) {
          throw StateError('configuration_authorization_handoff_repeated');
        }
        await _restoreListenerAfterRestart(request);
      }
    } catch (error) {
      if (handedOffToCoreRestart) {
        ref.read(authorizedTunEnableProvider.notifier).value =
            TunAuthorizationState.none;
        if (authorizationRestartCompleted) {
          try {
            await recoverStableCoreConfiguration(
              stableProfile,
              reason: 'authorization_reapply_failed',
            );
          } catch (_) {}
        }
        commonPrint.event(
          'configuration.apply.failed',
          fields: {
            'stage': authorizationRestartCompleted
                ? 'core_reapply'
                : 'core_restart',
            'timed_out': error is TimeoutException,
            'error_type': error.runtimeType.toString(),
            'error': '$error',
            if (error is CoreMethodException) 'error_code': error.code,
          },
        );
      }
      if (handedOffToCoreRestart &&
          identical(request, _latestRunRequest) &&
          ref.read(isStartProvider)) {
        await setRunning(false);
      }
      if (!requiresListenerReadiness) rethrow;
      if (request?.running == true) {
        await _failConnection(request!, error);
      } else if (!propagateErrors) {
        notifyListenerFailure(ref.read(patchClashConfigProvider).mixedPort);
      }
      if (propagateErrors || handedOffToCoreRestart) rethrow;
    }
  }

  Future<void> _applyWithFeedback(
    Future<void> Function() apply, {
    required bool silence,
  }) async {
    if (!requiresListenerReadiness) {
      Object? failure;
      StackTrace? failureStackTrace;
      await globalState.loadingRun<void>(
        () async {
          try {
            await apply();
          } catch (error, stackTrace) {
            failure = error;
            failureStackTrace = stackTrace;
            rethrow;
          }
        },
        silence: true,
        tag: !silence ? LoadingTag.proxies : null,
      );
      if (failure != null) {
        Error.throwWithStackTrace(failure!, failureStackTrace!);
      }
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

  @protected
  Future<void> restartCoreLifecycleOnly() {
    return ref.read(coreActionProvider.notifier).restartCoreLifecycleOnly();
  }

  @protected
  Future<void> stopCoreLifecycleOnly() {
    return ref.read(coreActionProvider.notifier).stopCoreLifecycleOnly();
  }

  Future<void> _restoreListenerAfterRestart(_RunRequest? request) {
    bool shouldRestore() =>
        ref.mounted &&
        identical(request, _latestRunRequest) &&
        !ref.read(suspendProvider) &&
        (ref.read(isStartProvider) || ref.read(connectionPendingProvider));
    return _listenerScheduler.run(() async {
      if (!shouldRestore()) return;
      if (!await setCoreRunning(true)) {
        throw StateError('listener_restore_failed');
      }
      if (!shouldRestore()) return;
      final config = ref.read(patchClashConfigProvider);
      final tunOnly =
          config.mixedPort == 0 &&
          !ref.read(networkSettingProvider).systemProxy &&
          _getEffectiveTunEnable(config.tun.enable);
      if (requiresListenerReadiness && !tunOnly) {
        await verifyLocalListener(
          config.mixedPort,
          isCancelled: () => !shouldRestore(),
        );
      }
    });
  }

  Future<void> _restartCoreAfterAuthorization() async {
    try {
      await restartCoreLifecycleOnly();
    } catch (_) {
      ref.read(authorizedTunEnableProvider.notifier).value =
          TunAuthorizationState.none;
      rethrow;
    }
  }

  Future<String> _applyCoreSetupWithDeadline({required SetupParams params}) {
    final timeout = supportsCoreSetupTimeoutRecovery
        ? configurationPreparationTimeout
        : null;
    final operation = applyCoreSetup(params: params, timeout: timeout);
    return timeout == null ? operation : operation.timeout(timeout);
  }

  @protected
  Future<void> recoverStableCoreConfiguration(
    Profile? profile, {
    required String reason,
  }) async {
    final request = _latestRunRequest;
    final stopwatch = Stopwatch()..start();
    commonPrint.event(
      'configuration.recovery.started',
      fields: {'reason': reason, 'has_profile': profile != null},
    );
    try {
      await restartCoreLifecycleOnly();
      final message = await _applyCoreSetupWithDeadline(
        params: _setupParams(profile),
      );
      if (message.isNotEmpty && !message.endsWith('is empty')) {
        throw StateError(message);
      }
      await ref.read(proxiesActionProvider.notifier).updateGroups();
      await ref.read(providersProvider.notifier).syncProviders();
      await _restoreListenerAfterRestart(request);
      commonPrint.event(
        'configuration.recovery.succeeded',
        fields: {'reason': reason, 'elapsed_ms': stopwatch.elapsedMilliseconds},
      );
    } catch (error) {
      var stopped = false;
      try {
        await stopCoreLifecycleOnly();
        stopped = true;
      } catch (stopError) {
        commonPrint.event(
          'configuration.recovery.stop_failed',
          fields: {
            'reason': reason,
            'error_type': stopError.runtimeType.toString(),
          },
        );
      }
      commonPrint.event(
        'configuration.recovery.failed',
        fields: {
          'reason': reason,
          'elapsed_ms': stopwatch.elapsedMilliseconds,
          'error_type': error.runtimeType.toString(),
          'core_stopped': stopped,
        },
      );
      rethrow;
    }
  }

  Future<VM2<String, String>> getProfile({
    required SetupState setupState,
    required PatchClashConfig patchConfig,
    Map<String, String>? selectedMapOverride,
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
    final Map<String, String> selectedMap =
        selectedMapOverride ?? ref.read(selectedMapProvider);
    final chainProxyBypassDomains = ref
        .read(profilesProvider)
        .map((profile) => Uri.tryParse(profile.url)?.host ?? '')
        .where((host) => host.isNotEmpty)
        .toSet()
        .toList();
    final configMap = await coreController
        .getConfig(profileId, timeout: configurationCoreReadTimeout)
        .timeout(configurationPreparationTimeout);
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
    bool Function()? isCurrent,
    Profile? profileOverride,
  }) async {
    final stableProfile = ref.read(currentProfileProvider);
    var profile = profileOverride ?? stableProfile;
    final patchConfig = ref.read(patchClashConfigProvider);
    final stopwatch = Stopwatch()..start();
    var stage = 'profile_refresh';
    _lastConfigurationFailureStage = null;
    commonPrint.event(
      'configuration.apply.started',
      fields: {
        'force': force,
        'has_profile': profile != null,
        'tun_requested': patchConfig.tun.enable,
        'mode': patchConfig.mode.name,
      },
    );
    Future<T> runStage<T>(String nextStage, Future<T> Function() action) async {
      if (isCurrent?.call() == false) {
        throw StateError('configuration_apply_superseded');
      }
      stage = nextStage;
      final stageStopwatch = Stopwatch()..start();
      commonPrint.event(
        'configuration.apply.stage.started',
        fields: {'stage': stage},
      );
      final result = await action();
      if (isCurrent?.call() == false) {
        throw StateError('configuration_apply_superseded');
      }
      commonPrint.event(
        'configuration.apply.stage.completed',
        fields: {
          'stage': stage,
          'elapsed_ms': stageStopwatch.elapsedMilliseconds,
        },
      );
      return result;
    }

    var effectiveTunEnable = false;
    String? configFilePath;
    Uint8List? previousConfigBytes;
    var configFileExisted = false;
    var configWriteStarted = false;
    var coreSetupStarted = false;
    try {
      final nextProfile = profileOverride == null
          ? await runStage(
              'profile_refresh',
              () async => profile?.checkAndUpdateAndCopy().timeout(
                configurationPreparationTimeout,
              ),
            )
          : null;
      if (nextProfile != null) {
        profile = nextProfile;
        if (profileOverride == null) {
          ref.read(profilesProvider.notifier).put(nextProfile);
        }
      }
      commonPrint.log('setup ===> ${profile?.realLabel}');
      await runStage('system_proxy_before', () async {
        await _inspectSystemProxy('before_setup');
      });
      final shouldContinueSetup = await runStage(
        'tun_authorization',
        () => requestAdmin(patchConfig.tun.enable),
      );
      if (!shouldContinueSetup) {
        commonPrint.event(
          'configuration.apply.handoff',
          fields: {
            'has_profile': profile != null,
            'outcome': 'core_restart_required',
            'elapsed_ms': stopwatch.elapsedMilliseconds,
          },
        );
        return _SetupTaskResult.handoffToCoreRestart;
      }
      effectiveTunEnable = _getEffectiveTunEnable(patchConfig.tun.enable);
      final realPatchConfig = patchConfig.copyWith.tun(
        enable: effectiveTunEnable,
      );
      final setupState = await runStage(
        'setup_state',
        () => ref
            .read(setupStateProvider(profile?.id).future)
            .timeout(configurationPreparationTimeout),
      );
      final vm2 = await runStage(
        'profile_prepare',
        () => getProfile(
          setupState: setupState,
          patchConfig: realPatchConfig,
          selectedMapOverride: profileOverride?.selectedMap,
        ).timeout(configurationPreparationTimeout),
      );
      final yamlString = vm2.a;
      final yamlMd5 = vm2.b;
      if (yamlMd5 == globalState.lastConfigMd5 && force == false) {
        commonPrint.event(
          'configuration.apply.succeeded',
          fields: {
            'has_profile': profile != null,
            'tun_effective': effectiveTunEnable,
            'outcome': 'unchanged',
            'elapsed_ms': stopwatch.elapsedMilliseconds,
          },
        );
        return _SetupTaskResult.completed;
      }
      if (system.isAndroid) {
        await runStage('android_shared_state', () async {
          globalState.lastVpnState = ref.read(vpnStateProvider);
          final sharedState = ref.read(sharedStateProvider);
          await preferences.saveShareState(sharedState);
        });
      }
      await _applyWithFeedback(() async {
        configFilePath = await runStage(
          'config_path',
          () => appPath.configFilePath,
        );
        await runStage('config_snapshot', () async {
          final file = File(configFilePath!);
          configFileExisted = await file.exists();
          if (configFileExisted) {
            previousConfigBytes = await file.readAsBytes();
          }
        });
        await runStage('config_write', () {
          configWriteStarted = true;
          return File(configFilePath!).safeWriteAsString(yamlString);
        });
        final message = await runStage('core_setup', () {
          coreSetupStarted = true;
          return _applyCoreSetupWithDeadline(params: _setupParams(profile));
        });
        if (message.isNotEmpty && !message.endsWith('is empty')) {
          throw message;
        }
        if (message.isEmpty && preloadInvoke != null) {
          await runStage('listener_prepare', preloadInvoke);
        }
        await runStage('post_update', () async {
          await onUpdated?.call();
        });
        globalState.lastConfigMd5 = yamlMd5;
        _appliedRuleProfileId = profile?.id;
        _appliedRuleTarget = defaultRuleTarget(yamlString);
        ref.read(checkIpNumProvider.notifier).add();
      }, silence: silence);
      commonPrint.event(
        'configuration.apply.succeeded',
        fields: {
          'has_profile': profile != null,
          'tun_effective': effectiveTunEnable,
          'outcome': 'applied',
          'elapsed_ms': stopwatch.elapsedMilliseconds,
        },
      );
      return _SetupTaskResult.completed;
    } catch (error, stackTrace) {
      _lastConfigurationFailureStage = stage;
      var configRestored = true;
      if (configWriteStarted && configFilePath != null) {
        try {
          final file = File(configFilePath!);
          if (configFileExisted) {
            await file.safeWriteAsBytes(previousConfigBytes ?? const <int>[]);
          } else {
            await file.safeDelete();
          }
        } catch (restoreError) {
          configRestored = false;
          commonPrint.event(
            'configuration.rollback.failed',
            fields: {
              'stage': stage,
              'error_type': restoreError.runtimeType.toString(),
            },
          );
        }
      }
      if (coreSetupStarted) {
        try {
          if (configRestored) {
            await recoverStableCoreConfiguration(
              stableProfile,
              reason: error is TimeoutException
                  ? 'core_setup_timeout'
                  : 'core_setup_failed',
            );
          } else {
            await stopCoreLifecycleOnly();
          }
        } catch (_) {}
      }
      commonPrint.event(
        'configuration.apply.failed',
        fields: {
          'stage': stage,
          'elapsed_ms': stopwatch.elapsedMilliseconds,
          'timed_out': error is TimeoutException,
          'error_type': error.runtimeType.toString(),
          'error': '$error',
          if (error is CoreMethodException) 'error_code': error.code,
          'tun_effective': effectiveTunEnable,
        },
      );
      commonPrint.log(
        'apply configuration failed at $stage: $error, $stackTrace',
        logLevel: LogLevel.warning,
      );
      rethrow;
    } finally {
      await _inspectSystemProxy('after_setup');
    }
  }
}

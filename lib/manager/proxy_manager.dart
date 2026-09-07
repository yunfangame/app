import 'dart:async';

import 'package:fl_clash/common/app_localizations.dart';
import 'package:fl_clash/common/macos_proxy_guard.dart';
import 'package:fl_clash/common/print.dart';
import 'package:fl_clash/common/proxy.dart';
import 'package:fl_clash/common/system.dart';
import 'package:fl_clash/common/windows_proxy_guard.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart' show ProxyState;
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:proxy/proxy.dart';

class ProxyManager extends ConsumerStatefulWidget {
  final Proxy? proxyClient;
  final WindowsProxyGuard? windowsProxyGuard;
  final MacOSProxyGuard? macOSProxyGuard;
  final bool? isWindows;
  final bool? isMacOS;
  final Duration macOSProxyGuardInterval;
  final ValueChanged<String>? notify;
  final Widget child;

  const ProxyManager({
    super.key,
    this.proxyClient,
    this.windowsProxyGuard,
    this.macOSProxyGuard,
    this.isWindows,
    this.isMacOS,
    this.macOSProxyGuardInterval = const Duration(seconds: 5),
    this.notify,
    required this.child,
  });

  @override
  ConsumerState createState() => _ProxyManagerState();
}

class _ProxyManagerState extends ConsumerState<ProxyManager> {
  Future<void> _pendingUpdate = Future.value();
  WindowsProxyGuard? _windowsProxyGuard;
  MacOSProxyGuard? _macOSProxyGuard;
  late final Proxy? _proxyClient;
  late final bool _isWindows;
  late final bool _isMacOS;
  Timer? _macOSProxyGuardTimer;
  bool _systemProxyGuardCheckScheduled = false;
  Future<void>? _systemProxyGuardCheck;
  int _requestedRevision = 0;

  bool _isCurrent(int revision) => mounted && revision == _requestedRevision;

  Future<void> _updateProxy(ProxyState proxyState, int revision) async {
    if (!mounted || !_isCurrent(revision)) return;
    final isStart = proxyState.isStart;
    final systemProxy = proxyState.systemProxy;
    final port = proxyState.port;
    commonPrint.event(
      'system_proxy.apply.started',
      fields: {
        'running_requested': isStart,
        'system_proxy_requested': systemProxy,
        'port': port,
      },
    );
    ProxyOperationResult? result;
    if (isStart && systemProxy) {
      _stopMacOSProxyGuard();
      final windowsGuard = _windowsProxyGuard;
      final macOSGuard = _macOSProxyGuard;
      if (windowsGuard != null) {
        final readiness = await windowsGuard.waitUntilReadyDetailed(
          port,
          isCancelled: () => !_isCurrent(revision),
        );
        commonPrint.event(
          'system_proxy.local_port.completed',
          fields: {
            ...readiness.toDiagnosticData(),
            'stale_request': !_isCurrent(revision),
          },
        );
        if (!_isCurrent(revision)) return;
        if (!readiness.ready) {
          result = const ProxyOperationResult(
            success: false,
            operation: 'start',
            stage: 'local_port_unavailable',
          );
        }
      }
      if (result == null && macOSGuard != null) {
        final readiness = await macOSGuard.waitUntilReadyDetailed(
          port,
          isCancelled: () => !_isCurrent(revision),
        );
        commonPrint.event(
          'system_proxy.local_port.completed',
          fields: {
            ...readiness.toDiagnosticData(),
            'platform': 'macos',
            'stale_request': !_isCurrent(revision),
          },
        );
        if (!_isCurrent(revision)) return;
        if (!readiness.ready) {
          result = const ProxyOperationResult(
            success: false,
            operation: 'start',
            stage: 'local_port_unavailable',
          );
        }
      }
      try {
        result ??= await _proxyClient?.startProxyDetailed(
          port,
          proxyState.bassDomain,
        );
      } catch (error) {
        commonPrint.event(
          'system_proxy.native_apply.failed',
          fields: {'error_type': error.runtimeType.toString()},
        );
        result = const ProxyOperationResult(
          success: false,
          operation: 'start',
          stage: 'native_exception',
        );
      }
      if (result?.success == true &&
          windowsGuard != null &&
          _isCurrent(revision)) {
        try {
          final verification = await windowsGuard.verifyAfterApply(
            port,
            isCancelled: () => !_isCurrent(revision),
          );
          if (verification != null) {
            commonPrint.event(
              'system_proxy.apply.recheck',
              fields: verification.toDiagnosticFields(),
            );
            if (!verification.success) result = verification;
          }
        } catch (error) {
          commonPrint.event(
            'system_proxy.recheck.failed',
            fields: {'error_type': error.runtimeType.toString()},
          );
          result = const ProxyOperationResult(
            success: false,
            operation: 'inspect',
            stage: 'readback',
          );
        }
      }
      if (result?.success == true &&
          macOSGuard != null &&
          _isCurrent(revision)) {
        final fallbackPending = result?.stage == 'fallback_pending';
        try {
          final verification = await macOSGuard.verifyAfterApply(
            port,
            isCancelled: () => !_isCurrent(revision),
          );
          if (verification != null) {
            commonPrint.event(
              'system_proxy.apply.recheck',
              fields: {
                ...verification.toDiagnosticFields(),
                'platform': 'macos',
              },
            );
            if (!verification.success && !fallbackPending) {
              result = verification;
            }
          }
        } catch (error) {
          commonPrint.event(
            'system_proxy.recheck.failed',
            fields: {
              'platform': 'macos',
              'error_type': error.runtimeType.toString(),
            },
          );
          result = const ProxyOperationResult(
            success: false,
            operation: 'inspect',
            stage: 'readback',
          );
        }
      }
      if (result?.success == true && macOSGuard != null) {
        _startMacOSProxyGuard();
      }
    } else {
      _stopMacOSProxyGuard();
      result = await _proxyClient?.stopProxyDetailed(
        expectedPort: _isWindows || _isMacOS ? port : null,
      );
    }
    final succeeded = result?.success;
    commonPrint.event(
      'system_proxy.apply.completed',
      fields: {
        'running_requested': isStart,
        'system_proxy_requested': systemProxy,
        'success': succeeded,
        if (result != null) ...result.toDiagnosticFields(),
        'stale_request': !_isCurrent(revision),
      },
    );
    if (succeeded != false || !_isCurrent(revision)) return;

    commonPrint.log(
      'update system proxy failed: ${result?.diagnosticCode} '
      'stage=${result?.stage} win32=${result?.errorCode}',
      logLevel: LogLevel.warning,
    );
    if (!mounted) return;

    if (!isStart || !systemProxy) {
      _showNotifier(
        currentAppLocalizations.systemProxyDisableFailed(
          result?.diagnosticCode ?? 'W-PROXY-09',
        ),
      );
      return;
    }

    final currentNetworkSetting = ref.read(networkSettingProvider);
    final hasEffectiveTun =
        ref.read(patchClashConfigProvider).tun.enable &&
        ref.read(authorizedTunEnableProvider) ==
            TunAuthorizationState.authorized;
    final shouldStopRunning =
        (_isWindows || _isMacOS) &&
        (result?.stage == 'local_port_unavailable' || !hasEffectiveTun);
    final stopOperation = shouldStopRunning
        ? ref.read(setupActionProvider.notifier).setRunning(false)
        : null;
    if (currentNetworkSetting.systemProxy) {
      ref.read(networkSettingProvider.notifier).value = currentNetworkSetting
          .copyWith(systemProxy: false);
    }
    _showNotifier(
      currentAppLocalizations.systemProxyApplyFailed(
        result?.diagnosticCode ?? 'W-PROXY-09',
      ),
    );
    await stopOperation;
  }

  void _showNotifier(String message) {
    if (!mounted) return;
    final notify = widget.notify;
    if (notify != null) {
      notify(message);
    } else {
      globalState.showNotifier(message);
    }
  }

  void _startMacOSProxyGuard() {
    if (_macOSProxyGuard == null) return;
    _macOSProxyGuardTimer?.cancel();
    _macOSProxyGuardTimer = Timer.periodic(
      widget.macOSProxyGuardInterval,
      (_) => unawaited(_scheduleSystemProxyGuardCheck()),
    );
  }

  void _stopMacOSProxyGuard() {
    _macOSProxyGuardTimer?.cancel();
    _macOSProxyGuardTimer = null;
  }

  Future<void> _scheduleSystemProxyGuardCheck() {
    final windowsGuard = _windowsProxyGuard;
    final macOSGuard = _macOSProxyGuard;
    if ((windowsGuard == null && macOSGuard == null) || !mounted) {
      return Future<void>.value();
    }
    if (_systemProxyGuardCheckScheduled) {
      return _systemProxyGuardCheck ?? Future<void>.value();
    }
    final revision = _requestedRevision;
    _systemProxyGuardCheckScheduled = true;
    final operation = _pendingUpdate
        .then((_) async {
          if (!_isCurrent(revision)) return;
          final proxyState = ref.read(proxyStateProvider);
          if (!proxyState.isStart || !proxyState.systemProxy) return;
          if (windowsGuard != null) {
            final result = await windowsGuard.reconcile(
              proxyState.port,
              proxyState.bassDomain,
              isCancelled: () => !_isCurrent(revision),
            );
            if (result == null || result.inspection.success) return;
            commonPrint.event(
              'system_proxy.guard.completed',
              fields: {
                'platform': 'windows',
                'repaired': result.repaired,
                'inspection': result.inspection.toDiagnosticFields(),
                if (result.readiness != null)
                  'readiness': result.readiness!.toDiagnosticData(),
                if (result.repair != null)
                  'repair': result.repair!.toDiagnosticFields(),
                if (result.verification != null)
                  'verification': result.verification!.toDiagnosticFields(),
              },
            );
            return;
          }
          final result = await macOSGuard!.reconcile(
            proxyState.port,
            proxyState.bassDomain,
            isCancelled: () => !_isCurrent(revision),
          );
          if (result == null || result.inspection.success) return;
          commonPrint.event(
            'system_proxy.guard.completed',
            fields: {
              'platform': 'macos',
              'repaired': result.repaired,
              'inspection': result.inspection.toDiagnosticFields(),
              if (result.readiness != null)
                'readiness': result.readiness!.toDiagnosticData(),
              if (result.repair != null)
                'repair': result.repair!.toDiagnosticFields(),
            },
          );
        })
        .catchError((Object error) {
          commonPrint.event(
            'system_proxy.guard.failed',
            fields: {
              'platform': windowsGuard != null ? 'windows' : 'macos',
              'error_type': error.runtimeType.toString(),
            },
          );
        });
    late final Future<void> tracked;
    tracked = operation.whenComplete(() {
      if (!identical(_systemProxyGuardCheck, tracked)) return;
      _systemProxyGuardCheckScheduled = false;
      _systemProxyGuardCheck = null;
    });
    _systemProxyGuardCheck = tracked;
    _pendingUpdate = tracked;
    return tracked;
  }

  void _scheduleUpdateProxy(ProxyState proxyState) {
    final revision = ++_requestedRevision;
    _pendingUpdate = _pendingUpdate
        .then((_) => _updateProxy(proxyState, revision))
        .catchError((Object error) {
          commonPrint.event(
            'system_proxy.apply.failed',
            fields: {
              'error_type': error.runtimeType.toString(),
              'error': '$error',
            },
          );
          commonPrint.log(
            'update system proxy failed: $error',
            logLevel: LogLevel.warning,
          );
        });
  }

  void _scheduleStartupRepair(ProxyState proxyState) {
    final windowsGuard = _windowsProxyGuard;
    final macOSGuard = _macOSProxyGuard;
    if (windowsGuard == null && macOSGuard == null) return;
    final revision = ++_requestedRevision;
    _pendingUpdate = _pendingUpdate
        .then((_) async {
          if (!_isCurrent(revision)) return;
          if (windowsGuard != null) {
            final result = await windowsGuard.repairStale(
              proxyState.port,
              isCancelled: () => !_isCurrent(revision),
            );
            commonPrint.event(
              'system_proxy.startup_repair.completed',
              fields: {
                'platform': 'windows',
                'status': result.status.name,
                'inspection': result.inspection.toDiagnosticFields(),
                if (result.cleanup != null)
                  'cleanup': result.cleanup!.toDiagnosticFields(),
              },
            );
            if (!_isCurrent(revision) || !mounted) return;
            if (result.status == WindowsProxyRepairStatus.cleaned) {
              _showNotifier(currentAppLocalizations.systemProxyStaleCleaned);
            } else if (result.status ==
                WindowsProxyRepairStatus.cleanupFailed) {
              _showNotifier(
                currentAppLocalizations.systemProxyDisableFailed(
                  result.cleanup?.diagnosticCode ?? 'W-PROXY-09',
                ),
              );
            }
            return;
          }
          final result = await macOSGuard!.repairStale(
            proxyState.port,
            isCancelled: () => !_isCurrent(revision),
          );
          commonPrint.event(
            'system_proxy.startup_repair.completed',
            fields: {
              'platform': 'macos',
              'status': result.status.name,
              'inspection': result.inspection.toDiagnosticFields(),
              if (result.cleanup != null)
                'cleanup': result.cleanup!.toDiagnosticFields(),
            },
          );
          if (!_isCurrent(revision) || !mounted) return;
          if (result.status == MacOSProxyRepairStatus.cleaned) {
            _showNotifier(currentAppLocalizations.systemProxyStaleCleaned);
          } else if (result.status == MacOSProxyRepairStatus.cleanupFailed) {
            _showNotifier(
              currentAppLocalizations.systemProxyDisableFailed(
                result.cleanup?.diagnosticCode ?? 'W-PROXY-09',
              ),
            );
          }
        })
        .catchError((Object error) {
          commonPrint.event(
            'system_proxy.startup_repair.failed',
            fields: {
              'error_type': error.runtimeType.toString(),
              'error': '$error',
            },
          );
        });
  }

  @override
  void initState() {
    super.initState();
    _proxyClient = widget.proxyClient ?? proxy;
    _isWindows = widget.isWindows ?? system.isWindows;
    _isMacOS = widget.isMacOS ?? system.isMacOS;
    _windowsProxyGuard = widget.windowsProxyGuard;
    _macOSProxyGuard = widget.macOSProxyGuard;
    if (_isWindows && _proxyClient != null) {
      _windowsProxyGuard ??= WindowsProxyGuard(
        inspector: _proxyClient.inspectProxy,
        starter: _proxyClient.startProxyDetailed,
        stopper: (port) => _proxyClient.stopProxyDetailed(expectedPort: port),
      );
      systemProxyRefreshSignal.attach(_scheduleSystemProxyGuardCheck);
    }
    if (_isMacOS && _proxyClient != null) {
      _macOSProxyGuard ??= MacOSProxyGuard(
        inspector: _proxyClient.inspectProxy,
        starter: _proxyClient.startProxyDetailed,
        stopper: (port) => _proxyClient.stopProxyDetailed(expectedPort: port),
      );
      systemProxyRefreshSignal.attach(_scheduleSystemProxyGuardCheck);
    }
    ref.listenManual(proxyStateProvider, (prev, next) {
      if (prev != next) {
        if (prev == null && (_isWindows || _isMacOS) && !next.isStart) {
          _scheduleStartupRepair(next);
        } else {
          _scheduleUpdateProxy(next);
        }
      }
    }, fireImmediately: true);
  }

  @override
  void dispose() {
    _requestedRevision++;
    _stopMacOSProxyGuard();
    if (_isWindows || _isMacOS) systemProxyRefreshSignal.detach();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}

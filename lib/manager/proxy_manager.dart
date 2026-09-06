import 'package:fl_clash/common/app_localizations.dart';
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
  final bool? isWindows;
  final ValueChanged<String>? notify;
  final Widget child;

  const ProxyManager({
    super.key,
    this.proxyClient,
    this.windowsProxyGuard,
    this.isWindows,
    this.notify,
    required this.child,
  });

  @override
  ConsumerState createState() => _ProxyManagerState();
}

class _ProxyManagerState extends ConsumerState<ProxyManager> {
  Future<void> _pendingUpdate = Future.value();
  WindowsProxyGuard? _windowsProxyGuard;
  late final Proxy? _proxyClient;
  late final bool _isWindows;
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
      final guard = _windowsProxyGuard;
      if (guard != null) {
        final readiness = await guard.waitUntilReadyDetailed(
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
      if (result?.success == true && guard != null && _isCurrent(revision)) {
        try {
          final verification = await guard.verifyAfterApply(
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
    } else {
      result = await _proxyClient?.stopProxyDetailed(
        expectedPort: _isWindows ? port : null,
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
        _isWindows &&
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
    final guard = _windowsProxyGuard;
    if (guard == null) return;
    final revision = ++_requestedRevision;
    _pendingUpdate = _pendingUpdate
        .then((_) async {
          if (!_isCurrent(revision)) return;
          final result = await guard.repairStale(
            proxyState.port,
            isCancelled: () => !_isCurrent(revision),
          );
          commonPrint.event(
            'system_proxy.startup_repair.completed',
            fields: {
              'status': result.status.name,
              'inspection': result.inspection.toDiagnosticFields(),
              if (result.cleanup != null)
                'cleanup': result.cleanup!.toDiagnosticFields(),
            },
          );
          if (!_isCurrent(revision) || !mounted) return;
          if (result.status == WindowsProxyRepairStatus.cleaned) {
            _showNotifier(currentAppLocalizations.systemProxyStaleCleaned);
          } else if (result.status == WindowsProxyRepairStatus.cleanupFailed) {
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
    _windowsProxyGuard = widget.windowsProxyGuard;
    if (_isWindows && _proxyClient != null) {
      _windowsProxyGuard ??= WindowsProxyGuard(
        inspector: _proxyClient.inspectProxy,
        stopper: (port) => _proxyClient.stopProxyDetailed(expectedPort: port),
      );
    }
    ref.listenManual(proxyStateProvider, (prev, next) {
      if (prev != next) {
        if (prev == null && _isWindows && !next.isStart) {
          _scheduleStartupRepair(next);
        } else {
          _scheduleUpdateProxy(next);
        }
      }
    }, fireImmediately: true);
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}

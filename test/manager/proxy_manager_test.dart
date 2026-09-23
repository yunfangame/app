import 'dart:async';

import 'package:fl_clash/common/macos_proxy_guard.dart';
import 'package:fl_clash/common/proxy.dart'
    show systemProxyCleanupSignal, systemProxyRefreshSignal;
import 'package:fl_clash/common/windows_proxy_guard.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/l10n/l10n.dart';
import 'package:fl_clash/manager/proxy_manager.dart';
import 'package:fl_clash/models/models.dart'
    show NetworkProps, PatchClashConfig;
import 'package:fl_clash/providers/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:proxy/proxy.dart';

const _started = ProxyOperationResult(
  success: true,
  operation: 'start',
  stage: 'verified',
  enabled: true,
  server: '127.0.0.1:7890',
);
const _stopped = ProxyOperationResult(
  success: true,
  operation: 'stop',
  stage: 'verified',
  enabled: false,
);
const _writeFailure = ProxyOperationResult(
  success: false,
  operation: 'start',
  stage: 'registry_write',
  errorCode: 5,
);
const _stopFailure = ProxyOperationResult(
  success: false,
  operation: 'stop',
  stage: 'registry_write',
  errorCode: 5,
);
const _readbackFailure = ProxyOperationResult(
  success: false,
  operation: 'inspect',
  stage: 'readback_mismatch',
  enabled: false,
);
const _fallbackPending = ProxyOperationResult(
  success: true,
  operation: 'start',
  stage: 'fallback_pending',
  enabled: false,
  fallbackUsed: true,
);

class _ProxyClient extends Proxy {
  final startPorts = <int>[];
  final stopPorts = <int?>[];
  final events = <String>[];
  int inspections = 0;
  Future<ProxyOperationResult> Function(int port)? start;
  Future<ProxyOperationResult> Function(int? port)? stop;
  Object? inspectionError;
  ProxyOperationResult inspection = _started;

  @override
  Future<ProxyOperationResult> startProxyDetailed(
    int port, [
    List<String> bypassDomain = const [],
  ]) async {
    startPorts.add(port);
    events.add('start:$port');
    final result = await (start?.call(port) ?? Future.value(_started));
    events.add('started:$port');
    return result;
  }

  @override
  Future<ProxyOperationResult> stopProxyDetailed({int? expectedPort}) async {
    stopPorts.add(expectedPort);
    events.add('stop:$expectedPort');
    final result = await (stop?.call(expectedPort) ?? Future.value(_stopped));
    events.add('stopped:$expectedPort');
    return result;
  }

  @override
  Future<ProxyOperationResult> inspectProxy(int expectedPort) async {
    inspections++;
    final error = inspectionError;
    if (error != null) throw error;
    return inspection;
  }
}

class _Guard extends WindowsProxyGuard {
  _Guard(_ProxyClient client)
    : super(
        inspector: client.inspectProxy,
        starter: client.startProxyDetailed,
        stopper: (port) => client.stopProxyDetailed(expectedPort: port),
        verificationDelay: Duration.zero,
      );

  Future<WindowsProxyReadinessResult> Function(int port)? readiness;
  bool Function()? cancellation;

  @override
  Future<WindowsProxyReadinessResult> waitUntilReadyDetailed(
    int port, {
    bool Function()? isCancelled,
  }) async {
    cancellation = isCancelled;
    return readiness?.call(port) ??
        WindowsProxyReadinessResult(
          status: WindowsProxyReadinessStatus.ready,
          port: port,
          attempts: 1,
          elapsed: Duration.zero,
        );
  }
}

class _MacGuard extends MacOSProxyGuard {
  _MacGuard(_ProxyClient client)
    : super(
        inspector: client.inspectProxy,
        starter: client.startProxyDetailed,
        stopper: (port) => client.stopProxyDetailed(expectedPort: port),
        verificationDelay: Duration.zero,
      );

  @override
  Future<MacOSProxyReadinessResult> waitUntilReadyDetailed(
    int port, {
    bool Function()? isCancelled,
  }) async {
    return MacOSProxyReadinessResult(
      status: isCancelled?.call() == true
          ? MacOSProxyReadinessStatus.cancelled
          : MacOSProxyReadinessStatus.ready,
      port: port,
      attempts: 1,
      elapsed: Duration.zero,
    );
  }
}

class _Setup extends SetupAction {
  final requests = <bool>[];
  Completer<void>? stopCompletion;

  @override
  Future<void> setRunning(
    bool running, {
    bool initialize = false,
    bool propagateErrors = false,
  }) {
    requests.add(running);
    ref.read(runTimeProvider.notifier).value = running ? 1 : null;
    ref.read(connectionPendingProvider.notifier).value = false;
    return running ? Future.value() : stopCompletion?.future ?? Future.value();
  }
}

class _Rig {
  final client = _ProxyClient();
  late final guard = _Guard(client);
  late final macGuard = _MacGuard(client);
  final notifications = <String>[];
  late final ProviderContainer container;
  late final _Setup setup;

  Future<void> mount(
    WidgetTester tester, {
    bool tunRequested = false,
    bool tunAuthorized = false,
    bool isWindows = true,
    bool isMacOS = false,
    Duration macOSProxyGuardInterval = const Duration(seconds: 5),
  }) async {
    container = ProviderContainer(
      overrides: [
        networkSettingProvider.overrideWithBuild(
          (_, _) => const NetworkProps(systemProxy: true),
        ),
        patchClashConfigProvider.overrideWithBuild(
          (_, _) => const PatchClashConfig().copyWith.tun(enable: tunRequested),
        ),
        runTimeProvider.overrideWithBuild((_, _) => 1),
        authorizedTunEnableProvider.overrideWithBuild(
          (_, _) => tunAuthorized
              ? TunAuthorizationState.authorized
              : TunAuthorizationState.unauthorized,
        ),
        setupActionProvider.overrideWith(_Setup.new),
      ],
    );
    setup = container.read(setupActionProvider.notifier) as _Setup;
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox());
      container.dispose();
    });
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: ProxyManager(
            proxyClient: client,
            windowsProxyGuard: isWindows ? guard : null,
            macOSProxyGuard: isMacOS ? macGuard : null,
            isWindows: isWindows,
            isMacOS: isMacOS,
            macOSProxyGuardInterval: macOSProxyGuardInterval,
            notify: notifications.add,
            child: const SizedBox(),
          ),
        ),
      ),
    );
  }
}

void main() {
  setUpAll(() => AppLocalizations.load(const Locale('en')));

  testWidgets('unavailable loopback skips native enable and stops run state', (
    tester,
  ) async {
    final rig = _Rig();
    rig.guard.readiness = (port) async => WindowsProxyReadinessResult(
      status: WindowsProxyReadinessStatus.timedOut,
      port: port,
      attempts: 10,
      elapsed: const Duration(seconds: 5),
      lastErrorType: 'socket_exception',
      lastOsErrorCode: 10061,
    );

    await rig.mount(tester, tunRequested: true, tunAuthorized: true);
    await tester.pumpAndSettle();

    expect(rig.client.startPorts, isEmpty);
    expect(rig.setup.requests, [false]);
    expect(rig.container.read(runTimeProvider), isNull);
    expect(rig.container.read(networkSettingProvider).systemProxy, isFalse);
    expect(rig.notifications.single, contains('W-PROXY-02'));
  });

  testWidgets('native write failure without TUN stops and rolls back', (
    tester,
  ) async {
    final rig = _Rig();
    rig.client.start = (_) async => _writeFailure;

    await rig.mount(tester);
    await tester.pumpAndSettle();

    expect(rig.client.startPorts, [7890]);
    expect(rig.setup.requests, [false]);
    expect(rig.container.read(runTimeProvider), isNull);
    expect(rig.container.read(networkSettingProvider).systemProxy, isFalse);
    expect(rig.notifications.single, contains('W-PROXY-03'));
  });

  testWidgets('native failure preserves requested authorized TUN', (
    tester,
  ) async {
    final rig = _Rig();
    rig.client.start = (_) async => _writeFailure;

    await rig.mount(tester, tunRequested: true, tunAuthorized: true);
    await tester.pumpAndSettle();

    expect(rig.setup.requests, isEmpty);
    expect(rig.container.read(runTimeProvider), 1);
    expect(rig.container.read(networkSettingProvider).systemProxy, isFalse);
    expect(rig.client.stopPorts, [7890]);
  });

  testWidgets('requested but unauthorized TUN does not mask write failure', (
    tester,
  ) async {
    final rig = _Rig();
    rig.client.start = (_) async => _writeFailure;

    await rig.mount(tester, tunRequested: true);
    await tester.pumpAndSettle();

    expect(rig.setup.requests, [false]);
    expect(rig.container.read(runTimeProvider), isNull);
  });

  testWidgets('native write exception follows the failure rollback path', (
    tester,
  ) async {
    final rig = _Rig();
    rig.client.start = (_) async => throw StateError('native unavailable');

    await rig.mount(tester);
    await tester.pumpAndSettle();

    expect(rig.setup.requests, [false]);
    expect(rig.container.read(networkSettingProvider).systemProxy, isFalse);
    expect(rig.notifications.single, contains('W-PROXY-09'));
  });

  testWidgets('successful write still requires delayed native readback', (
    tester,
  ) async {
    final rig = _Rig();
    rig.client.inspection = _readbackFailure;

    await rig.mount(tester);
    await tester.pumpAndSettle();

    expect(rig.client.inspections, 1);
    expect(rig.setup.requests, [false]);
    expect(rig.notifications.single, contains('W-PROXY-04'));
  });

  testWidgets('successful write and readback keep the run state', (
    tester,
  ) async {
    final rig = _Rig();

    await rig.mount(tester);
    await tester.pumpAndSettle();

    expect(rig.client.startPorts, [7890]);
    expect(rig.client.inspections, 1);
    expect(rig.setup.requests, isEmpty);
    expect(rig.container.read(networkSettingProvider).systemProxy, isTrue);
    expect(rig.notifications, isEmpty);
  });

  testWidgets('native readback exception also stops and rolls back', (
    tester,
  ) async {
    final rig = _Rig();
    rig.client.inspectionError = StateError('readback unavailable');

    await rig.mount(tester);
    await tester.pumpAndSettle();

    expect(rig.client.inspections, 1);
    expect(rig.setup.requests, [false]);
    expect(rig.container.read(networkSettingProvider).systemProxy, isFalse);
    expect(rig.notifications.single, contains('W-PROXY-04'));
  });

  testWidgets('finishing failed-start cleanup cannot undo a newer start', (
    tester,
  ) async {
    final rig = _Rig();
    final firstWrite = Completer<ProxyOperationResult>();
    var starts = 0;
    rig.client.start = (_) =>
        ++starts == 1 ? firstWrite.future : Future.value(_started);

    await rig.mount(tester);
    await tester.pump();
    final cleanup = Completer<void>();
    rig.setup.stopCompletion = cleanup;
    firstWrite.complete(_writeFailure);
    await tester.pump();
    expect(rig.setup.requests, [false]);
    expect(rig.container.read(proxyStateProvider).isStart, isFalse);
    await rig.setup.setRunning(true);
    rig.container
        .read(networkSettingProvider.notifier)
        .update((value) => value.copyWith(systemProxy: true));
    expect(rig.container.read(proxyStateProvider).isStart, isTrue);
    await tester.pump();
    cleanup.complete();
    await tester.pumpAndSettle();

    expect(rig.setup.requests, [false, true]);
    expect(rig.client.startPorts, [7890, 7890]);
    expect(rig.container.read(runTimeProvider), 1);
    expect(rig.container.read(networkSettingProvider).systemProxy, isTrue);
    expect(rig.notifications, isEmpty);
  });

  testWidgets('failed start still notifies when stopping the core throws', (
    tester,
  ) async {
    final rig = _Rig();
    final firstWrite = Completer<ProxyOperationResult>();
    rig.client.start = (_) => firstWrite.future;
    await rig.mount(tester);
    await tester.pump();
    final cleanup = Completer<void>();
    rig.setup.stopCompletion = cleanup;

    firstWrite.complete(_writeFailure);
    await tester.pump();
    expect(rig.setup.requests, [false]);
    cleanup.completeError(StateError('core stop unavailable'));
    await tester.pumpAndSettle();

    expect(rig.container.read(runTimeProvider), isNull);
    expect(rig.container.read(networkSettingProvider).systemProxy, isFalse);
    expect(rig.notifications.single, contains('W-PROXY-03'));
  });

  testWidgets('late native failure cannot roll back a newer port request', (
    tester,
  ) async {
    final rig = _Rig();
    final firstWrite = Completer<ProxyOperationResult>();
    rig.client.start = (port) =>
        port == 7890 ? firstWrite.future : Future.value(_started);

    await rig.mount(tester);
    await tester.pump();
    expect(rig.client.startPorts, [7890]);
    rig.container
        .read(patchClashConfigProvider.notifier)
        .update((value) => value.copyWith(mixedPort: 7891));
    await tester.pump();
    firstWrite.complete(_writeFailure);
    await tester.pumpAndSettle();

    expect(rig.client.startPorts, [7890, 7891]);
    expect(rig.setup.requests, isEmpty);
    expect(rig.container.read(networkSettingProvider).systemProxy, isTrue);
    expect(rig.notifications, isEmpty);
  });

  testWidgets('stop during probe cannot write a proxy on late readiness', (
    tester,
  ) async {
    final rig = _Rig();
    final probe = Completer<WindowsProxyReadinessResult>();
    rig.guard.readiness = (_) => probe.future;

    await rig.mount(tester);
    await tester.pump();
    await rig.setup.setRunning(false);
    await tester.pump();
    expect(rig.guard.cancellation?.call(), isTrue);
    probe.complete(
      const WindowsProxyReadinessResult(
        status: WindowsProxyReadinessStatus.ready,
        port: 7890,
        attempts: 1,
        elapsed: Duration.zero,
      ),
    );
    await tester.pumpAndSettle();

    expect(rig.client.startPorts, isEmpty);
    expect(rig.setup.requests, [false]);
    expect(rig.notifications, isEmpty);
  });

  testWidgets('disposal discards a late native failure without mutation', (
    tester,
  ) async {
    final rig = _Rig();
    final write = Completer<ProxyOperationResult>();
    rig.client.start = (_) => write.future;

    await rig.mount(tester);
    await tester.pump();
    await tester.pumpWidget(const SizedBox());
    write.complete(_writeFailure);
    await tester.pump();

    expect(rig.setup.requests, isEmpty);
    expect(rig.container.read(runTimeProvider), 1);
    expect(rig.notifications, isEmpty);
  });

  testWidgets('non-Windows native failure retains previous run semantics', (
    tester,
  ) async {
    final rig = _Rig();
    rig.client.start = (_) async => _writeFailure;

    await rig.mount(tester, isWindows: false);
    await tester.pumpAndSettle();

    expect(rig.setup.requests, isEmpty);
    expect(rig.container.read(runTimeProvider), 1);
    expect(rig.container.read(networkSettingProvider).systemProxy, isFalse);
  });

  testWidgets('macOS native failure rolls back the requested run state', (
    tester,
  ) async {
    final rig = _Rig();
    rig.client.start = (_) async => _writeFailure;

    await rig.mount(tester, isWindows: false, isMacOS: true);
    await tester.pumpAndSettle();

    expect(rig.client.startPorts, [7890]);
    expect(rig.setup.requests, [false]);
    expect(rig.container.read(runTimeProvider), isNull);
    expect(rig.container.read(networkSettingProvider).systemProxy, isFalse);
  });

  testWidgets('macOS network signal reapplies an overwritten system proxy', (
    tester,
  ) async {
    final rig = _Rig();
    rig.client.start = (_) async {
      rig.client.inspection = _started;
      return _started;
    };

    await rig.mount(tester, isWindows: false, isMacOS: true);
    await tester.pumpAndSettle();
    rig.client.inspection = _readbackFailure;
    await systemProxyRefreshSignal.request();
    await tester.pump();

    expect(rig.client.startPorts, [7890, 7890]);
    expect(rig.client.inspections, greaterThanOrEqualTo(2));
    expect(rig.container.read(networkSettingProvider).systemProxy, isTrue);
  });

  testWidgets('Windows network signal reapplies an overwritten system proxy', (
    tester,
  ) async {
    final rig = _Rig();
    rig.client.start = (_) async {
      rig.client.inspection = _started;
      return _started;
    };

    await rig.mount(tester);
    await tester.pumpAndSettle();
    rig.client.inspection = _readbackFailure;
    await systemProxyRefreshSignal.request();
    await tester.pump();

    expect(rig.client.startPorts, [7890, 7890]);
    expect(rig.client.inspections, greaterThanOrEqualTo(3));
    expect(rig.container.read(networkSettingProvider).systemProxy, isTrue);
  });

  testWidgets(
    'failed native disable still notifies without stopping the core',
    (tester) async {
      final rig = _Rig();
      await rig.mount(tester);
      await tester.pumpAndSettle();
      rig.client.stop = (_) async => _stopFailure;

      rig.container
          .read(networkSettingProvider.notifier)
          .update((state) => state.copyWith(systemProxy: false));
      await tester.pumpAndSettle();

      expect(rig.client.stopPorts, [7890]);
      expect(rig.setup.requests, isEmpty);
      expect(rig.container.read(runTimeProvider), 1);
      expect(rig.container.read(networkSettingProvider).systemProxy, isFalse);
      expect(rig.notifications, [
        AppLocalizations.current.systemProxyDisableFailed(
          _stopFailure.diagnosticCode,
        ),
      ]);
    },
  );

  testWidgets(
    'cancelled queued cleanup cannot stop an in-flight native apply',
    (tester) async {
      final rig = _Rig();
      final write = Completer<ProxyOperationResult>();
      rig.client.start = (_) => write.future;
      await rig.mount(tester, isWindows: false, isMacOS: true);
      await tester.pump();
      expect(rig.client.events, ['start:7890']);
      var cancelled = false;
      final cleanup = systemProxyCleanupSignal.request(
        7890,
        isCancelled: () => cancelled,
      );
      await tester.pump();
      expect(rig.client.stopPorts, isEmpty);

      cancelled = true;
      write.complete(_started);
      await tester.pumpAndSettle();
      await cleanup;

      expect(rig.client.events, ['start:7890', 'started:7890']);
      expect(rig.client.stopPorts, isEmpty);
      expect(rig.container.read(networkSettingProvider).systemProxy, isTrue);
      expect(rig.notifications, isEmpty);
    },
  );

  testWidgets('newer proxy revision discards an older queued cleanup', (
    tester,
  ) async {
    final rig = _Rig();
    final firstWrite = Completer<ProxyOperationResult>();
    rig.client.start = (port) =>
        port == 7890 ? firstWrite.future : Future.value(_started);
    await rig.mount(tester, isWindows: false, isMacOS: true);
    await tester.pump();
    final cleanup = systemProxyCleanupSignal.request(
      7890,
      isCancelled: () => false,
    );
    rig.container
        .read(patchClashConfigProvider.notifier)
        .update((state) => state.copyWith(mixedPort: 7891));
    await tester.pump();

    firstWrite.complete(_started);
    await tester.pumpAndSettle();

    expect(await cleanup, isFalse);
    expect(rig.client.startPorts, [7890, 7891]);
    expect(rig.client.stopPorts, isEmpty);
    expect(rig.notifications, isEmpty);
  });

  testWidgets('new start waits for an active native cleanup to finish', (
    tester,
  ) async {
    final rig = _Rig();
    await rig.mount(tester, isWindows: false, isMacOS: true);
    await tester.pumpAndSettle();
    final stop = Completer<ProxyOperationResult>();
    rig.client.stop = (_) => stop.future;
    final cleanup = systemProxyCleanupSignal.request(
      7890,
      isCancelled: () => false,
    );
    await tester.pump();
    expect(rig.client.events, ['start:7890', 'started:7890', 'stop:7890']);

    await rig.setup.setRunning(false);
    await tester.pump();
    await rig.setup.setRunning(true);
    await tester.pump();
    expect(rig.client.startPorts, [7890]);
    expect(rig.client.stopPorts, [7890]);

    stop.complete(_stopped);
    await tester.pumpAndSettle();
    await cleanup;

    expect(rig.client.events, [
      'start:7890',
      'started:7890',
      'stop:7890',
      'stopped:7890',
      'start:7890',
      'started:7890',
    ]);
    expect(rig.container.read(runTimeProvider), 1);
    expect(rig.container.read(networkSettingProvider).systemProxy, isTrue);
    expect(rig.notifications, isEmpty);
  });

  for (final throws in [false, true]) {
    testWidgets('cleanup failure releases queue: throws=$throws', (
      tester,
    ) async {
      final rig = _Rig();
      await rig.mount(tester, isWindows: false, isMacOS: true);
      await tester.pumpAndSettle();
      rig.client.stop = (_) async {
        if (throws) throw StateError('native cleanup unavailable');
        return _stopFailure;
      };
      final cleanup = systemProxyCleanupSignal.request(
        7890,
        isCancelled: () => false,
      );
      final outcome = throws
          ? expectLater(cleanup, throwsStateError)
          : expectLater(cleanup, completion(isFalse));
      await tester.pumpAndSettle();
      await outcome;
      expect(rig.client.stopPorts, [7890]);

      rig.client.stop = null;
      rig.container
          .read(patchClashConfigProvider.notifier)
          .update((state) => state.copyWith(mixedPort: 7891));
      await tester.pumpAndSettle();

      expect(rig.client.startPorts, [7890, 7891]);
      expect(rig.container.read(runTimeProvider), 1);
      expect(rig.container.read(networkSettingProvider).systemProxy, isTrue);
    });
  }

  testWidgets('macOS fallback stays armed while no primary network exists', (
    tester,
  ) async {
    final rig = _Rig();
    rig.client.start = (_) async => _fallbackPending;
    rig.client.inspection = _readbackFailure;

    await rig.mount(tester, isWindows: false, isMacOS: true);
    await tester.pumpAndSettle();

    expect(rig.client.startPorts, [7890]);
    expect(rig.setup.requests, isEmpty);
    expect(rig.container.read(runTimeProvider), 1);
    expect(rig.container.read(networkSettingProvider).systemProxy, isTrue);
  });
}

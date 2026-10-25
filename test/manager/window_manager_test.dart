import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:fl_clash/common/api_health.dart';
import 'package:fl_clash/common/render.dart';
import 'package:fl_clash/common/xboard_tickets.dart';
import 'package:fl_clash/common/xboard_auth.dart';
import 'package:fl_clash/common/xboard_marquee.dart';
import 'package:fl_clash/manager/window_manager.dart';
import 'package:fl_clash/models/config.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _saved = WindowProps(left: 3020, top: 181, width: 1280, height: 720);
const _recovered = WindowProps(left: 120, top: 80, width: 1180, height: 680);

Map<String, double> _bounds(WindowProps props) => {
  'x': props.left!,
  'y': props.top!,
  'width': props.width,
  'height': props.height,
};

class _SystemAction extends SystemAction {
  int refreshCalls = 0;
  int closeCalls = 0;
  Future<void> Function()? onClose;

  @override
  Future<void> refreshAutoLaunch() async {
    refreshCalls++;
  }

  @override
  Future<void> handleClose([bool exit = true]) async {
    closeCalls++;
    await onClose?.call();
  }
}

class _StoreAction extends StoreAction {
  int saveCalls = 0;

  @override
  void savePreferencesDebounce() {
    saveCalls++;
  }
}

class _Rig {
  final tickets = XboardTicketController();
  late final marquee = XboardMarqueeController(
    api: XboardMarqueeApi(
      unreadRequester: (_, _, _) async {
        marqueeCalls++;
        return {
          'status': 1,
          'data': {'items': []},
        };
      },
    ),
  );
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  late final ProviderContainer container;
  late final _SystemAction action;
  late final _StoreAction store;
  int boundsReads = 0;
  int marqueeCalls = 0;
  bool visible = true;
  bool minimized = false;
  bool focused = true;
  bool readStateFails = false;
  int stateReads = 0;
  Future<Map<String, double>> Function()? readBounds;
  Future<bool> Function()? readFocus;

  Future<void> mount(WidgetTester tester, {bool isWindows = true}) async {
    const windowChannel = MethodChannel('window_manager');
    const extensionChannel = MethodChannel('window_ext');
    binding.defaultBinaryMessenger.setMockMethodCallHandler(windowChannel, (
      call,
    ) async {
      if (call.method == 'isVisible') stateReads++;
      if (readStateFails &&
          {'isVisible', 'isMinimized', 'isFocused'}.contains(call.method)) {
        throw PlatformException(code: 'temporary_window_state');
      }
      if (call.method == 'isVisible') return visible;
      if (call.method == 'isMinimized') return minimized;
      if (call.method == 'isFocused') return readFocus?.call() ?? focused;
      if (call.method != 'getBounds') return null;
      boundsReads++;
      return readBounds?.call() ?? Future.value(_bounds(_recovered));
    });
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      extensionChannel,
      (call) async => null,
    );
    container = ProviderContainer(
      overrides: [
        windowSettingProvider.overrideWithBuild((_, _) => _saved),
        systemActionProvider.overrideWith(_SystemAction.new),
        storeActionProvider.overrideWith(_StoreAction.new),
      ],
    );
    action = container.read(systemActionProvider.notifier) as _SystemAction;
    store = container.read(storeActionProvider.notifier) as _StoreAction;
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox());
      tickets.dispose();
      marquee.dispose();
      render?.resume();
      container.dispose();
      binding.defaultBinaryMessenger.setMockMethodCallHandler(
        windowChannel,
        null,
      );
      binding.defaultBinaryMessenger.setMockMethodCallHandler(
        extensionChannel,
        null,
      );
    });
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: WindowManager(
          isWindows: isWindows,
          ticketController: tickets,
          marqueeController: marquee,
          child: const SizedBox(),
        ),
      ),
    );
  }

  Future<void> emit(String eventName) async {
    await binding.defaultBinaryMessenger.handlePlatformMessage(
      'window_manager',
      const StandardMethodCodec().encodeMethodCall(
        MethodCall('onEvent', {'eventName': eventName}),
      ),
      (_) {},
    );
  }
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    ApiHealthService.setAppForeground(true);
    ApiHealthService.setWindowForeground(true);
  });
  tearDown(() {
    ApiHealthService.setAppForeground(true);
    ApiHealthService.setWindowForeground(true);
  });

  testWidgets('temporary initial state failure retries and resumes marquee', (
    tester,
  ) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    final rig = _Rig()..readStateFails = true;
    await rig.mount(tester, isWindows: false);
    rig.marquee.startPolling(foreground: true, offline: false);
    try {
      final endpoint = Uri.parse('https://api.example.com');
      await rig.marquee.updateSession(
        XboardLoginResult(
          endpoint: endpoint,
          token: 'retry-fixture',
          authData: 'retry-fixture-auth',
          isAdmin: false,
          subscription: XboardSubscriptionData(
            endpoint: endpoint,
            subscribeUrl: null,
            uploadBytes: 0,
            downloadBytes: 0,
            transferEnableBytes: 100,
            rawData: const {},
          ),
        ),
        offline: false,
      );
      expect(rig.stateReads, 1);
      expect(rig.marqueeCalls, 0);
      rig.readStateFails = false;
      await tester.pump(const Duration(milliseconds: 999));
      expect(rig.stateReads, 1);
      await tester.pump(const Duration(milliseconds: 1));
      await tester.pump(Duration.zero);
      expect(rig.stateReads, 2);
      expect(rig.marqueeCalls, 1);
    } finally {
      rig.marquee.stopPolling();
    }
  });

  testWidgets('window state retries use a bounded budget reset by show', (
    tester,
  ) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    final rig = _Rig()..readStateFails = true;
    await rig.mount(tester, isWindows: false);
    var reads = 1;
    for (final seconds in [1, 3, 6, 12]) {
      await tester.pump(Duration(seconds: seconds));
      expect(rig.stateReads, ++reads);
    }
    await tester.pump(const Duration(hours: 1));
    expect(rig.stateReads, 5);
    await rig.emit('show');
    await tester.pump(Duration.zero);
    expect(rig.stateReads, 6);
    rig.readStateFails = false;
    await tester.pump(const Duration(seconds: 1));
    expect(rig.stateReads, 7);
    expect(rig.marquee.isForeground, isTrue);
  });

  for (final event in ['hide', 'blur', 'minimize']) {
    testWidgets('known window $event cancels native state retries', (
      tester,
    ) async {
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      final rig = _Rig()..readStateFails = true;
      await rig.mount(tester, isWindows: false);
      await rig.emit(event);
      await tester.pump(const Duration(hours: 1));
      expect(rig.stateReads, 1);
      expect(rig.marquee.isForeground, isFalse);
    });
  }

  testWidgets('native state retry waits for foreground app lifecycle', (
    tester,
  ) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    final rig = _Rig()..readStateFails = true;
    await rig.mount(tester, isWindows: false);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    try {
      await tester.pump(const Duration(seconds: 1));
      expect(rig.stateReads, 1);
      rig.readStateFails = false;
    } finally {
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    }
    await tester.pump(Duration.zero);
    expect(rig.stateReads, 2);
    expect(rig.marquee.isForeground, isTrue);
  });

  testWidgets(
    'automatic queries wait for fresh window verification on resume',
    (tester) async {
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      final initial = Completer<bool>();
      final rig = _Rig()..readFocus = () => initial.future;
      await rig.mount(tester, isWindows: false);
      expect(ApiHealthService.automaticRequestsAvailable, isFalse);
      initial.complete(true);
      await tester.pump();
      expect(ApiHealthService.automaticRequestsAvailable, isTrue);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      expect(ApiHealthService.automaticRequestsAvailable, isFalse);
      final pending = Completer<bool>();
      rig.readFocus = () => pending.future;
      rig.visible = false;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(ApiHealthService.automaticRequestsAvailable, isFalse);
      var requests = 0;
      final service = ApiHealthService(
        configUrl: 'https://config.example/resume-gate',
        configLoader: (_) async {
          requests++;
          return {
            'Authentication': 'FengWo',
            'hosts': ['https://api.example.com'],
          };
        },
        endpointProbe: (_) async => true,
      );
      expect((await service.check(forceRefresh: false)).isDeferred, isTrue);
      pending.complete(false);
      await tester.pump();
      expect((await service.check(forceRefresh: false)).isDeferred, isTrue);
      expect(requests, 0);
      await tester.pumpWidget(const SizedBox());
      expect(ApiHealthService.automaticRequestsAvailable, isFalse);
    },
  );

  testWidgets('disposing cancels native state retry', (tester) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    final rig = _Rig()..readStateFails = true;
    await rig.mount(tester, isWindows: false);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(hours: 1));
    expect(rig.stateReads, 1);
  });

  for (final isWindows in [true, false]) {
    testWidgets(
      'desktop $isWindows gates marquee on verified window activity',
      (tester) async {
        final rig = _Rig()..visible = false;
        await rig.mount(tester, isWindows: isWindows);
        final endpoint = Uri.parse('https://api.example.com');
        await rig.marquee.updateSession(
          XboardLoginResult(
            endpoint: endpoint,
            token: 'fixture',
            authData: 'fixture-auth',
            isAdmin: false,
            subscription: XboardSubscriptionData(
              endpoint: endpoint,
              subscribeUrl: null,
              uploadBytes: 0,
              downloadBytes: 0,
              transferEnableBytes: 100,
              rawData: const {},
            ),
          ),
          offline: false,
        );
        await rig.marquee.refresh(force: true);
        expect(rig.marqueeCalls, 0);
        rig.focused = false;
        rig.visible = true;
        await rig.emit('show');
        await tester.pump();
        await rig.marquee.refresh(force: true);
        expect(rig.marqueeCalls, 0);
        rig.focused = true;
        await rig.emit('focus');
        await rig.marquee.refresh(force: true);
        expect(rig.marqueeCalls, 1);
        final staleFocus = Completer<bool>();
        rig.readFocus = () => staleFocus.future;
        await rig.emit('show');
        await rig.emit('hide');
        staleFocus.complete(true);
        await tester.pump();
        await rig.marquee.refresh(force: true);
        expect(rig.marqueeCalls, 1);
        rig.readFocus = null;
        rig.visible = false;
        await rig.emit('restore');
        await tester.pump();
        await rig.marquee.refresh(force: true);
        expect(rig.marqueeCalls, 1);
        rig.visible = true;
        await rig.emit('show');
        await tester.pump();
        await rig.marquee.refresh(force: true);
        expect(rig.marqueeCalls, 2);
        await rig.emit('blur');
        await rig.marquee.refresh(force: true);
        expect(rig.marqueeCalls, 2);
      },
    );

    testWidgets(
      'desktop $isWindows defers config refresh until focused and visible',
      (tester) async {
        final rig = _Rig();
        await rig.mount(tester, isWindows: isWindows);
        var requests = 0;
        final service = ApiHealthService(
          configUrl: 'https://config.example/window',
          configCacheTtl: Duration.zero,
          diagnosticRecorder: (_, _) {},
          configLoader: (_) async {
            requests++;
            return {
              'Authentication': 'FengWo',
              'hosts': ['https://api.example.com'],
            };
          },
        );
        await service.loadConfig();
        expect(requests, 1);
        rig.visible = false;
        rig.focused = false;
        await rig.emit('hide');
        await service.loadConfig();
        await service.loadVerifiedCandidateEndpoints();
        await tester.pump();
        expect(requests, 1);
        await rig.emit('restore');
        await tester.pump();
        expect(requests, 1);
        rig.visible = true;
        await rig.emit('show');
        await tester.pump();
        expect(requests, 1);
        rig.focused = true;
        await rig.emit('focus');
        await tester.pump();
        expect(requests, 2);
        await rig.emit('blur');
        await service.loadConfig();
        await tester.pump();
        expect(requests, 2);
        await rig.emit('focus');
        await tester.pump();
        expect(requests, 3);
      },
    );

    testWidgets(
      'desktop $isWindows pauses ticket polling when hidden or blurred',
      (tester) async {
        final rig = _Rig();
        await rig.mount(tester, isWindows: isWindows);
        await rig.emit('hide');
        expect(rig.tickets.isForeground, isFalse);
        rig.tickets.setForeground(true);
        expect(rig.tickets.isForeground, isFalse);
        await rig.emit('focus');
        expect(rig.tickets.isForeground, isTrue);
        await rig.emit('minimize');
        expect(rig.tickets.isForeground, isFalse);
        await rig.emit('restore');
        expect(rig.tickets.isForeground, isTrue);
        await rig.emit('blur');
        expect(rig.tickets.isForeground, isFalse);
        rig.tickets.setForeground(false);
        await rig.emit('focus');
        expect(rig.tickets.isForeground, isFalse);
        rig.tickets.setForeground(true);
        expect(rig.tickets.isForeground, isTrue);
      },
    );
  }

  testWidgets('Windows close waits for its diagnostic to reach disk', (
    tester,
  ) async {
    final rig = _Rig();
    await rig.mount(tester);
    final directory = await tester.runAsync(
      () => Directory.systemTemp.createTemp('fengwo-window-close-'),
    );
    const pathChannel = MethodChannel('plugins.flutter.io/path_provider');
    addTearDown(() async {
      rig.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        pathChannel,
        null,
      );
      await directory!.delete(recursive: true);
    });
    await tester.runAsync(() async {
      final pathRequested = Completer<void>();
      final pathReady = Completer<String>();
      final closeCompleted = Completer<void>();
      rig.binding.defaultBinaryMessenger.setMockMethodCallHandler(pathChannel, (
        call,
      ) async {
        expect(call.method, 'getApplicationSupportDirectory');
        if (!pathRequested.isCompleted) pathRequested.complete();
        return pathReady.future;
      });
      rig.action.onClose = () async {
        final lines = await File(
          '${directory!.path}/diagnostics/events.jsonl',
        ).readAsLines();
        final entries = lines
            .map((line) => jsonDecode(line) as Map<String, dynamic>)
            .toList();
        expect(entries.last['event'], 'window.close.requested');
        closeCompleted.complete();
      };

      await rig.emit('close');
      await pathRequested.future.timeout(const Duration(seconds: 3));
      expect(rig.action.closeCalls, 0);
      pathReady.complete(directory!.path);
      await closeCompleted.future.timeout(const Duration(seconds: 3));
    });

    expect(rig.action.closeCalls, 1);
  });

  testWidgets('other platforms retain the direct close callback', (
    tester,
  ) async {
    final rig = _Rig();
    await rig.mount(tester, isWindows: false);

    await rig.emit('close');
    await tester.pump();

    expect(rig.action.closeCalls, 1);
  });

  testWidgets(
    'Windows show persists the current programmatically moved bounds',
    (tester) async {
      final rig = _Rig();
      await rig.mount(tester);

      await rig.emit('show');
      await tester.pumpAndSettle();

      expect(rig.boundsReads, 1);
      expect(rig.container.read(windowSettingProvider), _recovered);
    },
  );

  testWidgets(
    'Windows show and focus coalesce a read and preserve auto launch refresh',
    (tester) async {
      final rig = _Rig();
      await rig.mount(tester);

      await rig.emit('show');
      await rig.emit('focus');
      await tester.pumpAndSettle();

      expect(rig.boundsReads, 1);
      expect(rig.action.refreshCalls, 1);
      expect(rig.container.read(windowSettingProvider), _recovered);
    },
  );

  testWidgets('other platforms do not resave bounds on show or focus', (
    tester,
  ) async {
    final rig = _Rig();
    await rig.mount(tester, isWindows: false);

    await rig.emit('show');
    await rig.emit('focus');
    await tester.pumpAndSettle();

    expect(rig.boundsReads, 0);
    expect(rig.action.refreshCalls, 1);
    expect(rig.container.read(windowSettingProvider), _saved);
  });

  testWidgets('a failed bounds read keeps the previous saved position', (
    tester,
  ) async {
    final rig = _Rig();
    rig.readBounds = () async => throw PlatformException(code: 'windowClosed');
    await rig.mount(tester);

    await rig.emit('show');
    await tester.pumpAndSettle();

    expect(rig.container.read(windowSettingProvider), _saved);
    expect(tester.takeException(), isNull);
  });

  testWidgets('invalid native bounds do not replace saved window settings', (
    tester,
  ) async {
    final rig = _Rig();
    rig.readBounds = () async => {'x': 0, 'y': 0, 'width': 0, 'height': 0};
    await rig.mount(tester);

    await rig.emit('show');
    await tester.pumpAndSettle();

    expect(rig.container.read(windowSettingProvider), _saved);
  });

  testWidgets('hiding after a show event cancels the pending bounds update', (
    tester,
  ) async {
    final rig = _Rig();
    await rig.mount(tester);

    await rig.emit('show');
    rig.visible = false;
    await rig.emit('hide');
    await tester.pumpAndSettle();

    expect(rig.boundsReads, 0);
    expect(rig.container.read(windowSettingProvider), _saved);
  });

  testWidgets('minimizing after show preserves bounds and preference saving', (
    tester,
  ) async {
    final rig = _Rig();
    await rig.mount(tester);

    await rig.emit('show');
    rig.minimized = true;
    await rig.emit('minimize');
    render?.resume();
    await tester.pumpAndSettle();

    expect(rig.boundsReads, 0);
    expect(rig.store.saveCalls, 1);
    expect(rig.container.read(windowSettingProvider), _saved);
  });

  testWidgets(
    'a minimized native window is not read before its event arrives',
    (tester) async {
      final rig = _Rig();
      await rig.mount(tester);

      await rig.emit('show');
      rig.minimized = true;
      await tester.pumpAndSettle();

      expect(rig.boundsReads, 0);
      expect(rig.container.read(windowSettingProvider), _saved);
    },
  );

  testWidgets(
    'hiding while bounds are read cannot save transient coordinates',
    (tester) async {
      final rig = _Rig();
      final completion = Completer<Map<String, double>>();
      rig.readBounds = () => completion.future;
      await rig.mount(tester);

      await rig.emit('show');
      await tester.pump(const Duration(milliseconds: 100));
      expect(rig.boundsReads, 1);
      rig.visible = false;
      completion.complete(_bounds(_saved.copyWith(left: -32000, top: -32000)));
      await tester.pumpAndSettle();

      expect(rig.container.read(windowSettingProvider), _saved);
    },
  );

  testWidgets('disposing the manager cancels the scheduled bounds read', (
    tester,
  ) async {
    final rig = _Rig();
    await rig.mount(tester);

    await rig.emit('show');
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();

    expect(rig.boundsReads, 0);
    expect(rig.container.read(windowSettingProvider), _saved);
  });

  testWidgets(
    'a completed bounds request cannot write after manager disposal',
    (tester) async {
      final rig = _Rig();
      final completion = Completer<Map<String, double>>();
      rig.readBounds = () => completion.future;
      await rig.mount(tester);

      await rig.emit('show');
      await tester.pump(const Duration(milliseconds: 100));
      expect(rig.boundsReads, 1);
      await tester.pumpWidget(const SizedBox());
      completion.complete(_bounds(_recovered));
      await tester.pumpAndSettle();

      expect(rig.container.read(windowSettingProvider), _saved);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'a newer focus event prevents an old bounds response being saved',
    (tester) async {
      final rig = _Rig();
      final stale = Completer<Map<String, double>>();
      rig.readBounds = () => rig.boundsReads == 1
          ? stale.future
          : Future.value(_bounds(_recovered));
      await rig.mount(tester);

      await rig.emit('show');
      await tester.pump(const Duration(milliseconds: 100));
      expect(rig.boundsReads, 1);
      await rig.emit('focus');
      await tester.pumpAndSettle();
      expect(rig.container.read(windowSettingProvider), _recovered);
      stale.complete(_bounds(_saved));
      await tester.pumpAndSettle();

      expect(rig.boundsReads, 2);
      expect(rig.container.read(windowSettingProvider), _recovered);
    },
  );
}

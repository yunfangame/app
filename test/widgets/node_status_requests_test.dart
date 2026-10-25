import 'dart:async';

import 'package:fl_clash/common/api_health.dart';
import 'package:fl_clash/common/xboard_api_request.dart';
import 'package:fl_clash/common/theme.dart';
import 'package:fl_clash/common/xboard_auth.dart';
import 'package:fl_clash/common/xboard_nodes_snapshot.dart';
import 'package:fl_clash/common/measure.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/l10n/l10n.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/state.dart';
import 'package:fl_clash/views/proxies/fengwo_node_status.dart';
import 'package:fl_clash/widgets/inherited.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'leaving the node page discards its automatic response and returning reads once',
    (tester) async {
      final session = _session('account');
      globalState.activateXboardSession(session);
      globalState.xboardNodes = [_node('existing')];
      final old = Completer<List<XboardNodeData>>();
      final service = _NodesService()
        ..loader = (call) async => call == 1 ? old.future : [_node('returned')];
      final activity = await _mount(tester, service);
      expect(service.calls, 1);
      activity.value = false;
      await _flush(tester);
      old.complete([_node('departed')]);
      await _flush(tester);
      expect(globalState.xboardNodes.single.name, 'existing');
      expect(globalState.xboardNodesStatusFresh, isTrue);
      activity.value = true;
      await _flush(tester);
      expect(service.calls, 2);
      expect(globalState.xboardNodes.single.name, 'returned');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('pause and resume cannot revive an old automatic node read', (
    tester,
  ) async {
    globalState.activateXboardSession(_session('account'));
    final old = Completer<List<XboardNodeData>>();
    final service = _NodesService()
      ..loader = (call) async => call == 1 ? old.future : [_node('resumed')];
    await _mount(tester, service);
    ApiHealthService.setAppForeground(false);
    ApiHealthService.setAppForeground(true);
    ApiHealthService.setWindowForeground(false);
    ApiHealthService.setWindowForeground(true);
    await _flush(tester);
    expect(service.calls, 2);
    old.complete([_node('old activity')]);
    await _flush(tester);
    expect(service.calls, 2);
    expect(globalState.xboardNodes.single.name, 'resumed');
    expect(globalState.xboardNodesStatusFresh, isTrue);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'login node fetch survives a page leaving and returning uses its shared cache',
    (tester) async {
      final session = _session('account');
      globalState.activateXboardSession(session);
      final response = Completer<List<XboardNodeData>>();
      final loginService = _NodesService()..loader = (_) => response.future;
      final pageService = _NodesService();
      final login = globalState.loadXboardNodesSnapshot(loginService, session);
      final activity = await _mount(tester, pageService);
      activity.value = false;
      await _flush(tester);
      response.complete([_node('login')]);
      await login;
      await _flush(tester);
      expect(globalState.xboardNodes.single.name, 'login');
      activity.value = true;
      await _flush(tester);
      expect(loginService.calls, 1);
      expect(pageService.calls, 0);
      expect(globalState.xboardNodesStatusFresh, isTrue);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'repeated node delay tests do not add metadata HTTP while the snapshot is fresh',
    (tester) async {
      final session = _session('account');
      globalState.activateXboardSession(session);
      final service = _NodesService()
        ..loader = (_) async => [_node('Node A', online: false)];
      await globalState.loadXboardNodesSnapshot(service, session);
      await _mount(tester, service);
      for (var test = 0; test < 2; test++) {
        await tester.tap(
          find.byKey(const ValueKey('fengwo-node-status-refresh')),
        );
        await _flush(tester);
        expect(service.calls, 1);
      }
      await tester.pumpWidget(const SizedBox());
    },
  );

  setUp(() {
    globalState.clearXboardSession();
    globalState.setOfflineMode(false);
    globalState.refreshXboardNodes = null;
    ApiHealthService.setAppForeground(true);
    ApiHealthService.setWindowForeground(true);
    ApiHealthService.setOffline(false);
    ApiHealthService.networkChanged();
  });

  tearDown(() {
    globalState.clearXboardSession();
    globalState.setOfflineMode(false);
    globalState.refreshXboardNodes = null;
    ApiHealthService.setAppForeground(true);
    ApiHealthService.setWindowForeground(true);
    ApiHealthService.setOffline(false);
    ApiHealthService.networkChanged();
  });

  testWidgets('node entry reuses login metadata without an automatic timer', (
    tester,
  ) async {
    final session = _session('account');
    globalState.activateXboardSession(session);
    final service = _NodesService();
    await globalState.loadXboardNodesSnapshot(service, session);
    final active = await _mount(tester, service);
    expect(service.calls, 1);
    active.value = false;
    await _flush(tester);
    active.value = true;
    await _flush(tester);
    expect(service.calls, 1);
    await tester.pump(const Duration(hours: 1));
    expect(service.calls, 1);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('focus and page return do not create a read after cache expiry', (
    tester,
  ) async {
    final session = _session('account');
    globalState.activateXboardSession(session);
    var now = DateTime.utc(2026, 10, 25);
    final cache = XboardNodesSnapshotCache(now: () => now);
    final service = _NodesService();
    var loads = 0;
    Future<List<XboardNodeData>> load(
      XboardAuthService service,
      XboardLoginResult session,
    ) {
      loads++;
      return cache.load(
        session: session,
        epoch: globalState.xboardSessionRevision,
        loader: () => service.fetchNodes(
          endpoint: session.endpoint,
          authData: session.authData,
          userToken: session.token,
          secureSubscription: session.secureSubscription,
        ),
      );
    }

    final active = await _mount(tester, service, nodesLoader: load);
    expect(loads, 1);
    expect(service.calls, 1);
    now = now.add(const Duration(minutes: 1));
    active.value = false;
    await _flush(tester);
    active.value = true;
    ApiHealthService.setAppForeground(false);
    ApiHealthService.setAppForeground(true);
    ApiHealthService.setWindowForeground(false);
    ApiHealthService.setWindowForeground(true);
    ApiHealthService.networkChanged();
    await _flush(tester);
    expect(loads, 1);
    expect(service.calls, 1);
    await load(service, session);
    expect(service.calls, 2);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'node entry joins an in-flight login request across service instances',
    (tester) async {
      final session = _session('account');
      globalState.activateXboardSession(session);
      final response = Completer<List<XboardNodeData>>();
      final login = _NodesService()..loader = (_) => response.future;
      final page = _NodesService();
      final pending = globalState.loadXboardNodesSnapshot(login, session);
      await _mount(tester, page);
      expect(login.calls, 1);
      expect(page.calls, 0);
      response.complete([_node('login')]);
      await pending;
      await _flush(tester);
      expect(globalState.xboardNodes.single.name, 'login');
      expect(page.calls, 0);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'hidden page and background pause one automatic intent until active',
    (tester) async {
      globalState.activateXboardSession(_session('account'));
      ApiHealthService.setAppForeground(false);
      final service = _NodesService();
      final active = await _mount(tester, service, active: false);
      expect(service.calls, 0);
      active.value = true;
      await _flush(tester);
      expect(service.calls, 0);
      ApiHealthService.setAppForeground(true);
      await _flush(tester);
      expect(service.calls, 1);
      ApiHealthService.setAppForeground(false);
      ApiHealthService.setAppForeground(true);
      await _flush(tester);
      expect(service.calls, 1);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'window verification gate prevents automatic reads until confirmed',
    (tester) async {
      globalState.activateXboardSession(_session('account'));
      ApiHealthService.setWindowForeground(false);
      final service = _NodesService();
      await _mount(tester, service);
      expect(service.calls, 0);
      ApiHealthService.setWindowForeground(true);
      await _flush(tester);
      expect(service.calls, 1);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('offline entry waits for online restoration', (tester) async {
    globalState.activateXboardSession(_session('account'));
    globalState.setOfflineMode(true);
    ApiHealthService.setOffline(true);
    final service = _NodesService();
    await _mount(tester, service);
    expect(service.calls, 0);
    globalState.setOfflineMode(false);
    await _flush(tester);
    expect(service.calls, 0);
    ApiHealthService.setOffline(false);
    await _flush(tester);
    expect(service.calls, 1);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'Android refresh nodes reuses a fresh snapshot and refreshes stale metadata',
    (tester) async {
      final session = _session('account');
      globalState.activateXboardSession(session);
      final service = _NodesService()
        ..loader = (_) async => const [
          XboardNodeData(
            name: 'Node A',
            type: 'ss',
            rate: 1,
            tags: [],
            isOnline: false,
            rawData: {'is_online': false},
          ),
        ];
      await globalState.loadXboardNodesSnapshot(service, session);
      await _mount(tester, service);
      expect(service.calls, 1);
      await tester.tap(
        find.byKey(const ValueKey('fengwo-node-status-refresh')),
      );
      await _flush(tester);
      expect(service.calls, 1);
      globalState.markXboardNodesStaleForSession(
        session,
        globalState.xboardSessionRevision,
      );
      await tester.tap(
        find.byKey(const ValueKey('fengwo-node-status-refresh')),
      );
      await _flush(tester);
      expect(service.calls, 2);
      expect(globalState.xboardNodes.single.isOnline, isFalse);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('manual update bypasses a fresh automatic result', (
    tester,
  ) async {
    final session = _session('account');
    globalState.activateXboardSession(session);
    final service = _NodesService();
    await globalState.loadXboardNodesSnapshot(service, session);
    globalState.refreshXboardNodes = () async {
      await globalState.loadXboardNodesSnapshot(
        service,
        session,
        forceRefresh: true,
      );
      return true;
    };
    await _mount(tester, service);
    expect(service.calls, 1);
    await tester.tap(
      find.byKey(const ValueKey('fengwo-node-status-subscription-refresh')),
    );
    await _flush(tester);
    expect(service.calls, 2);
    expect(globalState.xboardNodesStatusFresh, isTrue);
    await tester.pumpWidget(const SizedBox());
  });

  for (final fails in [false, true]) {
    testWidgets(
      'manual intent takes over pending automatic nodes and ignores late $fails',
      (tester) async {
        final session = _session('account');
        globalState.activateXboardSession(session);
        final automatic = Completer<List<XboardNodeData>>();
        final manual = Completer<List<XboardNodeData>>();
        final service = _NodesService()
          ..loader = (call) => call == 1 ? automatic.future : manual.future;
        globalState.refreshXboardNodes = () async {
          await globalState.loadXboardNodesSnapshot(
            service,
            session,
            forceRefresh: true,
          );
          return true;
        };
        await _mount(tester, service);
        final finder = find.byKey(
          const ValueKey('fengwo-node-status-subscription-refresh'),
        );
        expect(tester.widget<IconButton>(finder).onPressed, isNotNull);
        await tester.tap(finder);
        await _flush(tester);
        expect(service.calls, 2);
        expect(tester.widget<IconButton>(finder).onPressed, isNull);
        manual.complete([_node('manual')]);
        await _flush(tester);
        expect(globalState.xboardNodes.single.name, 'manual');
        expect(tester.widget<IconButton>(finder).onPressed, isNotNull);
        if (fails) {
          automatic.completeError(StateError('late automatic failure'));
        } else {
          automatic.complete([_node('old automatic')]);
        }
        await _flush(tester);
        expect(globalState.xboardNodes.single.name, 'manual');
        expect(globalState.xboardNodesStatusFresh, isTrue);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }

  testWidgets(
    'same credentials with a new session epoch discard late failure',
    (tester) async {
      final oldSession = _session('account');
      globalState.activateXboardSession(oldSession);
      final old = Completer<List<XboardNodeData>>();
      final fresh = Completer<List<XboardNodeData>>();
      final service = _NodesService()
        ..loader = (call) => call == 1 ? old.future : fresh.future;
      await _mount(tester, service);
      final session = _session('account');
      globalState.activateXboardSession(session);
      await _flush(tester);
      expect(service.calls, 2);
      fresh.complete([_node('new epoch')]);
      await _flush(tester);
      old.completeError(StateError('old epoch failure'));
      await _flush(tester);
      expect(globalState.xboardSession, same(session));
      expect(globalState.xboardNodes.single.name, 'new epoch');
      expect(globalState.xboardNodesStatusFresh, isTrue);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('disposed page removes pending activity listener', (
    tester,
  ) async {
    globalState.activateXboardSession(_session('account'));
    ApiHealthService.setAppForeground(false);
    final service = _NodesService();
    await _mount(tester, service);
    await tester.pumpWidget(const SizedBox());
    ApiHealthService.setAppForeground(true);
    ApiHealthService.networkChanged();
    await _flush(tester);
    expect(service.calls, 0);
    expect(tester.takeException(), isNull);
  });
}

Future<void> _flush(WidgetTester tester) async {
  await tester.pump(Duration.zero);
  await tester.pump(Duration.zero);
  await tester.pump(Duration.zero);
}

Future<ValueNotifier<bool>> _mount(
  WidgetTester tester,
  XboardAuthService service, {
  bool active = true,
  Future<List<XboardNodeData>> Function(
    XboardAuthService service,
    XboardLoginResult session,
  )?
  nodesLoader,
}) async {
  tester.view.physicalSize = const Size(1100, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  const group = Group(
    name: 'group',
    type: GroupType.Selector,
    now: 'Node A',
    all: [Proxy(name: 'Node A', type: 'ss')],
  );
  final profile = Profile(
    id: 1,
    autoUpdateDuration: Duration.zero,
    currentGroupName: group.name,
    selectedMap: {group.name: 'Node A'},
  );
  final container = ProviderContainer(
    overrides: [
      groupsProvider.overrideWithValue([group]),
      currentGroupsStateProvider.overrideWithValue(
        const GroupsState(value: [group]),
      ),
      currentProfileProvider.overrideWithValue(profile),
      isStartProvider.overrideWithValue(false),
      delayProvider(proxyName: 'Node A').overrideWithValue(80),
    ],
  );
  addTearDown(container.dispose);
  globalState.container = container;
  final activity = ValueNotifier(active);
  addTearDown(activity.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        navigatorKey: globalState.navigatorKey,
        locale: const Locale('en'),
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.delegate.supportedLocales,
        builder: (context, child) {
          globalState.measure = Measure.of(context, 1);
          globalState.theme = CommonTheme.of(context, 1);
          return child!;
        },
        home: Scaffold(
          body: ValueListenableBuilder<bool>(
            valueListenable: activity,
            child: FengWoNodeStatusView(
              authService: service,
              nodesLoader: nodesLoader,
            ),
            builder: (_, active, child) =>
                PageActivityScope(isActive: active, child: child!),
          ),
        ),
      ),
    ),
  );
  await _flush(tester);
  return activity;
}

class _NodesService extends XboardAuthService {
  int calls = 0;
  Future<List<XboardNodeData>> Function(int call)? loader;

  @override
  Future<List<XboardNodeData>> fetchNodes({
    required Uri endpoint,
    required String authData,
    String? userToken,
    bool secureSubscription = false,
    bool Function()? canRequest,
  }) async {
    ensureXboardApiRequestAllowed(canRequest);
    calls++;
    final nodes =
        await (loader?.call(calls) ?? Future.value([_node('Node A')]));
    ensureXboardApiRequestAllowed(canRequest);
    return nodes;
  }
}

XboardLoginResult _session(String token) {
  final endpoint = Uri.parse('https://api.example');
  return XboardLoginResult(
    endpoint: endpoint,
    authData: token,
    token: token,
    isAdmin: false,
    subscription: XboardSubscriptionData(
      endpoint: endpoint,
      subscribeUrl: endpoint.resolve('/subscription'),
      uploadBytes: 0,
      downloadBytes: 0,
      transferEnableBytes: 1,
      rawData: const {},
    ),
  );
}

XboardNodeData _node(String name, {bool online = true}) => XboardNodeData(
  name: name,
  type: 'ss',
  rate: 1,
  tags: const ['HK'],
  isOnline: online,
  rawData: const {'is_online': true},
);

import 'dart:async';

import 'package:fl_clash/common/xboard_auth.dart';
import 'package:fl_clash/common/xboard_api_request.dart';
import 'package:fl_clash/state.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'an abandoned automatic node response cannot publish or mark existing metadata stale',
    () async {
      final session = _session();
      globalState.activateXboardSession(session);
      globalState.xboardNodes = [_node('existing')];
      final response = Completer<List<XboardNodeData>>();
      final service = _NodesService(
        (call) async => call == 1 ? response.future : [_node('fresh')],
      );
      var active = true;
      final automatic = globalState.loadXboardNodesSnapshot(
        service,
        session,
        canRequest: () => active,
      );
      final deferred = expectLater(
        automatic,
        throwsA(isA<XboardApiRequestDeferred>()),
      );
      active = false;
      response.complete([_node('departed')]);
      await deferred;
      expect(globalState.xboardNodes.single.name, 'existing');
      expect(globalState.xboardNodesStatusFresh, isTrue);
      await globalState.loadXboardNodesSnapshot(service, session);
      expect(service.calls, 2);
      expect(globalState.xboardNodes.single.name, 'fresh');
    },
  );

  test(
    'another valid node reader can publish when the first page leaves',
    () async {
      final session = _session();
      globalState.activateXboardSession(session);
      final response = Completer<List<XboardNodeData>>();
      final service = _NodesService((_) => response.future);
      var firstActive = true;
      final first = globalState.loadXboardNodesSnapshot(
        service,
        session,
        canRequest: () => firstActive,
      );
      final other = globalState.loadXboardNodesSnapshot(
        service,
        session,
        canRequest: () => true,
      );
      final deferred = expectLater(
        first,
        throwsA(isA<XboardApiRequestDeferred>()),
      );
      firstActive = false;
      response.complete([_node('other reader')]);
      expect((await other).single.name, 'other reader');
      await deferred;
      expect(service.calls, 1);
      expect(globalState.xboardNodes.single.name, 'other reader');
      expect(globalState.xboardNodesStatusFresh, isTrue);
    },
  );

  test(
    'a stale automatic node failure does not poison manual success',
    () async {
      final session = _session();
      globalState.activateXboardSession(session);
      final response = Completer<List<XboardNodeData>>();
      final service = _NodesService(
        (call) async => call == 1 ? response.future : [_node('manual')],
      );
      var active = true;
      final first = globalState.loadXboardNodesSnapshot(
        service,
        session,
        canRequest: () => active,
      );
      final deferred = expectLater(
        first,
        throwsA(isA<XboardApiRequestDeferred>()),
      );
      final manual = globalState.loadXboardNodesSnapshot(
        service,
        session,
        forceRefresh: true,
      );
      active = false;
      await manual;
      await deferred;
      response.completeError(StateError('old failure'));
      await Future<void>.delayed(Duration.zero);
      expect(globalState.xboardNodes.single.name, 'manual');
      expect(globalState.xboardNodesStatusFresh, isTrue);
    },
  );

  setUp(() {
    globalState.clearXboardSession();
    globalState.setOfflineMode(false);
  });
  tearDown(() {
    globalState.clearXboardSession();
    globalState.setOfflineMode(false);
  });

  test(
    'login and page share one request and cache hits do not republish',
    () async {
      final session = _session();
      globalState.activateXboardSession(session);
      final response = Completer<List<XboardNodeData>>();
      final service = _NodesService((_) => response.future);
      final login = globalState.loadXboardNodesSnapshot(service, session);
      final page = globalState.loadXboardNodesSnapshot(service, session);
      expect(service.calls, 1);
      response.complete([_node('fresh')]);
      expect((await login).single.name, 'fresh');
      expect((await page).single.name, 'fresh');
      final revision = globalState.xboardNodesRevisionNotifier.value;
      expect(
        (await globalState.loadXboardNodesSnapshot(
          service,
          session,
        )).single.name,
        'fresh',
      );
      expect(service.calls, 1);
      expect(globalState.xboardNodesRevisionNotifier.value, revision);
      expect(globalState.xboardNodesStatusFresh, isTrue);
    },
  );

  test('manual refresh supersedes pending automatic publication', () async {
    final session = _session();
    globalState.activateXboardSession(session);
    final old = Completer<List<XboardNodeData>>();
    final service = _NodesService(
      (call) async => call == 1 ? old.future : [_node('manual')],
    );
    final automatic = globalState.loadXboardNodesSnapshot(service, session);
    final manual = globalState.loadXboardNodesSnapshot(
      service,
      session,
      forceRefresh: true,
    );
    expect((await manual).single.name, 'manual');
    expect((await automatic).single.name, 'manual');
    old.complete([_node('obsolete')]);
    await Future<void>.delayed(Duration.zero);
    expect(globalState.xboardNodes.single.name, 'manual');
    expect(globalState.xboardNodesStatusFresh, isTrue);
    expect(service.calls, 2);
  });

  test('forced success bypasses a fresh cached result', () async {
    final session = _session();
    globalState.activateXboardSession(session);
    final service = _NodesService((call) async => [_node('read-$call')]);
    await globalState.loadXboardNodesSnapshot(service, session);
    await globalState.loadXboardNodesSnapshot(
      service,
      session,
      forceRefresh: true,
    );
    expect(service.calls, 2);
    expect(globalState.xboardNodes.single.name, 'read-2');
  });

  test('failed refresh retains metadata and marks its status stale', () async {
    final session = _session();
    globalState.activateXboardSession(session);
    final service = _NodesService((call) async {
      if (call > 1) throw StateError('offline');
      return [_node('old')];
    });
    await globalState.loadXboardNodesSnapshot(service, session);
    await expectLater(
      globalState.loadXboardNodesSnapshot(service, session, forceRefresh: true),
      throwsStateError,
    );
    expect(globalState.xboardNodes.single.name, 'old');
    expect(globalState.xboardNodesStatusFresh, isFalse);
  });

  test('a successful empty list replaces previous nodes', () async {
    final session = _session();
    globalState.activateXboardSession(session);
    final service = _NodesService(
      (call) async => call == 1 ? [_node('old')] : [],
    );
    await globalState.loadXboardNodesSnapshot(service, session);
    await globalState.loadXboardNodesSnapshot(
      service,
      session,
      forceRefresh: true,
    );
    expect(globalState.xboardNodes, isEmpty);
    expect(globalState.xboardNodesStatusFresh, isTrue);
  });

  test(
    'logout and relogin with the same credentials invalidate pending data',
    () async {
      final session = _session();
      globalState.activateXboardSession(session);
      final pending = Completer<List<XboardNodeData>>();
      final service = _NodesService(
        (call) async => call == 1 ? pending.future : [_node('new epoch')],
      );
      final old = globalState.loadXboardNodesSnapshot(service, session);
      final rejected = expectLater(old, throwsStateError);
      globalState.clearXboardSession();
      globalState.activateXboardSession(session);
      await globalState.loadXboardNodesSnapshot(service, session);
      pending.complete([_node('old epoch')]);
      await rejected;
      expect(globalState.xboardNodes.single.name, 'new epoch');
    },
  );

  test(
    'offline invalidates old data and explicit recovery seeds online reuse',
    () async {
      final session = _session();
      globalState.activateXboardSession(session);
      final service = _NodesService((call) async => [_node('$call')]);
      await globalState.loadXboardNodesSnapshot(service, session);
      globalState.setOfflineMode(true);
      await expectLater(
        globalState.loadXboardNodesSnapshot(service, session),
        throwsStateError,
      );
      expect(service.calls, 1);
      await globalState.loadXboardNodesSnapshot(
        service,
        session,
        ignoreOfflineMode: true,
      );
      expect(service.calls, 2);
      globalState.setOfflineMode(false);
      await globalState.loadXboardNodesSnapshot(service, session);
      expect(service.calls, 2);
    },
  );
}

class _NodesService extends XboardAuthService {
  _NodesService(this.loader);
  final Future<List<XboardNodeData>> Function(int call) loader;
  int calls = 0;

  @override
  Future<List<XboardNodeData>> fetchNodes({
    required Uri endpoint,
    required String authData,
    String? userToken,
    bool secureSubscription = false,
    bool Function()? canRequest,
  }) async {
    ensureXboardApiRequestAllowed(canRequest);
    final nodes = await loader(++calls);
    ensureXboardApiRequestAllowed(canRequest);
    return nodes;
  }
}

XboardLoginResult _session() => XboardLoginResult(
  endpoint: Uri.parse('https://nodes.example.com'),
  token: 'fixture-token',
  authData: 'fixture-auth',
  isAdmin: false,
  subscription: XboardSubscriptionData(
    endpoint: Uri.parse('https://nodes.example.com'),
    subscribeUrl: null,
    uploadBytes: 0,
    downloadBytes: 0,
    transferEnableBytes: 100,
    rawData: const {},
  ),
);

XboardNodeData _node(String name) => XboardNodeData(
  name: name,
  type: 'ss',
  rate: 1,
  tags: const ['HK'],
  isOnline: true,
  rawData: const {},
);

import 'package:fl_clash/common/xboard_auth.dart';
import 'package:fl_clash/state.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(() {
    globalState.clearXboardSession();
    globalState.setOfflineMode(false);
  });

  tearDown(() {
    globalState.clearXboardSession();
    globalState.setOfflineMode(false);
  });

  test('failed refresh retains successful metadata but invalidates status', () {
    final session = _session('current');
    final revision = globalState.activateXboardSession(session);
    final nodes = [_node('Node A')];
    globalState.setXboardNodesForSession(session, revision, nodes);
    expect(globalState.xboardNodesStatusFresh, isTrue);
    final notified = globalState.xboardNodesRevisionNotifier.value;
    final request = globalState.beginXboardNodesRefresh(session, revision);
    expect(
      globalState.markXboardNodesStaleForSession(
        session,
        revision,
        requestRevision: request,
      ),
      isTrue,
    );
    expect(globalState.xboardNodes, nodes);
    expect(globalState.xboardNodes.single.tags, ['HK']);
    expect(globalState.xboardNodes.single.rate, 2);
    expect(globalState.xboardNodesStatusFresh, isFalse);
    expect(
      globalState.xboardNodesRevisionNotifier.value,
      greaterThan(notified),
    );
  });

  test('successful empty response replaces the previous metadata', () {
    final session = _session('current');
    final revision = globalState.activateXboardSession(session);
    globalState.setXboardNodesForSession(session, revision, [_node('Node A')]);
    final request = globalState.beginXboardNodesRefresh(session, revision);
    expect(
      globalState.setXboardNodesForSession(
        session,
        revision,
        const [],
        requestRevision: request,
      ),
      isTrue,
    );
    expect(globalState.xboardNodes, isEmpty);
    expect(globalState.xboardNodesStatusFresh, isTrue);
  });

  for (final fresh in [true, false]) {
    test('subscription-only refresh preserves metadata freshness $fresh', () {
      final session = _session('current');
      final revision = globalState.activateXboardSession(session);
      final nodes = [_node('Node A')];
      globalState.setXboardNodesForSession(session, revision, nodes);
      if (!fresh) {
        globalState.markXboardNodesStaleForSession(session, revision);
      }
      final previousRequest = globalState.beginXboardNodesRefresh(
        session,
        revision,
      );
      final updatedSession = _session('current');
      globalState.activateXboardSession(
        updatedSession,
        nodes: globalState.xboardNodes,
        nodesStatusFresh: globalState.xboardNodesStatusFresh,
      );
      expect(globalState.xboardNodes, nodes);
      expect(globalState.xboardNodesStatusFresh, fresh);
      expect(
        globalState.setXboardNodesForSession(
          session,
          revision,
          const [],
          requestRevision: previousRequest,
        ),
        isFalse,
      );
      expect(globalState.xboardNodes, nodes);
      expect(globalState.xboardNodesStatusFresh, fresh);
    });
  }

  test('late success and failure cannot replace another account metadata', () {
    final oldSession = _session('old');
    final oldRevision = globalState.activateXboardSession(oldSession);
    final oldRequest = globalState.beginXboardNodesRefresh(
      oldSession,
      oldRevision,
    );
    final session = _session('new');
    final revision = globalState.activateXboardSession(session);
    final nodes = [_node('New account node')];
    globalState.setXboardNodesForSession(session, revision, nodes);
    expect(
      globalState.setXboardNodesForSession(oldSession, oldRevision, [
        _node('Old account node'),
      ], requestRevision: oldRequest),
      isFalse,
    );
    expect(
      globalState.markXboardNodesStaleForSession(
        oldSession,
        oldRevision,
        requestRevision: oldRequest,
      ),
      isFalse,
    );
    expect(globalState.xboardNodes, nodes);
    expect(globalState.xboardNodesStatusFresh, isTrue);
  });

  test('latest refresh wins when the same session has parallel requests', () {
    final session = _session('current');
    final revision = globalState.activateXboardSession(session);
    final first = globalState.beginXboardNodesRefresh(session, revision);
    final second = globalState.beginXboardNodesRefresh(session, revision);
    final nodes = [_node('Latest node')];
    expect(
      globalState.setXboardNodesForSession(
        session,
        revision,
        nodes,
        requestRevision: second,
      ),
      isTrue,
    );
    expect(
      globalState.setXboardNodesForSession(
        session,
        revision,
        const [],
        requestRevision: first,
      ),
      isFalse,
    );
    expect(
      globalState.markXboardNodesStaleForSession(
        session,
        revision,
        requestRevision: first,
      ),
      isFalse,
    );
    expect(globalState.xboardNodes, nodes);
    expect(globalState.xboardNodesStatusFresh, isTrue);
  });

  test('offline cache is not fresh and session changes notify consumers', () {
    final notifications = <int>[];
    void listener() {
      notifications.add(globalState.xboardNodesRevisionNotifier.value);
    }

    globalState.xboardNodesRevisionNotifier.addListener(listener);
    addTearDown(
      () => globalState.xboardNodesRevisionNotifier.removeListener(listener),
    );
    final session = _session('current');
    final revision = globalState.activateXboardSession(
      session,
      nodes: [_node('Cached node')],
    );
    expect(globalState.xboardNodesStatusFresh, isFalse);
    globalState.setXboardNodesForSession(session, revision, [
      _node('Live node'),
    ]);
    expect(globalState.xboardNodesStatusFresh, isTrue);
    globalState.setOfflineMode(true);
    expect(globalState.xboardNodesStatusFresh, isFalse);
    globalState.clearXboardSession();
    expect(globalState.xboardNodes, isEmpty);
    expect(globalState.xboardNodesStatusFresh, isFalse);
    expect(notifications, hasLength(3));
  });
}

XboardLoginResult _session(String token) {
  final endpoint = Uri.parse('https://api.example.com');
  return XboardLoginResult(
    endpoint: endpoint,
    token: token,
    authData: token,
    isAdmin: false,
    subscription: XboardSubscriptionData(
      endpoint: endpoint,
      subscribeUrl: endpoint.resolve('/subscribe/$token'),
      uploadBytes: 0,
      downloadBytes: 0,
      transferEnableBytes: 0,
      rawData: const {},
    ),
  );
}

XboardNodeData _node(String name) => XboardNodeData(
  name: name,
  type: 'ss',
  rate: 2,
  tags: const ['HK'],
  isOnline: true,
  rawData: const {'is_online': true},
);

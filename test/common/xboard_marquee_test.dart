import 'dart:async';

import 'package:dio/dio.dart';
import 'package:fl_clash/common/xboard_auth.dart';
import 'package:fl_clash/common/xboard_marquee.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

final _pollingControllers = <XboardMarqueeController>[];

void _startPolling(XboardMarqueeController controller) {
  _pollingControllers.add(controller);
  controller.startPolling(foreground: true, offline: false);
}

void _pollingTest(String description, WidgetTesterCallback callback) {
  testWidgets(description, (tester) async {
    _pollingControllers.clear();
    try {
      await callback(tester);
    } finally {
      for (final controller in _pollingControllers) {
        controller.stopPolling();
      }
    }
  });
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('parses the unread response in server order', () {
    final messages = parseXboardMarqueeUnreadResponse(_unreadResponse());

    expect(messages, hasLength(2));
    expect(messages.map((message) => message.id), [123, 124]);
    expect(messages.first.title, '线路维护通知');
    expect(messages.first.marqueeText, '今晚 02:00 部分线路维护');
    expect(messages.first.priority, 100);
    expect(messages.first.actionUrl, '/message/123');
    expect(messages.first.publishedAtEpochSeconds, 1788163200);
    expect(messages.first.expiresAtEpochSeconds, 1788249600);
  });

  test('uses the documented unread and read request contracts', () async {
    final adapter = _RecordingAdapter([
      ResponseBody.fromString(
        '{"status":1,"data":{"items":[]}}',
        200,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType],
        },
      ),
      ResponseBody.fromString(
        '{"status":1,"data":true}',
        200,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType],
        },
      ),
    ]);
    final dio = Dio()..httpClientAdapter = adapter;
    final api = XboardMarqueeApi(dio: dio);

    await api.fetchUnread(
      endpoint: Uri.parse('https://api.example.com/base'),
      token: '12345678901234567890123456789012',
    );
    await api.markRead(
      endpoint: Uri.parse('https://api.example.com/base'),
      token: '12345678901234567890123456789012',
      message: _message(123),
    );

    expect(adapter.requests, hasLength(2));
    expect(adapter.requests.first.uri.path, '/api/v1/app/site-message/unread');
    expect(adapter.requests.first.method, 'POST');
    expect(adapter.requests.first.data, {
      'token': '12345678901234567890123456789012',
      'limit': 10,
    });
    expect(adapter.requests.last.uri.path, '/api/v1/app/site-message/read');
    expect(adapter.requests.last.data, {
      'token': '12345678901234567890123456789012',
      'message_id': 123,
    });
  });

  test('successful read removes immediately and persists the queue', () async {
    var readCalls = 0;
    final api = XboardMarqueeApi(
      unreadRequester: (_, _, _) async => _unreadResponse(),
      readRequester: (_, _, _) async => readCalls++,
    );
    final controller = XboardMarqueeController(api: api);
    await controller.updateSession(_session(), offline: false);
    expect(controller.messages.map((message) => message.id), [123, 124]);

    expect(await controller.markRead(controller.messages.first), isTrue);
    expect(readCalls, 1);
    expect(controller.messages.map((message) => message.id), [124]);

    final offlineController = XboardMarqueeController(
      api: XboardMarqueeApi(
        unreadRequester: (_, _, _) => throw StateError('offline'),
      ),
    );
    await offlineController.updateSession(_session(), offline: true);
    expect(offlineController.messages.map((message) => message.id), [124]);
  });

  test(
    'read failure and 404-equivalent failure keep the local queue',
    () async {
      final controller = XboardMarqueeController(
        api: XboardMarqueeApi(
          unreadRequester: (_, _, _) async => _unreadResponse(),
          readRequester: (_, _, _) => throw const XboardMarqueeException('404'),
        ),
      );
      await controller.updateSession(_session(), offline: false);
      final message = controller.messages.first;

      expect(await controller.markRead(message), isFalse);
      expect(controller.messages.map((message) => message.id), [123, 124]);
    },
  );

  test('network refresh failure retains the cached queue', () async {
    final onlineController = XboardMarqueeController(
      api: XboardMarqueeApi(
        unreadRequester: (_, _, _) async => _unreadResponse(),
      ),
    );
    await onlineController.updateSession(_session(), offline: false);

    final failingController = XboardMarqueeController(
      api: XboardMarqueeApi(
        unreadRequester: (_, _, _) => throw StateError('network down'),
      ),
    );
    await failingController.updateSession(_session(), offline: false);
    expect(failingController.messages.map((message) => message.id), [123, 124]);
  });

  test(
    'coalesces overlapping refreshes and keeps the five minute deadline',
    () async {
      var now = DateTime(2026, 8, 31, 10);
      var calls = 0;
      final pending = Completer<Object?>();
      final controller = XboardMarqueeController(
        now: () => now,
        api: XboardMarqueeApi(
          unreadRequester: (_, _, _) {
            calls++;
            return calls == 1
                ? pending.future
                : Future.value(_unreadResponse());
          },
        ),
      );

      final loginRefresh = controller.updateSession(_session(), offline: false);
      final duplicate = controller.refresh(force: true);
      await Future<void>.delayed(Duration.zero);
      expect(calls, 1);
      pending.complete(_unreadResponse());
      await Future.wait([loginRefresh, duplicate]);

      await controller.refresh();
      expect(calls, 1);
      now = now.add(const Duration(seconds: 31));
      await controller.refresh();
      expect(calls, 1);
      now = now.add(const Duration(minutes: 5));
      await controller.refresh();
      expect(calls, 2);
    },
  );

  test(
    'loading notifications cannot reenter or bypass a new background gate',
    () async {
      var calls = 0;
      final controller = XboardMarqueeController(
        store: _MemoryStore(),
        api: XboardMarqueeApi(
          unreadRequester: (_, _, _) async {
            calls++;
            return _unreadResponse();
          },
        ),
      );
      addTearDown(controller.dispose);
      var paused = false;
      controller.addListener(() {
        if (!controller.isLoading || paused) return;
        paused = true;
        controller.setForeground(false);
        unawaited(controller.refresh(force: true));
      });
      await controller.updateSession(_session(), offline: false);
      expect(calls, 0);
      controller.setForeground(true);
      await controller.refresh(force: true);
      expect(calls, 1);
    },
  );

  _pollingTest(
    'automatic failures back off and success restores five minutes',
    (tester) async {
      var calls = 0;
      var failing = true;
      final controller = XboardMarqueeController(
        now: tester.binding.clock.now,
        store: _MemoryStore(),
        api: XboardMarqueeApi(
          unreadRequester: (_, _, _) async {
            calls++;
            if (failing) throw StateError('controlled_marquee_outage');
            return _unreadResponse();
          },
        ),
      );
      addTearDown(controller.dispose);
      _startPolling(controller);
      await controller.updateSession(_session(), offline: false);
      expect(calls, 1);
      for (final minutes in [5, 10, 20, 30, 30]) {
        final previous = calls;
        await tester.pump(Duration(minutes: minutes - 1));
        expect(calls, previous);
        await tester.pump(const Duration(minutes: 1));
        expect(calls, previous + 1);
      }
      failing = false;
      await tester.pump(const Duration(minutes: 30));
      expect(calls, 7);
      await tester.pump(const Duration(minutes: 4, seconds: 59));
      expect(calls, 7);
      await tester.pump(const Duration(seconds: 1));
      expect(calls, 8);
      expect(controller.messages, hasLength(2));
    },
  );

  _pollingTest('all refresh paths respect background and offline gates', (
    tester,
  ) async {
    final tokens = <String>[];
    final controller = XboardMarqueeController(
      now: tester.binding.clock.now,
      store: _MemoryStore(),
      api: XboardMarqueeApi(
        unreadRequester: (_, token, _) async {
          tokens.add(token);
          return _unreadResponse();
        },
      ),
    );
    addTearDown(controller.dispose);
    _startPolling(controller);
    await controller.updateSession(_session(), offline: false);
    controller.setForeground(false);
    await tester.pump(const Duration(hours: 1));
    await controller.updateSession(_session(token: 'rotated'), offline: false);
    await controller.refresh(force: true);
    expect(tokens, hasLength(1));
    controller.setWindowForeground(false);
    controller.setForeground(true);
    await tester.pump(Duration.zero);
    await controller.refresh(force: true);
    expect(tokens, hasLength(1));
    controller.setOffline(true);
    controller.setWindowForeground(true);
    await tester.pump(Duration.zero);
    await controller.refresh(force: true);
    expect(tokens, hasLength(1));
    controller.setOffline(false);
    controller.setForeground(true);
    controller.setWindowForeground(true);
    await tester.pump(Duration.zero);
    expect(tokens, hasLength(2));
    expect(tokens.last, 'rotated');
    await controller.refresh();
    expect(tokens, hasLength(2));
    await controller.refresh(force: true);
    expect(tokens, hasLength(3));
  });

  _pollingTest('recovery keeps failure cooldown and coalesces resume events', (
    tester,
  ) async {
    var calls = 0;
    final controller = XboardMarqueeController(
      now: tester.binding.clock.now,
      store: _MemoryStore(),
      api: XboardMarqueeApi(
        unreadRequester: (_, _, _) async {
          calls++;
          throw StateError('controlled_marquee_outage');
        },
      ),
    );
    addTearDown(controller.dispose);
    _startPolling(controller);
    await controller.updateSession(_session(), offline: false);
    controller.setForeground(false);
    await tester.pump(const Duration(minutes: 2));
    controller.setForeground(true);
    controller.setWindowForeground(true);
    controller.setOffline(false);
    await tester.pump(const Duration(minutes: 2, seconds: 59));
    expect(calls, 1);
    await tester.pump(const Duration(seconds: 1));
    expect(calls, 2);
    controller.setForeground(false);
    await tester.pump(const Duration(hours: 1));
    controller.setForeground(true);
    controller.setWindowForeground(true);
    controller.setOffline(false);
    await tester.pump(Duration.zero);
    expect(calls, 3);
  });

  test(
    'same authentication metadata updates credentials without fetching',
    () async {
      final tokens = <String>[];
      final store = _MemoryStore();
      final controller = XboardMarqueeController(
        store: store,
        api: XboardMarqueeApi(
          unreadRequester: (_, token, _) async {
            tokens.add(token);
            return _unreadResponse();
          },
        ),
      );
      addTearDown(controller.dispose);
      await controller.updateSession(_session(), offline: false);
      await controller.updateSession(
        _session(token: 'rotated'),
        offline: false,
      );
      expect(tokens, hasLength(1));
      expect(store.queues['https://api.example.com|rotated'], hasLength(2));
      await controller.refresh(force: true);
      expect(tokens.last, 'rotated');
    },
  );

  _pollingTest(
    'an in-flight result is kept in background without another poll',
    (tester) async {
      final pending = Completer<Object?>();
      var calls = 0;
      final controller = XboardMarqueeController(
        now: tester.binding.clock.now,
        store: _MemoryStore(),
        api: XboardMarqueeApi(
          unreadRequester: (_, _, _) {
            calls++;
            return calls == 1
                ? pending.future
                : Future.value(_unreadResponse());
          },
        ),
      );
      addTearDown(controller.dispose);
      _startPolling(controller);
      final loading = controller.updateSession(_session(), offline: false);
      await tester.pump(Duration.zero);
      controller.setForeground(false);
      pending.complete(_unreadResponse());
      await loading;
      expect(controller.messages, hasLength(2));
      await tester.pump(const Duration(hours: 1));
      expect(calls, 1);
      controller.setForeground(true);
      await tester.pump(Duration.zero);
      expect(calls, 2);
    },
  );

  test(
    'a delayed old cache cannot fetch or replace the next account',
    () async {
      final cached = Completer<List<XboardMarqueeMessage>>();
      final store = _MemoryStore()..firstLoad = cached.future;
      final tokens = <String>[];
      final controller = XboardMarqueeController(
        store: store,
        api: XboardMarqueeApi(
          unreadRequester: (_, token, _) async {
            tokens.add(token);
            return _unreadResponse();
          },
        ),
      );
      addTearDown(controller.dispose);
      final old = controller.updateSession(_session(), offline: false);
      final oldForce = controller.refresh(force: true);
      await controller.updateSession(
        _session(token: 'next', auth: 'next-auth'),
        offline: false,
      );
      cached.complete([_message(999)]);
      await Future.wait([old, oldForce]);
      expect(tokens, ['next']);
      expect(controller.messages.map((message) => message.id), [123, 124]);
    },
  );

  test('logout and a new login ignore an old unread response', () async {
    final pending = Completer<Object?>();
    var calls = 0;
    final controller = XboardMarqueeController(
      store: _MemoryStore(),
      api: XboardMarqueeApi(
        unreadRequester: (_, _, _) {
          calls++;
          return calls == 1 ? pending.future : Future.value(_unreadResponse());
        },
      ),
    );
    addTearDown(controller.dispose);
    final old = controller.updateSession(_session(), offline: false);
    await Future<void>.delayed(Duration.zero);
    await controller.updateSession(null, offline: false);
    await controller.updateSession(_session(), offline: false);
    pending.complete({
      'status': 1,
      'data': {'items': []},
    });
    await old;
    expect(calls, 2);
    expect(controller.messages, hasLength(2));
  });

  test(
    'late unread cannot restore a message marked read during its request',
    () async {
      final pending = Completer<Object?>();
      var calls = 0;
      final store = _MemoryStore();
      final controller = XboardMarqueeController(
        store: store,
        api: XboardMarqueeApi(
          unreadRequester: (_, _, _) =>
              ++calls == 1 ? Future.value(_unreadResponse()) : pending.future,
          readRequester: (_, _, _) async {},
        ),
      );
      addTearDown(controller.dispose);
      await controller.updateSession(_session(), offline: false);
      final refresh = controller.refresh(force: true);
      expect(await controller.markRead(controller.messages.first), isTrue);
      pending.complete(_unreadResponse());
      await refresh;
      expect(controller.messages.map((message) => message.id), [124]);
      expect(store.queues.values.single.map((message) => message.id), [124]);
    },
  );

  _pollingTest('disposing while fetching prevents notifications and timers', (
    tester,
  ) async {
    final pending = Completer<Object?>();
    var calls = 0;
    final controller = XboardMarqueeController(
      now: tester.binding.clock.now,
      store: _MemoryStore(),
      api: XboardMarqueeApi(
        unreadRequester: (_, _, _) {
          calls++;
          return pending.future;
        },
      ),
    );
    _startPolling(controller);
    final loading = controller.updateSession(_session(), offline: false);
    await tester.pump(Duration.zero);
    controller.dispose();
    pending.complete(_unreadResponse());
    await loading;
    await tester.pump(const Duration(hours: 1));
    expect(calls, 1);
    expect(tester.takeException(), isNull);
  });
}

Map<String, Object?> _unreadResponse() => {
  'status': 1,
  'data': {
    'items': [
      {
        'id': 123,
        'title': '线路维护通知',
        'marquee_text': '今晚 02:00 部分线路维护',
        'content': '预计维护十分钟，期间可能发生一次重连。',
        'priority': 100,
        'action_url': '/message/123',
        'published_at': 1788163200,
        'expires_at': 1788249600,
      },
      {
        'id': 124,
        'title': '客户端通知',
        'marquee_text': '第二条消息',
        'content': '第二条详情',
        'priority': 80,
        'action_url': '',
      },
    ],
    'has_more': false,
  },
};

XboardMarqueeMessage _message(int id) => XboardMarqueeMessage(
  id: id,
  marqueeText: '消息$id',
  title: '标题$id',
  detailText: '详情$id',
  actionUrl: '/message/$id',
);

XboardLoginResult _session({
  String token = '12345678901234567890123456789012',
  String auth = 'Bearer auth',
}) => XboardLoginResult(
  endpoint: Uri.parse('https://api.example.com'),
  token: token,
  authData: auth,
  isAdmin: false,
  subscription: XboardSubscriptionData(
    endpoint: Uri.parse('https://api.example.com'),
    subscribeUrl: Uri.parse('https://api.example.com/subscribe'),
    uploadBytes: 0,
    downloadBytes: 0,
    transferEnableBytes: 100,
    rawData: const {},
  ),
);

class _MemoryStore extends XboardMarqueeQueueStore {
  final queues = <String, List<XboardMarqueeMessage>>{};
  Future<List<XboardMarqueeMessage>>? firstLoad;

  @override
  Future<List<XboardMarqueeMessage>> load(String accountKey) {
    final pending = firstLoad;
    firstLoad = null;
    return pending ?? Future.value(queues[accountKey] ?? const []);
  }

  @override
  Future<void> save(
    String accountKey,
    List<XboardMarqueeMessage> messages,
  ) async {
    queues[accountKey] = List.of(messages);
  }
}

class _RecordingAdapter implements HttpClientAdapter {
  _RecordingAdapter(this._responses);

  final List<ResponseBody> _responses;
  final List<RequestOptions> requests = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    return _responses.removeAt(0);
  }

  @override
  void close({bool force = false}) {}
}

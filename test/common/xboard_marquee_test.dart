import 'dart:async';

import 'package:dio/dio.dart';
import 'package:fl_clash/common/xboard_auth.dart';
import 'package:fl_clash/common/xboard_marquee.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
    'coalesces overlapping refreshes and enforces the request gap',
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
      expect(calls, 1);
      pending.complete(_unreadResponse());
      await Future.wait([loginRefresh, duplicate]);

      await controller.refresh();
      expect(calls, 1);
      now = now.add(const Duration(seconds: 31));
      await controller.refresh();
      expect(calls, 2);
    },
  );
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

XboardLoginResult _session() => XboardLoginResult(
  endpoint: Uri.parse('https://api.example.com'),
  token: '12345678901234567890123456789012',
  authData: 'Bearer auth',
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

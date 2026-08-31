import 'package:fl_clash/common/xboard_auth.dart';
import 'package:fl_clash/common/xboard_marquee.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/widgets/fengwo_marquee.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('guides the user with a fixed view button and clickable bar', (
    tester,
  ) async {
    final controller = await _loadedController();
    var taps = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: FengWoMarqueeBar(
            controller: controller,
            onMessageTap: (_) => taps++,
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.byIcon(Icons.campaign_rounded), findsOneWidget);
    expect(find.text('查看详情'), findsOneWidget);
    expect(find.text('1/2'), findsOneWidget);

    await tester.tap(find.text('查看详情'));
    await tester.pump();
    expect(taps, 1);
  });

  testWidgets('finishing marquee animation rotates but never marks as read', (
    tester,
  ) async {
    final controller = await _loadedController();
    var taps = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: FengWoMarqueeBar(
            controller: controller,
            compact: true,
            onMessageTap: (_) => taps++,
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('查看'), findsOneWidget);
    expect(find.byKey(const ValueKey('marquee-message-123')), findsOneWidget);

    await tester.pump(const Duration(seconds: 17));
    await tester.pump();

    expect(taps, 0);
    expect(controller.messages, hasLength(2));
    expect(find.byKey(const ValueKey('marquee-message-124')), findsOneWidget);
  });

  test('only whitelisted in-app actions are routed', () {
    expect(pageLabelForMarqueeAction('fengwo://page/orders'), PageLabel.orders);
    expect(pageLabelForMarqueeAction('/app/settings'), PageLabel.resources);
    expect(pageLabelForMarqueeAction('/message/123'), isNull);
    expect(pageLabelForMarqueeAction('https://example.com/orders'), isNull);
    expect(pageLabelForMarqueeAction('javascript:alert(1)'), isNull);
  });
}

Future<XboardMarqueeController> _loadedController() async {
  final controller = XboardMarqueeController(
    api: XboardMarqueeApi(
      unreadRequester: (_, _, _) async => {
        'status': 1,
        'data': {
          'items': [
            {
              'id': 123,
              'title': '线路维护通知',
              'marquee_text': '今晚 02:00 部分线路维护',
              'content': '预计维护十分钟。',
              'action_url': '/message/123',
            },
            {
              'id': 124,
              'title': '客户端通知',
              'marquee_text': '第二条消息',
              'content': '第二条详情',
              'action_url': '',
            },
          ],
        },
      },
    ),
  );
  await controller.updateSession(_session(), offline: false);
  return controller;
}

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

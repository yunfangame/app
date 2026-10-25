import 'dart:async';

import 'package:fl_clash/common/xboard_auth.dart';
import 'package:fl_clash/common/xboard_marquee.dart';
import 'package:fl_clash/state.dart';
import 'package:fl_clash/widgets/xboard_marquee_host.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    globalState.clearXboardSession();
    globalState.setOfflineMode(false);
    TestWidgetsFlutterBinding.ensureInitialized()
        .handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  });

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    globalState.clearXboardSession();
    globalState.setOfflineMode(false);
    TestWidgetsFlutterBinding.ensureInitialized()
        .handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  });

  testWidgets('Android lifecycle recovery never uses desktop window RPCs', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    var windowCalls = 0;
    const channels = [
      MethodChannel('window_manager'),
      MethodChannel('window_ext'),
    ];
    for (final channel in channels) {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
        call,
      ) async {
        windowCalls++;
        throw PlatformException(code: 'android_window_rpc_forbidden');
      });
    }
    final tokens = <String>[];
    final controller = _controller(tester, tokens);
    addTearDown(controller.dispose);
    globalState.activateXboardSession(_session('android'));
    try {
      await tester.pumpWidget(
        XboardMarqueeHost(controller: controller, child: const SizedBox()),
      );
      await tester.pump(Duration.zero);
      expect(tokens, ['android']);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      globalState.activateXboardSession(_session('android'));
      await tester.pump(const Duration(hours: 1));
      expect(tokens, ['android']);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump(Duration.zero);
      expect(tokens, ['android', 'android']);
      expect(windowCalls, 0);
    } finally {
      await tester.pumpWidget(const SizedBox());
      debugDefaultTargetPlatformOverride = null;
      for (final channel in channels) {
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          null,
        );
      }
    }
  });

  testWidgets('host session changes cannot fetch while app is paused', (
    tester,
  ) async {
    final tokens = <String>[];
    final controller = _controller(tester, tokens);
    addTearDown(controller.dispose);
    globalState.activateXboardSession(_session('first'));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    try {
      await tester.pumpWidget(
        XboardMarqueeHost(controller: controller, child: const SizedBox()),
      );
      await tester.pump(Duration.zero);
      globalState.activateXboardSession(_session('second'));
      await tester.pump(const Duration(hours: 1));
      expect(tokens, isEmpty);
      controller.setWindowForeground(false);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump(Duration.zero);
      expect(tokens, isEmpty);
      controller.setWindowForeground(true);
      await tester.pump(Duration.zero);
      expect(tokens, ['second']);
    } finally {
      await tester.pumpWidget(const SizedBox());
    }
  });

  testWidgets('offline recovery and lifecycle resume share one due refresh', (
    tester,
  ) async {
    final tokens = <String>[];
    final controller = _controller(tester, tokens);
    addTearDown(controller.dispose);
    globalState.activateXboardSession(_session('first'));
    globalState.setOfflineMode(true);
    try {
      await tester.pumpWidget(
        XboardMarqueeHost(controller: controller, child: const SizedBox()),
      );
      await tester.pump(const Duration(hours: 1));
      expect(tokens, isEmpty);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      globalState.setOfflineMode(false);
      await tester.pump(Duration.zero);
      expect(tokens, isEmpty);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      controller.setWindowForeground(true);
      globalState.setOfflineMode(false);
      await tester.pump(Duration.zero);
      expect(tokens, ['first']);
      globalState.activateXboardSession(_session('first'));
      await tester.pump(const Duration(minutes: 4));
      expect(tokens, ['first']);
      await tester.pump(const Duration(minutes: 1));
      expect(tokens, ['first', 'first']);
    } finally {
      await tester.pumpWidget(const SizedBox());
    }
    await tester.pump(const Duration(hours: 1));
    expect(tokens, ['first', 'first']);
  });

  testWidgets('interrupted unread replays once after returning', (
    tester,
  ) async {
    final pending = Completer<Object?>();
    final tokens = <String>[];
    final controller = XboardMarqueeController(
      now: tester.binding.clock.now,
      store: _Store(),
      api: XboardMarqueeApi(
        unreadRequester: (_, token, _) {
          tokens.add(token);
          return tokens.length == 1 ? pending.future : Future.value(_response);
        },
      ),
    );
    addTearDown(controller.dispose);
    globalState.activateXboardSession(_session('first'));
    try {
      await tester.pumpWidget(
        XboardMarqueeHost(controller: controller, child: const SizedBox()),
      );
      await tester.pump(Duration.zero);
      expect(tokens, hasLength(1));
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      globalState.activateXboardSession(_session('first'));
      await tester.pump(const Duration(seconds: 10));
      expect(tokens, hasLength(1));
      pending.complete(_response);
      await tester.pump(Duration.zero);
      expect(controller.messages.single.id, 7);
      expect(tokens, hasLength(2));
      await tester.pump(const Duration(minutes: 4, seconds: 59));
      expect(tokens, hasLength(2));
      await tester.pump(const Duration(seconds: 1));
      expect(tokens, hasLength(3));
    } finally {
      await tester.pumpWidget(const SizedBox());
    }
  });
}

XboardMarqueeController _controller(WidgetTester tester, List<String> tokens) =>
    XboardMarqueeController(
      now: tester.binding.clock.now,
      store: _Store(),
      api: XboardMarqueeApi(
        unreadRequester: (_, token, _) async {
          tokens.add(token);
          return _response;
        },
      ),
    );

const _response = {
  'status': 1,
  'data': {
    'items': [
      {'id': 7, 'marquee_text': '消息', 'title': '标题'},
    ],
  },
};

XboardLoginResult _session(String account) {
  final endpoint = Uri.parse('https://api.example.com');
  return XboardLoginResult(
    endpoint: endpoint,
    token: account,
    authData: account,
    isAdmin: false,
    subscription: XboardSubscriptionData(
      endpoint: endpoint,
      subscribeUrl: null,
      uploadBytes: 0,
      downloadBytes: 0,
      transferEnableBytes: 100,
      rawData: const {},
    ),
  );
}

class _Store extends XboardMarqueeQueueStore {
  @override
  Future<List<XboardMarqueeMessage>> load(String accountKey) async => const [];

  @override
  Future<void> save(
    String accountKey,
    List<XboardMarqueeMessage> messages,
  ) async {}
}

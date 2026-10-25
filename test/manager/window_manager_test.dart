import 'dart:async';

import 'package:fl_clash/common/xboard_auth.dart';
import 'package:fl_clash/common/xboard_marquee.dart';
import 'package:fl_clash/manager/window_manager.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _StoreAction extends StoreAction {
  int saveCalls = 0;

  @override
  void savePreferencesDebounce() {
    saveCalls++;
  }
}

class _Rig {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  late final controller = XboardMarqueeController(
    api: XboardMarqueeApi(
      unreadRequester: (_, _, _) async {
        requests++;
        return {
          'status': 1,
          'data': {'items': []},
        };
      },
    ),
  );
  late final container = ProviderContainer(
    overrides: [storeActionProvider.overrideWith(_StoreAction.new)],
  );
  int requests = 0;
  bool visible = true;
  bool minimized = false;
  bool focused = true;
  bool readStateFails = false;
  int stateReads = 0;
  Future<bool> Function()? readFocus;

  Future<void> mount(WidgetTester tester) async {
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('window_manager'),
      (call) async {
        if (call.method == 'isVisible') stateReads++;
        if (readStateFails &&
            {'isVisible', 'isMinimized', 'isFocused'}.contains(call.method)) {
          throw PlatformException(code: 'temporary_window_state');
        }
        return switch (call.method) {
          'isVisible' => visible,
          'isMinimized' => minimized,
          'isFocused' => readFocus?.call() ?? focused,
          _ => null,
        };
      },
    );
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('window_ext'),
      (call) async => null,
    );
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
      container.dispose();
      binding.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('window_manager'),
        null,
      );
      binding.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('window_ext'),
        null,
      );
    });
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: WindowManager(
          marqueeController: controller,
          child: const SizedBox(),
        ),
      ),
    );
    final endpoint = Uri.parse('https://api.example.com');
    await controller.updateSession(
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
  }

  Future<void> emit(String event) =>
      binding.defaultBinaryMessenger.handlePlatformMessage(
        'window_manager',
        const StandardMethodCodec().encodeMethodCall(
          MethodCall('onEvent', {'eventName': event}),
        ),
        (_) {},
      );
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('temporary initial state failure retries and resumes marquee', (
    tester,
  ) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    final rig = _Rig()..readStateFails = true;
    await rig.mount(tester);
    rig.controller.startPolling(foreground: true, offline: false);
    try {
      expect(rig.stateReads, 1);
      expect(rig.requests, 0);
      rig.readStateFails = false;
      await tester.pump(const Duration(milliseconds: 999));
      expect(rig.stateReads, 1);
      await tester.pump(const Duration(milliseconds: 1));
      await tester.pump(Duration.zero);
      expect(rig.stateReads, 2);
      expect(rig.requests, 1);
    } finally {
      rig.controller.stopPolling();
    }
  });

  testWidgets('window state retries use a bounded budget reset by show', (
    tester,
  ) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    final rig = _Rig()..readStateFails = true;
    await rig.mount(tester);
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
    expect(rig.controller.isForeground, isTrue);
  });

  for (final event in ['hide', 'blur', 'minimize']) {
    testWidgets('known window $event cancels native state retries', (
      tester,
    ) async {
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      final rig = _Rig()..readStateFails = true;
      await rig.mount(tester);
      await rig.emit(event);
      await tester.pump(const Duration(hours: 1));
      expect(rig.stateReads, 1);
      expect(rig.controller.isForeground, isFalse);
    });
  }

  testWidgets('native state retry waits for foreground app lifecycle', (
    tester,
  ) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    final rig = _Rig()..readStateFails = true;
    await rig.mount(tester);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    try {
      await tester.pump(const Duration(seconds: 1));
      expect(rig.stateReads, 1);
      rig.readStateFails = false;
    } finally {
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    }
    await rig.emit('show');
    await tester.pump(Duration.zero);
    expect(rig.stateReads, 2);
    expect(rig.controller.isForeground, isTrue);
  });

  testWidgets('disposing cancels native state retry', (tester) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    final rig = _Rig()..readStateFails = true;
    await rig.mount(tester);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(hours: 1));
    expect(rig.stateReads, 1);
  });

  testWidgets('legacy desktop manager preserves marquee window gates', (
    tester,
  ) async {
    final rig = _Rig()..visible = false;
    await rig.mount(tester);
    expect(rig.requests, 0);
    rig.visible = true;
    rig.focused = false;
    await rig.emit('show');
    await tester.pump(Duration.zero);
    await rig.controller.refresh(force: true);
    expect(rig.requests, 0);
    rig.focused = true;
    await rig.emit('focus');
    await rig.controller.refresh(force: true);
    expect(rig.requests, 1);
    await rig.emit('blur');
    await rig.controller.refresh(force: true);
    expect(rig.requests, 1);
    await rig.emit('minimize');
    rig.minimized = true;
    await rig.emit('restore');
    await tester.pump(Duration.zero);
    await rig.controller.refresh(force: true);
    expect(rig.requests, 1);
    final store =
        rig.container.read(storeActionProvider.notifier) as _StoreAction;
    expect(store.saveCalls, 1);
    rig.minimized = false;
    await rig.emit('restore');
    await tester.pump(Duration.zero);
    await rig.controller.refresh(force: true);
    expect(rig.requests, 2);
  });

  testWidgets('a late native result cannot reopen a hidden marquee gate', (
    tester,
  ) async {
    final focus = Completer<bool>();
    final rig = _Rig()
      ..visible = false
      ..readFocus = () => focus.future;
    await rig.mount(tester);
    rig.visible = true;
    await rig.emit('show');
    await rig.emit('hide');
    focus.complete(true);
    await tester.pump(Duration.zero);
    await rig.controller.refresh(force: true);
    expect(rig.requests, 0);
    rig.readFocus = null;
    await rig.emit('focus');
    await rig.controller.refresh(force: true);
    expect(rig.requests, 1);
  });

  testWidgets('a native state failure remains paused until a focus event', (
    tester,
  ) async {
    final rig = _Rig()
      ..readFocus = () async => throw PlatformException(code: 'temporary');
    await rig.mount(tester);
    await rig.controller.refresh(force: true);
    expect(rig.requests, 0);
    rig.readFocus = null;
    await rig.emit('focus');
    await rig.controller.refresh(force: true);
    expect(rig.requests, 1);
  });
}

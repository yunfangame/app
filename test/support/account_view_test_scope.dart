import 'package:fl_clash/state.dart';
import 'package:fl_clash/widgets/inherited.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

int accountViewWindowCalls = 0;
bool accountViewWindowVisible = true;
bool accountViewWindowFocused = true;
bool accountViewWindowQueryFails = false;

void accountViewReadTest(
  String description,
  WidgetTesterCallback callback, {
  TargetPlatform platform = TargetPlatform.android,
}) {
  testWidgets(description, (tester) async {
    final previous = debugDefaultTargetPlatformOverride;
    debugDefaultTargetPlatformOverride = platform;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    accountViewWindowCalls = 0;
    accountViewWindowVisible = true;
    accountViewWindowFocused = true;
    accountViewWindowQueryFails = false;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('window_manager'),
      (call) async {
        accountViewWindowCalls++;
        if (accountViewWindowQueryFails) {
          throw PlatformException(code: 'controlled_window_failure');
        }
        return switch (call.method) {
          'isVisible' => accountViewWindowVisible,
          'isMinimized' => false,
          'isFocused' => accountViewWindowFocused,
          _ => null,
        };
      },
    );
    globalState.setOfflineMode(false);
    try {
      await callback(tester);
    } finally {
      await tester.pumpWidget(const SizedBox());
      globalState.clearXboardSession();
      globalState.setOfflineMode(false);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('window_manager'),
        null,
      );
      debugDefaultTargetPlatformOverride = previous;
    }
  });
}

Future<ValueNotifier<bool>> mountAccountView(
  WidgetTester tester,
  Widget child,
  Widget Function(Widget child) appBuilder, {
  bool active = true,
  Size size = const Size(1000, 1200),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final activity = ValueNotifier(active);
  addTearDown(activity.dispose);
  await tester.pumpWidget(
    appBuilder(
      ValueListenableBuilder<bool>(
        valueListenable: activity,
        child: child,
        builder: (_, active, child) =>
            PageActivityScope(isActive: active, child: child!),
      ),
    ),
  );
  await flushAccountReads(tester);
  return activity;
}

Future<void> flushAccountReads(WidgetTester tester) async {
  await tester.pump(Duration.zero);
  await tester.pump(Duration.zero);
}

Future<void> accountViewWindowEvent(WidgetTester tester, String event) async {
  await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
    'window_manager',
    const StandardMethodCodec().encodeMethodCall(
      MethodCall('onEvent', {'eventName': event}),
    ),
    (_) {},
  );
}

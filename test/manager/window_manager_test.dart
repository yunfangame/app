import 'dart:async';

import 'package:fl_clash/common/render.dart';
import 'package:fl_clash/manager/window_manager.dart';
import 'package:fl_clash/models/config.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

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

  @override
  Future<void> refreshAutoLaunch() async {
    refreshCalls++;
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
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  late final ProviderContainer container;
  late final _SystemAction action;
  late final _StoreAction store;
  int boundsReads = 0;
  bool visible = true;
  bool minimized = false;
  Future<Map<String, double>> Function()? readBounds;

  Future<void> mount(WidgetTester tester, {bool isWindows = true}) async {
    const windowChannel = MethodChannel('window_manager');
    const extensionChannel = MethodChannel('window_ext');
    binding.defaultBinaryMessenger.setMockMethodCallHandler(windowChannel, (
      call,
    ) async {
      if (call.method == 'isVisible') return visible;
      if (call.method == 'isMinimized') return minimized;
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
        child: WindowManager(isWindows: isWindows, child: const SizedBox()),
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

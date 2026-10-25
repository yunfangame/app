import 'dart:async';

import 'package:fl_clash/common/api_request_router.dart';
import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/common/xboard_order_changes.dart';
import 'package:fl_clash/l10n/l10n.dart';
import 'package:fl_clash/state.dart';
import 'package:fl_clash/views/orders/fengwo_orders.dart';
import 'package:fl_clash/widgets/inherited.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/api_health_fixture.dart';

bool _windowVisible = true;
bool _windowMinimized = false;
bool _windowFocused = true;
bool _windowQueryFails = false;
int _windowCalls = 0;

void _ordersTest(String description, WidgetTesterCallback callback) {
  testWidgets(description, (tester) async {
    try {
      await callback(tester);
    } finally {
      await tester.pumpWidget(const SizedBox());
      debugDefaultTargetPlatformOverride = null;
    }
  });
}

void main() {
  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    final binding = TestWidgetsFlutterBinding.ensureInitialized();
    binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    _windowVisible = true;
    _windowMinimized = false;
    _windowFocused = true;
    _windowQueryFails = false;
    _windowCalls = 0;
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('window_manager'),
      (call) async {
        _windowCalls++;
        if (_windowQueryFails) throw PlatformException(code: 'unavailable');
        return switch (call.method) {
          'isVisible' => _windowVisible,
          'isMinimized' => _windowMinimized,
          'isFocused' => _windowFocused,
          _ => null,
        };
      },
    );
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('window_ext'),
      (call) async {
        _windowCalls++;
        return null;
      },
    );
  });

  tearDown(() {
    globalState.clearXboardSession();
    globalState.setOfflineMode(false);
    xboardOrderChanges.value = null;
    final binding = TestWidgetsFlutterBinding.ensureInitialized();
    binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('window_manager'),
      null,
    );
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('window_ext'),
      null,
    );
    debugDefaultTargetPlatformOverride = null;
  });

  _ordersTest('hidden orders defer changes and metadata updates stay idle', (
    tester,
  ) async {
    var requests = 0;
    final activity = await _mountOrders(
      tester,
      _testService(onRequested: () => requests++),
      active: false,
    );
    globalState.activateXboardSession(_testSession());
    invalidateXboardOrders(_testSession());
    await _flushOrders(tester);
    expect(requests, 0);
    activity.value = true;
    await tester.pumpAndSettle();
    expect(requests, 1);
    globalState.activateXboardSession(_testSession());
    await tester.pumpAndSettle();
    expect(requests, 1);
    expect(find.byKey(const ValueKey('order-row-order-6')), findsOneWidget);
    activity.value = false;
    await tester.pump();
    invalidateXboardOrders(_testSession());
    invalidateXboardOrders(_testSession());
    await tester.pump(const Duration(minutes: 10));
    expect(requests, 1);
    activity.value = true;
    await tester.pumpAndSettle();
    expect(requests, 2);
  });

  _ordersTest('a hidden account change clears orders and waits for entry', (
    tester,
  ) async {
    final accounts = <String>[];
    final activity = await _mountOrders(
      tester,
      _testService(onAuthRequested: accounts.add),
    );
    expect(accounts, ['Bearer account-token']);
    activity.value = false;
    await tester.pump();
    globalState.activateXboardSession(_testSession(authData: 'Bearer second'));
    await _flushOrders(tester);
    expect(accounts, hasLength(1));
    expect(find.byKey(const ValueKey('order-row-order-6')), findsNothing);
    activity.value = true;
    await tester.pumpAndSettle();
    expect(accounts, ['Bearer account-token', 'Bearer second']);
    invalidateXboardOrders(_testSession());
    await tester.pumpAndSettle();
    expect(accounts, hasLength(2));
  });

  for (final sameAuth in [false, true]) {
    _ordersTest(
      'old order replies cannot survive a session boundary $sameAuth',
      (tester) async {
        final pending = Completer<XboardLoginResponse>();
        var requests = 0;
        await _mountOrders(
          tester,
          _testService(
            orders: (_, _) async {
              requests++;
              return requests == 1
                  ? pending.future
                  : _ordersResponse('current');
            },
          ),
        );
        expect(requests, 1);
        globalState.clearXboardSession();
        globalState.activateXboardSession(
          _testSession(
            authData: sameAuth ? 'Bearer account-token' : 'Bearer second',
          ),
        );
        await _flushOrders(tester);
        expect(requests, 2);
        expect(find.byKey(const ValueKey('order-row-current')), findsOneWidget);
        pending.complete(_ordersResponse('old'));
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('order-row-current')), findsOneWidget);
        expect(find.byKey(const ValueKey('order-row-old')), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }

  _ordersTest(
    'manual refresh shares requests and mutations queue one refresh',
    (tester) async {
      final pending = Completer<XboardLoginResponse>();
      var requests = 0;
      await _mountOrders(
        tester,
        _testService(
          orders: (_, _) async {
            requests++;
            if (requests == 2) return pending.future;
            return _ordersResponse(requests == 1 ? 'initial' : 'updated');
          },
        ),
      );
      final refresh = tester.widget<RefreshIndicator>(
        find.byType(RefreshIndicator),
      );
      final first = refresh.onRefresh();
      final second = refresh.onRefresh();
      await _flushOrders(tester);
      expect(requests, 2);
      invalidateXboardOrders(_testSession());
      invalidateXboardOrders(_testSession());
      await _flushOrders(tester);
      expect(requests, 2);
      pending.complete(_ordersResponse('stale'));
      await Future.wait([first, second]);
      await tester.pumpAndSettle();
      expect(requests, 3);
      expect(find.byKey(const ValueKey('order-row-updated')), findsOneWidget);
      expect(find.byKey(const ValueKey('order-row-stale')), findsNothing);
      await tester.pump(const Duration(hours: 1));
      expect(requests, 3);
    },
  );

  for (final state in [
    AppLifecycleState.inactive,
    AppLifecycleState.hidden,
    AppLifecycleState.paused,
  ]) {
    _ordersTest('Android orders wait through $state and resume once', (
      tester,
    ) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      var requests = 0;
      await _mountOrders(tester, _testService(onRequested: () => requests++));
      expect(requests, 1);
      tester.binding.handleAppLifecycleStateChanged(state);
      invalidateXboardOrders(_testSession());
      globalState.activateXboardSession(_testSession());
      await tester.pump(const Duration(hours: 1));
      expect(requests, 1);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(requests, 2);
      expect(_windowCalls, 0);
    });
  }

  for (final event in ['hide', 'minimize', 'blur']) {
    _ordersTest('desktop orders stay idle during window $event', (
      tester,
    ) async {
      var requests = 0;
      await _mountOrders(tester, _testService(onRequested: () => requests++));
      expect(requests, 1);
      if (event == 'hide') _windowVisible = false;
      if (event == 'minimize') _windowMinimized = true;
      if (event == 'blur') _windowFocused = false;
      await _windowEvent(tester, event);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      invalidateXboardOrders(_testSession());
      await tester.pump(const Duration(hours: 1));
      expect(requests, 1);
      _windowVisible = true;
      _windowMinimized = false;
      _windowFocused = true;
      await _windowEvent(tester, 'show');
      await _windowEvent(tester, 'restore');
      await _windowEvent(tester, 'focus');
      await tester.pumpAndSettle();
      expect(requests, 2);
    });
  }

  _ordersTest('offline orders defer initial and repeated invalidations', (
    tester,
  ) async {
    globalState.setOfflineMode(true);
    var requests = 0;
    await _mountOrders(tester, _testService(onRequested: () => requests++));
    invalidateXboardOrders(_testSession());
    globalState.activateXboardSession(_testSession(authData: 'Bearer second'));
    await _flushOrders(tester);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    await tester.pump(const Duration(hours: 1));
    expect(requests, 0);
    globalState.setOfflineMode(false);
    await tester.pumpAndSettle();
    expect(requests, 1);
    globalState.setOfflineMode(true);
    invalidateXboardOrders(_testSession());
    await tester.pump(const Duration(hours: 1));
    expect(requests, 1);
    globalState.setOfflineMode(false);
    await tester.pumpAndSettle();
    expect(requests, 2);
  });

  _ordersTest('window state failures recover without blocking manual refresh', (
    tester,
  ) async {
    _windowQueryFails = true;
    var requests = 0;
    await _mountOrders(tester, _testService(onRequested: () => requests++));
    expect(requests, 0);
    await tester.tap(find.byKey(const ValueKey('refresh-orders')));
    await _flushOrders(tester);
    expect(requests, 1);
    _windowQueryFails = false;
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(requests, 1);
    _windowVisible = false;
    await _windowEvent(tester, 'hide');
    await tester.tap(find.byKey(const ValueKey('refresh-orders')));
    await _flushOrders(tester);
    expect(requests, 1);
  });

  _ordersTest('an unavailable window query retries the initial order load', (
    tester,
  ) async {
    _windowQueryFails = true;
    var requests = 0;
    await _mountOrders(tester, _testService(onRequested: () => requests++));
    expect(requests, 0);
    _windowQueryFails = false;
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(requests, 1);
  });

  _ordersTest('a failed order query waits for an explicit retry', (
    tester,
  ) async {
    var requests = 0;
    await _mountOrders(
      tester,
      _testService(
        orders: (_, _) async {
          requests++;
          if (requests == 1) throw StateError('controlled_failure');
          return _ordersResponse('recovered');
        },
      ),
    );
    await tester.pump(const Duration(hours: 1));
    expect(requests, 1);
    await tester.tap(find.byKey(const ValueKey('refresh-orders')));
    await tester.pumpAndSettle();
    expect(requests, 2);
    expect(find.byKey(const ValueKey('order-row-recovered')), findsOneWidget);
  });

  _ordersTest('disposing an order query ignores its reply and later changes', (
    tester,
  ) async {
    final pending = Completer<XboardLoginResponse>();
    var requests = 0;
    await _mountOrders(
      tester,
      _testService(
        orders: (_, _) async {
          requests++;
          return pending.future;
        },
      ),
    );
    await tester.pumpWidget(const SizedBox());
    pending.complete(_ordersResponse('disposed'));
    invalidateXboardOrders(_testSession());
    await tester.pumpAndSettle();
    expect(requests, 1);
    expect(tester.takeException(), isNull);
  });

  _ordersTest('orders page paginates, shows details, and cancels an order', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(globalState.clearXboardSession);
    globalState.xboardSession = _testSession();
    var requests = 0;
    var cancelled = false;

    await tester.pumpWidget(
      _TestApp(
        child: FengWoOrdersView(
          pageSize: 3,
          authService: _testService(
            onRequested: () => requests++,
            isCancelled: () => cancelled,
            onCancelled: () => cancelled = true,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final l10n = tester.element(find.byType(FengWoOrdersView)).appLocalizations;
    expect(find.text(l10n.myOrders), findsNWidgets(2));
    expect(find.byKey(const ValueKey('order-row-order-6')), findsOne);
    expect(find.byKey(const ValueKey('order-row-order-3')), findsNothing);
    expect(find.text(l10n.orderPageIndicator(1, 3)), findsOne);
    expect(requests, 1);

    await tester.tap(find.byKey(const ValueKey('orders-next-page')));
    await tester.pump();
    expect(find.byKey(const ValueKey('order-row-order-3')), findsOne);
    expect(find.text(l10n.orderPageIndicator(2, 3)), findsOne);
    expect(requests, 1);

    await tester.tap(find.byKey(const ValueKey('orders-previous-page')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('order-detail-order-6')));
    await tester.pumpAndSettle();
    expect(find.text(l10n.orderDetailsTitle), findsOne);
    expect(find.text('测试套餐 6'), findsOne);
    await tester.tap(find.widgetWithText(FilledButton, l10n.done));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('order-cancel-order-6')));
    await tester.pumpAndSettle();
    expect(find.text(l10n.cancelOrderTitle), findsOne);
    await tester.tap(find.widgetWithText(FilledButton, l10n.cancelOrder));
    await tester.pumpAndSettle();

    expect(cancelled, isTrue);
    expect(requests, 2);
    expect(
      xboardOrderChanges.value?.matches(globalState.xboardSession),
      isTrue,
    );
    final cancelButton = tester.widget<TextButton>(
      find.byKey(const ValueKey('order-cancel-order-6')),
    );
    expect(cancelButton.onPressed, isNull);
    expect(tester.takeException(), isNull);
  });

  _ordersTest('orders page uses mobile cards in a dark narrow viewport', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(globalState.clearXboardSession);
    globalState.xboardSession = _testSession();

    await tester.pumpWidget(
      _TestApp(
        themeMode: ThemeMode.dark,
        child: FengWoOrdersView(pageSize: 3, authService: _testService()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('fengwo-orders-scroll')), findsOne);
    expect(find.byKey(const ValueKey('order-card-order-6')), findsOne);
    expect(find.byKey(const ValueKey('order-row-order-6')), findsNothing);
    expect(tester.takeException(), isNull);
  });
}

Future<ValueNotifier<bool>> _mountOrders(
  WidgetTester tester,
  XboardAuthService service, {
  bool active = true,
}) async {
  tester.view.physicalSize = const Size(1440, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  globalState.activateXboardSession(_testSession());
  final activity = ValueNotifier(active);
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox());
    activity.dispose();
  });
  await tester.pumpWidget(
    _TestApp(
      child: ValueListenableBuilder<bool>(
        valueListenable: activity,
        child: FengWoOrdersView(authService: service),
        builder: (_, active, child) =>
            PageActivityScope(isActive: active, child: child!),
      ),
    ),
  );
  await _flushOrders(tester);
  return activity;
}

Future<void> _flushOrders(WidgetTester tester) async {
  await tester.pump(Duration.zero);
  await tester.pump(Duration.zero);
}

Future<void> _windowEvent(WidgetTester tester, String event) async {
  await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
    'window_manager',
    const StandardMethodCodec().encodeMethodCall(
      MethodCall('onEvent', {'eventName': event}),
    ),
    (_) {},
  );
}

XboardLoginResponse _ordersResponse(String tradeNo) => XboardLoginResponse(
  statusCode: 200,
  data: {
    'data': [
      {
        'id': 1,
        'trade_no': tradeNo,
        'period': 'month_price',
        'total_amount': 800,
        'status': 3,
        'created_at': 1787992800,
        'plan': {'name': 'controlled-plan'},
      },
    ],
  },
);

XboardAuthService _testService({
  VoidCallback? onRequested,
  ValueChanged<String>? onAuthRequested,
  Future<XboardLoginResponse> Function(Uri, String)? orders,
  bool Function()? isCancelled,
  VoidCallback? onCancelled,
}) {
  return XboardAuthService(
    requestRouter: ApiRequestRouter(),
    apiHealthService: ApiHealthFixture(Uri.parse('https://api.example.com')),
    ordersRequester: (endpoint, authData) async {
      onRequested?.call();
      onAuthRequested?.call(authData);
      if (orders != null) return orders(endpoint, authData);
      return XboardLoginResponse(
        statusCode: 200,
        data: {
          'data': [
            for (var index = 0; index < 7; index++)
              {
                'id': index,
                'trade_no': 'order-$index',
                'period': index.isEven ? 'month_price' : 'reset_price',
                'total_amount': index.isEven ? 800 : 700,
                'status': index == 6
                    ? (isCancelled?.call() == true ? 2 : 0)
                    : 3,
                'created_at': 1787992800 + index * 60,
                'plan': {'name': '测试套餐 $index'},
              },
          ],
        },
      );
    },
    orderDetailRequester: (endpoint, authData) async {
      final tradeNo = endpoint.queryParameters['trade_no']!;
      final index = int.parse(tradeNo.split('-').last);
      return XboardLoginResponse(
        statusCode: 200,
        data: {
          'data': {
            'id': index,
            'trade_no': tradeNo,
            'period': 'month_price',
            'total_amount': 800,
            'status': 0,
            'created_at': 1787992800 + index * 60,
            'plan': {'name': '测试套餐 $index'},
            'payment': {'name': '支付宝'},
          },
        },
      );
    },
    orderCancelRequester: (endpoint, authData, tradeNo) async {
      onCancelled?.call();
      return const XboardLoginResponse(statusCode: 200, data: {'data': true});
    },
  );
}

XboardLoginResult _testSession({String authData = 'Bearer account-token'}) {
  final endpoint = Uri.parse('https://api.example.com');
  return XboardLoginResult(
    endpoint: endpoint,
    token: 'subscription-token',
    authData: authData,
    isAdmin: false,
    subscription: XboardSubscriptionData(
      endpoint: endpoint,
      subscribeUrl: Uri.parse('https://api.example.com/subscribe'),
      uploadBytes: 0,
      downloadBytes: 0,
      transferEnableBytes: bytesPerGigabyte * 60,
      rawData: const {},
    ),
  );
}

class _TestApp extends StatelessWidget {
  final Widget child;
  final ThemeMode themeMode;

  const _TestApp({required this.child, this.themeMode = ThemeMode.light});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF2468E8)),
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF78A7FF),
          brightness: Brightness.dark,
        ),
      ),
      themeMode: themeMode,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.delegate.supportedLocales,
      home: child,
    );
  }
}

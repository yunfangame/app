import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/l10n/l10n.dart';
import 'package:fl_clash/state.dart';
import 'package:fl_clash/views/orders/fengwo_orders.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('orders page paginates, shows details, and cancels an order', (
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
    final cancelButton = tester.widget<TextButton>(
      find.byKey(const ValueKey('order-cancel-order-6')),
    );
    expect(cancelButton.onPressed, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('orders page uses mobile cards in a dark narrow viewport', (
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

XboardAuthService _testService({
  VoidCallback? onRequested,
  bool Function()? isCancelled,
  VoidCallback? onCancelled,
}) {
  return XboardAuthService(
    ordersRequester: (endpoint, authData) async {
      onRequested?.call();
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

XboardLoginResult _testSession() {
  final endpoint = Uri.parse('https://api.example.com');
  return XboardLoginResult(
    endpoint: endpoint,
    token: 'subscription-token',
    authData: 'Bearer account-token',
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

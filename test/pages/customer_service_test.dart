import 'package:fl_clash/l10n/l10n.dart';
import 'package:fl_clash/pages/customer_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('uses the configured SaleSmartly service link', () {
    expect(saleSmartlyServiceUrl, 'https://kefu.wxbaohe.com');
  });

  test('uses responsive customer-service panel dimensions', () {
    expect(
      customerServicePanelSize(const Size(390, 844)),
      const Size(390, 844),
    );
    expect(
      customerServicePanelSize(const Size(800, 700)),
      const Size(720, 668),
    );
    expect(
      customerServicePanelSize(const Size(1000, 700)),
      const Size(880, 668),
    );
    expect(
      customerServicePanelSize(const Size(1200, 800)),
      const Size(1008, 768),
    );
    expect(
      customerServicePanelSize(const Size(1800, 1200)),
      const Size(1224, 1168),
    );
  });

  test('uses the compact SaleSmartly composer on desktop WebViews', () {
    expect(saleSmartlyDesktopUserAgent, contains('Mobile'));
    expect(saleSmartlyDesktopUserAgent, contains('iPhone'));
  });

  test('prevents the SaleSmartly document from overflowing horizontally', () {
    expect(saleSmartlyLayoutFixScript, contains('overflow-x: hidden'));
    expect(saleSmartlyLayoutFixScript, contains('overflow-wrap: anywhere'));
    expect(saleSmartlyLayoutFixScript, contains('scrollLeft = 0'));
  });

  testWidgets('customer service opens as a masked right side sheet', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      _testApp(
        home: Builder(
          builder: (context) => FilledButton(
            onPressed: () => CustomerServiceSheet.show(context, serviceUrl: ''),
            child: const Text('Open'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('customer-service-sheet')), findsOneWidget);
    expect(find.byType(AnimatedModalBarrier), findsOneWidget);
    expect(find.text('在线客服'), findsOneWidget);
    expect(
      tester.getSize(find.byKey(const Key('customer-service-sheet'))).width,
      1008,
    );
    expect(
      tester.getSize(find.byKey(const Key('customer-service-sheet'))).height,
      768,
    );

    await tester.tap(find.byKey(const Key('customer-service-close')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('customer-service-sheet')), findsNothing);
  });

  testWidgets('customer service view can host embedded chat content', (
    tester,
  ) async {
    await tester.pumpWidget(
      _testApp(
        home: CustomerServiceView(
          serviceUrl: 'https://chat.example.com/service/example-id',
          contentBuilder: (_) => const Text('SaleSmartly chat'),
        ),
      ),
    );

    expect(find.text('SaleSmartly chat'), findsOneWidget);
  });
}

Widget _testApp({required Widget home}) {
  return MaterialApp(
    locale: const Locale('zh', 'CN'),
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
    ],
    supportedLocales: AppLocalizations.delegate.supportedLocales,
    home: Scaffold(body: home),
  );
}

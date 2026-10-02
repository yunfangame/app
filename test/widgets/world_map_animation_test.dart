import 'package:fl_clash/l10n/l10n.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/views/dashboard/fengwo_desktop_dashboard.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final scenario in [
    (name: 'disconnected', running: false, selected: false, delay: 80),
    (name: 'selected', running: false, selected: true, delay: 80),
    (name: 'connected', running: true, selected: true, delay: 80),
    (name: 'latency testing', running: true, selected: true, delay: 0),
  ]) {
    testWidgets('100-node map stays idle when ${scenario.name}', (
      tester,
    ) async {
      await tester.pumpWidget(
        _MapApp(
          child: FengWoWorldMap(
            isStart: scenario.running,
            showRoute: scenario.running,
            opacity: 0.8,
            nodeName: scenario.selected ? '新加坡节点-0' : '',
            ipInfo: const IpInfo(
              ip: '198.51.100.1',
              countryCode: 'CN',
              latitude: 31.2304,
              longitude: 121.4737,
            ),
            nodes: List.generate(
              100,
              (index) => FengWoWorldMapNode(
                name: '新加坡节点-$index',
                delay: scenario.delay,
                countryCode: 'SG',
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      expect(tester.binding.transientCallbackCount, 0);
      expect(tester.binding.hasScheduledFrame, isFalse);
      if (scenario.running) {
        final route = tester.widget<PolylineLayer>(find.byType(PolylineLayer));
        expect(route.polylines.single.points, hasLength(2));
        expect(
          route.polylines.single.points.first.latitude,
          closeTo(31.2304, 0.001),
        );
        expect(find.byKey(const ValueKey('fengwo-route-user')), findsOneWidget);
        expect(find.byKey(const ValueKey('fengwo-route-node')), findsOneWidget);
      }
      expect(find.byKey(const ValueKey('fengwo-route-progress')), findsNothing);
      expect(
        find.byKey(const ValueKey('fengwo-user-focus-pulse')),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('connecting and opening map labels leave no animation ticker', (
    tester,
  ) async {
    final running = ValueNotifier(false);
    addTearDown(running.dispose);
    await tester.pumpWidget(
      _MapApp(
        child: ValueListenableBuilder<bool>(
          valueListenable: running,
          builder: (_, isStart, _) => FengWoWorldMap(
            isStart: isStart,
            showRoute: true,
            opacity: 0.8,
            nodeName: '新加坡节点',
            nodes: const [
              FengWoWorldMapNode(name: '新加坡节点', delay: 80, countryCode: 'SG'),
              FengWoWorldMapNode(name: '日本节点', delay: 90, countryCode: 'JP'),
            ],
          ),
        ),
      ),
    );
    await tester.pump();
    running.value = true;
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('fengwo-map-node-日本节点')));
    await tester.pump();

    expect(
      find.byKey(const ValueKey('fengwo-map-node-label-日本节点')),
      findsOneWidget,
    );
    expect(tester.binding.transientCallbackCount, 0);
    expect(tester.binding.hasScheduledFrame, isFalse);
    running.value = false;
    await tester.pump();
    expect(tester.binding.transientCallbackCount, 0);
    await tester.pumpWidget(const SizedBox.shrink());
    expect(tester.binding.transientCallbackCount, 0);
    expect(tester.takeException(), isNull);
  });
}

class _MapApp extends StatelessWidget {
  final Widget child;

  const _MapApp({required this.child});

  @override
  Widget build(BuildContext context) => MaterialApp(
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
    ],
    supportedLocales: AppLocalizations.delegate.supportedLocales,
    home: Scaffold(body: child),
  );
}

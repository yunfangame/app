import 'package:fl_clash/common/api_health.dart';
import 'package:fl_clash/l10n/l10n.dart';
import 'package:fl_clash/widgets/api_health_indicator.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('shows percentage details and refreshes remote config', (
    tester,
  ) async {
    var configLoads = 0;
    final service = ApiHealthService(
      configUrl: 'https://config.example.com/app.json',
      configLoader: (_) async {
        configLoads++;
        return {
          'Authentication': 'FengWo',
          'hosts': List.generate(
            5,
            (index) => 'https://api-$index.example.com',
          ),
        };
      },
      endpointProbe: (endpoint) async => endpoint.host != 'api-4.example.com',
    );

    await tester.pumpWidget(_testApp(service));
    await tester.pumpAndSettle();

    expect(configLoads, 1);
    expect(find.byKey(const Key('api-health-status-button')), findsOneWidget);
    expect(find.byKey(const Key('api-health-refresh-button')), findsNothing);
    final dot = tester.widget<Container>(
      find.byKey(const Key('api-health-status-dot')),
    );
    expect((dot.decoration! as BoxDecoration).color, const Color(0xFF2BD984));

    await tester.tap(find.byKey(const Key('api-health-status-button')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('api-health-dialog')), findsOneWidget);
    expect(find.text('4/5'), findsOneWidget);
    expect(find.text('站点1'), findsWidgets);
    expect(
      find.byKey(const Key('api-health-refresh-config-button')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('api-health-test-all-button')), findsOneWidget);
    expect(find.text('api-0.example.com'), findsNothing);

    await tester.tap(find.byKey(const Key('api-health-refresh-config-button')));
    await tester.pumpAndSettle();

    expect(configLoads, 2);
    await tester.tap(find.byKey(const Key('api-health-endpoint-1')));
    await tester.pumpAndSettle();
    expect(find.text('站点2'), findsWidgets);
    await tester.tap(find.byKey(const Key('api-health-confirm-button')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('api-health-dialog')), findsNothing);
    expect((await service.loadPreferredEndpoint())?.host, 'api-1.example.com');
  });

  testWidgets('service status dialog fits a narrow dark theme viewport', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final service = ApiHealthService(
      configUrl: 'https://config.example.com/app.json',
      configLoader: (_) async => {
        'Authentication': 'FengWo',
        'hosts': ['https://api.example.com'],
      },
      endpointProbe: (_) async => true,
    );

    await tester.pumpWidget(
      _testApp(service, themeMode: ThemeMode.dark, locale: const Locale('ru')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('api-health-status-button')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('api-health-dialog')), findsOneWidget);
    expect(find.text('1/1'), findsOneWidget);
    expect(find.byKey(const Key('api-health-confirm-button')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

Widget _testApp(
  ApiHealthService service, {
  ThemeMode themeMode = ThemeMode.light,
  Locale locale = const Locale('zh', 'CN'),
}) {
  return MaterialApp(
    themeMode: themeMode,
    theme: ThemeData(colorSchemeSeed: const Color(0xFF2268E7)),
    darkTheme: ThemeData(
      brightness: Brightness.dark,
      colorSchemeSeed: const Color(0xFF7D8DFF),
    ),
    locale: locale,
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
    ],
    supportedLocales: AppLocalizations.delegate.supportedLocales,
    home: Scaffold(
      backgroundColor: const Color(0xFF12103D),
      body: Center(child: ApiHealthControl(service: service)),
    ),
  );
}

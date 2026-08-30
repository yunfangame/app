import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/common/campus_network.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/l10n/l10n.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/state.dart';
import 'package:fl_clash/views/settings/fengwo_advanced_settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('advanced settings render and update the real configuration', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final updatedResources = <GeoResource>[];
    var campusCoreRestarts = 0;
    var campusConfigLoads = 0;
    final container = ProviderContainer();
    addTearDown(container.dispose);
    globalState.container = container;
    container.read(viewSizeProvider.notifier).value = const Size(1280, 1000);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: _TestApp(
          child: FengWoAdvancedSettingsView(
            geoResourceUpdater: (resource) async {
              updatedResources.add(resource);
            },
            campusNetworkConfigLoader: () async {
              campusConfigLoads++;
              if (campusConfigLoads > 1) {
                throw StateError('campus API is unavailable');
              }
              return const CampusNetworkConfig({
                'telecom': {'base.fengwo1688.cc': '114.80.8.196'},
                'unicom': {'base.fengwo1688.cc': '112.65.199.196'},
                'mobile': {'base.fengwo1688.cc': '120.233.118.84'},
              });
            },
            campusNetworkCoreRestarter: () async {
              campusCoreRestarts++;
            },
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.byKey(const ValueKey('advanced-proxy-card')), findsOne);
    expect(find.byKey(const ValueKey('advanced-ipv6-card')), findsOne);
    expect(find.byKey(const ValueKey('advanced-geodata-card')), findsOne);
    expect(
      find.byKey(const ValueKey('advanced-campus-network-card')),
      findsOne,
    );
    expect(find.byKey(const ValueKey('advanced-dns-card')), findsOne);

    await tester.tap(find.byKey(const ValueKey('advanced-allow-lan-switch')));
    await tester.pump();
    expect(container.read(patchClashConfigProvider).allowLan, isTrue);

    await tester.tap(find.byKey(const ValueKey('advanced-core-ipv6-switch')));
    await tester.pump();
    expect(container.read(patchClashConfigProvider).ipv6, isTrue);

    await tester.tap(find.byKey(const ValueKey('advanced-dns-ipv6-switch')));
    await tester.pump();
    expect(container.read(patchClashConfigProvider).dns.ipv6, isTrue);

    await tester.tap(find.byKey(const ValueKey('advanced-mixed-port-button')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), '8080');
    final l10n = tester
        .element(find.byType(FengWoAdvancedSettingsView))
        .appLocalizations;
    await tester.tap(find.text(l10n.submit));
    await tester.pumpAndSettle();
    expect(container.read(patchClashConfigProvider).mixedPort, 8080);

    final dnsModeTile = find.byKey(const ValueKey('advanced-dns-mode-tile'));
    await tester.ensureVisible(dnsModeTile);
    await tester.pumpAndSettle();
    await tester.tap(dnsModeTile);
    await tester.pumpAndSettle();
    await tester.tap(find.text('redir-host').last);
    await tester.pumpAndSettle();
    expect(
      container.read(patchClashConfigProvider).dns.enhancedMode,
      DnsMode.redirHost,
    );

    final geoIpUpdate = find.byKey(const ValueKey('advanced-update-GEOIP'));
    await tester.ensureVisible(geoIpUpdate);
    await tester.pumpAndSettle();
    await tester.tap(geoIpUpdate);
    await tester.pumpAndSettle();
    expect(updatedResources, [GeoResource.GEOIP]);

    final campusSwitch = find.byKey(
      const ValueKey('advanced-campus-network-switch'),
    );
    await tester.ensureVisible(campusSwitch);
    await tester.pumpAndSettle();
    await tester.tap(campusSwitch);
    await tester.pumpAndSettle();
    expect(container.read(appSettingProvider).campusNetworkEnabled, isTrue);
    expect(campusCoreRestarts, 1);
    expect(campusConfigLoads, 1);

    await tester.tap(campusSwitch);
    await tester.pumpAndSettle();
    expect(container.read(appSettingProvider).campusNetworkEnabled, isFalse);
    expect(campusCoreRestarts, 2);

    await tester.tap(campusSwitch);
    await tester.pumpAndSettle();
    expect(container.read(appSettingProvider).campusNetworkEnabled, isTrue);
    expect(campusCoreRestarts, 3);
    expect(campusConfigLoads, 1);

    expect(tester.takeException(), isNull);
  });

  testWidgets('advanced settings use one scroll view on a narrow dark screen', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      const ProviderScope(
        child: _TestApp(
          themeMode: ThemeMode.dark,
          child: FengWoAdvancedSettingsView(),
        ),
      ),
    );
    await tester.pump();

    expect(
      find.byKey(const ValueKey('fengwo-advanced-settings-scroll')),
      findsOne,
    );
    expect(find.byType(CustomScrollView), findsOne);
    expect(find.byKey(const ValueKey('advanced-proxy-card')), findsOne);
    expect(find.byKey(const ValueKey('advanced-ipv6-card')), findsOne);
    expect(find.byKey(const ValueKey('advanced-geodata-card')), findsOne);
    expect(
      find.byKey(const ValueKey('advanced-campus-network-card')),
      findsOne,
    );
    expect(find.byKey(const ValueKey('advanced-dns-card')), findsOne);
    expect(tester.takeException(), isNull);
  });

  testWidgets('advanced settings keep paired cards on tablet widths', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(760, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      const ProviderScope(child: _TestApp(child: FengWoAdvancedSettingsView())),
    );
    await tester.pump();

    final proxy = tester.getTopLeft(
      find.byKey(const ValueKey('advanced-proxy-card')),
    );
    final ipv6 = tester.getTopLeft(
      find.byKey(const ValueKey('advanced-ipv6-card')),
    );
    final geodata = tester.getTopLeft(
      find.byKey(const ValueKey('advanced-geodata-card')),
    );
    final campus = tester.getTopLeft(
      find.byKey(const ValueKey('advanced-campus-network-card')),
    );
    final dns = tester.getTopLeft(
      find.byKey(const ValueKey('advanced-dns-card')),
    );

    expect(ipv6.dx, greaterThan(proxy.dx));
    expect((ipv6.dy - proxy.dy).abs(), lessThan(1));
    expect(dns.dx, greaterThan(campus.dx));
    expect((dns.dy - campus.dy).abs(), lessThan(1));
    expect(campus.dy, greaterThan(proxy.dy));
    expect(geodata.dy, greaterThan(campus.dy));
    expect(
      (tester
                  .getSize(find.byKey(const ValueKey('advanced-proxy-card')))
                  .height -
              tester
                  .getSize(find.byKey(const ValueKey('advanced-ipv6-card')))
                  .height)
          .abs(),
      lessThan(1),
    );
    expect(
      (tester
                  .getSize(
                    find.byKey(const ValueKey('advanced-campus-network-card')),
                  )
                  .height -
              tester
                  .getSize(find.byKey(const ValueKey('advanced-dns-card')))
                  .height)
          .abs(),
      lessThan(1),
    );
    expect(tester.takeException(), isNull);
  });
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

import 'dart:async';

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/common/campus_network.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/l10n/l10n.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/state.dart';
import 'package:fl_clash/views/application_setting.dart';
import 'package:fl_clash/views/settings/fengwo_advanced_settings.dart';
import 'package:fl_clash/widgets/inherited.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final size in [const Size(390, 844), const Size(760, 1000)]) {
    testWidgets(
      'startup auto-connect defaults off and toggles on Android at ${size.width}',
      (tester) async {
        final container = await _pumpCampusSettings(
          tester,
          loadConfig: _loadTwoCampusLines,
          size: size,
        );
        final l10n = tester
            .element(find.byType(FengWoAdvancedSettingsView))
            .appLocalizations;
        final startupCard = find.byKey(const ValueKey('advanced-startup-card'));
        final autoConnect = find.byKey(
          const ValueKey('advanced-auto-connect-switch'),
        );
        final updateRect = tester.getRect(
          find.byKey(const ValueKey('advanced-software-update-card')),
        );
        final startupRect = tester.getRect(startupCard);
        final proxyRect = tester.getRect(
          find.byKey(const ValueKey('advanced-proxy-card')),
        );

        expect(find.text(l10n.startupSettings), findsOne);
        expect(find.text(l10n.autoRunDesc), findsOne);
        expect(
          find.descendant(of: startupCard, matching: find.byType(AutoRunItem)),
          findsOne,
        );
        expect(find.byType(AutoLaunchItem), findsNothing);
        expect(startupRect.width, updateRect.width);
        expect(startupRect.top, greaterThan(updateRect.bottom));
        expect(proxyRect.top, greaterThan(startupRect.bottom));
        expect(container.read(appSettingProvider).autoRun, isFalse);
        expect(tester.widget<Switch>(autoConnect).value, isFalse);

        await tester.ensureVisible(autoConnect);
        await tester.pumpAndSettle();
        await tester.tap(autoConnect);
        await tester.pumpAndSettle();

        expect(container.read(appSettingProvider).autoRun, isTrue);
        expect(tester.widget<Switch>(autoConnect).value, isTrue);

        await tester.ensureVisible(find.text(l10n.autoRun));
        await tester.pumpAndSettle();
        await tester.tap(find.text(l10n.autoRun));
        await tester.pumpAndSettle();

        expect(container.read(appSettingProvider).autoRun, isFalse);
        expect(tester.widget<Switch>(autoConnect).value, isFalse);
        expect(container.read(appSettingProvider).autoLaunch, isFalse);
        expect(tester.takeException(), isNull);
      },
      variant: const TargetPlatformVariant({TargetPlatform.android}),
    );
  }

  for (final platform in [
    TargetPlatform.android,
    TargetPlatform.iOS,
    TargetPlatform.macOS,
    TargetPlatform.windows,
    TargetPlatform.linux,
  ]) {
    testWidgets(
      'application routing entry is absent from advanced settings on $platform',
      (tester) async {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final container = ProviderContainer(
          overrides: [
            currentProfileProvider.overrideWithValue(null),
            systemActionProvider.overrideWith(_RoutingSystemAction.new),
          ],
        );
        addTearDown(container.dispose);
        globalState.container = container;
        container.read(viewSizeProvider.notifier).value = const Size(390, 844);
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: const _TestApp(
              child: FengWoAdvancedSettingsView(
                campusNetworkConfigLoader: _loadTwoCampusLines,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final entry = find.byKey(const ValueKey('advanced-app-routing-tile'));
        expect(entry, findsNothing);
        expect(tester.takeException(), isNull);
      },
      variant: TargetPlatformVariant({platform}),
    );
  }

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
    var diagnosticExports = 0;
    var diagnosticRuns = 0;
    final container = ProviderContainer(
      overrides: [currentProfileProvider.overrideWithValue(null)],
    );
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
              return const CampusNetworkConfig({
                'telecom': {'base.fengwo1688.cc': '114.80.8.196'},
                'unicom': {'base.fengwo1688.cc': '112.65.199.196'},
              });
            },
            campusNetworkCoreRestarter: () async {
              campusCoreRestarts++;
            },
            diagnosticLogExporter: () async {
              diagnosticExports++;
              return true;
            },
            networkDiagnosticRunner: () async {
              diagnosticRuns++;
              return const NetworkDiagnosticReport(
                code: 'W-NET-OK',
                summary: 'ready',
                steps: [],
              );
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
    expect(find.byKey(const ValueKey('advanced-diagnostic-card')), findsOne);

    await tester.tap(find.byKey(const ValueKey('advanced-allow-lan-switch')));
    await tester.pump();
    expect(container.read(patchClashConfigProvider).allowLan, isTrue);

    await tester.tap(
      find.byKey(const ValueKey('advanced-system-proxy-switch')),
    );
    await tester.pump();
    expect(container.read(networkSettingProvider).systemProxy, isFalse);

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
    expect(campusConfigLoads, 2);

    final runDiagnostics = find.byKey(
      const ValueKey('advanced-run-network-diagnostics'),
    );
    await tester.ensureVisible(runDiagnostics);
    await tester.pumpAndSettle();
    await tester.tap(runDiagnostics);
    await tester.pumpAndSettle();
    expect(diagnosticRuns, 1);
    expect(
      find.byKey(const ValueKey('advanced-network-diagnostic-result')),
      findsOne,
    );

    final exportLogs = find.byKey(
      const ValueKey('advanced-export-diagnostic-logs'),
    );
    await tester.ensureVisible(exportLogs);
    await tester.pumpAndSettle();
    await tester.tap(exportLogs);
    await tester.pumpAndSettle();
    expect(diagnosticExports, 1);

    await tester.ensureVisible(campusSwitch);
    await tester.pumpAndSettle();
    await tester.tap(campusSwitch);
    await tester.pumpAndSettle();
    expect(container.read(appSettingProvider).campusNetworkEnabled, isFalse);
    expect(campusCoreRestarts, 2);

    await tester.tap(campusSwitch);
    await tester.pumpAndSettle();
    expect(container.read(appSettingProvider).campusNetworkEnabled, isTrue);
    expect(campusCoreRestarts, 3);
    expect(campusConfigLoads, 3);

    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'entering settings replaces three cached lines with two remote lines',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final container = ProviderContainer(
        overrides: [currentProfileProvider.overrideWithValue(null)],
      );
      addTearDown(container.dispose);
      globalState.container = container;
      container.read(viewSizeProvider.notifier).value = const Size(1280, 1000);
      container.read(appSettingProvider.notifier).value = const AppSettingProps(
        campusOperator: 'mobile',
        campusHostsByOperator: {
          'telecom': {'base.fengwo1688.cc': '192.0.2.1'},
          'unicom': {'base.fengwo1688.cc': '192.0.2.2'},
          'mobile': {'base.fengwo1688.cc': '192.0.2.3'},
        },
      );

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const _TestApp(
            child: FengWoAdvancedSettingsView(
              campusNetworkConfigLoader: _loadTwoCampusLines,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final refreshed = container.read(appSettingProvider);
      expect(refreshed.campusHostsByOperator.keys, ['telecom', 'unicom']);
      expect(refreshed.campusOperator, 'telecom');

      final lineTile = find.byKey(
        const ValueKey('advanced-campus-network-line-tile'),
      );
      await tester.ensureVisible(lineTile);
      await tester.pumpAndSettle();
      await tester.tap(lineTile);
      await tester.pumpAndSettle();

      final l10n = tester
          .element(find.byType(FengWoAdvancedSettingsView))
          .appLocalizations;
      expect(find.text(l10n.campusNetworkLineNumber(1)), findsWidgets);
      expect(find.text(l10n.campusNetworkLineNumber(2)), findsOneWidget);
      expect(find.text(l10n.campusNetworkLineNumber(3)), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'five remote campus lines render and the fifth can become active',
    (tester) async {
      var loads = 0;
      var restarts = 0;
      final container = await _pumpCampusSettings(
        tester,
        loadConfig: () async {
          loads++;
          return _campusConfig(5);
        },
        restartCore: () async => restarts++,
      );
      final campusSwitch = find.byKey(
        const ValueKey('advanced-campus-network-switch'),
      );
      await tester.ensureVisible(campusSwitch);
      await tester.pumpAndSettle();
      await tester.tap(campusSwitch);
      await tester.pumpAndSettle();
      expect(loads, 2);
      expect(restarts, 1);
      expect(container.read(appSettingProvider).campusNetworkEnabled, isTrue);

      final lineTile = find.byKey(
        const ValueKey('advanced-campus-network-line-tile'),
      );
      await tester.ensureVisible(lineTile);
      await tester.pumpAndSettle();
      await tester.tap(lineTile);
      await tester.pumpAndSettle();
      final l10n = tester
          .element(find.byType(FengWoAdvancedSettingsView))
          .appLocalizations;
      expect(find.text(l10n.campusNetworkLineNumber(4)), findsOneWidget);
      expect(find.text(l10n.campusNetworkLineNumber(5)), findsOneWidget);
      await tester.tap(find.text(l10n.campusNetworkLineNumber(5)));
      await tester.pumpAndSettle();

      expect(container.read(appSettingProvider).campusOperator, 'line_5');
      expect(
        container.read(appSettingProvider).campusHostsByOperator,
        hasLength(5),
      );
      expect(restarts, 2);
      expect(tester.takeException(), isNull);
    },
  );

  for (final counts in [(5, 2), (2, 1)]) {
    final (before, after) = counts;
    testWidgets(
      'shrinking $before campus lines to $after replaces a removed selection',
      (tester) async {
        var restarts = 0;
        final container = await _pumpCampusSettings(
          tester,
          initial: AppSettingProps(
            campusNetworkEnabled: true,
            campusOperator: 'line_$before',
            campusHostsByOperator: _campusConfig(before).hostsByOperator,
          ),
          loadConfig: () async => _campusConfig(after),
          restartCore: () async => restarts++,
        );
        final settings = container.read(appSettingProvider);
        expect(settings.campusOperator, 'line_1');
        expect(settings.campusHostsByOperator, hasLength(after));
        expect(settings.campusNetworkEnabled, isTrue);
        expect(restarts, 1);

        final lineTile = find.byKey(
          const ValueKey('advanced-campus-network-line-tile'),
        );
        await tester.ensureVisible(lineTile);
        await tester.pumpAndSettle();
        await tester.tap(lineTile);
        await tester.pumpAndSettle();
        final l10n = tester
            .element(find.byType(FengWoAdvancedSettingsView))
            .appLocalizations;
        expect(find.text(l10n.campusNetworkLineNumber(1)), findsWidgets);
        for (var number = 2; number <= after; number++) {
          expect(
            find.text(l10n.campusNetworkLineNumber(number)),
            findsOneWidget,
          );
        }
        for (var number = after + 1; number <= before; number++) {
          expect(find.text(l10n.campusNetworkLineNumber(number)), findsNothing);
        }
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final refreshOnEntry in [true, false]) {
    testWidgets(
      'campus refresh preserves settings changed while ${refreshOnEntry ? 'entering' : 'enabling'}',
      (tester) async {
        final response = Completer<CampusNetworkConfig>();
        addTearDown(() {
          if (!response.isCompleted) response.complete(_campusConfig(0));
        });
        var loads = 0;
        final container = await _pumpCampusSettings(
          tester,
          loadConfig: () {
            loads++;
            if (refreshOnEntry || loads > 1) return response.future;
            return Future.value(_campusConfig(2));
          },
        );
        if (!refreshOnEntry) {
          final campusSwitch = find.byKey(
            const ValueKey('advanced-campus-network-switch'),
          );
          await tester.ensureVisible(campusSwitch);
          await tester.pumpAndSettle();
          await tester.tap(campusSwitch);
          await tester.pump();
        }

        container
            .read(appSettingProvider.notifier)
            .update((settings) => settings.copyWith(closeConnections: true));
        await tester.pump();
        expect(container.read(appSettingProvider).closeConnections, isTrue);
        response.complete(_campusConfig(2));
        await tester.pumpAndSettle();

        final settings = container.read(appSettingProvider);
        expect(settings.closeConnections, isTrue);
        expect(settings.campusHostsByOperator, hasLength(2));
        expect(settings.campusNetworkEnabled, !refreshOnEntry);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'an empty remote campus configuration clears cache and disables mode',
    (tester) async {
      var restarts = 0;
      final container = await _pumpCampusSettings(
        tester,
        initial: AppSettingProps(
          campusNetworkEnabled: true,
          campusOperator: 'line_5',
          campusHostsByOperator: _campusConfig(5).hostsByOperator,
        ),
        loadConfig: () async => _campusConfig(0),
        restartCore: () async => restarts++,
      );
      final settings = container.read(appSettingProvider);
      expect(settings.campusHostsByOperator, isEmpty);
      expect(settings.campusOperator, isEmpty);
      expect(settings.campusNetworkEnabled, isFalse);
      expect(restarts, 1);

      final lineTile = find.byKey(
        const ValueKey('advanced-campus-network-line-tile'),
      );
      await tester.ensureVisible(lineTile);
      await tester.pumpAndSettle();
      final l10n = tester
          .element(find.byType(FengWoAdvancedSettingsView))
          .appLocalizations;
      expect(
        find.descendant(of: lineTile, matching: find.text(l10n.none)),
        findsOneWidget,
      );
      await tester.tap(lineTile);
      await tester.pumpAndSettle();
      expect(find.byType(Dialog), findsNothing);
      expect(find.text(l10n.campusNetworkLineNumber(1)), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'enabling with an empty refreshed campus config does not restore old lines',
    (tester) async {
      var loads = 0;
      var restarts = 0;
      final container = await _pumpCampusSettings(
        tester,
        loadConfig: () async => _campusConfig(++loads == 1 ? 5 : 0),
        restartCore: () async => restarts++,
      );
      expect(
        container.read(appSettingProvider).campusHostsByOperator,
        hasLength(5),
      );
      final campusSwitch = find.byKey(
        const ValueKey('advanced-campus-network-switch'),
      );
      await tester.ensureVisible(campusSwitch);
      await tester.pumpAndSettle();
      await tester.tap(campusSwitch);
      await tester.pumpAndSettle();

      final settings = container.read(appSettingProvider);
      expect(loads, 2);
      expect(restarts, 0);
      expect(settings.campusHostsByOperator, isEmpty);
      expect(settings.campusOperator, isEmpty);
      expect(settings.campusNetworkEnabled, isFalse);
      expect(tester.widget<Switch>(campusSwitch).value, isFalse);
      expect(tester.takeException(), isNull);
    },
  );

  for (final platform in [
    TargetPlatform.android,
    TargetPlatform.macOS,
    TargetPlatform.windows,
  ]) {
    testWidgets(
      'campus config refreshes once per active entry on $platform',
      (tester) async {
        final active = ValueNotifier(false);
        addTearDown(active.dispose);
        var loads = 0;
        var restarts = 0;
        final container = await _pumpCampusSettings(
          tester,
          pageActive: active,
          initial: AppSettingProps(
            campusNetworkEnabled: true,
            campusOperator: 'line_2',
            campusHostsByOperator: _campusConfig(2).hostsByOperator,
          ),
          loadConfig: () async => _campusConfig(++loads == 1 ? 2 : 5),
          restartCore: () async => restarts++,
        );
        expect(loads, 0);
        active.value = true;
        await tester.pumpAndSettle();
        expect(loads, 1);
        expect(restarts, 0);
        container
            .read(appSettingProvider.notifier)
            .update((settings) => settings.copyWith(closeConnections: true));
        await tester.pumpAndSettle();
        expect(loads, 1);
        active.value = false;
        await tester.pumpAndSettle();
        expect(loads, 1);
        active.value = true;
        await tester.pumpAndSettle();
        expect(loads, 2);
        final settings = container.read(appSettingProvider);
        expect(settings.campusHostsByOperator, hasLength(5));
        expect(settings.campusOperator, 'line_2');
        expect(settings.campusNetworkEnabled, isTrue);
        expect(settings.closeConnections, isTrue);
        expect(restarts, 1);
        expect(tester.takeException(), isNull);
      },
      variant: TargetPlatformVariant({platform}),
    );
  }

  testWidgets('rapid campus re-entry discards the old response and refreshes', (
    tester,
  ) async {
    final active = ValueNotifier(true);
    addTearDown(active.dispose);
    final responses = <Completer<CampusNetworkConfig>>[];
    var restarts = 0;
    final container = await _pumpCampusSettings(
      tester,
      pageActive: active,
      initial: AppSettingProps(
        campusNetworkEnabled: true,
        campusOperator: 'line_3',
        campusHostsByOperator: _campusConfig(3).hostsByOperator,
      ),
      loadConfig: () {
        final response = Completer<CampusNetworkConfig>();
        responses.add(response);
        return response.future;
      },
      restartCore: () async => restarts++,
    );
    expect(responses, hasLength(1));
    active.value = false;
    await tester.pump();
    active.value = true;
    await tester.pump();
    responses.first.complete(_campusConfig(1));
    await tester.pumpAndSettle();
    expect(responses, hasLength(2));
    expect(
      container.read(appSettingProvider).campusHostsByOperator,
      hasLength(3),
    );
    expect(container.read(appSettingProvider).campusOperator, 'line_3');
    expect(restarts, 0);
    responses.last.complete(_campusConfig(2));
    await tester.pumpAndSettle();
    expect(
      container.read(appSettingProvider).campusHostsByOperator,
      hasLength(2),
    );
    expect(container.read(appSettingProvider).campusOperator, 'line_1');
    expect(restarts, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'failed campus re-entry keeps settings and permits the next refresh',
    (tester) async {
      final active = ValueNotifier(true);
      addTearDown(active.dispose);
      var loads = 0;
      var restarts = 0;
      final container = await _pumpCampusSettings(
        tester,
        pageActive: active,
        initial: AppSettingProps(
          campusNetworkEnabled: true,
          campusOperator: 'line_2',
          campusHostsByOperator: _campusConfig(2).hostsByOperator,
        ),
        loadConfig: () async {
          loads++;
          if (loads == 2) throw const FormatException('Invalid remote config');
          return _campusConfig(loads == 1 ? 2 : 5);
        },
        restartCore: () async => restarts++,
      );
      final before = container.read(appSettingProvider);
      active.value = false;
      await tester.pump();
      active.value = true;
      await tester.pumpAndSettle();
      expect(loads, 2);
      expect(container.read(appSettingProvider), before);
      expect(restarts, 0);
      expect(
        tester
            .widget<Switch>(
              find.byKey(const ValueKey('advanced-campus-network-switch')),
            )
            .onChanged,
        isNotNull,
      );
      active.value = false;
      await tester.pump();
      active.value = true;
      await tester.pumpAndSettle();
      expect(loads, 3);
      expect(
        container.read(appSettingProvider).campusHostsByOperator,
        hasLength(5),
      );
      expect(restarts, 1);
      expect(tester.takeException(), isNull);
    },
  );

  for (final dispose in [false, true]) {
    testWidgets(
      'campus response cannot apply after ${dispose ? 'disposal' : 'leaving the page'}',
      (tester) async {
        final active = ValueNotifier(true);
        addTearDown(active.dispose);
        final response = Completer<CampusNetworkConfig>();
        var restarts = 0;
        final container = await _pumpCampusSettings(
          tester,
          pageActive: active,
          initial: AppSettingProps(
            campusNetworkEnabled: true,
            campusOperator: 'line_2',
            campusHostsByOperator: _campusConfig(2).hostsByOperator,
          ),
          loadConfig: () => response.future,
          restartCore: () async => restarts++,
        );
        final before = container.read(appSettingProvider);
        if (dispose) {
          await tester.pumpWidget(const SizedBox.shrink());
        } else {
          active.value = false;
          await tester.pump();
        }
        response.complete(_campusConfig(5));
        await tester.pumpAndSettle();
        expect(container.read(appSettingProvider), before);
        expect(restarts, 0);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'campus re-entry refreshes after an in-progress enable operation',
    (tester) async {
      final active = ValueNotifier(true);
      addTearDown(active.dispose);
      final enabling = Completer<CampusNetworkConfig>();
      var loads = 0;
      var restarts = 0;
      final container = await _pumpCampusSettings(
        tester,
        pageActive: active,
        loadConfig: () {
          loads++;
          if (loads == 2) return enabling.future;
          return Future.value(_campusConfig(loads == 1 ? 2 : 5));
        },
        restartCore: () async => restarts++,
      );
      final campusSwitch = find.byKey(
        const ValueKey('advanced-campus-network-switch'),
      );
      await tester.ensureVisible(campusSwitch);
      await tester.pumpAndSettle();
      await tester.tap(campusSwitch);
      await tester.pump();
      expect(loads, 2);
      active.value = false;
      await tester.pump();
      active.value = true;
      await tester.pump();
      enabling.complete(_campusConfig(2));
      await tester.pumpAndSettle();
      expect(loads, 3);
      expect(container.read(appSettingProvider).campusNetworkEnabled, isTrue);
      expect(
        container.read(appSettingProvider).campusHostsByOperator,
        hasLength(5),
      );
      expect(restarts, 2);
      expect(tester.widget<Switch>(campusSwitch).onChanged, isNotNull);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('advanced settings use one scroll view on a narrow dark screen', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [currentProfileProvider.overrideWithValue(null)],
        child: const _TestApp(
          themeMode: ThemeMode.dark,
          child: FengWoAdvancedSettingsView(
            campusNetworkConfigLoader: _loadTwoCampusLines,
          ),
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
    expect(find.byKey(const ValueKey('advanced-diagnostic-card')), findsOne);
    final diagnostics = tester.getTopLeft(
      find.byKey(const ValueKey('advanced-diagnostic-card')),
    );
    final geodata = tester.getTopLeft(
      find.byKey(const ValueKey('advanced-geodata-card')),
    );
    expect(diagnostics.dy, lessThan(geodata.dy));
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
      ProviderScope(
        overrides: [currentProfileProvider.overrideWithValue(null)],
        child: const _TestApp(
          child: FengWoAdvancedSettingsView(
            campusNetworkConfigLoader: _loadTwoCampusLines,
          ),
        ),
      ),
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
    final diagnostics = tester.getTopLeft(
      find.byKey(const ValueKey('advanced-diagnostic-card')),
    );

    expect(ipv6.dx, greaterThan(proxy.dx));
    expect((ipv6.dy - proxy.dy).abs(), lessThan(1));
    expect(dns.dx, greaterThan(campus.dx));
    expect((dns.dy - campus.dy).abs(), lessThan(1));
    expect(campus.dy, greaterThan(proxy.dy));
    expect(diagnostics.dy, greaterThan(campus.dy));
    expect(geodata.dy, greaterThan(diagnostics.dy));
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

CampusNetworkConfig _campusConfig(int count) {
  return CampusNetworkConfig.fromRemote({
    'campusHostsByOperator': {
      for (var index = 0; index < count; index++)
        'line_${index + 1}': ['192.0.2.${index + 1} campus.example'],
    },
  });
}

Future<ProviderContainer> _pumpCampusSettings(
  WidgetTester tester, {
  required CampusNetworkConfigLoader loadConfig,
  AppSettingProps initial = const AppSettingProps(),
  CampusNetworkCoreRestarter? restartCore,
  ValueNotifier<bool>? pageActive,
  Size size = const Size(1280, 1000),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final container = ProviderContainer(
    overrides: [
      currentProfileProvider.overrideWithValue(null),
      appUpdateCurrentVersionProvider.overrideWithValue(null),
    ],
  );
  globalState.container = container;
  container.read(viewSizeProvider.notifier).value = size;
  container.read(appSettingProvider.notifier).value = initial;
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    container.dispose();
  });
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: _TestApp(
        child: ValueListenableBuilder<bool>(
          valueListenable: pageActive ?? const AlwaysStoppedAnimation(true),
          builder: (_, active, child) =>
              PageActivityScope(isActive: active, child: child!),
          child: FengWoAdvancedSettingsView(
            campusNetworkConfigLoader: loadConfig,
            campusNetworkCoreRestarter: restartCore ?? () async {},
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

Future<CampusNetworkConfig> _loadTwoCampusLines() async {
  return const CampusNetworkConfig({
    'telecom': {'base.fengwo1688.cc': '114.80.8.196'},
    'unicom': {'base.fengwo1688.cc': '112.65.199.196'},
  });
}

class _RoutingSystemAction extends SystemAction {
  @override
  Future<List<Package>> getPackages() async => [];
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

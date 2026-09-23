import 'package:fl_clash/common/campus_network.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/l10n/l10n.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/state.dart';
import 'package:fl_clash/views/settings/fengwo_advanced_settings.dart';
import 'package:fl_clash/views/settings/fengwo_dns_advanced.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

Finder _key(String value) => find.byKey(ValueKey(value));

void main() {
  for (final platform in [TargetPlatform.android, TargetPlatform.macOS]) {
    testWidgets('advanced DNS entry opens the editor on $platform', (
      tester,
    ) async {
      await _pump(tester, platform: platform, entry: true);
      final tile = _key('advanced-dns-options-tile');
      await tester.ensureVisible(tile);
      await tester.pumpAndSettle();
      await tester.tap(tile);
      await tester.pumpAndSettle();
      expect(find.byType(FengWoDnsAdvancedView), findsOneWidget);
      expect(_key('dns-advanced-filter-edit'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('filter edits save only on confirmation and preserve DNS mode', (
    tester,
  ) async {
    final container = await _pump(
      tester,
      patch: const PatchClashConfig(dns: Dns(enhancedMode: DnsMode.redirHost)),
    );
    final original = container.read(patchClashConfigProvider).dns.fakeIpFilter;
    await _tap(tester, 'dns-advanced-filter-edit');
    await tester.enterText(
      _key('dns-fake-ip-filter-input'),
      '  *.lan  \n\n+.example.org\n+.example.org\ngeosite:private\n',
    );
    expect(container.read(patchClashConfigProvider).dns.fakeIpFilter, original);
    await _tap(tester, 'dns-fake-ip-filter-save');
    expect(container.read(patchClashConfigProvider).dns.fakeIpFilter, [
      '*.lan',
      '+.example.org',
      'geosite:private',
    ]);
    expect(container.read(overrideDnsProvider), isFalse);
    expect(
      container.read(patchClashConfigProvider).dns.enhancedMode,
      DnsMode.redirHost,
    );
    expect(tester.takeException(), isNull);

    await _tap(tester, 'dns-advanced-filter-edit');
    await tester.enterText(
      _key('dns-fake-ip-filter-input'),
      'cancelled.example',
    );
    await _tap(tester, 'dns-fake-ip-filter-cancel');
    expect(
      container.read(patchClashConfigProvider).dns.fakeIpFilter,
      isNot(contains('cancelled.example')),
    );
  });

  testWidgets('empty filter list can be saved without changing range', (
    tester,
  ) async {
    final container = await _pump(tester);
    await _tap(tester, 'dns-advanced-filter-edit');
    await tester.enterText(_key('dns-fake-ip-filter-input'), ' \n\n ');
    await _tap(tester, 'dns-fake-ip-filter-save');
    expect(container.read(patchClashConfigProvider).dns.fakeIpFilter, isEmpty);
    expect(
      container.read(patchClashConfigProvider).dns.fakeIpRange,
      '198.18.0.1/16',
    );
  });

  testWidgets('invalid filter stays in editor without changing configuration', (
    tester,
  ) async {
    final container = await _pump(tester);
    final original = container.read(patchClashConfigProvider).dns.fakeIpFilter;
    await _tap(tester, 'dns-advanced-filter-edit');
    await tester.enterText(
      _key('dns-fake-ip-filter-input'),
      'bad..example.org',
    );
    await _tap(tester, 'dns-fake-ip-filter-save');
    expect(_key('dns-fake-ip-filter-input'), findsOneWidget);
    expect(container.read(patchClashConfigProvider).dns.fakeIpFilter, original);
    await _tap(tester, 'dns-fake-ip-filter-cancel');
  });

  testWidgets('user can explicitly enable local DNS and choose Fake-IP', (
    tester,
  ) async {
    final container = await _pump(
      tester,
      patch: const PatchClashConfig(dns: Dns(enhancedMode: DnsMode.redirHost)),
    );
    expect(container.read(overrideDnsProvider), isFalse);
    await _tap(tester, 'dns-advanced-override-switch');
    expect(container.read(overrideDnsProvider), isTrue);
    await _tap(tester, 'dns-advanced-mode-dropdown');
    await tester.tap(find.text('fake-ip').last);
    await tester.pumpAndSettle();
    expect(
      container.read(patchClashConfigProvider).dns.enhancedMode,
      DnsMode.fakeIp,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('campus DNS override is reflected without changing user switch', (
    tester,
  ) async {
    final container = await _pump(
      tester,
      settings: const AppSettingProps(
        campusNetworkEnabled: true,
        campusOperator: 'campus',
        campusHostsByOperator: {
          'campus': {'gateway.example': '192.0.2.1'},
        },
      ),
    );
    expect(container.read(overrideDnsProvider), isFalse);
    final toggle = tester.widget<SwitchListTile>(
      _key('dns-advanced-override-switch'),
    );
    expect(toggle.onChanged, isNull);
    expect(_key('dns-advanced-status'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('disabled DNS can be enabled explicitly', (tester) async {
    final container = await _pump(
      tester,
      overrideDns: true,
      patch: const PatchClashConfig(dns: Dns(enable: false)),
    );
    expect(container.read(patchClashConfigProvider).dns.enable, isFalse);
    await _tap(tester, 'dns-advanced-enable-dns');
    expect(container.read(patchClashConfigProvider).dns.enable, isTrue);
  });

  testWidgets('desktop range is collapsed and rejects unusably small subnets', (
    tester,
  ) async {
    final container = await _pump(tester, platform: TargetPlatform.windows);
    expect(_key('dns-advanced-range-edit').hitTestable(), findsNothing);
    await _tap(tester, 'dns-advanced-range-expansion');
    await _tap(tester, 'dns-advanced-range-edit');
    await tester.enterText(_key('dns-fake-ip-range-input'), '198.18.0.1/32');
    await _tap(tester, 'dns-fake-ip-range-save');
    expect(_key('dns-fake-ip-range-input'), findsOneWidget);
    expect(
      container.read(patchClashConfigProvider).dns.fakeIpRange,
      '198.18.0.1/16',
    );
    await tester.enterText(_key('dns-fake-ip-range-input'), '198.19.0.1/16');
    await _tap(tester, 'dns-fake-ip-range-save');
    expect(
      container.read(patchClashConfigProvider).dns.fakeIpRange,
      '198.19.0.1/16',
    );
    await _tap(tester, 'dns-advanced-range-edit');
    await _tap(tester, 'dns-fake-ip-range-reset');
    expect(
      container.read(patchClashConfigProvider).dns.fakeIpRange,
      '198.19.0.1/16',
    );
    await _tap(tester, 'dns-fake-ip-range-save');
    expect(
      container.read(patchClashConfigProvider).dns.fakeIpRange,
      '198.18.0.1/16',
    );
    expect(tester.takeException(), isNull);
  });

  for (final locale in ['zh', 'en', 'ja', 'ru']) {
    testWidgets('mobile $locale layout hides range controls at large text', (
      tester,
    ) async {
      await _pump(tester, locale: locale, textScale: 1.6);
      expect(_key('dns-advanced-range-expansion'), findsNothing);
      await _tap(tester, 'dns-advanced-filter-edit');
      expect(_key('dns-fake-ip-filter-input'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await _tap(tester, 'dns-fake-ip-filter-cancel');
    });
  }
}

Future<void> _tap(WidgetTester tester, String key) async {
  final target = _key(key);
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
  await tester.tap(target);
  await tester.pumpAndSettle();
}

Future<ProviderContainer> _pump(
  WidgetTester tester, {
  TargetPlatform platform = TargetPlatform.android,
  PatchClashConfig patch = const PatchClashConfig(),
  AppSettingProps settings = const AppSettingProps(),
  bool overrideDns = false,
  bool entry = false,
  String locale = 'zh',
  double textScale = 1,
}) async {
  final size = platform == TargetPlatform.android
      ? const Size(390, 844)
      : const Size(1200, 900);
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final container = ProviderContainer(
    overrides: [currentProfileProvider.overrideWithValue(null)],
  );
  globalState.container = container;
  container.read(viewSizeProvider.notifier).value = size;
  container.read(patchClashConfigProvider.notifier).value = patch;
  container.read(appSettingProvider.notifier).value = settings;
  container.read(overrideDnsProvider.notifier).value = overrideDns;
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    container.dispose();
  });
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        locale: locale == 'zh' ? const Locale('zh', 'CN') : Locale(locale),
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.delegate.supportedLocales,
        theme: ThemeData(platform: platform),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: entry
            ? FengWoAdvancedSettingsView(
                campusNetworkConfigLoader: () async =>
                    const CampusNetworkConfig({}),
              )
            : const FengWoDnsAdvancedView(),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

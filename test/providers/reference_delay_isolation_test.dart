import 'dart:convert';

import 'package:fl_clash/common/compute.dart';
import 'package:fl_clash/common/reference_delay.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/app.dart';
import 'package:fl_clash/providers/state.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:riverpod/riverpod.dart';

void main() {
  const testUrl = 'https://latency.example.test/';
  late ProviderContainer container;

  setUp(() {
    container = ProviderContainer(
      overrides: [selectedMapProvider.overrideWithValue({})],
    );
  });

  tearDown(() {
    container.dispose();
  });

  test('repeated presentation reads keep measured provider values intact', () {
    const standard = Delay(name: 'Leaf', url: testUrl, value: 350);
    const connection = Delay(name: 'Leaf', url: testUrl, value: 500);
    container.read(delayDataSourceProvider.notifier).setDelay(standard);
    container
        .read(connectionDelayDataSourceProvider.notifier)
        .setDelay(connection);

    for (var rebuild = 0; rebuild < 3; rebuild++) {
      final rawStandard = container.read(
        standardDelayProvider(proxyName: 'Leaf', testUrl: testUrl),
      );
      final rawConnection = container.read(
        connectionDelayProvider(proxyName: 'Leaf', testUrl: testUrl),
      );
      final rawEffective = container.read(
        delayProvider(proxyName: 'Leaf', testUrl: testUrl),
      );
      expect(rawStandard, 350);
      expect(rawConnection, 500);
      expect(rawEffective, 500);
      expect(referenceDelayMilliseconds(rawStandard), 350);
      expect(referenceDelayMilliseconds(rawConnection), 500);
      expect(referenceDelayMilliseconds(rawEffective), 500);
    }

    expect(container.read(delayDataSourceProvider)[testUrl], {'Leaf': 350});
    expect(container.read(connectionDelayDataSourceProvider)[testUrl], {
      'Leaf': 500,
    });
    expect(Delay.fromJson(jsonDecode(jsonEncode(standard))), standard);
    expect(Delay.fromJson(jsonDecode(jsonEncode(connection))), connection);
  });

  test('effective fallback and pending or failed measurements remain raw', () {
    container
        .read(delayDataSourceProvider.notifier)
        .setDelay(const Delay(name: 'Leaf', url: testUrl, value: 280));
    final effectiveProvider = delayProvider(
      proxyName: 'Leaf',
      testUrl: testUrl,
    );

    expect(container.read(effectiveProvider), 280);
    expect(referenceDelayMilliseconds(container.read(effectiveProvider)), 280);

    for (final value in [
      (0, 0),
      (-1, -1),
      (150, 150),
      (250, 250),
      (251, 251),
      (351, 351),
      (450, 450),
      (500, 500),
    ]) {
      container
          .read(connectionDelayDataSourceProvider.notifier)
          .setDelay(Delay(name: 'Leaf', url: testUrl, value: value.$1));
      expect(container.read(effectiveProvider), value.$1);
      expect(
        referenceDelayMilliseconds(container.read(effectiveProvider)),
        value.$2,
      );
      expect(
        container.read(
          standardDelayProvider(proxyName: 'Leaf', testUrl: testUrl),
        ),
        280,
      );
    }

    container
        .read(connectionDelayDataSourceProvider.notifier)
        .setDelay(const Delay(name: 'Leaf', url: testUrl));
    expect(container.read(effectiveProvider), 280);
    expect(referenceDelayMilliseconds(container.read(effectiveProvider)), 280);
  });

  test('raw presentation values preserve measured sorting order', () {
    const group = Group(
      name: 'Selector',
      type: GroupType.Selector,
      all: [
        Proxy(name: 'Slow', type: 'ss'),
        Proxy(name: 'Medium', type: 'ss'),
        Proxy(name: 'Fast', type: 'ss'),
      ],
    );
    const measurements = {'Slow': 150, 'Medium': 125, 'Fast': 101};
    for (final entry in measurements.entries) {
      container
          .read(delayDataSourceProvider.notifier)
          .setDelay(Delay(name: entry.key, url: testUrl, value: entry.value));
      expect(referenceDelayMilliseconds(entry.value), entry.value);
    }

    final delayMap = container.read(delayDataSourceProvider);
    final sorted = computeSort(
      groups: [group],
      sortType: ProxiesSortType.delay,
      delayMap: delayMap,
      selectedMap: {},
      defaultTestUrl: testUrl,
    );

    expect(sorted.single.all.map((proxy) => proxy.name), [
      'Fast',
      'Medium',
      'Slow',
    ]);
    expect(group.all.map((proxy) => proxy.name), ['Slow', 'Medium', 'Fast']);
    expect(delayMap[testUrl], measurements);
    expect(jsonDecode(jsonEncode(delayMap))[testUrl], measurements);
  });

  test('automatic group keeps the core selection and its measured latency', () {
    const group = Group(
      name: 'Automatic',
      type: GroupType.URLTest,
      now: 'CoreSelected',
      testUrl: testUrl,
      all: [
        Proxy(name: 'CoreSelected', type: 'ss'),
        Proxy(name: 'Other', type: 'ss'),
      ],
    );
    container.read(groupsProvider.notifier).update((_) => [group]);
    for (final entry in {'CoreSelected': 350, 'Other': 101}.entries) {
      container
          .read(delayDataSourceProvider.notifier)
          .setDelay(Delay(name: entry.key, url: testUrl, value: entry.value));
    }

    for (var rebuild = 0; rebuild < 3; rebuild++) {
      final measured = container.read(
        delayProvider(proxyName: 'Automatic', testUrl: testUrl),
      );
      expect(measured, 350);
      expect(referenceDelayMilliseconds(measured), 350);
      expect(
        container.read(realSelectedProxyStateProvider('Automatic')).proxyName,
        'CoreSelected',
      );
    }

    expect(container.read(groupsProvider).single.now, 'CoreSelected');
    expect(container.read(delayDataSourceProvider)[testUrl], {
      'CoreSelected': 350,
      'Other': 101,
    });
  });
}

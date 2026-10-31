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

  test('completed references are stored once and remain stable on reads', () {
    const standard = Delay(
      name: 'Leaf',
      url: testUrl,
      value: 137,
      successful: true,
    );
    const connection = Delay(
      name: 'Leaf',
      url: testUrl,
      value: 142,
      successful: false,
    );
    container.read(delayDataSourceProvider.notifier).setDelay(standard);
    container
        .read(connectionDelayDataSourceProvider.notifier)
        .setDelay(connection);

    for (var rebuild = 0; rebuild < 5; rebuild++) {
      expect(
        container.read(
          standardDelayProvider(proxyName: 'Leaf', testUrl: testUrl),
        ),
        137,
      );
      expect(
        container.read(
          connectionDelayProvider(proxyName: 'Leaf', testUrl: testUrl),
        ),
        142,
      );
      expect(
        container.read(delayProvider(proxyName: 'Leaf', testUrl: testUrl)),
        142,
      );
      expect(referenceDelayMilliseconds(142), 142);
    }
    expect(container.read(delayDataSourceProvider)[testUrl], {'Leaf': 137});
    expect(container.read(connectionDelayDataSourceProvider)[testUrl], {
      'Leaf': 142,
    });
    expect(Delay.fromJson(jsonDecode(jsonEncode(standard))), standard);
    expect(Delay.fromJson(jsonDecode(jsonEncode(connection))), connection);
  });

  test('failed completions replace failures with a stable reference value', () {
    for (final failure in [
      const Delay(name: 'Leaf', url: testUrl, value: -1),
      const Delay(name: 'Leaf', url: testUrl, value: -100),
      const Delay(name: 'Leaf', url: testUrl, successful: false),
      const Delay(name: 'Leaf', url: testUrl, value: 0, successful: false),
    ]) {
      container.read(delayDataSourceProvider.notifier).setDelay(failure);
      container
          .read(connectionDelayDataSourceProvider.notifier)
          .setDelay(failure);
      final standard = container.read(
        standardDelayProvider(proxyName: 'Leaf', testUrl: testUrl),
      );
      final connection = container.read(
        connectionDelayProvider(proxyName: 'Leaf', testUrl: testUrl),
      );
      expect(standard, inInclusiveRange(120, 150));
      expect(connection, inInclusiveRange(120, 150));
      for (var rebuild = 0; rebuild < 5; rebuild++) {
        expect(
          container.read(
            standardDelayProvider(proxyName: 'Leaf', testUrl: testUrl),
          ),
          standard,
        );
        expect(
          container.read(
            connectionDelayProvider(proxyName: 'Leaf', testUrl: testUrl),
          ),
          connection,
        );
      }
      expect(container.read(delayDataSourceProvider)[testUrl], {
        'Leaf': standard,
      });
      expect(container.read(connectionDelayDataSourceProvider)[testUrl], {
        'Leaf': connection,
      });
    }
  });

  test('each completed node is visible while another node remains pending', () {
    final notifier = container.read(delayDataSourceProvider.notifier);
    notifier.setDelay(const Delay(name: 'First', url: testUrl, value: 0));
    notifier.setDelay(const Delay(name: 'Second', url: testUrl, value: 0));
    final pendingSnapshot = container.read(delayDataSourceProvider);
    notifier.setDelay(const Delay(name: 'First', url: testUrl, value: 128));
    final firstSnapshot = container.read(delayDataSourceProvider);
    expect(firstSnapshot[testUrl], {'First': 128, 'Second': 0});
    expect(pendingSnapshot[testUrl], {'First': 0, 'Second': 0});
    notifier.setDelay(const Delay(name: 'Second', url: testUrl, value: -1));
    expect(
      container.read(delayDataSourceProvider)[testUrl]!['Second'],
      inInclusiveRange(120, 150),
    );
    expect(firstSnapshot[testUrl], {'First': 128, 'Second': 0});
  });

  test('pending and missing values do not receive a completed reference', () {
    for (final value in <int?>[null, 0]) {
      final delay = Delay(name: 'Leaf', url: testUrl, value: value);
      container.read(delayDataSourceProvider.notifier).setDelay(delay);
      container
          .read(connectionDelayDataSourceProvider.notifier)
          .setDelay(delay);
      expect(
        container.read(
          standardDelayProvider(proxyName: 'Leaf', testUrl: testUrl),
        ),
        value,
      );
      expect(
        container.read(
          connectionDelayProvider(proxyName: 'Leaf', testUrl: testUrl),
        ),
        value,
      );
    }
  });

  test(
    'sorting uses stored references and leaves the source group unchanged',
    () {
      const group = Group(
        name: 'Selector',
        type: GroupType.Selector,
        all: [
          Proxy(name: 'Slow', type: 'ss'),
          Proxy(name: 'Medium', type: 'ss'),
          Proxy(name: 'Fast', type: 'ss'),
        ],
      );
      const references = {'Slow': 150, 'Medium': 125, 'Fast': 101};
      for (final entry in references.entries) {
        container
            .read(delayDataSourceProvider.notifier)
            .setDelay(Delay(name: entry.key, url: testUrl, value: entry.value));
      }
      final stored = container.read(delayDataSourceProvider);
      final sorted = computeSort(
        groups: [group],
        sortType: ProxiesSortType.delay,
        delayMap: stored,
        selectedMap: {},
        defaultTestUrl: testUrl,
      );
      expect(sorted.single.all.map((proxy) => proxy.name), [
        'Fast',
        'Medium',
        'Slow',
      ]);
      expect(group.all.map((proxy) => proxy.name), ['Slow', 'Medium', 'Fast']);
      expect(jsonDecode(jsonEncode(stored))[testUrl], references);
    },
  );

  test('display reads do not alter automatic core selection', () {
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
    for (final entry in {'CoreSelected': 137, 'Other': 101}.entries) {
      container
          .read(delayDataSourceProvider.notifier)
          .setDelay(Delay(name: entry.key, url: testUrl, value: entry.value));
    }
    for (var rebuild = 0; rebuild < 3; rebuild++) {
      expect(
        container.read(delayProvider(proxyName: 'Automatic', testUrl: testUrl)),
        137,
      );
      expect(
        container.read(realSelectedProxyStateProvider('Automatic')).proxyName,
        'CoreSelected',
      );
    }
    expect(container.read(groupsProvider).single.now, 'CoreSelected');
  });
}

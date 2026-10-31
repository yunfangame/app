import 'dart:async';

import 'package:fl_clash/common/fixed.dart';
import 'package:fl_clash/core/controller.dart';
import 'package:fl_clash/core/interface.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:riverpod/riverpod.dart';

class _MockCore extends Mock implements CoreHandlerInterface {}

class _CommonAction extends CommonAction {
  _CommonAction(this.controller);

  final CoreController controller;

  @override
  CoreController get trafficController => controller;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _MockCore core;
  late ProviderContainer container;
  late CommonAction action;

  setUp(() {
    core = _MockCore();
    container = ProviderContainer(
      overrides: [
        commonActionProvider.overrideWith(
          () => _CommonAction(CoreController.test(core)),
        ),
        trafficsProvider.overrideWithBuild((_, _) => FixedList<Traffic>(30)),
      ],
    );
    action = container.read(commonActionProvider.notifier);
  });

  tearDown(() {
    container.dispose();
    CoreController.resetInstance();
  });

  test('publishes both traffic values only for the active sample', () async {
    const traffic = Traffic(up: 1, down: 2);
    const total = Traffic(up: 10, down: 20);
    when(() => core.getTraffic(any())).thenAnswer((_) async => traffic);
    when(() => core.getTotalTraffic(any())).thenAnswer((_) async => total);

    await action.updateTraffic(isCurrent: () => true);

    expect(container.read(trafficsProvider).list, [traffic]);
    expect(container.read(totalTrafficProvider), total);
  });

  test(
    'a stopped or background sample cannot start or continue reads',
    () async {
      final pending = Completer<Traffic>();
      var current = false;
      when(() => core.getTraffic(any())).thenAnswer((_) => pending.future);
      await action.updateTraffic(isCurrent: () => current);
      verifyNever(() => core.getTraffic(any()));

      current = true;
      final reading = action.updateTraffic(isCurrent: () => current);
      current = false;
      pending.complete(const Traffic(up: 1, down: 2));
      await reading;

      verifyNever(() => core.getTotalTraffic(any()));
      expect(container.read(trafficsProvider).list, isEmpty);
      expect(container.read(totalTrafficProvider), const Traffic());
    },
  );

  test('in-flight totals cannot overwrite state after stop or reset', () async {
    final pending = Completer<Traffic>();
    var current = true;
    when(
      () => core.getTraffic(any()),
    ).thenAnswer((_) async => const Traffic(up: 1));
    when(() => core.getTotalTraffic(any())).thenAnswer((_) => pending.future);
    final reading = action.updateTraffic(isCurrent: () => current);
    await Future<void>.delayed(Duration.zero);
    current = false;
    container.read(trafficsProvider.notifier).clear();
    pending.complete(const Traffic(up: 100));
    await reading;

    expect(container.read(trafficsProvider).list, isEmpty);
    expect(container.read(totalTrafficProvider), const Traffic());
  });

  test(
    'disposal invalidates a pending sample without provider writes',
    () async {
      final pending = Completer<Traffic>();
      when(() => core.getTraffic(any())).thenAnswer((_) => pending.future);
      final reading = action.updateTraffic(isCurrent: () => true);
      container.dispose();
      pending.complete(const Traffic(up: 1));

      await expectLater(reading, completes);
      verifyNever(() => core.getTotalTraffic(any()));
    },
  );
}

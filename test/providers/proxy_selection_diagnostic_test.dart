import 'dart:async';

import 'package:fl_clash/core/controller.dart';
import 'package:fl_clash/core/interface.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:riverpod/riverpod.dart';

class _MockCore extends Mock implements CoreHandlerInterface {}

class _TestProxiesAction extends ProxiesAction {
  _TestProxiesAction(this.controller);

  final CoreController controller;

  @override
  CoreController get proxyController => controller;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _MockCore core;
  late ProviderContainer container;
  late ProxiesAction action;
  const params = ChangeProxyParams(groupName: 'Primary', proxyName: 'Node');

  setUp(() {
    core = _MockCore();
    container = ProviderContainer(
      overrides: [
        proxiesActionProvider.overrideWith(
          () => _TestProxiesAction(CoreController.test(core)),
        ),
      ],
    );
    action = container.read(proxiesActionProvider.notifier);
    when(() => core.closeConnections()).thenAnswer((_) async => true);
    when(() => core.resetConnections()).thenAnswer((_) async => true);
  });

  tearDown(() => container.dispose());

  test('rejected node switch never closes existing streams', () async {
    when(
      () => core.changeProxy(params),
    ).thenAnswer((_) async => 'Not found group');

    await expectLater(
      action.changeProxy(groupName: 'Primary', proxyName: 'Node'),
      throwsStateError,
    );

    verifyNever(() => core.closeConnections());
    verifyNever(() => core.resetConnections());
    expect(container.read(checkIpNumProvider), 0);
  });

  test('RPC failure does not interrupt existing streams', () async {
    when(() => core.changeProxy(params)).thenThrow(StateError('disconnected'));

    await expectLater(
      action.changeProxy(groupName: 'Primary', proxyName: 'Node'),
      throwsStateError,
    );

    verifyNever(() => core.closeConnections());
    verifyNever(() => core.resetConnections());
  });

  test(
    'successful selection respects explicit close-connections option',
    () async {
      container
          .read(appSettingProvider.notifier)
          .update((value) => value.copyWith(closeConnections: true));
      when(() => core.changeProxy(params)).thenAnswer((_) async => '');

      await action.changeProxy(groupName: 'Primary', proxyName: 'Node');

      verifyInOrder([
        () => core.changeProxy(params),
        () => core.closeConnections(),
      ]);
      verifyNever(() => core.resetConnections());
      expect(container.read(checkIpNumProvider), 1);
    },
  );

  test('default selection preserves active streams', () async {
    when(() => core.changeProxy(params)).thenAnswer((_) async => '');

    await action.changeProxy(groupName: 'Primary', proxyName: 'Node');

    verifyNever(() => core.closeConnections());
    verify(() => core.resetConnections()).called(1);
  });

  test('connection cleanup failure does not undo a selected node', () async {
    container
        .read(appSettingProvider.notifier)
        .update((value) => value.copyWith(closeConnections: true));
    when(() => core.changeProxy(params)).thenAnswer((_) async => '');
    when(() => core.closeConnections()).thenThrow(StateError('cleanup failed'));

    await action.changeProxy(groupName: 'Primary', proxyName: 'Node');

    verify(() => core.changeProxy(params)).called(1);
    verify(() => core.closeConnections()).called(1);
    verifyNever(() => core.resetConnections());
    expect(container.read(checkIpNumProvider), 1);
  });

  test(
    'late response after disposal does not close existing streams',
    () async {
      final response = Completer<String>();
      when(() => core.changeProxy(params)).thenAnswer((_) => response.future);
      final operation = action.changeProxy(
        groupName: 'Primary',
        proxyName: 'Node',
      );

      container.dispose();
      response.complete('');
      await operation;

      verifyNever(() => core.closeConnections());
      verifyNever(() => core.resetConnections());
    },
  );

  test('runtime logs are retained before setup and bounded at 500', () {
    final logs = container.read(logsProvider.notifier);
    for (var index = 0; index < 510; index++) {
      logs.add(Log.app('entry-$index'));
    }
    final entries = container.read(logsProvider).list;
    expect(entries, hasLength(500));
    expect(entries.first.payload, 'entry-10');
    expect(entries.last.payload, 'entry-509');
  });
}

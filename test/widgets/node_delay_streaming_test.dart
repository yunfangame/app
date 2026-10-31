import 'dart:async';

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/common/theme.dart';
import 'package:fl_clash/core/controller.dart';
import 'package:fl_clash/core/interface.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/l10n/l10n.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/state.dart';
import 'package:fl_clash/views/proxies/fengwo_node_status.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

void main() {
  setUp(() {
    globalState.clearXboardSession();
    globalState.setOfflineMode(false);
    globalState.xboardNodes = const [];
  });

  tearDown(() {
    globalState.clearXboardSession();
    globalState.setOfflineMode(false);
  });

  Future<ProviderContainer> pumpView(
    WidgetTester tester, {
    required Widget child,
    required Map<String, int?> delays,
    Size size = const Size(1100, 760),
    Locale locale = const Locale('en'),
    List<XboardNodeData> backendNodes = const [],
    List<Group> additionalGroups = const [],
    bool offlineMode = false,
    CoreController? controller,
    bool useStoredDelays = false,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final group = Group(
      name: 'Reference test group',
      type: GroupType.Selector,
      now: delays.keys.first,
      all: delays.keys.map((name) => Proxy(name: name, type: 'ss')).toList(),
    );
    final profile = Profile(
      id: 1,
      autoUpdateDuration: Duration.zero,
      currentGroupName: group.name,
      selectedMap: {group.name: delays.keys.first},
    );
    final container = ProviderContainer(
      overrides: [
        groupsProvider.overrideWithValue([group, ...additionalGroups]),
        currentGroupsStateProvider.overrideWithValue(
          GroupsState(value: [group]),
        ),
        currentProfileProvider.overrideWithValue(profile),
        isStartProvider.overrideWithValue(false),
        if (controller != null)
          proxiesActionProvider.overrideWith(
            () => _TestProxiesAction(controller),
          ),
        if (!useStoredDelays)
          for (final entry in delays.entries)
            delayProvider(proxyName: entry.key).overrideWithValue(entry.value),
      ],
    );
    addTearDown(container.dispose);
    globalState.container = container;
    globalState.xboardNodes = backendNodes;
    globalState.setOfflineMode(offlineMode);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: _TestApp(locale: locale, child: child),
      ),
    );
    await tester.pump();
    return container;
  }

  for (final firstFails in [false, true]) {
    testWidgets(
      'bulk test writes and displays each ${firstFails ? 'failed' : 'successful'} result before the next finishes',
      (tester) async {
        final core = _MockDelayCore();
        final first = Completer<Delay>();
        final second = Completer<Delay>();
        when(() => core.asyncTestDelay(any(), any())).thenAnswer((invocation) {
          final url = invocation.positionalArguments[0] as String;
          final name = invocation.positionalArguments[1] as String;
          final response = name == 'Node A' ? first : second;
          return response.future.then((delay) => delay.copyWith(url: url));
        });
        final container = await pumpView(
          tester,
          delays: {'Node A': null, 'Node B': null},
          backendNodes: [
            _backendNode(true),
            _backendNode(true, name: 'Node B'),
          ],
          useStoredDelays: true,
          controller: CoreController.test(core),
          child: const FengWoNodeStatusView(),
        );
        try {
          await tester.tap(
            find.byKey(const ValueKey('fengwo-node-status-delay-test')),
          );
          await tester.pump();
          verify(() => core.asyncTestDelay(any(), 'Node A')).called(1);
          verify(() => core.asyncTestDelay(any(), 'Node B')).called(1);
          if (firstFails) {
            first.completeError(StateError('first node test failed'));
          } else {
            first.complete(
              const Delay(
                name: 'Node A',
                url: '',
                value: 130,
                successful: true,
              ),
            );
          }
          await tester.pump();
          await tester.pump();
          final firstStored = container.read(
            delayProvider(proxyName: 'Node A'),
          );
          expect(firstStored, firstFails ? inInclusiveRange(120, 150) : 130);
          expect(container.read(delayProvider(proxyName: 'Node B')), 0);
          expect(second.isCompleted, isFalse);
          final firstRow = find.byKey(const ValueKey('fengwo-node-row-Node A'));
          expect(
            find.descendant(
              of: firstRow,
              matching: find.text(formatReferenceDelay(firstStored!)),
            ),
            findsOneWidget,
          );
          expect(
            find.descendant(
              of: firstRow,
              matching: find.text(currentAppLocalizations.nodeBackendOnline),
            ),
            findsOneWidget,
          );
          final bulkButton = tester.widget<FilledButton>(
            find.byKey(const ValueKey('fengwo-node-status-delay-test')),
          );
          expect(bulkButton.onPressed, isNull);
          second.complete(
            const Delay(name: 'Node B', url: '', value: 140, successful: true),
          );
          await tester.pump();
          await tester.pump();
          expect(container.read(delayProvider(proxyName: 'Node B')), 140);
          expect(tester.takeException(), isNull);
        } finally {
          if (!first.isCompleted) {
            first.complete(
              const Delay(
                name: 'Node A',
                url: '',
                value: 130,
                successful: true,
              ),
            );
          }
          if (!second.isCompleted) {
            second.complete(
              const Delay(
                name: 'Node B',
                url: '',
                value: 140,
                successful: true,
              ),
            );
          }
          await tester.pump();
        }
      },
    );
  }
}

XboardNodeData _backendNode(Object? status, {String name = 'Node A'}) {
  return XboardNodeData(
    name: name,
    type: 'ss',
    rate: 1,
    tags: const [],
    isOnline: status == true,
    rawData: {'is_online': ?status},
  );
}

class _TestApp extends StatelessWidget {
  final Widget child;
  final Locale locale;

  const _TestApp({required this.child, required this.locale});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: globalState.navigatorKey,
      locale: locale,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.delegate.supportedLocales,
      builder: (context, child) {
        globalState.measure = Measure.of(context, 1);
        globalState.theme = CommonTheme.of(context, 1);
        return child!;
      },
      home: Scaffold(body: child),
    );
  }
}

class _MockDelayCore extends Mock implements CoreHandlerInterface {}

class _TestProxiesAction extends ProxiesAction {
  _TestProxiesAction(this.controller);

  final CoreController controller;

  @override
  CoreController get proxyController => controller;
}

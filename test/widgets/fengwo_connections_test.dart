import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/common/theme.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/l10n/l10n.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/state.dart';
import 'package:fl_clash/views/connection/fengwo_connections.dart';
import 'package:fl_clash/widgets/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  tearDown(() {
    globalState.xboardNodes = const [];
    globalState.setOfflineMode(false);
  });

  TrackerInfo connection({
    int download = 2048,
    int upload = 1024,
    int? downloadSpeed = 512,
    int? uploadSpeed = 256,
  }) {
    return TrackerInfo(
      id: 'connection-1',
      download: download,
      upload: upload,
      start: DateTime(2026, 8, 29, 10),
      metadata: const Metadata(
        network: 'tcp',
        host: 'clerk.openrouter.ai',
        destinationIP: '1.1.1.1',
        destinationPort: '443',
        process: 'Browser',
      ),
      chains: const ['Manual select'],
      rule: 'MATCH',
      rulePayload: '',
      downloadSpeed: downloadSpeed,
      uploadSpeed: uploadSpeed,
    );
  }

  Future<ProviderContainer> pumpView(
    WidgetTester tester, {
    required Size size,
    required Future<List<TrackerInfo>> Function() reader,
    FengWoConnectionRuleApplier? ruleApplier,
    Brightness brightness = Brightness.light,
    DateTime Function()? now,
    Mode mode = Mode.rule,
    int? measuredDelay,
    List<XboardNodeData> backendNodes = const [],
    bool offlineMode = false,
    bool nestedLeaf = false,
    Locale locale = const Locale('en'),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);

    const profile = Profile(
      id: 1,
      autoUpdateDuration: Duration.zero,
      currentGroupName: 'Manual select',
      selectedMap: {'Manual select': 'Node A'},
    );
    const group = Group(
      name: 'Manual select',
      type: GroupType.Selector,
      now: 'Node A',
      all: [Proxy(name: 'Node A', type: 'ss')],
    );
    final container = ProviderContainer(
      overrides: [
        groupsProvider.overrideWithValue([
          group,
          if (nestedLeaf)
            const Group(
              name: 'Node A',
              type: GroupType.URLTest,
              now: 'Selected leaf',
              all: [Proxy(name: 'Selected leaf', type: 'ss')],
            ),
        ]),
        currentProfileProvider.overrideWithValue(profile),
        delayProvider(proxyName: 'Node A').overrideWithValue(measuredDelay),
        patchClashConfigProvider.overrideWithBuild(
          (_, _) => PatchClashConfig(mode: mode),
        ),
      ],
    );
    addTearDown(container.dispose);
    globalState.container = container;
    globalState.xboardNodes = backendNodes;
    globalState.setOfflineMode(offlineMode);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: _TestApp(
          brightness: brightness,
          locale: locale,
          child: PageActivityScope(
            isActive: true,
            child: FengWoConnectionsView(
              connectionsReader: reader,
              ruleApplier: ruleApplier,
              now: now,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    return container;
  }

  testWidgets('renders the desktop table and live summary', (tester) async {
    await pumpView(
      tester,
      size: const Size(1500, 980),
      reader: () async => [connection()],
      now: () => DateTime(2026, 8, 29, 10, 0, 5),
    );
    await tester.pump();

    expect(find.text('Live connections'), findsWidgets);
    expect(find.text('clerk.openrouter.ai:443'), findsOneWidget);
    expect(find.text('Manual select'), findsOneWidget);
    expect(find.text('Connected'), findsOneWidget);
    expect(find.text('00:00:05'), findsOneWidget);
    expect(find.text('Active connections'), findsOneWidget);
    expect(tester.takeException(), null);
  });

  for (final size in [const Size(1500, 980), const Size(390, 844)]) {
    for (final sample in <(int?, String)>[
      (null, '-- ms'),
      (0, '-- ms'),
      (80, '80 ms'),
      (100, '100 ms'),
      (101, '100 ms'),
      (150, '100 ms'),
      (151, '101 ms'),
      (350, '300 ms'),
      (500, '450 ms'),
    ]) {
      testWidgets('connection summary references ${sample.$1} at $size', (
        tester,
      ) async {
        final container = await pumpView(
          tester,
          size: size,
          reader: () async => [],
          measuredDelay: sample.$1,
        );
        await tester.pump();

        final l10n = tester
            .element(find.byType(FengWoConnectionsView))
            .appLocalizations;
        expect(find.text(l10n.referenceCurrentNodeDelay), findsOneWidget);
        expect(find.text(sample.$2), findsOneWidget);
        expect(container.read(delayProvider(proxyName: 'Node A')), sample.$1);
        expect(tester.takeException(), isNull);
      });
    }
  }

  for (final size in [const Size(1500, 980), const Size(390, 844)]) {
    for (final sample
        in <(String, List<XboardNodeData>, bool, XboardNodeDisplayStatus)>[
          (
            'online',
            [_backendNode(true)],
            false,
            XboardNodeDisplayStatus.online,
          ),
          (
            'offline',
            [_backendNode(false)],
            false,
            XboardNodeDisplayStatus.offline,
          ),
          ('absent', [], false, XboardNodeDisplayStatus.unknown),
          (
            'missing field',
            [_backendNode(null)],
            false,
            XboardNodeDisplayStatus.unknown,
          ),
          (
            'ambiguous',
            [_backendNode(true), _backendNode(false)],
            false,
            XboardNodeDisplayStatus.unknown,
          ),
          (
            'offline cache',
            [_backendNode(true)],
            true,
            XboardNodeDisplayStatus.unknown,
          ),
        ]) {
      testWidgets('connection failure displays ${sample.$1} backend at $size', (
        tester,
      ) async {
        final container = await pumpView(
          tester,
          size: size,
          reader: () async => [],
          measuredDelay: -1,
          backendNodes: sample.$2,
          offlineMode: sample.$3,
        );
        await tester.pump();

        expect(
          find.text(formatXboardNodeDisplayStatus(sample.$4)),
          findsOneWidget,
        );
        expect(find.text(currentAppLocalizations.timeout), findsNothing);
        expect(find.textContaining(' ms'), findsNothing);
        expect(container.read(delayProvider(proxyName: 'Node A')), -1);
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('connection failure resolves selected group leaf status', (
    tester,
  ) async {
    await pumpView(
      tester,
      size: const Size(1500, 980),
      reader: () async => [],
      measuredDelay: -1,
      backendNodes: [_backendNode(true, name: 'Selected leaf')],
      nestedLeaf: true,
    );
    await tester.pump();

    expect(
      find.text(currentAppLocalizations.nodeBackendOnline),
      findsOneWidget,
    );
    expect(find.text(currentAppLocalizations.nodeStatusUnknown), findsNothing);
    expect(tester.takeException(), isNull);
  });

  for (final locale in [const Locale('en'), const Locale('zh', 'CN')]) {
    for (final sample in <(int, Object?, XboardNodeDisplayStatus)>[
      (350, null, XboardNodeDisplayStatus.unknown),
      (500, null, XboardNodeDisplayStatus.unknown),
      (-1, true, XboardNodeDisplayStatus.online),
      (-1, false, XboardNodeDisplayStatus.offline),
      (-1, null, XboardNodeDisplayStatus.unknown),
    ]) {
      testWidgets(
        'mobile summary fully fits ${sample.$1}/${sample.$3} in $locale',
        (tester) async {
          await pumpView(
            tester,
            size: const Size(390, 844),
            reader: () async => [],
            measuredDelay: sample.$1,
            backendNodes: [_backendNode(sample.$2)],
            locale: locale,
          );
          await tester.pump();

          final l10n = tester
              .element(find.byType(FengWoConnectionsView))
              .appLocalizations;
          final expected = sample.$1 > 0
              ? '${sample.$1 - 50} ms'
              : formatXboardNodeDisplayStatus(sample.$3);
          final card = find.byKey(
            ValueKey('connection-summary-${l10n.referenceCurrentNodeDelay}'),
          );
          final value = find.descendant(
            of: card,
            matching: find.text(expected),
          );
          expect(value, findsOneWidget);
          expect(
            tester.renderObject<RenderParagraph>(value).didExceedMaxLines,
            isFalse,
          );
          final textBounds = tester.getRect(value);
          final cardBounds = tester.getRect(card);
          expect(textBounds.left, greaterThanOrEqualTo(cardBounds.left));
          expect(textBounds.right, lessThanOrEqualTo(cardBounds.right));
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  testWidgets('calculates speed from consecutive snapshots', (tester) async {
    var reads = 0;
    var sampledAt = DateTime(2026, 8, 29, 10);
    await pumpView(
      tester,
      size: const Size(1500, 980),
      reader: () async {
        reads++;
        return [
          connection(
            download: reads == 1 ? 0 : 2048,
            upload: reads == 1 ? 0 : 1024,
            downloadSpeed: null,
            uploadSpeed: null,
          ),
        ];
      },
      now: () => sampledAt,
    );
    await tester.pump();
    sampledAt = sampledAt.add(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();

    expect(reads, greaterThanOrEqualTo(2));
    expect(find.text('2 KB/s'), findsWidgets);
    expect(find.text('1 KB/s'), findsWidgets);
    expect(tester.takeException(), null);
  });

  testWidgets('adds a direct rule with a global proxy fallback', (
    tester,
  ) async {
    Rule? appliedRule;
    String? appliedFallback;
    bool? switched;
    await pumpView(
      tester,
      size: const Size(1500, 980),
      mode: Mode.global,
      reader: () async => [connection()],
      ruleApplier:
          ({
            required connection,
            required rule,
            required fallbackTarget,
            required switchToRuleMode,
          }) async {
            appliedRule = rule;
            appliedFallback = fallbackTarget;
            switched = switchToRuleMode;
          },
    );
    await tester.pump();

    await tester.tap(find.byIcon(Icons.more_vert_rounded).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add rule'));
    await tester.pumpAndSettle();

    expect(find.text('DOMAIN,clerk.openrouter.ai,DIRECT'), findsOneWidget);
    expect(find.text('MATCH,Manual select'), findsOneWidget);
    expect(find.text('Other traffic policy'), findsOneWidget);

    final applyButton = find.byKey(const ValueKey('apply-connection-rule'));
    await tester.ensureVisible(applyButton);
    await tester.pumpAndSettle();
    await tester.tap(applyButton);
    await tester.pumpAndSettle();

    expect(appliedRule?.ruleAction, RuleAction.DOMAIN);
    expect(appliedRule?.content, 'clerk.openrouter.ai');
    expect(appliedRule?.ruleTarget, 'DIRECT');
    expect(appliedFallback, 'Manual select');
    expect(switched, isTrue);
    expect(tester.takeException(), null);
  });

  testWidgets('mobile dark layout uses cards without overflow', (tester) async {
    await pumpView(
      tester,
      size: const Size(390, 844),
      brightness: Brightness.dark,
      reader: () async => [connection()],
      now: () => DateTime(2026, 8, 29, 10, 0, 5),
    );
    await tester.pump();

    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('fengwo-mobile-connection-connection-1')),
      500,
      scrollable: find
          .descendant(
            of: find.byKey(const ValueKey('fengwo-connections-mobile-scroll')),
            matching: find.byType(Scrollable),
          )
          .first,
    );

    expect(
      find.byKey(const ValueKey('fengwo-mobile-connection-connection-1')),
      findsOneWidget,
    );
    expect(find.text('clerk.openrouter.ai:443'), findsOneWidget);
    expect(tester.takeException(), null);
  });
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
  final Brightness brightness;
  final Locale locale;

  const _TestApp({
    required this.child,
    required this.brightness,
    required this.locale,
  });

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: globalState.navigatorKey,
      locale: locale,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF136DF3),
          brightness: brightness,
        ),
      ),
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
      home: child,
    );
  }
}

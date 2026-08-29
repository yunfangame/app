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
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
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
        groupsProvider.overrideWithValue([group]),
        currentProfileProvider.overrideWithValue(profile),
        patchClashConfigProvider.overrideWithBuild(
          (_, _) => PatchClashConfig(mode: mode),
        ),
      ],
    );
    addTearDown(container.dispose);
    globalState.container = container;

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: _TestApp(
          brightness: brightness,
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

class _TestApp extends StatelessWidget {
  final Widget child;
  final Brightness brightness;

  const _TestApp({required this.child, required this.brightness});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: globalState.navigatorKey,
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

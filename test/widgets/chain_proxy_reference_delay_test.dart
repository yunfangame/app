import 'package:fl_clash/common/chain_proxy.dart';
import 'package:fl_clash/core/controller.dart';
import 'package:fl_clash/core/interface.dart';
import 'package:fl_clash/l10n/l10n.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/views/practical_tools/network_tool_dialogs.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

void main() {
  const entry = ChainProxyConfig(
    name: 'Reference chain',
    server: 'proxy.example.test',
    port: 1080,
  );
  const primaryUrl = 'https://www.gstatic.com/generate_204';
  const fallbackUrl = 'https://cp.cloudflare.com/generate_204';

  tearDown(CoreController.resetInstance);

  for (final scenario in const [
    (
      name: 'rejects two failed probes with positive reference values',
      successes: [false, false],
      enabled: false,
    ),
    (
      name: 'waits for the successful fallback after a failed reference value',
      successes: [false, true],
      enabled: true,
    ),
    (
      name: 'accepts an actual successful probe without a fallback',
      successes: [true],
      enabled: true,
    ),
  ]) {
    testWidgets('Windows chain dialog ${scenario.name}', (tester) async {
      final core = _MockChainCore();
      final urls = <String>[];
      var applyCount = 0;
      when(() => core.asyncTestDelay(any(), chainProxyRuntimeName)).thenAnswer((
        invocation,
      ) async {
        final url = invocation.positionalArguments.first as String;
        final index = urls.length;
        urls.add(url);
        return Delay(
          name: chainProxyRuntimeName,
          url: url,
          value: 137,
          successful: scenario.successes[index],
        );
      });
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container.read(appSettingProvider.notifier).value = const AppSettingProps(
        chainProxies: [entry],
        testUrl: primaryUrl,
      );
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: _TestApp(
            child: ChainProxyDialog(
              controller: CoreController.test(core),
              isWindows: true,
              coreRestarter: () async {
                applyCount++;
              },
            ),
          ),
        ),
      );
      try {
        final toggle = find.byKey(
          const ValueKey('chain-proxy-toggle-Reference chain'),
        );
        await tester.tap(toggle);
        for (var frame = 0; frame < 20; frame++) {
          await tester.pump();
          if (urls.length == scenario.successes.length &&
              tester.widget<TextButton>(toggle).onPressed != null) {
            break;
          }
        }
        expect(tester.widget<TextButton>(toggle).onPressed, isNotNull);

        expect(
          container.read(appSettingProvider).activeChainProxyName,
          scenario.enabled ? entry.name : isNull,
        );
        expect(applyCount, scenario.enabled ? 1 : 2);
        expect(
          urls,
          scenario.successes.length == 1
              ? [primaryUrl]
              : [primaryUrl, fallbackUrl],
        );
        verify(
          () => core.asyncTestDelay(any(), chainProxyRuntimeName),
        ).called(scenario.successes.length);
        expect(
          find.descendant(
            of: toggle,
            matching: find.text(
              scenario.enabled
                  ? AppLocalizations.current.disableProxy
                  : AppLocalizations.current.enableProxy,
            ),
          ),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
      }
    });
  }
}

class _MockChainCore extends Mock implements CoreHandlerInterface {}

class _TestApp extends StatelessWidget {
  const _TestApp({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      locale: const Locale('zh', 'CN'),
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.delegate.supportedLocales,
      home: Scaffold(body: child),
    );
  }
}

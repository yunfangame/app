import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/common/theme.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/l10n/l10n.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/state.dart';
import 'package:fl_clash/views/dashboard/fengwo_desktop_dashboard.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final scenario in [
    (
      name: 'default window',
      size: const Size(1280, 720),
      textScaler: TextScaler.noScaling,
    ),
    (
      name: 'compact window',
      size: const Size(1024, 640),
      textScaler: TextScaler.noScaling,
    ),
    (
      name: 'default window with large text',
      size: const Size(1280, 720),
      textScaler: const TextScaler.linear(1.4),
    ),
  ]) {
    testWidgets('desktop mode controls receive taps in ${scenario.name}', (
      tester,
    ) async {
      tester.view.physicalSize = scenario.size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      const profile = Profile(id: 1, autoUpdateDuration: Duration.zero);
      final container = ProviderContainer(
        overrides: [
          profilesProvider.overrideWithValue(const [profile]),
          currentProfileProvider.overrideWithValue(profile),
          setupActionProvider.overrideWith(_RecordingSetupAction.new),
        ],
      );
      addTearDown(container.dispose);
      globalState.container = container;

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: _TestApp(
            textScaler: scenario.textScaler,
            child: const _DesktopWindowFrame(),
          ),
        ),
      );
      await tester.pump();

      final systemProxy = find.byKey(
        const ValueKey('fengwo-desktop-system-proxy'),
      );
      await tester.tap(systemProxy);
      await tester.pump();
      expect(container.read(networkSettingProvider).systemProxy, isFalse);

      final l10n = tester
          .element(find.byType(FengWoDesktopDashboard))
          .appLocalizations;
      await tester.tap(find.text(l10n.tun));
      await tester.pump();
      expect(container.read(patchClashConfigProvider).tun.enable, isTrue);

      await tester.tap(
        find.byKey(const ValueKey('fengwo-desktop-global-mode')),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(
        find.byKey(const ValueKey('global-mode-confirmation-dialog')),
        findsOneWidget,
      );
      globalState.navigatorKey.currentState!.pop();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      container
          .read(patchClashConfigProvider.notifier)
          .update((config) => config.copyWith(mode: Mode.global));
      await tester.pump();

      await tester.tap(find.text(l10n.rule));
      await tester.pump();
      expect(container.read(patchClashConfigProvider).mode, Mode.rule);
      expect(tester.takeException(), isNull);
    });
  }
}

class _DesktopWindowFrame extends StatelessWidget {
  const _DesktopWindowFrame();

  @override
  Widget build(BuildContext context) {
    return const Column(
      children: [
        SizedBox(height: 40),
        Expanded(
          child: Row(
            children: [
              SizedBox(width: 222),
              Expanded(
                child: Column(
                  children: [
                    SizedBox(height: 82),
                    Expanded(child: FengWoDesktopDashboard()),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _RecordingSetupAction extends SetupAction {
  @override
  Future<void> enableWindowsTun() async {
    ref
        .read(patchClashConfigProvider.notifier)
        .update((s) => s.copyWith.tun(enable: true));
  }

  @override
  Future<ModeSwitchResult> changeModeAndWait(
    Mode mode, {
    bool Function()? isCancelled,
  }) async {
    if (isCancelled?.call() == true) return ModeSwitchResult.cancelled;
    ref
        .read(patchClashConfigProvider.notifier)
        .update((config) => config.copyWith(mode: mode));
    return ModeSwitchResult.switched;
  }
}

class _TestApp extends StatelessWidget {
  final Widget child;
  final TextScaler textScaler;

  const _TestApp({required this.child, required this.textScaler});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: globalState.navigatorKey,
      locale: const Locale('zh', 'CN'),
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF0969DA)),
      ),
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.delegate.supportedLocales,
      builder: (context, child) {
        final content = Builder(
          builder: (context) {
            globalState.measure = Measure.of(context, 1);
            globalState.theme = CommonTheme.of(context, 1);
            return child!;
          },
        );
        return MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: textScaler),
          child: content,
        );
      },
      home: child,
    );
  }
}

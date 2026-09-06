import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/common/theme.dart';
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
  testWidgets('pending connection never displays connected or a runtime', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final container = ProviderContainer(
      overrides: [
        profilesProvider.overrideWithValue([
          const Profile(id: 1, autoUpdateDuration: Duration.zero),
        ]),
      ],
    );
    addTearDown(container.dispose);
    globalState.container = container;
    container.read(connectionPendingProvider.notifier).value = true;
    try {
      await tester.pumpWidget(
        UncontrolledProviderScope(container: container, child: const _App()),
      );
      await tester.pump();
      final l10n = AppLocalizations.current;
      expect(find.text(l10n.connecting), findsOneWidget);
      expect(find.text(l10n.connected), findsNothing);
      expect(container.read(runTimeProvider), isNull);

      container.read(connectionPendingProvider.notifier).value = false;
      await tester.pump();
      expect(find.text(l10n.connecting), findsNothing);
      expect(find.text(l10n.connected), findsNothing);

      container.read(runTimeProvider.notifier).value = 0;
      await tester.pump();
      expect(find.text(l10n.connected), findsWidgets);

      container.read(runTimeProvider.notifier).value = null;
      container.read(connectionPendingProvider.notifier).value = true;
      container
          .read(excludeSSIDsProvider.notifier)
          .update((_) => ['test-wifi']);
      container.read(currentSSIDProvider.notifier).value = 'test-wifi';
      await tester.pump();
      expect(find.text(l10n.suspended), findsOneWidget);
      expect(find.text(l10n.connecting), findsNothing);
      expect(find.text(l10n.connected), findsNothing);
      expect(tester.takeException(), isNull);
    } finally {
      await tester.pumpWidget(const SizedBox());
    }
  });
}

class _App extends StatelessWidget {
  const _App();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      locale: const Locale('zh', 'CN'),
      theme: ThemeData(platform: TargetPlatform.windows),
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
      home: const FengWoDesktopDashboard(),
    );
  }
}

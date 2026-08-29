import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/common/theme.dart';
import 'package:fl_clash/l10n/l10n.dart';
import 'package:fl_clash/providers/app.dart';
import 'package:fl_clash/providers/config.dart';
import 'package:fl_clash/state.dart';
import 'package:fl_clash/views/theme.dart';
import 'package:fl_clash/views/tools.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('wide layout opens an anchored theme panel and updates mode', (
    tester,
  ) async {
    final container = await _pumpTestApp(tester, size: const Size(1000, 800));

    await tester.tap(find.byTooltip('Theme'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('theme-quick-panel')), findsOneWidget);
    expect(find.byType(BottomSheet), findsNothing);
    expect(
      tester.getSize(find.byKey(const Key('theme-quick-panel'))).width,
      340,
    );

    await tester.tap(find.text('Light'));
    await tester.pump();
    expect(container.read(themeSettingProvider).themeMode, ThemeMode.light);

    await tester.tap(find.text('Theme color'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('theme-color-dialog')), findsOneWidget);
  });

  testWidgets('compact layout opens the same theme panel in a bottom sheet', (
    tester,
  ) async {
    await _pumpTestApp(tester, size: const Size(390, 844));

    await tester.tap(find.byTooltip('Theme'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('theme-quick-panel')), findsOneWidget);
    expect(find.byType(BottomSheet), findsOneWidget);
    expect(find.text('Pure black mode'), findsOneWidget);
    expect(find.text('Color schemes'), findsOneWidget);
  });

  testWidgets('language button opens an anchored native-language list', (
    tester,
  ) async {
    final container = await _pumpTestApp(tester, size: const Size(1000, 800));

    await tester.tap(find.byTooltip('Language'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('locale-quick-panel')), findsOneWidget);
    expect(
      tester.getSize(find.byKey(const Key('locale-quick-panel'))).width,
      252,
    );
    expect(find.text('English'), findsOneWidget);
    expect(find.text('日本語'), findsOneWidget);
    expect(find.text('Русский'), findsOneWidget);
    expect(find.text('中文简体'), findsOneWidget);
    final selectedRow = find.ancestor(
      of: find.byIcon(Icons.check_rounded),
      matching: find.byType(InkWell),
    );
    expect(
      find.descendant(of: selectedRow, matching: find.text('Default')),
      findsOneWidget,
    );

    await tester.tap(find.text('中文简体'));
    await tester.pumpAndSettle();
    expect(container.read(appSettingProvider).locale, 'zh_CN');
  });
}

Future<ProviderContainer> _pumpTestApp(
  WidgetTester tester, {
  required Size size,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final container = ProviderContainer();
  addTearDown(container.dispose);
  globalState.container = container;
  container.read(viewSizeProvider.notifier).update((_) => size);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        navigatorKey: globalState.navigatorKey,
        locale: const Locale('en'),
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
        home: Consumer(
          builder: (context, ref, child) {
            ref.watch(appSettingProvider);
            return Scaffold(
              body: Center(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Builder(
                      builder: (context) => IconButton(
                        tooltip: 'Language',
                        onPressed: () => ToolLocaleSelector.show(context),
                        icon: const Icon(Icons.translate_rounded),
                      ),
                    ),
                    Builder(
                      builder: (context) => IconButton(
                        tooltip: 'Theme',
                        onPressed: () => ThemeQuickSelector.show(context),
                        icon: const Icon(Icons.palette_outlined),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

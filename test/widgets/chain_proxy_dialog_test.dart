import 'dart:async';

import 'package:fl_clash/common/chain_proxy.dart';
import 'package:fl_clash/l10n/l10n.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/views/practical_tools/network_tool_dialogs.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const first = ChainProxyConfig(
    name: 'Taiwan',
    server: 'proxy-one.example',
    port: 1080,
  );
  const second = ChainProxyConfig(
    name: 'Japan',
    protocol: ChainProxyProtocol.http,
    server: 'proxy-two.example',
    port: 8080,
  );

  testWidgets(
    'saves without a direct network check and rejects duplicate names',
    (tester) async {
      var validationCount = 0;
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: _TestApp(
            child: ChainProxyDialog(
              validator: (config) {
                validationCount++;
                return Future.value(
                  const ChainProxyValidationResult(
                    ChainProxyValidationStatus.unavailable,
                  ),
                );
              },
              coreRestarter: () async {},
            ),
          ),
        ),
      );

      await tester.tap(find.widgetWithText(FilledButton, '添加代理'));
      await tester.pumpAndSettle();
      final fields = find.byType(TextFormField);
      await tester.enterText(fields.at(0), 'Taiwan');
      await tester.enterText(fields.at(1), '127.0.0.1');
      await tester.enterText(fields.at(2), '1080');
      await tester.tap(find.widgetWithText(FilledButton, '添加代理').last);
      await tester.pumpAndSettle();

      expect(
        container.read(appSettingProvider).chainProxies.single.name,
        'Taiwan',
      );
      expect(find.text('Taiwan'), findsOneWidget);
      expect(validationCount, 0);

      await tester.tap(find.widgetWithText(FilledButton, '添加代理'));
      await tester.pumpAndSettle();
      final duplicateFields = find.byType(TextFormField);
      await tester.enterText(duplicateFields.at(0), ' taiwan ');
      await tester.enterText(duplicateFields.at(1), '127.0.0.1');
      await tester.enterText(duplicateFields.at(2), '1081');
      await tester.tap(find.widgetWithText(FilledButton, '添加代理').last);
      await tester.pump();

      expect(find.text('代理名称已存在，请使用其他名称'), findsOneWidget);
      expect(validationCount, 0);
    },
  );

  testWidgets('can reveal and hide a chain proxy password', (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const _TestApp(child: ChainProxyDialog()),
      ),
    );

    await tester.tap(find.widgetWithText(FilledButton, '添加代理'));
    await tester.pumpAndSettle();
    final passwordField = find.byType(TextFormField).at(4);
    final editableText = find.descendant(
      of: passwordField,
      matching: find.byType(EditableText),
    );
    expect(tester.widget<EditableText>(editableText).obscureText, isTrue);

    final visibility = find.byKey(
      const ValueKey('chain-proxy-password-visibility'),
    );
    await tester.tap(visibility);
    await tester.pump();
    expect(tester.widget<EditableText>(editableText).obscureText, isFalse);

    await tester.tap(visibility);
    await tester.pump();
    expect(tester.widget<EditableText>(editableText).obscureText, isTrue);
  });

  testWidgets('only the active proxy can be stopped while running', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final restart = Completer<void>();
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container.read(appSettingProvider.notifier).value = const AppSettingProps(
      chainProxies: [first, second],
    );
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: _TestApp(
          child: ChainProxyDialog(
            validator: (_) async => const ChainProxyValidationResult(
              ChainProxyValidationStatus.available,
            ),
            coreRestarter: () => restart.future,
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('chain-proxy-toggle-Taiwan')));
    await tester.pump(const Duration(milliseconds: 100));

    expect(container.read(appSettingProvider).activeChainProxyName, 'Taiwan');
    expect(find.textContaining('当前链式代理已启动'), findsOneWidget);
    final otherToggle = tester.widget<TextButton>(
      find.byKey(const ValueKey('chain-proxy-toggle-Japan')),
    );
    expect(otherToggle.onPressed, isNull);
    expect(
      tester
          .widgetList<IconButton>(find.byType(IconButton))
          .where((button) => button.tooltip == '编辑' || button.tooltip == '删除')
          .every((button) => button.onPressed == null),
      isTrue,
    );

    restart.complete();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('停止'), findsOneWidget);
  });

  testWidgets('can stop and re-enable the same proxy repeatedly', (
    tester,
  ) async {
    var validationCount = 0;
    var restartCount = 0;
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container.read(appSettingProvider.notifier).value = const AppSettingProps(
      chainProxies: [first],
    );
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: _TestApp(
          child: ChainProxyDialog(
            validator: (_) async {
              validationCount++;
              return const ChainProxyValidationResult(
                ChainProxyValidationStatus.available,
              );
            },
            coreRestarter: () async {
              restartCount++;
            },
          ),
        ),
      ),
    );

    final toggle = find.byKey(const ValueKey('chain-proxy-toggle-Taiwan'));
    await tester.tap(toggle);
    await tester.pump(const Duration(milliseconds: 100));
    expect(container.read(appSettingProvider).activeChainProxyName, 'Taiwan');
    expect(restartCount, 1);

    await tester.tap(toggle);
    await tester.pump(const Duration(milliseconds: 100));
    expect(container.read(appSettingProvider).activeChainProxyName, isNull);
    expect(restartCount, 2);

    await tester.tap(toggle);
    await tester.pump(const Duration(milliseconds: 100));
    expect(container.read(appSettingProvider).activeChainProxyName, 'Taiwan');
    expect(restartCount, 3);
    expect(validationCount, 2);
  });

  testWidgets('failed runtime validation restores the previous configuration', (
    tester,
  ) async {
    var restartCount = 0;
    var validationCount = 0;
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container.read(appSettingProvider.notifier).value = const AppSettingProps(
      chainProxies: [first],
    );
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: _TestApp(
          child: ChainProxyDialog(
            validator: (_) async {
              validationCount++;
              return const ChainProxyValidationResult(
                ChainProxyValidationStatus.unavailable,
              );
            },
            coreRestarter: () async {
              restartCount++;
            },
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('chain-proxy-toggle-Taiwan')));
    await tester.pumpAndSettle();

    expect(container.read(appSettingProvider).activeChainProxyName, isNull);
    expect(restartCount, 2);
    expect(validationCount, 1);
  });
}

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

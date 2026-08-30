import 'dart:async';

import 'package:fl_clash/common/streaming_unlock.dart';
import 'package:fl_clash/l10n/l10n.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/views/practical_tools.dart';
import 'package:fl_clash/views/practical_tools/network_tool_dialogs.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simple_icons/simple_icons.dart';

void main() {
  Widget app() {
    return ProviderScope(
      child: MaterialApp(
        locale: const Locale('zh', 'CN'),
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.delegate.supportedLocales,
        home: const Scaffold(body: PracticalToolsView()),
      ),
    );
  }

  Widget streamingApp(StreamingUnlockTester tester) {
    return ProviderScope(
      overrides: [isStartProvider.overrideWithValue(true)],
      child: MaterialApp(
        locale: const Locale('zh', 'CN'),
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.delegate.supportedLocales,
        home: Scaffold(body: StreamingTestDialog(tester: tester)),
      ),
    );
  }

  testWidgets('renders six practical tool cards', (tester) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('practical-tools-grid')), findsOneWidget);
    expect(find.text('网速测试'), findsOneWidget);
    expect(find.text('CF 优选 IP'), findsOneWidget);
    expect(find.text('IP 查询'), findsOneWidget);
    expect(find.text('流媒体解锁检测'), findsOneWidget);
    expect(find.text('链式代理管理'), findsOneWidget);
    expect(find.text('热门应用'), findsOneWidget);
    expect(tester.takeException(), null);
  });

  testWidgets('speed test card opens service chooser', (tester) async {
    tester.view.physicalSize = const Size(900, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('practical-tool-speedTest')));
    await tester.pumpAndSettle();

    expect(find.text('Speedtest'), findsOneWidget);
    expect(find.text('Google Fiber'), findsWidgets);
    expect(find.text('Fast.com'), findsOneWidget);
    expect(tester.takeException(), null);
  });

  testWidgets('narrow layout remains scrollable without overflow', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 760);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await tester.drag(
      find.byKey(const ValueKey('practical-tools-scroll')),
      const Offset(0, -900),
    );
    await tester.pumpAndSettle();

    expect(find.text('热门应用'), findsOneWidget);
    expect(tester.takeException(), null);
  });

  testWidgets('layout stays valid across responsive breakpoints', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(app());
    for (var width = 1180.0; width >= 380; width -= 20) {
      tester.view.physicalSize = Size(width, 800);
      await tester.pump(const Duration(milliseconds: 16));
      expect(tester.takeException(), isNull, reason: 'width: $width');
    }
  });

  testWidgets('chain proxy card opens manager and add form', (tester) async {
    tester.view.physicalSize = const Size(900, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    final card = find.byKey(const ValueKey('practical-tool-chainProxy'));
    await tester.ensureVisible(card);
    await tester.tap(card);
    await tester.pumpAndSettle();

    expect(find.text('当前未启用链式代理'), findsOneWidget);
    expect(find.text('暂无链式代理'), findsOneWidget);
    await tester.tap(find.text('添加代理'));
    await tester.pumpAndSettle();

    expect(find.text('协议'), findsOneWidget);
    expect(find.text('服务器'), findsOneWidget);
    expect(find.text('用户名'), findsOneWidget);
    expect(tester.takeException(), null);
  });

  testWidgets('popular apps use standard brand logos and names', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(900, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    final card = find.byKey(const ValueKey('practical-tool-popularApps'));
    await tester.ensureVisible(card);
    await tester.tap(card);
    await tester.pumpAndSettle();

    expect(find.text('Telegram'), findsOneWidget);
    expect(find.text('YouTube'), findsOneWidget);
    expect(find.text('Netflix'), findsOneWidget);
    expect(find.byIcon(SimpleIcons.telegram), findsOneWidget);
    expect(find.byIcon(SimpleIcons.youtube), findsOneWidget);
    expect(find.byIcon(SimpleIcons.netflix), findsOneWidget);
    expect(tester.takeException(), null);
  });

  testWidgets('streaming test reports the confirmed Netflix region', (
    tester,
  ) async {
    final unlockTester = StreamingUnlockTester(
      retryDelay: Duration.zero,
      fetcher: (uri) async => StreamingUnlockResponse(
        statusCode: 200,
        body: '',
        finalUri: uri.path == '/'
            ? Uri.parse('https://www.netflix.com/jp/')
            : Uri.parse('https://www.netflix.com/jp-en/title/81215567'),
      ),
    );

    await tester.pumpWidget(streamingApp(unlockTester));
    await tester.tap(find.byIcon(Icons.refresh_rounded).first);
    await tester.pumpAndSettle();

    expect(find.text('网页可访问 · JP'), findsOneWidget);
    expect(find.text('✅'), findsOneWidget);
    expect(tester.takeException(), null);
  });

  testWidgets('streaming challenge is shown as a reachable page', (
    tester,
  ) async {
    final unlockTester = StreamingUnlockTester(
      maxAttempts: 1,
      fetcher: (uri) async => StreamingUnlockResponse(
        statusCode: 403,
        body: 'region not supported',
        finalUri: uri,
      ),
    );

    await tester.pumpWidget(streamingApp(unlockTester));
    await tester.tap(find.byIcon(Icons.refresh_rounded).first);
    await tester.pumpAndSettle();

    expect(find.text('网页可访问，深度状态未确认'), findsOneWidget);
    expect(find.text('✅'), findsOneWidget);
    expect(tester.takeException(), null);
  });

  testWidgets('streaming test distinguishes a timeout', (tester) async {
    final unlockTester = StreamingUnlockTester(
      requestTimeout: const Duration(milliseconds: 20),
      retryDelay: Duration.zero,
      fetcher: (_) => Completer<StreamingUnlockResponse>().future,
    );

    await tester.pumpWidget(streamingApp(unlockTester));
    await tester.tap(find.byIcon(Icons.refresh_rounded).first);
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('检测超时，请重试'), findsOneWidget);
    expect(tester.takeException(), null);
  });
}

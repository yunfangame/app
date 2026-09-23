import 'dart:async';

import 'package:fl_clash/common/desktop_proxy_failure.dart';
import 'package:fl_clash/l10n/l10n.dart';
import 'package:fl_clash/widgets/desktop_proxy_failure_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<Completer<Object?>> pumpDialog(
    WidgetTester tester,
    Widget dialog,
  ) async {
    final result = Completer<Object?>();
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh', 'CN'),
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.delegate.supportedLocales,
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                result.complete(
                  await showDialog<Object?>(
                    context: context,
                    builder: (_) => dialog,
                  ),
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    return result;
  }

  const portFailure = DesktopProxyFailure(
    kind: DesktopProxyFailureKind.addressInUse,
    port: 7890,
    code: 'listener_not_ready',
  );

  testWidgets(
    'port conflict displays its reason and recovery choices in Chinese',
    (tester) async {
      try {
        await pumpDialog(
          tester,
          const DesktopProxyFailureDialog(failure: portFailure),
        );

        expect(find.text('代理启动失败'), findsOneWidget);
        expect(find.text('当前端口：7890'), findsOneWidget);
        expect(find.text('错误代码：listener_not_ready'), findsOneWidget);
        expect(
          find.text('当前监听端口已被其他程序占用。请关闭占用该端口的程序后重试，或更换端口。'),
          findsOneWidget,
        );
        expect(find.text('查看/导出日志'), findsOneWidget);
        expect(find.text('更换端口'), findsOneWidget);
        expect(find.text('重试'), findsOneWidget);
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
      }
    },
  );

  for (final kind in [
    DesktopProxyFailureKind.invalidBindAddress,
    DesktopProxyFailureKind.addressNotAvailable,
    DesktopProxyFailureKind.systemProxyAccessDenied,
    DesktopProxyFailureKind.systemProxyWriteFailed,
    DesktopProxyFailureKind.systemProxyReadbackFailed,
    DesktopProxyFailureKind.systemProxyFailed,
    DesktopProxyFailureKind.configurationFailed,
  ]) {
    testWidgets('$kind has no change-port action or false port-conflict text', (
      tester,
    ) async {
      try {
        await pumpDialog(
          tester,
          DesktopProxyFailureDialog(
            failure: DesktopProxyFailure(kind: kind, port: 7890, code: 'test'),
          ),
        );

        expect(find.text('更换端口'), findsNothing);
        expect(find.textContaining('已被其他程序占用'), findsNothing);
        expect(find.text('当前端口：7890'), findsOneWidget);
        expect(find.text('查看/导出日志'), findsOneWidget);
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
      }
    });
  }

  for (final entry in <String, DesktopProxyFailureChoice?>{
    'desktop-proxy-failure-logs': DesktopProxyFailureChoice.logs,
    'desktop-proxy-failure-retry': DesktopProxyFailureChoice.retry,
    'desktop-proxy-failure-change-port': DesktopProxyFailureChoice.changePort,
    'desktop-proxy-failure-cancel': null,
  }.entries) {
    testWidgets(
      '${entry.key} returns its choice without performing an operation',
      (tester) async {
        try {
          final result = await pumpDialog(
            tester,
            const DesktopProxyFailureDialog(failure: portFailure),
          );
          await tester.tap(find.byKey(ValueKey(entry.key)));
          await tester.pumpAndSettle();

          expect(await result.future, entry.value);
          expect(find.byType(DesktopProxyFailureDialog), findsNothing);
          expect(tester.takeException(), isNull);
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
        }
      },
    );
  }

  testWidgets('failure dialog permits dismissal without choosing a recovery', (
    tester,
  ) async {
    try {
      final result = await pumpDialog(
        tester,
        const DesktopProxyFailureDialog(failure: portFailure),
      );
      await tester.tapAt(const Offset(5, 5));
      await tester.pumpAndSettle();

      expect(await result.future, isNull);
      expect(find.byType(DesktopProxyFailureDialog), findsNothing);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
    }
  });

  testWidgets(
    'invalid and conflicting ports stay open with a useful validation error',
    (tester) async {
      try {
        final result = await pumpDialog(
          tester,
          const DesktopProxyPortDialog(
            currentPort: 7890,
            reservedPorts: {7891, 9090},
          ),
        );
        for (final entry in {
          '': '请输入 1024–49151 之间的整数端口',
          'abc': '请输入 1024–49151 之间的整数端口',
          '7890.5': '请输入 1024–49151 之间的整数端口',
          '1023': '请输入 1024–49151 之间的整数端口',
          '49152': '请输入 1024–49151 之间的整数端口',
          '7890': '新端口不能与当前端口相同',
          '7891': '该端口已用于其他本地监听服务，请选择其他端口',
          '9090': '该端口已用于其他本地监听服务，请选择其他端口',
        }.entries) {
          await tester.enterText(
            find.byKey(const ValueKey('desktop-proxy-port-input')),
            entry.key,
          );
          await tester.tap(
            find.byKey(const ValueKey('desktop-proxy-port-save')),
          );
          await tester.pumpAndSettle();

          expect(find.byType(DesktopProxyPortDialog), findsOneWidget);
          expect(find.text(entry.value), findsOneWidget);
          expect(result.isCompleted, isFalse);
          expect(tester.takeException(), isNull);
        }
        await tester.tap(
          find.byKey(const ValueKey('desktop-proxy-port-cancel')),
        );
        await tester.pumpAndSettle();
        expect(await result.future, isNull);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
      }
    },
  );

  for (final port in [1024, 49151]) {
    testWidgets(
      'saving valid boundary port $port returns it for the caller to retry',
      (tester) async {
        try {
          final result = await pumpDialog(
            tester,
            const DesktopProxyPortDialog(
              currentPort: 7890,
              reservedPorts: {9090},
            ),
          );
          expect(find.text('保存并重试'), findsOneWidget);
          await tester.enterText(
            find.byKey(const ValueKey('desktop-proxy-port-input')),
            '$port',
          );
          await tester.tap(
            find.byKey(const ValueKey('desktop-proxy-port-save')),
          );
          await tester.pumpAndSettle();

          expect(await result.future, port);
          expect(find.byType(DesktopProxyPortDialog), findsNothing);
          expect(tester.takeException(), isNull);
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
        }
      },
    );
  }

  testWidgets(
    'port dialog can be destroyed while editing without delayed callbacks',
    (tester) async {
      try {
        await pumpDialog(
          tester,
          const DesktopProxyPortDialog(currentPort: 7890, reservedPorts: {}),
        );
        await tester.enterText(
          find.byKey(const ValueKey('desktop-proxy-port-input')),
          '9000',
        );
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
      }
      await tester.pump(const Duration(seconds: 1));
      expect(tester.takeException(), isNull);
    },
  );
}

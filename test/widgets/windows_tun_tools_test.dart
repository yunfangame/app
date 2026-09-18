import 'dart:async';

import 'package:fl_clash/l10n/l10n.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/state.dart';
import 'package:fl_clash/widgets/windows_tun_tools.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final fail in [false, true]) {
    testWidgets(
      'tools show Chinese help and clear busy after repair, fail=$fail',
      (tester) async {
        final action = _ToolsSetup();
        final container = ProviderContainer(
          overrides: [setupActionProvider.overrideWith(() => action)],
        );
        addTearDown(container.dispose);
        globalState.container = container;
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: MaterialApp(
              locale: const Locale('zh', 'CN'),
              localizationsDelegates: const [
                AppLocalizations.delegate,
                GlobalMaterialLocalizations.delegate,
                GlobalWidgetsLocalizations.delegate,
                GlobalCupertinoLocalizations.delegate,
              ],
              supportedLocales: AppLocalizations.delegate.supportedLocales,
              home: const Scaffold(body: WindowsTunToolsButton()),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('windows-tun-tools')));
        await tester.pumpAndSettle();
        expect(find.text('虚拟网卡工具'), findsOneWidget);
        expect(find.text('导出日志'), findsOneWidget);
        await tester.tap(find.text('检测并修复服务'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        expect(action.calls, 1);
        expect(find.byType(CircularProgressIndicator), findsOneWidget);
        final button = tester.widget<IconButton>(
          find.byKey(const ValueKey('windows-tun-tools')),
        );
        expect(button.onPressed, isNull);
        if (fail) {
          action.completed.completeError(StateError('installation failed'));
        } else {
          action.completed.complete(false);
        }
        await tester.pumpAndSettle();
        expect(find.byType(CircularProgressIndicator), findsNothing);
        expect(
          tester
              .widget<IconButton>(
                find.byKey(const ValueKey('windows-tun-tools')),
              )
              .onPressed,
          isNotNull,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }
}

class _ToolsSetup extends SetupAction {
  int calls = 0;
  final completed = Completer<bool>();

  @override
  Future<bool> repairTunService() {
    calls++;
    return completed.future;
  }
}

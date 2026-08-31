import 'package:fl_clash/common/app_update.dart';
import 'package:fl_clash/widgets/app_update_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final release = AppUpdateRelease(
    packageKey: 'macos-arm64',
    version: '0.8.97',
    downloadUri: Uri.parse('https://house.example/fengwo.dmg'),
    releaseNotesHtml: '<h3>重要更新</h3><ul><li>修复校园网模式</li></ul>',
    title: '蜂窝加速器更新',
  );

  testWidgets('renders HTML notes and returns ignore-version decision', (
    tester,
  ) async {
    AppUpdateDecision? decision;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => FilledButton(
              onPressed: () async {
                decision = await showAppUpdateDialog(
                  context: context,
                  release: release,
                  currentVersion: '0.8.96',
                );
              },
              child: const Text('show'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('show'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('app-update-dialog')), findsOneWidget);
    expect(find.text('蜂窝加速器更新'), findsOneWidget);
    expect(find.text('重要更新'), findsOneWidget);
    expect(find.text('修复校园网模式'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('app-update-ignore')));
    await tester.pumpAndSettle();
    expect(decision, AppUpdateDecision.ignoreVersion);
  });

  testWidgets('supports updating later', (tester) async {
    AppUpdateDecision? decision;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                decision = await showAppUpdateDialog(
                  context: context,
                  release: release,
                  currentVersion: '0.8.96',
                );
              },
              child: const Text('show'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('show'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('app-update-later')));
    await tester.pumpAndSettle();
    expect(decision, AppUpdateDecision.later);
  });
}

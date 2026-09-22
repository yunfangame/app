import 'dart:async';

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/l10n/l10n.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/views/application_setting.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const desktop = TargetPlatformVariant({TargetPlatform.windows});

  testWidgets('startup defaults off and refreshes the actual system state', (
    tester,
  ) async {
    final action = _TestSystemAction();
    final container = await _pumpItem(tester, action);
    expect(container.read(appSettingProvider).autoLaunch, isFalse);
    expect(_switch(tester).value, isFalse);
    expect(action.refreshCalls, 1);
    expect(action.changes, isEmpty);
    expect(find.text('开机自启'), findsOneWidget);
    expect(find.byKey(const ValueKey('auto-launch-progress')), findsNothing);
  }, variant: desktop);

  testWidgets('startup switch reflects enabled system registration', (
    tester,
  ) async {
    final action = _TestSystemAction()..enabled = true;
    final container = await _pumpItem(tester, action);
    expect(container.read(appSettingProvider).autoLaunch, isTrue);
    expect(_switch(tester).value, isTrue);
    expect(action.changes, isEmpty);
  }, variant: desktop);

  testWidgets(
    'initial refresh keeps the previous value until read completes',
    (tester) async {
      final pending = Completer<void>();
      final action = _TestSystemAction()..refreshHandler = () => pending.future;
      final container = await _pumpItem(
        tester,
        action,
        initiallyEnabled: true,
        settle: false,
      );
      expect(_switch(tester).value, isTrue);
      expect(_switch(tester).onChanged, isNull);
      expect(find.text('正在读取系统启动设置…'), findsOneWidget);
      pending.complete();
      await tester.pumpAndSettle();
      expect(container.read(appSettingProvider).autoLaunch, isFalse);
      expect(_switch(tester).value, isFalse);
      expect(_switch(tester).onChanged, isNotNull);
    },
    variant: desktop,
  );

  testWidgets('startup waits for completion and ignores duplicate taps', (
    tester,
  ) async {
    final pending = Completer<void>();
    final action = _TestSystemAction()..changeHandler = (_) => pending.future;
    final container = await _pumpItem(tester, action);
    await tester.tap(find.byKey(const ValueKey('auto-launch-switch')));
    await tester.pump();
    expect(_switch(tester).onChanged, isNull);
    expect(_switch(tester).value, isFalse);
    expect(container.read(appSettingProvider).autoLaunch, isFalse);
    expect(find.text('正在应用启动设置…'), findsOneWidget);
    expect(find.byKey(const ValueKey('auto-launch-progress')), findsOneWidget);
    await tester.tap(find.text('开机自启'));
    await tester.pump();
    expect(action.changes, [true]);
    pending.complete();
    await tester.pumpAndSettle();
    expect(_switch(tester).value, isTrue);
    expect(_switch(tester).onChanged, isNotNull);
    expect(find.byKey(const ValueKey('auto-launch-progress')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('auto-launch-switch')));
    await tester.pumpAndSettle();
    expect(action.changes, [true, false]);
    expect(container.read(appSettingProvider).autoLaunch, isFalse);
  }, variant: desktop);

  testWidgets('startup failure retains state and allows another attempt', (
    tester,
  ) async {
    final action = _TestSystemAction()
      ..changeHandler = (_) async {
        throw const AutoLaunchException('verificationFailed');
      };
    final container = await _pumpItem(tester, action);
    await tester.tap(find.byKey(const ValueKey('auto-launch-switch')));
    await tester.pumpAndSettle();
    expect(container.read(appSettingProvider).autoLaunch, isFalse);
    expect(_switch(tester).value, isFalse);
    expect(_switch(tester).onChanged, isNotNull);
    expect(find.byKey(const ValueKey('auto-launch-progress')), findsNothing);
    expect(find.text('系统未确认设置生效，开机自启设置未更改，请重试。'), findsOneWidget);
    action.changeHandler = null;
    await tester.tap(find.byKey(const ValueKey('auto-launch-switch')));
    await tester.pumpAndSettle();
    expect(_switch(tester).value, isTrue);
    expect(find.byKey(const ValueKey('auto-launch-error')), findsNothing);
    expect(tester.takeException(), isNull);
  }, variant: desktop);

  testWidgets(
    'failed system read requires a successful retry before changes',
    (tester) async {
      final action = _TestSystemAction()
        ..refreshHandler = () async {
          throw const AutoLaunchException('readFailed');
        };
      await _pumpItem(tester, action, initiallyEnabled: true);
      expect(_switch(tester).value, isTrue);
      expect(_switch(tester).onChanged, isNull);
      expect(find.text('无法读取系统启动设置，请重试后再更改。'), findsOneWidget);
      action.refreshHandler = null;
      action.enabled = true;
      await tester.tap(find.byKey(const ValueKey('auto-launch-retry')));
      await tester.pumpAndSettle();
      expect(action.refreshCalls, 2);
      expect(_switch(tester).value, isTrue);
      expect(_switch(tester).onChanged, isNotNull);
      expect(action.changes, isEmpty);
      expect(find.byKey(const ValueKey('auto-launch-error')), findsNothing);
    },
    variant: desktop,
  );

  testWidgets(
    'pending startup write can finish after the view is disposed',
    (tester) async {
      final pending = Completer<void>();
      final action = _TestSystemAction()..changeHandler = (_) => pending.future;
      final container = await _pumpItem(tester, action);
      await tester.tap(find.byKey(const ValueKey('auto-launch-switch')));
      await tester.pump();
      await tester.pumpWidget(const SizedBox.shrink());
      pending.complete();
      await tester.pumpAndSettle();
      expect(container.read(appSettingProvider).autoLaunch, isTrue);
      expect(tester.takeException(), isNull);
    },
    variant: desktop,
  );

  testWidgets('pending system read can fail after the view is disposed', (
    tester,
  ) async {
    final pending = Completer<void>();
    final action = _TestSystemAction()..refreshHandler = () => pending.future;
    await _pumpItem(tester, action, settle: false);
    await tester.pumpWidget(const SizedBox.shrink());
    pending.completeError(const AutoLaunchException('readFailed'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  }, variant: desktop);

  testWidgets(
    'startup controls never read or change mobile system settings',
    (tester) async {
      final action = _TestSystemAction();
      await _pumpItem(tester, action);
      expect(find.byType(Switch), findsNothing);
      expect(action.refreshCalls, 0);
      expect(action.changes, isEmpty);
      expect(tester.takeException(), isNull);
    },
    variant: const TargetPlatformVariant({
      TargetPlatform.android,
      TargetPlatform.iOS,
    }),
  );
}

Switch _switch(WidgetTester tester) {
  return tester.widget<Switch>(
    find.byKey(const ValueKey('auto-launch-switch')),
  );
}

Future<ProviderContainer> _pumpItem(
  WidgetTester tester,
  _TestSystemAction action, {
  bool initiallyEnabled = false,
  bool settle = true,
}) async {
  final container = ProviderContainer(
    overrides: [systemActionProvider.overrideWith(() => action)],
  );
  container
      .read(appSettingProvider.notifier)
      .update((state) => state.copyWith(autoLaunch: initiallyEnabled));
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    container.dispose();
  });
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        locale: const Locale('zh', 'CN'),
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.delegate.supportedLocales,
        home: const Scaffold(body: AutoLaunchItem()),
      ),
    ),
  );
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
  }
  return container;
}

class _TestSystemAction extends SystemAction {
  Future<void> Function()? refreshHandler;
  Future<void> Function(bool)? changeHandler;
  int refreshCalls = 0;
  final changes = <bool>[];
  bool enabled = false;

  @override
  Future<void> refreshAutoLaunch() async {
    refreshCalls++;
    await refreshHandler?.call();
    if (!ref.mounted) return;
    ref
        .read(appSettingProvider.notifier)
        .update((state) => state.copyWith(autoLaunch: enabled));
  }

  @override
  Future<void> setAutoLaunch(bool value) async {
    changes.add(value);
    await changeHandler?.call(value);
    enabled = value;
    if (!ref.mounted) return;
    ref
        .read(appSettingProvider.notifier)
        .update((state) => state.copyWith(autoLaunch: value));
  }
}

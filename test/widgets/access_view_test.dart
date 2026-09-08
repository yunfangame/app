import 'dart:async';

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/l10n/l10n.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/state.dart';
import 'package:fl_clash/views/access.dart';
import 'package:fl_clash/widgets/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const _packages = [
  Package(
    packageName: 'com.example.browser',
    label: 'Browser',
    system: false,
    internet: true,
    lastUpdateTime: 1,
  ),
  Package(
    packageName: 'com.example.CHAT',
    label: 'Chat',
    system: false,
    internet: true,
    lastUpdateTime: 2,
  ),
  Package(
    packageName: 'com.example.system',
    label: 'System app',
    system: true,
    launchable: false,
    internet: true,
    lastUpdateTime: 3,
  ),
];

const _longNamePackage = Package(
  packageName:
      'com.example.enterprise.collaboration.application.with.a.very.long.package.identifier',
  label: '企业协作与即时通讯应用 Enterprise Collaboration Application',
  system: false,
  internet: true,
  lastUpdateTime: 1,
);

void main() {
  testWidgets(
    'default list keeps launchable preinstalled apps and hides services',
    (tester) async {
      const installed = [
        Package(
          packageName: 'com.android.chrome',
          label: 'Chrome',
          system: true,
          launchable: true,
          internet: true,
          lastUpdateTime: 1,
        ),
        Package(
          packageName: 'com.google.android.youtube',
          label: 'YouTube',
          system: true,
          launchable: true,
          internet: true,
          lastUpdateTime: 1,
        ),
        Package(
          packageName: 'com.google.android.configupdater',
          label: 'ConfigUpdater',
          system: true,
          launchable: false,
          internet: true,
          lastUpdateTime: 1,
        ),
      ];
      final harness = await _pumpAccess(
        tester,
        loadPackages: () async => installed,
      );
      expect(find.text('Chrome'), findsOneWidget);
      expect(find.text('YouTube'), findsOneWidget);
      expect(find.text('ConfigUpdater'), findsNothing);
      final showAll = find.byKey(const ValueKey('app-routing-show-all'));
      expect(tester.widget<FilterChip>(showAll).selected, isFalse);
      await tester.tap(showAll);
      await tester.pumpAndSettle();
      final serviceRow = find.byKey(
        const Key('com.google.android.configupdater'),
      );
      await _revealRoutingItem(tester, serviceRow);
      await tester.tap(serviceRow);
      await tester.pump();
      await tester.ensureVisible(showAll);
      await tester.pumpAndSettle();
      await tester.tap(showAll);
      await tester.pumpAndSettle();
      expect(find.text('ConfigUpdater'), findsNothing);
      expect(harness.container.read(accessControlStateProvider).rejectList, [
        'com.google.android.configupdater',
      ]);
      await tester.tap(find.byKey(const ValueKey('app-routing-save')));
      await tester.pumpAndSettle();
      expect(harness.action.calls.single.rejectList, [
        'com.google.android.configupdater',
      ]);
      expect(harness.action.calls.single.isFilterNonLaunchableApp, isTrue);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'application routing fits a phone and defaults to selected apps direct',
    (tester) async {
      final harness = await _pumpAccess(tester);
      final mode = tester.widget<ChoiceChip>(
        find.byKey(const ValueKey('app-routing-mode-rejectSelected')),
      );

      expect(mode.selected, isTrue);
      expect(
        harness.container.read(accessControlStateProvider).enable,
        isFalse,
      );
      expect(find.text('Browser'), findsOneWidget);
      expect(find.text('Chat'), findsOneWidget);
      expect(find.text('System app'), findsNothing);
      expect(find.byType(PackageIcon), findsNWidgets(2));
      expect(_saveButton(tester).onPressed, isNull);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'application search matches names and package identifiers ignoring case',
    (tester) async {
      await _pumpAccess(tester);
      await tester.tap(find.byKey(const ValueKey('app-routing-search')));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'BROWSER');
      await tester.pumpAndSettle();
      expect(find.text('Browser'), findsOneWidget);
      expect(find.text('Chat'), findsNothing);

      await tester.enterText(find.byType(TextField), ' COM.EXAMPLE.chat ');
      await tester.pumpAndSettle();
      expect(find.text('Chat'), findsOneWidget);
      expect(find.text('Browser'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'saving offline preserves hidden selections and both mode lists',
    (tester) async {
      final harness = await _pumpAccess(
        tester,
        props: const AccessControlProps(
          enable: true,
          acceptList: ['com.example.unlisted'],
          rejectList: ['com.example.system'],
        ),
      );
      final l10n = tester.element(find.byType(AccessView)).appLocalizations;
      expect(find.text('System app'), findsNothing);
      await tester.tap(find.byKey(const Key('com.example.browser')));
      await tester.pump();
      expect(find.text(l10n.save), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('app-routing-save')));
      await tester.pumpAndSettle();

      expect(harness.action.calls, hasLength(1));
      expect(harness.action.calls.single.rejectList, [
        'com.example.browser',
        'com.example.system',
      ]);
      expect(harness.action.calls.single.acceptList, ['com.example.unlisted']);
      expect(find.text(l10n.appRoutingSaved), findsOneWidget);
      expect(_saveButton(tester).onPressed, isNull);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('switching routing modes preserves independent selections', (
    tester,
  ) async {
    final harness = await _pumpAccess(
      tester,
      props: const AccessControlProps(
        enable: true,
        acceptList: ['com.example.CHAT'],
        rejectList: ['com.example.browser'],
      ),
    );
    final browser = find.byKey(const Key('com.example.browser'));
    final chat = find.byKey(const Key('com.example.CHAT'));
    expect(tester.widget<PackageListItem>(browser).value, isTrue);
    expect(tester.widget<PackageListItem>(chat).value, isFalse);

    await tester.tap(
      find.byKey(const ValueKey('app-routing-mode-acceptSelected')),
    );
    await tester.pumpAndSettle();
    expect(tester.widget<PackageListItem>(browser).value, isFalse);
    expect(tester.widget<PackageListItem>(chat).value, isTrue);

    await _revealRoutingItem(tester, browser);
    await tester.tap(browser);
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('app-routing-save')));
    await tester.pumpAndSettle();

    expect(harness.action.calls.single.acceptList, [
      'com.example.CHAT',
      'com.example.browser',
    ]);
    expect(harness.action.calls.single.rejectList, ['com.example.browser']);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'connected save requests reconnection without claiming it completed',
    (tester) async {
      final harness = await _pumpAccess(tester, running: true);
      final l10n = tester.element(find.byType(AccessView)).appLocalizations;
      expect(find.text(l10n.appRoutingReconnect), findsOneWidget);
      expect(find.text(l10n.appRoutingConnectionHint), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('app-routing-enable')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('app-routing-save')));
      await tester.pumpAndSettle();

      expect(harness.action.calls.single.enable, isTrue);
      expect(find.text(l10n.appRoutingReconnecting), findsOneWidget);
      expect(find.text(l10n.appRoutingSaved), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('failed save keeps edits and permits a successful retry', (
    tester,
  ) async {
    var attempts = 0;
    final harness = await _pumpAccess(
      tester,
      onApply: (_) async {
        if (++attempts == 1) throw StateError('save unavailable');
        return AccessControlApplyResult.saved;
      },
    );
    final l10n = tester.element(find.byType(AccessView)).appLocalizations;
    await tester.tap(find.byKey(const ValueKey('app-routing-enable')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('app-routing-save')));
    await tester.pumpAndSettle();

    expect(find.text(l10n.appRoutingSaveFailed), findsOneWidget);
    expect(harness.container.read(accessControlStateProvider).enable, isTrue);
    expect(
      harness.container.read(vpnSettingProvider).accessControlProps.enable,
      isFalse,
    );
    expect(_saveButton(tester).onPressed, isNotNull);

    await tester.tap(find.byKey(const ValueKey('app-routing-save')));
    await tester.pumpAndSettle();
    expect(harness.action.calls, hasLength(2));
    expect(find.text(l10n.appRoutingSaveFailed), findsNothing);
    expect(find.text(l10n.appRoutingSaved), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final stage in ['sync', 'restart']) {
    testWidgets(
      '$stage failure remains retryable after leaving and reopening routing',
      (tester) async {
        var attempts = 0;
        late _TestSetupAction action;
        final harness = await _pumpAccess(
          tester,
          running: true,
          onApply: (props) async {
            if (++attempts == 1) {
              action.savePendingReconnect(props);
              throw StateError('$stage unavailable');
            }
            action.reconnectPending = false;
            return AccessControlApplyResult.reconnectRequested;
          },
        );
        action = harness.action;
        final l10n = tester.element(find.byType(AccessView)).appLocalizations;
        await tester.tap(find.byKey(const ValueKey('app-routing-enable')));
        await tester.pump();
        await tester.tap(find.byKey(const ValueKey('app-routing-save')));
        await tester.pumpAndSettle();

        expect(find.text(l10n.appRoutingSaveFailed), findsOneWidget);
        expect(
          harness.container.read(vpnSettingProvider).accessControlProps,
          harness.container.read(accessControlStateProvider),
        );
        expect(action.hasPendingAccessControlReconnect, isTrue);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
        await tester.pumpWidget(_accessApp(harness.container));
        await tester.pumpAndSettle();

        expect(find.text(l10n.appRoutingSaveFailed), findsNothing);
        expect(
          harness.container.read(accessControlStateProvider).enable,
          isTrue,
        );
        expect(_saveButton(tester).onPressed, isNotNull);
        await tester.tap(find.byKey(const ValueKey('app-routing-save')));
        await tester.pumpAndSettle();

        expect(action.calls, hasLength(2));
        expect(action.hasPendingAccessControlReconnect, isFalse);
        expect(find.text(l10n.appRoutingReconnecting), findsOneWidget);
        expect(_saveButton(tester).onPressed, isNull);
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final scenario in [
    (
      name: 'phone search keyboard',
      size: const Size(390, 844),
      keyboard: 300.0,
    ),
    (name: 'landscape phone', size: const Size(844, 390), keyboard: 0.0),
  ]) {
    testWidgets('routing remains usable with ${scenario.name}', (tester) async {
      final harness = await _pumpAccess(
        tester,
        running: true,
        size: scenario.size,
        props: const AccessControlProps(enable: true),
      );
      final search = find.byKey(const ValueKey('app-routing-search'));
      await _revealRoutingItem(tester, search);
      await tester.tap(search);
      await tester.pumpAndSettle();
      tester.view.viewInsets = FakeViewPadding(bottom: scenario.keyboard);
      addTearDown(tester.view.resetViewInsets);
      await tester.enterText(find.byType(TextField), 'browser');
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      final browser = find.byKey(const Key('com.example.browser'));
      await _revealRoutingItem(tester, browser);
      await tester.tap(browser);
      await tester.pump();
      final save = find.byKey(const ValueKey('app-routing-save'));
      await _revealRoutingItem(tester, save);
      expect(save.hitTestable(), findsOneWidget);
      expect(_saveButton(tester).onPressed, isNotNull);
      await tester.tap(save);
      await tester.pumpAndSettle();

      expect(harness.action.calls.single.rejectList, ['com.example.browser']);
      expect(tester.takeException(), isNull);
    });
  }

  for (final scenario in [
    (
      name: 'dark theme with larger text',
      size: const Size(390, 844),
      brightness: Brightness.dark,
      textScale: 1.3,
    ),
    (
      name: 'small phone with large text',
      size: const Size(360, 740),
      brightness: Brightness.light,
      textScale: 1.6,
    ),
  ]) {
    testWidgets('routing supports ${scenario.name}', (tester) async {
      final harness = await _pumpAccess(
        tester,
        running: true,
        size: scenario.size,
        brightness: scenario.brightness,
        textScale: scenario.textScale,
        props: const AccessControlProps(enable: true),
        loadPackages: () async => [_longNamePackage],
      );
      final context = tester.element(find.byType(AccessView));
      expect(Theme.of(context).brightness, scenario.brightness);
      expect(
        MediaQuery.textScalerOf(context).scale(10),
        scenario.textScale * 10,
      );
      expect(tester.takeException(), isNull);

      final appRow = find.byKey(Key(_longNamePackage.packageName));
      await _revealRoutingItem(tester, appRow);
      for (final text in [
        _longNamePackage.label,
        _longNamePackage.packageName,
      ]) {
        final widget = tester.widget<Text>(find.text(text));
        expect(widget.maxLines, 1);
        expect(
          widget.overflow ?? widget.style?.overflow,
          TextOverflow.ellipsis,
        );
      }
      expect(appRow.hitTestable(), findsOneWidget);
      await tester.tap(appRow);
      await tester.pump();

      final save = find.byKey(const ValueKey('app-routing-save'));
      await _revealRoutingItem(tester, save);
      expect(save.hitTestable(), findsOneWidget);
      expect(_saveButton(tester).onPressed, isNotNull);
      await tester.tap(save);
      await tester.pumpAndSettle();

      expect(harness.action.calls.single.rejectList, [
        _longNamePackage.packageName,
      ]);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('save ignores repeated taps and can finish after page disposal', (
    tester,
  ) async {
    final pending = Completer<AccessControlApplyResult>();
    final harness = await _pumpAccess(tester, onApply: (_) => pending.future);
    await tester.tap(find.byKey(const ValueKey('app-routing-enable')));
    await tester.pump();
    final onPressed = _saveButton(tester).onPressed!;
    onPressed();
    onPressed();
    await tester.pump();

    expect(harness.action.calls, hasLength(1));
    expect(_saveButton(tester).onPressed, isNull);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    pending.complete(AccessControlApplyResult.saved);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('package loading failure can retry and late completion is safe', (
    tester,
  ) async {
    var attempts = 0;
    final pending = Completer<List<Package>>();
    final harness = await _pumpAccess(
      tester,
      loadPackages: () async {
        if (++attempts == 1) throw StateError('packages unavailable');
        return pending.future;
      },
    );
    final l10n = tester.element(find.byType(AccessView)).appLocalizations;
    expect(find.text(l10n.appRoutingLoadFailed), findsOneWidget);
    await tester.tap(find.text(l10n.retry));
    await tester.pump();
    expect(attempts, 2);

    await tester.pumpWidget(const SizedBox.shrink());
    pending.complete(_packages);
    await tester.pumpAndSettle();
    expect(harness.action.calls, isEmpty);
    expect(tester.takeException(), isNull);
  });
}

FilledButton _saveButton(WidgetTester tester) {
  return tester.widget<FilledButton>(
    find.byKey(const ValueKey('app-routing-save')),
  );
}

Future<void> _revealRoutingItem(WidgetTester tester, Finder finder) async {
  await tester.scrollUntilVisible(
    finder,
    120,
    scrollable: find.descendant(
      of: find.byKey(const ValueKey('app-routing-scroll')),
      matching: find.byType(Scrollable),
    ),
  );
  await tester.pumpAndSettle();
}

Future<({ProviderContainer container, _TestSetupAction action})> _pumpAccess(
  WidgetTester tester, {
  AccessControlProps props = const AccessControlProps(),
  bool running = false,
  Size size = const Size(390, 844),
  Brightness brightness = Brightness.light,
  double textScale = 1,
  Future<AccessControlApplyResult> Function(AccessControlProps)? onApply,
  Future<List<Package>> Function()? loadPackages,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final action = _TestSetupAction(onApply);
  final container = ProviderContainer(
    overrides: [
      currentProfileProvider.overrideWithValue(null),
      isStartProvider.overrideWithValue(running),
      setupActionProvider.overrideWith(() => action),
      systemActionProvider.overrideWith(
        () => _TestSystemAction(loadPackages ?? () async => _packages),
      ),
    ],
  );
  addTearDown(container.dispose);
  globalState.container = container;
  final configSubscription = container.listen(configProvider, (_, _) {});
  addTearDown(configSubscription.close);
  container.read(viewSizeProvider.notifier).value = size;
  container
      .read(vpnSettingProvider.notifier)
      .update((state) => state.copyWith(accessControlProps: props));
  await tester.pumpWidget(
    _accessApp(container, brightness: brightness, textScale: textScale),
  );
  await tester.pumpAndSettle();
  return (container: container, action: action);
}

Widget _accessApp(
  ProviderContainer container, {
  Brightness brightness = Brightness.light,
  double textScale = 1,
}) {
  return UncontrolledProviderScope(
    container: container,
    child: MaterialApp(
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF006780),
          brightness: brightness,
        ),
      ),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      locale: const Locale('zh', 'CN'),
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.delegate.supportedLocales,
      home: const AccessView(),
    ),
  );
}

class _TestSetupAction extends SetupAction {
  final Future<AccessControlApplyResult> Function(AccessControlProps)? onApply;
  final calls = <AccessControlProps>[];
  bool reconnectPending = false;

  _TestSetupAction(this.onApply);

  @override
  void build() {}

  @override
  bool get hasPendingAccessControlReconnect => reconnectPending;

  void savePendingReconnect(AccessControlProps props) {
    reconnectPending = true;
    ref
        .read(vpnSettingProvider.notifier)
        .update((state) => state.copyWith(accessControlProps: props));
  }

  @override
  Future<AccessControlApplyResult> applyAccessControl(
    AccessControlProps props,
  ) async {
    calls.add(props);
    final result =
        await (onApply?.call(props) ??
            Future.value(
              ref.read(isStartProvider)
                  ? AccessControlApplyResult.reconnectRequested
                  : AccessControlApplyResult.saved,
            ));
    if (ref.mounted) {
      ref
          .read(vpnSettingProvider.notifier)
          .update((state) => state.copyWith(accessControlProps: props));
    }
    return result;
  }
}

class _TestSystemAction extends SystemAction {
  final Future<List<Package>> Function() loadPackages;

  _TestSystemAction(this.loadPackages);

  @override
  Future<List<Package>> getPackages() async {
    final packages = await loadPackages();
    if (ref.mounted) ref.read(packagesProvider.notifier).value = packages;
    return packages;
  }
}

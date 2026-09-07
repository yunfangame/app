import 'dart:async';

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/l10n/l10n.dart';
import 'package:fl_clash/manager/status_manager.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/state.dart';
import 'package:fl_clash/views/dashboard/widgets/global_mode_confirmation.dart';
import 'package:fl_clash/widgets/loading.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const _triggerKey = ValueKey('request-global-mode');
const _dialogKey = ValueKey('global-mode-confirmation-dialog');
const _progressKey = ValueKey('global-mode-selection-progress');
const _confirmKey = ValueKey('global-mode-confirm');
const _cancelKey = ValueKey('global-mode-cancel');
const _rememberKey = ValueKey('global-mode-dont-show-checkbox');
const _profile = Profile(
  id: 1,
  autoUpdateDuration: Duration.zero,
  currentGroupName: '规则节点组',
  selectedMap: {'GLOBAL': '原全局节点', '规则节点组': '原规则节点'},
);

void main() {
  testWidgets(
    'confirmation delegates selection without premature state writes',
    (tester) async {
      final pending = Completer<HongKongSelectionResult>();
      final fixture = await _pumpHarness(tester, select: () => pending.future);
      await _openConfirmation(tester);

      expect(fixture.action.requests, isEmpty);
      expect(fixture.action.manualCancellations, isEmpty);
      expect(find.byKey(_dialogKey), findsOneWidget);
      await tester.tap(find.byKey(_rememberKey));
      await tester.pump();
      expect(tester.widget<Checkbox>(find.byKey(_rememberKey)).value, isTrue);
      await tester.tap(find.byKey(_confirmKey));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(fixture.action.requests, [Mode.global]);
      expect(fixture.action.manualCancellations, [true]);
      expect(fixture.action.isCancelled?.call(), isFalse);
      expect(find.byKey(_progressKey), findsOneWidget);
      expect(find.byType(CommonCircleLoading), findsOneWidget);
      expect(fixture.container.read(patchClashConfigProvider).mode, Mode.rule);
      expect(fixture.container.read(currentProfileProvider), _profile);
      expect(
        fixture.container.read(appSettingProvider).skipGlobalModeConfirmation,
        isTrue,
      );

      await tester.tapAt(const Offset(5, 5));
      await tester.binding.handlePopRoute();
      await tester.pump();
      expect(find.byKey(_progressKey), findsOneWidget);
      expect(fixture.action.requests, [Mode.global]);

      pending.complete(HongKongSelectionResult.selected);
      await tester.pumpAndSettle();
      expect(find.byKey(_progressKey), findsNothing);
      expect(find.byType(CommonCircleLoading), findsNothing);
      expect(fixture.container.read(patchClashConfigProvider).mode, Mode.rule);
      expect(fixture.container.read(currentProfileProvider), _profile);
      expect(tester.takeException(), isNull);
    },
  );

  for (final closeKey in [
    _cancelKey,
    const ValueKey('global-mode-dialog-close'),
  ]) {
    testWidgets(
      'cancel through $closeKey keeps selection and preference intact',
      (tester) async {
        final fixture = await _pumpHarness(tester);
        await _openConfirmation(tester);
        await tester.tap(find.byKey(_rememberKey));
        await tester.tap(find.byKey(closeKey));
        await tester.pumpAndSettle();

        expect(fixture.action.requests, isEmpty);
        expect(find.byKey(_dialogKey), findsNothing);
        expect(find.byKey(_progressKey), findsNothing);
        expect(
          fixture.container.read(patchClashConfigProvider).mode,
          Mode.rule,
        );
        expect(fixture.container.read(currentProfileProvider), _profile);
        expect(
          fixture.container.read(appSettingProvider).skipGlobalModeConfirmation,
          isFalse,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('remembered preference skips confirmation but still selects', (
    tester,
  ) async {
    final pending = Completer<HongKongSelectionResult>();
    final fixture = await _pumpHarness(
      tester,
      skipConfirmation: true,
      select: () => pending.future,
    );
    await tester.tap(find.byKey(_triggerKey));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byKey(_dialogKey), findsNothing);
    expect(find.byKey(_progressKey), findsOneWidget);
    expect(fixture.action.requests, [Mode.global]);
    expect(fixture.container.read(patchClashConfigProvider).mode, Mode.rule);
    pending.complete(HongKongSelectionResult.selected);
    await tester.pumpAndSettle();
    expect(find.byKey(_progressKey), findsNothing);
    expect(tester.takeException(), isNull);
  });

  for (final result in [
    HongKongSelectionResult.unavailable,
    HongKongSelectionResult.failed,
    HongKongSelectionResult.cancelled,
  ]) {
    testWidgets(
      '$result preserves selection and provides appropriate feedback',
      (tester) async {
        final fixture = await _pumpHarness(tester, select: () async => result);
        final l10n = tester.element(find.byKey(_triggerKey)).appLocalizations;
        await _openConfirmation(tester);
        await tester.tap(find.byKey(_confirmKey));
        await tester.pumpAndSettle();

        expect(fixture.action.requests, [Mode.global]);
        expect(find.byKey(_progressKey), findsNothing);
        expect(
          fixture.container.read(patchClashConfigProvider).mode,
          Mode.rule,
        );
        expect(fixture.container.read(currentProfileProvider), _profile);
        expect(
          find.text(l10n.hongKongNodesUnavailable),
          result == HongKongSelectionResult.unavailable
              ? findsOneWidget
              : findsNothing,
        );
        expect(
          find.text(l10n.hongKongSelectionFailed),
          result == HongKongSelectionResult.failed
              ? findsOneWidget
              : findsNothing,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('unexpected exceptions clear loading and show only safe text', (
    tester,
  ) async {
    const privateError = 'private-token-do-not-display';
    final fixture = await _pumpHarness(
      tester,
      select: () async => throw StateError(privateError),
    );
    final l10n = tester.element(find.byKey(_triggerKey)).appLocalizations;
    await _openConfirmation(tester);
    await tester.tap(find.byKey(_confirmKey));
    await tester.pumpAndSettle();

    expect(find.byKey(_progressKey), findsNothing);
    expect(find.text(l10n.hongKongSelectionFailed), findsOneWidget);
    expect(find.textContaining(privateError), findsNothing);
    expect(fixture.container.read(patchClashConfigProvider).mode, Mode.rule);
    expect(fixture.container.read(currentProfileProvider), _profile);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'disposing the requester cancels selection and clears its dialog',
    (tester) async {
      final pending = Completer<HongKongSelectionResult>();
      final fixture = await _pumpHarness(tester, select: () => pending.future);
      final l10n = tester.element(find.byKey(_triggerKey)).appLocalizations;
      await _openConfirmation(tester);
      await tester.tap(find.byKey(_confirmKey));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      fixture.showRequester.value = false;
      await tester.pump();

      expect(fixture.action.isCancelled?.call(), isTrue);
      pending.complete(HongKongSelectionResult.unavailable);
      await tester.pumpAndSettle();

      expect(find.byKey(_progressKey), findsNothing);
      expect(find.text(l10n.hongKongNodesUnavailable), findsNothing);
      expect(find.text(l10n.hongKongSelectionFailed), findsNothing);
      expect(fixture.container.read(patchClashConfigProvider).mode, Mode.rule);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('loading cleanup does not dismiss a newer route', (tester) async {
    final pending = Completer<HongKongSelectionResult>();
    await _pumpHarness(tester, select: () => pending.future);
    await _openConfirmation(tester);
    await tester.tap(find.byKey(_confirmKey));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    unawaited(
      showDialog<void>(
        context: tester.element(find.byKey(_progressKey)),
        builder: (_) => const AlertDialog(
          key: ValueKey('newer-route'),
          content: Text('A newer dialog'),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    pending.complete(HongKongSelectionResult.selected);
    await tester.pumpAndSettle();

    expect(find.byKey(_progressKey), findsNothing);
    expect(find.byKey(const ValueKey('newer-route')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('already-global mode does not ask or select again', (
    tester,
  ) async {
    final fixture = await _pumpHarness(tester, mode: Mode.global);
    await tester.tap(find.byKey(_triggerKey));
    await tester.pumpAndSettle();
    expect(fixture.action.requests, isEmpty);
    expect(find.byKey(_dialogKey), findsNothing);
    expect(find.byKey(_progressKey), findsNothing);
    expect(tester.takeException(), isNull);
  });

  for (final locale in [
    const Locale('en'),
    const Locale('zh', 'CN'),
    const Locale('ja'),
    const Locale('ru'),
  ]) {
    testWidgets('narrow $locale dialog keeps translated actions readable', (
      tester,
    ) async {
      final fixture = await _pumpHarness(
        tester,
        size: const Size(320, 568),
        locale: locale,
        textScale: 1.4,
      );
      final l10n = tester.element(find.byKey(_triggerKey)).appLocalizations;
      await _openConfirmation(tester);
      await tester.ensureVisible(find.byKey(_confirmKey));
      await tester.pumpAndSettle();

      final label = find.text(l10n.switchAndSelectHongKong);
      expect(label, findsOneWidget);
      expect(
        tester.renderObject<RenderParagraph>(label).didExceedMaxLines,
        isFalse,
      );
      expect(find.textContaining('DIRECT'), findsNothing);
      expect(tester.takeException(), isNull);

      await tester.ensureVisible(find.byKey(_cancelKey));
      await tester.tap(find.byKey(_cancelKey));
      await tester.pumpAndSettle();
      expect(fixture.action.requests, isEmpty);
      expect(tester.takeException(), isNull);
    });
  }
}

Future<void> _openConfirmation(WidgetTester tester) async {
  await tester.tap(find.byKey(_triggerKey));
  await tester.pumpAndSettle();
}

Future<_Fixture> _pumpHarness(
  WidgetTester tester, {
  Future<HongKongSelectionResult> Function()? select,
  bool skipConfirmation = false,
  Mode mode = Mode.rule,
  Size size = const Size(1000, 900),
  Locale locale = const Locale('en'),
  double textScale = 1,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final showRequester = ValueNotifier(true);
  final action = _RecordingProxiesAction(
    select ?? () async => HongKongSelectionResult.selected,
  );
  final container = ProviderContainer(
    overrides: [
      proxiesActionProvider.overrideWith(() => action),
      viewSizeProvider.overrideWithBuild((_, _) => size),
      currentProfileProvider.overrideWithValue(_profile),
      patchClashConfigProvider.overrideWithBuild(
        (_, _) => PatchClashConfig(mode: mode),
      ),
      appSettingProvider.overrideWithBuild(
        (_, _) => AppSettingProps(skipGlobalModeConfirmation: skipConfirmation),
      ),
    ],
  );
  globalState.container = container;
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox());
    showRequester.dispose();
    container.dispose();
  });
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        locale: locale,
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        ),
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.delegate.supportedLocales,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: StatusManager(
          child: Scaffold(
            body: Center(
              child: ValueListenableBuilder(
                valueListenable: showRequester,
                builder: (_, visible, _) =>
                    visible ? const _ModeSwitchButton() : const SizedBox(),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return _Fixture(container, action, showRequester);
}

class _Fixture {
  final ProviderContainer container;
  final _RecordingProxiesAction action;
  final ValueNotifier<bool> showRequester;

  const _Fixture(this.container, this.action, this.showRequester);
}

class _RecordingProxiesAction extends ProxiesAction {
  final Future<HongKongSelectionResult> Function() select;
  final requests = <Mode>[];
  final manualCancellations = <bool>[];
  bool Function()? isCancelled;

  _RecordingProxiesAction(this.select);

  @override
  void cancelHongKongSelection({bool manual = false}) {
    manualCancellations.add(manual);
    super.cancelHongKongSelection(manual: manual);
  }

  @override
  Future<HongKongSelectionResult> selectHongKongForMode(
    Mode mode, {
    bool Function()? isCancelled,
  }) {
    requests.add(mode);
    this.isCancelled = isCancelled;
    return select();
  }
}

class _ModeSwitchButton extends ConsumerWidget {
  const _ModeSwitchButton();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final skipConfirmation = ref.watch(
      appSettingProvider.select(
        (settings) => settings.skipGlobalModeConfirmation,
      ),
    );
    return FilledButton(
      key: _triggerKey,
      onPressed: () => requestGlobalModeSwitch(
        context,
        ref,
        skipConfirmation: skipConfirmation,
      ),
      child: const Text('Global'),
    );
  }
}

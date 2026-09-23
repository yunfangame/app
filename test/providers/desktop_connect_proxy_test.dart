import 'package:fl_clash/providers/providers.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:riverpod/riverpod.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final initialized in [false, true]) {
    test(
      'desktop user start enables system proxy before connecting with initialized=$initialized',
      () {
        final rig = _createRig(
          desktop: true,
          initialized: initialized,
          systemProxy: false,
        );
        addTearDown(rig.container.dispose);

        rig.container.read(commonActionProvider.notifier).toggleRunning();

        expect(rig.container.read(networkSettingProvider).systemProxy, isTrue);
        expect(rig.setup.requests, [
          (running: true, initialize: !initialized, systemProxyAtRequest: true),
        ]);
      },
    );
  }

  for (final scenario in [
    (name: 'stop connected client', started: true, pending: false),
    (name: 'cancel connection', started: false, pending: true),
    (name: 'cancel pending connected client', started: true, pending: true),
  ]) {
    for (final enabled in [false, true]) {
      test('desktop ${scenario.name} keeps system proxy=$enabled', () {
        final rig = _createRig(
          desktop: true,
          initialized: false,
          started: scenario.started,
          pending: scenario.pending,
          systemProxy: enabled,
        );
        addTearDown(rig.container.dispose);
        final previous = rig.container.read(networkSettingProvider);

        rig.container.read(commonActionProvider.notifier).toggleRunning();

        expect(rig.container.read(networkSettingProvider), previous);
        expect(rig.setup.requests, [
          (running: false, initialize: false, systemProxyAtRequest: enabled),
        ]);
      });
    }
  }

  for (final enabled in [false, true]) {
    test('mobile user start preserves system proxy=$enabled', () {
      final rig = _createRig(
        desktop: false,
        initialized: true,
        systemProxy: enabled,
      );
      addTearDown(rig.container.dispose);
      final previous = rig.container.read(networkSettingProvider);

      rig.container.read(commonActionProvider.notifier).toggleRunning();

      expect(rig.container.read(networkSettingProvider), previous);
      expect(rig.setup.requests, [
        (running: true, initialize: false, systemProxyAtRequest: enabled),
      ]);
    });
  }
}

({ProviderContainer container, _RecordingSetup setup}) _createRig({
  required bool desktop,
  required bool initialized,
  required bool systemProxy,
  bool started = false,
  bool pending = false,
}) {
  final container = ProviderContainer(
    overrides: [
      initProvider.overrideWithBuild((_, _) => initialized),
      isStartProvider.overrideWithValue(started),
      connectionPendingProvider.overrideWithBuild((_, _) => pending),
      commonActionProvider.overrideWith(() => _QuietCommon(desktop)),
      setupActionProvider.overrideWith(_RecordingSetup.new),
    ],
  );
  container
      .read(networkSettingProvider.notifier)
      .update((state) => state.copyWith(systemProxy: systemProxy));
  return (
    container: container,
    setup: container.read(setupActionProvider.notifier) as _RecordingSetup,
  );
}

class _QuietCommon extends CommonAction {
  final bool desktop;

  _QuietCommon(this.desktop);

  @override
  bool get enablesSystemProxyOnConnect => desktop;

  @override
  Future<void> updateTraffic() async {}
}

class _RecordingSetup extends SetupAction {
  final requests =
      <({bool running, bool initialize, bool systemProxyAtRequest})>[];

  @override
  Future<void> setRunning(
    bool running, {
    bool initialize = false,
    bool propagateErrors = false,
  }) async {
    requests.add((
      running: running,
      initialize: initialize,
      systemProxyAtRequest: ref.read(networkSettingProvider).systemProxy,
    ));
  }
}

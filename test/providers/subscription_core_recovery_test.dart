import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/core/desktop/model.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/action.dart';
import 'package:fl_clash/providers/app.dart';
import 'package:fl_clash/providers/config.dart';
import 'package:fl_clash/providers/database.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:riverpod/riverpod.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;

  setUpAll(() async {
    directory = await Directory.systemTemp.createTemp('subscription_core_test');
    PathProviderPlatform.instance = _TestPathProvider(directory.path);
  });

  tearDownAll(() async {
    await commonPrint.flushDiagnosticEvents();
    await directory.delete(recursive: true);
  });

  for (final useBytes in [false, true]) {
    test(
      'recovers stopped Core before ${useBytes ? 'V2' : 'V1'} validation',
      () async {
        final harness = _Harness();
        addTearDown(harness.container.dispose);

        final profile = await harness.sync(useBytes: useBytes);

        expect(harness.events, ['start', 'init', 'validate', 'apply']);
        expect(harness.container.read(profilesProvider), [profile]);
        expect(harness.container.read(currentProfileIdProvider), profile.id);
        expect(
          harness.container.read(coreStatusProvider),
          CoreStatus.connected,
        );
        expect(harness.container.read(runTimeProvider), isNull);
      },
    );
  }
}

class _Harness {
  _Harness() {
    core = _TestCoreAction(events);
    container = ProviderContainer(
      overrides: [
        currentProfileIdProvider.overrideWithBuild((_, _) => null),
        profilesProvider.overrideWith(_MemoryProfiles.new),
        coreActionProvider.overrideWith(() => core),
        setupActionProvider.overrideWith(() => _TestSetupAction(events)),
      ],
    );
  }

  final events = <String>[];
  late final _TestCoreAction core;
  late final ProviderContainer container;
  bool current = true;

  Future<Profile> sync({required bool useBytes}) {
    final action = container.read(profilesActionProvider.notifier);
    Future<Profile> validate(Profile profile) async {
      events.add('validate');
      if (!core.initialized) {
        throw TimeoutException('Core method validateConfig timed out');
      }
      return profile.copyWith(lastUpdateDate: DateTime.now());
    }

    return useBytes
        ? action.syncSubscriptionProfileBytes(
            Uint8List.fromList([1, 2, 3]),
            sourceId: 'fengwo-v2://test-key/test-token',
            isCurrent: () => current,
            loader: (profile, _) => validate(profile),
          )
        : action.syncSubscriptionProfile(
            'https://api.example/s/test-token',
            isCurrent: () => current,
            loader: validate,
          );
  }
}

class _TestCoreAction extends CoreAction {
  _TestCoreAction(this.events);

  final List<String> events;
  bool initialized = false;

  @override
  Future<CoreLifecycleResult> startLifecycle() async {
    events.add('start');
    return const CoreLifecycleResult(
      revision: 1,
      outcome: CoreLifecycleOutcome.applied,
    );
  }

  @override
  Future<bool> initializeCoreForSubscription() async {
    events.add('init');
    initialized = true;
    return true;
  }
}

class _TestSetupAction extends SetupAction {
  _TestSetupAction(this.events);

  final List<String> events;

  @override
  Future<void> applyProfile({
    bool silence = false,
    bool force = false,
    Future<void> Function()? preloadInvoke,
    bool Function()? isCurrent,
    bool propagateErrors = false,
    Profile? profileOverride,
  }) async {
    events.add('apply');
  }
}

class _MemoryProfiles extends Profiles {
  @override
  List<Profile> build() => [];

  @override
  Future<void> putDurable(Profile profile) async {
    state = [...state.where((value) => value.id != profile.id), profile];
  }

  @override
  Future<void> setAllDurable(List<Profile> profiles) async {
    state = List.of(profiles);
  }
}

class _TestPathProvider extends PathProviderPlatform {
  _TestPathProvider(this.root);

  final String root;

  @override
  Future<String?> getTemporaryPath() async => root;

  @override
  Future<String?> getApplicationSupportPath() async => root;

  @override
  Future<String?> getApplicationCachePath() async => root;
}

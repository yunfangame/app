import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/common/login_routing_coordinator.dart';
import 'package:fl_clash/core/desktop/model.dart';
import 'package:fl_clash/database/database.dart' show database;
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/action.dart';
import 'package:fl_clash/providers/app.dart';
import 'package:fl_clash/providers/config.dart';
import 'package:fl_clash/providers/database.dart';
import 'package:fl_clash/providers/state.dart';
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
    await database.close();
    await commonPrint.flushDiagnosticEvents();
    await directory.delete(recursive: true);
  });

  setUp(() async {
    await database.profilesDao.setAll([]);
  });

  for (final useBytes in [false, true]) {
    test(
      'recovers Core and returns the committed ${useBytes ? 'V2' : 'V1'} profile',
      () async {
        final harness = _Harness();
        addTearDown(harness.container.dispose);
        final persistedAt = DateTime(2026, 10, 4, 12, 34, 56);
        final committedProfile = Completer<Profile>();
        final subscription = harness.container.listen(currentProfileProvider, (
          _,
          profile,
        ) {
          if (!committedProfile.isCompleted &&
              profile?.lastUpdateDate == persistedAt) {
            committedProfile.complete(profile);
          }
        }, fireImmediately: true);
        addTearDown(subscription.close);
        await harness.container.read(profilesStreamProvider.future);

        final profile = await harness.sync(useBytes: useBytes);
        final immediatelyCurrent = harness.container.read(
          currentProfileProvider,
        );
        expect(profile, immediatelyCurrent);
        expect(loginRoutingProfileMatches(profile, immediatelyCurrent), isTrue);
        final current = await committedProfile.future;
        final persisted = (await database.profilesDao.query().get()).single;

        expect(harness.events, ['start', 'init', 'validate', 'apply']);
        expect(harness.validatedProfile!.lastUpdateDate!.millisecond, 123);
        expect(harness.validatedProfile!.lastUpdateDate!.microsecond, 456);
        expect(profile.lastUpdateDate, persistedAt);
        expect(profile, persisted);
        expect(profile, current);
        expect(loginRoutingProfileMatches(profile, current), isTrue);
        expect(
          loginRoutingProfileMatches(harness.validatedProfile, current),
          isFalse,
        );
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

  test('routing still rejects distinct content revisions in one second', () {
    final original = Profile.normal().copyWith(
      lastUpdateDate: DateTime(2026, 10, 4, 12, 34, 56, 100),
    );
    final refreshed = original.copyWith(
      lastUpdateDate: DateTime(2026, 10, 4, 12, 34, 56, 900),
    );

    expect(loginRoutingProfileMatches(original, refreshed), isFalse);
  });
}

class _Harness {
  _Harness() {
    core = _TestCoreAction(events);
    container = ProviderContainer(
      overrides: [
        currentProfileIdProvider.overrideWithBuild((_, _) => null),
        coreActionProvider.overrideWith(() => core),
        setupActionProvider.overrideWith(() => _TestSetupAction(events)),
      ],
    );
  }

  final events = <String>[];
  late final _TestCoreAction core;
  late final ProviderContainer container;
  bool current = true;
  Profile? validatedProfile;

  Future<Profile> sync({required bool useBytes}) {
    final action = container.read(profilesActionProvider.notifier);
    Future<Profile> validate(Profile profile) async {
      events.add('validate');
      if (!core.initialized) {
        throw TimeoutException('Core method validateConfig timed out');
      }
      return validatedProfile = profile.copyWith(
        lastUpdateDate: DateTime(2026, 10, 4, 12, 34, 56, 123, 456),
        currentGroupName: 'Proxy',
        selectedMap: const {'Proxy': 'Hong Kong 1'},
      );
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

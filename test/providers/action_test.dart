import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:fl_clash/core/desktop/model.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/action.dart';
import 'package:fl_clash/providers/app.dart';
import 'package:fl_clash/providers/config.dart';
import 'package:fl_clash/providers/database.dart';
import 'package:fl_clash/providers/state.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:riverpod/riverpod.dart';

void main() {
  group('ProfilesAction', () {
    test('keeps edited profile data when remote update fails', () async {
      final original = Profile.normal(label: 'old label', url: 'bad-url');
      final edited = original.copyWith(
        label: 'new label',
        url: 'still-bad-url',
      );
      final container = ProviderContainer(
        overrides: [
          currentProfileIdProvider.overrideWithBuild((_, _) => null),
          profilesProvider.overrideWith(() => _TestProfiles([original])),
        ],
      );
      addTearDown(container.dispose);

      expect(
        container.read(profilesProvider).getProfile(original.id),
        original,
      );

      await expectLater(
        container.read(profilesActionProvider.notifier).updateProfile(edited),
        throwsA(anything),
      );

      final profile = container.read(profilesProvider).getProfile(original.id);
      expect(profile?.label, edited.label);
      expect(profile?.url, edited.url);
    });

    test('updates selection, inserts first profile, and reorders profiles', () {
      final first = Profile.normal(label: 'First');
      final second = Profile.normal(label: 'Second');
      final container = ProviderContainer(
        overrides: [
          currentProfileIdProvider.overrideWithBuild((_, _) => first.id),
          profilesProvider.overrideWith(() => _TestProfiles([first])),
        ],
      );
      addTearDown(container.dispose);
      final action = container.read(profilesActionProvider.notifier);

      action.updateCurrentSelectedMap('Group', 'Proxy');
      final updatedFirst = container.read(profilesProvider).single;
      expect(updatedFirst.selectedMap['Group'], 'Proxy');

      action.updateCurrentSelectedMap('Group', 'Proxy');
      expect(container.read(profilesProvider), hasLength(1));

      container.read(currentProfileIdProvider.notifier).value = null;
      action.putProfile(second);
      expect(container.read(currentProfileIdProvider), second.id);
      expect(container.read(profilesProvider), [updatedFirst, second]);

      action.reorder([second, updatedFirst]);
      expect(container.read(profilesProvider), [second, updatedFirst]);
    });

    test(
      'skips profile updates that are disabled, fresh, or file-based',
      () async {
        final profiles = [
          Profile.normal(label: 'Disabled').copyWith(autoUpdate: false),
          Profile.normal(label: 'Fresh').copyWith(
            autoUpdate: true,
            lastUpdateDate: DateTime.now().add(const Duration(days: 1)),
          ),
          Profile.normal(label: 'File').copyWith(
            autoUpdate: true,
            lastUpdateDate: DateTime.now().subtract(const Duration(days: 1)),
          ),
        ];
        final container = ProviderContainer(
          overrides: [
            currentProfileIdProvider.overrideWithBuild((_, _) => null),
            profilesProvider.overrideWith(() => _TestProfiles(profiles)),
          ],
        );
        addTearDown(container.dispose);
        final action = container.read(profilesActionProvider.notifier);

        await action.autoUpdateProfiles();
        await action.updateProfiles();

        expect(container.read(profilesProvider), profiles);
      },
    );

    test('setProfileAndAutoApply stores a non-current profile', () {
      final current = Profile.normal(label: 'Current');
      final other = Profile.normal(label: 'Other');
      final container = ProviderContainer(
        overrides: [
          currentProfileIdProvider.overrideWithBuild((_, _) => current.id),
          profilesProvider.overrideWith(() => _TestProfiles([current])),
        ],
      );
      addTearDown(container.dispose);

      container
          .read(profilesActionProvider.notifier)
          .setProfileAndAutoApply(other);

      expect(container.read(profilesProvider), [current, other]);
      expect(container.read(currentProfileIdProvider), current.id);
    });

    test('imports a new subscription, selects it, and applies it', () async {
      const url = 'https://subscribe.example.com/client/new-token';
      late _TestSetupAction setupAction;
      Profile? loadedProfile;
      final container = ProviderContainer(
        overrides: [
          currentProfileIdProvider.overrideWithBuild((_, _) => null),
          profilesProvider.overrideWith(() => _TestProfiles([])),
          setupActionProvider.overrideWith(() {
            setupAction = _TestSetupAction();
            return setupAction;
          }),
        ],
      );
      addTearDown(container.dispose);

      final imported = await container
          .read(profilesActionProvider.notifier)
          .syncSubscriptionProfile(
            url,
            label: '蜂窝订阅',
            loader: (profile) async {
              loadedProfile = profile;
              return profile.copyWith(label: '远程订阅');
            },
          );

      expect(loadedProfile?.url, url);
      expect(loadedProfile?.label, '蜂窝订阅');
      expect(imported.label, '远程订阅');
      expect(container.read(profilesProvider), [imported]);
      expect(container.read(currentProfileIdProvider), imported.id);
      expect(setupAction.applyProfileCount, 1);
    });

    test(
      'updates an existing subscription without adding a duplicate',
      () async {
        const url = 'https://subscribe.example.com/client/existing-token';
        final existing = Profile.normal(label: '旧订阅', url: url);
        final other = Profile.normal(label: '其他配置', url: 'https://other.test');
        late _TestSetupAction setupAction;
        var loaderCalls = 0;
        final container = ProviderContainer(
          overrides: [
            currentProfileIdProvider.overrideWithBuild((_, _) => other.id),
            profilesProvider.overrideWith(
              () => _TestProfiles([other, existing]),
            ),
            setupActionProvider.overrideWith(() {
              setupAction = _TestSetupAction();
              return setupAction;
            }),
          ],
        );
        addTearDown(container.dispose);

        final updated = await container
            .read(profilesActionProvider.notifier)
            .syncSubscriptionProfile(
              url,
              label: '不应覆盖已有名称',
              loader: (profile) async {
                loaderCalls++;
                expect(profile.id, existing.id);
                return profile.copyWith(label: '已刷新订阅');
              },
            );

        final profiles = container.read(profilesProvider);
        expect(loaderCalls, 1);
        expect(updated.id, existing.id);
        expect(updated.label, '已刷新订阅');
        expect(profiles, hasLength(2));
        expect(profiles.where((profile) => profile.url == url), [updated]);
        expect(container.read(currentProfileIdProvider), existing.id);
        expect(setupAction.applyProfileCount, 1);
      },
    );

    test(
      'replaces the previous account subscription after applying the new one',
      () async {
        const oldUrl = 'https://subscribe.example.com/client/account-a';
        const newUrl = 'https://subscribe.example.com/client/account-b';
        final oldProfile = Profile.normal(label: 'Account A', url: oldUrl);
        final manualProfile = Profile.normal(
          label: 'Manual',
          url: 'https://manual.example.com/config',
        );
        late _TestSetupAction setupAction;
        final clearedEffects = <int>[];
        final container = ProviderContainer(
          overrides: [
            currentProfileIdProvider.overrideWithBuild((_, _) => oldProfile.id),
            profilesProvider.overrideWith(
              () => _TestProfiles([oldProfile, manualProfile]),
            ),
            setupActionProvider.overrideWith(() {
              setupAction = _TestSetupAction();
              return setupAction;
            }),
          ],
        );
        addTearDown(container.dispose);

        final imported = await container
            .read(profilesActionProvider.notifier)
            .syncSubscriptionProfile(
              newUrl,
              replacingUrl: oldUrl,
              loader: (profile) async => profile.copyWith(label: 'Account B'),
              effectClearer: (profileId) async => clearedEffects.add(profileId),
            );

        expect(container.read(profilesProvider), [manualProfile, imported]);
        expect(container.read(currentProfileIdProvider), imported.id);
        expect(setupAction.applyProfileCount, 1);
        expect(setupAction.setRunningCount, 0);
        expect(clearedEffects, [oldProfile.id]);
      },
    );

    test('replaces a legacy URL with a local V2 source identifier', () async {
      const oldUrl = 'https://subscribe.example.com/client/account-a';
      const sourceId = 'fengwo-v2://test-key/account-hash';
      final oldProfile = Profile.normal(label: 'Account A', url: oldUrl);
      late _TestSetupAction setupAction;
      Profile? loadedProfile;
      Uint8List? loadedBytes;
      final container = ProviderContainer(
        overrides: [
          currentProfileIdProvider.overrideWithBuild((_, _) => oldProfile.id),
          profilesProvider.overrideWith(() => _TestProfiles([oldProfile])),
          setupActionProvider.overrideWith(() {
            setupAction = _TestSetupAction();
            return setupAction;
          }),
        ],
      );
      addTearDown(container.dispose);
      final bytes = Uint8List.fromList(utf8.encode('proxies: []'));

      final imported = await container
          .read(profilesActionProvider.notifier)
          .syncSubscriptionProfileBytes(
            bytes,
            sourceId: sourceId,
            replacingUrl: oldUrl,
            loader: (profile, content) async {
              loadedProfile = profile;
              loadedBytes = content;
              return profile.copyWith(label: 'V2 Account');
            },
          );

      expect(loadedProfile?.id, oldProfile.id);
      expect(loadedProfile?.url, sourceId);
      expect(loadedBytes, bytes);
      expect(container.read(profilesProvider), [imported]);
      expect(container.read(currentProfileIdProvider), oldProfile.id);
      expect(setupAction.applyProfileCount, 1);
    });

    test('V2 migration removes stale XBoard profiles after applying', () async {
      const sourceId = 'fengwo-v2://test-key/account-hash';
      final staleLegacy = Profile.normal(
        label: 'Stale account',
        url: 'https://api.example.com/sakula/cddfa43b5a09bdd07b05d85955a7cf0f',
      );
      final manualProfile = Profile.normal(
        label: 'Manual',
        url: 'https://manual.example.com/config',
      );
      late _TestSetupAction setupAction;
      final clearedEffects = <int>[];
      final container = ProviderContainer(
        overrides: [
          currentProfileIdProvider.overrideWithBuild((_, _) => staleLegacy.id),
          profilesProvider.overrideWith(
            () => _TestProfiles([staleLegacy, manualProfile]),
          ),
          setupActionProvider.overrideWith(() {
            setupAction = _TestSetupAction();
            return setupAction;
          }),
        ],
      );
      addTearDown(container.dispose);

      final imported = await container
          .read(profilesActionProvider.notifier)
          .syncSubscriptionProfileBytes(
            Uint8List.fromList(utf8.encode('proxies: []')),
            sourceId: sourceId,
            removeLegacyXboardProfiles: true,
            loader: (profile, _) async => profile.copyWith(label: 'V2 Account'),
            effectClearer: (profileId) async => clearedEffects.add(profileId),
          );

      expect(container.read(profilesProvider), [manualProfile, imported]);
      expect(container.read(currentProfileIdProvider), imported.id);
      expect(setupAction.applyProfileCount, 1);
      expect(clearedEffects, [staleLegacy.id]);
    });

    test('failed V2 migration preserves legacy XBoard profiles', () async {
      final staleLegacy = Profile.normal(
        label: 'Stale account',
        url: 'https://api.example.com/sakula/cddfa43b5a09bdd07b05d85955a7cf0f',
      );
      late _TestSetupAction setupAction;
      final clearedEffects = <int>[];
      final container = ProviderContainer(
        overrides: [
          currentProfileIdProvider.overrideWithBuild((_, _) => staleLegacy.id),
          profilesProvider.overrideWith(() => _TestProfiles([staleLegacy])),
          setupActionProvider.overrideWith(() {
            setupAction = _TestSetupAction();
            return setupAction;
          }),
        ],
      );
      addTearDown(container.dispose);
      container.read(setupActionProvider);

      await expectLater(
        container
            .read(profilesActionProvider.notifier)
            .syncSubscriptionProfileBytes(
              Uint8List.fromList(utf8.encode('proxies: []')),
              sourceId: 'fengwo-v2://test-key/account-hash',
              removeLegacyXboardProfiles: true,
              loader: (_, _) async => throw StateError('download failed'),
              effectClearer: (profileId) async => clearedEffects.add(profileId),
            ),
        throwsA(isA<StateError>()),
      );

      expect(container.read(profilesProvider), [staleLegacy]);
      expect(container.read(currentProfileIdProvider), staleLegacy.id);
      expect(setupAction.applyProfileCount, 0);
      expect(clearedEffects, isEmpty);
    });

    test(
      'removing the signed-out account clears its active nodes only',
      () async {
        const accountUrl = 'https://subscribe.example.com/client/account-a';
        final accountProfile = Profile.normal(
          label: 'Account A',
          url: accountUrl,
        );
        final manualProfile = Profile.normal(
          label: 'Manual',
          url: 'https://manual.example.com/config',
        );
        late _TestSetupAction setupAction;
        final clearedEffects = <int>[];
        final container = ProviderContainer(
          overrides: [
            currentProfileIdProvider.overrideWithBuild(
              (_, _) => accountProfile.id,
            ),
            profilesProvider.overrideWith(
              () => _TestProfiles([accountProfile, manualProfile]),
            ),
            setupActionProvider.overrideWith(() {
              setupAction = _TestSetupAction();
              return setupAction;
            }),
          ],
        );
        addTearDown(container.dispose);

        await container
            .read(profilesActionProvider.notifier)
            .removeSubscriptionProfile(
              accountUrl,
              effectClearer: (profileId) async => clearedEffects.add(profileId),
            );

        expect(container.read(profilesProvider), [manualProfile]);
        expect(container.read(currentProfileIdProvider), isNull);
        expect(setupAction.setRunningCount, 1);
        expect(clearedEffects, [accountProfile.id]);
      },
    );

    test(
      'does not change profile state when subscription loading fails',
      () async {
        final original = Profile.normal(
          label: 'Current',
          url: 'https://subscribe.example.com/client/original-token',
        );
        late _TestSetupAction setupAction;
        final container = ProviderContainer(
          overrides: [
            currentProfileIdProvider.overrideWithBuild((_, _) => original.id),
            profilesProvider.overrideWith(() => _TestProfiles([original])),
            setupActionProvider.overrideWith(() {
              setupAction = _TestSetupAction();
              return setupAction;
            }),
          ],
        );
        addTearDown(container.dispose);
        container.read(setupActionProvider);

        await expectLater(
          container
              .read(profilesActionProvider.notifier)
              .syncSubscriptionProfile(
                'https://subscribe.example.com/client/failing-token',
                loader: (_) async => throw StateError('download failed'),
              ),
          throwsA(isA<StateError>()),
        );

        expect(container.read(profilesProvider), [original]);
        expect(container.read(currentProfileIdProvider), original.id);
        expect(setupAction.applyProfileCount, 0);
      },
    );

    test(
      'rejects invalid subscription URLs without loading or applying',
      () async {
        late _TestSetupAction setupAction;
        var loaderCalls = 0;
        final container = ProviderContainer(
          overrides: [
            currentProfileIdProvider.overrideWithBuild((_, _) => null),
            profilesProvider.overrideWith(() => _TestProfiles([])),
            setupActionProvider.overrideWith(() {
              setupAction = _TestSetupAction();
              return setupAction;
            }),
          ],
        );
        addTearDown(container.dispose);
        container.read(setupActionProvider);
        final action = container.read(profilesActionProvider.notifier);

        for (final url in [
          '',
          'client/token',
          'ftp://subscribe.example.com/client/token',
          'https:///client/token',
        ]) {
          await expectLater(
            action.syncSubscriptionProfile(
              url,
              loader: (profile) async {
                loaderCalls++;
                return profile;
              },
            ),
            throwsA(isA<ArgumentError>()),
          );
        }

        expect(loaderCalls, 0);
        expect(container.read(profilesProvider), isEmpty);
        expect(container.read(currentProfileIdProvider), isNull);
        expect(setupAction.applyProfileCount, 0);
      },
    );
  });

  group('GeoResourceAction', () {
    test('GeoResource has correct updatingKey', () {
      expect(GeoResource.MMDB.updatingKey, 'geo_resource_MMDB');
      expect(GeoResource.ASN.updatingKey, 'geo_resource_ASN');
      expect(GeoResource.GEOIP.updatingKey, 'geo_resource_GEOIP');
      expect(GeoResource.GEOSITE.updatingKey, 'geo_resource_GEOSITE');
    });

    test('IsUpdating provider works with geo resource key', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final key = GeoResource.MMDB.updatingKey;
      expect(container.read(isUpdatingProvider(key)), false);

      container.read(isUpdatingProvider(key).notifier).value = true;
      expect(container.read(isUpdatingProvider(key)), true);

      container.read(isUpdatingProvider(key).notifier).value = false;
      expect(container.read(isUpdatingProvider(key)), false);
    });

    test('updates valid resource URLs and rejects malformed URLs', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final action = container.read(geoResourceActionProvider.notifier);

      expect(
        () => action.updateGeoResourceUrl(GeoResource.MMDB, 'not-a-url'),
        throwsA('Invalid url'),
      );

      const url = 'https://example.com/Country.mmdb';
      action.updateGeoResourceUrl(GeoResource.MMDB, url);
      expect(
        container.read(patchClashConfigProvider).geoXUrl[GeoResource.MMDB],
        url,
      );
    });
  });

  group('CoreAction', () {
    test('applies the profile after restarting a stopped core', () async {
      final container = ProviderContainer(
        overrides: [
          coreActionProvider.overrideWith(_TestCoreAction.new),
          setupActionProvider.overrideWith(_TestSetupAction.new),
        ],
      );
      addTearDown(container.dispose);
      final coreAction =
          container.read(coreActionProvider.notifier) as _TestCoreAction;
      final setupAction =
          container.read(setupActionProvider.notifier) as _TestSetupAction;

      await coreAction.restartCore();

      expect(coreAction.lifecycleRestartCount, 1);
      expect(setupAction.setRunningCount, 0);
      expect(setupAction.applyProfileCount, 1);
    });

    test(
      'restores the started state after restarting a running core',
      () async {
        final container = ProviderContainer(
          overrides: [
            coreActionProvider.overrideWith(_TestCoreAction.new),
            setupActionProvider.overrideWith(_TestSetupAction.new),
          ],
        );
        addTearDown(container.dispose);
        container.read(runTimeProvider.notifier).value = 0;
        final coreAction =
            container.read(coreActionProvider.notifier) as _TestCoreAction;
        final setupAction =
            container.read(setupActionProvider.notifier) as _TestSetupAction;

        await coreAction.restartCore();

        expect(coreAction.lifecycleRestartCount, 1);
        expect(setupAction.setRunningCount, 1);
        expect(setupAction.applyProfileCount, 0);
      },
    );

    test(
      'coalesces concurrent restart requests into one lifecycle restart',
      () async {
        final container = ProviderContainer(
          overrides: [
            coreActionProvider.overrideWith(_TestCoreAction.new),
            setupActionProvider.overrideWith(_TestSetupAction.new),
          ],
        );
        addTearDown(container.dispose);
        final coreAction =
            container.read(coreActionProvider.notifier) as _TestCoreAction;
        final setupAction =
            container.read(setupActionProvider.notifier) as _TestSetupAction;
        final restartCompleter = Completer<CoreLifecycleResult>();
        coreAction.restartCompleter = restartCompleter;

        final first = coreAction.restartCore();
        final second = coreAction.restartCore();
        await Future<void>.delayed(Duration.zero);

        expect(coreAction.lifecycleRestartCount, 1);
        restartCompleter.complete(_restartResult);
        await Future.wait([first, second]);

        expect(setupAction.applyProfileCount, 1);
      },
    );

    test('reapplies the latest request without restarting twice', () async {
      final container = ProviderContainer(
        overrides: [
          coreActionProvider.overrideWith(_TestCoreAction.new),
          setupActionProvider.overrideWith(_TestSetupAction.new),
        ],
      );
      addTearDown(container.dispose);
      final coreAction =
          container.read(coreActionProvider.notifier) as _TestCoreAction;
      final setupAction =
          container.read(setupActionProvider.notifier) as _TestSetupAction;
      final restartCompleter = Completer<CoreLifecycleResult>();
      final firstApplyStarted = Completer<void>();
      final firstApplyCompleter = Completer<void>();
      coreAction.restartCompleter = restartCompleter;
      setupAction.firstApplyStarted = firstApplyStarted;
      setupAction.firstApplyCompleter = firstApplyCompleter;

      final first = coreAction.restartCore();
      await Future<void>.delayed(Duration.zero);
      restartCompleter.complete(_restartResult);
      await firstApplyStarted.future;

      final second = coreAction.restartCore();
      firstApplyCompleter.complete();
      await Future.wait([first, second]);

      expect(coreAction.lifecycleRestartCount, 1);
      expect(setupAction.applyProfileCount, 2);
    });

    test('surfaces a failed restart to its caller as a rejection', () async {
      final container = ProviderContainer(
        overrides: [
          coreActionProvider.overrideWith(_TestCoreAction.new),
          setupActionProvider.overrideWith(_TestSetupAction.new),
        ],
      );
      addTearDown(container.dispose);
      final coreAction =
          container.read(coreActionProvider.notifier) as _TestCoreAction;
      final restartCompleter = Completer<CoreLifecycleResult>();
      coreAction.restartCompleter = restartCompleter;

      final restart = coreAction.restartCore();
      restartCompleter.completeError(StateError('core is gone'));

      await expectLater(restart, throwsA(isA<StateError>()));
      expect(container.read(coreStatusProvider), CoreStatus.disconnected);

      // The failed operation must not latch: a later restart still runs.
      coreAction.restartCompleter = null;
      await coreAction.restartCore();
      expect(coreAction.lifecycleRestartCount, 2);
      expect(container.read(coreStatusProvider), CoreStatus.connected);
    });
  });

  group('SetupAction', () {
    group('rapid status changes', () {
      test('updates runtime and traffic while core start is pending', () async {
        final startCompleter = Completer<bool>();
        final container = ProviderContainer(
          overrides: [
            initProvider.overrideWithBuild((_, _) => true),
            commonActionProvider.overrideWith(_RaceCommonAction.new),
            setupActionProvider.overrideWith(_RaceSetupAction.new),
          ],
        );
        addTearDown(container.dispose);
        final action =
            container.read(setupActionProvider.notifier) as _RaceSetupAction;
        final commonAction =
            container.read(commonActionProvider.notifier) as _RaceCommonAction;
        action.startCompleter = startCompleter;

        final startFuture = action.setRunning(true);
        final initialRunTime = container.read(runTimeProvider)!;
        await Future<void>.delayed(const Duration(milliseconds: 1100));

        expect(container.read(runTimeProvider), greaterThan(initialRunTime));
        expect(commonAction.updateTrafficCount, greaterThanOrEqualTo(2));

        startCompleter.complete(true);
        await startFuture;

        expect(action.transitions, [true]);
        await action.setRunning(false);
      });

      test('serializes listener changes while latest start owns UI', () async {
        final stopCompleter = Completer<bool>();
        final container = ProviderContainer(
          overrides: [
            initProvider.overrideWithBuild((_, _) => true),
            commonActionProvider.overrideWith(_RaceCommonAction.new),
            setupActionProvider.overrideWith(_RaceSetupAction.new),
          ],
        );
        addTearDown(container.dispose);
        final action =
            container.read(setupActionProvider.notifier) as _RaceSetupAction;
        await action.setRunning(true);
        action.transitions.clear();
        action.applyProfileDebounceCount = 0;
        action.stopCompleter = stopCompleter;

        final stopFuture = action.setRunning(false);
        await Future<void>.delayed(Duration.zero);
        expect(action.transitions, [false]);

        final startFuture = action.setRunning(true);

        expect(container.read(runTimeProvider), isNotNull);

        stopCompleter.complete(true);
        await Future.wait([stopFuture, startFuture]);

        expect(action.transitions, [false, true]);
        expect(container.read(runTimeProvider), isNotNull);
        expect(container.read(isStartProvider), isTrue);
        expect(action.applyProfileDebounceCount, 1);
        expect(action.resetCoreTrafficCount, 0);

        await action.setRunning(false);
      });

      test('newer stop prevents stale start continuation', () async {
        final startCompleter = Completer<bool>();
        final container = ProviderContainer(
          overrides: [
            initProvider.overrideWithBuild((_, _) => true),
            commonActionProvider.overrideWith(_RaceCommonAction.new),
            setupActionProvider.overrideWith(_RaceSetupAction.new),
          ],
        );
        addTearDown(container.dispose);
        final action =
            container.read(setupActionProvider.notifier) as _RaceSetupAction;
        action.startCompleter = startCompleter;

        final startFuture = action.setRunning(true);
        await Future<void>.delayed(Duration.zero);
        expect(action.transitions, [true]);

        final stopFuture = action.setRunning(false);
        expect(container.read(runTimeProvider), isNull);

        startCompleter.complete(true);
        await Future.wait([startFuture, stopFuture]);

        expect(action.transitions, [true, false]);
        expect(container.read(runTimeProvider), isNull);
        expect(container.read(isStartProvider), isFalse);
        expect(action.applyProfileDebounceCount, 0);
        expect(action.resetCoreTrafficCount, 1);
      });

      test('skips an intermediate stop when a newer start is queued', () async {
        final startCompleter = Completer<bool>();
        final container = ProviderContainer(
          overrides: [
            initProvider.overrideWithBuild((_, _) => true),
            commonActionProvider.overrideWith(_RaceCommonAction.new),
            setupActionProvider.overrideWith(_RaceSetupAction.new),
          ],
        );
        addTearDown(container.dispose);
        final action =
            container.read(setupActionProvider.notifier) as _RaceSetupAction;
        action.startCompleter = startCompleter;

        final firstStart = action.setRunning(true);
        await Future<void>.delayed(Duration.zero);
        final stop = action.setRunning(false);
        final latestStart = action.setRunning(true);

        startCompleter.complete(true);
        await Future.wait([firstStart, stop, latestStart]);

        expect(action.transitions, [true, true]);
        expect(container.read(isStartProvider), isTrue);
        expect(action.applyProfileDebounceCount, 1);
        expect(action.resetCoreTrafficCount, 0);

        await action.setRunning(false);
      });

      test('stale initialization cannot start after a newer stop', () async {
        final container = ProviderContainer(
          overrides: [
            initProvider.overrideWithBuild((_, _) => true),
            commonActionProvider.overrideWith(_RaceCommonAction.new),
            setupActionProvider.overrideWith(_InitializingSetupAction.new),
          ],
        );
        addTearDown(container.dispose);
        final action =
            container.read(setupActionProvider.notifier)
                as _InitializingSetupAction;

        final start = action.setRunning(true, initialize: true);
        final stop = action.setRunning(false);
        await stop;

        expect(action.transitions, [false]);
        expect(container.read(isStartProvider), isFalse);

        action.continueInitialization();
        await start;

        expect(action.transitions, [false]);
        expect(container.read(isStartProvider), isFalse);
      });

      test(
        'keeps suspended startup local until the listener resumes',
        () async {
          final container = ProviderContainer(
            overrides: [
              initProvider.overrideWithBuild((_, _) => true),
              suspendProvider.overrideWithValue(true),
              commonActionProvider.overrideWith(_RaceCommonAction.new),
              setupActionProvider.overrideWith(_RaceSetupAction.new),
            ],
          );
          addTearDown(container.dispose);
          final action =
              container.read(setupActionProvider.notifier) as _RaceSetupAction;

          await action.setRunning(true);

          expect(action.transitions, isEmpty);
          expect(container.read(isStartProvider), isTrue);
          expect(action.applyProfileDebounceCount, 1);

          await action.setRunning(false);
          expect(action.transitions, [false]);
        },
      );
    });

    test(
      'restarts core after newly granting admin during config update',
      () async {
        late _AuthorizationSetupAction setupAction;
        late _RestartRecordingCoreAction coreAction;
        final container = ProviderContainer(
          overrides: [
            setupActionProvider.overrideWith(() {
              setupAction = _AuthorizationSetupAction([AuthorizeCode.success]);
              return setupAction;
            }),
            coreActionProvider.overrideWith(() {
              coreAction = _RestartRecordingCoreAction();
              return coreAction;
            }),
          ],
        );
        addTearDown(container.dispose);
        container
            .read(patchClashConfigProvider.notifier)
            .update((state) => state.copyWith.tun(enable: true));
        container.read(setupActionProvider);
        container.read(coreActionProvider);

        await setupAction.updateConfig();

        expect(setupAction.authorizationRequestCount, 1);
        expect(
          container.read(authorizedTunEnableProvider),
          TunAuthorizationState.authorized,
        );
        expect(coreAction.restartCount, 1);
      },
    );

    test('reopens authorization and propagates a failed restart', () async {
      late _AuthorizationSetupAction setupAction;
      final container = ProviderContainer(
        overrides: [
          currentProfileProvider.overrideWithValue(null),
          setupActionProvider.overrideWith(() {
            setupAction = _AuthorizationSetupAction([AuthorizeCode.success]);
            return setupAction;
          }),
          coreActionProvider.overrideWith(_FailingRestartCoreAction.new),
        ],
      );
      addTearDown(container.dispose);
      container
          .read(patchClashConfigProvider.notifier)
          .update((state) => state.copyWith.tun(enable: true));
      container.read(setupActionProvider);
      container.read(coreActionProvider);

      await expectLater(
        setupAction.applyProfile(force: true),
        throwsA(same(_restartFailure)),
      );

      expect(
        container.read(authorizedTunEnableProvider),
        TunAuthorizationState.none,
      );
    });

    test('requests admin authorization once per app lifecycle', () async {
      late _AuthorizationSetupAction setupAction;
      final container = ProviderContainer(
        overrides: [
          setupActionProvider.overrideWith(() {
            setupAction = _AuthorizationSetupAction([
              AuthorizeCode.error,
              AuthorizeCode.success,
            ]);
            return setupAction;
          }),
        ],
      );
      addTearDown(container.dispose);
      container.read(setupActionProvider);

      expect(await setupAction.requestAdmin(true), isTrue);
      expect(
        container.read(authorizedTunEnableProvider),
        TunAuthorizationState.unauthorized,
      );

      expect(await setupAction.requestAdmin(true), isTrue);
      expect(setupAction.authorizationRequestCount, 1);
      expect(
        container.read(authorizedTunEnableProvider),
        TunAuthorizationState.unauthorized,
      );
    });

    test('keeps tun disabled while authorization stays unauthorized', () async {
      late _AuthorizationSetupAction setupAction;
      final container = ProviderContainer(
        overrides: [
          setupActionProvider.overrideWith(() {
            setupAction = _AuthorizationSetupAction([AuthorizeCode.error]);
            return setupAction;
          }),
        ],
      );
      addTearDown(container.dispose);
      container
          .read(patchClashConfigProvider.notifier)
          .update((state) => state.copyWith.tun(enable: true));
      container.read(setupActionProvider);

      await setupAction.requestAdmin(true);

      expect(container.read(autoSetSystemDnsStateProvider).a, isFalse);
    });
  });
}

class _TestProfiles extends Profiles {
  final List<Profile> initial;

  _TestProfiles(this.initial);

  @override
  List<Profile> build() => initial;

  @override
  void put(Profile profile) {
    final next = List<Profile>.from(state);
    final index = next.indexWhere((item) => item.id == profile.id);
    if (index == -1) {
      next.add(profile);
    } else {
      next[index] = profile;
    }
    state = next;
  }

  @override
  Future<void> del(int id) async {
    state = state.where((profile) => profile.id != id).toList();
  }

  @override
  void reorder(List<Profile> profiles) {
    state = List.of(profiles);
  }
}

class _TestCoreAction extends CoreAction {
  int lifecycleRestartCount = 0;
  Completer<CoreLifecycleResult>? restartCompleter;

  @override
  Future<void> initCore() async {}

  @override
  Future<CoreLifecycleResult> restartLifecycle() {
    lifecycleRestartCount++;
    return restartCompleter?.future ?? Future.value(_restartResult);
  }
}

class _TestSetupAction extends SetupAction {
  int setRunningCount = 0;
  int applyProfileCount = 0;
  Completer<void>? firstApplyStarted;
  Completer<void>? firstApplyCompleter;

  @override
  Future<void> setRunning(bool running, {bool initialize = false}) async {
    setRunningCount++;
  }

  @override
  Future<void> applyProfile({
    bool silence = false,
    bool force = false,
    Future<void> Function()? preloadInvoke,
  }) async {
    applyProfileCount++;
    if (applyProfileCount == 1) {
      firstApplyStarted?.complete();
      await firstApplyCompleter?.future;
    }
  }
}

const _restartResult = CoreLifecycleResult(
  revision: 1,
  outcome: CoreLifecycleOutcome.applied,
);

class _RestartRecordingCoreAction extends CoreAction {
  int restartCount = 0;

  @override
  Future<void> restartCore() async {
    restartCount++;
  }
}

class _FailingRestartCoreAction extends CoreAction {
  @override
  Future<void> restartCore() async {
    throw _restartFailure;
  }
}

final _restartFailure = Exception('restart failed');

class _AuthorizationSetupAction extends SetupAction {
  final List<AuthorizeCode> authorizationResults;
  int authorizationRequestCount = 0;

  _AuthorizationSetupAction(this.authorizationResults);

  @override
  Future<AuthorizeCode> authorizeCore() async {
    return authorizationResults[authorizationRequestCount++];
  }
}

class _RaceSetupAction extends SetupAction {
  int applyProfileDebounceCount = 0;
  int resetCoreTrafficCount = 0;
  final transitions = <bool>[];
  Completer<bool>? startCompleter;
  Completer<bool>? stopCompleter;

  @override
  void applyProfileDebounce({bool silence = false, bool force = false}) {
    applyProfileDebounceCount++;
  }

  @override
  Future<bool> setCoreRunning(bool running) async {
    transitions.add(running);
    return running
        ? await startCompleter?.future ?? true
        : await stopCompleter?.future ?? true;
  }

  @override
  void resetCoreTraffic() {
    resetCoreTrafficCount++;
  }
}

class _InitializingSetupAction extends _RaceSetupAction {
  final _initializationCompleter = Completer<void>();

  void continueInitialization() {
    _initializationCompleter.complete();
  }

  @override
  Future<void> applyProfile({
    bool silence = false,
    bool force = false,
    Future<void> Function()? preloadInvoke,
  }) async {
    await _initializationCompleter.future;
    await preloadInvoke?.call();
  }
}

class _RaceCommonAction extends CommonAction {
  int updateTrafficCount = 0;

  @override
  Future<void> updateTraffic() async {
    updateTrafficCount++;
  }
}

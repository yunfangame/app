import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/database/database.dart' show database;
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/action.dart';
import 'package:fl_clash/providers/config.dart';
import 'package:fl_clash/providers/database.dart';
import 'package:fl_clash/state.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:riverpod/riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakePathProvider extends PathProviderPlatform {
  _FakePathProvider(this.root);

  final String root;

  @override
  Future<String?> getTemporaryPath() async => root;

  @override
  Future<String?> getApplicationSupportPath() async => root;

  @override
  Future<String?> getApplicationCachePath() async => root;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory testDirectory;

  setUpAll(() {
    testDirectory = Directory.systemTemp.createTempSync('action_test');
    PathProviderPlatform.instance = _FakePathProvider(testDirectory.path);
  });

  tearDownAll(() async {
    await database.close();
    await commonPrint.flushDiagnosticEvents();
    await testDirectory.delete(recursive: true);
  });

  group('managed V1 profile updates', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
      globalState.clearXboardSession();
      globalState.setOfflineMode(false);
    });

    tearDown(() {
      globalState.clearXboardSession();
      globalState.setOfflineMode(false);
    });

    ProviderContainer createContainer(
      Profile profile,
      _TestProfileUpdateAction action,
    ) {
      final container = ProviderContainer(
        overrides: [
          currentProfileIdProvider.overrideWithBuild((_, _) => null),
          profilesProvider.overrideWith(() => _TestProfiles([profile])),
          profilesActionProvider.overrideWith(() => action),
        ],
      );
      addTearDown(container.dispose);
      return container;
    }

    test(
      'initial sync imports the active API URL and removes the old URL',
      () async {
        final session = _profileUpdateSession();
        globalState.activateXboardSession(session);
        final oldProfile = Profile.normal(url: session.subscribeUrl.toString());
        final setup = _TestSetupAction();
        final container = ProviderContainer(
          overrides: [
            currentProfileIdProvider.overrideWithBuild((_, _) => oldProfile.id),
            profilesProvider.overrideWith(() => _TestProfiles([oldProfile])),
            setupActionProvider.overrideWith(() => setup),
          ],
        );
        addTearDown(container.dispose);
        final cleared = <int>[];
        final imported = await container
            .read(profilesActionProvider.notifier)
            .syncSubscriptionProfile(
              session.legacySubscribeUrl.toString(),
              replacingUrl: oldProfile.url,
              isCurrent: () => identical(globalState.xboardSession, session),
              loader: (profile) async {
                expect(
                  profile.url,
                  'https://working-api.example:8443/s/current-token?flag=clash',
                );
                return profile;
              },
              effectClearer: (id) async => cleared.add(id),
            );

        expect(container.read(profilesProvider), [imported]);
        expect(container.read(currentProfileIdProvider), imported.id);
        expect(setup.applyCount, 1);
        expect(cleared, [oldProfile.id]);
      },
    );

    test(
      'initial sync restores the file when the session expires during loading',
      () async {
        final profile = Profile.normal(
          url: 'https://working-api.example/s/token',
        );
        final file = File(await appPath.getProfilePath(profile.id.toString()));
        await file.safeWriteAsBytes(utf8.encode('previous configuration'));
        final setup = _TestSetupAction();
        final container = ProviderContainer(
          overrides: [
            currentProfileIdProvider.overrideWithBuild((_, _) => profile.id),
            profilesProvider.overrideWith(() => _TestProfiles([profile])),
            setupActionProvider.overrideWith(() => setup),
          ],
        );
        addTearDown(container.dispose);
        var current = true;
        await expectLater(
          container
              .read(profilesActionProvider.notifier)
              .syncSubscriptionProfile(
                profile.url,
                isCurrent: () => current,
                loader: (candidate) async {
                  await file.safeWriteAsBytes(
                    utf8.encode('expired configuration'),
                  );
                  current = false;
                  return candidate.copyWith(label: 'Expired');
                },
              ),
          throwsStateError,
        );

        expect(await file.readAsString(), 'previous configuration');
        expect(container.read(profilesProvider), [profile]);
        expect(container.read(currentProfileIdProvider), profile.id);
        expect(setup.applyCount, 0);
      },
    );

    test(
      'an expired session cannot start writing downloaded profile bytes',
      () async {
        final profile = Profile.normal(
          url: 'https://working-api.example/s/token',
        );
        final file = File(await appPath.getProfilePath(profile.id.toString()));
        await file.safeWriteAsBytes(utf8.encode('previous configuration'));
        await expectLater(
          profile.saveFile(
            Uint8List.fromList(utf8.encode('expired configuration')),
            isCurrent: () => false,
          ),
          throwsStateError,
        );
        expect(await file.readAsString(), 'previous configuration');
      },
    );

    test(
      'manual update saves the successful API source after loading',
      () async {
        final session = _profileUpdateSession();
        globalState.activateXboardSession(session);
        final profile = Profile.normal(url: session.subscribeUrl.toString());
        final storage = XboardSessionStorage();
        await storage.setManagedProfileUrl(profile.url);
        final action = _TestProfileUpdateAction();
        final container = createContainer(profile, action);

        await container
            .read(profilesActionProvider.notifier)
            .updateProfile(profile);

        expect(action.loaded.single.url, session.legacySubscribeUrl.toString());
        expect(container.read(profilesProvider).single.id, profile.id);
        expect(
          container.read(profilesProvider).single.url,
          session.legacySubscribeUrl.toString(),
        );
        expect(
          await storage.loadManagedProfileUrl(),
          session.legacySubscribeUrl.toString(),
        );
      },
    );

    test(
      'automatic update migrates a saved API source for the same account',
      () async {
        final session = _profileUpdateSession();
        globalState.activateXboardSession(session);
        final profile = Profile.normal(
          url: 'https://previous-api.example/s/current-token?flag=clash',
        );
        final storage = XboardSessionStorage();
        await storage.setManagedProfileUrl(profile.url);
        final action = _TestProfileUpdateAction();
        final container = createContainer(profile, action);

        await container
            .read(profilesActionProvider.notifier)
            .autoUpdateProfiles();

        expect(action.loaded.single.url, session.legacySubscribeUrl.toString());
        expect(
          container.read(profilesProvider).single.url,
          session.legacySubscribeUrl.toString(),
        );
        expect(
          await storage.loadManagedProfileUrl(),
          session.legacySubscribeUrl.toString(),
        );
      },
    );

    test(
      'keeps unrelated imports and another account source unchanged',
      () async {
        globalState.activateXboardSession(_profileUpdateSession());
        final profile = Profile.normal(
          url: 'https://other.example/s/another-account-token?flag=clash',
        );
        final storage = XboardSessionStorage();
        await storage.setManagedProfileUrl(profile.url);
        final action = _TestProfileUpdateAction();
        final container = createContainer(profile, action);

        await container
            .read(profilesActionProvider.notifier)
            .updateProfile(profile);

        expect(action.loaded.single.url, profile.url);
        expect(container.read(profilesProvider).single.url, profile.url);
        expect(await storage.loadManagedProfileUrl(), profile.url);
      },
    );

    test('does not download a managed profile in offline mode', () async {
      final session = _profileUpdateSession();
      globalState.activateXboardSession(session);
      globalState.setOfflineMode(true);
      final profile = Profile.normal(url: session.subscribeUrl.toString());
      final action = _TestProfileUpdateAction();
      final container = createContainer(profile, action);

      await container
          .read(profilesActionProvider.notifier)
          .autoUpdateProfiles();

      expect(action.loaded, isEmpty);
      expect(container.read(profilesProvider).single, profile);
    });

    for (final secureSubscription in [false, true]) {
      test(
        'does not revive V1 when its URL is missing or V2 owns the session ($secureSubscription)',
        () async {
          globalState.activateXboardSession(
            _profileUpdateSession(
              secureSubscription: secureSubscription,
              subscribeUrl: null,
            ),
          );
          final profile = Profile.normal(
            url: 'https://old.example/s/current-token?flag=clash',
          );
          await XboardSessionStorage().setManagedProfileUrl(profile.url);
          final action = _TestProfileUpdateAction();
          final container = createContainer(profile, action);

          await expectLater(
            container
                .read(profilesActionProvider.notifier)
                .updateProfile(profile),
            throwsA(isA<SubscriptionV2Exception>()),
          );

          expect(action.loaded, isEmpty);
          expect(container.read(profilesProvider).single, profile);
        },
      );
    }

    test('keeps the saved URL and file when a migrated update fails', () async {
      final session = _profileUpdateSession();
      globalState.activateXboardSession(session);
      final profile = Profile.normal(url: session.subscribeUrl.toString());
      final file = File(await appPath.getProfilePath(profile.id.toString()));
      await file.safeWriteAsBytes(utf8.encode('previous configuration'));
      final storage = XboardSessionStorage();
      await storage.setManagedProfileUrl(profile.url);
      final action = _TestProfileUpdateAction()
        ..loader = (candidate) async {
          await file.safeWriteAsBytes(utf8.encode('failed replacement'));
          throw StateError('download failed');
        };
      final container = createContainer(profile, action);

      await expectLater(
        container.read(profilesActionProvider.notifier).updateProfile(profile),
        throwsStateError,
      );

      expect(await file.readAsString(), 'previous configuration');
      expect(await storage.loadManagedProfileUrl(), profile.url);
      expect(container.read(profilesProvider).single, profile);
    });

    test(
      'discards a migrated update when the account changes during loading',
      () async {
        final session = _profileUpdateSession();
        globalState.activateXboardSession(session);
        final profile = Profile.normal(url: session.subscribeUrl.toString());
        final storage = XboardSessionStorage();
        await storage.setManagedProfileUrl(profile.url);
        final entered = Completer<Profile>();
        final pending = Completer<Profile>();
        final action = _TestProfileUpdateAction()
          ..loader = (candidate) {
            entered.complete(candidate);
            return pending.future;
          };
        final container = createContainer(profile, action);
        final result = container
            .read(profilesActionProvider.notifier)
            .updateProfile(profile);
        final candidate = await entered.future;
        final assertion = expectLater(result, throwsStateError);
        globalState.activateXboardSession(
          _profileUpdateSession(
            subscribeUrl: 'https://subscribe.example/s/new-account',
          ),
        );
        pending.complete(candidate);
        await assertion;

        expect(await storage.loadManagedProfileUrl(), profile.url);
        expect(container.read(profilesProvider).single, profile);
      },
    );
  });
}

XboardLoginResult _profileUpdateSession({
  String? subscribeUrl = 'https://subscribe.example/s/current-token?flag=clash',
  bool secureSubscription = false,
}) {
  final endpoint = Uri.parse(
    'https://working-api.example:8443/api/v1/passport/auth/login',
  );
  return XboardLoginResult(
    endpoint: endpoint,
    token: 'current-token',
    authData: 'test-auth',
    isAdmin: false,
    secureSubscription: secureSubscription,
    subscription: XboardSubscriptionData(
      endpoint: endpoint,
      subscribeUrl: subscribeUrl == null ? null : Uri.parse(subscribeUrl),
      uploadBytes: 0,
      downloadBytes: 0,
      transferEnableBytes: 100,
      rawData: const {},
    ),
  );
}

class _TestProfileUpdateAction extends ProfilesAction {
  final loaded = <Profile>[];
  Future<Profile> Function(Profile)? loader;

  @override
  Future<Profile> loadProfileUpdate(
    Profile profile, {
    bool Function()? isCurrent,
  }) async {
    loaded.add(profile);
    return loader != null
        ? await loader!(profile)
        : profile.copyWith(lastUpdateDate: DateTime.now());
  }
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

class _TestSetupAction extends SetupAction {
  int applyCount = 0;

  @override
  Future<void> applyProfile({
    bool silence = false,
    bool force = false,
    Future<void> Function()? preloadInvoke,
  }) async {
    applyCount++;
  }
}

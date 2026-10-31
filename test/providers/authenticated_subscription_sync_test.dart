import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/database/database.dart' show database;
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/action.dart';
import 'package:fl_clash/providers/app.dart';
import 'package:fl_clash/providers/config.dart';
import 'package:fl_clash/providers/database.dart';
import 'package:fl_clash/state.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:riverpod/riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  setUpAll(() async {
    directory = await Directory.systemTemp.createTemp('authenticated_profiles');
    PathProviderPlatform.instance = _Paths(directory.path);
  });
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    globalState.clearXboardSession();
    globalState.setOfflineMode(false);
  });
  tearDown(() {
    globalState.clearXboardSession();
    globalState.setOfflineMode(false);
  });
  tearDownAll(() async {
    await database.close();
    await commonPrint.flushDiagnosticEvents();
    await directory.delete(recursive: true);
  });

  test(
    'concurrent login transactions share download and durable commit',
    () async {
      final h = await _Harness.create();
      final entered = Completer<void>();
      final release = Completer<void>();
      h.action.beforeDownload = () async {
        if (!entered.isCompleted) entered.complete();
        await release.future;
      };
      final first = h.login();
      await entered.future;
      final second = h.login();
      release.complete();
      final profiles = await Future.wait([first, second]);
      expect(h.action.downloads, 1);
      expect(profiles[0], profiles[1]);
      expect(h.setup.applications, 1);
    },
  );

  for (final useV2 in [false, true]) {
    test('failed durable save never applies profile (V2 $useV2)', () async {
      final h = await _Harness.create();
      await h.file.parent.create(recursive: true);
      await h.file.writeAsString('prior-validated');
      final entered = Completer<void>();
      final failure = Completer<void>();
      final profiles = h.container.read(profilesProvider.notifier) as _Profiles;
      profiles.persist = (_) {
        entered.complete();
        return failure.future;
      };
      final syncing = _syncWithDownloadedFile(h, useV2: useV2);
      final rejected = expectLater(syncing, throwsA(isA<StateError>()));
      await entered.future;
      expect(h.setup.applications, 0);
      expect(h.container.read(currentProfileIdProvider), isNull);
      failure.completeError(StateError('write failed'));
      await rejected;
      expect(h.setup.applications, 0);
      expect(h.container.read(profilesProvider), [h.profile]);
      expect(await h.file.readAsString(), 'prior-validated');
    });

    for (final change in ['file', 'source', 'account', 'new-write']) {
      test('file rollback preserves concurrent $change (V2 $useV2)', () async {
        final h = await _Harness.create();
        await h.file.parent.create(recursive: true);
        await h.file.writeAsString('prior-validated');
        final entered = Completer<void>();
        final failure = Completer<void>();
        final profiles =
            h.container.read(profilesProvider.notifier) as _Profiles;
        var writes = 0;
        profiles.persist = (_) {
          if (++writes > 1) return Future.value();
          entered.complete();
          return failure.future;
        };
        final syncing = _syncWithDownloadedFile(h, useV2: useV2);
        final rejected = expectLater(syncing, throwsA(isA<StateError>()));
        await entered.future;
        await h.file.writeAsString('newer-owner');
        switch (change) {
          case 'file':
            break;
          case 'source':
            profiles.put(h.profile.copyWith(url: 'fengwo-v2://fixture/newer'));
          case 'account':
            globalState.activateXboardSession(_session('another'));
          case 'new-write':
            await profiles.putDurable(
              h.profile.copyWith(url: 'fengwo-v2://fixture/newer'),
            );
        }
        failure.completeError(StateError('late write failed'));
        await rejected;
        expect(h.setup.applications, 0);
        expect(await h.file.readAsString(), 'newer-owner');
      });
    }
  }

  for (final change in ['none', 'new-writer', 'new-source']) {
    test(
      'model write followed by account switch preserves file ownership ($change)',
      () async {
        final h = await _Harness.create();
        await h.file.parent.create(recursive: true);
        await h.file.writeAsString('previous-accepted');
        final candidateBytes = Uint8List.fromList(
          'candidate-profile'.codeUnits,
        );
        final syncing = h.action.runAuthenticatedSubscriptionSync(
          h.session,
          allowTokenRegistration: false,
          sync: (guard) => h.action.syncSubscriptionProfileBytes(
            candidateBytes,
            sourceId: 'fengwo-v2://fixture/replacement',
            replacingUrl: h.profile.url,
            isCurrent: guard,
            loader: (candidate, bytes) async {
              final saved = await candidate.saveFile(
                bytes,
                isCurrent: guard,
                validateConfig: (path) async {
                  expect(await File(path).readAsBytes(), candidateBytes);
                  return '';
                },
              );
              expect(await h.file.readAsBytes(), candidateBytes);
              globalState.activateXboardSession(_session('two'));
              switch (change) {
                case 'none':
                  break;
                case 'new-writer':
                  final newOwner = ProfileFileWriteScope(h.file.path);
                  try {
                    await newOwner.run(
                      () => writeProfileFileBytes(h.file, candidateBytes),
                    );
                  } finally {
                    newOwner.dispose();
                  }
                case 'new-source':
                  h.container
                      .read(profilesProvider.notifier)
                      .put(h.profile.copyWith(url: 'fengwo-v2://fixture/two'));
                  await writeProfileFileBytes(
                    h.file,
                    Uint8List.fromList('new-account-profile'.codeUnits),
                  );
              }
              if (!guard()) throw StateError('profile_sync_superseded');
              return saved;
            },
          ),
        );
        await expectLater(syncing, throwsStateError);
        expect(h.setup.applications, 0);
        expect(h.container.read(currentProfileIdProvider), isNull);
        expect(globalState.xboardSession?.token, 'two');
        expect(await h.file.readAsString(), switch (change) {
          'none' => 'previous-accepted',
          'new-writer' => 'candidate-profile',
          _ => 'new-account-profile',
        });
        if (change != 'new-source') {
          expect(h.container.read(profilesProvider), [h.profile]);
        }
      },
    );
  }

  test(
    'nearby sequential login reuses verified bytes and reapplies locally',
    () async {
      final h = await _Harness.create();
      final first = await h.login();
      h.action.now = h.action.now.add(const Duration(seconds: 29));
      expect(await h.login(), first);
      expect(h.action.downloads, 1);
      expect(h.setup.applications, 2);
      h.action.now = h.action.now.add(const Duration(seconds: 1));
      await h.login();
      expect(h.action.downloads, 2);
    },
  );

  for (final realProfiles in [false, true]) {
    for (final reuseIdentity in [false, true]) {
      test(
        'V2 replacement survives old source cleanup ($realProfiles, $reuseIdentity)',
        () async {
          const sourceId = 'fengwo-v2://fixture/replacement';
          final h = await _Harness.create(
            realProfiles: realProfiles,
            existingReplacementSource: reuseIdentity ? null : sourceId,
          );
          final updateDate = DateTime(2026, 10, 31, 12, 27, 13, 123, 456);
          final databaseEcho = Completer<void>();
          if (realProfiles) {
            h.container.listen(profilesProvider, (_, profiles) {
              if (profiles.any(
                (profile) =>
                    profile.url == sourceId &&
                    profile.lastUpdateDate ==
                        DateTime.fromMillisecondsSinceEpoch(
                          (updateDate.millisecondsSinceEpoch ~/ 1000) * 1000,
                        ),
              )) {
                if (!databaseEcho.isCompleted) databaseEcho.complete();
              }
            });
            h.setup.afterApply = () =>
                databaseEcho.future.timeout(const Duration(seconds: 3));
          }
          File? committedFile;
          final result = await h.action.runAuthenticatedSubscriptionSync(
            h.session,
            allowTokenRegistration: false,
            sync: (guard) => h.action.syncSubscriptionProfileBytes(
              Uint8List.fromList([1]),
              sourceId: sourceId,
              replacingUrl: h.profile.url,
              isCurrent: guard,
              loader: (profile, _) async {
                expect(profile.id == h.profile.id, reuseIdentity);
                committedFile = File(
                  await appPath.getProfilePath(profile.id.toString()),
                );
                await committedFile!.parent.create(recursive: true);
                await committedFile!.writeAsString('validated-replacement');
                return profile.copyWith(lastUpdateDate: updateDate);
              },
              effectClearer: (_) async {},
            ),
          );
          expect(result, isNotNull);
          expect(result!.url, sourceId);
          expect(h.container.read(currentProfileIdProvider), result.id);
          expect(h.container.read(profilesProvider).map((p) => (p.id, p.url)), [
            (result.id, sourceId),
          ]);
          expect(await committedFile!.readAsString(), 'validated-replacement');
          expect(h.setup.applications, 1);
          h.setup.afterApply = null;
          await XboardSessionStorage().setManagedProfileUrl(sourceId);
          final refreshed = await h.action.runAuthenticatedSubscriptionSync(
            h.session,
            allowTokenRegistration: false,
            forceRefresh: true,
            sync: (guard) => h.action.syncSubscriptionProfileBytes(
              Uint8List.fromList([2]),
              sourceId: sourceId,
              isCurrent: guard,
              loader: (profile, _) async {
                await committedFile!.writeAsString('validated-refresh');
                return profile.copyWith(
                  lastUpdateDate: DateTime(2026, 10, 31, 12, 27, 24, 321),
                );
              },
            ),
          );
          expect(refreshed?.id, result.id);
          expect(h.container.read(currentProfileIdProvider), result.id);
          expect(await committedFile!.readAsString(), 'validated-refresh');
          expect(h.setup.applications, 2);
        },
      );
    }
  }

  for (final change in ['logout', 'source', 'delete-profile']) {
    test('V2 replacement rejects $change during cleanup', () async {
      const sourceId = 'fengwo-v2://fixture/replacement';
      final h = await _Harness.create(existingReplacementSource: sourceId);
      Profile? replacement;
      final syncing = h.action.runAuthenticatedSubscriptionSync(
        h.session,
        allowTokenRegistration: false,
        sync: (guard) => h.action.syncSubscriptionProfileBytes(
          Uint8List.fromList([1]),
          sourceId: sourceId,
          replacingUrl: h.profile.url,
          isCurrent: guard,
          loader: (profile, _) async => replacement = profile,
          effectClearer: (_) async {
            switch (change) {
              case 'logout':
                globalState.clearXboardSession();
              case 'source':
                h.container
                    .read(profilesProvider.notifier)
                    .put(
                      replacement!.copyWith(url: 'fengwo-v2://fixture/changed'),
                    );
              case 'delete-profile':
                await h.container
                    .read(profilesProvider.notifier)
                    .del(replacement!.id);
            }
          },
        ),
      );
      await expectLater(syncing, throwsA(isA<StateError>()));
    });
  }

  for (final loginFirst in [false, true]) {
    test(
      'startup automatic and login converge without queue deadlock ($loginFirst)',
      () async {
        final h = await _Harness.create();
        final entered = Completer<void>();
        final release = Completer<void>();
        h.action.beforeDownload = () async {
          if (!entered.isCompleted) entered.complete();
          await release.future;
        };
        final first = loginFirst ? h.login() : h.action.autoUpdateProfiles();
        await entered.future;
        final second = loginFirst ? h.action.autoUpdateProfiles() : h.login();
        release.complete();
        await Future.wait<Object?>([first, second]);
        expect(h.action.downloads, 1);
        expect(h.container.read(currentProfileIdProvider), h.profile.id);
        expect(h.setup.applications, greaterThanOrEqualTo(1));
      },
    );
  }

  test('loose automatic work joins a strict login transaction', () async {
    final h = await _Harness.create();
    final entered = Completer<void>();
    final release = Completer<void>();
    h.action.beforeDownload = () async {
      if (!entered.isCompleted) entered.complete();
      await release.future;
    };
    final login = h.login(allowTokenRegistration: false);
    await entered.future;
    final automatic = h.action.autoUpdateProfiles();
    release.complete();
    await Future.wait<Object?>([login, automatic]);
    expect(h.action.downloads, 1);
  });

  test(
    'same authentication metadata refresh preserves a recent result',
    () async {
      final h = await _Harness.create();
      await h.login();
      globalState.activateXboardSession(_session('one'));
      await h.login();
      expect(h.action.downloads, 1);
    },
  );

  test(
    'login reuses immediately preceding successful automatic transaction',
    () async {
      final h = await _Harness.create();
      await h.action.autoUpdateProfiles();
      expect(h.action.downloads, 1);
      await h.login();
      expect(h.action.downloads, 1);
      expect(h.setup.applications, 1);
    },
  );

  test(
    'platform restore callback runs once only for a valid reused transaction',
    () async {
      final h = await _Harness.create();
      var restores = 0;
      Future<void> onReuse(Profile profile, bool Function() guard) async {
        expect(guard(), isTrue);
        expect(profile.id, h.profile.id);
        restores++;
      }

      await h.login(onReuse: onReuse);
      expect(restores, 0);
      await h.login(onReuse: onReuse);
      expect(restores, 1);
      await h.login(forceRefresh: true, onReuse: onReuse);
      expect(restores, 1);
    },
  );

  for (final change in [
    'delete-file',
    'replace-file',
    'delete-profile',
    'source',
    'logout',
    'account',
  ]) {
    test('completed result is isolated after $change', () async {
      final h = await _Harness.create();
      await h.login();
      switch (change) {
        case 'delete-file':
          await h.file.delete();
        case 'replace-file':
          await h.file.writeAsString('externally changed');
        case 'delete-profile':
          await h.container.read(profilesProvider.notifier).del(h.profile.id);
        case 'source':
          h.container
              .read(profilesProvider.notifier)
              .put(h.profile.copyWith(url: 'https://other.example/source'));
        case 'logout':
          globalState.clearXboardSession();
        case 'account':
          globalState.activateXboardSession(_session('another'));
      }
      final result = await h.login();
      if (change == 'logout' || change == 'account') {
        expect(result, isNull);
        expect(h.action.downloads, 1);
      } else {
        expect(h.action.downloads, 2);
      }
    });
  }

  for (final change in [
    'offline',
    'logout',
    'account',
    'source',
    'delete-profile',
    'dispose',
  ]) {
    test('late transaction cannot commit after $change', () async {
      final h = await _Harness.create();
      final entered = Completer<void>();
      final release = Completer<void>();
      h.action.beforeDownload = () async {
        entered.complete();
        await release.future;
      };
      final work = h.login();
      await entered.future;
      switch (change) {
        case 'offline':
          globalState.setOfflineMode(true);
        case 'logout':
          globalState.clearXboardSession();
        case 'account':
          globalState.activateXboardSession(_session('another'));
        case 'source':
          h.container
              .read(profilesProvider.notifier)
              .put(h.profile.copyWith(url: 'https://other.example/changed'));
        case 'delete-profile':
          await h.container.read(profilesProvider.notifier).del(h.profile.id);
        case 'dispose':
          h.container.dispose();
      }
      release.complete();
      await expectLater(work, throwsA(anything));
      expect(h.setup.applications, 0);
    });
  }

  test(
    'forced payment starts fresh and supersedes an older automatic result',
    () async {
      final h = await _Harness.create();
      final entered = Completer<void>();
      final release = Completer<void>();
      h.action.beforeDownload = () async {
        if (h.action.downloads == 1) {
          entered.complete();
          await release.future;
        }
      };
      final automatic = h.action.autoUpdateProfiles();
      await entered.future;
      final payment = h.login(forceRefresh: true);
      release.complete();
      await Future.wait<Object?>([automatic, payment]);
      expect(h.action.downloads, 2);
      expect(await h.file.readAsString(), 'validated-2');
    },
  );

  test(
    'concurrent forced requests coalesce and completed force is never a force hit',
    () async {
      final h = await _Harness.create();
      final entered = Completer<void>();
      final release = Completer<void>();
      h.action.beforeDownload = () async {
        if (!entered.isCompleted) entered.complete();
        await release.future;
      };
      final first = h.login(forceRefresh: true);
      await entered.future;
      final second = h.login(forceRefresh: true);
      release.complete();
      await Future.wait([first, second]);
      expect(h.action.downloads, 1);
      await h.login(forceRefresh: true);
      expect(h.action.downloads, 2);
    },
  );

  for (final registered in [false, true]) {
    test(
      'strict login waits for loose completion without inheriting registration ($registered)',
      () async {
        final h = await _Harness.create();
        final entered = Completer<void>();
        final release = Completer<void>();
        final loose = h.action.runAuthenticatedSubscriptionSync(
          h.session,
          allowTokenRegistration: true,
          sync: (guard) async {
            entered.complete();
            await release.future;
            return h.action.syncSubscriptionProfileBytes(
              Uint8List.fromList([1]),
              sourceId: 'fengwo-v2://fixture/account',
              replacingUrl: h.profile.url,
              usedTokenRegistration: registered,
              isCurrent: guard,
              loader: (profile, _) =>
                  h.action.loadProfileUpdate(profile, isCurrent: guard),
            );
          },
        );
        await entered.future;
        var strictLoads = 0;
        final strict = h.action.runAuthenticatedSubscriptionSync(
          h.session,
          allowTokenRegistration: false,
          sync: (guard) async {
            strictLoads++;
            return h.action.syncSubscriptionProfileBytes(
              Uint8List.fromList([2]),
              sourceId: 'fengwo-v2://fixture/account',
              isCurrent: guard,
              loader: (profile, _) =>
                  h.action.loadProfileUpdate(profile, isCurrent: guard),
            );
          },
        );
        expect(strictLoads, 0);
        release.complete();
        await Future.wait([loose, strict]);
        expect(strictLoads, registered ? 1 : 0);
      },
    );
  }

  test(
    'null and failed callbacks are never successful cache entries',
    () async {
      final h = await _Harness.create();
      await h.action.runAuthenticatedSubscriptionSync(
        h.session,
        allowTokenRegistration: true,
        sync: (_) async => null,
      );
      await expectLater(
        h.action.runAuthenticatedSubscriptionSync(
          h.session,
          allowTokenRegistration: true,
          sync: (_) async => throw StateError('controlled'),
        ),
        throwsStateError,
      );
      await h.login();
      expect(h.action.downloads, 1);
    },
  );
}

Future<Profile?> _syncWithDownloadedFile(_Harness h, {required bool useV2}) =>
    useV2
    ? h.action.runAuthenticatedSubscriptionSync(
        h.session,
        allowTokenRegistration: false,
        sync: (guard) => h.action.syncSubscriptionProfileBytes(
          Uint8List.fromList([1]),
          sourceId: 'fengwo-v2://fixture/replacement',
          replacingUrl: h.profile.url,
          isCurrent: guard,
          loader: (profile, _) async {
            await h.file.writeAsString('validated-v2');
            return profile.copyWith(lastUpdateDate: h.action.now);
          },
        ),
      )
    : h.login();

class _Harness {
  _Harness(this.session, this.profile, this.action, this.setup, this.container);
  final XboardLoginResult session;
  final Profile profile;
  final _Action action;
  final _Setup setup;
  final ProviderContainer container;
  late File file;

  static Future<_Harness> create({
    bool realProfiles = false,
    String? existingReplacementSource,
  }) async {
    final session = _session('one');
    globalState.activateXboardSession(session);
    final profile = Profile.normal(url: session.legacySubscribeUrl.toString());
    final initialProfiles = [
      profile,
      if (existingReplacementSource != null)
        Profile.normal(url: existingReplacementSource),
    ];
    await XboardSessionStorage().setManagedProfileUrl(profile.url);
    if (realProfiles) await database.profilesDao.setAll(initialProfiles);
    final action = _Action();
    final setup = _Setup();
    final container = ProviderContainer(
      overrides: [
        profilesActionProvider.overrideWith(() => action),
        setupActionProvider.overrideWith(() => setup),
        if (!realProfiles)
          profilesProvider.overrideWith(() => _Profiles(initialProfiles)),
        currentProfileIdProvider.overrideWithBuild((_, _) => null),
        coreStatusProvider.overrideWithBuild((_, _) => CoreStatus.connected),
      ],
    );
    addTearDown(container.dispose);
    container.listen(currentProfileIdProvider, (_, _) {});
    if (realProfiles) {
      container.listen(profilesProvider, (_, _) {});
      await container.read(profilesStreamProvider.future);
    }
    container.read(profilesActionProvider.notifier);
    final h = _Harness(session, profile, action, setup, container);
    h.file = File(await appPath.getProfilePath(profile.id.toString()));
    return h;
  }

  Future<Profile?> login({
    bool forceRefresh = false,
    bool allowTokenRegistration = true,
    Future<void> Function(Profile, bool Function())? onReuse,
  }) => action.runAuthenticatedSubscriptionSync(
    session,
    allowTokenRegistration: allowTokenRegistration,
    forceRefresh: forceRefresh,
    onReuse: onReuse,
    sync: (guard) => action.syncSubscriptionProfile(
      session.legacySubscribeUrl.toString(),
      isCurrent: guard,
      loader: (profile) => action.loadProfileUpdate(profile, isCurrent: guard),
    ),
  );
}

class _Action extends ProfilesAction {
  DateTime now = DateTime.utc(2026, 10, 25);
  int downloads = 0;
  Future<void> Function()? beforeDownload;
  @override
  DateTime get profileUpdateNow => now;
  @override
  int profileUpdateJitterSeconds(int maximum) => 0;
  @override
  Future<Profile> loadProfileUpdate(
    Profile profile, {
    bool Function()? isCurrent,
  }) async {
    final count = ++downloads;
    await beforeDownload?.call();
    if (isCurrent?.call() == false) throw StateError('superseded');
    final file = File(await appPath.getProfilePath(profile.id.toString()));
    await file.parent.create(recursive: true);
    await file.writeAsString('validated-$count');
    return profile.copyWith(lastUpdateDate: now);
  }
}

class _Profiles extends Profiles {
  _Profiles(this.initial);
  final List<Profile> initial;
  Future<void> Function(Profile) persist = (_) async {};
  @override
  List<Profile> build() {
    ref.listen(currentProfileIdProvider, (_, _) {});
    return initial;
  }

  @override
  Future<void> persistProfile(Profile profile) => persist(profile);

  @override
  void put(Profile profile) =>
      state = [...state.where((p) => p.id != profile.id), profile];
  @override
  Future<void> del(int id) async =>
      state = state.where((p) => p.id != id).toList();
}

class _Setup extends SetupAction {
  int applications = 0;
  Future<void> Function()? afterApply;
  @override
  Future<void> applyProfile({
    bool silence = false,
    bool force = false,
    Future<void> Function()? preloadInvoke,
    bool Function()? isCurrent,
    bool propagateErrors = false,
    Profile? profileOverride,
  }) async {
    if (isCurrent?.call() == false) throw StateError('superseded');
    applications++;
    await afterApply?.call();
  }

  @override
  void applyProfileDebounce({bool silence = false, bool force = false}) {}
}

class _Paths extends PathProviderPlatform {
  _Paths(this.root);
  final String root;
  @override
  Future<String?> getTemporaryPath() async => root;
  @override
  Future<String?> getApplicationSupportPath() async => root;
  @override
  Future<String?> getApplicationCachePath() async => root;
}

XboardLoginResult _session(String account) => XboardLoginResult(
  endpoint: Uri.parse('https://api.example'),
  token: account,
  authData: 'Bearer $account',
  isAdmin: false,
  subscription: XboardSubscriptionData(
    endpoint: Uri.parse('https://api.example'),
    subscribeUrl: Uri.parse('https://api.example/s/managed?flag=clash'),
    uploadBytes: 0,
    downloadBytes: 0,
    transferEnableBytes: 100,
    rawData: const {},
  ),
);

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/common/windows_identity.dart';
import 'package:fl_clash/database/database.dart' show database;
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/action.dart';
import 'package:fl_clash/providers/app.dart';
import 'package:fl_clash/providers/config.dart';
import 'package:fl_clash/providers/database.dart';
import 'package:fl_clash/state.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
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
    'rule-account',
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
        case 'rule-account':
          globalState.xboardRuleAccountKey = 'new-rule-account';
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

class _Harness {
  _Harness(this.session, this.profile, this.action, this.setup, this.container);
  final XboardLoginResult session;
  final Profile profile;
  final _Action action;
  final _Setup setup;
  final ProviderContainer container;
  late File file;

  static Future<_Harness> create() async {
    final session = _session('one');
    globalState.activateXboardSession(session);
    final profile = Profile.normal(url: session.legacySubscribeUrl.toString());
    await XboardSessionStorage().setManagedProfileUrl(profile.url);
    final action = _Action();
    final setup = _Setup();
    final container = ProviderContainer(
      overrides: [
        profilesActionProvider.overrideWith(() => action),
        setupActionProvider.overrideWith(() => setup),
        profilesProvider.overrideWith(() => _Profiles([profile])),
        currentProfileIdProvider.overrideWithBuild((_, _) => null),
        coreStatusProvider.overrideWithBuild((_, _) => CoreStatus.connected),
      ],
    );
    addTearDown(container.dispose);
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
      ruleAccountKey: globalState.xboardRuleAccountKey,
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
  @override
  List<Profile> build() {
    ref.listen(currentProfileIdProvider, (_, _) {});
    return initial;
  }

  @override
  void put(Profile profile) =>
      state = [...state.where((p) => p.id != profile.id), profile];
  @override
  Future<void> del(int id) async =>
      state = state.where((p) => p.id != id).toList();
}

class _Setup extends SetupAction {
  int applications = 0;
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
  Future<String?> getApplicationSupportPath() async {
    final directory = Directory(
      p.join(root, windowsDataCompany, windowsDataProduct),
    );
    await directory.create(recursive: true);
    return directory.path;
  }

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

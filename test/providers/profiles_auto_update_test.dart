import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/common/xboard_api_request.dart';
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
    directory = await Directory.systemTemp.createTemp('profiles_auto_update');
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
    'offline automatic entry never downloads even without a session',
    () async {
      final h = _Harness();
      globalState.setOfflineMode(true);
      await h.action.autoUpdateProfiles();
      expect(h.action.loaded, isEmpty);
      globalState.setOfflineMode(false);
      await h.action.autoUpdateProfiles();
      expect(h.action.loaded, hasLength(1));
    },
  );

  test('background automatic scans defer inactive profiles only', () async {
    final h = _Harness(profiles: [_profile(1), _profile(2)]);
    h.action.available = false;
    h.container.read(currentProfileIdProvider.notifier).value = 1;
    await h.action.autoUpdateProfiles();
    expect(h.action.loaded.map((profile) => profile.id), [1]);
    h.action.available = true;
    await h.action.autoUpdateProfiles();
    expect(h.action.loaded.map((profile) => profile.id), [1, 2]);
  });

  test('manual refresh bypasses a background automatic gate', () async {
    final h = _Harness();
    h.action.available = false;
    await h.action.autoUpdateProfiles();
    expect(h.action.loaded, isEmpty);
    await h.action.updateProfile(h.profiles.single);
    expect(h.action.loaded, hasLength(1));
  });

  for (final selected in [false, true]) {
    test(
      'suspension preserves only selected automatic work: $selected',
      () async {
        final h = _Harness();
        if (selected) {
          h.container.read(currentProfileIdProvider.notifier).value = 1;
        }
        final entered = Completer<void>();
        final release = Completer<void>();
        h.action.loader = (profile, current) async {
          entered.complete();
          await release.future;
          if (current?.call() == false) {
            throw const XboardApiRequestDeferred();
          }
          return profile.copyWith(lastUpdateDate: h.clock.now);
        };
        final automatic = h.action.autoUpdateProfiles();
        await entered.future;
        h.action.available = false;
        h.action.available = true;
        release.complete();
        await automatic;
        expect(h.profiles.single.lastUpdateDate, selected ? h.clock.now : null);
        h.action.loader = null;
        await h.action.autoUpdateProfiles();
        expect(h.action.loaded, hasLength(selected ? 1 : 2));
        expect(h.profiles.single.lastUpdateDate, h.clock.now);
      },
    );
  }

  test(
    'background deferral does not create automatic failure cooling',
    () async {
      final h = _Harness();
      final entered = Completer<void>();
      final release = Completer<void>();
      h.action.loader = (profile, current) async {
        entered.complete();
        await release.future;
        if (current?.call() == false) {
          throw const XboardApiRequestDeferred();
        }
        return profile.copyWith(lastUpdateDate: h.clock.now);
      };
      final automatic = h.action.autoUpdateProfiles();
      await entered.future;
      h.action.available = false;
      release.complete();
      await automatic;
      expect(h.profiles.single.lastUpdateDate, isNull);
      h.action.available = true;
      h.action.loader = null;
      await h.action.autoUpdateProfiles();
      expect(h.action.loaded, hasLength(2));
      expect(h.profiles.single.lastUpdateDate, h.clock.now);
    },
  );

  test(
    'automatic updates preserve disabled, file and daily freshness rules',
    () async {
      final clock = _Clock();
      final h = _Harness(
        clock: clock,
        profiles: [
          _profile(1).copyWith(lastUpdateDate: clock.now),
          _profile(2).copyWith(autoUpdate: false),
          _profile(3).copyWith(url: ''),
        ],
      );
      await h.action.autoUpdateProfiles();
      clock.advance(const Duration(days: 1) - const Duration(milliseconds: 1));
      await h.action.autoUpdateProfiles();
      expect(h.action.loaded, isEmpty);
      clock.advance(const Duration(milliseconds: 1));
      await h.action.autoUpdateProfiles();
      expect(h.action.loaded.map((p) => p.id), [1]);
    },
  );

  test(
    'each failed source backs off from twenty minutes to six hours',
    () async {
      final h = _Harness();
      h.action.loader = (_, _) async => throw StateError('controlled outage');
      await h.action.autoUpdateProfiles();
      var calls = 1;
      for (final minutes in [20, 40, 80, 160, 320, 360, 360]) {
        h.clock.advance(
          Duration(minutes: minutes) - const Duration(milliseconds: 1),
        );
        await h.action.autoUpdateProfiles();
        expect(h.action.loaded, hasLength(calls));
        h.clock.advance(const Duration(milliseconds: 1));
        await h.action.autoUpdateProfiles();
        expect(h.action.loaded, hasLength(++calls));
      }
    },
  );

  test(
    'jitter delays automatic retry without exceeding the six hour cap',
    () async {
      final h = _Harness();
      h.action.jitter = 60;
      h.action.loader = (_, _) async => throw StateError('controlled outage');
      await h.action.autoUpdateProfiles();
      for (final minutes in [20, 40, 80, 160, 320]) {
        final count = h.action.loaded.length;
        h.clock.advance(Duration(minutes: minutes));
        await h.action.autoUpdateProfiles();
        expect(h.action.loaded, hasLength(count));
        h.clock.advance(const Duration(minutes: 1));
        await h.action.autoUpdateProfiles();
        expect(h.action.loaded, hasLength(count + 1));
      }
      final count = h.action.loaded.length;
      h.clock.advance(const Duration(hours: 6));
      await h.action.autoUpdateProfiles();
      expect(h.action.loaded, hasLength(count + 1));
    },
  );

  test(
    'manual success bypasses cooldown and resets later failure backoff',
    () async {
      final h = _Harness();
      h.action.loader = (_, _) async => throw StateError('controlled outage');
      await h.action.autoUpdateProfiles();
      h.action.loader = null;
      await h.action.updateProfile(h.profiles.single);
      expect(h.action.loaded, hasLength(2));
      h.clock.advance(const Duration(days: 1));
      h.action.loader = (_, _) async => throw StateError('controlled outage');
      await h.action.autoUpdateProfiles();
      h.clock.advance(const Duration(minutes: 20));
      await h.action.autoUpdateProfiles();
      expect(h.action.loaded, hasLength(4));
    },
  );

  test(
    'source and account changes do not inherit another retry cooldown',
    () async {
      globalState.activateXboardSession(_session('one'));
      final h = _Harness(profiles: [_profile(1), _profile(2)]);
      h.action.loader = (_, _) async => throw StateError('controlled outage');
      await h.action.autoUpdateProfiles();
      expect(h.action.loaded, hasLength(2));
      h.put(h.profiles.first.copyWith(url: 'https://changed.example/profile'));
      await h.action.autoUpdateProfiles();
      expect(h.action.loaded, hasLength(3));
      globalState.activateXboardSession(_session('two'));
      await h.action.autoUpdateProfiles();
      expect(h.action.loaded, hasLength(5));
    },
  );

  test(
    'clock rollback cannot preserve failure cooldown indefinitely',
    () async {
      final h = _Harness();
      h.action.loader = (_, _) async => throw StateError('controlled outage');
      await h.action.autoUpdateProfiles();
      h.clock.advance(const Duration(seconds: -1));
      await h.action.autoUpdateProfiles();
      expect(h.action.loaded, hasLength(2));
    },
  );

  for (final manualFirst in [false, true]) {
    test(
      'automatic and manual updates share one active download ($manualFirst)',
      () async {
        final h = _Harness();
        final entered = Completer<void>();
        final result = Completer<Profile>();
        h.action.loader = (profile, _) {
          entered.complete();
          return result.future;
        };
        final first = manualFirst
            ? h.action.updateProfile(h.profiles.single)
            : h.action.autoUpdateProfiles();
        await entered.future;
        final second = h.action.autoUpdateProfiles();
        final third = h.action.updateProfile(
          h.profiles.single,
          showLoading: true,
        );
        expect(h.action.loaded, hasLength(1));
        result.complete(
          h.profiles.single.copyWith(lastUpdateDate: h.clock.now),
        );
        await Future.wait([first, second, third]);
        expect(h.action.loaded, hasLength(1));
        expect(
          h.container.read(isUpdatingProvider(h.profiles.single.updatingKey)),
          isFalse,
        );
      },
    );
  }

  for (final change in ['fresh', 'disabled']) {
    test('manual intent upgrades queued automatic work ($change)', () async {
      final h = _Harness(profiles: [_profile(2), _profile(1)]);
      final entered = Completer<void>();
      final result = Completer<Profile>();
      h.action.loader = (profile, _) {
        if (profile.id == 1) {
          entered.complete();
          return result.future;
        }
        return Future.value(profile.copyWith(lastUpdateDate: h.clock.now));
      };
      final blocking = h.action.updateProfile(h.profiles.last);
      await entered.future;
      final automatic = h.action.autoUpdateProfiles();
      final manual = h.action.updateProfile(h.profiles.first);
      final queued = h.profiles.first;
      h.put(
        change == 'fresh'
            ? queued.copyWith(lastUpdateDate: h.clock.now)
            : queued.copyWith(autoUpdate: false),
      );
      result.complete(h.profiles.last.copyWith(lastUpdateDate: h.clock.now));
      await Future.wait([blocking, automatic, manual]);
      expect(h.action.loaded.map((profile) => profile.id), [1, 2]);
      expect(h.profiles.first.lastUpdateDate, h.clock.now);
      if (change == 'disabled') expect(h.profiles.first.autoUpdate, isFalse);
    });
  }

  for (final change in ['fresh', 'disabled', 'deleted', 'source']) {
    test(
      'queued automatic work rechecks the latest profile ($change)',
      () async {
        final h = _Harness(profiles: [_profile(2), _profile(1)]);
        final entered = Completer<void>();
        final result = Completer<Profile>();
        h.action.loader = (profile, _) {
          entered.complete();
          return result.future;
        };
        final blocking = h.action.updateProfile(h.profiles.last);
        await entered.future;
        final automatic = h.action.autoUpdateProfiles();
        final queued = h.profiles.first;
        switch (change) {
          case 'fresh':
            h.put(queued.copyWith(lastUpdateDate: h.clock.now));
          case 'disabled':
            h.put(queued.copyWith(autoUpdate: false));
          case 'deleted':
            await h.container.read(profilesProvider.notifier).del(queued.id);
          case 'source':
            h.put(queued.copyWith(url: 'https://replacement.example/profile'));
        }
        result.complete(h.profiles.last.copyWith(lastUpdateDate: h.clock.now));
        await Future.wait([blocking, automatic]);
        expect(h.action.loaded.map((p) => p.id), [1]);
        if (change == 'source') {
          h.action.loader = null;
          await h.action.autoUpdateProfiles();
          expect(
            h.action.loaded.last.url,
            'https://replacement.example/profile',
          );
        }
      },
    );
  }

  test(
    'queue entry rechecks offline mode and leaves remaining profiles idle',
    () async {
      final h = _Harness(profiles: [_profile(2), _profile(1)]);
      final entered = Completer<void>();
      final result = Completer<Profile>();
      h.action.loader = (profile, _) {
        entered.complete();
        return result.future;
      };
      final blocking = h.action.updateProfile(h.profiles.last);
      final rejected = expectLater(blocking, throwsStateError);
      await entered.future;
      final automatic = h.action.autoUpdateProfiles();
      globalState.setOfflineMode(true);
      result.complete(h.profiles.last.copyWith(lastUpdateDate: h.clock.now));
      await Future.wait([rejected, automatic]);
      expect(h.action.loaded.map((p) => p.id), [1]);
      globalState.setOfflineMode(false);
      h.action.loader = null;
      await h.action.autoUpdateProfiles();
      expect(h.action.loaded.map((p) => p.id), [1, 2, 1]);
    },
  );

  for (final change in ['source', 'source_back', 'deleted', 'logout']) {
    test(
      'late downloads cannot revive stale profile or account state ($change)',
      () async {
        globalState.activateXboardSession(_session('one'));
        final h = _Harness();
        final original = h.profiles.single;
        final file = File(await appPath.getProfilePath(original.id.toString()));
        await file.safeWriteAsBytes([1, 2, 3]);
        final entered = Completer<void>();
        final release = Completer<void>();
        h.action.loader = (profile, _) async {
          entered.complete();
          await release.future;
          await file.safeWriteAsBytes([9, 9, 9]);
          return profile.copyWith(lastUpdateDate: h.clock.now);
        };
        final updating = h.action.autoUpdateProfiles();
        await entered.future;
        switch (change) {
          case 'source':
            h.put(original.copyWith(url: 'https://new.example/profile'));
          case 'source_back':
            h.put(original.copyWith(url: 'https://new.example/profile'));
            h.put(original);
          case 'deleted':
            await h.container.read(profilesProvider.notifier).del(original.id);
          case 'logout':
            globalState.clearXboardSession();
            globalState.activateXboardSession(_session('one'));
        }
        release.complete();
        await updating;
        if (change == 'deleted') {
          expect(h.profiles, isEmpty);
          expect(await file.exists(), isFalse);
        } else {
          expect(h.profiles.single.lastUpdateDate, isNull);
          expect(await file.readAsBytes(), [1, 2, 3]);
        }
      },
    );
  }

  test('same-auth metadata changes preserve a valid ongoing update', () async {
    globalState.activateXboardSession(_session('one'));
    final h = _Harness();
    final entered = Completer<void>();
    final result = Completer<Profile>();
    h.action.loader = (profile, _) {
      entered.complete();
      return result.future;
    };
    final updating = h.action.autoUpdateProfiles();
    await entered.future;
    globalState.activateXboardSession(_session('one'));
    h.put(
      h.profiles.single.copyWith(
        label: 'new label',
        selectedMap: {'Proxy': 'new node'},
      ),
    );
    result.complete(h.profiles.single.copyWith(lastUpdateDate: h.clock.now));
    await updating;
    expect(h.profiles.single.lastUpdateDate, h.clock.now);
    expect(h.profiles.single.label, 'new label');
    expect(h.profiles.single.selectedMap, {'Proxy': 'new node'});
  });

  test(
    'login and payment profile sync bypass automatic failure cooldown',
    () async {
      final h = _Harness();
      h.action.loader = (_, _) async => throw StateError('controlled outage');
      await h.action.autoUpdateProfiles();
      var called = false;
      await expectLater(
        h.action.syncSubscriptionProfile(
          h.profiles.single.url,
          loader: (profile) async {
            called = true;
            throw StateError('explicit sync reached downloader');
          },
        ),
        throwsStateError,
      );
      expect(called, isTrue);
      await h.action.autoUpdateProfiles();
      expect(h.action.loaded, hasLength(1));
    },
  );

  test(
    'manual V2 updates use fresh scoped exchanges after automatic failure',
    () async {
      final session = _session('one');
      globalState.activateXboardSession(session);
      final profile = _profile(100).copyWith(url: 'fengwo-v2://key/account');
      await XboardSessionStorage().setManagedProfileUrl(profile.url);
      final h = _Harness(profiles: [profile]);
      h.action.v2Loader = (_) async => throw StateError('controlled outage');
      await h.action.autoUpdateProfiles();
      await expectLater(h.action.updateProfile(profile), throwsStateError);
      expect(h.action.v2ForceModes, [false, true]);
      expect(h.action.v2Scopes, everyElement(isNotNull));
      expect(identical(h.action.v2Scopes[0], h.action.v2Scopes[1]), isFalse);
    },
  );

  for (final change in ['logout', 'source', 'deleted']) {
    test('late V2 bytes are rejected before saving ($change)', () async {
      globalState.activateXboardSession(_session('one'));
      final h = _Harness(
        profiles: [_profile(100).copyWith(url: 'fengwo-v2://key/account')],
      );
      final entered = Completer<void>();
      final result = Completer<SubscriptionV2Profile?>();
      h.action.v2Loader = (_) {
        entered.complete();
        return result.future;
      };
      final updating = h.action.autoUpdateProfiles();
      await entered.future;
      switch (change) {
        case 'logout':
          globalState.clearXboardSession();
        case 'source':
          h.put(h.profiles.single.copyWith(url: 'fengwo-v2://key/new-account'));
        case 'deleted':
          await h.container.read(profilesProvider.notifier).del(100);
      }
      result.complete(
        SubscriptionV2Profile(
          bytes: Uint8List.fromList([9]),
          sourceId: 'fengwo-v2://key/account',
        ),
      );
      await updating;
      expect(h.profiles.every((p) => p.lastUpdateDate == null), isTrue);
      expect(await File(await appPath.getProfilePath('100')).exists(), isFalse);
    });
  }
}

Profile _profile(int id) => Profile(
  id: id,
  label: 'Profile $id',
  url: 'https://import.example/profile-$id',
  autoUpdateDuration: const Duration(days: 1),
);

class _Clock {
  DateTime now = DateTime.utc(2026, 10, 25);
  void advance(Duration duration) => now = now.add(duration);
}

class _Harness {
  _Harness({List<Profile>? profiles, _Clock? clock})
    : clock = clock ?? _Clock() {
    action = _Action(this.clock);
    container = ProviderContainer(
      overrides: [
        profilesActionProvider.overrideWith(() => action),
        setupActionProvider.overrideWith(_SetupAction.new),
        profilesProvider.overrideWith(
          () => _Profiles(profiles ?? [_profile(1)]),
        ),
        currentProfileIdProvider.overrideWithBuild((_, _) => null),
        coreStatusProvider.overrideWithBuild((_, _) => CoreStatus.connected),
      ],
    );
    addTearDown(container.dispose);
    container.read(profilesActionProvider.notifier);
    container.listen(currentProfileIdProvider, (_, _) {});
  }
  final _Clock clock;
  late final _Action action;
  late final ProviderContainer container;
  List<Profile> get profiles => container.read(profilesProvider);
  void put(Profile profile) =>
      container.read(profilesProvider.notifier).put(profile);
}

class _Action extends ProfilesAction {
  _Action(this.clock);
  final _Clock clock;
  int jitter = 0;
  bool _available = true;
  int activityRevision = 0;
  bool get available => _available;
  set available(bool value) {
    if (_available && !value) activityRevision++;
    _available = value;
  }

  final loaded = <Profile>[];
  final v2ForceModes = <bool>[];
  final v2Scopes = <Object?>[];
  Future<Profile> Function(Profile, bool Function()?)? loader;
  Future<SubscriptionV2Profile?> Function(XboardLoginResult)? v2Loader;
  @override
  DateTime get profileUpdateNow => clock.now;
  @override
  int profileUpdateJitterSeconds(int maximum) => jitter;
  @override
  bool get canAutomaticallyReadProfiles => available;
  @override
  int get automaticProfileRequestRevision => activityRevision;
  @override
  Future<Profile> loadProfileUpdate(
    Profile profile, {
    bool Function()? isCurrent,
  }) async {
    loaded.add(profile);
    return loader == null
        ? profile.copyWith(lastUpdateDate: clock.now)
        : await loader!(profile, isCurrent);
  }

  @override
  Future<SubscriptionV2Profile?> loadSubscriptionV2Profile(
    XboardLoginResult session, {
    bool forceRefresh = false,
    Object? requestScope,
    bool Function()? canRequest,
  }) {
    v2ForceModes.add(forceRefresh);
    v2Scopes.add(requestScope);
    return v2Loader!(session);
  }
}

class _Profiles extends Profiles {
  _Profiles(this.initial);
  final List<Profile> initial;
  @override
  List<Profile> build() => initial;
  @override
  void put(Profile profile) => state = [
    for (final previous in state)
      if (previous.id == profile.id) profile else previous,
  ];
  @override
  Future<void> del(int id) async =>
      state = state.where((p) => p.id != id).toList();
}

class _SetupAction extends SetupAction {
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

import 'dart:async';
import 'dart:io';

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/common/post_login_profile_sync.dart';
import 'package:fl_clash/common/windows_identity.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/action.dart';
import 'package:fl_clash/providers/app.dart';
import 'package:fl_clash/providers/database.dart';
import 'package:fl_clash/state.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:riverpod/riverpod.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  setUpAll(() async {
    directory = await Directory.systemTemp.createTemp('post_login_sync');
    PathProviderPlatform.instance = _Paths(directory.path);
  });
  setUp(() {
    globalState.clearXboardSession();
    globalState.setOfflineMode(false);
  });
  tearDown(() {
    globalState.clearXboardSession();
    globalState.setOfflineMode(false);
  });
  tearDownAll(() async {
    await commonPrint.flushDiagnosticEvents();
    await directory.delete(recursive: true);
  });

  for (final initiallyOffline in [false, true]) {
    test('normal login enters the real profile action online before first sync '
        '(previous offline=$initiallyOffline)', () async {
      globalState.setOfflineMode(initiallyOffline);
      final session = _session();
      final revision = globalState.activateXboardSession(session);
      final profile = Profile.normal(url: 'fengwo-v2://fixture/current');
      final container = ProviderContainer(
        overrides: [profilesProvider.overrideWith(() => _Profiles(profile))],
      );
      addTearDown(container.dispose);
      final action = container.read(profilesActionProvider.notifier);
      final coordinator = PostLoginProfileSyncCoordinator();
      var downloads = 0;
      final result = await coordinator.run(
        sessionRevision: revision,
        isCurrent: () => globalState.isActiveXboardSession(session, revision),
        enterOnline: () => globalState.setOfflineMode(false),
        sync: (isCurrent) async {
          final synced = await action.runAuthenticatedSubscriptionSync(
            session,
            allowTokenRegistration: false,
            sourceProfile: profile,
            isCurrent: isCurrent,
            sync: (guard) async {
              expect(guard(), isTrue);
              expect(globalState.isOfflineMode, isFalse);
              downloads++;
              return profile;
            },
          );
          return synced != null;
        },
      );

      expect(result, isTrue);
      expect(downloads, 1);
      expect(globalState.isOfflineMode, isFalse);
      expect(globalState.isActiveXboardSession(session, revision), isTrue);
    });
  }

  test(
    'one revision shares in-flight work and remembers a successful sync',
    () async {
      final coordinator = PostLoginProfileSyncCoordinator();
      final completed = Completer<bool>();
      var calls = 0;
      Future<bool> run() => coordinator.run(
        sessionRevision: 1,
        isCurrent: () => true,
        enterOnline: () {},
        sync: (_) {
          calls++;
          return completed.future;
        },
      );
      final first = run();
      final duplicate = run();
      expect(identical(first, duplicate), isTrue);
      expect(calls, 1);
      completed.complete(true);
      expect(await first, isTrue);
      expect(await run(), isTrue);
      expect(calls, 1);
    },
  );

  test(
    'an incomplete first sync can retry without duplicate in-flight work',
    () async {
      final coordinator = PostLoginProfileSyncCoordinator();
      var calls = 0;
      Future<bool> run() => coordinator.run(
        sessionRevision: 1,
        isCurrent: () => true,
        enterOnline: () {},
        sync: (_) async => ++calls > 1,
      );
      expect(await run(), isFalse);
      final retry = run();
      final duplicate = run();
      expect(identical(retry, duplicate), isTrue);
      expect(await retry, isTrue);
      expect(calls, 2);
      expect(await run(), isTrue);
      expect(calls, 2);
    },
  );

  test(
    'a failed sync permits retry and diagnostics contain only gate reasons',
    () async {
      final coordinator = PostLoginProfileSyncCoordinator();
      final reasons = <String>[];
      var calls = 0;
      Future<bool> run() => coordinator.run(
        sessionRevision: 1,
        isCurrent: () => true,
        enterOnline: () {},
        sync: (_) async {
          if (++calls == 1) throw StateError('private fixture detail');
          return true;
        },
        onDiagnostic: reasons.add,
      );
      await expectLater(run(), throwsStateError);
      expect(await run(), isTrue);
      expect(calls, 2);
      expect(reasons, ['started', 'failed', 'started', 'completed']);
    },
  );

  test('a stale login neither exits offline mode nor starts work', () async {
    final coordinator = PostLoginProfileSyncCoordinator();
    var onlineTransitions = 0;
    var calls = 0;
    expect(
      await coordinator.run(
        sessionRevision: 1,
        isCurrent: () => false,
        enterOnline: () => onlineTransitions++,
        sync: (_) async {
          calls++;
          return true;
        },
      ),
      isFalse,
    );
    expect(onlineTransitions, 0);
    expect(calls, 0);
  });

  test(
    'session replacement during online transition cannot start old work',
    () async {
      final coordinator = PostLoginProfileSyncCoordinator();
      var current = true;
      var calls = 0;
      expect(
        await coordinator.run(
          sessionRevision: 1,
          isCurrent: () => current,
          enterOnline: () => current = false,
          sync: (_) async {
            calls++;
            return true;
          },
        ),
        isFalse,
      );
      expect(calls, 0);
    },
  );

  for (final clear in [false, true]) {
    test(
      'late old work cannot finish a newer session (cancel=$clear)',
      () async {
        final coordinator = PostLoginProfileSyncCoordinator();
        final oldResult = Completer<bool>();
        final newResult = Completer<bool>();
        var revision = 1;
        late bool Function() oldCurrent;
        final first = coordinator.run(
          sessionRevision: 1,
          isCurrent: () => revision == 1,
          enterOnline: () {},
          sync: (isCurrent) {
            oldCurrent = isCurrent;
            return oldResult.future;
          },
        );
        if (clear) coordinator.cancel();
        revision = 2;
        final next = coordinator.run(
          sessionRevision: 2,
          isCurrent: () => revision == 2,
          enterOnline: () {},
          sync: (_) => newResult.future,
        );
        expect(oldCurrent(), isFalse);
        oldResult.complete(true);
        expect(await first, isFalse);
        newResult.complete(true);
        expect(await next, isTrue);
        var duplicateStarted = false;
        expect(
          await coordinator.run(
            sessionRevision: 2,
            isCurrent: () => revision == 2,
            enterOnline: () {},
            sync: (_) async {
              duplicateStarted = true;
              return true;
            },
          ),
          isTrue,
        );
        expect(duplicateStarted, isFalse);
      },
    );
  }

  test(
    'logout invalidates an active sync even before session cleanup',
    () async {
      final coordinator = PostLoginProfileSyncCoordinator();
      final result = Completer<bool>();
      late bool Function() active;
      final pending = coordinator.run(
        sessionRevision: 1,
        isCurrent: () => true,
        enterOnline: () {},
        sync: (isCurrent) {
          active = isCurrent;
          return result.future;
        },
      );
      coordinator.cancel();
      expect(active(), isFalse);
      result.complete(true);
      expect(await pending, isFalse);
    },
  );

  test(
    'identity replacement at the same revision cannot reuse old work',
    () async {
      final coordinator = PostLoginProfileSyncCoordinator();
      final session = _session();
      final revision = globalState.activateXboardSession(session);
      final oldResult = Completer<bool>();
      final first = coordinator.run(
        sessionRevision: revision,
        isCurrent: () => globalState.isActiveXboardSession(session, revision),
        enterOnline: () => globalState.setOfflineMode(false),
        sync: (_) => oldResult.future,
      );
      final replacement = _session();
      globalState.xboardSession = replacement;
      var replacementCalls = 0;
      final second = coordinator.run(
        sessionRevision: revision,
        isCurrent: () =>
            globalState.isActiveXboardSession(replacement, revision),
        enterOnline: () => globalState.setOfflineMode(false),
        sync: (_) async {
          replacementCalls++;
          return true;
        },
      );
      expect(await second, isTrue);
      expect(replacementCalls, 1);
      oldResult.complete(true);
      expect(await first, isFalse);
    },
  );

  test('a late failure cannot clear the newer in-flight operation', () async {
    final coordinator = PostLoginProfileSyncCoordinator();
    final oldResult = Completer<bool>();
    final newResult = Completer<bool>();
    var revision = 1;
    final first = coordinator.run(
      sessionRevision: 1,
      isCurrent: () => revision == 1,
      enterOnline: () {},
      sync: (_) => oldResult.future,
    );
    final firstFailure = expectLater(first, throwsStateError);
    revision = 2;
    var calls = 0;
    Future<bool> runCurrent() => coordinator.run(
      sessionRevision: 2,
      isCurrent: () => revision == 2,
      enterOnline: () {},
      sync: (_) {
        calls++;
        return newResult.future;
      },
    );
    final second = runCurrent();
    oldResult.completeError(StateError('old failure'));
    await firstFailure;
    expect(identical(runCurrent(), second), isTrue);
    expect(calls, 1);
    newResult.complete(true);
    expect(await second, isTrue);
  });

  testWidgets('a stale session still releases its own loading state', (
    tester,
  ) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final provider = loadingProvider(LoadingTag.subscriptionProfile);
    final loading = container.read(provider.notifier);
    final coordinator = PostLoginProfileSyncCoordinator();
    final result = Completer<bool>();
    var current = true;
    final pending = coordinator.run(
      sessionRevision: 1,
      isCurrent: () => current,
      enterOnline: () {},
      onStarted: loading.start,
      onSettled: loading.stop,
      sync: (_) => result.future,
    );
    expect(container.read(provider), isTrue);
    current = false;
    result.complete(true);
    expect(await pending, isFalse);
    await tester.pump(const Duration(seconds: 1));
    expect(container.read(provider), isFalse);
  });

  testWidgets('old completion cannot stop loading owned by a newer login', (
    tester,
  ) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final provider = loadingProvider(LoadingTag.subscriptionProfile);
    final loading = container.read(provider.notifier);
    final coordinator = PostLoginProfileSyncCoordinator();
    final oldResult = Completer<bool>();
    final newResult = Completer<bool>();
    var revision = 1;
    Future<bool> run(int expected, Completer<bool> result) => coordinator.run(
      sessionRevision: expected,
      isCurrent: () => revision == expected,
      enterOnline: () {},
      onStarted: loading.start,
      onSettled: loading.stop,
      sync: (_) => result.future,
    );
    final first = run(1, oldResult);
    revision = 2;
    final second = run(2, newResult);
    oldResult.complete(true);
    expect(await first, isFalse);
    await tester.pump(const Duration(seconds: 1));
    expect(container.read(provider), isTrue);
    newResult.complete(true);
    expect(await second, isTrue);
    await tester.pump(const Duration(seconds: 1));
    expect(container.read(provider), isFalse);
  });

  test(
    'retry waits for failed attempt cleanup before taking ownership',
    () async {
      final coordinator = PostLoginProfileSyncCoordinator();
      final cleaning = Completer<void>();
      final cleanupStarted = Completer<void>();
      var calls = 0;
      Future<bool> run() => coordinator.run(
        sessionRevision: 1,
        isCurrent: () => true,
        enterOnline: () {},
        sync: (_) async => ++calls > 1,
        onSettled: () async {
          if (calls != 1) return;
          cleanupStarted.complete();
          await cleaning.future;
        },
      );
      final first = run();
      await cleanupStarted.future;
      expect(identical(run(), first), isTrue);
      expect(calls, 1);
      cleaning.complete();
      expect(await first, isFalse);
      expect(await run(), isTrue);
      expect(calls, 2);
    },
  );
}

class _Profiles extends Profiles {
  _Profiles(this.profile);
  final Profile profile;

  @override
  List<Profile> build() => [profile];
}

class _Paths extends PathProviderPlatform {
  _Paths(this.root);
  final String root;

  @override
  Future<String?> getTemporaryPath() async => root;

  @override
  Future<String?> getApplicationSupportPath() async =>
      p.join(root, windowsDataCompany, windowsDataProduct);

  @override
  Future<String?> getApplicationCachePath() async => root;
}

XboardLoginResult _session() => XboardLoginResult(
  endpoint: Uri.parse('https://api.example'),
  token: 'fixture',
  authData: 'Bearer fixture',
  isAdmin: false,
  secureSubscription: true,
  subscription: XboardSubscriptionData(
    endpoint: Uri.parse('https://api.example'),
    subscribeUrl: Uri.parse('https://api.example/subscription'),
    email: 'fixture@example.invalid',
    planId: 1,
    transferEnableBytes: 1024,
    uploadBytes: 0,
    downloadBytes: 0,
    expiredAtEpochSeconds: null,
    resetDay: null,
    plan: null,
    rawData: const {'expired_at': null},
  ),
  rawData: const {},
);

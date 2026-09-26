import 'dart:async';
import 'dart:convert';

import 'package:fl_clash/common/xboard_auth.dart';
import 'package:fl_clash/common/xboard_routing_store.dart';
import 'package:fl_clash/common/xboard_session_storage.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/profile.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('round trips routing and preserves unrelated profile properties', () {
    const profile = Profile(
      id: 20,
      label: 'subscription',
      autoUpdateDuration: Duration(hours: 12),
      currentGroupName: 'GLOBAL',
      selectedMap: {'GLOBAL': 'US 02', 'Proxy': 'SG 01'},
      unfoldSet: {'Proxy'},
    );
    final snapshot = XboardRoutingSnapshot.fromProfile(Mode.global, profile);
    final decoded = XboardRoutingSnapshot.fromJson(
      jsonDecode(jsonEncode(snapshot.toJson())) as Map<String, dynamic>,
    );
    final updatedProfile = profile.copyWith(
      id: 30,
      label: 'new subscription',
      url: 'https://example.com/new',
      selectedMap: {'GLOBAL': 'HK 01'},
      currentGroupName: 'Proxy',
    );

    expect(decoded.mode, Mode.global);
    expect(
      decoded.applyTo(updatedProfile),
      updatedProfile.copyWith(
        selectedMap: profile.selectedMap,
        currentGroupName: profile.currentGroupName,
      ),
    );
  });

  test('copies mutable selections and exposes an immutable snapshot', () {
    final selections = {'GLOBAL': 'US 02'};
    final snapshot = XboardRoutingSnapshot(
      mode: Mode.global,
      selectedMap: selections,
    );
    selections['GLOBAL'] = 'HK 01';
    expect(snapshot.selectedMap, {'GLOBAL': 'US 02'});
    expect(
      () => snapshot.selectedMap['GLOBAL'] = 'HK 01',
      throwsUnsupportedError,
    );
  });

  test('keeps the global selection when another group has been cleared', () {
    final snapshot = XboardRoutingSnapshot(
      mode: Mode.global,
      selectedMap: {'GLOBAL': 'US 02', 'Auto': ''},
      currentGroupName: '',
    );
    final restored = XboardRoutingSnapshot.fromJson(
      jsonDecode(jsonEncode(snapshot.toJson())) as Map<String, dynamic>,
    );
    expect(restored.selectedMap, {'GLOBAL': 'US 02', 'Auto': ''});
    expect(restored.currentGroupName, isNull);
  });

  test('rejects malformed versions modes selections and group names', () {
    final valid = _snapshot('US 02').toJson();
    final invalid = <Map<String, Object?>>[
      {...valid, 'version': 2},
      {...valid, 'version': '1'},
      {...valid, 'version': 1.0},
      {...valid, 'mode': 'unknown'},
      {...valid, 'mode': 1},
      {...valid, 'selected_map': []},
      {
        ...valid,
        'selected_map': {'GLOBAL': 1},
      },
      {
        ...valid,
        'selected_map': {1: 'US 02'},
      },
      {
        ...valid,
        'selected_map': {' ': 'US 02'},
      },
      {...valid, 'current_group_name': 42},
      {...valid, 'unexpected': true},
    ];
    for (final json in invalid) {
      expect(
        () => XboardRoutingSnapshot.fromJson(json),
        throwsFormatException,
        reason: json.toString(),
      );
    }
  });

  test('isolates accounts and subscriptions across store restarts', () async {
    final first = _session(uuid: 'user-a', planId: 1);
    final otherAccount = _session(uuid: 'user-b', planId: 1);
    final otherPlan = _session(uuid: 'user-a', planId: 2);
    final store = XboardRoutingStore();
    await store.save(first, _snapshot('US 02'));
    await store.save(otherAccount, _snapshot('HK 01'));
    await store.save(otherPlan, _snapshot('SG 01', mode: Mode.rule));
    final restarted = XboardRoutingStore();

    expect((await restarted.load(first))?.selectedMap['GLOBAL'], 'US 02');
    expect(
      (await restarted.load(otherAccount))?.selectedMap['GLOBAL'],
      'HK 01',
    );
    expect((await restarted.load(otherPlan))?.selectedMap['GLOBAL'], 'SG 01');
    expect((await restarted.load(otherPlan))?.mode, Mode.rule);
  });

  test('UUID and plan scope survives token and endpoint rotation', () async {
    final original = _session();
    final rotated = _session(
      email: 'new-email@example.com',
      token: 'new-secret',
      endpoint: 'https://new-api.example.com',
      subscribeUrl: 'https://new-subscription.example.com/new-token',
    );
    final store = XboardRoutingStore();
    await store.save(original, _snapshot('US 02'));

    expect(
      XboardRoutingStore.scopeKey(rotated),
      XboardRoutingStore.scopeKey(original),
    );
    expect((await store.load(rotated))?.selectedMap['GLOBAL'], 'US 02');
    final offline = XboardOfflineCache(
      verifiedAt: DateTime(2026, 9, 24),
      subscription: original.subscription,
      nodes: const [],
      isAdmin: false,
    ).toSession();
    expect(offline.token, isEmpty);
    expect(
      XboardRoutingStore.scopeKey(offline),
      XboardRoutingStore.scopeKey(original),
    );
    expect((await store.load(offline))?.selectedMap['GLOBAL'], 'US 02');
  });

  test('normalizes fallback emails and prefers subscription plan ID', () {
    expect(
      XboardRoutingStore.scopeKey(
        _session(uuid: null, email: ' Member@Example.com ', planId: 3),
      ),
      XboardRoutingStore.scopeKey(
        _session(uuid: null, email: 'member@example.com', planId: 3),
      ),
    );
    expect(
      XboardRoutingStore.scopeKey(_session(planId: 3, nestedPlanId: 9)),
      XboardRoutingStore.scopeKey(_session(planId: null, nestedPlanId: 3)),
    );
  });

  test('uses URL only if plan identity is missing', () async {
    final first = _session(planId: null, subscribeUrl: 'https://sub/a');
    final second = _session(planId: null, subscribeUrl: 'https://sub/b');
    final store = XboardRoutingStore();
    await store.save(first, _snapshot('US 02'));
    expect((await store.load(first))?.selectedMap['GLOBAL'], 'US 02');
    expect(await store.load(second), isNull);
  });

  test(
    'does not save unscoped sessions or expose identity and tokens',
    () async {
      final store = XboardRoutingStore();
      final preferences = await SharedPreferences.getInstance();
      final noIdentity = _session(uuid: null, email: null);
      final noSubscription = _session(planId: null, subscribeUrl: null);
      for (final session in [noIdentity, noSubscription]) {
        expect(XboardRoutingStore.scopeKey(session), isNull);
        await store.save(session, _snapshot('US 02'));
        expect(await store.load(session), isNull);
      }
      expect(preferences.getKeys(), isEmpty);
      await store.save(_session(), _snapshot('US 02'));
      final key = preferences.getKeys().single;
      final persisted = '$key ${preferences.getString(key)}';
      for (final secret in [
        'account-uuid',
        'member@example.com',
        'private-token',
        'private-auth',
        'https://',
      ]) {
        expect(persisted, isNot(contains(secret)));
      }
      expect(
        key,
        matches(RegExp(r'^xboard\.local_routing\.v1\.[0-9a-f]{64}$')),
      );
    },
  );

  test(
    'ignores invalid saved records and accepts a later valid write',
    () async {
      final session = _session();
      final key = XboardRoutingStore.scopeKey(session)!;
      final preferences = await SharedPreferences.getInstance();
      final store = XboardRoutingStore();
      for (final source in [
        '{not-json',
        '[]',
        'null',
        '{}',
        jsonEncode({..._snapshot('US 02').toJson(), 'mode': 'invalid'}),
      ]) {
        await preferences.setString(key, source);
        expect(await store.load(session), isNull);
      }
      await preferences.setInt(key, 20);
      expect(await store.load(session), isNull);
      await store.save(session, _snapshot('US 02'));
      expect((await store.load(session))?.selectedMap['GLOBAL'], 'US 02');
    },
  );

  test('serializes writes and makes load and flush wait for writes', () async {
    final preferences = _ControlledPreferences(
      await SharedPreferences.getInstance(),
    );
    final store = XboardRoutingStore(
      preferencesLoader: () async => preferences,
    );
    final session = _session();
    final first = store.save(session, _snapshot('US 02'));
    await preferences.started.future;
    final second = store.save(session, _snapshot('SG 01'));
    var loaded = false;
    var flushed = false;
    final loading = store.load(session).then((value) {
      loaded = true;
      return value;
    });
    final flushing = store.flush().then((_) => flushed = true);
    await Future<void>.delayed(Duration.zero);
    expect(preferences.writes, 1);
    expect(loaded, isFalse);
    expect(flushed, isFalse);
    preferences.release.complete();
    await Future.wait([first, second, flushing]);
    expect((await loading)?.selectedMap['GLOBAL'], 'SG 01');
    expect(preferences.writes, 2);
    expect(flushed, isTrue);
  });

  test('surfaces rejected writes via save and flush and recovers', () async {
    final preferences = _ControlledPreferences(
      await SharedPreferences.getInstance(),
    )..reject = true;
    preferences.release.complete();
    final store = XboardRoutingStore(
      preferencesLoader: () async => preferences,
    );
    final session = _session();
    final writing = store.save(session, _snapshot('US 02'));
    await expectLater(writing, throwsStateError);
    await expectLater(store.flush(), throwsStateError);
    expect(await store.load(session), isNull);
    preferences.reject = false;
    await store.save(session, _snapshot('SG 01'));
    await store.flush();
    expect((await store.load(session))?.selectedMap['GLOBAL'], 'SG 01');
  });

  test(
    'binds one owner per profile ID and URL across store restarts',
    () async {
      final accountA = _session(uuid: 'user-a', planId: 1);
      final accountB = _session(uuid: 'user-b', planId: 1);
      final planB = _session(uuid: 'user-a', planId: 2);
      const profile = Profile(
        id: 42,
        url: 'https://subscription.example.com/private-token',
        autoUpdateDuration: Duration.zero,
      );
      final store = XboardRoutingStore();
      expect(await store.ownsProfile(accountA, profile), isFalse);
      await store.save(accountA, _snapshot('US 02'));
      expect(await store.ownsProfile(accountA, profile), isFalse);
      await store.bindProfile(accountA, profile);
      final restarted = XboardRoutingStore();
      expect(await restarted.ownsProfile(accountA, profile), isTrue);
      expect(await restarted.ownsProfile(accountB, profile), isFalse);
      expect(await restarted.ownsProfile(planB, profile), isFalse);
      expect(
        await restarted.ownsProfile(accountA, profile.copyWith(id: 43)),
        isFalse,
      );
      expect(
        await restarted.ownsProfile(
          accountA,
          profile.copyWith(url: 'https://subscription.example.com/another'),
        ),
        isFalse,
      );
      await restarted.bindProfile(accountB, profile);
      expect(await store.ownsProfile(accountB, profile), isTrue);
      expect(await store.ownsProfile(accountA, profile), isFalse);
      await restarted.bindProfile(planB, profile);
      expect(await store.ownsProfile(planB, profile), isTrue);
      expect(await store.ownsProfile(accountA, profile), isFalse);
      expect(await store.ownsProfile(accountB, profile), isFalse);
      final preferences = await SharedPreferences.getInstance();
      final persisted = preferences
          .getKeys()
          .map((key) => '$key ${preferences.get(key)}')
          .join();
      expect(persisted, isNot(contains(profile.url)));
      expect(persisted, isNot(contains('user-a')));
      expect(persisted, isNot(contains('private-token')));
    },
  );

  test('ownership checks wait for both snapshot and binding writes', () async {
    final preferences = _ControlledPreferences(
      await SharedPreferences.getInstance(),
    );
    final store = XboardRoutingStore(
      preferencesLoader: () async => preferences,
    );
    final session = _session();
    const profile = Profile(id: 42, autoUpdateDuration: Duration.zero);
    final saving = store.save(session, _snapshot('US 02'));
    await preferences.started.future;
    final binding = store.bindProfile(session, profile);
    var checked = false;
    var flushed = false;
    final checking = store.ownsProfile(session, profile).then((value) {
      checked = true;
      return value;
    });
    final flushing = store.flush().then((_) => flushed = true);
    await Future<void>.delayed(Duration.zero);
    expect(preferences.writes, 1);
    expect(checked, isFalse);
    expect(flushed, isFalse);
    preferences.release.complete();
    await Future.wait([saving, binding, flushing]);
    expect(await checking, isTrue);
    expect(preferences.writes, 2);
    expect(flushed, isTrue);
    expect((await store.load(session))?.selectedMap['GLOBAL'], 'US 02');
  });

  test(
    'binding failures are observable and do not block later writes',
    () async {
      final preferences = _ControlledPreferences(
        await SharedPreferences.getInstance(),
      )..reject = true;
      preferences.release.complete();
      final store = XboardRoutingStore(
        preferencesLoader: () async => preferences,
      );
      final session = _session();
      const profile = Profile(id: 42, autoUpdateDuration: Duration.zero);
      await expectLater(store.bindProfile(session, profile), throwsStateError);
      await expectLater(store.flush(), throwsStateError);
      expect(await store.ownsProfile(session, profile), isFalse);
      preferences.reject = false;
      await store.bindProfile(session, profile);
      await store.flush();
      expect(await store.ownsProfile(session, profile), isTrue);
      expect(await store.load(session), isNull);
      await store.save(session, _snapshot('US 02'));
      expect((await store.load(session))?.selectedMap['GLOBAL'], 'US 02');
      final unscoped = _session(uuid: null, email: null);
      await store.bindProfile(unscoped, profile);
      expect(await store.ownsProfile(unscoped, profile), isFalse);
      expect(await store.ownsProfile(session, profile), isTrue);
    },
  );

  test('ignores malformed profile ownership values', () async {
    const profile = Profile(id: 42, autoUpdateDuration: Duration.zero);
    final session = _session();
    final store = XboardRoutingStore();
    await store.bindProfile(session, profile);
    final preferences = await SharedPreferences.getInstance();
    await preferences.setInt(preferences.getKeys().single, 7);
    expect(await store.ownsProfile(session, profile), isFalse);
  });

  test(
    'surfaces storage loader failures and can flush an empty queue',
    () async {
      var fail = true;
      final store = XboardRoutingStore(
        preferencesLoader: () async {
          if (fail) throw StateError('unavailable');
          return SharedPreferences.getInstance();
        },
      );
      await store.flush();
      await expectLater(store.load(_session()), throwsStateError);
      await expectLater(
        store.save(_session(), _snapshot('US 02')),
        throwsStateError,
      );
      await expectLater(store.flush(), throwsStateError);
      fail = false;
      await store.save(_session(), _snapshot('SG 01'));
      await store.flush();
      expect((await store.load(_session()))?.selectedMap['GLOBAL'], 'SG 01');
    },
  );
}

XboardRoutingSnapshot _snapshot(String node, {Mode mode = Mode.global}) =>
    XboardRoutingSnapshot(
      mode: mode,
      selectedMap: {'GLOBAL': node},
      currentGroupName: 'GLOBAL',
    );

XboardLoginResult _session({
  String? uuid = 'account-uuid',
  String? email = 'member@example.com',
  int? planId = 1,
  int? nestedPlanId,
  String token = 'private-token',
  String endpoint = 'https://api.example.com',
  String? subscribeUrl = 'https://subscribe.example.com/private-token',
}) => XboardLoginResult(
  endpoint: Uri.parse(endpoint),
  token: token,
  authData: 'private-auth',
  isAdmin: false,
  subscription: XboardSubscriptionData(
    endpoint: Uri.parse(endpoint),
    subscribeUrl: subscribeUrl == null ? null : Uri.parse(subscribeUrl),
    uuid: uuid,
    email: email,
    planId: planId,
    plan: nestedPlanId == null
        ? null
        : XboardPlanData(id: nestedPlanId, rawData: const {}),
    token: token,
    uploadBytes: 0,
    downloadBytes: 0,
    transferEnableBytes: 100,
    rawData: const {},
  ),
);

class _ControlledPreferences extends Fake implements SharedPreferences {
  _ControlledPreferences(this.inner);

  final SharedPreferences inner;
  final started = Completer<void>();
  final release = Completer<void>();
  int writes = 0;
  bool reject = false;

  @override
  String? getString(String key) => inner.getString(key);

  @override
  Future<bool> setString(String key, String value) async {
    writes++;
    if (writes == 1) {
      started.complete();
      await release.future;
    }
    if (reject) return false;
    return inner.setString(key, value);
  }
}

import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:fl_clash/common/subscription_entry_reminder.dart';
import 'package:fl_clash/common/xboard_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final now = DateTime.utc(2026, 10, 9, 12);

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('subscription entry reminder evaluation', () {
    test('ignores unavailable data, invalid usage and exhausted traffic', () {
      expect(evaluateSubscriptionEntryReminder(null, now: now), isNull);
      for (final subscription in [
        _subscription(quota: 0),
        _subscription(quota: -1),
        _subscription(upload: -1),
        _subscription(download: -1),
        _subscription(quota: 5, upload: 5),
        _subscription(quota: 5, download: 5),
        _subscription(quota: 5, upload: 3, download: 2),
        _subscription(quota: 5, upload: 6),
        _subscription(
          quota: 9223372036854775807,
          upload: 9223372036854775806,
          download: 9223372036854775806,
        ),
      ]) {
        expect(
          evaluateSubscriptionEntryReminder(subscription, now: now),
          isNull,
        );
      }
    });

    test('unlimited time reminds below ten GB but not at the threshold', () {
      for (final remaining in [1, 9 * bytesPerGigabyte]) {
        final evaluation = evaluateSubscriptionEntryReminder(
          _subscription(quota: remaining),
          now: now,
        );
        expect(evaluation?.lowTraffic, isTrue);
        expect(evaluation?.expiringSoon, isFalse);
      }
      for (final remaining in [
        10 * bytesPerGigabyte,
        10 * bytesPerGigabyte + 1,
      ]) {
        expect(
          evaluateSubscriptionEntryReminder(
            _subscription(quota: remaining),
            now: now,
          ),
          isNull,
        );
      }
    });

    test('calculates remaining traffic from both upload and download', () {
      final evaluation = evaluateSubscriptionEntryReminder(
        _subscription(
          quota: 20 * bytesPerGigabyte,
          upload: 7 * bytesPerGigabyte,
          download: 4 * bytesPerGigabyte,
        ),
        now: now,
      );
      expect(evaluation?.lowTraffic, isTrue);
    });

    test('monthly expiry is strictly less than three days', () {
      final evaluation = evaluateSubscriptionEntryReminder(
        _subscription(expiry: now.add(const Duration(days: 3, seconds: -1))),
        now: now,
      );
      expect(evaluation?.expiringSoon, isTrue);
      expect(evaluation?.lowTraffic, isFalse);
      for (final expiry in [
        now.add(const Duration(days: 3)),
        now.add(const Duration(days: 3, seconds: 1)),
      ]) {
        expect(
          evaluateSubscriptionEntryReminder(
            _subscription(expiry: expiry),
            now: now,
          ),
          isNull,
        );
      }
    });

    test('expiry ends reminders even when traffic is low', () {
      for (final expiry in [now, now.subtract(const Duration(seconds: 1))]) {
        expect(
          evaluateSubscriptionEntryReminder(
            _subscription(quota: 1, expiry: expiry),
            now: now,
          ),
          isNull,
        );
      }
      expect(
        evaluateSubscriptionEntryReminder(
          _subscription(
            quota: 1,
            upload: 1,
            expiry: now.add(const Duration(days: 1)),
          ),
          now: now,
        ),
        isNull,
      );
    });

    test(
      'monthly low traffic requires reset strictly more than seven days away',
      () {
        final expiry = now.add(const Duration(days: 30));
        for (final reset in [
          now.add(const Duration(days: 6)),
          now.add(const Duration(days: 7)),
        ]) {
          expect(
            evaluateSubscriptionEntryReminder(
              _subscription(quota: 1, expiry: expiry, reset: reset),
              now: now,
            ),
            isNull,
          );
        }
        final evaluation = evaluateSubscriptionEntryReminder(
          _subscription(
            quota: 1,
            expiry: expiry,
            reset: now.add(const Duration(days: 8)),
          ),
          now: now,
        );
        expect(evaluation?.lowTraffic, isTrue);
        expect(evaluation?.expiringSoon, isFalse);
      },
    );

    test(
      'seven days plus one millisecond qualifies and expiry boundary is exact',
      () {
        final reset = now.add(const Duration(days: 7));
        final subscription = _subscription(
          quota: 1,
          expiry: now.add(const Duration(days: 30)),
          reset: reset,
        );
        expect(
          evaluateSubscriptionEntryReminder(
            subscription,
            now: now.subtract(const Duration(milliseconds: 1)),
          )?.lowTraffic,
          isTrue,
        );
        expect(
          evaluateSubscriptionEntryReminder(subscription, now: now),
          isNull,
        );
        expect(
          evaluateSubscriptionEntryReminder(
            _subscription(expiry: now.add(const Duration(days: 3))),
            now: now.add(const Duration(milliseconds: 1)),
          )?.expiringSoon,
          isTrue,
        );
      },
    );

    test('monthly ten GB threshold remains strict with a distant reset', () {
      expect(
        evaluateSubscriptionEntryReminder(
          _subscription(
            quota: 10 * bytesPerGigabyte,
            expiry: now.add(const Duration(days: 30)),
            reset: now.add(const Duration(days: 8)),
          ),
          now: now,
        ),
        isNull,
      );
    });

    test(
      'missing, elapsed and invalid reset dates do not imply a low traffic reminder',
      () {
        for (final reset in [null, 0, -1, 8640000000001, _epoch(now)]) {
          expect(
            evaluateSubscriptionEntryReminder(
              _subscription(
                quota: 1,
                expiry: now.add(const Duration(days: 30)),
                resetEpoch: reset,
              ),
              now: now,
            ),
            isNull,
          );
        }
      },
    );

    test('only accepts reset at or before the membership expiry', () {
      final expiry = now.add(const Duration(days: 8));
      expect(
        evaluateSubscriptionEntryReminder(
          _subscription(quota: 1, expiry: expiry, reset: expiry),
          now: now,
        )?.lowTraffic,
        isTrue,
      );
      expect(
        evaluateSubscriptionEntryReminder(
          _subscription(
            quota: 1,
            expiry: expiry,
            reset: expiry.add(const Duration(seconds: 1)),
          ),
          now: now,
        ),
        isNull,
      );
    });

    test('invalid resets preserve independent expiry reminders', () {
      for (final reset in [null, 0, -1, 8640000000001]) {
        final evaluation = evaluateSubscriptionEntryReminder(
          _subscription(
            quota: 1,
            expiry: now.add(const Duration(days: 2)),
            resetEpoch: reset,
          ),
          now: now,
        );
        expect(evaluation?.expiringSoon, isTrue);
        expect(evaluation?.lowTraffic, isFalse);
      }
    });

    test('invalid finite expiry cannot become unlimited time', () {
      for (final expiry in [0, -1, 8640000000001, 9223372036854775807]) {
        expect(
          evaluateSubscriptionEntryReminder(
            _subscription(quota: 1, expiryEpoch: expiry),
            now: now,
          ),
          isNull,
        );
      }
    });

    test('UTC and local representations of the same instant agree', () {
      final subscription = _subscription(
        quota: 1,
        expiry: now.add(const Duration(days: 30)),
        reset: now.add(const Duration(days: 8)),
      );
      expect(
        evaluateSubscriptionEntryReminder(subscription, now: now)?.lowTraffic,
        evaluateSubscriptionEntryReminder(
          subscription,
          now: now.toLocal(),
        )?.lowTraffic,
      );
    });
  });

  group('subscription entry reminder account identity', () {
    test(
      'canonical email remains stable across credentials and API addresses',
      () {
        final key = SubscriptionEntryReminderStore.accountKey(
          _session(email: ' Member@Example.com ', uuid: 'first'),
        );
        expect(
          SubscriptionEntryReminderStore.accountKey(
            _session(
              email: 'member@example.com',
              uuid: 'changed',
              endpoint: 'https://backup.example',
              token: 'new-credentials',
            ),
          ),
          key,
        );
        expect(key, matches(RegExp(r'^[a-f0-9]{64}$')));
        expect(key, isNot(contains('member')));
        expect(
          SubscriptionEntryReminderStore.accountKey(
            _session(email: 'other@example.com'),
          ),
          isNot(key),
        );
      },
    );

    test('canonical UUID is used when email is missing', () {
      expect(
        SubscriptionEntryReminderStore.accountKey(
          _session(uuid: ' ACCOUNT-UUID '),
        ),
        SubscriptionEntryReminderStore.accountKey(
          _session(
            email: ' ',
            uuid: 'account-uuid',
            endpoint: 'https://backup.example',
          ),
        ),
      );
      expect(
        SubscriptionEntryReminderStore.accountKey(
          _session(uuid: 'account-uuid'),
        ),
        isNot(
          SubscriptionEntryReminderStore.accountKey(
            _session(uuid: 'other-uuid'),
          ),
        ),
      );
    });

    test(
      'existing email account hash preserves identity when fields are absent',
      () {
        final fallback = sha256
            .convert(
              utf8.encode(
                'fengwo.local-account-rules.v1\u0000member@example.com',
              ),
            )
            .toString();
        expect(
          SubscriptionEntryReminderStore.accountKey(
            _session(),
            fallbackAccountKey: fallback,
          ),
          SubscriptionEntryReminderStore.accountKey(
            _session(email: 'member@example.com'),
          ),
        );
        expect(
          SubscriptionEntryReminderStore.accountKey(
            _session(uuid: 'account-uuid'),
            fallbackAccountKey: fallback,
          ),
          SubscriptionEntryReminderStore.accountKey(
            _session(email: 'member@example.com', uuid: 'account-uuid'),
          ),
        );
      },
    );

    test(
      'missing API email keeps a prior email suppression with UUID present',
      () async {
        final original = _session(
          email: 'member@example.com',
          uuid: 'account-uuid',
        );
        final originalKey = SubscriptionEntryReminderStore.accountKey(
          original,
        )!;
        final fallback = sha256
            .convert(
              utf8.encode(
                'fengwo.local-account-rules.v1\u0000member@example.com',
              ),
            )
            .toString();
        await SubscriptionEntryReminderStore().disable(originalKey);
        final missingEmailKey = SubscriptionEntryReminderStore.accountKey(
          _session(
            uuid: 'account-uuid',
            endpoint: 'https://backup.example',
            token: 'new-credentials',
          ),
          fallbackAccountKey: fallback,
        );
        expect(missingEmailKey, originalKey);
        expect(
          await SubscriptionEntryReminderStore().isDisabled(missingEmailKey!),
          isTrue,
        );
      },
    );

    test('missing identity and malformed fallback do not use token or API', () {
      expect(SubscriptionEntryReminderStore.accountKey(_session()), isNull);
      for (final fallback in ['member@example.com', 'a' * 63, 'A' * 64, ' ']) {
        expect(
          SubscriptionEntryReminderStore.accountKey(
            _session(),
            fallbackAccountKey: fallback,
          ),
          isNull,
        );
      }
    });
  });

  group('subscription entry reminder suppression', () {
    test('isolates accounts and persists across new store instances', () async {
      final store = SubscriptionEntryReminderStore();
      expect(await store.isDisabled('first'), isFalse);
      await store.disable('first');
      expect(await store.isDisabled('first'), isTrue);
      expect(await store.isDisabled('second'), isFalse);
      final restored = SubscriptionEntryReminderStore();
      expect(await restored.isDisabled('first'), isTrue);
      expect(await restored.isDisabled('second'), isFalse);
    });

    test(
      'suppression does not expire after plan renewal or traffic reset',
      () async {
        final key = SubscriptionEntryReminderStore.accountKey(
          _session(email: 'member@example.com'),
        )!;
        await SubscriptionEntryReminderStore().disable(key);
        final renewed = _session(
          email: 'member@example.com',
          token: 'renewed-credentials',
          subscription: _subscription(
            email: 'member@example.com',
            quota: 60 * bytesPerGigabyte,
            expiry: now.add(const Duration(days: 60)),
            reset: now.add(const Duration(days: 30)),
          ),
        );
        expect(
          await SubscriptionEntryReminderStore().isDisabled(
            SubscriptionEntryReminderStore.accountKey(renewed)!,
          ),
          isTrue,
        );
      },
    );

    test('preference keys do not store plaintext account identities', () async {
      await SubscriptionEntryReminderStore().disable('member@example.com');
      final preferences = await SharedPreferences.getInstance();
      expect(preferences.getKeys(), hasLength(1));
      final key = preferences.getKeys().single;
      expect(key, isNot(contains('member')));
      expect(key, isNot(contains('@')));
      expect(preferences.get(key), isTrue);
    });

    test('disables immediately while preference loading is pending', () async {
      final preferences = await SharedPreferences.getInstance();
      final loaded = Completer<SharedPreferences>();
      final store = SubscriptionEntryReminderStore(
        preferencesLoader: () => loaded.future,
      );
      final write = store.disable('first');
      expect(await store.isDisabled('first'), isTrue);
      loaded.complete(preferences);
      await write;
    });

    test(
      'pending preference read observes a subsequent in-memory disable',
      () async {
        final preferences = await SharedPreferences.getInstance();
        final loaded = Completer<SharedPreferences>();
        final store = SubscriptionEntryReminderStore(
          preferencesLoader: () => loaded.future,
        );
        final read = store.isDisabled('first');
        final write = store.disable('first');
        loaded.complete(preferences);
        expect(await read, isTrue);
        await write;
      },
    );

    test(
      'serializes writes while immediately suppressing both accounts',
      () async {
        final preferences = _ControlledPreferences(
          await SharedPreferences.getInstance(),
        );
        final gate = Completer<bool>();
        preferences.onWrite = (key, value) => preferences.writes.length == 1
            ? gate.future
            : Future<bool>.value(true);
        final store = SubscriptionEntryReminderStore(
          preferencesLoader: () async => preferences,
        );
        final first = store.disable('first');
        final second = store.disable('second');
        await preferences.started.future;
        expect(preferences.writes, hasLength(1));
        expect(await store.isDisabled('first'), isTrue);
        expect(await store.isDisabled('second'), isTrue);
        gate.complete(true);
        await Future.wait([first, second]);
        expect(preferences.writes, hasLength(2));
        final restored = SubscriptionEntryReminderStore();
        expect(await restored.isDisabled('first'), isTrue);
        expect(await restored.isDisabled('second'), isTrue);
      },
    );

    test(
      'failed preference loading reports failure but keeps current suppression',
      () async {
        final store = SubscriptionEntryReminderStore(
          preferencesLoader: () async => throw StateError('loader_failed'),
        );
        await expectLater(store.isDisabled('first'), throwsStateError);
        await expectLater(store.disable('first'), throwsStateError);
        expect(await store.isDisabled('first'), isTrue);
        expect(
          await SubscriptionEntryReminderStore().isDisabled('first'),
          isFalse,
        );
      },
    );

    test(
      'rejected write does not poison subsequent queued writes or retries',
      () async {
        final preferences = _ControlledPreferences(
          await SharedPreferences.getInstance(),
        );
        preferences.onWrite = (key, value) async =>
            preferences.writes.length != 1;
        final store = SubscriptionEntryReminderStore(
          preferencesLoader: () async => preferences,
        );
        final first = store.disable('first');
        final failed = expectLater(first, throwsStateError);
        final second = store.disable('second');
        await Future.wait([failed, second]);
        expect(await store.isDisabled('first'), isTrue);
        expect(
          await SubscriptionEntryReminderStore().isDisabled('first'),
          isFalse,
        );
        expect(
          await SubscriptionEntryReminderStore().isDisabled('second'),
          isTrue,
        );
        await store.disable('first');
        expect(
          await SubscriptionEntryReminderStore().isDisabled('first'),
          isTrue,
        );
      },
    );

    test('thrown writes also release the queue for another account', () async {
      final preferences = _ControlledPreferences(
        await SharedPreferences.getInstance(),
      );
      preferences.onWrite = (key, value) async {
        if (preferences.writes.length == 1) throw StateError('write_failed');
        return true;
      };
      final store = SubscriptionEntryReminderStore(
        preferencesLoader: () async => preferences,
      );
      final first = store.disable('first');
      final failed = expectLater(first, throwsStateError);
      final second = store.disable('second');
      await Future.wait([failed, second]);
      expect(await store.isDisabled('first'), isTrue);
      expect(
        await SubscriptionEntryReminderStore().isDisabled('second'),
        isTrue,
      );
    });

    test('invalid preference values do not disable reminders', () async {
      await SubscriptionEntryReminderStore().disable('first');
      final preferences = await SharedPreferences.getInstance();
      final key = preferences.getKeys().single;
      await preferences.setString(key, 'true');
      expect(
        await SubscriptionEntryReminderStore().isDisabled('first'),
        isFalse,
      );
    });

    test('rejects empty account keys without recording a preference', () async {
      final store = SubscriptionEntryReminderStore();
      expect(() => store.disable(' '), throwsArgumentError);
      await expectLater(store.isDisabled(' '), throwsArgumentError);
      expect((await SharedPreferences.getInstance()).getKeys(), isEmpty);
    });
  });
}

XboardSubscriptionData _subscription({
  int quota = 60 * bytesPerGigabyte,
  int upload = 0,
  int download = 0,
  DateTime? expiry,
  DateTime? reset,
  int? expiryEpoch,
  int? resetEpoch,
  String? email,
  String? uuid,
  String endpoint = 'https://api.example',
}) {
  return XboardSubscriptionData(
    endpoint: Uri.parse(endpoint),
    subscribeUrl: null,
    transferEnableBytes: quota,
    uploadBytes: upload,
    downloadBytes: download,
    expiredAtEpochSeconds:
        expiryEpoch ?? (expiry == null ? null : _epoch(expiry)),
    nextResetAtEpochSeconds:
        resetEpoch ?? (reset == null ? null : _epoch(reset)),
    email: email,
    uuid: uuid,
    rawData: const {},
  );
}

int _epoch(DateTime value) => value.millisecondsSinceEpoch ~/ 1000;

XboardLoginResult _session({
  String? email,
  String? uuid,
  String endpoint = 'https://api.example',
  String token = 'credentials',
  XboardSubscriptionData? subscription,
}) {
  return XboardLoginResult(
    endpoint: Uri.parse(endpoint),
    token: token,
    authData: token,
    isAdmin: false,
    subscription:
        subscription ??
        _subscription(email: email, uuid: uuid, endpoint: endpoint),
  );
}

class _ControlledPreferences extends Fake implements SharedPreferences {
  _ControlledPreferences(this.inner);

  final SharedPreferences inner;
  final List<String> writes = [];
  final Completer<void> started = Completer<void>();
  Future<bool> Function(String key, bool value)? onWrite;

  @override
  Object? get(String key) => inner.get(key);

  @override
  Future<bool> setBool(String key, bool value) async {
    writes.add(key);
    if (!started.isCompleted) started.complete();
    if (onWrite != null && !await onWrite!(key, value)) return false;
    return inner.setBool(key, value);
  }
}

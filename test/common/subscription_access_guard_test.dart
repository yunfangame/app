import 'dart:async';

import 'package:fl_clash/common/subscription_access_guard.dart';
import 'package:fl_clash/common/xboard_auth.dart';
import 'package:flutter_test/flutter_test.dart';

XboardSubscriptionData subscription({
  int used = 0,
  int? expiry,
  Map<String, Object?>? rawData,
}) => XboardSubscriptionData(
  endpoint: Uri.parse('https://example.com'),
  subscribeUrl: null,
  uploadBytes: used,
  downloadBytes: 0,
  transferEnableBytes: 100,
  expiredAtEpochSeconds: expiry,
  rawData: rawData ?? {'transfer_enable': 100, 'u': used, 'd': 0},
);

void main() {
  for (final invalid in [
    <String, Object?>{},
    {'transfer_enable': null, 'u': 0, 'd': 0},
    {'transfer_enable': 'invalid', 'u': 0, 'd': 0},
    {'transfer_enable': 100, 'u': -1, 'd': 0},
    {'transfer_enable': 100, 'u': 0, 'd': double.nan},
  ]) {
    test(
      'invalid usage response is allowed without a false warning: $invalid',
      () async {
        final guard = SubscriptionAccessGuard();
        final data = subscription(used: 100, rawData: invalid);
        expect(subscriptionAccessIssue(data), isNull);
        expect(
          await guard.check(
            account: 'a',
            fetch: () async => data,
            isCurrent: () => true,
            notify: (_, _) async => fail('must not notify'),
          ),
          isTrue,
        );
      },
    );
  }

  test('only expired or exhausted plans prevent access', () {
    expect(subscriptionAccessIssue(subscription(used: 99)), isNull);
    expect(
      subscriptionAccessIssue(subscription(used: 100)),
      SubscriptionAccessIssue.exhausted,
    );
    expect(
      subscriptionAccessIssue(subscription(used: 101)),
      SubscriptionAccessIssue.exhausted,
    );
    expect(
      subscriptionAccessIssue(subscription(expiry: 1)),
      SubscriptionAccessIssue.expired,
    );
  });

  test('startup and connection share fetch and notification', () async {
    final guard = SubscriptionAccessGuard();
    final pending = Completer<XboardSubscriptionData>();
    var fetches = 0;
    var notices = 0;
    Future<bool> check() => guard.check(
      account: 'a',
      fetch: () {
        fetches++;
        return pending.future;
      },
      isCurrent: () => true,
      notify: (_, _) async {
        notices++;
      },
    );
    final first = check();
    final second = check();
    pending.complete(subscription(used: 100));
    expect(await first, isFalse);
    expect(await second, isFalse);
    expect(fetches, 1);
    expect(notices, 1);
    expect(await check(), isFalse);
    expect(notices, 1);
  });

  test('healthy refresh clears warning and accounts stay isolated', () async {
    final guard = SubscriptionAccessGuard();
    var data = subscription(used: 100);
    var notices = 0;
    Future<bool> check(String account) => guard.check(
      account: account,
      fetch: () async => data,
      isCurrent: () => true,
      notify: (_, _) async {
        notices++;
      },
    );
    expect(await check('a'), isFalse);
    expect(await check('b'), isFalse);
    data = subscription();
    expect(await check('a'), isTrue);
    data = subscription(used: 100);
    expect(await check('a'), isFalse);
    expect(notices, 3);
  });

  test('failed refresh does not block or warn using cached traffic', () async {
    final guard = SubscriptionAccessGuard();
    expect(
      await guard.check(
        account: 'a',
        fetch: () async => throw StateError('offline'),
        isCurrent: () => true,
        notify: (_, _) async => fail('must not notify'),
      ),
      isTrue,
    );
  });

  test('account changed during refresh prevents stale notification', () async {
    final guard = SubscriptionAccessGuard();
    expect(
      await guard.check(
        account: 'a',
        fetch: () async => subscription(used: 100),
        isCurrent: () => false,
        notify: (_, _) async => fail('must not notify'),
      ),
      isFalse,
    );
  });

  test('same account new session does not reuse an outdated request', () async {
    final guard = SubscriptionAccessGuard();
    final oldResponse = Completer<XboardSubscriptionData>();
    final newResponse = Completer<XboardSubscriptionData>();
    var oldCurrent = true;
    var notices = 0;
    final previous = guard.check(
      account: 'a',
      requestKey: '1',
      fetch: () => oldResponse.future,
      isCurrent: () => oldCurrent,
      notify: (_, _) async {
        notices++;
      },
    );
    oldCurrent = false;
    final current = guard.check(
      account: 'a',
      requestKey: '2',
      fetch: () => newResponse.future,
      isCurrent: () => true,
      notify: (_, _) async {
        notices++;
      },
    );
    newResponse.complete(subscription());
    expect(await current, isTrue);
    oldResponse.complete(subscription(used: 100));
    expect(await previous, isFalse);
    expect(notices, 0);
  });
}

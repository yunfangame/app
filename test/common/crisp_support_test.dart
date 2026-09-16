import 'dart:convert';
import 'dart:ui';

import 'package:fl_clash/l10n/l10n.dart';

import 'package:fl_clash/common/crisp_support.dart';
import 'package:fl_clash/common/xboard_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUpAll(() => AppLocalizations.load(const Locale('zh', 'CN')));

  test('exposes only selected support data, never authentication secrets', () {
    final user = CrispSupportUser.fromSession(_session());
    expect(user.email, 'customer@example.com');
    expect(user.data['plan'], '200G 月套餐');
    expect(user.data['traffic_used_bytes'], 3 * bytesPerGigabyte);
    expect(user.data['traffic_total_bytes'], 200 * bytesPerGigabyte);
    expect(user.data['traffic_remaining_bytes'], 197 * bytesPerGigabyte);
    expect(user.data['traffic_used_gb'], '3.00');
    expect(user.data['device_limit'], 3);
    expect(user.data['expires_at'], '2030-01-01T00:00:00.000Z');
    final script = user.updateScript;
    for (final secret in [
      'AUTH_SECRET',
      'SUB_SECRET',
      'LOGIN_SECRET',
      'RAW_SECRET',
    ]) {
      expect(script, isNot(contains(secret)));
    }
    expect(script, isNot(contains('subscribeUrl')));
  });

  test('anonymous support does not inherit a previous user or plan', () {
    final user = CrispSupportUser.fromSession(null);
    expect(user.accountKey, 'guest');
    expect(user.email, isNull);
    expect(user.data['logged_in'], false);
    expect(user.data.containsKey('plan'), false);
  });

  test('a logged-in customer gets a plain-text summary with no secrets', () {
    final user = CrispSupportUser.fromSession(_session());
    expect(user.summary, contains('账号：customer@example.com'));
    expect(user.summary, contains('订阅套餐：200G 月套餐'));
    expect(user.summary, contains('已用流量：3.00 GB / 200.00 GB'));
    expect(user.summary, contains('剩余流量：197.00 GB'));
    for (final secret in [
      'AUTH_SECRET',
      'SUB_SECRET',
      'LOGIN_SECRET',
      'RAW_SECRET',
    ]) {
      expect(user.summary, isNot(contains(secret)));
    }
    expect(CrispSupportUser.fromSession(null).summary, isNull);
    expect(
      CrispSupportUser.fromSession(_session(expires: null)).summary,
      contains('到期时间：不限时'),
    );
  });

  test('support messages stay Chinese when the app uses English', () async {
    await AppLocalizations.load(const Locale('en'));
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    try {
      expect(
        CrispSupportUser.fromSession(_session(expires: null)).summary,
        '【账号信息】\n'
        '账号：customer@example.com\n'
        '订阅套餐：200G 月套餐\n'
        '已用流量：3.00 GB / 200.00 GB\n'
        '剩余流量：197.00 GB\n'
        '到期时间：不限时\n'
        '客户端：苹果桌面端（macOS）',
      );
      final missingProfile = CrispSupportUser.fromSession(
        _session(email: '', planName: null, expires: null),
      );
      expect(missingProfile.summary, contains('账号：未知'));
      expect(missingProfile.summary, contains('订阅套餐：暂无有效套餐'));
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      expect(
        CrispSupportUser.fromSession(_session()).summary,
        contains('客户端：安卓客户端'),
      );
    } finally {
      debugDefaultTargetPlatformOverride = null;
      await AppLocalizations.load(const Locale('zh', 'CN'));
    }
  });

  test('API failover and subscription refresh retain the same account', () {
    final first = CrispSupportUser.fromSession(_session());
    final second = CrispSupportUser.fromSession(
      _session(host: 'backup.example.com', email: 'CUSTOMER@example.com'),
    );
    expect(first.accountKey, second.accountKey);
    expect(
      first.accountKey,
      isNot(
        CrispSupportUser.fromSession(
          _session(email: 'other@example.com'),
        ).accountKey,
      ),
    );
  });

  test('handles unlimited time, exhausted traffic and offline snapshots', () {
    final user = CrispSupportUser.fromSession(
      _session(expires: null, total: bytesPerGigabyte),
      offline: true,
    );
    expect(user.data['expires_at'], 'unlimited');
    expect(user.data['expired'], false);
    expect(user.data['traffic_remaining_bytes'], 0);
    expect(user.data['offline_mode'], true);
  });

  test('encodes profile values without turning them into JavaScript', () {
    const value = "quotation '\"\\\n</script>";
    const user = CrispSupportUser(
      accountKey: 'private-key',
      data: {'plan': value},
    );
    expect(user.updateScript, contains(jsonEncode(value)));
    expect(user.updateScript, isNot(contains('private-key')));
  });

  test(
    'session tokens are independent random values, not user identifiers',
    () {
      final first = createCrispSessionToken();
      final second = createCrispSessionToken();
      expect(base64Url.decode(first), hasLength(32));
      expect(first, isNot(second));
    },
  );
}

XboardLoginResult _session({
  String host = 'api.example.com',
  String email = 'customer@example.com',
  String? planName = '200G 月套餐',
  int? expires = 1893456000,
  int total = 200 * bytesPerGigabyte,
}) => XboardLoginResult(
  endpoint: Uri.https(host),
  token: 'LOGIN_SECRET',
  authData: 'AUTH_SECRET',
  isAdmin: false,
  rawData: const {'extra': 'RAW_SECRET'},
  subscription: XboardSubscriptionData(
    endpoint: Uri.https(host),
    subscribeUrl: Uri.parse('https://example.com/subscribe?token=SUB_SECRET'),
    token: 'SUB_SECRET',
    email: email,
    uploadBytes: bytesPerGigabyte,
    downloadBytes: 2 * bytesPerGigabyte,
    transferEnableBytes: total,
    expiredAtEpochSeconds: expires,
    planId: 7,
    deviceLimit: 3,
    plan: planName == null
        ? null
        : XboardPlanData(name: planName, rawData: const {}),
    rawData: const {'extra': 'RAW_SECRET'},
  ),
);

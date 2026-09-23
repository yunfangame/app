import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';

import 'xboard_auth.dart';

const crispWebsiteId = String.fromEnvironment(
  'CRISP_WEBSITE_ID',
  defaultValue: 'f8b04adc-c060-4ae6-94e0-e0e378ed7fda',
);

const crispServiceUrl =
    'https://go.crisp.chat/chat/embed/'
    '?website_id=$crispWebsiteId&session_merge=false';

final crispServiceUri = Uri.parse(crispServiceUrl);

Uri crispSessionUri(Uri uri, {required String sessionToken}) {
  if (uri.scheme != 'https' ||
      uri.origin != crispServiceUri.origin ||
      uri.path != crispServiceUri.path) {
    return uri;
  }
  final parameters = {...uri.queryParameters}..remove('crisp_sid');
  return uri.replace(
    queryParameters: {
      ...parameters,
      'token_id': sessionToken,
      'session_merge': 'false',
    },
  );
}

String createCrispSessionToken() {
  final random = Random.secure();
  return base64UrlEncode(List<int>.generate(32, (_) => random.nextInt(256)));
}

class CrispSupportUser {
  const CrispSupportUser({
    required this.accountKey,
    this.email,
    this.summary,
    this.data = const {},
  });

  factory CrispSupportUser.fromSession(
    XboardLoginResult? session, {
    required String appVersion,
    bool offline = false,
  }) {
    final subscription = session?.subscription;
    final email = subscription?.email?.trim();
    final hasEmail = email != null && email.isNotEmpty;
    final version = appVersion
        .trim()
        .replaceFirst(RegExp(r'^[vV]'), '')
        .split('+')
        .first;
    return CrispSupportUser(
      accountKey: session == null
          ? 'guest'
          : hasEmail
          ? 'email:${email.toLowerCase()}'
          : 'account:${subscription?.uuid ?? session.authData}',
      email: hasEmail ? email : null,
      summary: subscription == null
          ? null
          : _chineseAccountSummary(subscription, appVersion: version),
      data: {
        'logged_in': session != null,
        'platform': defaultTargetPlatform.name,
        'app_version': version,
        'offline_mode': offline,
        if (subscription != null) ...{
          'plan': subscription.plan?.name ?? '',
          'plan_id': subscription.planId ?? 0,
          'traffic_used_bytes': subscription.usedBytes,
          'traffic_total_bytes': subscription.transferEnableBytes,
          'traffic_remaining_bytes': subscription.remainingBytes,
          'traffic_used_gb': subscription.usedGb.toStringAsFixed(2),
          'traffic_total_gb': subscription.transferEnableGb.toStringAsFixed(2),
          'expires_at':
              subscription.expiresAt?.toUtc().toIso8601String() ?? 'unlimited',
          'expired': subscription.isExpired,
          'device_limit': subscription.deviceLimit ?? '',
          'speed_limit_mbps': subscription.speedLimit ?? '',
        },
      },
    );
  }

  final String accountKey;
  final String? email;
  final String? summary;
  final Map<String, Object> data;

  String get updateScript =>
      '''
(() => {
  const profile = ${jsonEncode({'email': email, 'data': data, 'summary': summary})};
  window.fengwoSupportProfile = profile;
  if (!window.fengwoSupportBound || !window.\$crisp) return;
  if (profile.email) window.\$crisp.push(['set', 'user:email', [profile.email]]);
  window.\$crisp.push(['set', 'session:data', [Object.entries(profile.data)]]);
  $crispSummaryBridgeScript
})();
''';
}

String _chineseAccountSummary(
  XboardSubscriptionData subscription, {
  required String appVersion,
}) {
  final email = subscription.email?.trim();
  final plan = subscription.plan?.name?.trim();
  final expiresAt = subscription.expiresAt;
  final expiry = expiresAt == null
      ? '不限时'
      : '${expiresAt.toIso8601String().substring(0, 16).replaceFirst('T', ' ')} ${expiresAt.timeZoneName}';
  final platform = switch (defaultTargetPlatform) {
    TargetPlatform.android => '安卓客户端',
    TargetPlatform.iOS => '苹果移动端',
    TargetPlatform.macOS => '苹果桌面端（macOS）',
    TargetPlatform.windows => 'Windows 桌面端',
    TargetPlatform.linux => 'Linux 桌面端',
    TargetPlatform.fuchsia => 'Fuchsia 客户端',
  };
  return [
    '【账号信息】',
    '账号：${email == null || email.isEmpty ? '未知' : email}',
    '订阅套餐：${plan == null || plan.isEmpty ? '暂无有效套餐' : plan}',
    '已用流量：${subscription.usedGb.toStringAsFixed(2)} GB / ${subscription.transferEnableGb.toStringAsFixed(2)} GB',
    '剩余流量：${subscription.remainingGb.toStringAsFixed(2)} GB',
    '到期时间：$expiry',
    '客户端：$platform',
    '客户端版本：v$appVersion',
  ].join('\n');
}

String crispBootstrapScript({required String sessionToken}) =>
    '''
(() => {
  if (location.origin !== 'https://go.crisp.chat' ||
      location.pathname !== '/chat/embed/' ||
      new URL(location.href).searchParams.get('token_id') !== ${jsonEncode(sessionToken)} ||
      window.fengwoSupportStarted) return;
  window.fengwoSupportStarted = true;
  window.fengwoSupportBound = false;
  const started = Date.now();
  const watch = setInterval(() => {
    if (Date.now() - started > 45000) {
      clearInterval(watch);
      return;
    }
    const crisp = window.\$crisp;
    if (!crisp || typeof crisp.get !== 'function') return;
    clearInterval(watch);
    const markReady = () => {
      if (window.fengwoSupportBound) return;
      const identifier = crisp.get('session:identifier');
      if (typeof identifier !== 'string' || !identifier) return;
      window.fengwoSupportSessionId = identifier;
      window.fengwoSupportBound = true;
      window.FengwoSupportReady.postMessage('ready');
    };
    crisp.push(['on', 'session:loaded', markReady]);
    markReady();
  }, 50);
})();
''';

const crispSummaryBridgeScript = r'''
(() => {
  if (window.fengwoSupportSummaryListener) return;
  window.fengwoSupportSummaryListener = true;
  let pending = null;
  let sent = false;
  window.$crisp.push(['on', 'message:sent', (message) => {
    if (!message || message.from !== 'user') return;
    const content = message.content;
    if (message.type === 'text'
        ? typeof content !== 'string' || !content.trim()
        : !content || typeof content !== 'object' || !Object.keys(content).length) return;
    if (pending?.attempted && message.type === 'text' && message.content === pending.text) {
      const current = window.fengwoSupportProfile;
      if (!window.fengwoSupportBound ||
          window.$crisp.get('session:identifier') !== pending.sessionId ||
          current?.data?.logged_in !== true || current.email !== pending.email) {
        pending = null;
        return;
      }
      sent = true;
      pending = null;
      window.$crisp.push(['set', 'session:data', [[['support_summary_sent', true]]]]);
      window.FengwoSupportReady.postMessage('summary_sent');
      return;
    }
    const profile = window.fengwoSupportProfile;
    const persisted = window.$crisp.get('session:data', 'support_summary_sent');
    if (sent || pending || persisted === true || persisted === 'true' ||
        !window.fengwoSupportBound || profile?.data?.logged_in !== true ||
        typeof profile.summary !== 'string' || !profile.summary.trim()) return;
    const sessionId = window.$crisp.get('session:identifier');
    if (typeof sessionId !== 'string' || !sessionId) return;
    const attempt = { sessionId, email: profile.email, attempted: false, text: null };
    pending = attempt;
    setTimeout(() => {
      if (pending !== attempt) return;
      const current = window.fengwoSupportProfile;
      const persisted = window.$crisp.get('session:data', 'support_summary_sent');
      if (sent || !window.fengwoSupportBound ||
          window.$crisp.get('session:identifier') !== attempt.sessionId ||
          current?.data?.logged_in !== true || current.email !== attempt.email ||
          typeof current.summary !== 'string' || !current.summary.trim() ||
          persisted === true || persisted === 'true') {
        pending = null;
        return;
      }
      attempt.text = current.summary;
      attempt.attempted = true;
      try {
        window.$crisp.push(['do', 'message:send', ['text', attempt.text]]);
      } catch (_) {
        pending = null;
        window.FengwoSupportReady.postMessage('summary_failed');
      }
    }, 0);
  }]);
})();
''';

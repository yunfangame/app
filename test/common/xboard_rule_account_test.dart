import 'package:fl_clash/common/xboard_auth.dart';
import 'package:fl_clash/common/xboard_rule_account.dart';
import 'package:fl_clash/state.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(globalState.clearXboardSession);
  tearDown(globalState.clearXboardSession);

  test('normalizes account email into an opaque full-length key', () {
    final key = xboardRuleAccountKeyForEmail('user@example.com');
    expect(key, matches(RegExp(r'^[a-f0-9]{64}$')));
    expect(key, xboardRuleAccountKeyForEmail(' USER@EXAMPLE.COM '));
    expect(key, isNot(xboardRuleAccountKeyForEmail('other@example.com')));
    expect(key, isNot(contains('user@example.com')));
    expect(xboardRuleAccountKeyForEmail(' '), isNull);
    expect(xboardRuleAccountKeyForEmail(null), isNull);
  });

  test('rejects invalid stored account keys', () {
    for (final value in [null, 123, '', 'user@example.com', 'abcdef']) {
      expect(normalizeXboardRuleAccountKey(value), isNull);
    }
    final key = xboardRuleAccountKeyForEmail('user@example.com');
    expect(normalizeXboardRuleAccountKey(key), key);
    expect(normalizeXboardRuleAccountKey('$key\n'), isNull);
  });

  test('account identity survives API failover and token changes', () {
    globalState.activateXboardSession(_session(email: 'user@example.com'));
    final key = globalState.xboardRuleAccountKey;
    globalState.activateXboardSession(
      _session(
        email: ' USER@example.com ',
        host: 'backup.example.com',
        token: 'renewed-token',
      ),
    );
    expect(globalState.xboardRuleAccountKey, key);
  });

  test('uses authenticated login email when subscription omits it', () {
    globalState.activateXboardSession(
      _session(),
      accountEmail: 'manual@example.com',
    );
    expect(
      globalState.xboardRuleAccountKey,
      xboardRuleAccountKeyForEmail('manual@example.com'),
    );
    globalState.activateXboardSession(
      _session(email: 'verified@example.com'),
      accountEmail: 'input@example.com',
    );
    expect(
      globalState.xboardRuleAccountKey,
      xboardRuleAccountKeyForEmail('verified@example.com'),
    );
  });

  test('refresh can retain the already authenticated account key', () {
    globalState.activateXboardSession(
      _session(),
      accountEmail: 'manual@example.com',
    );
    final key = globalState.xboardRuleAccountKey;
    globalState.activateXboardSession(
      _session(token: 'renewed-token'),
      ruleAccountKey: key,
    );
    expect(globalState.xboardRuleAccountKey, key);
  });

  test('session changes publish the matching account identity atomically', () {
    final observed = <String?>[];
    void onRevision() => observed.add(globalState.xboardRuleAccountKey);
    globalState.xboardSessionRevisionNotifier.addListener(onRevision);
    try {
      globalState.activateXboardSession(_session(email: 'first@example.com'));
      globalState.activateXboardSession(_session(email: 'second@example.com'));
      globalState.clearXboardSession();
      globalState.activateXboardSession(_session());
      expect(observed, [
        xboardRuleAccountKeyForEmail('first@example.com'),
        xboardRuleAccountKeyForEmail('second@example.com'),
        null,
        null,
      ]);
    } finally {
      globalState.xboardSessionRevisionNotifier.removeListener(onRevision);
    }
  });
}

XboardLoginResult _session({
  String? email,
  String host = 'api.example.com',
  String token = 'subscription-token',
}) {
  final endpoint = Uri.https(host, '/api/v1');
  return XboardLoginResult(
    endpoint: endpoint,
    token: token,
    authData: 'Bearer $token',
    isAdmin: false,
    subscription: XboardSubscriptionData(
      endpoint: endpoint,
      subscribeUrl: Uri.https(host, '/subscribe', {'token': token}),
      uploadBytes: 0,
      downloadBytes: 0,
      transferEnableBytes: 1024,
      email: email,
      rawData: const {},
    ),
  );
}

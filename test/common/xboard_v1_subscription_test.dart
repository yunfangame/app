import 'package:fl_clash/common/xboard_auth.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('V1 uses the working API origin and preserves subscription data', () {
    final source = Uri.parse(
      'https://subscribe.example.com:8443/custom/a%2Fb'
      '?token=a%2Bb%2Fc+&flag=clash&flag=meta',
    );
    final session = _session(
      endpoint: 'https://api.example.com:9443/api/v1/passport/auth/login?x=1',
      subscribeUrl: source,
    );

    final result = session.legacySubscribeUrl!;

    expect(result.origin, 'https://api.example.com:9443');
    expect(result.path, source.path);
    expect(result.query, source.query);
    expect(result.queryParametersAll['flag'], ['clash', 'meta']);
    expect(result.queryParameters['token'], 'a+b/c ');
    expect(session.subscribeUrl, source);
  });

  test('V1 replaces the old port with the API default HTTPS port', () {
    final session = _session(
      endpoint: 'https://api.example.com/api/v1/passport/auth/login',
      subscribeUrl: Uri.parse('https://subscribe.example.com:8443/s/token'),
    );

    expect(
      session.legacySubscribeUrl,
      Uri.parse('https://api.example.com/s/token'),
    );
  });

  test('V1 upgrades a plain subscription URL to the working HTTPS API', () {
    final session = _session(
      endpoint: 'https://api.example.com',
      subscribeUrl: Uri.parse('http://subscribe.example.com/s/token'),
    );

    expect(
      session.legacySubscribeUrl,
      Uri.parse('https://api.example.com/s/token'),
    );
  });

  test('V1 cannot downgrade an HTTPS subscription to HTTP', () {
    final session = _session(
      endpoint: 'http://api.example.com',
      subscribeUrl: Uri.parse('https://subscribe.example.com/s/token'),
    );

    expect(() => session.legacySubscribeUrl, throwsFormatException);
  });

  test('V2 sessions never construct a legacy subscription URL', () {
    final source = Uri.parse('https://subscribe.example.com/s/token');
    final session = _session(
      endpoint: 'https://api.example.com',
      subscribeUrl: source,
      secureSubscription: true,
    );

    expect(session.legacySubscribeUrl, isNull);
    expect(session.subscribeUrl, source);
  });

  test('missing V1 URL is not reconstructed from the saved account token', () {
    final session = _session(endpoint: 'https://api.example.com');

    expect(session.token, isNotEmpty);
    expect(session.legacySubscribeUrl, isNull);
  });

  for (final endpoint in [
    '/api/v1/passport/auth/login',
    'ftp://api.example.com',
    'https://user:password@api.example.com',
  ]) {
    test('V1 rejects an invalid API endpoint: $endpoint', () {
      final session = _session(
        endpoint: endpoint,
        subscribeUrl: Uri.parse('https://subscribe.example.com/s/token'),
      );

      expect(() => session.legacySubscribeUrl, throwsFormatException);
    });
  }
}

XboardLoginResult _session({
  required String endpoint,
  Uri? subscribeUrl,
  bool secureSubscription = false,
}) {
  final api = Uri.parse(endpoint);
  return XboardLoginResult(
    endpoint: api,
    token: 'saved-subscription-token',
    authData: 'Bearer saved-session',
    isAdmin: false,
    secureSubscription: secureSubscription,
    subscription: XboardSubscriptionData(
      endpoint: api,
      subscribeUrl: subscribeUrl,
      uploadBytes: 0,
      downloadBytes: 0,
      transferEnableBytes: 1024,
      rawData: const {},
    ),
  );
}

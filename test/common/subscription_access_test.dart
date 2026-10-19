import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:fl_clash/common/api_network_diagnostic.dart';
import 'package:fl_clash/common/subscription_access.dart';
import 'package:fl_clash/common/subscription_v2.dart';
import 'package:fl_clash/common/xboard_auth.dart';
import 'package:fl_clash/common/xboard_refresh_coordinator.dart';
import 'package:fl_clash/l10n/l10n.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/api_health_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final now = DateTime.utc(2026, 10, 19);
  late AppLocalizations l10n;
  setUpAll(
    () async => l10n = await AppLocalizations.load(const Locale('zh', 'CN')),
  );

  test('explicit empty plan and zero allocation means not purchased', () {
    final data = _subscription(planId: null, quota: 0);
    expect(
      evaluateSubscriptionAccess(data, now: now),
      SubscriptionAccess.notPurchased,
    );
    expect(SubscriptionAccess.notPurchased.message(l10n), '尚未购买套餐，请先购买套餐');
  });

  test('expired plan and exact expiry boundary are business states', () {
    for (final expiry in [now.subtract(const Duration(seconds: 1)), now]) {
      final data = _subscription(expiry: expiry.millisecondsSinceEpoch ~/ 1000);
      expect(
        evaluateSubscriptionAccess(data, now: now),
        SubscriptionAccess.expired,
      );
    }
    expect(SubscriptionAccess.expired.message(l10n), '套餐已过期，请续费后连接');
  });

  test('future expiry and null unlimited expiry permit profile loading', () {
    for (final expiry in [null, now.millisecondsSinceEpoch ~/ 1000 + 1]) {
      expect(
        evaluateSubscriptionAccess(_subscription(expiry: expiry), now: now),
        SubscriptionAccess.available,
      );
    }
  });

  test('explicit zero expiry of a purchased plan is not unlimited access', () {
    expect(
      evaluateSubscriptionAccess(
        _subscription(raw: {'expired_at': 0}),
        now: now,
      ),
      SubscriptionAccess.expired,
    );
  });

  test('manual traffic grants without plan metadata remain usable', () {
    expect(
      evaluateSubscriptionAccess(_subscription(planId: null), now: now),
      SubscriptionAccess.available,
    );
  });

  test(
    'known plan with zero allocation is not mislabeled as never purchased',
    () {
      expect(
        evaluateSubscriptionAccess(_subscription(quota: 0), now: now),
        SubscriptionAccess.unknown,
      );
    },
  );

  test('used traffic does not turn a purchased plan into not purchased', () {
    final data = XboardSubscriptionData(
      endpoint: Uri.parse('https://api.example.com'),
      subscribeUrl: null,
      uploadBytes: 200,
      downloadBytes: 100,
      transferEnableBytes: 100,
      planId: 1,
      rawData: const {'plan_id': 1, 'expired_at': null, 'transfer_enable': 100},
    );
    expect(
      evaluateSubscriptionAccess(data, now: now),
      SubscriptionAccess.available,
    );
  });

  test('absent or malformed summary fields are not empty-plan evidence', () {
    for (final raw in [
      <String, Object?>{},
      {'plan_id': null},
      {'plan_id': null, 'transfer_enable': 'invalid', 'expired_at': null},
      {'plan_id': null, 'transfer_enable': 0, 'expired_at': 'invalid'},
      {'plan_id': null, 'plan': 'invalid', 'transfer_enable': 0},
      {'plan_id': 'invalid', 'plan': null, 'transfer_enable': 0},
      {'plan_id': null, 'transfer_enable': 0.5, 'expired_at': null},
    ]) {
      expect(
        evaluateSubscriptionAccess(
          _subscription(planId: null, quota: 0, rawOnly: raw),
          now: now,
        ),
        SubscriptionAccess.unknown,
      );
    }
  });

  test(
    'numeric-string summary is accepted without converting missing metadata',
    () {
      expect(
        evaluateSubscriptionAccess(
          _subscription(
            planId: null,
            quota: 0,
            rawOnly: {
              'plan_id': '0',
              'transfer_enable': '0',
              'expired_at': null,
            },
          ),
          now: now,
        ),
        SubscriptionAccess.notPurchased,
      );
    },
  );

  for (final data in [
    _subscription(planId: null, quota: 0),
    _subscription(expiry: 1),
  ]) {
    test(
      'blocked ${evaluateSubscriptionAccess(data).name} skips download and routing nonfatally',
      () async {
        final events = <Map<String, Object?>>[];
        final messages = <String>[];
        var downloads = 0;
        var routed = false;
        final result = await syncXboardProfileFirst<String?>(
          isCurrent: () => true,
          syncProfile: () => syncAccessibleSubscriptionProfile<String>(
            subscription: data,
            isCurrent: () => true,
            sync: () async {
              downloads++;
              return 'must not load';
            },
            onBlocked: (access) => messages.add(access.message(l10n)!),
            onDiagnostic: (event, fields) =>
                events.add({'event': event, ...fields}),
          ),
          prepareRouting: (profile) async {
            if (profile != null) routed = true;
          },
        );
        expect(result, isNull);
        expect(downloads, 0);
        expect(routed, isFalse);
        expect(messages.single, isNot(contains('检查网络')));
        expect(events.last['event'], 'subscription.profile.sync.skipped');
        expect(events.last['reason'], evaluateSubscriptionAccess(data).name);
        expect(events.toString(), isNot(contains('api.example.com')));
        expect(events.toString(), isNot(contains('token')));
      },
    );
  }

  test(
    'purchase or renewal resumes loading without clearing login identity',
    () async {
      var data = _subscription(planId: null, quota: 0);
      var downloads = 0;
      Future<String?> refresh() => syncAccessibleSubscriptionProfile<String>(
        subscription: data,
        isCurrent: () => true,
        sync: () async {
          downloads++;
          return 'renewed profile';
        },
        onBlocked: (_) {},
        onDiagnostic: (_, _) {},
      );
      expect(await refresh(), isNull);
      data = _subscription();
      expect(await refresh(), 'renewed profile');
      expect(downloads, 1);
    },
  );

  test('unknown summary continues attempting profile fetch', () async {
    var downloads = 0;
    expect(
      await syncAccessibleSubscriptionProfile<String>(
        subscription: _subscription(planId: null, quota: 0, rawOnly: {}),
        isCurrent: () => true,
        sync: () async {
          downloads++;
          return 'profile';
        },
        onBlocked: (_) => fail('missing fields must not mean no plan'),
        onDiagnostic: (_, _) {},
      ),
      'profile',
    );
    expect(downloads, 1);
  });

  test(
    'superseded session cannot show a business message or start download',
    () async {
      final events = <String>[];
      expect(
        await syncAccessibleSubscriptionProfile<String>(
          subscription: _subscription(planId: null, quota: 0),
          isCurrent: () => false,
          sync: () async => throw StateError('must not download'),
          onBlocked: (_) => fail('must not notify'),
          onDiagnostic: (event, _) => events.add(event),
        ),
        isNull,
      );
      expect(events, isEmpty);
    },
  );

  test('session replaced during request discards late result', () async {
    var current = true;
    final response = Completer<String>();
    final result = syncAccessibleSubscriptionProfile<String>(
      subscription: _subscription(),
      isCurrent: () => current,
      sync: () => response.future,
      onBlocked: (_) => fail('active plan'),
      onDiagnostic: (_, _) {},
    );
    current = false;
    response.complete('stale profile');
    expect(await result, isNull);
  });

  test(
    'overlapping refreshes share one access evaluation and one request',
    () async {
      final coordinator = XboardRefreshCoordinator<String?>();
      final response = Completer<String>();
      var calls = 0;
      Future<String?> refresh(XboardRefreshAttempt<String?> _) =>
          syncAccessibleSubscriptionProfile<String>(
            subscription: _subscription(),
            isCurrent: () => true,
            sync: () {
              calls++;
              return response.future;
            },
            onBlocked: (_) {},
            onDiagnostic: (_, _) {},
          );
      final first = coordinator.run(isCurrent: () => true, refresh: refresh);
      final second = coordinator.run(isCurrent: () => true, refresh: refresh);
      expect(identical(first, second), isTrue);
      response.complete('profile');
      expect(await first, 'profile');
      expect(await second, 'profile');
      expect(calls, 1);
    },
  );

  for (final error in <Object>[
    const SocketException('Failed host lookup'),
    TimeoutException('timed out'),
    const HandshakeException('certificate verify failed'),
    DioException.connectionTimeout(
      timeout: const Duration(seconds: 5),
      requestOptions: RequestOptions(path: '/profile'),
    ),
    const SubscriptionV2Exception(
      'gateway_unavailable',
      diagnostic: ApiNetworkDiagnostic(
        failure: ApiNetworkFailure.dns,
        stage: 'secure_gateway',
      ),
    ),
  ]) {
    test(
      'real transport ${error.runtimeType} uses network message and diagnostic',
      () {
        expect(
          subscriptionProfileFailureMessage(error, l10n),
          l10n.subscriptionImportFailed,
        );
        expect(subscriptionProfileDiagnostic(error), isNotNull);
      },
    );
  }

  for (final error in <Object>[
    const SubscriptionV2Exception('subscription_unavailable'),
    const SubscriptionV2Exception('gateway_unavailable', statusCode: 403),
    const SubscriptionV2Exception(
      'gateway_unavailable',
      diagnostic: ApiNetworkDiagnostic(
        failure: ApiNetworkFailure.http,
        stage: 'secure_gateway',
        statusCode: 503,
      ),
    ),
    const FormatException('invalid profile'),
    StateError('profile validation failed'),
    DioException.badResponse(
      statusCode: 403,
      requestOptions: RequestOptions(path: '/profile'),
      response: Response(
        requestOptions: RequestOptions(path: '/profile'),
        statusCode: 403,
      ),
    ),
  ]) {
    test(
      'service or format failure ${error.runtimeType} is not invented plan or network failure',
      () {
        expect(
          subscriptionProfileFailureMessage(error, l10n),
          l10n.subscriptionProfileUnavailable,
        );
      },
    );
  }

  for (final data in [
    <String, Object?>{
      'plan_id': null,
      'plan': null,
      'expired_at': null,
      'transfer_enable': 0,
    },
    <String, Object?>{'plan_id': 1, 'expired_at': 1, 'transfer_enable': 100},
  ]) {
    test(
      'login and plan catalog remain available for ${data['plan_id'] == null ? 'no plan' : 'expired plan'}',
      () async {
        final endpoint = Uri.parse('https://api.example.com');
        final service = XboardAuthService(
          apiHealthService: ApiHealthFixture(endpoint),
          loginRequester: (_, _, _) async => const XboardLoginResponse(
            statusCode: 200,
            data: {
              'data': {
                'token': 'test-token',
                'auth_data': 'Bearer test-token',
                'is_admin': false,
              },
            },
          ),
          subscriptionRequester: (_, _) async => XboardLoginResponse(
            statusCode: 200,
            data: {
              'data': {'u': 0, 'd': 0, ...data},
            },
          ),
          plansRequester: (_, _) async => const XboardLoginResponse(
            statusCode: 200,
            data: {
              'data': [
                {
                  'id': 1,
                  'name': 'Test plan',
                  'month_price': 1000,
                  'sell': 1,
                  'renew': 1,
                },
              ],
            },
          ),
        );
        final session = await service.login(
          email: 'test@example.com',
          password: 'fixture',
        );
        expect(session.authData, 'Bearer test-token');
        expect(
          evaluateSubscriptionAccess(session.subscription).blocksProfileSync,
          isTrue,
        );
        expect(
          await service.fetchPlans(
            endpoint: session.endpoint,
            authData: session.authData,
          ),
          hasLength(1),
        );
        expect(session.authData, 'Bearer test-token');
      },
    );
  }

  test(
    'legacy unknown network error retains DNS diagnostic and display text',
    () {
      final error = preserveSubscriptionDownloadError(
        DioException(
          requestOptions: RequestOptions(path: '/profile'),
          error: const SocketException('Failed host lookup'),
        ),
        l10n,
        Uri.parse('https://private.example.com/profile?token=must-not-log'),
      );
      expect(error.toString(), l10n.unknownNetworkError);
      final diagnostic = subscriptionProfileDiagnostic(error)!;
      expect(diagnostic.failure, ApiNetworkFailure.dns);
      expect(diagnostic.stage, 'subscription_download');
      expect(
        diagnostic.toDiagnosticFields().toString(),
        isNot(contains('must-not-log')),
      );
      expect(
        subscriptionProfileFailureMessage(error, l10n),
        l10n.subscriptionImportFailed,
      );
    },
  );

  test(
    'legacy rejected download retains HTTP status without claiming a plan state',
    () {
      final options = RequestOptions(path: '/profile');
      final error = preserveSubscriptionDownloadError(
        DioException.badResponse(
          statusCode: 403,
          requestOptions: options,
          response: Response(requestOptions: options, statusCode: 403),
        ),
        l10n,
        null,
      );
      expect(error.toString(), l10n.networkException);
      expect(
        subscriptionProfileDiagnostic(error)?.failure,
        ApiNetworkFailure.http,
      );
      expect(subscriptionProfileDiagnostic(error)?.statusCode, 403);
      expect(
        subscriptionProfileFailureMessage(error, l10n),
        l10n.subscriptionProfileUnavailable,
      );
    },
  );

  test('known legacy Dio failure remains the original typed exception', () {
    final error = DioException.connectionTimeout(
      timeout: const Duration(seconds: 1),
      requestOptions: RequestOptions(path: '/profile'),
    );
    expect(
      identical(preserveSubscriptionDownloadError(error, l10n, null), error),
      isTrue,
    );
  });

  for (final expired in [false, true]) {
    test('secure login remains valid with expired=$expired', () async {
      final service = XboardAuthService(
        apiHealthService: ApiHealthFixture(
          Uri.parse('https://api.example.com'),
        ),
        subscriptionV2Client: _SummaryOnlyClient({
          'plan_id': expired ? 1 : null,
          'plan': null,
          'expired_at': expired ? 1 : null,
          'transfer_enable': expired ? 100 : 0,
          'u': 0,
          'd': 0,
        }),
        loginRequester: (_, _, _) async =>
            throw StateError('must not fall back to legacy login'),
      );
      final session = await service.login(
        email: 'test@example.com',
        password: 'fixture',
      );
      expect(session.secureSubscription, isTrue);
      expect(session.authData, 'Bearer secure-test-token');
      expect(
        await syncAccessibleSubscriptionProfile<String>(
          subscription: session.subscription,
          isCurrent: () => true,
          sync: () async => throw StateError('must not download profile'),
          onBlocked: (access) => expect(
            access,
            expired
                ? SubscriptionAccess.expired
                : SubscriptionAccess.notPurchased,
          ),
          onDiagnostic: (_, _) {},
        ),
        isNull,
      );
      expect(session.authData, 'Bearer secure-test-token');
    });
  }

  test('real authentication rejection remains a login error', () async {
    final service = XboardAuthService(
      apiHealthService: ApiHealthFixture(Uri.parse('https://api.example.com')),
      loginRequester: (_, _, _) async => const XboardLoginResponse(
        statusCode: 401,
        data: {'message': 'rejected'},
      ),
    );
    await expectLater(
      service.login(email: 'test@example.com', password: 'fixture'),
      throwsA(
        isA<XboardAuthException>().having(
          (error) => error.failure,
          'failure',
          XboardAuthFailure.authenticationRejected,
        ),
      ),
    );
  });
}

class _SummaryOnlyClient extends SubscriptionV2Client {
  _SummaryOnlyClient(this.summary);

  final Map<String, Object?> summary;

  @override
  Future<SubscriptionV2Login?> secureLogin({
    required Uri endpoint,
    required String email,
    required String password,
    required String appVersion,
    String? platform,
  }) async => SubscriptionV2Login(
    endpoint: endpoint,
    token: 'secure-test-token',
    authData: 'Bearer secure-test-token',
    isAdmin: false,
    subscription: summary,
    rawData: const {},
  );
}

XboardSubscriptionData _subscription({
  int? planId = 1,
  int quota = 100,
  int? expiry,
  Map<String, Object?> raw = const {},
  Map<String, Object?>? rawOnly,
}) => XboardSubscriptionData(
  endpoint: Uri.parse('https://api.example.com'),
  subscribeUrl: null,
  uploadBytes: 0,
  downloadBytes: 0,
  transferEnableBytes: quota,
  planId: planId,
  expiredAtEpochSeconds: expiry,
  rawData:
      rawOnly ??
      {
        'plan_id': planId,
        'plan': null,
        'expired_at': expiry,
        'transfer_enable': quota,
        ...raw,
      },
);

import 'dart:async';

import 'package:fl_clash/common/api_health.dart';
import 'package:fl_clash/common/api_network_diagnostic.dart';
import 'package:fl_clash/common/xboard_auth.dart';
import 'package:fl_clash/l10n/l10n.dart';
import 'package:fl_clash/pages/login.dart';
import 'package:fl_clash/widgets/api_network_diagnostic_text.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  for (final size in [const Size(1200, 900), const Size(320, 640)]) {
    testWidgets('final network failure is actionable and retryable at $size', (
      tester,
    ) async {
      _useSize(tester, size);
      var attempts = 0;
      var navigations = 0;
      var exports = 0;
      await tester.pumpWidget(
        _app(
          onLogin: () => navigations++,
          authenticate: (_, _) async {
            attempts++;
            if (attempts == 1) {
              throw _failure(ApiNetworkFailure.permissionDenied);
            }
            return _session();
          },
          onExportLogs: () async {
            exports++;
            return true;
          },
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('login-network-failure')), findsNothing);
      await tester.tap(find.byKey(const Key('login-submit-button')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('login-network-failure')), findsOneWidget);
      expect(find.textContaining('联网权限被拒绝'), findsOneWidget);
      expect(find.textContaining('尚不能确定是哪个软件导致'), findsOneWidget);
      expect(find.textContaining('secret.invalid'), findsNothing);
      await tester.tap(find.byKey(const Key('login-export-logs')));
      await tester.pumpAndSettle();
      expect(exports, 1);
      expect(find.text('导出成功'), findsOneWidget);
      await tester.tap(find.byKey(const Key('login-api-diagnostics')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('api-health-dialog')), findsOneWidget);
      expect(find.textContaining('仅检测配置与 API 能否连通'), findsOneWidget);
      await tester.tap(find.byKey(const Key('api-health-dialog-close')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('login-submit-button')));
      await tester.pumpAndSettle();
      expect(attempts, 2);
      expect(navigations, 1);
      expect(find.byKey(const Key('login-network-failure')), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('intermediate pending login shows no failure or extra submit', (
    tester,
  ) async {
    _useSize(tester, const Size(1200, 900));
    final pending = Completer<XboardLoginResult>();
    var attempts = 0;
    await tester.pumpWidget(
      _app(
        authenticate: (_, _) {
          attempts++;
          return pending.future;
        },
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('login-submit-button')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('login-submit-button')));
    expect(attempts, 1);
    expect(find.byKey(const Key('login-network-failure')), findsNothing);
    pending.complete(_session());
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('login-network-failure')), findsNothing);
  });

  testWidgets('late final authentication failure is safe after disposal', (
    tester,
  ) async {
    _useSize(tester, const Size(1200, 900));
    final pending = Completer<XboardLoginResult>();
    await tester.pumpWidget(_app(authenticate: (_, _) => pending.future));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('login-submit-button')));
    await tester.pump();
    await tester.pumpWidget(const SizedBox());
    pending.completeError(_failure(ApiNetworkFailure.tls));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('business password failure does not claim a network failure', (
    tester,
  ) async {
    _useSize(tester, const Size(1200, 900));
    await tester.pumpWidget(
      _app(
        authenticate: (_, _) async => throw const XboardAuthException(
          failure: XboardAuthFailure.authenticationRejected,
          message: '邮箱或密码错误',
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('login-submit-button')));
    await tester.pumpAndSettle();
    expect(find.text('邮箱或密码错误'), findsOneWidget);
    expect(find.byKey(const Key('login-network-failure')), findsNothing);
  });

  for (final entry in {
    XboardAuthFailure.unavailable: '服务暂时不可用，请稍后重试',
    XboardAuthFailure.secureProtocolRejected: '安全登录响应校验失败，请导出日志',
  }.entries) {
    testWidgets(
      '${entry.key.name} without diagnostics does not claim a network failure',
      (tester) async {
        _useSize(tester, const Size(1200, 900));
        await tester.pumpWidget(
          _app(
            authenticate: (_, _) async => throw XboardAuthException(
              failure: entry.key,
              message: entry.value,
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('login-submit-button')));
        await tester.pumpAndSettle();
        expect(find.text(entry.value), findsOneWidget);
        expect(find.byKey(const Key('login-network-failure')), findsNothing);
      },
    );
  }

  testWidgets('export failure resets busy state and allows retry', (
    tester,
  ) async {
    _useSize(tester, const Size(1200, 900));
    var exports = 0;
    await tester.pumpWidget(
      _app(
        authenticate: (_, _) async => throw _failure(ApiNetworkFailure.timeout),
        onExportLogs: () async {
          exports++;
          if (exports == 1) throw StateError('secret.invalid/token');
          return true;
        },
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('login-submit-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('login-export-logs')));
    await tester.pumpAndSettle();
    expect(find.text('日志导出失败，请重试。'), findsOneWidget);
    expect(find.textContaining('secret.invalid'), findsNothing);
    await tester.tap(find.byKey(const Key('login-export-logs')));
    await tester.pumpAndSettle();
    expect(exports, 2);
    expect(tester.takeException(), isNull);
  });

  testWidgets('export ignores duplicate taps and disposal', (tester) async {
    _useSize(tester, const Size(1200, 900));
    final pending = Completer<bool>();
    var exports = 0;
    await tester.pumpWidget(
      _app(
        authenticate: (_, _) async => throw _failure(ApiNetworkFailure.dns),
        onExportLogs: () {
          exports++;
          return pending.future;
        },
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('login-submit-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('login-export-logs')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('login-export-logs')));
    expect(exports, 1);
    await tester.pumpWidget(const SizedBox());
    pending.completeError(StateError('failed'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  for (final locale in [
    const Locale('en'),
    const Locale('zh', 'CN'),
    const Locale('ja'),
    const Locale('ru'),
  ]) {
    testWidgets('all typed reasons are localized in $locale', (tester) async {
      await tester.pumpWidget(
        _localized(
          locale: locale,
          child: Builder(
            builder: (context) => SingleChildScrollView(
              child: Column(
                children: [
                  for (final failure in ApiNetworkFailure.values)
                    Text(
                      apiNetworkDiagnosticMessage(
                        context,
                        ApiNetworkDiagnostic(
                          failure: failure,
                          stage: 'not-user-visible',
                          statusCode: 403,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('HTTP 403'), findsOneWidget);
      expect(find.textContaining('not-user-visible'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }
}

Widget _app({
  required Future<XboardLoginResult> Function(String, String) authenticate,
  VoidCallback? onLogin,
  Future<bool> Function()? onExportLogs,
}) {
  return _localized(
    child: LoginPage(
      onLogin: onLogin ?? () {},
      onLanguagePressed: (_) {},
      onThemePressed: (_) {},
      onSupportPressed: (_) {},
      appVersion: '0.8.99',
      authenticate: authenticate,
      prefill: const LoginFormPrefill(
        email: 'user@example.com',
        password: 'test-password',
      ),
      apiHealthService: ApiHealthService(configUrl: ''),
      onExportLogs: onExportLogs,
    ),
  );
}

Widget _localized({
  required Widget child,
  Locale locale = const Locale('zh', 'CN'),
}) {
  return MaterialApp(
    locale: locale,
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
    ],
    supportedLocales: AppLocalizations.delegate.supportedLocales,
    home: child,
  );
}

void _useSize(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

XboardAuthException _failure(ApiNetworkFailure failure) {
  return XboardAuthException(
    failure: XboardAuthFailure.unavailable,
    message: 'secret.invalid/private?token=not-for-display',
    diagnostic: ApiNetworkDiagnostic(failure: failure, stage: 'login'),
  );
}

XboardLoginResult _session() {
  final endpoint = Uri.parse('https://api.example.com');
  return XboardLoginResult(
    endpoint: endpoint,
    token: 'subscription-token',
    authData: 'Bearer login-token',
    isAdmin: false,
    subscription: XboardSubscriptionData(
      endpoint: endpoint,
      subscribeUrl: Uri.parse('https://subscribe.example.com/client/token'),
      uploadBytes: 0,
      downloadBytes: 0,
      transferEnableBytes: bytesPerGigabyte,
      rawData: const {},
    ),
  );
}

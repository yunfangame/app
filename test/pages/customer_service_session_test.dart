import 'dart:async';

import 'package:fl_clash/l10n/l10n.dart';
import 'package:fl_clash/pages/customer_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webview_platform_interface/webview_platform_interface.dart';

void main() {
  late _WebViewPlatform platform;
  final uri = crispServiceUri;
  const user = CrispSupportUser(accountKey: 'user-a');

  setUp(() {
    platform = _WebViewPlatform();
    WebViewPlatform.instance = platform;
  });

  testWidgets('reopening retains the page without another network load', (
    tester,
  ) async {
    final cache = CustomerServiceSessionCache();
    try {
      final first = cache.acquire(uri, user: user);
      await _show(tester, first);
      await tester.pumpWidget(const SizedBox.shrink());
      cache.release(first);
      await tester.pump(const Duration(seconds: 10));
      final second = cache.acquire(uri, user: user);
      await _show(tester, second);
      expect(second, same(first));
      expect(platform.controllers, hasLength(1));
      expect(platform.controllers.single.requests, [uri]);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      cache.clear();
      await tester.pump();
    }
  });

  testWidgets('unused sessions expire and release the native WebView', (
    tester,
  ) async {
    final cache = CustomerServiceSessionCache(
      keepAlive: const Duration(seconds: 5),
    );
    try {
      final first = cache.acquire(uri, user: user);
      await tester.pump();
      cache.release(first);
      await tester.pump(const Duration(seconds: 6));
      expect(platform.controllers.first.closes, 1);
      final second = cache.acquire(uri, user: user);
      expect(second, isNot(same(first)));
      expect(second.sessionToken, first.sessionToken);
      await tester.pump();
      expect(platform.controllers, hasLength(2));
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      cache.clear();
      await tester.pump();
    }
  });

  testWidgets('changing account or URL starts a separate page', (tester) async {
    final cache = CustomerServiceSessionCache();
    try {
      final first = cache.acquire(uri, user: user);
      await tester.pump();
      final second = cache.acquire(
        uri,
        user: const CrispSupportUser(accountKey: 'user-b'),
      );
      await tester.pump();
      expect(second, isNot(same(first)));
      expect(second.sessionToken, isNot(first.sessionToken));
      expect(platform.controllers.first.closes, 1);
      final third = cache.acquire(
        Uri.parse('https://support.example.com'),
        user: const CrispSupportUser(accountKey: 'user-b'),
      );
      await tester.pump();
      expect(third, isNot(same(second)));
      expect(platform.controllers[1].closes, 1);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      cache.clear();
      await tester.pump();
    }
  });

  testWidgets('waits for chat readiness and offers recovery for slow loading', (
    tester,
  ) async {
    final session = CustomerServiceSession(
      uri,
      sessionToken: 'test-token',
      user: user,
    );
    try {
      await _show(tester, session);
      final controller = platform.controllers.single;
      platform.delegate.onPageFinished!(uri.toString());
      await tester.pump(const Duration(seconds: 13));
      expect(session.ready, isFalse);
      expect(find.byKey(const Key('customer-service-retry')), findsOneWidget);
      expect(
        find.byKey(const Key('customer-service-open-browser')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('test-native-webview')), findsOneWidget);
      controller.channel!.onMessageReceived(
        const JavaScriptMessage(message: 'ready'),
      );
      await tester.pump();
      expect(session.ready, isTrue);
      expect(find.byKey(const Key('customer-service-retry')), findsNothing);
      expect(find.byType(LinearProgressIndicator), findsNothing);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await session.close();
      await tester.pump();
    }
  });

  testWidgets(
    'slow-load retry reloads the original URL and clears the notice',
    (tester) async {
      final session = CustomerServiceSession(
        uri,
        sessionToken: 'test-token',
        user: user,
      );
      try {
        await _show(tester, session);
        await tester.pump(const Duration(seconds: 13));
        await tester.tap(find.byKey(const Key('customer-service-retry')));
        await tester.pump();
        expect(platform.controllers.single.requests, [uri, uri]);
        expect(session.slow, isFalse);
        await tester.pumpWidget(const SizedBox.shrink());
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await session.close();
        await tester.pump();
      }
    },
  );

  testWidgets(
    'ignores subresource failures and recovers from main-frame errors',
    (tester) async {
      final session = CustomerServiceSession(
        uri,
        sessionToken: 'test-token',
        user: user,
      );
      try {
        await _show(tester, session);
        platform.delegate.onError!(
          const WebResourceError(
            errorCode: -1,
            description: 'private diagnostic',
            isForMainFrame: false,
          ),
        );
        expect(session.failed, isFalse);
        platform.delegate.onError!(
          const WebResourceError(
            errorCode: -1,
            description: 'private diagnostic',
            isForMainFrame: true,
          ),
        );
        await tester.pump();
        expect(session.failed, isTrue);
        expect(find.text('private diagnostic'), findsNothing);
        expect(find.text('客服页面加载失败，请重试或在浏览器中打开。'), findsOneWidget);
        await session.reload();
        await tester.pump();
        expect(session.failed, isFalse);
        expect(platform.controllers.single.requests, [uri, uri]);
        await tester.pumpWidget(const SizedBox.shrink());
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await session.close();
        await tester.pump();
      }
    },
  );

  testWidgets('a failed load request is recoverable', (tester) async {
    platform.failLoad = true;
    final session = CustomerServiceSession(
      uri,
      sessionToken: 'test-token',
      user: user,
    );
    try {
      await tester.pump();
      expect(session.failed, isTrue);
      platform.controllers.single.failLoad = false;
      await session.reload();
      expect(session.failed, isFalse);
      expect(platform.controllers.single.requests, [uri, uri]);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await session.close();
      await tester.pump();
    }
  });

  testWidgets('failed initialization can be retried', (tester) async {
    platform.failInitialization = true;
    final session = CustomerServiceSession(
      uri,
      sessionToken: 'test-token',
      user: user,
    );
    try {
      await tester.pump();
      expect(session.failed, isTrue);
      platform.failInitialization = false;
      await session.reload();
      expect(session.failed, isFalse);
      expect(platform.controllers.single.requests, [uri]);
    } finally {
      await session.close();
      await tester.pump();
    }
  });

  testWidgets('reopening syncs new package data without recreating the page', (
    tester,
  ) async {
    final cache = CustomerServiceSessionCache();
    try {
      final first = cache.acquire(uri, user: user);
      await tester.pump();
      platform.controllers.single.channel!.onMessageReceived(
        const JavaScriptMessage(message: 'ready'),
      );
      await tester.pump();
      cache.release(first);
      final second = cache.acquire(
        uri,
        user: const CrispSupportUser(
          accountKey: 'user-a',
          email: 'user@example.com',
          data: {'plan': 'new-plan', 'traffic_used_bytes': 12345},
        ),
      );
      await tester.pump();
      expect(second, same(first));
      expect(platform.controllers.single.requests, [uri]);
      expect(platform.controllers.single.scripts.last, contains('new-plan'));
      expect(platform.controllers.single.scripts.last, contains('12345'));
    } finally {
      cache.clear();
      await tester.pump();
    }
  });

  testWidgets('closing during initialization prevents a late page load', (
    tester,
  ) async {
    final gate = Completer<void>();
    platform.initializationGate = gate.future;
    final session = CustomerServiceSession(
      uri,
      sessionToken: 'test-token',
      user: user,
    );
    final closing = session.close();
    gate.complete();
    await closing;
    await session.close();
    expect(platform.controllers.single.requests, isEmpty);
    expect(platform.controllers.single.closes, 1);
    await tester.pump(const Duration(seconds: 13));
    expect(tester.takeException(), isNull);
  });
}

Future<void> _show(WidgetTester tester, CustomerServiceSession session) async {
  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('zh', 'CN'),
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.delegate.supportedLocales,
      home: Scaffold(
        body: CustomerServiceView(
          serviceUrl: session.uri.toString(),
          session: session,
        ),
      ),
    ),
  );
  await tester.pump();
}

class _WebViewPlatform extends WebViewPlatform {
  final controllers = <_Controller>[];
  late _Delegate delegate;
  bool failInitialization = false;
  bool failLoad = false;
  Future<void>? initializationGate;

  @override
  PlatformWebViewController createPlatformWebViewController(
    PlatformWebViewControllerCreationParams params,
  ) {
    final controller = _Controller(params, this);
    controllers.add(controller);
    return controller;
  }

  @override
  PlatformNavigationDelegate createPlatformNavigationDelegate(
    PlatformNavigationDelegateCreationParams params,
  ) => delegate = _Delegate(params);

  @override
  PlatformWebViewWidget createPlatformWebViewWidget(
    PlatformWebViewWidgetCreationParams params,
  ) => _Widget(params);
}

class _Controller extends PlatformWebViewController {
  _Controller(super.params, this.owner)
    : failLoad = owner.failLoad,
      super.implementation();
  final _WebViewPlatform owner;
  final requests = <Uri>[];
  final scripts = <String>[];
  int closes = 0;
  bool failLoad;
  JavaScriptChannelParams? channel;

  @override
  Future<void> setJavaScriptMode(JavaScriptMode mode) async {
    await owner.initializationGate;
    if (owner.failInitialization) throw StateError('not initialized');
  }

  @override
  Future<void> setPlatformNavigationDelegate(
    PlatformNavigationDelegate handler,
  ) async {}
  @override
  Future<void> addJavaScriptChannel(JavaScriptChannelParams params) async {
    channel = params;
  }

  @override
  Future<void> setUserAgent(String? value) async {}
  @override
  Future<void> loadRequest(LoadRequestParams params) async {
    requests.add(params.uri);
    if (failLoad) throw StateError('load failed');
  }

  @override
  Future<void> runJavaScript(String source) async {
    scripts.add(source);
  }

  @override
  Future<bool> isOffscreenWebViewSupported() async => true;
  @override
  Future<void> closeOffscreenWebView() async {
    closes++;
  }
}

class _Delegate extends PlatformNavigationDelegate {
  _Delegate(super.params) : super.implementation();
  PageEventCallback? onPageFinished;
  WebResourceErrorCallback? onError;
  @override
  Future<void> setOnNavigationRequest(
    NavigationRequestCallback callback,
  ) async {}
  @override
  Future<void> setOnPageStarted(PageEventCallback callback) async {}
  @override
  Future<void> setOnPageFinished(PageEventCallback callback) async {
    onPageFinished = callback;
  }

  @override
  Future<void> setOnProgress(ProgressCallback callback) async {}
  @override
  Future<void> setOnWebResourceError(WebResourceErrorCallback callback) async {
    onError = callback;
  }
}

class _Widget extends PlatformWebViewWidget {
  _Widget(super.params) : super.implementation();
  @override
  Widget build(BuildContext context) =>
      const SizedBox.expand(key: Key('test-native-webview'));
}

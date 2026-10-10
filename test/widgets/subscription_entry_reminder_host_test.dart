import 'dart:async';

import 'package:fl_clash/common/subscription_entry_reminder.dart';
import 'package:fl_clash/common/xboard_auth.dart';
import 'package:fl_clash/l10n/l10n.dart';
import 'package:fl_clash/state.dart';
import 'package:fl_clash/widgets/subscription_entry_reminder_host.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';

import '../support/api_health_fixture.dart';

const _reminderKey = ValueKey('subscription-entry-reminder-dialog');
const _closeKey = ValueKey('subscription-entry-reminder-close');
const _disableKey = ValueKey('subscription-entry-reminder-dont-remind');
final _now = DateTime(2026, 10, 9, 12);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    globalState.clearXboardSession();
    globalState.setOfflineMode(false);
    WidgetsBinding.instance.handleAppLifecycleStateChanged(
      AppLifecycleState.resumed,
    );
  });

  tearDown(() {
    globalState.clearXboardSession();
    globalState.setOfflineMode(false);
  });

  testWidgets('cold entry queries without blocking connection controls', (
    tester,
  ) async {
    final session = _activate();
    final service = _FakeAuthService();
    final response = service.enqueue();
    var connections = 0;
    await _pumpHost(
      tester,
      service,
      child: FilledButton(
        key: const ValueKey('connect-fixture'),
        onPressed: () => connections++,
        child: const Text('连接测试'),
      ),
    );

    expect(service.calls, 1);
    expect(find.byKey(_reminderKey), findsNothing);
    await tester.tap(find.byKey(const ValueKey('connect-fixture')));
    await tester.pump();
    expect(connections, 1);
    expect(service.calls, 1);

    final subscription = _subscription(remainingGb: 8);
    response.complete(subscription);
    await tester.pumpAndSettle();
    expect(find.byKey(_reminderKey), findsOneWidget);
    expect(find.byType(TextButton), findsOneWidget);
    expect(find.byKey(_closeKey), findsOneWidget);
    expect(globalState.xboardSubscription, same(subscription));
    expect(globalState.xboardSession, same(session));
    await _finish(tester, service);
  });

  testWidgets('ordinary dismissal waits for a new background entry', (
    tester,
  ) async {
    _activate();
    final service = _FakeAuthService(defaultResponse: () => _subscription());
    await _pumpHost(tester, service);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(_closeKey));
    await tester.pumpAndSettle();
    final lifecycle = _lifecycle(tester);
    lifecycle.didChangeAppLifecycleState(AppLifecycleState.inactive);
    lifecycle.didChangeAppLifecycleState(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(service.calls, 1);
    expect(find.byKey(_reminderKey), findsNothing);

    lifecycle.didChangeAppLifecycleState(AppLifecycleState.paused);
    lifecycle.didChangeAppLifecycleState(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(service.calls, 2);
    expect(find.byKey(_reminderKey), findsOneWidget);
    await _finish(tester, service);
  });

  testWidgets('window show and restore signals share a single entry', (
    tester,
  ) async {
    _activate();
    final service = _FakeAuthService(defaultResponse: () => _subscription());
    await _pumpHost(tester, service);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(_closeKey));
    await tester.pumpAndSettle();
    final listener = tester.state(find.byType(SubscriptionEntryReminderHost));
    final window = listener as WindowListener;
    window.onWindowEvent('hide');
    window.onWindowEvent('show');
    window.onWindowRestore();
    _lifecycle(tester).didChangeAppLifecycleState(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(service.calls, 2);
    expect(find.byKey(_reminderKey), findsOneWidget);
    window.onWindowRestore();
    window.onWindowEvent('show');
    await tester.pumpAndSettle();
    expect(service.calls, 2);
    expect(find.byKey(_reminderKey), findsOneWidget);
    await _finish(tester, service);
  });

  testWidgets('do not remind persists across restart for this account only', (
    tester,
  ) async {
    final first = _activate();
    final service = _FakeAuthService(defaultResponse: () => _subscription());
    await _pumpHost(tester, service);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(_disableKey));
    await tester.pumpAndSettle();
    final firstKey = SubscriptionEntryReminderStore.accountKey(first)!;
    expect(await SubscriptionEntryReminderStore().isDisabled(firstKey), isTrue);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    _activate();
    await _pumpHost(tester, service);
    await tester.pumpAndSettle();
    expect(service.calls, 1);
    expect(find.byKey(_reminderKey), findsNothing);

    final second = _activate(account: 'second');
    service.defaultResponse = () => _subscription(account: 'second');
    await tester.pumpAndSettle();
    expect(service.calls, 2);
    expect(find.byKey(_reminderKey), findsOneWidget);
    expect(
      await SubscriptionEntryReminderStore().isDisabled(
        SubscriptionEntryReminderStore.accountKey(second)!,
      ),
      isFalse,
    );
    await _finish(tester, service);
  });

  testWidgets('network failure preserves the snapshot and child interaction', (
    tester,
  ) async {
    final initial = _activate().subscription;
    final service = _FakeAuthService();
    final response = service.enqueue();
    var taps = 0;
    await _pumpHost(
      tester,
      service,
      child: TextButton(onPressed: () => taps++, child: const Text('操作测试')),
    );
    response.completeError(StateError('fixture_network_unavailable'));
    await tester.pumpAndSettle();
    expect(find.byKey(_reminderKey), findsNothing);
    expect(globalState.xboardSubscription, same(initial));
    await tester.tap(find.text('操作测试'));
    await tester.pump();
    expect(taps, 1);
    await _finish(tester, service);
  });

  testWidgets('timeout rejects the late response and does not block the page', (
    tester,
  ) async {
    final initial = _activate().subscription;
    final service = _FakeAuthService();
    final response = service.enqueue();
    await _pumpHost(tester, service, timeout: const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 60));
    response.complete(_subscription());
    await tester.pumpAndSettle();
    expect(find.byKey(_reminderKey), findsNothing);
    expect(find.text('主页测试'), findsOneWidget);
    expect(globalState.xboardSubscription, same(initial));
    await _finish(tester, service);
  });

  testWidgets('late response from the previous account cannot show or write', (
    tester,
  ) async {
    _activate();
    final service = _FakeAuthService();
    final firstResponse = service.enqueue();
    final secondResponse = service.enqueue();
    await _pumpHost(tester, service);
    final second = _activate(account: 'second');
    await tester.pump();
    await tester.pump();
    expect(service.calls, 2);
    firstResponse.complete(_subscription());
    await tester.pumpAndSettle();
    expect(globalState.xboardSubscription, same(second.subscription));
    expect(find.byKey(_reminderKey), findsNothing);
    final fresh = _subscription(account: 'second', remainingGb: 20);
    secondResponse.complete(fresh);
    await tester.pumpAndSettle();
    expect(globalState.xboardSubscription, same(fresh));
    expect(find.byKey(_reminderKey), findsNothing);
    await _finish(tester, service);
  });

  testWidgets('a newer snapshot in the same session wins over an old query', (
    tester,
  ) async {
    final session = _activate();
    final service = _FakeAuthService();
    final response = service.enqueue();
    await _pumpHost(tester, service);
    final newer = _subscription(remainingGb: 25);
    globalState.updateXboardSubscriptionSnapshot(session, newer);
    response.complete(_subscription());
    await tester.pumpAndSettle();
    expect(globalState.xboardSubscription, same(newer));
    expect(find.byKey(_reminderKey), findsNothing);
    await _finish(tester, service);
  });

  testWidgets('the newer app entry owns the response and popup', (
    tester,
  ) async {
    _activate();
    final service = _FakeAuthService();
    final firstResponse = service.enqueue();
    final secondResponse = service.enqueue();
    await _pumpHost(tester, service);
    final lifecycle = _lifecycle(tester);
    lifecycle.didChangeAppLifecycleState(AppLifecycleState.paused);
    lifecycle.didChangeAppLifecycleState(AppLifecycleState.resumed);
    await tester.pump();
    await tester.pump();
    expect(service.calls, 2);
    final newer = _subscription(remainingGb: 27);
    secondResponse.complete(newer);
    await tester.pumpAndSettle();
    firstResponse.complete(_subscription());
    await tester.pumpAndSettle();
    expect(globalState.xboardSubscription, same(newer));
    expect(find.byKey(_reminderKey), findsNothing);
    await _finish(tester, service);
  });

  testWidgets('offline transition invalidates an in flight query', (
    tester,
  ) async {
    final initial = _activate().subscription;
    final service = _FakeAuthService();
    final response = service.enqueue();
    await _pumpHost(tester, service);
    globalState.setOfflineMode(true);
    response.complete(_subscription());
    await tester.pumpAndSettle();
    expect(find.byKey(_reminderKey), findsNothing);
    expect(globalState.xboardSubscription, same(initial));
    await _finish(tester, service);
  });

  testWidgets('offline mode does not query or show an advance reminder', (
    tester,
  ) async {
    _activate();
    globalState.setOfflineMode(true);
    final service = _FakeAuthService(defaultResponse: () => _subscription());
    await _pumpHost(tester, service);
    await tester.pumpAndSettle();
    expect(service.calls, 0);
    expect(find.byKey(_reminderKey), findsNothing);
    await _finish(tester, service);
  });

  testWidgets('disposing the host rejects a late response', (tester) async {
    final initial = _activate().subscription;
    final service = _FakeAuthService();
    final response = service.enqueue();
    await _pumpHost(tester, service);
    await tester.pumpWidget(const SizedBox.shrink());
    response.complete(_subscription());
    await tester.pumpAndSettle();
    expect(globalState.xboardSubscription, same(initial));
    expect(find.byKey(_reminderKey), findsNothing);
    await _finish(tester, service);
  });

  testWidgets('background removes its dialog and resumes with one new query', (
    tester,
  ) async {
    _activate();
    final service = _FakeAuthService(defaultResponse: () => _subscription());
    await _pumpHost(tester, service);
    await tester.pumpAndSettle();
    expect(find.byKey(_reminderKey), findsOneWidget);
    final lifecycle = _lifecycle(tester);
    lifecycle.didChangeAppLifecycleState(AppLifecycleState.hidden);
    await tester.pumpAndSettle();
    expect(find.byKey(_reminderKey), findsNothing);
    lifecycle.didChangeAppLifecycleState(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(service.calls, 2);
    expect(find.byKey(_reminderKey), findsOneWidget);
    globalState.setOfflineMode(true);
    await tester.pumpAndSettle();
    expect(find.byKey(_reminderKey), findsNothing);
    await _finish(tester, service);
  });

  testWidgets('disposing only the host removes its own active dialog', (
    tester,
  ) async {
    _activate();
    final service = _FakeAuthService(defaultResponse: () => _subscription());
    final visible = ValueNotifier(true);
    addTearDown(visible.dispose);
    await tester.pumpWidget(
      _TestApp(
        child: ValueListenableBuilder<bool>(
          valueListenable: visible,
          builder: (_, active, _) =>
              active ? _host(service) : const Text('主页测试'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(_reminderKey), findsOneWidget);
    visible.value = false;
    await tester.pumpAndSettle();
    expect(find.byKey(_reminderKey), findsNothing);
    expect(find.text('主页测试'), findsOneWidget);
    await _finish(tester, service);
  });

  testWidgets('waits for another modal to close without stacking reminders', (
    tester,
  ) async {
    _activate();
    final service = _FakeAuthService();
    final response = service.enqueue();
    await _pumpHost(
      tester,
      service,
      child: Builder(
        builder: (context) => TextButton(
          key: const ValueKey('open-other-modal'),
          onPressed: () => showDialog<void>(
            context: context,
            builder: (dialogContext) => AlertDialog(
              key: const ValueKey('other-modal'),
              title: const Text('其他窗口测试'),
              actions: [
                TextButton(
                  key: const ValueKey('close-other-modal'),
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('关闭其他窗口'),
                ),
              ],
            ),
          ),
          child: const Text('打开其他窗口'),
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('open-other-modal')));
    await tester.pumpAndSettle();
    response.complete(_subscription());
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('other-modal')), findsOneWidget);
    expect(find.byKey(_reminderKey), findsNothing);
    expect(find.byType(AlertDialog), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('close-other-modal')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('other-modal')), findsNothing);
    expect(find.byKey(_reminderKey), findsOneWidget);
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(service.calls, 1);
    await _finish(tester, service);
  });

  testWidgets('logout removes its reminder without removing another modal', (
    tester,
  ) async {
    _activate();
    final service = _FakeAuthService(defaultResponse: () => _subscription());
    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      _TestApp(navigatorKey: navigator, child: _host(service)),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(_reminderKey), findsOneWidget);
    unawaited(
      showDialog<void>(
        context: navigator.currentContext!,
        builder: (_) => const AlertDialog(
          key: ValueKey('foreign-modal'),
          title: Text('独立窗口测试'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    globalState.clearXboardSession();
    await tester.pumpAndSettle();
    expect(find.byKey(_reminderKey, skipOffstage: false), findsNothing);
    expect(find.byKey(const ValueKey('foreign-modal')), findsOneWidget);
    expect(service.calls, 1);
    navigator.currentState!.pop();
    await tester.pumpAndSettle();
    await _finish(tester, service);
  });

  testWidgets('a fresh snapshot cancels a reminder waiting behind a modal', (
    tester,
  ) async {
    final session = _activate();
    final service = _FakeAuthService();
    final response = service.enqueue();
    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      _TestApp(navigatorKey: navigator, child: _host(service)),
    );
    await tester.pump();
    await tester.pump();
    unawaited(
      showDialog<void>(
        context: navigator.currentContext!,
        builder: (_) => const AlertDialog(
          key: ValueKey('foreign-modal'),
          title: Text('独立窗口测试'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    response.complete(_subscription());
    await tester.pumpAndSettle();
    expect(find.byKey(_reminderKey), findsNothing);
    final newer = _subscription(remainingGb: 25);
    globalState.updateXboardSubscriptionSnapshot(session, newer);
    navigator.currentState!.pop();
    await tester.pumpAndSettle();
    expect(find.byKey(_reminderKey), findsNothing);
    expect(globalState.xboardSubscription, same(newer));
    await _finish(tester, service);
  });

  testWidgets('a response for another account is discarded', (tester) async {
    final initial = _activate().subscription;
    final service = _FakeAuthService(
      defaultResponse: () => _subscription(account: 'second'),
    );
    await _pumpHost(tester, service);
    await tester.pumpAndSettle();
    expect(globalState.xboardSubscription, same(initial));
    expect(find.byKey(_reminderKey), findsNothing);
    await _finish(tester, service);
  });

  for (final hours in [168, 169]) {
    testWidgets('monthly low traffic with reset in $hours hours', (
      tester,
    ) async {
      _activate();
      final service = _FakeAuthService(
        defaultResponse: () => _subscription(
          expiresAt: _now.add(const Duration(days: 30)),
          resetAt: _now.add(Duration(hours: hours)),
        ),
      );
      await _pumpHost(tester, service);
      await tester.pumpAndSettle();
      expect(
        find.byKey(_reminderKey),
        hours > 168 ? findsOneWidget : findsNothing,
      );
      await _finish(tester, service);
    });
  }

  for (final entry in [
    ('healthy', 20, null),
    ('exhausted', 0, null),
    ('expired', 8, _now.subtract(const Duration(hours: 1))),
  ]) {
    testWidgets('${entry.$1} plan has no advance reminder', (tester) async {
      _activate();
      final service = _FakeAuthService(
        defaultResponse: () =>
            _subscription(remainingGb: entry.$2, expiresAt: entry.$3),
      );
      await _pumpHost(tester, service);
      await tester.pumpAndSettle();
      expect(service.calls, 1);
      expect(find.byKey(_reminderKey), findsNothing);
      await _finish(tester, service);
    });
  }

  testWidgets('monthly expiry warning renders time and reset countdown', (
    tester,
  ) async {
    _activate();
    final service = _FakeAuthService(
      defaultResponse: () => _subscription(
        remainingGb: 20,
        expiresAt: _now.add(const Duration(days: 2, hours: 4)),
        resetAt: _now.add(const Duration(days: 1, hours: 3)),
      ),
    );
    await _pumpHost(tester, service);
    await tester.pumpAndSettle();
    expect(find.byKey(_reminderKey), findsOneWidget);
    expect(
      find.byKey(const ValueKey('subscription-entry-reminder-expiry')),
      findsOneWidget,
    );
    expect(find.textContaining('1 天 3 小时'), findsOneWidget);
    await _finish(tester, service);
  });
}

XboardSubscriptionData _subscription({
  String account = 'first',
  int remainingGb = 8,
  DateTime? expiresAt,
  DateTime? resetAt,
}) => XboardSubscriptionData(
  endpoint: Uri.parse('https://api.example.com'),
  subscribeUrl: null,
  uploadBytes: 0,
  downloadBytes: (30 - remainingGb) * bytesPerGigabyte,
  transferEnableBytes: 30 * bytesPerGigabyte,
  planId: 1,
  email: '$account@example.com',
  uuid: 'fixture-$account',
  expiredAtEpochSeconds: expiresAt == null
      ? null
      : expiresAt.millisecondsSinceEpoch ~/ 1000,
  nextResetAtEpochSeconds: resetAt == null
      ? null
      : resetAt.millisecondsSinceEpoch ~/ 1000,
  rawData: const {},
);

XboardLoginResult _activate({String account = 'first'}) {
  final session = XboardLoginResult(
    endpoint: Uri.parse('https://api.example.com'),
    token: 'fixture-$account',
    authData: 'fixture-auth-$account',
    isAdmin: false,
    subscription: _subscription(account: account, remainingGb: 30),
    rawData: const {},
  );
  globalState.activateXboardSession(session);
  return session;
}

WidgetsBindingObserver _lifecycle(WidgetTester tester) =>
    tester.state(find.byType(SubscriptionEntryReminderHost))
        as WidgetsBindingObserver;

SubscriptionEntryReminderHost _host(
  _FakeAuthService service, {
  Widget child = const Text('主页测试'),
  Duration timeout = const Duration(seconds: 8),
}) => SubscriptionEntryReminderHost(
  authService: service,
  preferenceStore: SubscriptionEntryReminderStore(),
  now: () => _now,
  observeDesktopWindow: false,
  requestTimeout: timeout,
  child: child,
);

Future<void> _pumpHost(
  WidgetTester tester,
  _FakeAuthService service, {
  Widget child = const Text('主页测试'),
  Duration timeout = const Duration(seconds: 8),
}) async {
  await tester.pumpWidget(
    _TestApp(
      child: _host(service, timeout: timeout, child: child),
    ),
  );
  await tester.pump();
  await tester.pump();
}

Future<void> _finish(WidgetTester tester, _FakeAuthService service) async {
  await tester.pumpWidget(const SizedBox.shrink());
  service.completeRemaining();
  await tester.pumpAndSettle();
  expect(tester.takeException(), isNull);
}

class _FakeAuthService extends XboardAuthService {
  _FakeAuthService({this.defaultResponse})
    : super(
        apiHealthService: ApiHealthFixture(
          Uri.parse('https://api.example.com'),
        ),
      );

  XboardSubscriptionData Function()? defaultResponse;
  final _queued = <Completer<XboardSubscriptionData>>[];
  final _all = <Completer<XboardSubscriptionData>>[];
  int calls = 0;

  Completer<XboardSubscriptionData> enqueue() {
    final response = Completer<XboardSubscriptionData>();
    _queued.add(response);
    _all.add(response);
    return response;
  }

  @override
  Future<XboardSubscriptionData> fetchSubscription({
    required Uri endpoint,
    required String authData,
    String? userToken,
    bool secureSubscription = false,
  }) {
    calls++;
    if (_queued.isNotEmpty) return _queued.removeAt(0).future;
    final response = defaultResponse;
    if (response != null) return Future.value(response());
    final pending = Completer<XboardSubscriptionData>();
    _all.add(pending);
    return pending.future;
  }

  void completeRemaining() {
    for (final response in _all) {
      if (!response.isCompleted) {
        response.complete(_subscription(remainingGb: 30));
      }
    }
  }
}

class _TestApp extends StatelessWidget {
  const _TestApp({this.navigatorKey, required this.child});

  final GlobalKey<NavigatorState>? navigatorKey;
  final Widget child;

  @override
  Widget build(BuildContext context) => MaterialApp(
    navigatorKey: navigatorKey,
    locale: const Locale('zh', 'CN'),
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
    ],
    supportedLocales: AppLocalizations.delegate.supportedLocales,
    theme: ThemeData(colorSchemeSeed: const Color(0xFF1B6CF2)),
    home: Scaffold(body: child),
  );
}

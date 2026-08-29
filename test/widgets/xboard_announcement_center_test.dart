import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/l10n/l10n.dart';
import 'package:fl_clash/state.dart';
import 'package:fl_clash/widgets/xboard_announcement_center.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    globalState.clearXboardSession();
    globalState.setOfflineMode(false);
    globalState.showXboardAnnouncements = null;
  });

  tearDown(() {
    globalState.showXboardAnnouncements = null;
    globalState.clearXboardSession();
    globalState.setOfflineMode(false);
  });

  testWidgets(
    'renders HTML and navigates announcements on a narrow dark screen',
    (tester) async {
      tester.view.physicalSize = const Size(390, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var suppressed = false;

      await tester.pumpWidget(
        _TestApp(
          themeMode: ThemeMode.dark,
          child: Builder(
            builder: (context) => FilledButton(
              onPressed: () => showDialog<void>(
                context: context,
                builder: (_) => XboardAnnouncementDialog(
                  notices: const [
                    XboardNoticeData(
                      id: 1,
                      title: '第一条公告',
                      content: '<p>HTML <strong>富文本</strong></p>',
                      tags: ['弹窗'],
                      createdAtEpochSeconds: 1787996400,
                      updatedAtEpochSeconds: null,
                      rawData: {},
                    ),
                    XboardNoticeData(
                      id: 2,
                      title: '第二条公告',
                      content: '<ul><li>列表内容</li></ul>',
                      tags: [],
                      createdAtEpochSeconds: 1787992800,
                      updatedAtEpochSeconds: null,
                      rawData: {},
                    ),
                  ],
                  baseEndpoint: Uri.parse('https://api.example.com'),
                  initiallySuppressedToday: false,
                  onSuppressedTodayChanged: (value) async {
                    suppressed = value;
                  },
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.text('第一条公告'), findsOneWidget);
      expect(_richTextContaining('富文本'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('announcement-suppress-today')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);

      await tester.tap(
        find.byKey(const ValueKey('announcement-suppress-today')),
      );
      await tester.pumpAndSettle();
      expect(suppressed, isTrue);

      await tester.tap(find.byKey(const ValueKey('announcement-next-button')));
      await tester.pumpAndSettle();
      expect(find.text('第二条公告'), findsOneWidget);
      expect(_richTextContaining('列表内容'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('auto prompt filters popup tags and honors today suppression', (
    tester,
  ) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    globalState.container = container;
    var requests = 0;
    final service = XboardAuthService(
      noticesRequester: (endpoint, authData) async {
        requests++;
        return const XboardLoginResponse(
          statusCode: 200,
          data: {
            'data': [
              {
                'id': 2,
                'title': '需要弹窗',
                'content': '<p>重要内容</p>',
                'tags': ['弹窗'],
                'created_at': 1787996400,
              },
              {
                'id': 1,
                'title': '普通公告',
                'content': '<p>普通内容</p>',
                'tags': [],
                'created_at': 1787992800,
              },
            ],
            'total': 2,
          },
        );
      },
    );
    final session = _session();
    globalState.activateXboardSession(session);
    var now = DateTime(2026, 8, 29, 23, 50);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: _TestApp(
          child: XboardAnnouncementCenterHost(
            authService: service,
            preferenceStore: XboardNoticePreferenceStore(),
            now: () => now,
            child: const Scaffold(body: SizedBox.expand()),
          ),
        ),
      ),
    );
    await tester.pump();

    globalState.requestXboardAnnouncementAutoPrompt();
    await tester.pumpAndSettle();

    expect(requests, 1);
    expect(
      find.byKey(const ValueKey('xboard-announcement-dialog')),
      findsOneWidget,
    );
    expect(find.text('需要弹窗'), findsOneWidget);
    expect(find.text('普通公告'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('announcement-suppress-today')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('announcement-close-button')));
    await tester.pumpAndSettle();

    globalState.activateXboardSession(_session());
    globalState.requestXboardAnnouncementAutoPrompt();
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('xboard-announcement-dialog')),
      findsNothing,
    );

    now = DateTime(2026, 8, 30, 0, 1);
    globalState.activateXboardSession(_session());
    globalState.requestXboardAnnouncementAutoPrompt();
    await tester.pumpAndSettle();

    expect(find.text('需要弹窗'), findsOneWidget);
  });
}

Finder _richTextContaining(String value) {
  return find.byWidgetPredicate(
    (widget) => widget is RichText && widget.text.toPlainText().contains(value),
  );
}

XboardLoginResult _session() {
  final endpoint = Uri.parse('https://api.example.com');
  return XboardLoginResult(
    endpoint: endpoint,
    token: 'token',
    authData: 'Bearer token',
    isAdmin: false,
    subscription: XboardSubscriptionData(
      endpoint: endpoint,
      subscribeUrl: Uri.parse('https://api.example.com/subscribe'),
      uploadBytes: 0,
      downloadBytes: 0,
      transferEnableBytes: bytesPerGigabyte * 60,
      email: 'member@example.com',
      rawData: const {},
    ),
  );
}

class _TestApp extends StatelessWidget {
  const _TestApp({required this.child, this.themeMode = ThemeMode.light});

  final Widget child;
  final ThemeMode themeMode;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      locale: const Locale('zh', 'CN'),
      theme: ThemeData(colorSchemeSeed: const Color(0xFF2468E8)),
      darkTheme: ThemeData(
        brightness: Brightness.dark,
        colorSchemeSeed: const Color(0xFF78A7FF),
      ),
      themeMode: themeMode,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.delegate.supportedLocales,
      home: Scaffold(body: Center(child: child)),
    );
  }
}

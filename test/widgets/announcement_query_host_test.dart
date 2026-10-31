import 'dart:async';

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/l10n/l10n.dart';
import 'package:fl_clash/state.dart';
import 'package:fl_clash/widgets/inherited.dart';
import 'package:fl_clash/widgets/xboard_announcement_center.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/api_health_fixture.dart';

void _hostTest(
  String name,
  Future<void> Function(WidgetTester, _Rig) callback,
) {
  testWidgets(name, (tester) async {
    final rig = _Rig();
    globalState.activateXboardSession(_session());
    try {
      await callback(tester, rig);
    } finally {
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      rig.active.dispose();
      rig.container.dispose();
      for (final channel in ['window_manager', 'window_ext']) {
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          MethodChannel(channel),
          null,
        );
      }
    }
  });
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    globalState.clearXboardSession();
    globalState.setOfflineMode(false);
    TestWidgetsFlutterBinding.ensureInitialized()
        .handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  });
  tearDown(() {
    globalState.clearXboardSession();
    globalState.setOfflineMode(false);
    globalState.showXboardAnnouncements = null;
    TestWidgetsFlutterBinding.ensureInitialized()
        .handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  });

  _hostTest('manual supersedes pending automatic data and leaves one dialog', (
    tester,
    rig,
  ) async {
    final old = Completer<List<XboardNoticeData>>();
    final manual = Completer<List<XboardNoticeData>>();
    rig.service.loader = (call) => call == 1 ? old.future : manual.future;
    await rig.mount(tester);
    await rig.automatic(tester);
    expect(rig.service.calls, 1);
    globalState.showXboardAnnouncements!(automatic: false);
    await tester.pumpAndSettle();
    expect(rig.service.calls, 2);
    manual.complete([_notice(2)]);
    await tester.pumpAndSettle();
    expect(find.text('Notice 2'), findsOneWidget);
    old.complete([_notice(1)]);
    await tester.pumpAndSettle();
    expect(find.text('Notice 1'), findsNothing);
    expect(find.byType(XboardAnnouncementDialog), findsOneWidget);
    await rig.close(tester);
    await rig.automatic(tester);
    expect(rig.service.calls, 2);
    expect(find.byType(XboardAnnouncementDialog), findsNothing);
  });

  _hostTest(
    'manual refresh replaces an open automatic dialog without stacking',
    (tester, rig) async {
      rig.service.loader = (call) async => [_notice(call)];
      await rig.mount(tester);
      await rig.automatic(tester);
      expect(find.text('Notice 1'), findsOneWidget);
      globalState.showXboardAnnouncements!(automatic: false);
      await tester.pumpAndSettle();
      expect(rig.service.calls, 2);
      expect(find.byType(XboardAnnouncementDialog), findsOneWidget);
      expect(find.text('Notice 2'), findsOneWidget);
    },
  );

  _hostTest(
    'manual request during close waits for the previous route removal',
    (tester, rig) async {
      rig.service.loader = (call) async => [_notice(call)];
      await rig.mount(tester);
      await rig.automatic(tester);
      await tester.tap(find.byKey(const ValueKey('announcement-close-button')));
      globalState.showXboardAnnouncements!(automatic: false);
      await tester.pump();
      expect(rig.service.calls, 2);
      expect(find.byType(XboardAnnouncementDialog), findsOneWidget);
      await tester.pumpAndSettle();
      expect(find.byType(XboardAnnouncementDialog), findsOneWidget);
      expect(find.text('Notice 2'), findsOneWidget);
    },
  );

  _hostTest(
    'a raw notice version change is eligible for a new automatic dialog',
    (tester, rig) async {
      var version = 1;
      rig.service.loader = (_) async => [
        XboardNoticeData(
          id: 1,
          title: 'Versioned',
          content: '<p>unchanged</p>',
          tags: const ['弹窗'],
          createdAtEpochSeconds: null,
          updatedAtEpochSeconds: null,
          rawData: {'version': version},
        ),
      ];
      await rig.mount(tester);
      await rig.automatic(tester);
      await rig.close(tester);
      version++;
      rig.now = rig.now.add(const Duration(minutes: 5));
      await rig.automatic(tester);
      expect(find.text('Versioned'), findsOneWidget);
      expect(rig.service.calls, 2);
    },
  );

  _hostTest(
    'new notice IDs and versions can display again within the same day',
    (tester, rig) async {
      var notices = [_notice(1)];
      rig.service.loader = (_) async => notices;
      await rig.mount(tester);
      await rig.automatic(tester);
      await rig.close(tester);
      globalState.activateXboardSession(_session(token: 'metadata-rotation'));
      await rig.automatic(tester);
      expect(rig.service.calls, 1);
      expect(find.byType(XboardAnnouncementDialog), findsNothing);
      rig.now = rig.now.add(const Duration(minutes: 5));
      notices = [_notice(1), _notice(2)];
      await rig.automatic(tester);
      expect(rig.service.calls, 2);
      expect(find.text('Notice 2'), findsOneWidget);
      expect(
        tester
            .widget<XboardAnnouncementDialog>(
              find.byType(XboardAnnouncementDialog),
            )
            .notices,
        hasLength(1),
      );
      await rig.close(tester);
      rig.now = rig.now.add(const Duration(minutes: 5));
      notices = [_notice(1, title: 'Updated 1', updated: 99), _notice(2)];
      await rig.automatic(tester);
      expect(find.text('Updated 1'), findsOneWidget);
      expect(
        tester
            .widget<XboardAnnouncementDialog>(
              find.byType(XboardAnnouncementDialog),
            )
            .notices,
        hasLength(1),
      );
      await rig.close(tester);
      rig.now = rig.now.add(const Duration(days: 1));
      await rig.automatic(tester);
      expect(
        tester
            .widget<XboardAnnouncementDialog>(
              find.byType(XboardAnnouncementDialog),
            )
            .notices,
        hasLength(2),
      );
    },
  );

  _hostTest(
    'empty and failed automatic checks are cached but manual is immediate',
    (tester, rig) async {
      var failing = false;
      rig.service.loader = (_) async {
        if (failing) throw StateError('controlled_notice_outage');
        return [];
      };
      await rig.mount(tester);
      await rig.automatic(tester);
      await rig.automatic(tester);
      expect(rig.service.calls, 1);
      rig.now = rig.now.add(const Duration(seconds: 60));
      failing = true;
      await rig.automatic(tester);
      await rig.automatic(tester);
      expect(rig.service.calls, 2);
      failing = false;
      rig.service.loader = (_) async => [_notice(3)];
      globalState.showXboardAnnouncements!(automatic: false);
      await tester.pumpAndSettle();
      expect(rig.service.calls, 3);
      expect(find.text('Notice 3'), findsOneWidget);
    },
  );

  _hostTest(
    'background and inactive pages defer and merge automatic triggers',
    (tester, rig) async {
      await rig.mount(tester);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await rig.automatic(tester);
      await rig.automatic(tester);
      expect(rig.service.calls, 0);
      rig.active.value = false;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(rig.service.calls, 0);
      rig.active.value = true;
      await tester.pumpAndSettle();
      expect(rig.service.calls, 1);
      expect(find.byType(XboardAnnouncementDialog), findsOneWidget);
    },
  );

  _hostTest(
    'a covered page postpones automatic presentation without another fetch',
    (tester, rig) async {
      await rig.mount(tester);
      final route = DialogRoute<void>(
        context: tester.element(find.byKey(const ValueKey('open-other'))),
        builder: (_) => const AlertDialog(content: Text('Other dialog')),
      );
      final navigator = Navigator.of(
        tester.element(find.byKey(const ValueKey('open-other'))),
      );
      navigator.push(route);
      await tester.pumpAndSettle();
      await rig.automatic(tester);
      expect(rig.service.calls, 0);
      navigator.pop();
      await tester.pumpAndSettle();
      expect(rig.service.calls, 1);
      expect(find.byType(XboardAnnouncementDialog), findsOneWidget);
    },
  );

  _hostTest(
    'an interrupted automatic result replays once after the covered page returns',
    (tester, rig) async {
      final pending = Completer<List<XboardNoticeData>>();
      rig.service.loader = (_) => pending.future;
      await rig.mount(tester);
      await rig.automatic(tester);
      final context = tester.element(find.byKey(const ValueKey('open-other')));
      final navigator = Navigator.of(context);
      navigator.push(
        DialogRoute<void>(
          context: context,
          builder: (_) => const AlertDialog(content: Text('Covering dialog')),
        ),
      );
      await tester.pumpAndSettle();
      pending.complete([_notice(1)]);
      await tester.pumpAndSettle();
      expect(find.byType(XboardAnnouncementDialog), findsNothing);
      navigator.pop();
      await tester.pumpAndSettle();
      expect(rig.service.calls, 2);
      expect(find.text('Notice 1'), findsOneWidget);
    },
  );

  for (final change in ['offline', 'logout', 'account', 'dispose']) {
    _hostTest('late notice results are isolated after $change', (
      tester,
      rig,
    ) async {
      final pending = Completer<List<XboardNoticeData>>();
      rig.service.loader = (call) =>
          call == 1 ? pending.future : Future.value([_notice(2)]);
      await rig.mount(tester);
      await rig.automatic(tester);
      expect(rig.service.calls, 1);
      switch (change) {
        case 'offline':
          globalState.setOfflineMode(true);
        case 'logout':
          globalState.clearXboardSession();
          globalState.activateXboardSession(_session());
        case 'account':
          globalState.activateXboardSession(_session(auth: 'other-account'));
        case 'dispose':
          await tester.pumpWidget(const SizedBox());
      }
      pending.complete([_notice(99)]);
      await tester.pumpAndSettle();
      expect(find.text('Notice 99'), findsNothing);
      if (change == 'offline') {
        expect(rig.service.calls, 1);
        globalState.setOfflineMode(false);
        await tester.pumpAndSettle();
      }
      if (change != 'dispose') expect(find.text('Notice 2'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  _hostTest('offline and account changes close a stale dialog', (
    tester,
    rig,
  ) async {
    await rig.mount(tester);
    await rig.automatic(tester);
    globalState.setOfflineMode(true);
    await tester.pumpAndSettle();
    expect(find.byType(XboardAnnouncementDialog), findsNothing);
    globalState.clearXboardSession();
    globalState.setOfflineMode(false);
    await tester.pumpAndSettle();
    expect(find.byType(XboardAnnouncementDialog), findsNothing);
  });

  _hostTest('desktop native failure recovers while blur still blocks queries', (
    tester,
    rig,
  ) async {
    rig.observeWindow = true;
    var failing = true;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('window_manager'),
      (call) async {
        if (failing) throw PlatformException(code: 'temporary_window_state');
        return call.method == 'isMinimized' ? false : true;
      },
    );
    await rig.mount(tester);
    await rig.automatic(tester);
    expect(rig.service.calls, 0);
    failing = false;
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(rig.service.calls, 1);
    await rig.close(tester);
    await _windowEvent(tester, 'blur');
    rig.now = rig.now.add(const Duration(minutes: 5));
    await rig.automatic(tester);
    expect(rig.service.calls, 1);
    await _windowEvent(tester, 'focus');
    await tester.pumpAndSettle();
    expect(rig.service.calls, 2);
    expect(find.byType(XboardAnnouncementDialog), findsNothing);
  });

  _hostTest('disposing a host cancels the pending native window deadline', (
    tester,
    rig,
  ) async {
    rig.observeWindow = true;
    final visibility = Completer<bool>();
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('window_manager'),
      (call) async => call.method == 'isVisible'
          ? visibility.future
          : call.method != 'isMinimized',
    );
    await rig.mount(tester);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    expect(visibility.isCompleted, isFalse);
    expect(rig.service.calls, 0);
  });

  _hostTest('superseded native reads release their deadlines before disposal', (
    tester,
    rig,
  ) async {
    rig.observeWindow = true;
    final reads = <Completer<bool>>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('window_manager'),
      (call) async {
        if (call.method == 'isVisible') {
          final pending = Completer<bool>();
          reads.add(pending);
          return pending.future;
        }
        return call.method != 'isMinimized';
      },
    );
    await rig.mount(tester);
    await _windowEvent(tester, 'show');
    await tester.pump();
    expect(reads.length, greaterThanOrEqualTo(2));
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    expect(reads.every((read) => !read.isCompleted), isTrue);
  });

  _hostTest(
    'focus supersedes a late background result without changing shared reads',
    (tester, rig) async {
      rig.observeWindow = true;
      final visibility = Completer<bool>();
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('window_manager'),
        (call) async => call.method == 'isVisible'
            ? visibility.future
            : call.method != 'isMinimized',
      );
      await rig.mount(tester);
      await rig.automatic(tester);
      expect(rig.service.calls, 0);
      await _windowEvent(tester, 'focus');
      await tester.pumpAndSettle();
      expect(rig.service.calls, 1);
      visibility.complete(false);
      await tester.pumpAndSettle();
      await rig.close(tester);
      rig.now = rig.now.add(const Duration(minutes: 5));
      await rig.automatic(tester);
      expect(rig.service.calls, 2);
    },
  );

  for (final pause in ['page', 'lifecycle', 'window', 'offline', 'modal']) {
    _hostTest('automatic pagination defers under $pause and replays once', (
      tester,
      rig,
    ) async {
      final first = Completer<XboardLoginResponse>();
      final pages = <String?>[];
      rig.overrideService = XboardAuthService(
        apiHealthService: ApiHealthFixture(
          Uri.parse('https://api.example.com'),
        ),
        noticesRequester: (uri, _) async {
          final page = uri.queryParameters['current'];
          pages.add(page);
          if (pages.length == 1) return first.future;
          return _page(int.parse(page!));
        },
      );
      if (pause == 'window') {
        rig.observeWindow = true;
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          const MethodChannel('window_manager'),
          (call) async => call.method == 'isMinimized' ? false : true,
        );
      }
      await rig.mount(tester);
      await rig.automatic(tester);
      expect(pages, ['1']);
      final context = tester.element(find.byKey(const ValueKey('open-other')));
      switch (pause) {
        case 'page':
          rig.active.value = false;
        case 'lifecycle':
          tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.paused,
          );
        case 'window':
          await _windowEvent(tester, 'blur');
        case 'offline':
          globalState.setOfflineMode(true);
        case 'modal':
          unawaited(
            Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const Scaffold(body: Text('covered')),
              ),
            ),
          );
      }
      await tester.pumpAndSettle();
      first.complete(_page(1));
      await tester.pumpAndSettle();
      expect(pages, ['1']);
      expect(find.byType(XboardAnnouncementDialog), findsNothing);
      switch (pause) {
        case 'page':
          rig.active.value = true;
        case 'lifecycle':
          tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.resumed,
          );
        case 'window':
          await _windowEvent(tester, 'focus');
        case 'offline':
          globalState.setOfflineMode(false);
        case 'modal':
          Navigator.of(context).pop();
      }
      await tester.pumpAndSettle();
      expect(pages, ['1', '1', '2']);
      expect(find.byType(XboardAnnouncementDialog), findsOneWidget);
      await tester.pumpAndSettle();
      expect(pages, hasLength(3));
    });
  }

  _hostTest(
    'pause and resume before old page completes does not continue that query',
    (tester, rig) async {
      final first = Completer<XboardLoginResponse>();
      final pages = <String?>[];
      rig.overrideService = XboardAuthService(
        apiHealthService: ApiHealthFixture(
          Uri.parse('https://api.example.com'),
        ),
        noticesRequester: (uri, _) async {
          final page = uri.queryParameters['current'];
          pages.add(page);
          return pages.length == 1 ? first.future : _page(int.parse(page!));
        },
      );
      await rig.mount(tester);
      await rig.automatic(tester);
      rig.active.value = false;
      await tester.pumpAndSettle();
      rig.active.value = true;
      await tester.pumpAndSettle();
      first.complete(_page(1));
      await tester.pumpAndSettle();
      expect(pages, ['1', '1', '2']);
      expect(find.byType(XboardAnnouncementDialog), findsOneWidget);
    },
  );

  _hostTest('announcement query preserves all server pagination', (
    tester,
    rig,
  ) async {
    final pages = <String?>[];
    rig.overrideService = XboardAuthService(
      apiHealthService: ApiHealthFixture(Uri.parse('https://api.example.com')),
      noticesRequester: (uri, _) async {
        pages.add(uri.queryParameters['current']);
        final id = int.parse(uri.queryParameters['current']!);
        return XboardLoginResponse(
          statusCode: 200,
          data: {
            'data': [
              {
                'id': id,
                'title': 'Page $id',
                'content': '<p>$id</p>',
                'tags': ['弹窗'],
              },
            ],
            'total': 3,
          },
        );
      },
    );
    await rig.mount(tester);
    await rig.automatic(tester);
    expect(pages, ['1', '2', '3']);
    expect(
      tester
          .widget<XboardAnnouncementDialog>(
            find.byType(XboardAnnouncementDialog),
          )
          .notices,
      hasLength(3),
    );
  });

  _hostTest(
    'resume cannot reuse foreground while native validation is pending or hidden',
    (tester, rig) async {
      rig.observeWindow = true;
      var visible = true;
      var failing = false;
      Completer<bool>? visibility;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('window_manager'),
        (call) async {
          if (failing) throw PlatformException(code: 'temporary_window_state');
          return switch (call.method) {
            'isVisible' => visibility?.future ?? visible,
            'isMinimized' => false,
            'isFocused' => true,
            _ => null,
          };
        },
      );
      await rig.mount(tester);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await rig.automatic(tester);
      expect(rig.service.calls, 0);
      visibility = Completer<bool>();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(rig.service.calls, 0);
      visible = false;
      visibility.complete(false);
      visibility = null;
      await tester.pumpAndSettle();
      expect(rig.service.calls, 0);
      failing = true;
      await _windowEvent(tester, 'show');
      await tester.pumpAndSettle();
      expect(rig.service.calls, 0);
      failing = false;
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
      expect(rig.service.calls, 0);
      visible = true;
      await _windowEvent(tester, 'focus');
      await tester.pumpAndSettle();
      expect(rig.service.calls, 1);
      expect(find.byType(XboardAnnouncementDialog), findsOneWidget);
    },
  );
}

XboardLoginResponse _page(int id) => XboardLoginResponse(
  statusCode: 200,
  data: {
    'data': [
      {
        'id': id,
        'title': 'Page $id',
        'content': '<p>$id</p>',
        'tags': ['弹窗'],
      },
    ],
    'total': 2,
  },
);

class _Rig {
  final container = ProviderContainer();
  final active = ValueNotifier(true);
  final service = _NoticeService();
  XboardAuthService? overrideService;
  var now = DateTime(2026, 10, 25, 12);
  bool observeWindow = false;

  Future<void> mount(WidgetTester tester) async {
    globalState.container = container;
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          locale: const Locale('zh', 'CN'),
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.delegate.supportedLocales,
          home: ValueListenableBuilder<bool>(
            valueListenable: active,
            builder: (_, value, _) => PageActivityScope(
              isActive: value,
              child: XboardAnnouncementCenterHost(
                authService: overrideService ?? service,
                now: () => now,
                observeDesktopWindow: observeWindow,
                child: const Scaffold(
                  body: SizedBox(key: ValueKey('open-other')),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> automatic(WidgetTester tester) async {
    globalState.requestXboardAnnouncementAutoPrompt();
    await tester.pumpAndSettle();
  }

  Future<void> close(WidgetTester tester) async {
    await tester.tap(find.byKey(const ValueKey('announcement-close-button')));
    await tester.pumpAndSettle();
  }
}

class _NoticeService extends XboardAuthService {
  int calls = 0;
  Future<List<XboardNoticeData>> Function(int)? loader;
  @override
  Future<List<XboardNoticeData>> fetchNotices({
    required Uri endpoint,
    required String authData,
    bool Function()? canRequest,
  }) {
    calls++;
    return loader?.call(calls) ?? Future.value([_notice(1)]);
  }
}

XboardNoticeData _notice(int id, {String? title, int? updated}) =>
    XboardNoticeData(
      id: id,
      title: title ?? 'Notice $id',
      content: '<p>$id</p>',
      tags: const ['弹窗'],
      createdAtEpochSeconds: null,
      updatedAtEpochSeconds: updated,
      rawData: const {},
    );

XboardLoginResult _session({
  String auth = 'Bearer account',
  String token = 'token',
}) {
  final endpoint = Uri.parse('https://api.example.com');
  return XboardLoginResult(
    endpoint: endpoint,
    token: token,
    authData: auth,
    isAdmin: false,
    subscription: XboardSubscriptionData(
      endpoint: endpoint,
      subscribeUrl: null,
      uploadBytes: 0,
      downloadBytes: 0,
      transferEnableBytes: 100,
      email: 'member@example.com',
      rawData: const {},
    ),
  );
}

Future<void> _windowEvent(WidgetTester tester, String event) async {
  await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
    'window_manager',
    const StandardMethodCodec().encodeMethodCall(
      MethodCall('onEvent', {'eventName': event}),
    ),
    (_) {},
  );
}

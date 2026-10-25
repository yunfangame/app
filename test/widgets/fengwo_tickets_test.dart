import 'dart:async';

import 'package:fl_clash/common/xboard_api_request.dart';
import 'package:fl_clash/common/xboard_tickets.dart';
import 'package:fl_clash/l10n/l10n.dart';
import 'package:fl_clash/views/account/fengwo_tickets.dart';
import 'package:fl_clash/widgets/inherited.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/ticket_fixtures.dart';

Widget app(
  XboardTicketController controller, {
  double width = 620,
  double scale = 1,
  bool pollingEnabled = true,
}) => MaterialApp(
  locale: const Locale('en'),
  localizationsDelegates: const [
    AppLocalizations.delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ],
  supportedLocales: AppLocalizations.delegate.supportedLocales,
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
    child: child!,
  ),
  home: Scaffold(
    body: Center(
      child: SizedBox(
        width: width,
        height: 430,
        child: FengWoTicketPanel(
          controller: controller,
          pollingEnabled: pollingEnabled,
        ),
      ),
    ),
  ),
);

class _DetailPollingRig {
  final fixture = TicketFixture();
  int detailCalls = 0;
  int fetchCalls = 0;
  int summaryCalls = 0;
  Future<Object?> Function()? readDetail;
  late final controller = XboardTicketController(
    summaryPollingEnabled: false,
    pollJitterSeconds: () => 0,
    now: TestWidgetsFlutterBinding.instance.clock.now,
    api: XboardTicketApi(
      requester: (uri, auth, body) {
        if (uri.path.endsWith('/detail')) {
          detailCalls++;
          if (readDetail != null) return readDetail!();
        }
        if (uri.path.endsWith('/fetch')) fetchCalls++;
        if (uri.path.endsWith('/summary')) summaryCalls++;
        return fixture.request(uri, auth, body);
      },
    ),
  )..updateSession(ticketSession(), offline: false);

  Future<void> open(WidgetTester tester) async {
    addTearDown(controller.dispose);
    if (fixture.closed) {
      await controller.refresh(filter: 1);
    } else {
      await controller.refresh();
    }
    controller.startPolling(foreground: true);
    await tester.pumpWidget(app(controller, pollingEnabled: false));
    await tester.tap(find.byKey(const ValueKey('ticket-1')));
    await tester.pumpAndSettle();
  }
}

void main() {
  testWidgets(
    'deferred automatic details keep the existing conversation without showing an error',
    (tester) async {
      final rig = _DetailPollingRig();
      await rig.open(tester);
      rig.readDetail = () async => throw const XboardApiRequestDeferred();
      await tester.pump(const Duration(seconds: 30));
      await tester.pumpAndSettle();
      expect(rig.detailCalls, 2);
      expect(find.text('Please try another node'), findsOneWidget);
      expect(find.text('Unable to load tickets. Please retry.'), findsNothing);
      rig.readDetail = null;
      await tester.pump(const Duration(seconds: 30));
      expect(rig.detailCalls, 3);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'pause and resume invalidate an older automatic response and refresh once after it settles',
    (tester) async {
      final rig = _DetailPollingRig();
      await rig.open(tester);
      final pending = Completer<Object?>();
      rig.readDetail = () => pending.future;
      await tester.pump(const Duration(seconds: 30));
      expect(rig.detailCalls, 2);
      rig.controller.setForeground(false);
      rig.controller.setForeground(true);
      await tester.pump(Duration.zero);
      expect(rig.detailCalls, 2);
      rig.readDetail = null;
      pending.complete({
        'data': {
          'id': 1,
          'subject': 'Stale conversation',
          'status': 1,
          'latest_reply_id': 99,
          'messages': [],
        },
      });
      await tester.pumpAndSettle();
      expect(rig.detailCalls, 3);
      expect(find.text('Stale conversation'), findsNothing);
      expect(find.byKey(const ValueKey('ticket-reply-input')), findsOneWidget);
      expect(rig.fixture.readCalls, 1);
      await tester.pump(const Duration(seconds: 30));
      expect(rig.detailCalls, 4);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'closed details check for reopening every five minutes and then restore the active interval',
    (tester) async {
      final rig = _DetailPollingRig()..fixture.closed = true;
      await rig.open(tester);
      expect(rig.detailCalls, 1);
      await tester.pump(const Duration(seconds: 299));
      expect(rig.detailCalls, 1);
      rig.fixture.closed = false;
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
      expect(rig.detailCalls, 2);
      expect(find.byKey(const ValueKey('ticket-reply-input')), findsOneWidget);
      await tester.pump(const Duration(seconds: 29));
      expect(rig.detailCalls, 2);
      await tester.pump(const Duration(seconds: 1));
      expect(rig.detailCalls, 3);
      expect(rig.summaryCalls, 0);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'closed detail manual refresh is immediate and dismissal stops its timer before the exit animation',
    (tester) async {
      final rig = _DetailPollingRig()..fixture.closed = true;
      await rig.open(tester);
      final refresh = find.descendant(
        of: find.byType(Dialog),
        matching: find.byIcon(Icons.refresh),
      );
      await tester.tap(refresh);
      await tester.pumpAndSettle();
      expect(rig.detailCalls, 2);
      await tester.pump(const Duration(seconds: 299));
      expect(rig.detailCalls, 2);
      await tester.tap(find.byKey(const ValueKey('ticket-detail-dismiss')));
      await tester.pump(const Duration(seconds: 1));
      expect(rig.detailCalls, 2);
      final fetches = rig.fetchCalls;
      await tester.pump(const Duration(hours: 1));
      expect(rig.detailCalls, 2);
      expect(rig.fetchCalls, fetches);
      expect(rig.summaryCalls, 0);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'reply and close confirm immediately and switch only the detail to the closed interval',
    (tester) async {
      final rig = _DetailPollingRig();
      await rig.open(tester);
      await tester.enterText(
        find.byKey(const ValueKey('ticket-reply-input')),
        'Resolved',
      );
      await tester.tap(find.byKey(const ValueKey('ticket-reply-send')));
      await tester.pumpAndSettle();
      expect(rig.detailCalls, 2);
      await tester.tap(find.text('Close ticket'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Close ticket'));
      await tester.pumpAndSettle();
      expect(rig.fixture.closeCalls, 1);
      expect(rig.detailCalls, 3);
      await tester.pump(const Duration(seconds: 299));
      expect(rig.detailCalls, 3);
      await tester.pump(const Duration(seconds: 1));
      expect(rig.detailCalls, 4);
      expect(rig.summaryCalls, 0);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'closed detail refresh pauses in the background and resumes once',
    (tester) async {
      final rig = _DetailPollingRig()..fixture.closed = true;
      await rig.open(tester);
      rig.controller.setForeground(false);
      rig.controller.setWindowForeground(false);
      await tester.pump(const Duration(hours: 1));
      expect(rig.detailCalls, 1);
      rig.controller.setForeground(true);
      await tester.pump(Duration.zero);
      expect(rig.detailCalls, 1);
      rig.controller.setWindowForeground(true);
      await tester.pumpAndSettle();
      expect(rig.detailCalls, 2);
      await tester.pump(const Duration(seconds: 299));
      expect(rig.detailCalls, 2);
      await tester.pump(const Duration(seconds: 1));
      expect(rig.detailCalls, 3);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('ticket panels can turn list polling on and off', (tester) async {
    final fixture = TicketFixture();
    var fetchCalls = 0;
    var summaryCalls = 0;
    final controller = XboardTicketController(
      summaryPollingEnabled: false,
      pollJitterSeconds: () => 0,
      api: XboardTicketApi(
        requester: (uri, auth, body) {
          if (uri.path.endsWith('/fetch')) fetchCalls++;
          if (uri.path.endsWith('/summary')) summaryCalls++;
          return fixture.request(uri, auth, body);
        },
      ),
    )..updateSession(ticketSession(), offline: false);
    addTearDown(controller.dispose);
    try {
      await controller.refresh();
      controller.startPolling(foreground: true);
      await tester.pumpWidget(app(controller, pollingEnabled: false));
      await tester.pump(const Duration(minutes: 10));
      expect(fetchCalls, 1);
      await tester.pumpWidget(app(controller));
      await tester.pump(const Duration(seconds: 30));
      expect(fetchCalls, 2);
      await tester.pumpWidget(app(controller, pollingEnabled: false));
      await tester.pump(const Duration(minutes: 10));
      expect(fetchCalls, 2);
      expect(summaryCalls, 0);
    } finally {
      await tester.pumpWidget(const SizedBox());
    }
  });

  testWidgets(
    'manual lists keep only open ticket conversations polling',
    (tester) async {
      final fixture = TicketFixture();
      var fetchCalls = 0;
      var detailCalls = 0;
      var summaryCalls = 0;
      final controller = XboardTicketController(
        summaryPollingEnabled: false,
        pollJitterSeconds: () => 0,
        api: XboardTicketApi(
          requester: (uri, auth, body) {
            if (uri.path.endsWith('/fetch')) fetchCalls++;
            if (uri.path.endsWith('/detail')) detailCalls++;
            if (uri.path.endsWith('/summary')) summaryCalls++;
            return fixture.request(uri, auth, body);
          },
        ),
      )..updateSession(ticketSession(), offline: false);
      addTearDown(controller.dispose);
      try {
        await controller.refresh();
        controller.startPolling(foreground: true);
        await tester.pumpWidget(app(controller, pollingEnabled: false));
        await tester.tap(find.byKey(const ValueKey('ticket-1')));
        await tester.pumpAndSettle();
        expect(detailCalls, 1);
        await tester.pump(const Duration(seconds: 30));
        expect(detailCalls, 2);
        expect(summaryCalls, 0);
        controller.setForeground(false);
        await tester.pump(const Duration(minutes: 10));
        expect(detailCalls, 2);
        controller.setForeground(true);
        await tester.pump(Duration.zero);
        expect(detailCalls, 3);
        await tester.tap(find.byKey(const ValueKey('ticket-detail-dismiss')));
        await tester.pumpAndSettle();
        final previousFetches = fetchCalls;
        await tester.pump(const Duration(hours: 1));
        expect(detailCalls, 3);
        expect(fetchCalls, previousFetches);
        expect(summaryCalls, 0);
      } finally {
        await tester.pumpWidget(const SizedBox());
      }
    },
    variant: const TargetPlatformVariant({
      TargetPlatform.macOS,
      TargetPlatform.android,
    }),
  );

  testWidgets('offstage ticket panels use the ordinary foreground interval', (
    tester,
  ) async {
    final fixture = TicketFixture();
    var summaryCalls = 0;
    var fetchCalls = 0;
    final controller = XboardTicketController(
      pollJitterSeconds: () => 0,
      api: XboardTicketApi(
        requester: (uri, auth, body) {
          if (uri.path.endsWith('/summary')) summaryCalls++;
          if (uri.path.endsWith('/fetch')) fetchCalls++;
          return fixture.request(uri, auth, body);
        },
      ),
    )..updateSession(ticketSession(), offline: false);
    addTearDown(controller.dispose);
    try {
      await tester.pumpWidget(
        PageActivityScope(isActive: false, child: app(controller)),
      );
      controller.startPolling(foreground: true);
      await tester.pump(Duration.zero);
      expect(summaryCalls, 1);
      await tester.pump(const Duration(seconds: 30));
      expect(fetchCalls, 0);
      await tester.pumpWidget(
        PageActivityScope(isActive: true, child: app(controller)),
      );
      await tester.pump(const Duration(seconds: 30));
      expect(fetchCalls, 1);
      await tester.pumpWidget(
        PageActivityScope(isActive: false, child: app(controller)),
      );
      await tester.pump(const Duration(seconds: 119));
      expect(summaryCalls, 1);
      await tester.pump(const Duration(seconds: 1));
      expect(summaryCalls, 2);
    } finally {
      controller.stopPolling();
    }
  });

  testWidgets('background detail responses are not automatically marked read', (
    tester,
  ) async {
    final fixture = TicketFixture();
    final pending = Completer<Object?>();
    var detailCalls = 0;
    var fetchCalls = 0;
    final controller = XboardTicketController(
      pollJitterSeconds: () => 0,
      api: XboardTicketApi(
        requester: (uri, auth, body) {
          if (uri.path.endsWith('/fetch')) fetchCalls++;
          if (uri.path.endsWith('/detail') && ++detailCalls == 1) {
            return pending.future;
          }
          return fixture.request(uri, auth, body);
        },
      ),
    )..updateSession(ticketSession(), offline: false);
    addTearDown(controller.dispose);
    try {
      await controller.refresh();
      await tester.pumpWidget(app(controller));
      controller.startPolling(foreground: true);
      await tester.pump(Duration.zero);
      await tester.tap(find.byKey(const ValueKey('ticket-1')));
      await tester.pump(const Duration(milliseconds: 300));
      controller.setForeground(false);
      pending.complete(
        await fixture.request(
          Uri.parse('https://example.com/api/v1/user/ticket-sync/detail?id=1'),
          'one',
          null,
        ),
      );
      await tester.pumpAndSettle();
      expect(fixture.readCalls, 0);
      expect(controller.unreadCount, 1);
      final previousFetches = fetchCalls;
      await tester.pump(const Duration(minutes: 10));
      expect(detailCalls, 1);
      expect(fetchCalls, previousFetches);
      controller.setForeground(true);
      await tester.pump(Duration.zero);
      await tester.pumpAndSettle();
      expect(detailCalls, 2);
      expect(fixture.readCalls, 1);
      expect(controller.unreadCount, 0);
    } finally {
      controller.stopPolling();
    }
  });

  testWidgets(
    'bounded ticket list scrolls without growing and filters closed tickets',
    (tester) async {
      final fixture = TicketFixture()..itemCount = 60;
      final controller = fixture.controller();
      addTearDown(controller.dispose);
      await controller.refresh();
      await tester.pumpWidget(app(controller));
      await tester.pumpAndSettle();
      final size = tester.getSize(find.byType(FengWoTicketPanel));
      expect(find.byKey(const ValueKey('ticket-unread-1')), findsOneWidget);
      await tester.drag(
        find.byKey(const ValueKey('ticket-list-scroll')),
        const Offset(0, -600),
      );
      await tester.pumpAndSettle();
      expect(tester.getSize(find.byType(FengWoTicketPanel)), size);
      await tester.tap(find.text('Closed (0)'));
      await tester.pumpAndSettle();
      expect(find.text('No tickets here yet'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('details read acknowledgement, reply, and close work', (
    tester,
  ) async {
    final fixture = TicketFixture();
    final controller = fixture.controller();
    addTearDown(controller.dispose);
    await controller.refresh();
    await tester.pumpWidget(app(controller));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('ticket-1')));
    await tester.pumpAndSettle();
    expect(find.text('Please try another node'), findsOneWidget);
    expect(fixture.readCalls, 1);
    expect(controller.unreadCount, 0);
    await tester.enterText(
      find.byKey(const ValueKey('ticket-reply-input')),
      'It works now',
    );
    await tester.tap(find.byKey(const ValueKey('ticket-reply-send')));
    await tester.pumpAndSettle();
    expect(fixture.replyCalls, 1);
    await tester.tap(find.text('Close ticket'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Close ticket'));
    await tester.pumpAndSettle();
    expect(fixture.closeCalls, 1);
    expect(find.byKey(const ValueKey('ticket-reply-input')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('ticket-detail-dismiss')));
    await tester.pumpAndSettle();
  });

  testWidgets(
    'failed details do not mark read; failed acknowledgement can retry',
    (tester) async {
      final fixture = TicketFixture()..failDetail = true;
      final controller = fixture.controller();
      addTearDown(controller.dispose);
      await controller.refresh();
      await tester.pumpWidget(app(controller));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('ticket-1')));
      await tester.pumpAndSettle();
      expect(fixture.readCalls, 0);
      expect(controller.unreadCount, 1);
      fixture.failDetail = false;
      fixture.failRead = true;
      await tester.tap(find.text('Unable to load tickets. Please retry.'));
      await tester.pumpAndSettle();
      expect(controller.unreadCount, 1);
      fixture.failRead = false;
      await tester.tap(
        find.text(
          'Read status could not be synced. Retry to clear the notification.',
        ),
      );
      await tester.pumpAndSettle();
      expect(controller.unreadCount, 0);
      await tester.tap(find.byKey(const ValueKey('ticket-detail-dismiss')));
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'new ticket validates, preserves drafts after failure, and submits',
    (tester) async {
      final fixture = TicketFixture()..failWrite = true;
      final controller = fixture.controller();
      addTearDown(controller.dispose);
      await controller.refresh();
      await tester.pumpWidget(app(controller));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('ticket-create')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('ticket-submit')));
      await tester.pumpAndSettle();
      expect(fixture.createCalls, 0);
      await tester.enterText(
        find.byKey(const ValueKey('ticket-subject-input')),
        'Question',
      );
      await tester.enterText(
        find.byKey(const ValueKey('ticket-message-input')),
        'Need help',
      );
      await tester.tap(find.byKey(const ValueKey('ticket-submit')));
      await tester.pumpAndSettle();
      expect(find.text('Need help'), findsOneWidget);
      fixture.failWrite = false;
      await tester.tap(find.byKey(const ValueKey('ticket-submit')));
      await tester.pumpAndSettle();
      expect(fixture.createCalls, 1);
      expect(fixture.submitted!['subject'], 'Question');
      expect(fixture.submitted!['level'], 1);
    },
  );

  testWidgets('composer does not submit after account switch', (tester) async {
    final fixture = TicketFixture();
    final controller = fixture.controller();
    addTearDown(controller.dispose);
    await controller.refresh();
    await tester.pumpWidget(app(controller));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('ticket-create')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('ticket-subject-input')),
      'Private draft',
    );
    await tester.enterText(
      find.byKey(const ValueKey('ticket-message-input')),
      'Private content',
    );
    controller.updateSession(
      ticketSession('different-account'),
      offline: false,
    );
    await tester.tap(find.byKey(const ValueKey('ticket-submit')));
    await tester.pumpAndSettle();
    expect(fixture.createCalls, 0);
    expect(find.byKey(const ValueKey('ticket-message-input')), findsNothing);
  });

  for (final viewport in [
    const Size(320, 844),
    const Size(390, 844),
    const Size(844, 390),
  ]) {
    final width = viewport.width;
    testWidgets('mobile $viewport supports larger text and keyboard', (
      tester,
    ) async {
      tester.view.physicalSize = viewport;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetViewInsets);
      final fixture = TicketFixture();
      final controller = fixture.controller();
      addTearDown(controller.dispose);
      await controller.refresh();
      await tester.pumpWidget(app(controller, width: width - 48, scale: 1.3));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.tap(find.byKey(const ValueKey('ticket-1')));
      await tester.pumpAndSettle();
      tester.view.viewInsets = FakeViewPadding(
        bottom: viewport.height < 500 ? 180 : 300,
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.tap(find.byKey(const ValueKey('ticket-detail-dismiss')));
      await tester.pumpAndSettle();
    });
  }
}

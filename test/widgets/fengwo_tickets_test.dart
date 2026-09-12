import 'package:fl_clash/l10n/l10n.dart';
import 'package:fl_clash/common/xboard_tickets.dart';
import 'package:fl_clash/views/account/fengwo_tickets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/ticket_fixtures.dart';

Widget app(
  XboardTicketController controller, {
  double width = 620,
  double scale = 1,
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
        child: FengWoTicketPanel(controller: controller),
      ),
    ),
  ),
);

void main() {
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

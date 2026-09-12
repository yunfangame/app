import 'dart:async';

import 'package:fl_clash/common/xboard_tickets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/ticket_fixtures.dart';

void main() {
  test(
    'server read is shared by devices and failed read preserves unread',
    () async {
      final fixture = TicketFixture();
      final mac = fixture.controller();
      final windows = fixture.controller();
      addTearDown(mac.dispose);
      addTearDown(windows.dispose);
      await mac.refresh();
      await windows.refresh();
      expect(windows.unreadCount, 1);
      final detail = await mac.detail(1);
      fixture.failRead = true;
      await expectLater(mac.markRead(detail), throwsStateError);
      expect(mac.tickets.single.unread, isTrue);
      fixture.failRead = false;
      await mac.markRead(detail);
      await windows.refresh();
      expect(windows.unreadCount, 0);
      expect(windows.tickets.single.unread, isFalse);
    },
  );

  test(
    'stale session responses and offline requests cannot leak state',
    () async {
      final pending = Completer<Object?>();
      var calls = 0;
      final controller = XboardTicketController(
        api: XboardTicketApi(
          requester: (_, _, _) {
            calls++;
            return pending.future;
          },
        ),
      );
      addTearDown(controller.dispose);
      controller.updateSession(ticketSession(), offline: false);
      final loading = controller.refresh();
      controller.updateSession(ticketSession('two'), offline: true);
      pending.complete({
        'data': {
          'items': [
            {'id': 1, 'unread': true},
          ],
          'unread_count': 1,
        },
      });
      await loading;
      await controller.refresh();
      await controller.refreshSummary();
      expect(controller.tickets, isEmpty);
      expect(controller.unreadCount, 0);
      expect(calls, 1);
    },
  );

  test('filter changes supersede in flight requests', () async {
    final open = Completer<Object?>();
    final closed = Completer<Object?>();
    final controller = XboardTicketController(
      api: XboardTicketApi(
        requester: (uri, _, _) =>
            uri.queryParameters['status'] == '0' ? open.future : closed.future,
      ),
    );
    addTearDown(controller.dispose);
    controller.updateSession(ticketSession(), offline: false);
    final first = controller.refresh();
    final second = controller.refresh(filter: 1);
    closed.complete({
      'data': {
        'items': [
          {'id': 2, 'status': 1},
        ],
        'unread_count': 0,
      },
    });
    await second;
    open.complete({
      'data': {
        'items': [
          {'id': 1},
        ],
        'unread_count': 1,
      },
    });
    await first;
    expect(controller.tickets.single.id, 2);
    expect(controller.status, 1);
    expect(controller.unreadCount, 0);
  });

  test(
    'read sends the displayed reply id rather than a newly arriving reply',
    () async {
      Map<String, Object?>? acknowledgement;
      final fixture = TicketFixture();
      final controller = XboardTicketController(
        api: XboardTicketApi(
          requester: (uri, auth, body) async {
            if (uri.path.endsWith('/read')) acknowledgement = body;
            return fixture.request(uri, auth, body);
          },
        ),
      );
      addTearDown(controller.dispose);
      controller.updateSession(ticketSession(), offline: false);
      final detail = await controller.detail(1);
      await controller.markRead(detail);
      expect(acknowledgement, {'ticket_id': 1, 'last_read_message_id': 2});
    },
  );
}

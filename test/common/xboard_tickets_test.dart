import 'dart:async';

import 'package:fl_clash/common/xboard_api_request.dart';
import 'package:fl_clash/common/xboard_auth.dart';
import 'package:fl_clash/common/xboard_tickets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/ticket_fixtures.dart';

class _BeforeReturnTicketApi extends XboardTicketApi {
  _BeforeReturnTicketApi(this.beforeReturn);

  final void Function() beforeReturn;

  @override
  Future<Object?> request(
    XboardLoginResult session,
    String path, {
    Map<String, Object?>? query,
    Map<String, Object?>? body,
    bool Function()? canRequest,
  }) async {
    beforeReturn();
    return path.endsWith('detail')
        ? {'id': 1, 'messages': <Object?>[]}
        : {
            'items': [
              {'id': 1},
            ],
          };
  }
}

void main() {
  test('guarded list and detail recheck activity before returning', () async {
    var active = true;
    final controller = XboardTicketController(
      summaryPollingEnabled: false,
      api: _BeforeReturnTicketApi(() => active = false),
    )..updateSession(ticketSession(), offline: false);
    addTearDown(controller.dispose);
    controller.startPolling(foreground: true);
    await expectLater(
      controller.refresh(canRequest: () => active),
      throwsA(isA<XboardApiRequestDeferred>()),
    );
    expect(controller.tickets, isEmpty);
    expect(controller.failed, isFalse);
    active = true;
    await expectLater(
      controller.detail(1, canRequest: () => active),
      throwsA(isA<XboardApiRequestDeferred>()),
    );
  });

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

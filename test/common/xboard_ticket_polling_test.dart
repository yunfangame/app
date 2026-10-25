import 'dart:async';

import 'package:fl_clash/common/xboard_api_request.dart';
import 'package:fl_clash/common/xboard_tickets.dart';
import 'package:fl_clash/state.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/ticket_fixtures.dart';

final _controllers = <XboardTicketController>[];

void _pollingTest(String description, WidgetTesterCallback callback) {
  testWidgets(description, (tester) async {
    _controllers.clear();
    try {
      await callback(tester);
    } finally {
      for (final controller in _controllers) {
        controller.stopPolling();
      }
    }
  });
}

class _Rig {
  _Rig({this.summaryPollingEnabled = true}) {
    _controllers.add(controller);
  }
  final bool summaryPollingEnabled;
  final fixture = TicketFixture();
  final summaryAccounts = <String>[];
  int fetchCalls = 0;
  bool failSummary = false;
  Future<Object?> Function(String auth)? summary;
  Future<Object?> Function(int call)? fetch;
  late final controller = XboardTicketController(
    summaryPollingEnabled: summaryPollingEnabled,
    pollJitterSeconds: () => 0,
    now: TestWidgetsFlutterBinding.instance.clock.now,
    api: XboardTicketApi(
      requester: (uri, auth, body) {
        if (uri.path.endsWith('/summary')) {
          summaryAccounts.add(auth);
          if (summary != null) return summary!(auth);
          if (failSummary) throw StateError('Unavailable');
        }
        if (uri.path.endsWith('/fetch')) {
          fetchCalls++;
          if (fetch != null) return fetch!(fetchCalls);
        }
        return fixture.request(uri, auth, body);
      },
    ),
  )..updateSession(ticketSession(), offline: false);
}

void main() {
  _pollingTest(
    'automatic recovery preserves summary failure deadline while manual refresh can bypass it',
    (tester) async {
      final rig = _Rig()..failSummary = true;
      addTearDown(rig.controller.dispose);
      rig.controller.startPolling(foreground: true);
      await tester.pump(Duration.zero);
      expect(rig.summaryAccounts, hasLength(1));
      for (var repeat = 0; repeat < 5; repeat++) {
        await tester.pump(const Duration(seconds: 20));
        rig.controller.setForeground(false);
        rig.controller.setForeground(true);
        rig.controller.refreshAutomatically();
        await tester.pump(Duration.zero);
        expect(rig.summaryAccounts, hasLength(1));
      }
      await tester.pump(const Duration(seconds: 139));
      expect(rig.summaryAccounts, hasLength(1));
      await tester.pump(const Duration(seconds: 1));
      expect(rig.summaryAccounts, hasLength(2));
      rig.controller.refreshNow();
      await tester.pump(Duration.zero);
      expect(rig.summaryAccounts, hasLength(3));
    },
  );

  _pollingTest(
    'an automatic list invalidated by pause and resume defers without failure and then refreshes once',
    (tester) async {
      final rig = _Rig(summaryPollingEnabled: false);
      addTearDown(rig.controller.dispose);
      final pending = Completer<Object?>();
      rig.fetch = (call) async => call == 1
          ? await pending.future
          : {
              'data': {
                ...rig.fixture.summary,
                'page': 1,
                'has_more': false,
                'items': [
                  {'id': 1},
                ],
              },
            };
      rig.controller.setViewActive(Object(), true);
      rig.controller.startPolling(foreground: true);
      await tester.pump(Duration.zero);
      expect(rig.fetchCalls, 1);
      rig.controller.setForeground(false);
      rig.controller.setForeground(true);
      rig.controller.refreshAutomatically();
      await tester.pump(Duration.zero);
      expect(rig.fetchCalls, 1);
      pending.complete({
        'data': {
          ...rig.fixture.summary,
          'page': 1,
          'has_more': false,
          'items': [
            {'id': 9},
          ],
        },
      });
      await tester.pump(Duration.zero);
      await tester.pump(Duration.zero);
      expect(rig.fetchCalls, 2);
      expect(rig.controller.tickets.single.id, 1);
      expect(rig.controller.failed, isFalse);
      await tester.pump(const Duration(seconds: 30));
      expect(rig.fetchCalls, 3);
      expect(rig.summaryAccounts, isEmpty);
    },
  );

  _pollingTest('repeated focus changes preserve the closed detail deadline', (
    tester,
  ) async {
    final rig = _Rig(summaryPollingEnabled: false);
    addTearDown(rig.controller.dispose);
    rig.controller.startPolling(foreground: true);
    var calls = 0;
    rig.controller.setViewActive(
      Object(),
      true,
      detailInterval: const Duration(minutes: 5),
      refresh: () async {
        calls++;
        return true;
      },
    );
    for (var count = 0; count < 10; count++) {
      await tester.pump(const Duration(seconds: 20));
      rig.controller.setWindowForeground(false);
      rig.controller.setWindowForeground(true);
      await tester.pump(Duration.zero);
      expect(calls, 0);
    }
    await tester.pump(const Duration(seconds: 99));
    expect(calls, 0);
    await tester.pump(const Duration(seconds: 1));
    expect(calls, 1);
  });

  _pollingTest(
    'a deferred detail request preserves the active interval without failure backoff',
    (tester) async {
      final rig = _Rig(summaryPollingEnabled: false);
      addTearDown(rig.controller.dispose);
      rig.controller.startPolling(foreground: true);
      var calls = 0;
      rig.controller.setViewActive(
        Object(),
        true,
        detailInterval: const Duration(seconds: 30),
        refresh: () async {
          calls++;
          if (calls == 1) throw const XboardApiRequestDeferred();
          return true;
        },
      );
      await tester.pump(const Duration(seconds: 30));
      expect(calls, 1);
      await tester.pump(const Duration(seconds: 29));
      expect(calls, 1);
      await tester.pump(const Duration(seconds: 1));
      expect(calls, 2);
    },
  );

  _pollingTest(
    'independent active and closed details suppress the covered list without sharing cadence',
    (tester) async {
      final rig = _Rig(summaryPollingEnabled: false);
      addTearDown(rig.controller.dispose);
      rig.controller.startPolling(foreground: true);
      rig.controller.setViewActive(Object(), true);
      var activeCalls = 0;
      var closedCalls = 0;
      rig.controller.setViewActive(
        Object(),
        true,
        detailInterval: const Duration(seconds: 30),
        refresh: () async {
          activeCalls++;
          return true;
        },
      );
      rig.controller.setViewActive(
        Object(),
        true,
        detailInterval: const Duration(minutes: 5),
        refresh: () async {
          closedCalls++;
          return false;
        },
      );
      for (var tick = 1; tick <= 20; tick++) {
        await tester.pump(const Duration(seconds: 30));
        expect(activeCalls, tick);
        expect(closedCalls, tick ~/ 10);
      }
      expect(rig.fetchCalls, 0);
      expect(rig.summaryAccounts, isEmpty);
      await tester.pump(const Duration(seconds: 30));
      expect(activeCalls, 21);
      expect(closedCalls, 2);
    },
  );

  _pollingTest(
    'detail failures retain 240 and 480 second backoff and manual success restores its interval',
    (tester) async {
      final rig = _Rig(summaryPollingEnabled: false);
      addTearDown(rig.controller.dispose);
      rig.controller.startPolling(foreground: true);
      final owner = Object();
      var calls = 0;
      rig.controller.setViewActive(
        owner,
        true,
        detailInterval: const Duration(seconds: 30),
        refresh: () async {
          calls++;
          return calls > 2;
        },
      );
      await tester.pump(const Duration(seconds: 30));
      expect(calls, 1);
      await tester.pump(const Duration(seconds: 239));
      expect(calls, 1);
      await tester.pump(const Duration(seconds: 1));
      expect(calls, 2);
      await tester.pump(const Duration(seconds: 479));
      expect(calls, 2);
      rig.controller.recordViewRefresh(owner, true);
      await tester.pump(const Duration(seconds: 29));
      expect(calls, 2);
      await tester.pump(const Duration(seconds: 1));
      expect(calls, 3);
      await tester.pump(const Duration(seconds: 30));
      expect(calls, 4);
    },
  );

  _pollingTest(
    'per-view details pause together and resume once without duplicate timers',
    (tester) async {
      final rig = _Rig(summaryPollingEnabled: false);
      addTearDown(rig.controller.dispose);
      rig.controller.startPolling(foreground: true);
      var calls = 0;
      final owner = Object();
      Future<bool?> refresh() async {
        calls++;
        return true;
      }

      rig.controller.setViewActive(
        owner,
        true,
        refresh: refresh,
        detailInterval: const Duration(minutes: 5),
      );
      rig.controller.setViewActive(
        owner,
        true,
        refresh: refresh,
        detailInterval: const Duration(minutes: 5),
      );
      rig.controller.setWindowForeground(false);
      rig.controller.setForeground(false);
      await tester.pump(const Duration(hours: 1));
      expect(calls, 0);
      rig.controller.setForeground(true);
      await tester.pump(Duration.zero);
      expect(calls, 0);
      rig.controller.setWindowForeground(true);
      rig.controller.refreshNow();
      await tester.pump(Duration.zero);
      expect(calls, 1);
      await tester.pump(const Duration(seconds: 299));
      expect(calls, 1);
      await tester.pump(const Duration(seconds: 1));
      expect(calls, 2);
      rig.controller.setViewActive(owner, false);
      await tester.pump(const Duration(hours: 1));
      expect(calls, 2);
      expect(rig.fetchCalls, 0);
      expect(rig.summaryAccounts, isEmpty);
    },
  );

  _pollingTest('desktop summaries stay idle across login and focus changes', (
    tester,
  ) async {
    final rig = _Rig(
      summaryPollingEnabled:
          globalState.xboardTicketController.summaryPollingEnabled,
    );
    addTearDown(rig.controller.dispose);
    rig.controller.startPolling(foreground: true);
    await tester.pump(Duration.zero);
    await tester.pump(const Duration(hours: 1));
    rig.controller.setForeground(false);
    rig.controller.setWindowForeground(false);
    rig.controller.updateSession(ticketSession('two'), offline: false);
    rig.controller.setForeground(true);
    rig.controller.setWindowForeground(true);
    rig.controller.refreshNow();
    await tester.pump(Duration.zero);
    await tester.pump(const Duration(hours: 1));
    expect(rig.summaryAccounts, isEmpty);
    expect(rig.fetchCalls, 0);
  });

  _pollingTest('visible tickets still refresh without summary polling', (
    tester,
  ) async {
    final rig = _Rig(summaryPollingEnabled: false);
    addTearDown(rig.controller.dispose);
    rig.controller.startPolling(foreground: true);
    final list = Object();
    rig.controller.setViewActive(list, true);
    await rig.controller.refresh();
    expect(rig.fetchCalls, 1);
    expect(rig.controller.unreadCount, 1);
    expect(rig.controller.openCount, 1);
    await tester.pump(const Duration(seconds: 30));
    expect(rig.fetchCalls, 2);
    final chat = Object();
    var detailCalls = 0;
    rig.controller.setViewActive(
      chat,
      true,
      refresh: () async {
        detailCalls++;
        return true;
      },
    );
    await tester.pump(const Duration(seconds: 30));
    expect(detailCalls, 1);
    expect(rig.fetchCalls, 2);
    rig.controller.setViewActive(chat, false);
    rig.controller.setViewActive(list, false);
    await tester.pump(const Duration(hours: 1));
    expect(rig.summaryAccounts, isEmpty);
    expect(rig.fetchCalls, 2);
    expect(detailCalls, 1);
  });

  _pollingTest(
    'manual ticket actions do not restart disabled summary polling',
    (tester) async {
      final rig = _Rig(summaryPollingEnabled: false);
      addTearDown(rig.controller.dispose);
      rig.controller.startPolling(foreground: true);
      await rig.controller.refresh();
      await rig.controller.markRead(await rig.controller.detail(1));
      expect(rig.controller.unreadCount, 0);
      await rig.controller.mutate('reply', {'id': 1, 'message': 'hello'});
      expect(rig.fixture.readCalls, 1);
      expect(rig.fixture.replyCalls, 1);
      expect(rig.fetchCalls, 3);
      await tester.pump(const Duration(hours: 1));
      expect(rig.summaryAccounts, isEmpty);
      expect(rig.fetchCalls, 3);
    },
  );

  _pollingTest('foreground unread counts poll every 120 seconds', (
    tester,
  ) async {
    final rig = _Rig();
    addTearDown(rig.controller.dispose);
    rig.controller.startPolling(foreground: true);
    await tester.pump(Duration.zero);
    expect(rig.summaryAccounts, ['one']);
    await tester.pump(const Duration(seconds: 119));
    expect(rig.summaryAccounts, hasLength(1));
    await tester.pump(const Duration(seconds: 1));
    expect(rig.summaryAccounts, hasLength(2));
    expect(rig.controller.unreadCount, 1);
  });

  _pollingTest('visible ticket list polls at 30 then returns to 120', (
    tester,
  ) async {
    final rig = _Rig();
    addTearDown(rig.controller.dispose);
    rig.controller.startPolling(foreground: true);
    await tester.pump(Duration.zero);
    final owner = Object();
    rig.controller.setViewActive(owner, true);
    await tester.pump(const Duration(seconds: 29));
    expect(rig.fetchCalls, 0);
    await tester.pump(const Duration(seconds: 1));
    expect(rig.fetchCalls, 1);
    expect(rig.summaryAccounts, hasLength(1));
    rig.controller.setViewActive(owner, false);
    await tester.pump(const Duration(seconds: 119));
    expect(rig.summaryAccounts, hasLength(1));
    await tester.pump(const Duration(seconds: 1));
    expect(rig.summaryAccounts, hasLength(2));
  });

  _pollingTest('chat shares the timer and supersedes the covered list', (
    tester,
  ) async {
    final rig = _Rig();
    addTearDown(rig.controller.dispose);
    rig.controller.startPolling(foreground: true);
    await tester.pump(Duration.zero);
    var detailCalls = 0;
    final list = Object();
    final chat = Object();
    rig.controller.setViewActive(list, true);
    rig.controller.setViewActive(
      chat,
      true,
      refresh: () async {
        detailCalls++;
        return true;
      },
    );
    await tester.pump(const Duration(seconds: 30));
    expect(detailCalls, 1);
    expect(rig.fetchCalls, 0);
    expect(rig.summaryAccounts, hasLength(2));
    rig.controller.setViewActive(chat, false);
    await tester.pump(const Duration(seconds: 30));
    expect(detailCalls, 1);
    expect(rig.fetchCalls, 1);
  });

  _pollingTest('background pauses every poll and resume refreshes once', (
    tester,
  ) async {
    final rig = _Rig();
    addTearDown(rig.controller.dispose);
    rig.controller.startPolling(foreground: true);
    await tester.pump(Duration.zero);
    rig.controller.setForeground(false);
    await tester.pump(const Duration(hours: 1));
    await rig.controller.refreshSummary();
    await rig.controller.refresh();
    expect(rig.summaryAccounts, hasLength(1));
    expect(rig.fetchCalls, 0);
    rig.controller.setForeground(true);
    rig.controller.setForeground(true);
    await tester.pump(Duration.zero);
    expect(rig.summaryAccounts, hasLength(2));
  });

  _pollingTest('login and foreground events in one turn coalesce', (
    tester,
  ) async {
    final rig = _Rig();
    addTearDown(rig.controller.dispose);
    rig.controller.startPolling(foreground: false);
    rig.controller.updateSession(ticketSession('two'), offline: false);
    rig.controller.setForeground(true);
    rig.controller.updateSession(ticketSession('two'), offline: false);
    rig.controller.refreshNow();
    rig.controller.refreshNow();
    await tester.pump(Duration.zero);
    expect(rig.summaryAccounts, ['two']);
  });

  _pollingTest('failures back off to 240 and 480 and cap there', (
    tester,
  ) async {
    final rig = _Rig()..failSummary = true;
    addTearDown(rig.controller.dispose);
    rig.controller.startPolling(foreground: true);
    await tester.pump(Duration.zero);
    await tester.pump(const Duration(seconds: 239));
    expect(rig.summaryAccounts, hasLength(1));
    await tester.pump(const Duration(seconds: 1));
    expect(rig.summaryAccounts, hasLength(2));
    for (var call = 3; call <= 4; call++) {
      await tester.pump(const Duration(seconds: 479));
      expect(rig.summaryAccounts, hasLength(call - 1));
      await tester.pump(const Duration(seconds: 1));
      expect(rig.summaryAccounts, hasLength(call));
    }
    rig.failSummary = false;
    await tester.pump(const Duration(seconds: 480));
    expect(rig.summaryAccounts, hasLength(5));
    await tester.pump(const Duration(seconds: 119));
    expect(rig.summaryAccounts, hasLength(5));
    await tester.pump(const Duration(seconds: 1));
    expect(rig.summaryAccounts, hasLength(6));
  });

  _pollingTest('page changes do not bypass failure backoff', (tester) async {
    final rig = _Rig()..failSummary = true;
    addTearDown(rig.controller.dispose);
    rig.controller.startPolling(foreground: true);
    await tester.pump(Duration.zero);
    rig.controller.setViewActive(Object(), true);
    await tester.pump(const Duration(seconds: 239));
    expect(rig.fetchCalls, 0);
    await tester.pump(const Duration(seconds: 1));
    expect(rig.fetchCalls, 1);
    await tester.pump(const Duration(seconds: 30));
    expect(rig.fetchCalls, 2);
  });

  _pollingTest('summary and foreground triggers share an in-flight request', (
    tester,
  ) async {
    final rig = _Rig();
    final pending = Completer<Object?>();
    rig.summary = (_) => pending.future;
    addTearDown(rig.controller.dispose);
    final first = rig.controller.refreshSummary();
    final second = rig.controller.refreshSummary();
    rig.controller.startPolling(foreground: true);
    rig.controller.setForeground(false);
    rig.controller.setForeground(true);
    await tester.pump(Duration.zero);
    expect(rig.summaryAccounts, hasLength(1));
    pending.complete({'data': rig.fixture.summary});
    await Future.wait([first, second]);
    await tester.pump(Duration.zero);
    expect(rig.summaryAccounts, hasLength(1));
  });

  _pollingTest('duplicate failed summary requests advance backoff only once', (
    tester,
  ) async {
    final rig = _Rig();
    addTearDown(rig.controller.dispose);
    rig.controller.startPolling(foreground: true);
    await tester.pump(Duration.zero);
    final pending = Completer<Object?>();
    rig.summary = (_) => pending.future;
    final first = rig.controller.refreshSummary();
    final second = rig.controller.refreshSummary();
    pending.completeError(StateError('Unavailable'));
    await Future.wait([first, second]);
    rig.summary = null;
    await tester.pump(const Duration(seconds: 239));
    expect(rig.summaryAccounts, hasLength(2));
    await tester.pump(const Duration(seconds: 1));
    expect(rig.summaryAccounts, hasLength(3));
  });

  _pollingTest('equivalent list refresh requests share the network operation', (
    tester,
  ) async {
    final rig = _Rig();
    final pending = Completer<Object?>();
    rig.fetch = (_) => pending.future;
    addTearDown(rig.controller.dispose);
    final first = rig.controller.refresh();
    final second = rig.controller.refresh(filter: 0);
    await tester.pump(Duration.zero);
    expect(rig.fetchCalls, 1);
    pending.complete({
      'data': {...rig.fixture.summary, 'items': [], 'has_more': false},
    });
    await Future.wait([first, second]);
  });

  _pollingTest('account changes ignore previous pending unread results', (
    tester,
  ) async {
    final rig = _Rig();
    final pending = Completer<Object?>();
    rig.summary = (auth) => auth == 'one'
        ? pending.future
        : Future.value({
            'data': {'unread_count': 2},
          });
    addTearDown(rig.controller.dispose);
    rig.controller.startPolling(foreground: true);
    await tester.pump(Duration.zero);
    rig.controller.updateSession(ticketSession('two'), offline: false);
    await tester.pump(Duration.zero);
    expect(rig.summaryAccounts, ['one', 'two']);
    expect(rig.controller.unreadCount, 2);
    pending.complete({
      'data': {'unread_count': 9},
    });
    await tester.pump(Duration.zero);
    expect(rig.controller.unreadCount, 2);
  });

  for (final action in ['reply', 'read']) {
    _pollingTest(
      'successful $action refreshes immediately and clears backoff',
      (tester) async {
        final rig = _Rig()..failSummary = true;
        addTearDown(rig.controller.dispose);
        rig.controller.startPolling(foreground: true);
        await tester.pump(Duration.zero);
        if (action == 'read') {
          await rig.controller.markRead(await rig.controller.detail(1));
          expect(rig.controller.unreadCount, 0);
        } else {
          await rig.controller.mutate('reply', {'id': 1, 'message': 'hello'});
          expect(rig.fixture.replyCalls, 1);
        }
        expect(rig.fetchCalls, 1);
        expect(rig.summaryAccounts, hasLength(1));
        rig.failSummary = false;
        await tester.pump(const Duration(seconds: 119));
        expect(rig.summaryAccounts, hasLength(1));
        await tester.pump(const Duration(seconds: 1));
        expect(rig.summaryAccounts, hasLength(2));
      },
    );
  }

  _pollingTest('view registration preserves the immediate login refresh', (
    tester,
  ) async {
    final rig = _Rig();
    addTearDown(rig.controller.dispose);
    rig.controller.startPolling(foreground: true);
    rig.controller.setViewActive(Object(), true);
    await tester.pump(Duration.zero);
    expect(rig.fetchCalls, 1);
    expect(rig.summaryAccounts, isEmpty);
  });

  _pollingTest('successful read supersedes a pending pre-read list response', (
    tester,
  ) async {
    final rig = _Rig();
    addTearDown(rig.controller.dispose);
    final oldList = Completer<Object?>();
    rig.fetch = (call) => call == 1
        ? oldList.future
        : rig.fixture.request(
            Uri.parse(
              'https://example.com/api/v1/user/ticket-sync/fetch?status=0',
            ),
            'one',
            null,
          );
    final previous = rig.controller.refresh();
    final detail = await rig.controller.detail(1);
    await rig.controller.markRead(detail);
    expect(rig.fetchCalls, 2);
    expect(rig.controller.unreadCount, 0);
    expect(rig.controller.tickets.single.unread, isFalse);
    oldList.complete({
      'data': {
        'unread_count': 1,
        'items': [
          {'id': 1, 'unread': true},
        ],
      },
    });
    await previous;
    expect(rig.controller.unreadCount, 0);
    expect(rig.controller.tickets.single.unread, isFalse);
  });

  _pollingTest('logout offline and disposal stop polling', (tester) async {
    final rig = _Rig();
    rig.controller.startPolling(foreground: true);
    await tester.pump(Duration.zero);
    rig.controller.updateSession(ticketSession(), offline: true);
    await tester.pump(const Duration(hours: 1));
    expect(rig.summaryAccounts, hasLength(1));
    rig.controller.updateSession(null, offline: false);
    await tester.pump(const Duration(hours: 1));
    expect(rig.summaryAccounts, hasLength(1));
    rig.controller.updateSession(ticketSession('two'), offline: false);
    await tester.pump(Duration.zero);
    expect(rig.summaryAccounts, ['one', 'two']);
    rig.controller.dispose();
    await tester.pump(const Duration(hours: 1));
    expect(rig.summaryAccounts, hasLength(2));
  });

  for (final jitter in [-99, 99]) {
    _pollingTest('jitter $jitter stays within the 15-second bounds', (
      tester,
    ) async {
      var calls = 0;
      final controller = XboardTicketController(
        pollJitterSeconds: () => jitter,
        api: XboardTicketApi(
          requester: (_, _, _) async {
            calls++;
            return {
              'data': {'unread_count': 0},
            };
          },
        ),
      )..updateSession(ticketSession(), offline: false);
      addTearDown(controller.dispose);
      _controllers.add(controller);
      controller.startPolling(foreground: true);
      await tester.pump(Duration.zero);
      final seconds = jitter < 0 ? 105 : 135;
      await tester.pump(Duration(seconds: seconds - 1));
      expect(calls, 1);
      await tester.pump(const Duration(seconds: 1));
      expect(calls, 2);
    });
  }
}

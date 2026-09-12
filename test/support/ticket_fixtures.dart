import 'package:fl_clash/common/xboard_auth.dart';
import 'package:fl_clash/common/xboard_tickets.dart';

XboardLoginResult ticketSession([String account = 'one']) {
  final endpoint = Uri.parse('https://example.com');
  return XboardLoginResult(
    endpoint: endpoint,
    token: account,
    authData: account,
    isAdmin: false,
    subscription: XboardSubscriptionData(
      endpoint: endpoint,
      subscribeUrl: null,
      uploadBytes: 0,
      downloadBytes: 0,
      transferEnableBytes: 100,
      rawData: const {},
    ),
  );
}

class TicketFixture {
  bool unread = true;
  bool closed = false;
  bool failRead = false;
  bool failDetail = false;
  bool failWrite = false;
  int readCalls = 0;
  int createCalls = 0;
  int replyCalls = 0;
  int closeCalls = 0;
  int itemCount = 1;
  Map<String, Object?>? submitted;

  late final api = XboardTicketApi(requester: request);
  XboardTicketController controller() =>
      XboardTicketController(api: api)
        ..updateSession(ticketSession(), offline: false);

  Future<Object?> request(
    Uri uri,
    String auth,
    Map<String, Object?>? body,
  ) async {
    final action = uri.path.split('/').last;
    if (action == 'read') {
      readCalls++;
      if (failRead) throw StateError('read failed');
      unread = false;
      return {'data': summary};
    }
    if (action == 'summary') return {'data': summary};
    if (action == 'detail') {
      if (failDetail) throw StateError('detail failed');
      return {
        'data': {
          'id': 1,
          'subject': 'Connection issue',
          'status': closed ? 1 : 0,
          'latest_reply_id': 2,
          'messages': [
            {
              'id': 1,
              'is_me': true,
              'message': 'Help with my connection',
              'created_at': 100,
            },
            {
              'id': 2,
              'is_me': false,
              'message': 'Please try another node',
              'created_at': 200,
            },
          ],
        },
      };
    }
    if (action == 'fetch') {
      final matching = uri.queryParameters['status'] == (closed ? '1' : '0');
      return {
        'data': {
          ...summary,
          'page': 1,
          'has_more': false,
          'items': matching
              ? [
                  for (var i = 1; i <= itemCount; i++)
                    {
                      'id': i,
                      'subject': i == 1 ? 'Connection issue' : 'Ticket $i',
                      'status': closed ? 1 : 0,
                      'reply_status': 0,
                      'unread': unread && i == 1,
                      'latest_reply_id': 2,
                      'updated_at': 200,
                    },
                ]
              : [],
        },
      };
    }
    if (failWrite) throw StateError('write failed');
    submitted = body;
    if (action == 'save') createCalls++;
    if (action == 'reply') replyCalls++;
    if (action == 'close') {
      closeCalls++;
      closed = true;
    }
    return {'data': true};
  }

  Map<String, Object?> get summary => {
    'unread_count': unread ? 1 : 0,
    'open_count': closed ? 0 : itemCount,
    'closed_count': closed ? itemCount : 0,
  };
}

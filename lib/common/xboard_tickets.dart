import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import 'xboard_auth.dart';

typedef XboardTicketRequester =
    Future<Object?> Function(
      Uri endpoint,
      String authData,
      Map<String, Object?>? body,
    );

int _number(Object? value) => int.tryParse('$value') ?? 0;

class XboardTicket {
  XboardTicket.fromMap(Map data)
    : id = _number(data['id']),
      subject = '${data['subject'] ?? ''}',
      closed = _number(data['status']) == 1,
      replied = _number(data['reply_status']) == 0,
      updatedAt = _number(data['updated_at']),
      latestReplyId = _number(data['latest_reply_id']),
      unread = data['unread'] == true;

  final int id;
  final String subject;
  final bool closed;
  final bool replied;
  final int updatedAt;
  final int latestReplyId;
  final bool unread;
}

class XboardTicketDetail {
  XboardTicketDetail.fromMap(Map data)
    : id = _number(data['id']),
      subject = '${data['subject'] ?? ''}',
      closed = _number(data['status']) == 1,
      latestReplyId = _number(data['latest_reply_id']),
      messages = List.unmodifiable(
        (data['messages'] as List).map(
          (item) => XboardTicketMessage.fromMap(item as Map),
        ),
      );

  final int id;
  final String subject;
  final bool closed;
  final int latestReplyId;
  final List<XboardTicketMessage> messages;
  bool get canReply => !closed && messages.isNotEmpty && !messages.last.isMe;
}

class XboardTicketMessage {
  XboardTicketMessage.fromMap(Map data)
    : id = _number(data['id']),
      isMe = data['is_me'] == true || data['is_me'] == 1,
      text = '${data['message'] ?? ''}',
      createdAt = _number(data['created_at']);

  final int id;
  final bool isMe;
  final String text;
  final int createdAt;
}

class XboardTicketApi {
  XboardTicketApi({Dio? dio, XboardTicketRequester? requester})
    : _dio =
          dio ??
          Dio(
            BaseOptions(
              connectTimeout: const Duration(seconds: 5),
              receiveTimeout: const Duration(seconds: 10),
              sendTimeout: const Duration(seconds: 10),
            ),
          ),
      _requester = requester;

  final Dio _dio;
  final XboardTicketRequester? _requester;

  Future<Object?> request(
    XboardLoginResult session,
    String path, {
    Map<String, Object?>? query,
    Map<String, Object?>? body,
  }) async {
    final endpoint = session.endpoint
        .resolve('/api/v1/user/$path')
        .replace(
          queryParameters: query?.map((key, value) => MapEntry(key, '$value')),
        );
    final requester = _requester;
    Object? payload;
    if (requester != null) {
      payload = await requester(endpoint, session.authData, body);
    } else {
      final response = await _dio.requestUri<Object?>(
        endpoint,
        data: body == null ? null : FormData.fromMap(body),
        options: Options(
          method: body == null ? 'GET' : 'POST',
          headers: {
            'Authorization': session.authData,
            'Accept': 'application/json',
          },
          responseType: ResponseType.json,
        ),
      );
      payload = response.data;
    }
    if (payload is! Map ||
        !payload.containsKey('data') ||
        payload['status'] == 0 ||
        payload['data'] == false) {
      throw const FormatException('Invalid ticket response');
    }
    return payload['data'];
  }
}

class XboardTicketController extends ChangeNotifier {
  XboardTicketController({XboardTicketApi? api})
    : api = api ?? XboardTicketApi();

  final XboardTicketApi api;
  XboardLoginResult? _session;
  int _generation = 0;
  int _listRevision = 0;
  int _summaryRevision = 0;
  bool _offline = false;
  bool _disposed = false;
  bool loading = false;
  bool failed = false;
  bool hasMore = false;
  int status = 0;
  int page = 0;
  int unreadCount = 0;
  int openCount = 0;
  int closedCount = 0;
  List<XboardTicket> tickets = const [];
  Future<void>? _summaryOperation;

  XboardLoginResult? get session => _session;
  bool isCurrent(XboardLoginResult session) =>
      !_disposed &&
      !_offline &&
      _session?.authData == session.authData &&
      _session?.endpoint == session.endpoint;

  void updateSession(XboardLoginResult? session, {required bool offline}) {
    if (_session?.authData == session?.authData &&
        _session?.endpoint == session?.endpoint &&
        _offline == offline) {
      return;
    }
    _generation++;
    _listRevision++;
    _summaryRevision++;
    _session = session;
    _offline = offline;
    _summaryOperation = null;
    loading = false;
    failed = false;
    hasMore = false;
    page = 0;
    status = 0;
    unreadCount = openCount = closedCount = 0;
    tickets = const [];
    notifyListeners();
  }

  void _summary(Map data) {
    unreadCount = _number(data['unread_count']);
    openCount = _number(data['open_count']);
    closedCount = _number(data['closed_count']);
  }

  Future<void> refreshSummary() {
    final current = _summaryOperation;
    if (current != null) return current;
    final session = _session;
    if (session == null || _offline || _disposed) return Future.value();
    final generation = _generation;
    final revision = ++_summaryRevision;
    final operation = () async {
      try {
        final data = await api.request(session, 'ticket-sync/summary');
        if (_disposed ||
            generation != _generation ||
            revision != _summaryRevision) {
          return;
        }
        _summary(data as Map);
        notifyListeners();
      } catch (_) {
        return;
      }
    }();
    _summaryOperation = operation;
    return operation.whenComplete(() {
      if (identical(_summaryOperation, operation)) _summaryOperation = null;
    });
  }

  Future<void> refresh({int? filter, bool more = false}) async {
    final session = _session;
    if (session == null ||
        _offline ||
        _disposed ||
        (more && (loading || !hasMore))) {
      return;
    }
    if (filter != null && filter != status) {
      status = filter;
      tickets = const [];
      page = 0;
      hasMore = false;
    }
    final generation = _generation;
    final revision = ++_listRevision;
    final summaryRevision = ++_summaryRevision;
    final nextPage = more ? page + 1 : 1;
    loading = true;
    failed = false;
    notifyListeners();
    try {
      final data =
          await api.request(
                session,
                'ticket-sync/fetch',
                query: {'status': status, 'page': nextPage, 'limit': 30},
              )
              as Map;
      if (_disposed || generation != _generation || revision != _listRevision) {
        return;
      }
      final items = (data['items'] as List)
          .map((item) => XboardTicket.fromMap(item as Map))
          .toList();
      tickets = List.unmodifiable(
        more
            ? {
                ...{for (final t in tickets) t.id: t},
                ...{for (final t in items) t.id: t},
              }.values
            : items,
      );
      hasMore = data['has_more'] == true;
      page = nextPage;
      if (summaryRevision == _summaryRevision) _summary(data);
    } catch (_) {
      if (!_disposed &&
          generation == _generation &&
          revision == _listRevision) {
        failed = true;
      }
    } finally {
      if (!_disposed &&
          generation == _generation &&
          revision == _listRevision) {
        loading = false;
        notifyListeners();
      }
    }
  }

  Future<XboardTicketDetail> detail(int id) async {
    final session = _session;
    if (session == null || !isCurrent(session)) {
      throw StateError('No active session');
    }
    final generation = _generation;
    final data = await api.request(
      session,
      'ticket-sync/detail',
      query: {'id': id},
    );
    if (generation != _generation || !isCurrent(session)) {
      throw StateError('Session changed');
    }
    return XboardTicketDetail.fromMap(data as Map);
  }

  Future<void> markRead(XboardTicketDetail detail) async {
    final session = _session;
    if (session == null || !isCurrent(session) || detail.latestReplyId == 0) {
      return;
    }
    final generation = _generation;
    ++_summaryRevision;
    await api.request(
      session,
      'ticket-sync/read',
      body: {
        'ticket_id': detail.id,
        'last_read_message_id': detail.latestReplyId,
      },
    );
    if (generation != _generation || !isCurrent(session)) return;
    await refresh();
  }

  Future<void> mutate(String action, Map<String, Object?> body) async {
    final session = _session;
    if (session == null || !isCurrent(session)) {
      throw StateError('No active session');
    }
    final generation = _generation;
    await api.request(session, 'ticket/$action', body: body);
    if (generation != _generation || !isCurrent(session)) {
      throw StateError('Session changed');
    }
    await refresh(filter: action == 'save' ? 0 : null);
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    super.dispose();
  }
}

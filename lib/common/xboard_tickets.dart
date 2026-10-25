import 'dart:async';
import 'dart:math';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import 'api_health.dart';
import 'api_request_router.dart';
import 'xboard_api_request.dart';
import 'xboard_auth.dart';

typedef XboardTicketRequester =
    Future<Object?> Function(
      Uri endpoint,
      String authData,
      Map<String, Object?>? body,
    );

typedef XboardTicketViewRefresh = Future<bool?> Function();

class _XboardTicketDetailPoll {
  _XboardTicketDetailPoll(this.refresh, this.interval);

  XboardTicketViewRefresh refresh;
  Duration interval;
  Timer? timer;
  Future<bool?>? operation;
  int failures = 0;
  bool refreshRequested = false;
  DateTime? nextAt;
}

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
  XboardTicketApi({
    Dio? dio,
    XboardTicketRequester? requester,
    ApiHealthService? apiHealthService,
    ApiRequestRouter? router,
    Duration requestTimeout = const Duration(seconds: 20),
    Duration operationTimeout = const Duration(seconds: 45),
  }) : _dio =
           dio ??
           Dio(
             BaseOptions(
               connectTimeout: const Duration(seconds: 5),
               receiveTimeout: const Duration(seconds: 10),
               sendTimeout: const Duration(seconds: 10),
             ),
           ),
       _requester = requester,
       _executor = XboardApiRequestExecutor(
         apiHealthService: apiHealthService,
         router: router,
         singleEndpointSimulation:
             apiHealthService == null && (requester != null || dio != null),
         requestTimeout: requestTimeout,
         operationTimeout: operationTimeout,
       );

  final Dio _dio;
  final XboardTicketRequester? _requester;
  final XboardApiRequestExecutor _executor;

  Future<Object?> request(
    XboardLoginResult session,
    String path, {
    Map<String, Object?>? query,
    Map<String, Object?>? body,
    bool Function()? canRequest,
  }) async {
    final endpoint = session.endpoint
        .resolve('/api/v1/user/$path')
        .replace(
          queryParameters: query?.map((key, value) => MapEntry(key, '$value')),
        );
    return _executor.run(
      endpoint: endpoint,
      canRequest: canRequest,
      allowRetry:
          body == null &&
          const {
            'ticket-sync/summary',
            'ticket-sync/fetch',
            'ticket-sync/detail',
          }.contains(path),
      request: (target, cancelToken) async {
        final requester = _requester;
        Object? payload;
        if (requester != null) {
          payload = await requester(target, session.authData, body);
        } else {
          final response = await _dio.requestUri<Object?>(
            target,
            cancelToken: cancelToken,
            data: body == null ? null : FormData.fromMap(body),
            options: Options(
              method: body == null ? 'GET' : 'POST',
              headers: {
                'Authorization': session.authData,
                'Accept': 'application/json',
              },
              responseType: ResponseType.json,
              followRedirects: false,
              validateStatus: (status) =>
                  status != null && status >= 200 && status < 300,
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
      },
    );
  }
}

class XboardTicketController extends ChangeNotifier {
  XboardTicketController({
    XboardTicketApi? api,
    int Function()? pollJitterSeconds,
    DateTime Function()? now,
    this.summaryPollingEnabled = true,
  }) : api = api ?? XboardTicketApi(),
       _now = now ?? DateTime.now,
       _pollJitterSeconds =
           pollJitterSeconds ?? (() => Random().nextInt(31) - 15);

  final XboardTicketApi api;
  final bool summaryPollingEnabled;
  final int Function() _pollJitterSeconds;
  final DateTime Function() _now;
  final _activeViews = <Object, XboardTicketViewRefresh?>{};
  final _detailPolls = <Object, _XboardTicketDetailPoll>{};
  Timer? _pollTimer;
  bool _pollImmediate = false;
  Future<bool?>? _pollOperation;
  bool _polling = false;
  bool _appForeground = true;
  bool _windowForeground = true;
  bool get _foreground => _appForeground && _windowForeground;
  int _pollFailures = 0;
  int _dataRevision = 0;
  Future<bool?>? _listOperation;
  int? _listRequestStatus;
  int? _listRequestDataRevision;
  bool _listRequestMore = false;
  XboardLoginResult? _session;
  int _generation = 0;
  int _listRevision = 0;
  int _summaryRevision = 0;
  bool _offline = false;
  bool _disposed = false;
  int _activityRevision = 0;
  bool loading = false;
  bool failed = false;
  bool hasMore = false;
  int status = 0;
  int page = 0;
  int unreadCount = 0;
  int openCount = 0;
  int closedCount = 0;
  List<XboardTicket> tickets = const [];
  Future<bool?>? _summaryOperation;

  XboardLoginResult? get session => _session;
  bool get isForeground => _foreground;
  bool get _canPollDetails =>
      _polling && _foreground && !_disposed && !_offline && _session != null;
  bool get _canPoll =>
      _canPollDetails &&
      _detailPolls.isEmpty &&
      (summaryPollingEnabled || _activeViews.isNotEmpty);

  void startPolling({required bool foreground}) {
    if (_disposed) return;
    final previous = _foreground;
    _polling = true;
    _appForeground = foreground;
    if (previous != _foreground) _activityRevision++;
    _requestPoll(preserveClosedDeadline: true);
  }

  void stopPolling() {
    if (_polling) _activityRevision++;
    _polling = false;
    _pollTimer?.cancel();
    for (final poll in _detailPolls.values) {
      poll.timer?.cancel();
    }
  }

  void refreshNow() => _requestPoll();

  void setForeground(bool foreground) {
    if (_disposed) return;
    final previous = _foreground;
    _appForeground = foreground;
    _foregroundChanged(previous);
  }

  void setWindowForeground(bool foreground) {
    if (_disposed) return;
    final previous = _foreground;
    _windowForeground = foreground;
    _foregroundChanged(previous);
  }

  void _foregroundChanged(bool previous) {
    if (previous == _foreground) return;
    _activityRevision++;
    _pollTimer?.cancel();
    for (final poll in _detailPolls.values) {
      poll.timer?.cancel();
      poll.refreshRequested = false;
    }
    if (_foreground) _requestPoll(preserveClosedDeadline: true);
  }

  void setViewActive(
    Object owner,
    bool active, {
    XboardTicketViewRefresh? refresh,
    Duration? detailInterval,
  }) {
    if (_disposed) return;
    if (active) {
      final detail = _detailPolls[owner];
      if (_activeViews.containsKey(owner) &&
          _activeViews[owner] == refresh &&
          detail?.interval == detailInterval) {
        return;
      }
      _activeViews[owner] = refresh;
      if (detailInterval != null && refresh != null) {
        final poll = detail ?? _XboardTicketDetailPoll(refresh, detailInterval);
        poll.refresh = refresh;
        poll.interval = detailInterval;
        _detailPolls[owner] = poll;
        _scheduleDetailPoll(owner, poll);
      } else {
        _detailPolls.remove(owner)?.timer?.cancel();
      }
    } else {
      if (!_activeViews.containsKey(owner)) return;
      _activeViews.remove(owner);
      _detailPolls.remove(owner)?.timer?.cancel();
    }
    _schedulePoll();
  }

  void _requestPoll({bool preserveClosedDeadline = false}) {
    for (final entry in _detailPolls.entries) {
      _scheduleDetailPoll(
        entry.key,
        entry.value,
        immediately: true,
        preserveDeadline:
            preserveClosedDeadline &&
            entry.value.interval >= const Duration(minutes: 5),
      );
    }
    _pollTimer?.cancel();
    _pollImmediate = false;
    if (!_canPoll || _pollOperation != null) return;
    _pollImmediate = true;
    _pollTimer = Timer(Duration.zero, () {
      _pollImmediate = false;
      unawaited(_poll());
    });
  }

  void recordViewRefresh(Object owner, bool? success) {
    final poll = _detailPolls[owner];
    if (poll == null || success == null) return;
    poll.failures = success ? 0 : min(poll.failures + 1, 2);
    _scheduleDetailPoll(owner, poll);
  }

  bool _isCurrentDetailPoll(Object owner, _XboardTicketDetailPoll poll) =>
      _canPollDetails && identical(_detailPolls[owner], poll);

  void _scheduleDetailPoll(
    Object owner,
    _XboardTicketDetailPoll poll, {
    bool immediately = false,
    bool preserveDeadline = false,
  }) {
    poll.timer?.cancel();
    if (!_isCurrentDetailPoll(owner, poll)) return;
    final current = _now();
    final remaining = preserveDeadline && poll.nextAt != null
        ? poll.nextAt!.difference(current)
        : null;
    if (poll.operation != null) {
      poll.refreshRequested |=
          immediately && (remaining == null || remaining <= Duration.zero);
      return;
    }
    poll.refreshRequested = false;
    final seconds = max(poll.interval.inSeconds, switch (poll.failures) {
      0 => 0,
      1 => 240,
      _ => 480,
    });
    final jitter = _pollJitterSeconds().clamp(-15, 15);
    final delay = remaining != null
        ? (remaining.isNegative ? Duration.zero : remaining)
        : immediately
        ? Duration.zero
        : Duration(seconds: seconds + jitter);
    poll.nextAt = current.add(delay);
    poll.timer = Timer(delay, () => unawaited(_pollDetail(owner, poll)));
  }

  Future<void> _pollDetail(Object owner, _XboardTicketDetailPoll poll) async {
    if (!_isCurrentDetailPoll(owner, poll) || poll.operation != null) return;
    final generation = _generation;
    final operation = Future<bool?>.sync(poll.refresh);
    poll.operation = operation;
    bool? success;
    try {
      success = await operation;
    } on XboardApiRequestDeferred {
      success = null;
    } catch (_) {
      success = false;
    }
    if (!identical(poll.operation, operation)) return;
    poll.operation = null;
    if (generation != _generation || !_isCurrentDetailPoll(owner, poll)) return;
    if (success != null) {
      poll.failures = success ? 0 : min(poll.failures + 1, 2);
    }
    _scheduleDetailPoll(owner, poll, immediately: poll.refreshRequested);
  }

  void _schedulePoll() {
    if (_pollImmediate && (_pollTimer?.isActive ?? false) && _canPoll) return;
    _pollTimer?.cancel();
    _pollImmediate = false;
    if (!_canPoll || _pollOperation != null) return;
    final seconds = switch (_pollFailures) {
      0 => _activeViews.isEmpty ? 120 : 30,
      1 => 240,
      _ => 480,
    };
    final jitter = _pollJitterSeconds().clamp(-15, 15);
    _pollTimer = Timer(
      Duration(seconds: seconds + jitter),
      () => unawaited(_poll()),
    );
  }

  void _recordPollResult(bool? success, {bool reschedule = true}) {
    if (success == null) return;
    _pollFailures = success ? 0 : min(_pollFailures + 1, 2);
    if (reschedule) _schedulePoll();
  }

  Future<void> _poll() async {
    if (!_canPoll || _pollOperation != null) return;
    final generation = _generation;
    final dataRevision = _dataRevision;
    final operation = () async {
      if (_activeViews.isEmpty) return _refreshSummary();
      final refresh = _activeViews.values.last;
      if (refresh == null) return _refreshList();
      try {
        final success = await refresh();
        if (!_canPoll || generation != _generation) return null;
        if (success == false) return false;
        if (!summaryPollingEnabled) return success;
        return _refreshSummary();
      } catch (_) {
        return false;
      }
    }();
    _pollOperation = operation;
    final success = await operation;
    if (!identical(_pollOperation, operation)) return;
    _pollOperation = null;
    if (generation != _generation || _disposed) return;
    if (dataRevision == _dataRevision) {
      _recordPollResult(success, reschedule: false);
    }
    _schedulePoll();
  }

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
    _dataRevision++;
    _session = session;
    _offline = offline;
    _summaryOperation = null;
    _listOperation = null;
    _pollOperation = null;
    _pollFailures = 0;
    _pollTimer?.cancel();
    for (final poll in _detailPolls.values) {
      poll.timer?.cancel();
      poll.operation = null;
      poll.failures = 0;
      poll.refreshRequested = false;
      poll.nextAt = null;
    }
    loading = false;
    failed = false;
    hasMore = false;
    page = 0;
    status = 0;
    unreadCount = openCount = closedCount = 0;
    tickets = const [];
    notifyListeners();
    _requestPoll();
  }

  void _summary(Map data) {
    unreadCount = _number(data['unread_count']);
    openCount = _number(data['open_count']);
    closedCount = _number(data['closed_count']);
  }

  Future<void> refreshSummary() async {
    await _refreshSummary();
  }

  Future<bool?> _observeRefresh(Future<bool?> operation, int generation) async {
    final success = await operation;
    if (generation == _generation && !_disposed && _pollOperation == null) {
      _recordPollResult(success);
    }
    return success;
  }

  Future<bool?> _refreshSummary() {
    final current = _summaryOperation;
    if (current != null) return current;
    final session = _session;
    if (session == null || _offline || _disposed || !_foreground) {
      return Future.value();
    }
    final generation = _generation;
    final revision = ++_summaryRevision;
    final request = () async {
      try {
        final data = await api.request(session, 'ticket-sync/summary');
        if (_disposed ||
            generation != _generation ||
            revision != _summaryRevision) {
          return null;
        }
        _summary(data as Map);
        notifyListeners();
        return true;
      } catch (_) {
        return generation == _generation && !_disposed ? false : null;
      }
    }();
    final operation = _observeRefresh(request, generation);
    _summaryOperation = operation;
    return operation.whenComplete(() {
      if (identical(_summaryOperation, operation)) _summaryOperation = null;
    });
  }

  Future<void> refresh({int? filter, bool more = false}) async {
    await _refreshList(filter: filter, more: more);
  }

  Future<bool?> _refreshList({int? filter, bool more = false}) {
    final session = _session;
    if (session == null ||
        _offline ||
        _disposed ||
        !_foreground ||
        (more && (loading || !hasMore))) {
      return Future.value();
    }
    final requestedStatus = filter ?? status;
    if (!more &&
        _listOperation != null &&
        !_listRequestMore &&
        _listRequestStatus == requestedStatus &&
        _listRequestDataRevision == _dataRevision) {
      return _listOperation!;
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
    final request = () async {
      try {
        final data =
            await api.request(
                  session,
                  'ticket-sync/fetch',
                  query: {'status': status, 'page': nextPage, 'limit': 30},
                )
                as Map;
        if (_disposed ||
            generation != _generation ||
            revision != _listRevision) {
          return null;
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
        return true;
      } catch (_) {
        if (!_disposed &&
            generation == _generation &&
            revision == _listRevision) {
          failed = true;
          return false;
        }
        return null;
      } finally {
        if (!_disposed &&
            generation == _generation &&
            revision == _listRevision) {
          loading = false;
          notifyListeners();
        }
      }
    }();
    final operation = _observeRefresh(request, generation);
    _listRequestStatus = requestedStatus;
    _listRequestDataRevision = _dataRevision;
    _listRequestMore = more;
    _listOperation = operation;
    return operation.whenComplete(() {
      if (identical(_listOperation, operation)) _listOperation = null;
    });
  }

  Future<XboardTicketDetail> detail(
    int id, {
    bool Function()? canRequest,
  }) async {
    final session = _session;
    if (session == null || !isCurrent(session)) {
      throw StateError('No active session');
    }
    final generation = _generation;
    final activity = _activityRevision;
    final data = await api.request(
      session,
      'ticket-sync/detail',
      query: {'id': id},
      canRequest: canRequest == null
          ? null
          : () =>
                generation == _generation &&
                activity == _activityRevision &&
                isCurrent(session) &&
                _canPollDetails &&
                canRequest(),
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
    _dataRevision++;
    _listRevision++;
    _summaryRevision++;
    _summaryOperation = null;
    if (_foreground) await refresh();
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
    _dataRevision++;
    _listRevision++;
    _summaryRevision++;
    _summaryOperation = null;
    if (_foreground) await refresh(filter: action == 'save' ? 0 : null);
  }

  @override
  void dispose() {
    _disposed = true;
    stopPolling();
    _activeViews.clear();
    _detailPolls.clear();
    _generation++;
    super.dispose();
  }
}

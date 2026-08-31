import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'xboard_auth.dart';

const xboardMarqueeUnreadPath = '/api/v1/app/site-message/unread';
const xboardMarqueeReadPath = '/api/v1/app/site-message/read';
const xboardMarqueeLimit = 10;
const xboardMarqueeRefreshInterval = Duration(minutes: 5);
const xboardMarqueeMinimumRequestGap = Duration(seconds: 30);

typedef XboardMarqueeUnreadRequester =
    Future<Object?> Function(Uri endpoint, String token, int limit);
typedef XboardMarqueeReadRequester =
    Future<void> Function(
      Uri endpoint,
      String token,
      XboardMarqueeMessage message,
    );

class XboardMarqueeMessage {
  const XboardMarqueeMessage({
    required this.id,
    required this.marqueeText,
    required this.title,
    required this.detailText,
    required this.actionUrl,
    this.priority = 0,
    this.publishedAtEpochSeconds,
    this.expiresAtEpochSeconds,
    this.rawData = const {},
  });

  final int id;
  final String marqueeText;
  final String title;
  final String detailText;
  final String actionUrl;
  final int priority;
  final int? publishedAtEpochSeconds;
  final int? expiresAtEpochSeconds;
  final Map<String, Object?> rawData;

  Map<String, Object?> toCacheJson() => {
    'id': id,
    'marquee_text': marqueeText,
    'title': title,
    'detail_text': detailText,
    'action_url': actionUrl,
    'priority': priority,
    'published_at': publishedAtEpochSeconds,
    'expires_at': expiresAtEpochSeconds,
  };

  static XboardMarqueeMessage? fromMap(Map<Object?, Object?> raw) {
    final data = raw.map((key, value) => MapEntry(key.toString(), value));
    final id = _integer(data['id'] ?? data['message_id']);
    final marqueeText = _string(data['marquee_text']);
    if (id == null || marqueeText == null) return null;
    return XboardMarqueeMessage(
      id: id,
      marqueeText: marqueeText,
      title: _string(data['title']) ?? '站内消息',
      detailText:
          _string(
            data['detail_text'] ??
                data['content'] ??
                data['message'] ??
                data['detail'],
          ) ??
          marqueeText,
      actionUrl: _string(data['action_url']) ?? '',
      priority: _integer(data['priority']) ?? 0,
      publishedAtEpochSeconds: _integer(data['published_at']),
      expiresAtEpochSeconds: _integer(data['expires_at']),
      rawData: Map.unmodifiable(data),
    );
  }
}

class XboardMarqueeException implements Exception {
  const XboardMarqueeException(this.message);

  final String message;

  @override
  String toString() => message;
}

class XboardMarqueeApi {
  XboardMarqueeApi({
    Dio? dio,
    XboardMarqueeUnreadRequester? unreadRequester,
    XboardMarqueeReadRequester? readRequester,
  }) : _dio =
           dio ??
           Dio(
             BaseOptions(
               connectTimeout: const Duration(seconds: 5),
               sendTimeout: const Duration(seconds: 5),
               receiveTimeout: const Duration(seconds: 8),
             ),
           ),
       _unreadRequester = unreadRequester,
       _readRequester = readRequester;

  final Dio _dio;
  final XboardMarqueeUnreadRequester? _unreadRequester;
  final XboardMarqueeReadRequester? _readRequester;

  Future<List<XboardMarqueeMessage>> fetchUnread({
    required Uri endpoint,
    required String token,
    int limit = xboardMarqueeLimit,
  }) async {
    final requestEndpoint = endpoint.resolve(xboardMarqueeUnreadPath);
    final payload = await (_unreadRequester ?? _requestUnread)(
      requestEndpoint,
      token,
      limit,
    );
    return parseXboardMarqueeUnreadResponse(payload);
  }

  Future<void> markRead({
    required Uri endpoint,
    required String token,
    required XboardMarqueeMessage message,
  }) async {
    final requestEndpoint = endpoint.resolve(xboardMarqueeReadPath);
    await (_readRequester ?? _requestRead)(requestEndpoint, token, message);
  }

  Future<Object?> _requestUnread(Uri endpoint, String token, int limit) async {
    final response = await _dio.postUri<Object?>(
      endpoint,
      data: {'token': token, 'limit': limit},
      options: Options(
        contentType: Headers.jsonContentType,
        responseType: ResponseType.json,
        validateStatus: (status) => status != null,
      ),
    );
    if (response.statusCode == null ||
        response.statusCode! < 200 ||
        response.statusCode! >= 300) {
      throw XboardMarqueeException(
        'Unread site-message request failed (${response.statusCode ?? 0})',
      );
    }
    return response.data;
  }

  Future<void> _requestRead(
    Uri endpoint,
    String token,
    XboardMarqueeMessage message,
  ) async {
    final response = await _dio.postUri<Object?>(
      endpoint,
      data: {'token': token, 'message_id': message.id},
      options: Options(
        contentType: Headers.jsonContentType,
        responseType: ResponseType.json,
        validateStatus: (status) => status != null,
      ),
    );
    if (response.statusCode == null ||
        response.statusCode! < 200 ||
        response.statusCode! >= 300 ||
        !_isSuccessfulReadResponse(response.data)) {
      throw XboardMarqueeException(
        'Read site-message request failed (${response.statusCode ?? 0})',
      );
    }
  }
}

class XboardMarqueeQueueStore {
  XboardMarqueeQueueStore({
    Future<SharedPreferences> Function()? preferencesLoader,
  }) : _preferencesLoader = preferencesLoader ?? SharedPreferences.getInstance;

  static const _keyPrefix = 'xboard.marquee.queue.';

  final Future<SharedPreferences> Function() _preferencesLoader;

  Future<List<XboardMarqueeMessage>> load(String accountKey) async {
    try {
      final preferences = await _preferencesLoader();
      final value = preferences.getString(_key(accountKey));
      if (value == null || value.isEmpty) return const [];
      final decoded = jsonDecode(value);
      if (decoded is! List) return const [];
      return List.unmodifiable(
        decoded
            .whereType<Map>()
            .map(XboardMarqueeMessage.fromMap)
            .whereType<XboardMarqueeMessage>(),
      );
    } catch (_) {
      return const [];
    }
  }

  Future<void> save(
    String accountKey,
    List<XboardMarqueeMessage> messages,
  ) async {
    final preferences = await _preferencesLoader();
    await preferences.setString(
      _key(accountKey),
      jsonEncode(messages.map((message) => message.toCacheJson()).toList()),
    );
  }

  String _key(String accountKey) =>
      '$_keyPrefix${sha256.convert(utf8.encode(accountKey))}';
}

class XboardMarqueeController extends ChangeNotifier {
  XboardMarqueeController({
    XboardMarqueeApi? api,
    XboardMarqueeQueueStore? store,
    DateTime Function()? now,
  }) : _api = api ?? XboardMarqueeApi(),
       _store = store ?? XboardMarqueeQueueStore(),
       _now = now ?? DateTime.now;

  final XboardMarqueeApi _api;
  final XboardMarqueeQueueStore _store;
  final DateTime Function() _now;
  final Set<int> _markingReadIds = {};

  XboardLoginResult? _session;
  String? _accountKey;
  List<XboardMarqueeMessage> _messages = const [];
  Future<void>? _refreshOperation;
  DateTime? _lastRequestAt;
  int _generation = 0;
  bool _loading = false;

  List<XboardMarqueeMessage> get messages => _messages;
  bool get isLoading => _loading;

  Future<void> updateSession(
    XboardLoginResult? session, {
    required bool offline,
  }) async {
    final nextAccountKey = session == null
        ? null
        : '${session.endpoint.origin}|${session.token}';
    if (nextAccountKey == _accountKey) {
      if (!offline) await refresh();
      return;
    }
    final generation = ++_generation;
    _session = session;
    _accountKey = nextAccountKey;
    _lastRequestAt = null;
    _refreshOperation = null;
    _markingReadIds.clear();
    if (nextAccountKey == null) {
      _replaceMessages(const []);
      return;
    }
    final cached = await _store.load(nextAccountKey);
    if (generation != _generation) return;
    _replaceMessages(cached);
    if (!offline) await refresh(force: true);
  }

  Future<void> refresh({bool force = false}) {
    final operation = _refreshOperation;
    if (operation != null) return operation;
    final session = _session;
    final accountKey = _accountKey;
    if (session == null || accountKey == null) return Future.value();
    final lastRequestAt = _lastRequestAt;
    if (!force &&
        lastRequestAt != null &&
        _now().difference(lastRequestAt) < xboardMarqueeMinimumRequestGap) {
      return Future.value();
    }
    final generation = _generation;
    _lastRequestAt = _now();
    _loading = true;
    notifyListeners();
    final future = _refresh(
      session: session,
      accountKey: accountKey,
      generation: generation,
    );
    _refreshOperation = future;
    return future;
  }

  Future<void> _refresh({
    required XboardLoginResult session,
    required String accountKey,
    required int generation,
  }) async {
    try {
      final unread = await _api.fetchUnread(
        endpoint: session.endpoint,
        token: session.token,
      );
      if (generation != _generation || accountKey != _accountKey) return;
      _replaceMessages(unread);
      await _store.save(accountKey, unread);
    } catch (error, stackTrace) {
      debugPrint('[APP] refresh marquee messages failed: $error, $stackTrace');
    } finally {
      if (generation == _generation) {
        _loading = false;
        _refreshOperation = null;
        notifyListeners();
      }
    }
  }

  Future<bool> markRead(XboardMarqueeMessage message) async {
    final session = _session;
    final accountKey = _accountKey;
    if (session == null ||
        accountKey == null ||
        !_messages.any((item) => item.id == message.id) ||
        !_markingReadIds.add(message.id)) {
      return false;
    }
    final generation = _generation;
    try {
      await _api.markRead(
        endpoint: session.endpoint,
        token: session.token,
        message: message,
      );
      if (generation != _generation || accountKey != _accountKey) return false;
      final remaining = _messages
          .where((item) => item.id != message.id)
          .toList(growable: false);
      _replaceMessages(remaining);
      await _store.save(accountKey, remaining);
      return true;
    } catch (_) {
      return false;
    } finally {
      _markingReadIds.remove(message.id);
    }
  }

  void _replaceMessages(List<XboardMarqueeMessage> value) {
    final ids = <int>{};
    _messages = List.unmodifiable(
      value.where(
        (message) => message.marqueeText.isNotEmpty && ids.add(message.id),
      ),
    );
    notifyListeners();
  }
}

List<XboardMarqueeMessage> parseXboardMarqueeUnreadResponse(Object? payload) {
  Object? decoded = payload;
  if (decoded is String) decoded = jsonDecode(decoded);
  if (decoded is Map && _integer(decoded['status']) != 1) {
    throw const XboardMarqueeException(
      'Unread site-message request was rejected',
    );
  }
  Object? rawMessages = decoded;
  if (decoded is Map) {
    final data = decoded['data'];
    rawMessages = switch (data) {
      final List values => values,
      final Map map =>
        map['list'] ?? map['items'] ?? map['messages'] ?? map['data'],
      _ => decoded['list'] ?? decoded['items'] ?? decoded['messages'],
    };
  }
  if (rawMessages is! List) {
    throw const XboardMarqueeException('Invalid unread site-message response');
  }
  final ids = <int>{};
  return List.unmodifiable(
    rawMessages
        .whereType<Map>()
        .map(XboardMarqueeMessage.fromMap)
        .whereType<XboardMarqueeMessage>()
        .where((message) => ids.add(message.id))
        .take(xboardMarqueeLimit),
  );
}

String? _string(Object? value) {
  final normalized = value?.toString().trim();
  return normalized == null || normalized.isEmpty ? null : normalized;
}

int? _integer(Object? value) => switch (value) {
  final int number => number,
  final num number => number.toInt(),
  final String text => int.tryParse(text.trim()),
  _ => null,
};

bool _isSuccessfulReadResponse(Object? payload) {
  Object? decoded = payload;
  if (decoded is String) {
    try {
      decoded = jsonDecode(decoded);
    } on FormatException {
      return false;
    }
  }
  return decoded is Map &&
      _integer(decoded['status']) == 1 &&
      decoded['data'] == true;
}

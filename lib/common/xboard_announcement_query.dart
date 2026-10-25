import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'xboard_auth.dart';
import 'xboard_api_request.dart';

class XboardAnnouncementQueryCache {
  XboardAnnouncementQueryCache({DateTime Function()? now})
    : _now = now ?? DateTime.now;

  final DateTime Function() _now;
  final _entries = <String, _AnnouncementEntry>{};
  int _epoch = 0;

  static String accountKey(XboardLoginResult session) => sha256
      .convert(
        utf8.encode(jsonEncode([session.endpoint.origin, session.authData])),
      )
      .toString();

  Future<List<XboardNoticeData>> load({
    required XboardLoginResult session,
    required Future<List<XboardNoticeData>> Function() loader,
    bool forceRefresh = false,
    bool Function()? canRequest,
  }) {
    final key = accountKey(session);
    final entry = _entries.putIfAbsent(key, _AnnouncementEntry.new);
    final active = entry.request;
    if (active != null && (!forceRefresh || active.forced)) {
      return active.future;
    }
    final now = _now();
    if (!forceRefresh) {
      if (entry.error != null &&
          entry.failedAt != null &&
          !now.isBefore(entry.failedAt!) &&
          now.isBefore(entry.retryAfter!)) {
        return Future.error(entry.error!, entry.stackTrace);
      }
      final value = entry.value;
      final at = entry.at;
      if (value != null && at != null) {
        final age = now.difference(at);
        final ttl = value.isEmpty
            ? const Duration(seconds: 60)
            : const Duration(minutes: 5);
        if (!age.isNegative && age < ttl) return Future.value(value);
      }
    }
    final request = _AnnouncementRequest(++entry.revision, forceRefresh);
    entry.request = request;
    unawaited(_complete(key, entry, request, _epoch, loader, canRequest));
    return request.future;
  }

  void clear() {
    _epoch++;
    _entries.clear();
  }

  Future<void> _complete(
    String key,
    _AnnouncementEntry entry,
    _AnnouncementRequest request,
    int epoch,
    Future<List<XboardNoticeData>> Function() loader,
    bool Function()? canRequest,
  ) async {
    try {
      ensureXboardApiRequestAllowed(canRequest);
      final value = List<XboardNoticeData>.unmodifiable(await loader());
      if (epoch != _epoch || !identical(_entries[key], entry)) {
        throw StateError('announcement_query_superseded');
      }
      if (entry.revision != request.revision) {
        request.completer.complete(await _latest(key, entry, epoch));
        return;
      }
      ensureXboardApiRequestAllowed(canRequest);
      entry.value = value;
      entry.at = _now();
      entry.error = null;
      entry.stackTrace = null;
      entry.failedAt = null;
      entry.retryAfter = null;
      entry.failures = 0;
      request.completer.complete(value);
    } catch (error, stackTrace) {
      if (epoch == _epoch && identical(_entries[key], entry)) {
        if (entry.revision != request.revision) {
          try {
            request.completer.complete(await _latest(key, entry, epoch));
          } catch (latestError, latestStack) {
            request.completer.completeError(latestError, latestStack);
          }
          return;
        }
        if (error is XboardApiRequestDeferred || canRequest?.call() == false) {
          request.completer.completeError(
            error is XboardApiRequestDeferred
                ? error
                : const XboardApiRequestDeferred(),
            stackTrace,
          );
          return;
        }
        const delays = [30, 60, 120, 300];
        entry.failures++;
        final now = _now();
        entry.error = error;
        entry.stackTrace = stackTrace;
        entry.failedAt = now;
        entry.retryAfter = now.add(
          Duration(seconds: delays[(entry.failures - 1).clamp(0, 3)]),
        );
      }
      request.completer.completeError(error, stackTrace);
    } finally {
      if (identical(entry.request, request)) entry.request = null;
    }
  }

  Future<List<XboardNoticeData>> _latest(
    String key,
    _AnnouncementEntry entry,
    int epoch,
  ) async {
    final request = entry.request;
    if (request == null && entry.error != null) {
      Error.throwWithStackTrace(entry.error!, entry.stackTrace!);
    }
    final value = request != null ? await request.future : entry.value;
    if (epoch != _epoch || !identical(_entries[key], entry) || value == null) {
      throw StateError('announcement_query_superseded');
    }
    return value;
  }
}

class _AnnouncementEntry {
  int revision = 0;
  int failures = 0;
  List<XboardNoticeData>? value;
  DateTime? at;
  Object? error;
  StackTrace? stackTrace;
  DateTime? failedAt;
  DateTime? retryAfter;
  _AnnouncementRequest? request;
}

class _AnnouncementRequest {
  _AnnouncementRequest(this.revision, this.forced);

  final int revision;
  final bool forced;
  final completer = Completer<List<XboardNoticeData>>();

  Future<List<XboardNoticeData>> get future => completer.future;
}

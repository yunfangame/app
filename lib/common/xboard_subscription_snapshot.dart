import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'xboard_auth.dart';

class XboardSubscriptionSnapshotCache {
  XboardSubscriptionSnapshotCache({
    DateTime Function()? now,
    this.ttl = const Duration(seconds: 30),
  }) : _now = now ?? DateTime.now;

  final DateTime Function() _now;
  final Duration ttl;
  final _entries = <String, _SnapshotEntry>{};
  int _epoch = 0;

  static String accountKey(XboardLoginResult session) => sha256
      .convert(
        utf8.encode(
          jsonEncode([
            session.endpoint.origin,
            session.authData,
            session.token,
            session.secureSubscription,
          ]),
        ),
      )
      .toString();

  Future<XboardSubscriptionData> load({
    required XboardLoginResult session,
    required Future<XboardSubscriptionData> Function() loader,
    bool forceRefresh = false,
  }) {
    final key = accountKey(session);
    final entry = _entries.putIfAbsent(key, _SnapshotEntry.new);
    final forced = entry.forced;
    if (forced != null) return forced.future;
    final now = _now();
    if (!forceRefresh) {
      final value = entry.value;
      final at = entry.at;
      if (value != null && at != null && _fresh(value, at, now)) {
        return Future.value(value);
      }
      if (entry.normal != null) return entry.normal!.future;
      if (entry.error != null &&
          entry.failedAt != null &&
          !now.isBefore(entry.failedAt!) &&
          now.isBefore(entry.retryAfter!)) {
        return Future.error(entry.error!, entry.stackTrace);
      }
    }
    final request = _SnapshotRequest(++entry.revision);
    if (forceRefresh) {
      entry.forced = request;
      entry.normal = null;
    } else {
      entry.normal = request;
    }
    unawaited(_complete(key, entry, request, _epoch, loader));
    return request.future;
  }

  bool _fresh(XboardSubscriptionData value, DateTime at, DateTime now) {
    final age = now.difference(at);
    if (age.isNegative || age >= ttl) return false;
    for (final seconds in [
      value.expiredAtEpochSeconds,
      value.nextResetAtEpochSeconds,
    ]) {
      if (seconds == null || seconds <= 0 || seconds > 8640000000000) continue;
      final boundary = DateTime.fromMillisecondsSinceEpoch(seconds * 1000);
      if (boundary.isAfter(at) && !boundary.isAfter(now)) return false;
    }
    return true;
  }

  void remember(XboardLoginResult session, XboardSubscriptionData value) {
    final entry = _entries.putIfAbsent(accountKey(session), _SnapshotEntry.new);
    entry.revision++;
    entry.valueRevision = entry.revision;
    entry.value = value;
    entry.at = _now();
    entry.failures = 0;
    entry.error = null;
    entry.stackTrace = null;
    entry.failedAt = null;
    entry.retryAfter = null;
  }

  void clear() {
    _epoch++;
    _entries.clear();
  }

  Future<void> _complete(
    String key,
    _SnapshotEntry entry,
    _SnapshotRequest request,
    int epoch,
    Future<XboardSubscriptionData> Function() loader,
  ) async {
    try {
      final value = await loader();
      if (epoch != _epoch || !identical(_entries[key], entry)) {
        throw StateError('subscription_snapshot_superseded');
      }
      if (entry.revision == request.revision) {
        entry.value = value;
        entry.valueRevision = request.revision;
        entry.at = _now();
        entry.failures = 0;
        entry.error = null;
        entry.stackTrace = null;
        entry.failedAt = null;
        entry.retryAfter = null;
      }
      final newer = entry.forced;
      if (entry.error != null && entry.errorRevision > request.revision) {
        Error.throwWithStackTrace(entry.error!, entry.stackTrace!);
      }
      request.completer.complete(
        newer != null && !identical(newer, request)
            ? await newer.future
            : entry.valueRevision > request.revision
            ? entry.value ?? value
            : value,
      );
    } catch (error, stackTrace) {
      if (epoch == _epoch &&
          identical(_entries[key], entry) &&
          entry.revision == request.revision) {
        entry.failures++;
        const delays = [30, 60, 120, 300];
        final now = _now();
        entry.error = error;
        entry.errorRevision = request.revision;
        entry.stackTrace = stackTrace;
        entry.failedAt = now;
        entry.retryAfter = now.add(
          Duration(seconds: delays[(entry.failures - 1).clamp(0, 3)]),
        );
      }
      final newer = entry.forced;
      if (epoch == _epoch && newer != null && !identical(newer, request)) {
        try {
          request.completer.complete(await newer.future);
        } catch (newError, newStackTrace) {
          request.completer.completeError(newError, newStackTrace);
        }
      } else if (epoch == _epoch &&
          identical(_entries[key], entry) &&
          entry.error != null &&
          entry.errorRevision > request.revision) {
        request.completer.completeError(entry.error!, entry.stackTrace);
      } else if (epoch == _epoch &&
          identical(_entries[key], entry) &&
          entry.valueRevision > request.revision &&
          entry.value != null) {
        request.completer.complete(entry.value);
      } else {
        request.completer.completeError(error, stackTrace);
      }
    } finally {
      if (identical(entry.forced, request)) entry.forced = null;
      if (identical(entry.normal, request)) entry.normal = null;
    }
  }
}

class _SnapshotEntry {
  XboardSubscriptionData? value;
  DateTime? at;
  Object? error;
  StackTrace? stackTrace;
  DateTime? failedAt;
  DateTime? retryAfter;
  int failures = 0;
  int revision = 0;
  int valueRevision = 0;
  int errorRevision = 0;
  _SnapshotRequest? normal;
  _SnapshotRequest? forced;
}

class _SnapshotRequest {
  _SnapshotRequest(this.revision);

  final int revision;
  final completer = Completer<XboardSubscriptionData>();

  Future<XboardSubscriptionData> get future => completer.future;
}

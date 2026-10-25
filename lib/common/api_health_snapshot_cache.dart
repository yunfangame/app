import 'dart:async';

import 'api_health.dart';

class ApiHealthSnapshotCache {
  ApiHealthSnapshotCache({
    DateTime Function()? now,
    this.ttl = const Duration(seconds: 30),
  }) : _now = now ?? DateTime.now;

  final DateTime Function() _now;
  final Duration ttl;
  final _entries = <String, _HealthSnapshotEntry>{};

  ApiHealthSnapshot? peek(String scope) => _entries[scope]?.value;

  Future<ApiHealthSnapshot> load({
    required String scope,
    required Future<ApiHealthSnapshot> Function() loader,
    required bool forceRefresh,
  }) {
    final entry = _entries.putIfAbsent(scope, _HealthSnapshotEntry.new);
    if (_entries.length > 32) {
      final idle = _entries.entries.where(
        (item) =>
            item.key != scope &&
            item.value.normal == null &&
            item.value.forced == null,
      );
      if (idle.isNotEmpty) _entries.remove(idle.first.key);
    }
    final forced = entry.forced;
    if (forced != null) return forced.future;
    final now = _now();
    if (!forceRefresh) {
      final at = entry.at;
      final value = entry.value;
      if (value != null && at != null) {
        final age = now.difference(at);
        if (!age.isNegative &&
            ((entry.failures == 0 && age < ttl) ||
                (entry.failures > 0 && now.isBefore(entry.retryAfter!)))) {
          return Future.value(value);
        }
      }
      final normal = entry.normal;
      if (normal != null) return normal.future;
    }
    final request = _HealthSnapshotRequest(++entry.revision);
    if (forceRefresh) {
      final normal = entry.normal;
      entry.forced = request;
      entry.normal = null;
      if (normal != null && !normal.completer.isCompleted) {
        normal.completer.complete(request.future);
      }
    } else {
      entry.normal = request;
    }
    unawaited(_complete(entry, request, loader));
    return request.future;
  }

  Future<void> _complete(
    _HealthSnapshotEntry entry,
    _HealthSnapshotRequest request,
    Future<ApiHealthSnapshot> Function() loader,
  ) async {
    ApiHealthSnapshot result;
    try {
      result = await loader();
    } catch (_) {
      result = ApiHealthSnapshot.unavailable('check_failed');
    }
    if (entry.revision == request.revision && !result.isDeferred) {
      entry.value = result;
      entry.valueRevision = request.revision;
      entry.at = _now();
      if (result.reachableCount == 0) {
        entry.failures++;
        const delays = [30, 60, 120, 300];
        entry.retryAfter = entry.at!.add(
          Duration(seconds: delays[(entry.failures - 1).clamp(0, 3)]),
        );
      } else {
        entry.failures = 0;
        entry.retryAfter = null;
      }
    }
    final newer = entry.forced;
    if (!request.completer.isCompleted) {
      if (newer != null && !identical(newer, request)) {
        request.completer.complete(await newer.future);
      } else {
        request.completer.complete(
          entry.valueRevision > request.revision ? entry.value! : result,
        );
      }
    }
    if (identical(entry.normal, request)) entry.normal = null;
    if (identical(entry.forced, request)) entry.forced = null;
  }
}

class _HealthSnapshotEntry {
  ApiHealthSnapshot? value;
  DateTime? at;
  DateTime? retryAfter;
  int failures = 0;
  int revision = 0;
  int valueRevision = 0;
  _HealthSnapshotRequest? normal;
  _HealthSnapshotRequest? forced;
}

class _HealthSnapshotRequest {
  _HealthSnapshotRequest(this.revision);

  final int revision;
  final completer = Completer<ApiHealthSnapshot>();

  Future<ApiHealthSnapshot> get future => completer.future;
}

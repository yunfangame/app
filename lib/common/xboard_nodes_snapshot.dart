import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'xboard_auth.dart';

class XboardNodesSnapshotCache {
  XboardNodesSnapshotCache({
    DateTime Function()? now,
    this.ttl = const Duration(seconds: 30),
  }) : _now = now ?? DateTime.now;

  final DateTime Function() _now;
  final Duration ttl;
  final _entries = <String, _NodesSnapshotEntry>{};
  int? _epoch;
  int _generation = 0;

  static String accountKey(XboardLoginResult session) => sha256
      .convert(
        utf8.encode(
          jsonEncode([
            session.endpoint.toString(),
            session.authData,
            session.token,
            session.secureSubscription,
            session.subscription.email?.trim().toLowerCase(),
            session.subscription.uuid,
          ]),
        ),
      )
      .toString();

  Future<List<XboardNodeData>> load({
    required XboardLoginResult session,
    required int epoch,
    required Future<List<XboardNodeData>> Function() loader,
    bool forceRefresh = false,
  }) {
    if (!_selectEpoch(epoch)) {
      return Future.error(StateError('nodes_snapshot_superseded'));
    }
    final key = accountKey(session);
    final entry = _entries.putIfAbsent(key, _NodesSnapshotEntry.new);
    final forced = entry.forced;
    if (forced != null) return forced.future;
    if (!forceRefresh) {
      final at = entry.at;
      final value = entry.value;
      if (at != null && value != null) {
        final age = _now().difference(at);
        if (!age.isNegative && age < ttl) return Future.value(value);
      }
      final normal = entry.normal;
      if (normal != null) return normal.future;
    }
    final request = _NodesSnapshotRequest(++entry.revision);
    if (forceRefresh) {
      final normal = entry.normal;
      entry.normal = null;
      entry.forced = request;
      if (normal != null && !normal.completer.isCompleted) {
        normal.completer.complete(request.future);
      }
    } else {
      entry.normal = request;
    }
    unawaited(_complete(key, entry, request, _generation, loader));
    return request.future;
  }

  void remember(
    XboardLoginResult session,
    List<XboardNodeData> nodes, {
    required int epoch,
  }) {
    if (!_selectEpoch(epoch)) return;
    final entry = _entries.putIfAbsent(
      accountKey(session),
      _NodesSnapshotEntry.new,
    );
    final value = _freezeNodes(nodes);
    entry.revision++;
    entry.value = value;
    entry.at = _now();
    for (final pending in [entry.normal, entry.forced]) {
      if (pending != null && !pending.completer.isCompleted) {
        pending.completer.complete(value);
      }
    }
    entry.normal = null;
    entry.forced = null;
  }

  bool _selectEpoch(int epoch) {
    final current = _epoch;
    if (current != null && epoch < current) return false;
    if (epoch != current) {
      clear();
      _epoch = epoch;
    }
    return true;
  }

  void clear() {
    _generation++;
    for (final entry in _entries.values) {
      for (final pending in [entry.normal, entry.forced]) {
        if (pending != null && !pending.completer.isCompleted) {
          pending.completer.completeError(
            StateError('nodes_snapshot_superseded'),
          );
        }
      }
    }
    _entries.clear();
  }

  Future<void> _complete(
    String key,
    _NodesSnapshotEntry entry,
    _NodesSnapshotRequest request,
    int generation,
    Future<List<XboardNodeData>> Function() loader,
  ) async {
    try {
      final value = _freezeNodes(await loader());
      if (generation != _generation || !identical(_entries[key], entry)) {
        throw StateError('nodes_snapshot_superseded');
      }
      if (entry.revision == request.revision) {
        entry.value = value;
        entry.at = _now();
      }
      if (!request.completer.isCompleted) request.completer.complete(value);
    } catch (error, stackTrace) {
      if (!request.completer.isCompleted) {
        request.completer.completeError(error, stackTrace);
      }
    } finally {
      if (identical(entry.normal, request)) entry.normal = null;
      if (identical(entry.forced, request)) entry.forced = null;
    }
  }

  List<XboardNodeData> _freezeNodes(List<XboardNodeData> nodes) =>
      List.unmodifiable(
        nodes.map(
          (node) => XboardNodeData(
            id: node.id,
            name: node.name,
            type: node.type,
            rate: node.rate,
            tags: List.unmodifiable(node.tags),
            isOnline: node.isOnline,
            rawData: Map.unmodifiable(
              node.rawData.map(
                (key, value) => MapEntry(key, _freezeValue(value)),
              ),
            ),
          ),
        ),
      );

  Object? _freezeValue(Object? value) {
    if (value is List) return List.unmodifiable(value.map(_freezeValue));
    if (value is Map) {
      return Map.unmodifiable(
        value.map((key, value) => MapEntry(key, _freezeValue(value))),
      );
    }
    return value;
  }
}

class _NodesSnapshotEntry {
  List<XboardNodeData>? value;
  DateTime? at;
  int revision = 0;
  _NodesSnapshotRequest? normal;
  _NodesSnapshotRequest? forced;
}

class _NodesSnapshotRequest {
  _NodesSnapshotRequest(this.revision);

  final int revision;
  final completer = Completer<List<XboardNodeData>>();

  Future<List<XboardNodeData>> get future => completer.future;
}

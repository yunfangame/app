import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'xboard_auth.dart';
import 'xboard_api_request.dart';

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
  }) => loadGuarded(
    session: session,
    epoch: epoch,
    loader: (_) => loader(),
    forceRefresh: forceRefresh,
  );

  Future<List<XboardNodeData>> loadGuarded({
    required XboardLoginResult session,
    required int epoch,
    required Future<List<XboardNodeData>> Function(bool Function() canRequest)
    loader,
    bool Function()? canRequest,
    bool forceRefresh = false,
  }) {
    if (!_selectEpoch(epoch)) {
      return Future.error(StateError('nodes_snapshot_superseded'));
    }
    if (canRequest?.call() == false) {
      return Future.error(const XboardApiRequestDeferred());
    }
    final key = accountKey(session);
    final entry = _entries.putIfAbsent(key, _NodesSnapshotEntry.new);
    final forced = entry.forced;
    if (forced != null && _isAdmitting(forced)) {
      return _join(forced, canRequest);
    }
    if (forced != null) entry.forced = null;
    if (!forceRefresh) {
      final at = entry.at;
      final value = entry.value;
      if (at != null && value != null) {
        final age = _now().difference(at);
        if (!age.isNegative && age < ttl) {
          final consumer = XboardApiRequestConsumers().add(canRequest);
          return canRequest == null
              ? Future.value(value)
              : consumer.wait(Future.value(value));
        }
      }
      final normal = entry.normal;
      if (normal != null && _isAdmitting(normal)) {
        return _join(normal, canRequest);
      }
      if (normal != null) entry.normal = null;
    }
    final request = _NodesSnapshotRequest(++entry.revision);
    final consumer = request.consumers.add(canRequest);
    if (forceRefresh) {
      final normal = entry.normal;
      entry.normal = null;
      entry.forced = request;
      if (normal != null && !normal.completer.isCompleted) {
        request.consumers.inherit(normal.consumers);
        normal.consumers.close();
        normal.completer.complete(request.future);
      }
    } else {
      entry.normal = request;
    }
    unawaited(_complete(key, entry, request, _generation, loader));
    return canRequest == null ? request.future : consumer.wait(request.future);
  }

  bool _isAdmitting(_NodesSnapshotRequest request) {
    if (request.consumers.aggregateAllowed) return true;
    request.consumers.close();
    if (!request.completer.isCompleted) {
      request.completer.completeError(const XboardApiRequestDeferred());
    }
    return false;
  }

  Future<List<XboardNodeData>> _join(
    _NodesSnapshotRequest request,
    bool Function()? canRequest,
  ) {
    final consumer = request.consumers.add(canRequest);
    return canRequest == null ? request.future : consumer.wait(request.future);
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
          pending.consumers.close();
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
    Future<List<XboardNodeData>> Function(bool Function() canRequest) loader,
  ) async {
    bool allowed() =>
        generation == _generation &&
        identical(_entries[key], entry) &&
        entry.revision == request.revision &&
        request.consumers.aggregateAllowed;
    try {
      ensureXboardApiRequestAllowed(allowed);
      final value = _freezeNodes(await loader(allowed));
      ensureXboardApiRequestAllowed(allowed);
      entry.value = value;
      entry.at = _now();
      if (!request.completer.isCompleted) request.completer.complete(value);
    } catch (error, stackTrace) {
      if (!request.completer.isCompleted) {
        request.completer.completeError(error, stackTrace);
      }
    } finally {
      request.consumers.close();
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
  final consumers = XboardApiRequestConsumers();
  final completer = Completer<List<XboardNodeData>>();

  Future<List<XboardNodeData>> get future => completer.future;
}

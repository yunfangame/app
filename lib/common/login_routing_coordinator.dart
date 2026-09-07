import 'dart:async';

import 'package:collection/collection.dart';
import 'package:fl_clash/models/profile.dart';

bool loginRoutingProfileMatches(
  Profile? expected,
  Profile? current, {
  bool allowContentRefresh = false,
}) {
  if (expected == null || current == null) return expected == current;
  return expected.id == current.id &&
      expected.url == current.url &&
      (allowContentRefresh ||
          expected.lastUpdateDate == current.lastUpdateDate) &&
      expected.currentGroupName == current.currentGroupName &&
      const MapEquality<String, String>().equals(
        expected.selectedMap,
        current.selectedMap,
      ) &&
      expected.overwriteType == current.overwriteType &&
      expected.scriptId == current.scriptId;
}

class LoginRoutingAttempt {
  LoginRoutingAttempt(this._isSessionCurrent);

  final bool Function() _isSessionCurrent;
  final _cancelled = Completer<void>();

  bool get isCancelled => _cancelled.isCompleted || !_isSessionCurrent();

  void _cancel() {
    if (!_cancelled.isCompleted) _cancelled.complete();
  }
}

class LoginRoutingCoordinator {
  LoginRoutingCoordinator({
    required void Function() resetToRule,
    required void Function() cancelSelection,
  }) : _resetToRule = resetToRule,
       _cancelSelection = cancelSelection;

  final void Function() _resetToRule;
  final void Function() _cancelSelection;
  LoginRoutingAttempt? _active;
  bool _disposed = false;

  LoginRoutingAttempt begin({required bool Function() isSessionCurrent}) {
    if (_disposed) throw StateError('login_routing_disposed');
    cancel();
    _resetToRule();
    return _active = LoginRoutingAttempt(isSessionCurrent);
  }

  bool isCurrent(LoginRoutingAttempt attempt) =>
      !_disposed && identical(attempt, _active) && !attempt.isCancelled;

  Future<void> select<T>(
    LoginRoutingAttempt attempt, {
    required Future<void> Function() prepare,
    required bool Function() canStart,
    required Future<T> Function(bool Function() isCancelled) select,
    required void Function(T result) onResult,
    required void Function(Object error) onError,
  }) async {
    bool isCancelled() => !isCurrent(attempt);
    if (isCancelled()) return;
    try {
      final ready = await Future.any([
        prepare().then((_) => true),
        attempt._cancelled.future.then((_) => false),
      ]);
      if (!ready || isCancelled() || !canStart()) return;
      final result = await select(isCancelled);
      if (!isCancelled()) onResult(result);
    } catch (error) {
      if (!isCancelled()) onError(error);
    }
  }

  void cancel() {
    _active?._cancel();
    _active = null;
    if (!_disposed) _cancelSelection();
  }

  void dispose() {
    if (_disposed) return;
    cancel();
    _disposed = true;
  }
}

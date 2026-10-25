import 'dart:async';

import 'package:fl_clash/state.dart';

import 'xboard_auth.dart';

final _catalogScope = _CatalogScope();
final xboardPlanCatalog = XboardCatalogCache<List<XboardAvailablePlan>>();

class XboardCatalogCache<T> {
  XboardCatalogCache({
    this.ttl = const Duration(minutes: 1),
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  final Duration ttl;
  final DateTime Function() _now;
  final Map<Object, _CatalogEntry<T>> _entries = {};
  int? _epoch;

  T? peek(XboardLoginResult session, {Object key = 'all'}) {
    _synchronize(session);
    final entry = _entries[key];
    final at = entry?.at;
    if (entry == null || at == null || entry.pending != null) return null;
    final age = _now().difference(at);
    return !age.isNegative && age < ttl ? entry.value : null;
  }

  Future<T>? inFlight(XboardLoginResult session, {Object key = 'all'}) {
    _synchronize(session);
    return _entries[key]?.pending;
  }

  Future<T> load(
    XboardLoginResult session,
    Future<T> Function() loader, {
    Object key = 'all',
    bool forceRefresh = false,
  }) {
    final epoch = _synchronize(session);
    final entry = _entries.putIfAbsent(key, _CatalogEntry<T>.new);
    if (entry.forced != null) return entry.forced!;
    if (!forceRefresh) {
      final value = peek(session, key: key);
      if (value != null) return Future.value(value);
      if (entry.pending != null) return entry.pending!;
    }
    final revision = ++entry.revision;
    final completer = Completer<T>();
    final future = completer.future;
    entry.latest = future;
    entry.pending = future;
    if (forceRefresh) entry.forced = future;
    unawaited(() async {
      try {
        final value = await loader();
        if (!_isCurrent(session, epoch, key, entry)) {
          throw StateError('Catalog session changed');
        }
        if (entry.revision != revision) {
          completer.complete(await entry.latest!);
        } else {
          entry.value = value;
          entry.at = _now();
          completer.complete(value);
        }
      } catch (error, stackTrace) {
        if (_isCurrent(session, epoch, key, entry) &&
            entry.revision != revision) {
          try {
            completer.complete(await entry.latest!);
          } catch (latestError, latestStack) {
            completer.completeError(latestError, latestStack);
          }
        } else {
          completer.completeError(error, stackTrace);
        }
      } finally {
        if (identical(entry.pending, future)) entry.pending = null;
        if (identical(entry.forced, future)) entry.forced = null;
      }
    }());
    return future;
  }

  void invalidate(XboardLoginResult session) {
    if (!_catalogScope.matches(session)) return;
    _entries.clear();
    _epoch = _catalogScope.epoch;
  }

  int _synchronize(XboardLoginResult session) {
    final epoch = _catalogScope.capture(session);
    if (_epoch != epoch) {
      _entries.clear();
      _epoch = epoch;
    }
    return epoch;
  }

  bool _isCurrent(
    XboardLoginResult session,
    int epoch,
    Object key,
    _CatalogEntry<T> entry,
  ) =>
      _catalogScope.matches(session) &&
      _catalogScope.epoch == epoch &&
      _epoch == epoch &&
      identical(_entries[key], entry);
}

class _CatalogEntry<T> {
  T? value;
  DateTime? at;
  Future<T>? pending;
  Future<T>? forced;
  Future<T>? latest;
  int revision = 0;
}

class _CatalogScope {
  bool _listening = false;
  (String, String)? _identity;
  bool _offline = false;
  int epoch = 0;

  (String, String)? _key(XboardLoginResult? session) {
    if (session == null) return null;
    final endpoint = session.endpoint;
    if (!{'http', 'https'}.contains(endpoint.scheme) ||
        endpoint.host.isEmpty ||
        endpoint.userInfo.isNotEmpty ||
        session.authData.isEmpty) {
      return null;
    }
    return (endpoint.origin, session.authData);
  }

  void _sync() {
    final identity = _key(globalState.xboardSession);
    final offline = globalState.isOfflineMode;
    if (_identity == identity && _offline == offline) return;
    _identity = identity;
    _offline = offline;
    epoch++;
  }

  bool matches(XboardLoginResult session) {
    if (!_listening) {
      _listening = true;
      globalState.xboardSessionRevisionNotifier.addListener(_sync);
      globalState.offlineModeNotifier.addListener(_sync);
    }
    _sync();
    return !_offline && _identity != null && _key(session) == _identity;
  }

  int capture(XboardLoginResult session) {
    if (!matches(session)) throw StateError('Catalog session unavailable');
    return epoch;
  }
}

Future<List<XboardAvailablePlan>> loadXboardPlanCatalog({
  required XboardAuthService authService,
  required XboardLoginResult session,
  int? planId,
  bool forceRefresh = false,
}) async {
  final epoch = _catalogScope.capture(session);
  if (planId != null && !forceRefresh) {
    var plans = xboardPlanCatalog.peek(session);
    if (plans == null) {
      final pending = xboardPlanCatalog.inFlight(session);
      if (pending != null) {
        try {
          plans = await pending;
        } on XboardAuthException catch (error) {
          if (error.failure == XboardAuthFailure.authenticationRejected) {
            rethrow;
          }
        }
        _ensureCatalogEpoch(session, epoch);
      }
    }
    if (plans != null && plans.any((plan) => plan.id == planId)) {
      return plans;
    }
  }
  return xboardPlanCatalog.load(
    session,
    () => authService.fetchPlans(
      endpoint: session.endpoint,
      authData: session.authData,
      planId: planId,
    ),
    key: planId ?? 'all',
    forceRefresh: forceRefresh,
  );
}

Future<XboardAvailablePlan?> findXboardCatalogPlan({
  required XboardAuthService authService,
  required XboardLoginResult session,
  int? planId,
  String? planName,
  bool forceRefresh = false,
}) async {
  final epoch = _catalogScope.capture(session);
  if (planId != null) {
    try {
      final plans = await loadXboardPlanCatalog(
        authService: authService,
        session: session,
        planId: planId,
        forceRefresh: forceRefresh,
      );
      for (final plan in plans) {
        if (plan.id == planId) return plan;
      }
    } on XboardAuthException catch (error) {
      if (error.failure == XboardAuthFailure.authenticationRejected) rethrow;
    }
  }
  _ensureCatalogEpoch(session, epoch);
  final plans = await loadXboardPlanCatalog(
    authService: authService,
    session: session,
    forceRefresh: forceRefresh,
  );
  for (final plan in plans) {
    if (planId != null && plan.id == planId) return plan;
  }
  if (planName != null) {
    for (final plan in plans) {
      if (plan.name.trim() == planName.trim()) return plan;
    }
  }
  return null;
}

void _ensureCatalogEpoch(XboardLoginResult session, int epoch) {
  if (!_catalogScope.matches(session) || _catalogScope.epoch != epoch) {
    throw StateError('Catalog session changed');
  }
}

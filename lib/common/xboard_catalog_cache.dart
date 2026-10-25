import 'dart:async';

import 'package:fl_clash/state.dart';

import 'xboard_auth.dart';
import 'xboard_api_request.dart';

final _catalogScope = _CatalogScope();
final xboardPlanCatalog = XboardCatalogCache<List<XboardAvailablePlan>>();
final xboardPaymentMethodCatalog =
    XboardCatalogCache<List<XboardPaymentMethod>>();

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

  Future<T>? inFlight(
    XboardLoginResult session, {
    Object key = 'all',
    bool Function()? canRequest,
  }) {
    _synchronize(session);
    final request = _entries[key]?.pending;
    if (request == null || !request.consumers.aggregateAllowed) return null;
    final consumer = request.consumers.add(canRequest);
    return consumer.wait(request.future);
  }

  Future<T> load(
    XboardLoginResult session,
    Future<T> Function() loader, {
    Object key = 'all',
    bool forceRefresh = false,
    bool Function()? canRequest,
  }) => loadGuarded(
    session,
    (_) => loader(),
    key: key,
    forceRefresh: forceRefresh,
    canRequest: canRequest,
  );

  Future<T> loadGuarded(
    XboardLoginResult session,
    Future<T> Function(bool Function() canRequest) loader, {
    Object key = 'all',
    bool forceRefresh = false,
    bool Function()? canRequest,
  }) {
    final epoch = _synchronize(session);
    final entry = _entries.putIfAbsent(key, _CatalogEntry<T>.new);
    final forced = entry.forced;
    if (forced != null && forced.consumers.aggregateAllowed) {
      return forced.consumers.add(canRequest).wait(forced.future);
    }
    if (!forceRefresh) {
      final value = peek(session, key: key);
      if (value != null) {
        if (canRequest?.call() == false) {
          return Future.error(const XboardApiRequestDeferred());
        }
        return Future.value(value);
      }
      final pending = entry.pending;
      if (pending != null && pending.consumers.aggregateAllowed) {
        return pending.consumers.add(canRequest).wait(pending.future);
      }
    }
    final request = _CatalogRequest<T>(entry.revision + 1);
    final consumer = request.consumers.add(canRequest);
    if (!consumer.allowed) {
      return Future.error(const XboardApiRequestDeferred());
    }
    entry.revision = request.revision;
    if (forceRefresh && entry.pending != null) {
      request.consumers.inherit(entry.pending!.consumers);
      entry.pending!.consumers.close();
    }
    entry.latest = request;
    entry.pending = request;
    if (forceRefresh) entry.forced = request;
    bool requestAllowed() =>
        _isCurrent(session, epoch, key, entry) &&
        entry.revision == request.revision &&
        request.consumers.aggregateAllowed;
    unawaited(() async {
      try {
        ensureXboardApiRequestAllowed(requestAllowed);
        final value = await loader(requestAllowed);
        if (!_isCurrent(session, epoch, key, entry)) {
          throw StateError('Catalog session changed');
        }
        if (entry.revision != request.revision) {
          request.completer.complete(await entry.latest!.future);
        } else {
          ensureXboardApiRequestAllowed(requestAllowed);
          entry.value = value;
          entry.at = _now();
          request.completer.complete(value);
        }
      } catch (error, stackTrace) {
        if (_isCurrent(session, epoch, key, entry) &&
            entry.revision != request.revision) {
          try {
            request.completer.complete(await entry.latest!.future);
          } catch (latestError, latestStack) {
            request.completer.completeError(latestError, latestStack);
          }
        } else {
          request.completer.completeError(
            !_isCurrent(session, epoch, key, entry)
                ? StateError('Catalog session changed')
                : error is XboardApiRequestDeferred ||
                      !request.consumers.aggregateAllowed
                ? const XboardApiRequestDeferred()
                : error,
            stackTrace,
          );
        }
      } finally {
        if (identical(entry.pending, request)) entry.pending = null;
        if (identical(entry.forced, request)) entry.forced = null;
      }
    }());
    return consumer.wait(request.future);
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
  _CatalogRequest<T>? pending;
  _CatalogRequest<T>? forced;
  _CatalogRequest<T>? latest;
  int revision = 0;
}

class _CatalogRequest<T> {
  _CatalogRequest(this.revision);
  final int revision;
  final consumers = XboardApiRequestConsumers();
  final completer = Completer<T>();
  Future<T> get future => completer.future;
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
  bool Function()? canRequest,
}) async {
  ensureXboardApiRequestAllowed(canRequest);
  final epoch = _catalogScope.capture(session);
  if (planId != null && !forceRefresh) {
    var plans = xboardPlanCatalog.peek(session);
    if (plans == null) {
      final pending = xboardPlanCatalog.inFlight(
        session,
        canRequest: canRequest,
      );
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
  return xboardPlanCatalog.loadGuarded(
    session,
    (requestAllowed) => authService.fetchPlans(
      endpoint: session.endpoint,
      authData: session.authData,
      planId: planId,
      canRequest: requestAllowed,
    ),
    canRequest: canRequest,
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
  bool Function()? canRequest,
}) async {
  ensureXboardApiRequestAllowed(canRequest);
  final epoch = _catalogScope.capture(session);
  if (planId != null) {
    try {
      final plans = await loadXboardPlanCatalog(
        authService: authService,
        session: session,
        planId: planId,
        forceRefresh: forceRefresh,
        canRequest: canRequest,
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
    canRequest: canRequest,
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

Future<List<XboardPaymentMethod>> loadXboardPaymentMethodCatalog({
  required XboardAuthService authService,
  required XboardLoginResult session,
  bool forceRefresh = false,
  bool Function()? canRequest,
}) => xboardPaymentMethodCatalog.loadGuarded(
  session,
  (requestAllowed) => authService.fetchPaymentMethods(
    endpoint: session.endpoint,
    authData: session.authData,
    canRequest: requestAllowed,
  ),
  canRequest: canRequest,
  forceRefresh: forceRefresh,
);

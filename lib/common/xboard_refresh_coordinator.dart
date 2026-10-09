import 'dart:async';

class XboardRefreshAttempt<T> {
  XboardRefreshAttempt(
    this.isCurrent,
    this.refreshMetadata,
    this.retryWhenUnchanged,
  );

  final bool Function() isCurrent;
  bool refreshMetadata;
  bool retryWhenUnchanged;
  void Function()? onMetadataRequested;
  final _completer = Completer<T>();

  Future<T> get future => _completer.future;

  void _requestMetadata() {
    if (refreshMetadata) return;
    refreshMetadata = true;
    onMetadataRequested?.call();
  }
}

class XboardRefreshCoordinator<T> {
  XboardRefreshAttempt<T>? _active;

  Future<T> run({
    required bool Function() isCurrent,
    required Future<T> Function(XboardRefreshAttempt<T> attempt) refresh,
    bool refreshMetadata = false,
    bool retryWhenUnchanged = false,
  }) {
    final active = _active;
    if (active != null && active.isCurrent()) {
      if (refreshMetadata) active._requestMetadata();
      active.retryWhenUnchanged |= retryWhenUnchanged;
      return active.future;
    }
    final attempt = XboardRefreshAttempt<T>(
      isCurrent,
      refreshMetadata,
      retryWhenUnchanged,
    );
    _active = attempt;
    unawaited(() async {
      try {
        attempt._completer.complete(await refresh(attempt));
      } catch (error, stackTrace) {
        attempt._completer.completeError(error, stackTrace);
      } finally {
        attempt.onMetadataRequested = null;
        if (identical(_active, attempt)) _active = null;
      }
    }());
    return attempt.future;
  }

  void cancel() {
    _active = null;
  }
}

Future<T> syncXboardProfileFirst<T>({
  required Future<T> Function() syncProfile,
  required Future<void> Function(T profile) prepareRouting,
  required bool Function() isCurrent,
  Future<void> Function()? refreshMetadata,
  void Function(Object error, StackTrace stackTrace)? onMetadataError,
}) async {
  if (!isCurrent()) throw StateError('profile_sync_superseded');
  final profileFuture = syncProfile();
  if (refreshMetadata != null) {
    unawaited(
      Future<void>.sync(refreshMetadata).then<void>(
        (_) {},
        onError: (Object error, StackTrace stackTrace) {
          if (isCurrent()) onMetadataError?.call(error, stackTrace);
        },
      ),
    );
  }
  final profile = await profileFuture;
  if (!isCurrent()) throw StateError('profile_sync_superseded');
  await prepareRouting(profile);
  if (!isCurrent()) throw StateError('profile_sync_superseded');
  return profile;
}

part of '../action.dart';

class CorePreparationException implements Exception {
  const CorePreparationException(this.code, {this.cause});

  final String code;
  final Object? cause;

  @override
  String toString() => 'CorePreparationException($code)';
}

@Riverpod(keepAlive: true)
class CoreAction extends _$CoreAction {
  final _lifecycleScheduler = SerialTaskScheduler();
  int _lifecycleRevision = 0;
  int _requestedRestartRevision = 0;
  Future<void>? _restartOperation;

  @override
  void build() {}

  Future<void> initCore() async {
    final isInit = await coreController.isInit;

    final version = ref.read(versionProvider);
    if (!isInit) {
      final res = await coreController.init(version);
      commonPrint.log('init result: $res');
    } else {
      await ref.read(proxiesActionProvider.notifier).updateGroups();
    }
  }

  Future<void> startCore() {
    _lifecycleRevision++;
    return _lifecycleScheduler.run(() async {
      ref.read(coreStatusProvider.notifier).value = CoreStatus.connecting;
      try {
        await startLifecycle();
        ref.read(coreStatusProvider.notifier).value = CoreStatus.connected;
        await initCore();
      } catch (error) {
        ref.read(coreStatusProvider.notifier).value = CoreStatus.disconnected;
        globalState.showNotifier(error.toString());
      }
    });
  }

  @protected
  Future<CoreLifecycleResult> startLifecycle() {
    return coreController.start();
  }

  @protected
  Future<bool> initializeCoreForSubscription() async {
    if (await coreController.isInit) return true;
    return coreController.init(ref.read(versionProvider));
  }

  Future<void> ensureCoreForSubscription({bool Function()? isCurrent}) {
    if (!system.isDesktop) return Future.value();
    final revision = _lifecycleRevision;
    void ensureCurrent() {
      if (!ref.mounted ||
          revision != _lifecycleRevision ||
          isCurrent?.call() == false) {
        throw const CorePreparationException('core_preparation_superseded');
      }
    }

    return _lifecycleScheduler.run(() async {
      ensureCurrent();
      if (ref.read(coreStatusProvider) == CoreStatus.connected) return;
      ref.read(coreStatusProvider.notifier).value = CoreStatus.connecting;
      var stage = 'start';
      try {
        final result = await startLifecycle();
        ensureCurrent();
        if (result.outcome == CoreLifecycleOutcome.superseded) {
          throw const CorePreparationException('core_preparation_superseded');
        }
        stage = 'init';
        final initialized = await initializeCoreForSubscription().timeout(
          const Duration(seconds: 15),
        );
        ensureCurrent();
        if (!initialized) {
          throw const CorePreparationException('core_init_failed');
        }
        ref.read(coreStatusProvider.notifier).value = CoreStatus.connected;
      } catch (error, stackTrace) {
        if (ref.mounted && revision == _lifecycleRevision) {
          ref.read(coreStatusProvider.notifier).value = CoreStatus.disconnected;
        }
        if (error is CorePreparationException) rethrow;
        Error.throwWithStackTrace(
          CorePreparationException('core_${stage}_failed', cause: error),
          stackTrace,
        );
      }
    });
  }

  @protected
  Future<CoreLifecycleResult> restartLifecycle() {
    return coreController.restart();
  }

  @protected
  Future<CoreLifecycleResult> stopLifecycle() {
    return coreController.stop();
  }

  Future<void> restartCoreLifecycleOnly() {
    _lifecycleRevision++;
    return _lifecycleScheduler.run(() async {
      ref.read(coreStatusProvider.notifier).value = CoreStatus.connecting;
      try {
        await restartLifecycle();
        await initCore();
        ref.read(coreStatusProvider.notifier).value = CoreStatus.connected;
      } catch (_) {
        ref.read(coreStatusProvider.notifier).value = CoreStatus.disconnected;
        rethrow;
      }
    });
  }

  Future<void> stopCoreLifecycleOnly() {
    _lifecycleRevision++;
    return _lifecycleScheduler.run(() async {
      try {
        await stopLifecycle();
      } finally {
        ref.read(coreStatusProvider.notifier).value = CoreStatus.disconnected;
      }
    });
  }

  Future<void> restartCore() {
    _requestedRestartRevision++;
    final activeOperation = _restartOperation;
    if (activeOperation != null) {
      return activeOperation;
    }

    final operation = _runRestartWorker();
    _restartOperation = operation;
    return operation;
  }

  Future<void> _runRestartWorker() async {
    try {
      await restartCoreLifecycleOnly();

      var appliedRevision = 0;
      while (appliedRevision < _requestedRestartRevision) {
        final revision = _requestedRestartRevision;
        if (ref.read(isStartProvider) || ref.read(connectionPendingProvider)) {
          await ref
              .read(setupActionProvider.notifier)
              .setRunning(true, initialize: true, propagateErrors: true);
        } else {
          await ref
              .read(setupActionProvider.notifier)
              .applyProfile(force: true, propagateErrors: true);
        }
        appliedRevision = revision;
      }
    } catch (_) {
      ref.read(coreStatusProvider.notifier).value = CoreStatus.disconnected;
      rethrow;
    } finally {
      _restartOperation = null;
    }
  }
}

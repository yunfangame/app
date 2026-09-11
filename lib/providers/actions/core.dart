part of '../action.dart';

@Riverpod(keepAlive: true)
class CoreAction extends _$CoreAction {
  final _lifecycleScheduler = SerialTaskScheduler();
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

  Future<void> startCore() async {
    ref.read(coreStatusProvider.notifier).value = CoreStatus.connecting;
    try {
      await coreController.start();
      ref.read(coreStatusProvider.notifier).value = CoreStatus.connected;
      await initCore();
    } catch (error) {
      ref.read(coreStatusProvider.notifier).value = CoreStatus.disconnected;
      globalState.showNotifier(error.toString());
    }
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

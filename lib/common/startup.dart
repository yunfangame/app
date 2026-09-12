import 'dart:async';

final class StartupStageException implements Exception {
  final String stage;
  final Object? cause;
  final Duration? timeout;

  const StartupStageException.failure(this.stage, this.cause) : timeout = null;

  const StartupStageException.timeout(this.stage, this.timeout) : cause = null;

  bool get isTimeout => timeout != null;

  @override
  String toString() {
    final duration = timeout;
    if (duration != null) {
      return '启动阶段“$stage”超过 ${duration.inSeconds} 秒未完成';
    }
    return '启动阶段“$stage”失败：$cause';
  }
}

Future<T> runStartupStage<T>({
  required String stage,
  required Duration timeout,
  required Future<T> Function() operation,
  void Function(String stage)? onStart,
}) async {
  onStart?.call(stage);
  try {
    return await Future<T>.sync(operation).timeout(
      timeout,
      onTimeout: () => throw StartupStageException.timeout(stage, timeout),
    );
  } on StartupStageException {
    rethrow;
  } catch (error, stackTrace) {
    Error.throwWithStackTrace(
      StartupStageException.failure(stage, error),
      stackTrace,
    );
  }
}

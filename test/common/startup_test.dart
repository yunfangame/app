import 'dart:async';

import 'package:fl_clash/common/startup.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('startup stage reports progress and returns its result', () async {
    String? stage;

    final result = await runStartupStage<int>(
      stage: '读取系统信息',
      timeout: const Duration(seconds: 1),
      operation: () async => 26,
      onStart: (value) => stage = value,
    );

    expect(stage, '读取系统信息');
    expect(result, 26);
  });

  test('startup stage turns a stalled operation into a named error', () async {
    final pending = Completer<void>();

    final operation = runStartupStage<void>(
      stage: '恢复本地数据',
      timeout: const Duration(milliseconds: 10),
      operation: () => pending.future,
    );

    await expectLater(
      operation,
      throwsA(
        isA<StartupStageException>()
            .having((error) => error.stage, 'stage', '恢复本地数据')
            .having((error) => error.isTimeout, 'isTimeout', isTrue),
      ),
    );
  });

  test('startup stage keeps the failed stage and cause', () async {
    final failure = StateError('damaged preferences');

    final operation = runStartupStage<void>(
      stage: '恢复本地数据',
      timeout: const Duration(seconds: 1),
      operation: () async => throw failure,
    );

    await expectLater(
      operation,
      throwsA(
        isA<StartupStageException>()
            .having((error) => error.stage, 'stage', '恢复本地数据')
            .having((error) => error.cause, 'cause', same(failure)),
      ),
    );
  });
}

import 'dart:async';

import 'package:fl_clash/common/runtime_sampler.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'samples only while running in foreground and resumes immediately',
    (tester) async {
      var samples = 0;
      final sampler = RuntimeSampler(sample: (_) async => samples++);
      addTearDown(sampler.close);

      sampler.setForeground(false);
      sampler.setRunning(true);
      await tester.pump(const Duration(seconds: 3));
      expect(samples, 0);

      sampler.setForeground(true);
      expect(samples, 1);
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(samples, 2);

      sampler.setForeground(false);
      await tester.pump(const Duration(seconds: 10));
      expect(samples, 2);
      sampler.setForeground(true);
      expect(samples, 3);
      await tester.pump();

      sampler.setRunning(false);
      await tester.pump(const Duration(seconds: 5));
      expect(samples, 3);
      sampler.setRunning(true);
      expect(samples, 4);
      sampler.close();
      await tester.pump();
    },
  );

  testWidgets('coalesces a slow sample across pause resume and restart', (
    tester,
  ) async {
    final pending = <Completer<void>>[];
    final guards = <bool Function()>[];
    var active = 0;
    var maximumActive = 0;
    final sampler = RuntimeSampler(
      sample: (isCurrent) async {
        active++;
        if (active > maximumActive) maximumActive = active;
        guards.add(isCurrent);
        final completion = Completer<void>();
        pending.add(completion);
        await completion.future;
        active--;
      },
    );
    addTearDown(sampler.close);

    sampler.setRunning(true);
    await tester.pump(const Duration(seconds: 20));
    expect(pending, hasLength(1));
    sampler.setForeground(false);
    expect(guards.single(), isFalse);
    sampler.setForeground(true);
    sampler.setRunning(false);
    sampler.setRunning(true);
    expect(pending, hasLength(1));

    pending.first.complete();
    await tester.pump();
    expect(pending, hasLength(2));
    expect(guards.first(), isFalse);
    expect(guards.last(), isTrue);
    expect(maximumActive, 1);

    sampler.setRunning(false);
    pending.last.complete();
    await tester.pump();
    await tester.pump(const Duration(seconds: 10));
    expect(pending, hasLength(2));
    sampler.close();
  });

  testWidgets(
    'sample failure does not latch and close invalidates in-flight data',
    (tester) async {
      var calls = 0;
      var errors = 0;
      final pending = Completer<void>();
      bool Function()? guard;
      final sampler = RuntimeSampler(
        sample: (isCurrent) async {
          calls++;
          if (calls == 1) throw StateError('synthetic read failure');
          guard = isCurrent;
          await pending.future;
        },
        onError: (_, _) => errors++,
      );
      addTearDown(sampler.close);

      sampler.setRunning(true);
      await tester.pump();
      expect(errors, 1);
      await tester.pump(const Duration(seconds: 1));
      expect(calls, 2);
      expect(guard!(), isTrue);
      sampler.close();
      sampler.close();
      expect(guard!(), isFalse);
      pending.complete();
      await tester.pump();
      sampler.setRunning(true);
      sampler.setForeground(true);
      await tester.pump(const Duration(seconds: 10));
      expect(calls, 2);
    },
  );
}

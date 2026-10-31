import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:fl_clash/common/diagnostic_log.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('records ordered structured events without sensitive values', () async {
    final directory = await Directory.systemTemp.createTemp(
      'fengwo-diagnostic-test-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final log = DiagnosticLog(
      directoryLoader: () async => directory,
      clock: () => DateTime.utc(2026, 9, 3, 8, 30),
      sessionId: 'test-session',
    );

    await log.record(
      'auth.login.failed',
      fields: {
        'email': 'person@example.com',
        'token': 'very-sensitive-token',
        'url': 'https://api.example.com/login?token=secret',
        'ip': '203.0.113.20',
        'message':
            'Authorization: Bearer raw-token\nserver: edge.example.com password=two words',
      },
    );
    await log.record('connection.requested', fields: {'running': true});

    final lines = const LineSplitter()
        .convert(await log.readAll())
        .map((line) => jsonDecode(line) as Map<String, dynamic>)
        .toList();
    expect(lines, hasLength(2));
    expect(lines.first['session'], 'test-session');
    expect(lines.first['sequence'], 1);
    expect(lines.first['event'], 'auth.login.failed');
    expect(lines.last['sequence'], 2);
    expect(lines.first['fields']['email'], '<redacted-email>');
    expect(lines.first['fields']['token'], '<redacted>');
    expect(lines.first['fields']['url'], '<redacted-url>');
    expect(lines.first['fields']['ip'], '<redacted-ip>');
    final exported = await log.readAll();
    expect(exported, isNot(contains('very-sensitive-token')));
    expect(exported, isNot(contains('raw-token')));
    expect(exported, isNot(contains('edge.example.com')));
    expect(exported, isNot(contains('two words')));
  });

  test('rotates diagnostic files and retains recent events', () async {
    final directory = await Directory.systemTemp.createTemp(
      'fengwo-diagnostic-rotation-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final log = DiagnosticLog(
      directoryLoader: () async => directory,
      maxFileBytes: 170,
      retainedFileCount: 2,
      sessionId: 'rotation-session',
    );

    await log.record(
      'event.one',
      fields: {'value': List.filled(80, 'a').join()},
    );
    await log.record(
      'event.two',
      fields: {'value': List.filled(80, 'b').join()},
    );
    await log.record(
      'event.three',
      fields: {'value': List.filled(80, 'c').join()},
    );

    final content = await log.readAll();
    expect(content, isNot(contains('event.one')));
    expect(content, contains('event.two'));
    expect(content, contains('event.three'));
  });

  test('fingerprints identifiers consistently without exposing them', () {
    final first = diagnosticFingerprint(' Person@Example.com ');
    final second = diagnosticFingerprint('person@example.com');
    expect(first, second);
    expect(first, hasLength(12));
    expect(first, isNot(contains('person')));
  });

  test(
    'a single retained file rotates without growing across repeated appends',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'fengwo-log-one-file-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final log = DiagnosticLog(
        directoryLoader: () async => directory,
        maxFileBytes: 512,
        retainedFileCount: 1,
        sessionId: 'one-file',
      );
      for (var index = 0; index < 100; index++) {
        await log.record('event.normal', fields: {'index': index});
      }
      final rows = _readLines(await log.readAll());
      expect(rows.length, lessThan(5));
      expect(rows.last['fields']['index'], 99);
      expect(rows.any((row) => row['fields']['index'] == 0), isFalse);
      final files = await Directory(
        '${directory.path}/diagnostics',
      ).list().toList();
      expect(files, hasLength(1));
      expect(await File(files.single.path).length(), lessThanOrEqualTo(512));
    },
  );

  test(
    'one-file rotation replaces an oversized entry on the next append',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'fengwo-log-oversized-rotation-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final log = DiagnosticLog(
        directoryLoader: () async => directory,
        maxFileBytes: 180,
        retainedFileCount: 1,
        sessionId: 'oversized',
      );
      await log.record('event.large', fields: {'value': 'x' * 600});
      final file = File('${directory.path}/diagnostics/events.jsonl');
      expect(await file.length(), greaterThan(180));
      await log.record('event.small');
      final rows = _readLines(await log.readAll());
      expect(rows, hasLength(1));
      expect(rows.single['event'], 'event.small');
      expect(await file.length(), lessThanOrEqualTo(180));
    },
  );

  test('default limits bound a single oversized structured event', () async {
    final directory = await Directory.systemTemp.createTemp(
      'fengwo-log-default-limits-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final log = DiagnosticLog(
      directoryLoader: () async => directory,
      sessionId: 'default-limits',
    );
    await log.record(
      'core.error',
      fields: {
        for (var index = 0; index < 1000; index++) 'field$index': 'x' * 600,
      },
    );
    final rows = _readLines(await log.readAll());
    expect(rows, hasLength(1));
    expect(rows.single['fields']['fields_truncated'], isTrue);
    expect(
      rows.single['fields']['original_encoded_bytes'],
      greaterThan(log.maxPendingBytes),
    );
    final file = File('${directory.path}/diagnostics/events.jsonl');
    expect(await file.length(), lessThanOrEqualTo(log.maxFileBytes));
  });

  test(
    'bounds a normal burst and flushes retained events with overflow counts',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'fengwo-log-burst-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final log = DiagnosticLog(
        directoryLoader: () async => directory,
        maxPendingEvents: 8,
        sessionId: 'burst',
      );
      final writes = <Future<void>>[];
      for (var index = 0; index < 1000; index++) {
        writes.add(log.record('event.normal', fields: {'index': index}));
      }
      expect(writes.every((future) => identical(future, writes.first)), isTrue);
      await log.flush();
      await Future.wait(writes);
      final rows = _readLines(await log.readAll());
      final events = rows
          .where((row) => row['event'] == 'event.normal')
          .toList();
      final overflow = rows.singleWhere(
        (row) => row['event'] == 'diagnostic.buffer.overflow',
      );
      expect(events, hasLength(8));
      expect(events.first['fields']['index'], 992);
      expect(events.last['fields']['index'], 999);
      expect(overflow['fields']['dropped_normal_events'], 992);
      expect(overflow['fields']['dropped_critical_events'], 0);
      expect(overflow['fields']['first_dropped_sequence'], 1);
      expect(overflow['fields']['last_dropped_sequence'], 992);
    },
  );

  test(
    'critical errors survive a normal flood while slow storage is in flight',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'fengwo-log-slow-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final gate = Completer<void>();
      final started = Completer<void>();
      var first = true;
      final log = DiagnosticLog(
        directoryLoader: () async {
          if (first) {
            first = false;
            started.complete();
            await gate.future;
          }
          return directory;
        },
        maxPendingEvents: 4,
        sessionId: 'slow',
      );
      final initial = log.record('event.initial');
      await started.future;
      unawaited(log.record('core.crashed', fields: {'code': 'synthetic'}));
      for (var index = 0; index < 100; index++) {
        unawaited(log.record('event.normal', fields: {'index': index}));
      }
      var flushed = false;
      final flush = log.flush().then((_) => flushed = true);
      await Future<void>.delayed(Duration.zero);
      expect(flushed, isFalse);
      gate.complete();
      await flush;
      await initial;
      final rows = _readLines(await log.readAll());
      expect(rows.where((row) => row['event'] == 'core.crashed'), hasLength(1));
      expect(rows.where((row) => row['event'] == 'event.normal'), hasLength(3));
      final overflow = rows.singleWhere(
        (row) => row['event'] == 'diagnostic.buffer.overflow',
      );
      expect(overflow['fields']['dropped_normal_events'], 97);
      expect(overflow['fields']['dropped_critical_events'], 0);
    },
  );

  test(
    'critical-only flood stays bounded and reports critical loss explicitly',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'fengwo-log-critical-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final log = DiagnosticLog(
        directoryLoader: () async => directory,
        maxPendingEvents: 4,
        sessionId: 'critical',
      );
      for (var index = 0; index < 50; index++) {
        unawaited(log.record('core.error', fields: {'index': index}));
      }
      await log.flush();
      final rows = _readLines(await log.readAll());
      final errors = rows.where((row) => row['event'] == 'core.error').toList();
      expect(errors, hasLength(4));
      expect(errors.first['fields']['index'], 46);
      expect(errors.last['fields']['index'], 49);
      final overflow = rows.singleWhere(
        (row) => row['event'] == 'diagnostic.buffer.overflow',
      );
      expect(overflow['fields']['dropped_normal_events'], 0);
      expect(overflow['fields']['dropped_critical_events'], 46);
    },
  );

  test(
    'bounds encoded bytes and replaces oversized fields with safe metadata',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'fengwo-log-bytes-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final log = DiagnosticLog(
        directoryLoader: () async => directory,
        maxPendingEvents: 100,
        maxPendingBytes: 1024,
        sessionId: 'bytes',
      );
      final fields = <String, Object?>{
        for (var index = 0; index < 100; index++) 'field$index': 'x' * 40,
      };
      unawaited(log.record('event.oversized', fields: fields, critical: true));
      for (var index = 0; index < 100; index++) {
        unawaited(
          log.record(
            'event.normal',
            fields: {'index': index, 'value': 'x' * 100},
          ),
        );
      }
      await log.flush();
      final rows = _readLines(await log.readAll());
      final oversized = rows.singleWhere(
        (row) => row['event'] == 'event.oversized',
      );
      expect(oversized['fields']['fields_truncated'], isTrue);
      expect(oversized['fields']['original_encoded_bytes'], greaterThan(1024));
      final events = rows.where(
        (row) => row['event'] != 'diagnostic.buffer.overflow',
      );
      expect(
        events.fold<int>(
          0,
          (sum, row) => sum + utf8.encode('${jsonEncode(row)}\n').length,
        ),
        lessThanOrEqualTo(1024),
      );
    },
  );

  test(
    'batches disk operations and retries flush after a write failure',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'fengwo-log-retry-',
      );
      addTearDown(() => directory.delete(recursive: true));
      var fail = true;
      var directoryReads = 0;
      final log = DiagnosticLog(
        directoryLoader: () async {
          directoryReads++;
          if (fail) {
            throw const FileSystemException('synthetic storage failure');
          }
          return directory;
        },
        sessionId: 'retry',
      );
      await log.record('core.error');
      fail = false;
      final afterFailure = directoryReads;
      for (var index = 0; index < 100; index++) {
        unawaited(log.record('event.normal', fields: {'index': index}));
      }
      await log.flush();
      expect(directoryReads - afterFailure, lessThan(10));
      final rows = _readLines(await log.readAll());
      expect(
        rows.where((row) => row['event'] == 'event.normal'),
        hasLength(100),
      );
      final overflow = rows.singleWhere(
        (row) => row['event'] == 'diagnostic.buffer.overflow',
      );
      expect(overflow['fields']['write_failures'], 1);
      expect(overflow['fields']['unconfirmed_write_events'], 1);
      expect(overflow['fields']['dropped_critical_events'], 0);
    },
  );

  test(
    'flush has a finite generation while later events keep arriving',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'fengwo-log-finite-flush-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final gates = List.generate(3, (_) => Completer<void>());
      final starts = List.generate(3, (_) => Completer<void>());
      var directoryReads = 0;
      final log = DiagnosticLog(
        directoryLoader: () async {
          final index = directoryReads++;
          if (index < gates.length) {
            starts[index].complete();
            await gates[index].future;
          }
          return directory;
        },
        maxPendingEvents: 4,
        sessionId: 'finite-flush',
      );
      unawaited(log.record('event.initial'));
      await starts.first.future;
      unawaited(log.record('event.before_flush', critical: true));
      final flush = log.flush();
      expect(identical(log.flush(), flush), isTrue);
      gates.first.complete();
      await starts[1].future;
      for (var index = 0; index < 100; index++) {
        unawaited(log.record('event.after_flush', fields: {'index': index}));
      }
      final producer = Timer.periodic(const Duration(milliseconds: 1), (_) {
        unawaited(log.record('event.producer'));
      });
      try {
        gates[1].complete();
        await flush.timeout(const Duration(seconds: 2));
        await starts[2].future;
        expect(gates[2].isCompleted, isFalse);
        final file = File('${directory.path}/diagnostics/events.jsonl');
        final content = await file.readAsString();
        expect(content, contains('event.before_flush'));
        expect(content, isNot(contains('event.after_flush')));
      } finally {
        producer.cancel();
        for (final gate in gates) {
          if (!gate.isCompleted) gate.complete();
        }
        await log.flush();
      }
      final rows = _readLines(await log.readAll());
      expect(
        rows.where((row) => row['event'] == 'diagnostic.buffer.overflow'),
        isNotEmpty,
      );
    },
  );

  test(
    'readAll coalesces and completes without chasing future producer writes',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'fengwo-log-read-barrier-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final firstWrite = Completer<void>();
      final firstStarted = Completer<void>();
      final laterWrite = Completer<void>();
      final laterStarted = Completer<void>();
      var directoryReads = 0;
      final log = DiagnosticLog(
        directoryLoader: () async {
          directoryReads++;
          if (directoryReads == 1) {
            firstStarted.complete();
            await firstWrite.future;
          } else if (directoryReads == 3) {
            laterStarted.complete();
            await laterWrite.future;
          }
          return directory;
        },
        maxPendingEvents: 4,
        sessionId: 'read-barrier',
      );
      unawaited(log.record('event.initial'));
      await firstStarted.future;
      final export = log.readAll();
      expect(identical(log.readAll(), export), isTrue);
      for (var index = 0; index < 100; index++) {
        unawaited(log.record('event.after_export', fields: {'index': index}));
      }
      final producer = Timer.periodic(const Duration(milliseconds: 1), (_) {
        unawaited(log.record('event.producer'));
      });
      try {
        firstWrite.complete();
        final exported = await export.timeout(const Duration(seconds: 2));
        expect(exported, contains('event.initial'));
        expect(exported, isNot(contains('event.after_export')));
        await laterStarted.future;
        expect(laterWrite.isCompleted, isFalse);
      } finally {
        producer.cancel();
        if (!firstWrite.isCompleted) firstWrite.complete();
        if (!laterWrite.isCompleted) laterWrite.complete();
        await log.flush();
      }
    },
  );
}

List<Map<String, dynamic>> _readLines(String value) => const LineSplitter()
    .convert(value)
    .map((line) => jsonDecode(line) as Map<String, dynamic>)
    .toList();

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
}

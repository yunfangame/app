import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

typedef DiagnosticDirectoryLoader = Future<Directory> Function();
typedef DiagnosticClock = DateTime Function();

class DiagnosticLog {
  final DiagnosticDirectoryLoader _directoryLoader;
  final DiagnosticClock _clock;
  final int maxFileBytes;
  final int retainedFileCount;
  final String sessionId;
  Future<void> _pendingWrite = Future.value();
  int _sequence = 0;

  DiagnosticLog({
    DiagnosticDirectoryLoader? directoryLoader,
    DiagnosticClock? clock,
    this.maxFileBytes = 1024 * 1024,
    this.retainedFileCount = 3,
    String? sessionId,
  }) : _directoryLoader = directoryLoader ?? getApplicationSupportDirectory,
       _clock = clock ?? DateTime.now,
       sessionId = sessionId ?? _newSessionId() {
    assert(maxFileBytes > 0);
    assert(retainedFileCount > 0);
  }

  Future<void> record(String event, {Map<String, Object?> fields = const {}}) {
    final entry = <String, Object?>{
      'timestamp': _clock().toUtc().toIso8601String(),
      'session': sessionId,
      'sequence': ++_sequence,
      'event': normalizeDiagnosticEventName(event),
      'fields': sanitizeDiagnosticFields(fields),
    };
    final line = '${jsonEncode(entry)}\n';
    final operation = _pendingWrite
        .catchError((_) {})
        .then((_) => _append(line));
    _pendingWrite = operation.catchError((_) {});
    return _pendingWrite;
  }

  Future<void> flush() => _pendingWrite;

  Future<String> readAll() async {
    await flush();
    final directory = await _diagnosticDirectory();
    final buffer = StringBuffer();
    for (var index = retainedFileCount - 1; index >= 0; index--) {
      final file = File(_filePath(directory, index));
      if (!await file.exists()) continue;
      final content = await file.readAsString();
      if (content.isEmpty) continue;
      buffer.write(content);
      if (!content.endsWith('\n')) buffer.writeln();
    }
    return buffer.toString();
  }

  Future<void> _append(String line) async {
    final directory = await _diagnosticDirectory();
    final currentFile = File(_filePath(directory, 0));
    final nextBytes = utf8.encode(line).length;
    if (await currentFile.exists() &&
        await currentFile.length() + nextBytes > maxFileBytes) {
      await _rotate(directory);
    }
    await currentFile.writeAsString(line, mode: FileMode.append, flush: true);
  }

  Future<Directory> _diagnosticDirectory() async {
    final root = await _directoryLoader();
    final directory = Directory(path.join(root.path, 'diagnostics'));
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }
    return directory;
  }

  Future<void> _rotate(Directory directory) async {
    for (var index = retainedFileCount - 1; index >= 1; index--) {
      final target = File(_filePath(directory, index));
      if (await target.exists()) await target.delete();
      final source = File(_filePath(directory, index - 1));
      if (await source.exists()) await source.rename(target.path);
    }
  }

  String _filePath(Directory directory, int index) {
    final suffix = index == 0 ? '' : '.$index';
    return path.join(directory.path, 'events.jsonl$suffix');
  }
}

String diagnosticFingerprint(String value) {
  final normalized = value.trim().toLowerCase();
  if (normalized.isEmpty) return '';
  return sha256.convert(utf8.encode(normalized)).toString().substring(0, 12);
}

String sanitizeDiagnosticText(String value, {int? maxLength = 2048}) {
  var sanitized = value;
  final home = Platform.environment['HOME'];
  if (home != null && home.isNotEmpty) {
    sanitized = sanitized.replaceAll(home, '<home>');
  }
  sanitized = sanitized
      .replaceAll(
        RegExp(r'''https?://[^\s\]\[\)\("'<>]+''', caseSensitive: false),
        '<redacted-url>',
      )
      .replaceAll(
        RegExp(
          r'\b[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}\b',
          caseSensitive: false,
        ),
        '<redacted-email>',
      )
      .replaceAll(
        RegExp(r'(?<![\d.])(?:\d{1,3}\.){3}\d{1,3}(?![\d.])'),
        '<redacted-ip>',
      )
      .replaceAll(
        RegExp(
          r'\b(?:[0-9a-f]{1,4}:){2,}[0-9a-f:]{0,39}\b',
          caseSensitive: false,
        ),
        '<redacted-ip>',
      )
      .replaceAll(
        RegExp(
          r'\b(?:[a-z0-9-]+\.)+[a-z]{2,}(?::\d{1,5})?\b',
          caseSensitive: false,
        ),
        '<redacted-host>',
      )
      .replaceAll(
        RegExp(r'C:\\Users\\[^\\\s]+', caseSensitive: false),
        r'C:\Users\<user>',
      )
      .replaceAll(
        RegExp(r'\bauthorization\s*[:=]\s*[^\r\n,;]+', caseSensitive: false),
        'authorization=<redacted>',
      )
      .replaceAll(
        RegExp(r'\bbearer\s+[^\s,;]+', caseSensitive: false),
        'bearer <redacted>',
      )
      .replaceAll(
        RegExp(
          r'\b(token|password|passwd|secret|auth_data|subscribe_url)\s*[:=]\s*[^\r\n,;]+',
          caseSensitive: false,
        ),
        r'$1=<redacted>',
      )
      .replaceAll(
        RegExp(
          r'\b(server|host|sni)\s*[:=]\s*[^\r\n,;]+',
          caseSensitive: false,
        ),
        r'$1=<redacted>',
      );
  if (maxLength == null || sanitized.length <= maxLength) return sanitized;
  return '${sanitized.substring(0, maxLength)}<truncated>';
}

String normalizeDiagnosticEventName(String value) {
  final normalized = value.trim().toLowerCase().replaceAll(
    RegExp(r'[^a-z0-9._-]+'),
    '_',
  );
  if (normalized.isEmpty) return 'unknown';
  return normalized.length <= 80 ? normalized : normalized.substring(0, 80);
}

Map<String, Object?> sanitizeDiagnosticFields(Map<String, Object?> fields) {
  return fields.map((key, value) {
    final normalizedKey = key.toLowerCase().replaceAll('-', '_');
    const blockedKeys = {
      'password',
      'passwd',
      'token',
      'secret',
      'authorization',
      'auth_data',
      'subscribe_url',
      'subscription',
      'profile',
      'profile_content',
      'node_address',
      'server',
    };
    final blocked =
        blockedKeys.contains(normalizedKey) ||
        normalizedKey.endsWith('_password') ||
        normalizedKey.endsWith('_token') ||
        normalizedKey.endsWith('_secret');
    return MapEntry(
      sanitizeDiagnosticText(key),
      blocked ? '<redacted>' : _sanitizeValue(value),
    );
  });
}

Object? _sanitizeValue(Object? value) {
  return switch (value) {
    null || bool() || int() || double() => value,
    String() => sanitizeDiagnosticText(value),
    Iterable() => value.map(_sanitizeValue).toList(growable: false),
    Map() => sanitizeDiagnosticFields(
      value.map((key, item) => MapEntry('$key', item)),
    ),
    _ => sanitizeDiagnosticText('$value'),
  };
}

String _newSessionId() {
  final random = Random.secure();
  return List.generate(
    8,
    (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
  ).join();
}

final diagnosticLog = DiagnosticLog();

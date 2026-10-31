import 'dart:async';
import 'dart:collection';
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
  final int maxPendingEvents;
  final int maxPendingBytes;
  final String sessionId;
  final _pending = Queue<_DiagnosticEntry>();
  Completer<void>? _activeCompletion;
  Completer<void>? _pendingCompletion;
  Completer<String>? _readCompletion;
  bool _drainScheduled = false;
  bool _reading = false;
  int _pendingBytes = 0;
  _DiagnosticOverflow _overflow = _DiagnosticOverflow();
  int _sequence = 0;

  DiagnosticLog({
    DiagnosticDirectoryLoader? directoryLoader,
    DiagnosticClock? clock,
    this.maxFileBytes = 1024 * 1024,
    this.retainedFileCount = 3,
    this.maxPendingEvents = 256,
    this.maxPendingBytes = 256 * 1024,
    String? sessionId,
  }) : _directoryLoader = directoryLoader ?? getApplicationSupportDirectory,
       _clock = clock ?? DateTime.now,
       sessionId = sessionId ?? _newSessionId() {
    assert(maxFileBytes > 0);
    assert(retainedFileCount > 0);
    assert(maxPendingEvents > 0);
    assert(maxPendingBytes >= 512);
  }

  Future<void> record(
    String event, {
    Map<String, Object?> fields = const {},
    bool critical = false,
  }) {
    final eventName = normalizeDiagnosticEventName(event);
    final sequence = ++_sequence;
    final entry = <String, Object?>{
      'timestamp': _clock().toUtc().toIso8601String(),
      'session': sessionId,
      'sequence': sequence,
      'event': eventName,
      'fields': sanitizeDiagnosticFields(fields),
    };
    var line = '${jsonEncode(entry)}\n';
    var bytes = utf8.encode(line).length;
    if (bytes > maxPendingBytes) {
      entry['fields'] = {
        'fields_truncated': true,
        'original_encoded_bytes': bytes,
      };
      line = '${jsonEncode(entry)}\n';
      bytes = utf8.encode(line).length;
    }
    final queued = _DiagnosticEntry(
      line: line,
      bytes: bytes,
      sequence: sequence,
      critical: critical || _isCriticalEvent(eventName),
    );
    if (bytes > maxPendingBytes) {
      _overflow.add(queued);
      return _ensureDrain();
    }
    while (_pending.length >= maxPendingEvents ||
        _pendingBytes + bytes > maxPendingBytes) {
      _DiagnosticEntry? oldestNormal;
      for (final item in _pending) {
        if (!item.critical) {
          oldestNormal = item;
          break;
        }
      }
      if (oldestNormal == null && !queued.critical) {
        _overflow.add(queued);
        return _ensureDrain();
      }
      final discarded = oldestNormal ?? _pending.first;
      _pending.remove(discarded);
      _pendingBytes -= discarded.bytes;
      _overflow.add(discarded);
    }
    _pending.addLast(queued);
    _pendingBytes += bytes;
    return _ensureDrain();
  }

  Future<void> flush() => _ensureDrain();

  bool _isCriticalEvent(String event) => RegExp(
    r'(^|[._-])(failed|failure|error|crash|crashed|rejected|denied|timeout)($|[._-])',
  ).hasMatch(event);

  Future<void> _ensureDrain() {
    if (_pending.isEmpty && _overflow.isEmpty) {
      return _activeCompletion?.future ?? Future.value();
    }
    final completion = _pendingCompletion ??= Completer<void>();
    _scheduleDrain();
    return completion.future;
  }

  void _scheduleDrain() {
    if (_activeCompletion != null ||
        _pendingCompletion == null ||
        _drainScheduled ||
        _reading) {
      return;
    }
    _drainScheduled = true;
    scheduleMicrotask(_drain);
  }

  Future<void> _drain() async {
    _drainScheduled = false;
    if (_reading || _activeCompletion != null) return;
    final completion = _pendingCompletion;
    if (completion == null) return;
    _pendingCompletion = null;
    _activeCompletion = completion;
    final snapshot = _pending.toList(growable: false);
    _pending.clear();
    _pendingBytes = 0;
    final overflow = _overflow;
    _overflow = _DiagnosticOverflow();
    final summary = overflow.isEmpty
        ? null
        : '${jsonEncode({'timestamp': _clock().toUtc().toIso8601String(), 'session': sessionId, 'sequence': ++_sequence, 'event': 'diagnostic.buffer.overflow', 'fields': overflow.toJson()})}\n';
    var confirmed = 0;
    try {
      while (confirmed < snapshot.length) {
        final batch = <String>[];
        var bytes = 0;
        var index = confirmed;
        while (index < snapshot.length && batch.length < 64) {
          final next = snapshot[index];
          if (batch.isNotEmpty && bytes + next.bytes > 64 * 1024) break;
          batch.add(next.line);
          bytes += next.bytes;
          index++;
        }
        await _appendBatch(batch);
        confirmed = index;
      }
      if (summary != null) await _appendBatch([summary]);
    } catch (_) {
      _overflow.merge(overflow);
      _overflow.unconfirmedWriteEvents += snapshot.length - confirmed;
      _overflow.writeFailures++;
    } finally {
      _activeCompletion = null;
      completion.complete();
      _scheduleDrain();
    }
  }

  Future<String> readAll() {
    final active = _readCompletion;
    if (active != null) return active.future;
    final completion = Completer<String>();
    _readCompletion = completion;
    unawaited(_readSnapshot(completion));
    return completion.future;
  }

  Future<void> _readSnapshot(Completer<String> completion) async {
    try {
      await flush();
      _reading = true;
      await _activeCompletion?.future;
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
      completion.complete(buffer.toString());
    } catch (error, stackTrace) {
      completion.completeError(error, stackTrace);
    } finally {
      _reading = false;
      _readCompletion = null;
      _scheduleDrain();
    }
  }

  Future<void> _appendBatch(Iterable<String> lines) async {
    final directory = await _diagnosticDirectory();
    final currentFile = File(_filePath(directory, 0));
    var currentBytes = await currentFile.exists()
        ? await currentFile.length()
        : 0;
    final chunk = StringBuffer();
    var chunkBytes = 0;
    Future<void> writeChunk() async {
      if (chunk.isEmpty) return;
      await currentFile.writeAsString(
        chunk.toString(),
        mode: FileMode.append,
        flush: true,
      );
      currentBytes += chunkBytes;
      chunk.clear();
      chunkBytes = 0;
    }

    for (final line in lines) {
      final lineBytes = utf8.encode(line).length;
      if (currentBytes + chunkBytes > 0 &&
          currentBytes + chunkBytes + lineBytes > maxFileBytes) {
        await writeChunk();
        await _rotate(directory);
        currentBytes = 0;
      }
      chunk.write(line);
      chunkBytes += lineBytes;
    }
    await writeChunk();
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
    final current = File(_filePath(directory, 0));
    if (await current.exists()) await current.delete();
  }

  String _filePath(Directory directory, int index) {
    final suffix = index == 0 ? '' : '.$index';
    return path.join(directory.path, 'events.jsonl$suffix');
  }
}

class _DiagnosticEntry {
  const _DiagnosticEntry({
    required this.line,
    required this.bytes,
    required this.sequence,
    required this.critical,
  });

  final String line;
  final int bytes;
  final int sequence;
  final bool critical;
}

class _DiagnosticOverflow {
  int normal = 0;
  int critical = 0;
  int writeFailures = 0;
  int unconfirmedWriteEvents = 0;
  int? firstSequence;
  int? lastSequence;

  bool get isEmpty =>
      normal == 0 &&
      critical == 0 &&
      writeFailures == 0 &&
      unconfirmedWriteEvents == 0;

  void add(_DiagnosticEntry entry) {
    if (entry.critical) {
      critical++;
    } else {
      normal++;
    }
    firstSequence = min(firstSequence ?? entry.sequence, entry.sequence);
    lastSequence = max(lastSequence ?? entry.sequence, entry.sequence);
  }

  void merge(_DiagnosticOverflow other) {
    normal += other.normal;
    critical += other.critical;
    writeFailures += other.writeFailures;
    unconfirmedWriteEvents += other.unconfirmedWriteEvents;
    if (other.firstSequence != null) {
      firstSequence = min(
        firstSequence ?? other.firstSequence!,
        other.firstSequence!,
      );
      lastSequence = max(
        lastSequence ?? other.lastSequence!,
        other.lastSequence!,
      );
    }
  }

  Map<String, Object?> toJson() => {
    'dropped_normal_events': normal,
    'dropped_critical_events': critical,
    'write_failures': writeFailures,
    'unconfirmed_write_events': unconfirmedWriteEvents,
    'first_dropped_sequence': firstSequence,
    'last_dropped_sequence': lastSequence,
  };
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

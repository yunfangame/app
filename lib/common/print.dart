import 'dart:async';
import 'dart:convert';

import 'package:fl_clash/common/diagnostic_log.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/app.dart';
import 'package:fl_clash/state.dart';
import 'package:flutter/material.dart';

class CommonPrint {
  static CommonPrint? _instance;

  CommonPrint._internal();

  factory CommonPrint() {
    _instance ??= CommonPrint._internal();
    return _instance!;
  }

  void log(String? text, {LogLevel logLevel = LogLevel.info}) {
    final payload = '[APP] $text';
    debugPrint(payload);
    if (!globalState.isAttach) {
      return;
    }
    globalState.container
        .read(logsProvider.notifier)
        .add(Log.app(payload).copyWith(logLevel: logLevel));
  }

  void event(String name, {Map<String, Object?> fields = const {}}) {
    final eventName = normalizeDiagnosticEventName(name);
    final safeFields = sanitizeDiagnosticFields(fields);
    final payload = '[DIAG] $eventName ${jsonEncode(safeFields)}';
    debugPrint(payload);
    unawaited(diagnosticLog.record(eventName, fields: fields));
    if (!globalState.isAttach) return;
    globalState.container.read(logsProvider.notifier).add(Log.app(payload));
  }

  Future<void> flushDiagnosticEvents() => diagnosticLog.flush();

  Future<String> readDiagnosticEvents() => diagnosticLog.readAll();
}

final commonPrint = CommonPrint();

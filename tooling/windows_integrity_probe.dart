import 'dart:convert';
import 'dart:io';

import 'package:fl_clash/common/windows_integrity.dart';

void main() {
  try {
    final snapshot = verifyWindowsStartupIntegrity();
    stdout.writeln(
      jsonEncode({
        'status': snapshot == null ? 'skipped' : 'allowed',
        'startup_would_continue': true,
        if (snapshot != null) ...snapshot.diagnosticFields,
      }),
    );
  } on WindowsIntegrityException catch (error) {
    stdout.writeln(
      jsonEncode({
        'status': 'blocked',
        'startup_would_continue': false,
        ...error.diagnosticFields,
      }),
    );
    exitCode = error.isRestricted ? 23 : 24;
  } catch (error) {
    stdout.writeln(
      jsonEncode({
        'status': 'unexpected_failure',
        'error_type': error.runtimeType.toString(),
        'startup_would_continue': false,
      }),
    );
    exitCode = 25;
  }
}

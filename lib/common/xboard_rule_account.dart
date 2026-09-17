import 'dart:convert';

import 'package:crypto/crypto.dart';

String? xboardRuleAccountKeyForEmail(String? email) {
  final normalized = email?.trim().toLowerCase();
  if (normalized == null || normalized.isEmpty) return null;
  return sha256
      .convert(utf8.encode('fengwo.local-account-rules.v1\u0000$normalized'))
      .toString();
}

String? normalizeXboardRuleAccountKey(Object? value) {
  if (value is! String || value.length != 64) return null;
  return RegExp(r'^[a-f0-9]{64}$').hasMatch(value) ? value : null;
}

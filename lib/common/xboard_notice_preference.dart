import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class XboardNoticePreferenceStore {
  XboardNoticePreferenceStore({
    Future<SharedPreferences> Function()? preferencesLoader,
  }) : _preferencesLoader = preferencesLoader ?? SharedPreferences.getInstance;

  static const _keyPrefix = 'xboard.notice.suppressed_date.';

  final Future<SharedPreferences> Function() _preferencesLoader;

  Future<bool> isSuppressedToday(String accountId, {DateTime? now}) async {
    final preferences = await _preferencesLoader();
    return preferences.getString(_key(accountId)) == _dateKey(now);
  }

  Future<void> setSuppressedToday(
    String accountId,
    bool suppressed, {
    DateTime? now,
  }) async {
    final preferences = await _preferencesLoader();
    final key = _key(accountId);
    if (suppressed) {
      await preferences.setString(key, _dateKey(now));
      return;
    }
    await preferences.remove(key);
  }

  String _key(String accountId) {
    final encoded = base64Url.encode(
      utf8.encode(accountId.trim().toLowerCase()),
    );
    return '$_keyPrefix$encoded';
  }

  String _dateKey(DateTime? value) {
    final date = (value ?? DateTime.now()).toLocal();
    return '${date.year.toString().padLeft(4, '0')}-'
        '${date.month.toString().padLeft(2, '0')}-'
        '${date.day.toString().padLeft(2, '0')}';
  }
}

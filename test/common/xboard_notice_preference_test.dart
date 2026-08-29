import 'package:fl_clash/common/xboard_notice_preference.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test(
    'suppresses reminders per account for the current local day only',
    () async {
      final store = XboardNoticePreferenceStore();
      final today = DateTime(2026, 8, 29, 23, 59);

      await store.setSuppressedToday('api|first@example.com', true, now: today);

      expect(
        await store.isSuppressedToday('api|first@example.com', now: today),
        isTrue,
      );
      expect(
        await store.isSuppressedToday('api|second@example.com', now: today),
        isFalse,
      );
      expect(
        await store.isSuppressedToday(
          'api|first@example.com',
          now: DateTime(2026, 8, 30),
        ),
        isFalse,
      );
    },
  );

  test('clears a current-day suppression', () async {
    final store = XboardNoticePreferenceStore();
    final now = DateTime(2026, 8, 29);

    await store.setSuppressedToday('api|member@example.com', true, now: now);
    await store.setSuppressedToday('api|member@example.com', false, now: now);

    expect(
      await store.isSuppressedToday('api|member@example.com', now: now),
      isFalse,
    );
  });
}

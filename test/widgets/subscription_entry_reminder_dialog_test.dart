import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/common/subscription_entry_reminder.dart';
import 'package:fl_clash/l10n/l10n.dart';
import 'package:fl_clash/widgets/subscription_entry_reminder_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime(2026, 10, 9, 12);

  testWidgets(
    'shows remaining traffic, three-day expiry and reset days and hours',
    (tester) async {
      await _openReminder(
        tester,
        subscription: _subscription(
          now,
          expiresIn: const Duration(days: 2),
          resetIn: const Duration(days: 1, hours: 4),
        ),
        now: now,
        evaluation: const SubscriptionEntryReminderEvaluation(
          lowTraffic: false,
          expiringSoon: true,
        ),
      );

      expect(find.text('套餐提醒'), findsOneWidget);
      expect(find.text('剩余流量：9.0 GB'), findsOneWidget);
      expect(find.text('剩余流量已不足 10 GB。'), findsNothing);
      expect(find.textContaining('剩余不足 3 天'), findsOneWidget);
      expect(find.text('距离下次流量重置还有 1 天 4 小时'), findsOneWidget);
      expect(find.text('知道了'), findsOneWidget);
      expect(find.text('不再提醒'), findsOneWidget);
      expect(find.byType(Checkbox), findsNothing);
      expect(find.text('重置流量'), findsNothing);
      expect(find.text('续费'), findsNothing);
      expect(find.text('升级套餐'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('monthly low traffic reminder does not claim expiry is near', (
    tester,
  ) async {
    await _openReminder(
      tester,
      subscription: _subscription(now),
      now: now,
      evaluation: const SubscriptionEntryReminderEvaluation(
        lowTraffic: true,
        expiringSoon: false,
      ),
    );

    expect(find.text('距离下次流量重置还有 8 天 4 小时'), findsOneWidget);
    expect(find.text('剩余流量已不足 10 GB。'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('subscription-entry-reminder-expiry')),
      findsNothing,
    );
    final dialog = find.byType(SubscriptionEntryReminderDialog);
    expect(
      find.descendant(of: dialog, matching: find.byType(TextButton)),
      findsOneWidget,
    );
    expect(
      find.descendant(of: dialog, matching: find.byType(FilledButton)),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'unlimited plan shows precise low traffic without reset or expiry',
    (tester) async {
      await _openReminder(
        tester,
        subscription: _subscription(now, unlimited: true, remainingGb: 0.75),
        now: now,
        evaluation: const SubscriptionEntryReminderEvaluation(
          lowTraffic: true,
          expiringSoon: false,
        ),
      );

      expect(find.text('剩余流量：0.75 GB'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('subscription-entry-reminder-expiry')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('subscription-entry-reminder-reset')),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('expiry-only reminder shows current remaining traffic', (
    tester,
  ) async {
    await _openReminder(
      tester,
      subscription: _subscription(
        now,
        expiresIn: const Duration(days: 2),
        remainingGb: 20,
      ),
      now: now,
      evaluation: const SubscriptionEntryReminderEvaluation(
        lowTraffic: false,
        expiringSoon: true,
      ),
    );

    expect(find.text('剩余流量：20.0 GB'), findsOneWidget);
    expect(find.text('剩余流量已不足 10 GB。'), findsNothing);
    expect(find.textContaining('剩余不足 3 天'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  final trafficBoundaryCases = <({double remaining, String displayed})>[
    (remaining: 10 - 1 / bytesPerGigabyte, displayed: '9.9'),
    (remaining: 1 / bytesPerGigabyte, displayed: '<0.01'),
  ];
  for (final value in trafficBoundaryCases) {
    testWidgets(
      'remaining traffic stays below the boundary: ${value.displayed}',
      (tester) async {
        await _openReminder(
          tester,
          subscription: _subscription(
            now,
            unlimited: true,
            remainingGb: value.remaining,
          ),
          now: now,
          evaluation: const SubscriptionEntryReminderEvaluation(
            lowTraffic: true,
            expiringSoon: false,
          ),
        );

        expect(find.text('剩余流量：${value.displayed} GB'), findsOneWidget);
        expect(find.text('剩余流量已不足 10 GB。'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }

  final invalidResetEpochSeconds = <String, int>{
    'out-of-range epoch': 9223372036854775,
    'negative epoch': -1,
    'later than expiry':
        now.add(const Duration(days: 8)).millisecondsSinceEpoch ~/ 1000,
  };
  for (final entry in invalidResetEpochSeconds.entries) {
    testWidgets('expiry reminder omits invalid reset: ${entry.key}', (
      tester,
    ) async {
      await _openReminder(
        tester,
        subscription: _subscription(
          now,
          expiresIn: const Duration(days: 2),
          remainingGb: 20,
          nextResetEpochSeconds: entry.value,
        ),
        now: now,
        evaluation: const SubscriptionEntryReminderEvaluation(
          lowTraffic: false,
          expiringSoon: true,
        ),
      );

      expect(
        find.byKey(const ValueKey('subscription-entry-reminder-expiry')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('subscription-entry-reminder-reset')),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'Got it closes only this reminder without suppressing later reminders',
    (tester) async {
      SubscriptionEntryReminderChoice? choice;
      await _openReminder(
        tester,
        subscription: _subscription(now),
        now: now,
        evaluation: const SubscriptionEntryReminderEvaluation(
          lowTraffic: true,
          expiringSoon: false,
        ),
        onClosed: (value) => choice = value,
      );

      await tester.tap(
        find.byKey(const ValueKey('subscription-entry-reminder-close')),
      );
      await tester.pumpAndSettle();

      expect(choice, isNotNull);
      expect(choice!.dontRemind, isFalse);
      expect(find.byType(SubscriptionEntryReminderDialog), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Do not remind closes directly with account suppression choice', (
    tester,
  ) async {
    SubscriptionEntryReminderChoice? choice;
    await _openReminder(
      tester,
      subscription: _subscription(now),
      now: now,
      evaluation: const SubscriptionEntryReminderEvaluation(
        lowTraffic: true,
        expiringSoon: false,
      ),
      onClosed: (value) => choice = value,
    );

    expect(find.text('“不再提醒”仅对当前账号在本客户端生效。'), findsOneWidget);
    await tester.tap(
      find.byKey(const ValueKey('subscription-entry-reminder-dont-remind')),
    );
    await tester.pumpAndSettle();

    expect(choice, isNotNull);
    expect(choice!.dontRemind, isTrue);
    expect(find.byType(SubscriptionEntryReminderDialog), findsNothing);
    expect(tester.takeException(), isNull);
  });

  for (final locale in const [
    Locale('zh', 'CN'),
    Locale('en'),
    Locale('ja'),
    Locale('ru'),
  ]) {
    for (final brightness in Brightness.values) {
      testWidgets('fits narrow $locale $brightness with enlarged text', (
        tester,
      ) async {
        tester.view.physicalSize = const Size(320, 640);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        SubscriptionEntryReminderChoice? choice;
        await _openReminder(
          tester,
          subscription: _subscription(
            now,
            expiresIn: const Duration(days: 2),
            resetIn: const Duration(days: 1, hours: 4),
          ),
          now: now,
          evaluation: const SubscriptionEntryReminderEvaluation(
            lowTraffic: false,
            expiringSoon: true,
          ),
          locale: locale,
          brightness: brightness,
          textScale: 1.4,
          onClosed: (value) => choice = value,
        );

        expect(tester.takeException(), isNull);
        await tester.ensureVisible(
          find.byKey(const ValueKey('subscription-entry-reminder-close')),
        );
        await tester.tap(
          find.byKey(const ValueKey('subscription-entry-reminder-close')),
        );
        await tester.pumpAndSettle();

        expect(choice?.dontRemind, isFalse);
        expect(find.byType(SubscriptionEntryReminderDialog), findsNothing);
        expect(tester.takeException(), isNull);
      });
    }
  }
}

Future<void> _openReminder(
  WidgetTester tester, {
  required XboardSubscriptionData subscription,
  required SubscriptionEntryReminderEvaluation evaluation,
  required DateTime now,
  Locale locale = const Locale('zh', 'CN'),
  Brightness brightness = Brightness.light,
  double textScale = 1,
  ValueChanged<SubscriptionEntryReminderChoice?>? onClosed,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      locale: locale,
      theme: ThemeData(
        brightness: brightness,
        colorSchemeSeed: const Color(0xFF075FEA),
      ),
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.delegate.supportedLocales,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            key: const ValueKey('open-subscription-entry-reminder'),
            onPressed: () async {
              final choice = await showDialog<SubscriptionEntryReminderChoice>(
                context: context,
                barrierDismissible: false,
                builder: (context) => SubscriptionEntryReminderDialog(
                  subscription: subscription,
                  evaluation: evaluation,
                  now: now,
                ),
              );
              onClosed?.call(choice);
            },
            child: const Text('Open'),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(
    find.byKey(const ValueKey('open-subscription-entry-reminder')),
  );
  await tester.pumpAndSettle();
}

XboardSubscriptionData _subscription(
  DateTime now, {
  bool unlimited = false,
  double remainingGb = 9,
  Duration expiresIn = const Duration(days: 20),
  Duration resetIn = const Duration(days: 8, hours: 4),
  int? nextResetEpochSeconds,
}) {
  return XboardSubscriptionData(
    endpoint: Uri.parse('https://api.example.invalid'),
    subscribeUrl: null,
    uploadBytes: bytesPerGigabyte,
    downloadBytes: 0,
    transferEnableBytes:
        bytesPerGigabyte + (remainingGb * bytesPerGigabyte).round(),
    expiredAtEpochSeconds: unlimited
        ? null
        : now.add(expiresIn).millisecondsSinceEpoch ~/ 1000,
    nextResetAtEpochSeconds:
        nextResetEpochSeconds ??
        now.add(resetIn).millisecondsSinceEpoch ~/ 1000,
    planId: 1,
    rawData: const {},
  );
}

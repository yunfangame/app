import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/l10n/l10n.dart';
import 'package:fl_clash/widgets/windows_tun_progress.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'TUN progress blocks dismissal and can close without removing another dialog',
    (tester) async {
      late VoidCallback close;
      late BuildContext pageContext;
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('zh', 'CN'),
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.delegate.supportedLocales,
          home: Scaffold(
            body: Builder(
              builder: (context) {
                pageContext = context;
                return TextButton(
                  onPressed: () => close = showWindowsTunProgress(context),
                  child: const Text('start'),
                );
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('start'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(
        find.text(pageContext.appLocalizations.tunStarting),
        findsOneWidget,
      );
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      await tester.tapAt(const Offset(5, 5));
      await tester.pump();
      await tester.binding.handlePopRoute();
      await tester.pump();
      expect(find.byType(WindowsTunProgressDialog), findsOneWidget);
      showDialog<void>(
        context: pageContext,
        builder: (_) => const AlertDialog(content: Text('failure')),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      close();
      close();
      await tester.pumpAndSettle();
      expect(find.byType(WindowsTunProgressDialog), findsNothing);
      expect(find.text('failure'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}

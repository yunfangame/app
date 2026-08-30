import 'package:fl_clash/common/scroll.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Android scroll behavior disables page stretching', (
    tester,
  ) async {
    late BuildContext testContext;
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(platform: TargetPlatform.android),
        home: Builder(
          builder: (context) {
            testContext = context;
            return const SizedBox();
          },
        ),
      ),
    );

    final behavior = BaseScrollBehavior();
    const child = SizedBox(key: ValueKey('scroll-child'));
    final decorated = behavior.buildOverscrollIndicator(
      testContext,
      child,
      const ScrollableDetails.vertical(),
    );

    expect(decorated, same(child));
    expect(
      behavior.getScrollPhysics(testContext),
      isA<ClampingScrollPhysics>(),
    );
  });
}

import 'package:fl_clash/common/print.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/providers/app.dart';
import 'package:fl_clash/state.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late DebugPrintCallback previousDebugPrint;
  late bool previousIsAttach;
  final output = <String>[];

  setUp(() {
    previousDebugPrint = debugPrint;
    previousIsAttach = globalState.isAttach;
    globalState.isAttach = false;
    output.clear();
    debugPrint = (message, {wrapWidth}) {
      if (message != null) output.add(message);
    };
  });

  tearDown(() {
    debugPrint = previousDebugPrint;
    globalState.isAttach = previousIsAttach;
  });

  test('redacts sensitive runtime messages before console output', () {
    commonPrint.log(
      'find https://example.com/subscribe?token=fake-subscription proxy: false',
    );
    commonPrint.log(
      'login failed {"password":"fake-password",'
      '"account":"test-account","code":"auth_failed"}',
    );

    expect(output.first, '[APP] find <redacted-url> proxy: false');
    expect(output.last, contains('auth_failed'));
    for (final secret in [
      'fake-subscription',
      'fake-password',
      'test-account',
    ]) {
      expect(output.join('\n'), isNot(contains(secret)));
    }
  });

  test('stores the same redacted message and severity in the UI log', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    globalState.container = container;
    globalState.isAttach = true;

    commonPrint.log(
      'request failed access_token=fake-access; stage=core_setup',
      logLevel: LogLevel.error,
    );

    final log = container.read(logsProvider).list.single;
    expect(log.payload, output.single);
    expect(log.logLevel, LogLevel.error);
    expect(log.payload, contains('stage=core_setup'));
    expect(log.payload, isNot(contains('fake-access')));
  });

  test('redacts deep links and nested encoded subscription URLs', () {
    for (final link in [
      'flclash://install-config?url=https%3A%2F%2Fexample.com%2Ffake-subscription',
      'FLCLASH%3A%2F%2Finstall-config%3Furl%3Dfake-subscription',
      'https%253A%252F%252Fexample.com%252Ffake-subscription',
      'ss://fake-node-password@example.com:443',
    ]) {
      commonPrint.log('onAppLink: $link');
    }

    expect(output, everyElement('[APP] onAppLink: <redacted-url>'));
  });

  test('keeps full non-sensitive errors and operation details', () {
    final trace = List.filled(2400, 'x').join();
    final message =
        'Core setup failed: code=listener_not_ready; elapsed_ms=430\n$trace';

    commonPrint.log(message);

    expect(output.single, '[APP] $message');
  });
}

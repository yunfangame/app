import 'package:fl_clash/common/window.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:window_ext/window_ext.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  const windowChannel = MethodChannel('window_manager');
  const extensionChannel = MethodChannel('window_ext');
  final calls = <String>[];
  Object? recoveryError;
  bool? recoveryResult;

  setUp(() {
    calls.clear();
    recoveryError = null;
    recoveryResult = true;
    binding.defaultBinaryMessenger.setMockMethodCallHandler(windowChannel, (
      call,
    ) async {
      calls.add(call.method);
      if (call.method == 'isVisible') return true;
      if (call.method == 'isMinimized') return false;
      return null;
    });
    binding.defaultBinaryMessenger.setMockMethodCallHandler(extensionChannel, (
      call,
    ) async {
      calls.add(call.method);
      expect(call.method, 'restoreToActiveScreen');
      expect(call.arguments, isNull);
      final error = recoveryError;
      if (error != null) throw error;
      return recoveryResult;
    });
  });

  tearDown(() {
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      windowChannel,
      null,
    );
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      extensionChannel,
      null,
    );
  });

  test(
    'explicit Windows show requests recovery before normal activation',
    () async {
      await Window.forTesting(isWindows: true).show();

      expect(calls, [
        'restoreToActiveScreen',
        'isMinimized',
        'show',
        'focus',
        'setSkipTaskbar',
      ]);
    },
  );

  test('startup show preserves the saved monitor position', () async {
    await Window.forTesting(isWindows: true).show(restoreToActiveScreen: false);

    expect(calls, ['isMinimized', 'show', 'focus', 'setSkipTaskbar']);
  });

  test('other platforms keep their original activation path', () async {
    await Window.forTesting(isWindows: false).show();

    expect(calls, ['isMinimized', 'show', 'focus', 'setSkipTaskbar']);
  });

  test('a rejected recovery request still shows the window', () async {
    recoveryResult = false;

    await Window.forTesting(isWindows: true).show();

    expect(
      calls,
      containsAllInOrder(['restoreToActiveScreen', 'show', 'focus']),
    );
  });

  test('an unavailable recovery plugin still shows the window', () async {
    recoveryError = MissingPluginException();

    await Window.forTesting(isWindows: true).show();

    expect(
      calls,
      containsAllInOrder(['restoreToActiveScreen', 'show', 'focus']),
    );
  });

  test('a recovery platform error still shows the window', () async {
    recoveryError = PlatformException(code: 'recoveryFailed');

    await Window.forTesting(isWindows: true).show();

    expect(
      calls,
      containsAllInOrder(['restoreToActiveScreen', 'show', 'focus']),
    );
  });

  test('a visible Windows failure window is recovered explicitly', () async {
    await Window.forTesting(isWindows: true).showInitFailure();

    expect(
      calls,
      containsAllInOrder([
        'ensureInitialized',
        'isVisible',
        'restoreToActiveScreen',
        'show',
        'focus',
      ]),
    );
  });

  test(
    'other platforms leave an already visible failure window alone',
    () async {
      await Window.forTesting(isWindows: false).showInitFailure();

      expect(calls, ['ensureInitialized', 'isVisible']);
    },
  );

  test(
    'an empty native recovery response reports an unsuccessful request',
    () async {
      recoveryResult = null;

      expect(await windowExtManager.restoreToActiveScreen(), isFalse);
    },
  );
}

import 'package:fl_clash/common/constant.dart';
import 'package:fl_clash/plugins/app.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('$packageName/app');

  setUp(() {
    App().clearPackageIconCache();
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    App().clearPackageIconCache();
  });

  test('reads previous execution crash state from Android', () async {
    MethodCall? receivedCall;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          receivedCall = call;
          return true;
        });

    final didCrash = await App().didCrashOnPreviousExecution();

    expect(didCrash, isTrue);
    expect(receivedCall, isNotNull);
    expect(receivedCall!.method, 'didCrashOnPreviousExecution');
  });

  test('uses false when Android returns no crash state', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async => null);

    expect(await App().didCrashOnPreviousExecution(), isFalse);
  });

  for (final entry in {
    'opened': AppUpdateInstallResult.opened,
    'permissionRequired': AppUpdateInstallResult.permissionRequired,
    'invalidPackage': AppUpdateInstallResult.invalidPackage,
    'cancelled': AppUpdateInstallResult.cancelled,
    'failed': AppUpdateInstallResult.failed,
    'unexpected': AppUpdateInstallResult.failed,
  }.entries) {
    test('maps Android update installer result ${entry.key}', () async {
      MethodCall? received;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            received = call;
            return entry.key;
          });
      final outcome = await App().installUpdate(
        '/cache/fengwo-app-updates/FengWo.apk',
      );
      expect(outcome, entry.value);
      expect(received!.method, 'installUpdate');
      expect(received!.arguments, {
        'path': '/cache/fengwo-app-updates/FengWo.apk',
      });
    });
  }

  test('requests every package icon from Android only once', () async {
    var iconCallCount = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          iconCallCount++;
          return '/icons/${call.arguments['packageName']}.png';
        });

    final app = App();
    final results = await Future.wait([
      app.getPackageIcon('com.a'),
      app.getPackageIcon('com.a'),
    ]);
    final cached = await app.getPackageIcon('com.a');

    expect(iconCallCount, 1);
    expect(results.first, isNotNull);
    expect(cached, same(results.first));
    expect(app.hasPackageIcon('com.a'), isTrue);
    expect(app.getCachedPackageIcon('com.a'), same(results.first));

    await app.getPackageIcon('com.b');

    expect(iconCallCount, 2);
  });

  test(
    'caches packages without an icon and skips empty package names',
    () async {
      var iconCallCount = 0;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (_) async {
            iconCallCount++;
            return null;
          });

      final app = App();

      expect(await app.getPackageIcon(''), isNull);
      expect(iconCallCount, 0);
      expect(app.hasPackageIcon(''), isFalse);

      expect(await app.getPackageIcon('com.a'), isNull);
      expect(await app.getPackageIcon('com.a'), isNull);

      expect(iconCallCount, 1);
      expect(app.hasPackageIcon('com.a'), isTrue);
    },
  );

  test('caches a failed package icon lookup', () async {
    var iconCallCount = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async {
          iconCallCount++;
          throw PlatformException(code: 'unavailable');
        });

    final app = App();

    expect(await app.getPackageIcon('com.a'), isNull);
    expect(await app.getPackageIcon('com.a'), isNull);
    expect(iconCallCount, 1);
  });

  test('uses false when crash detection is unavailable', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async {
          throw PlatformException(code: 'unavailable');
        });

    expect(await App().didCrashOnPreviousExecution(), isFalse);
  });
}

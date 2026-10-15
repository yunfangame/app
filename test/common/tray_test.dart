import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:fl_clash/common/constant.dart';
import 'package:fl_clash/common/tray.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  final copiedCommands = <Map<String, Object>>[];

  tearDown(() {
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      null,
    );
  });

  tearDownAll(() async {
    final evidencePath = Platform.environment['FENGWO_TRAY_COPY_EVIDENCE'];
    if (evidencePath != null) {
      await File(evidencePath).writeAsString(
        const JsonEncoder.withIndent('  ').convert(copiedCommands),
      );
    }
  });

  test('uses the FengWo desktop tray name', () {
    expect(trayName, 'FengWo');
  });

  group('Tray.getTryIcon', () {
    final tray = Tray();
    final suffix = tray.trayIconSuffix;

    test('returns idle icon when core is not started', () {
      expect(
        tray.getTryIcon(isStart: false, tunEnable: false),
        'assets/images/icon/status_1.$suffix',
      );
    });

    test('returns normal mode icon when core is started without TUN', () {
      expect(
        tray.getTryIcon(isStart: true, tunEnable: false),
        Platform.isMacOS
            ? 'assets/images/icon/status_1.$suffix'
            : 'assets/images/icon/status_2.$suffix',
      );
    });

    test('returns enhanced mode icon when core is started with TUN', () {
      expect(
        tray.getTryIcon(isStart: true, tunEnable: true),
        Platform.isMacOS
            ? 'assets/images/icon/status_1.$suffix'
            : 'assets/images/icon/status_3.$suffix',
      );
    });
  });

  group('copy environment variables', () {
    test('uses the existing localized parent and native Windows submenu', () {
      for (final label in [
        'Copying environment variables',
        '\u590d\u5236\u73af\u5883\u53d8\u91cf',
      ]) {
        final item = buildCopyEnvMenuItem(
          label: label,
          port: 17980,
          isWindows: true,
        );

        expect(item.label, label);
        expect(item.type, 'submenu');
        expect(item.onClick, isNull);
        expect(item.disabled, isFalse);
        final entries = item.submenu!.items!;
        expect(entries.map((entry) => entry.label), [
          'Bash',
          'CMD',
          'PowerShell',
        ]);
        expect(entries.map((entry) => entry.type), everyElement('normal'));
        expect(entries.map((entry) => entry.disabled), everyElement(isFalse));
        expect(entries.map((entry) => entry.id).toSet(), hasLength(3));
        for (final entry in entries) {
          expect(item.submenu!.getMenuItemById(entry.id), same(entry));
          expect(entry.onClick, isNotNull);
        }
        final serialized = item.toJson();
        final serializedMenu = serialized['submenu'] as Map<String, dynamic>;
        final serializedItems = serializedMenu['items'] as List<dynamic>;
        expect(serialized['type'], 'submenu');
        expect(serializedItems.map((entry) => (entry as Map)['label']), [
          'Bash',
          'CMD',
          'PowerShell',
        ]);
      }
    });

    for (final port in [1, 1080, 7890, 17980, 65535]) {
      final url = 'http://127.0.0.1:$port';
      final expected = {
        'Bash': 'export ALL_PROXY="$url"',
        'CMD': 'set "ALL_PROXY=$url"',
        'PowerShell': '\$env:ALL_PROXY = "$url"',
      };
      for (final command in expected.entries) {
        test('${command.key} copies the current mixed port $port', () async {
          final item = buildCopyEnvMenuItem(
            label: 'Copying environment variables',
            port: port,
            isWindows: true,
          );
          final entry = item.submenu!.items!.singleWhere(
            (entry) => entry.label == command.key,
          );
          final clipboard = _captureClipboard(binding);

          entry.onClick!(entry);

          final text = await clipboard;
          expect(text, command.value);
          copiedCommands.add({
            'shell': command.key,
            'port': port,
            'command': text,
            'expected': url,
          });
        });
      }
    }

    test(
      'rebuilding the menu uses the new port rather than the old one',
      () async {
        buildCopyEnvMenuItem(label: 'Copy', port: 7890, isWindows: true);
        final updated = buildCopyEnvMenuItem(
          label: 'Copy',
          port: 17980,
          isWindows: true,
        );
        for (final entry in updated.submenu!.items!) {
          final clipboard = _captureClipboard(binding);
          entry.onClick!(entry);
          final text = await clipboard;
          expect(text, contains('127.0.0.1:17980'));
          expect(text, isNot(contains('7890')));
        }
      },
    );

    test('Mac and Linux retain their one-click export command', () async {
      final item = buildCopyEnvMenuItem(
        label: 'Copying environment variables',
        port: 17980,
        isWindows: false,
      );
      expect(item.type, 'normal');
      expect(item.submenu, isNull);
      final clipboard = _captureClipboard(binding);

      item.onClick!(item);

      expect(await clipboard, 'export all_proxy=http://127.0.0.1:17980');
    });
  });
}

Future<String> _captureClipboard(TestWidgetsFlutterBinding binding) {
  final result = Completer<String>();
  binding.defaultBinaryMessenger.setMockMethodCallHandler(
    SystemChannels.platform,
    (call) async {
      if (call.method == 'Clipboard.setData') {
        final arguments = call.arguments as Map;
        result.complete(arguments['text'] as String);
      }
      return null;
    },
  );
  return result.future;
}

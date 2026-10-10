import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:flutter_js/flutter_js.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('JavaScript verification uses native Windows ARM64', () {
    expect(Platform.isWindows, isTrue);
    expect(Abi.current(), Abi.windowsArm64);
  });

  test('the actual plugin evaluates numbers and UTF-8', () {
    final runtime = getJavascriptRuntime(xhr: false);
    try {
      expect(runtime.evaluate('1 + 2').stringResult, '3');
      expect(runtime.evaluate('"蜂窝 ARM64 🚀"').stringResult, '蜂窝 ARM64 🚀');
    } finally {
      runtime.dispose();
    }
  });

  test(
    'the actual plugin preserves config script objects and arrays',
    () async {
      final runtime = getJavascriptRuntime(xhr: false);
      try {
        final result = await runtime.evaluateAsync('''
        function main(config) {
          config.mode = 'global';
          config.proxies.push({name: '测试', port: 7890});
          return config;
        }
        JSON.stringify(main({mode: 'rule', proxies: []}));
      ''');
        expect(result.isError, isFalse);
        expect(jsonDecode(result.stringResult), {
          'mode': 'global',
          'proxies': [
            {'name': '测试', 'port': 7890},
          ],
        });
      } finally {
        runtime.dispose();
      }
    },
  );

  test('the actual plugin invokes a Dart channel through ARM64 FFI', () {
    final runtime = getJavascriptRuntime(xhr: false);
    Object? received;
    try {
      runtime.onMessage('smoke', (Object? value) {
        received = value;
        return 'ok';
      });
      final result = runtime.evaluate(
        'sendMessage("smoke", JSON.stringify({value: 7}));',
      );
      expect(result.isError, isFalse);
      expect(received, {'value': 7});
    } finally {
      runtime.dispose();
    }
  });

  test('the actual plugin resolves Promise values', () async {
    final runtime = getJavascriptRuntime(xhr: false);
    try {
      final result = await runtime.handlePromise(
        runtime.evaluate('Promise.resolve({answer: 42, name: "蜂窝"})'),
        timeout: const Duration(seconds: 3),
      );
      expect(result.isError, isFalse);
      expect(jsonDecode(result.stringResult), {'answer': 42, 'name': '蜂窝'});
    } finally {
      runtime.dispose();
    }
  });

  test('the actual plugin enforces its execution timeout and memory limit', () {
    final runtime = QuickJsRuntime2(timeout: 20, memoryLimit: 64 * 1024 * 1024);
    try {
      final result = runtime.evaluate('while (true) {}');
      expect(result.isError, isTrue);
      expect(result.stringResult.toLowerCase(), contains('interrupted'));
    } finally {
      runtime.dispose();
    }
  });
}

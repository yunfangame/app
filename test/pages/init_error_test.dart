import 'dart:async';
import 'dart:io';

import 'package:fl_clash/common/preferences_storage_error.dart';
import 'package:fl_clash/common/startup.dart';
import 'package:fl_clash/common/windows_integrity.dart';
import 'package:fl_clash/pages/error.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final stack = StackTrace.fromString('Migration.run (migration.dart:126)');
  const storageError = PreferenceStorageException(
    operation: 'read',
    cause: FormatException(
      'private-token-do-not-export',
      '{"token":"private-token-do-not-export","account":"private-account"}',
    ),
    path: r'C:\Users\customer\AppData\Roaming\FengWo\preferences.json',
  );

  testWidgets('low integrity guidance and copied paths fit a narrow window', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 480);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    String? copied;
    const integrityError = WindowsIntegrityException(
      snapshot: WindowsIntegritySnapshot(
        executablePath: r'D:\Favorites\FlClash\FengWo.exe',
        dataDirectoryCandidate: r'C:\Users\用户\AppData\Roaming\com.follow\蜂窝加速器',
        rid: 4096,
      ),
      code: 'WIN-INTEGRITY-LOW',
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(platform: TargetPlatform.windows),
        home: InitErrorScreen(
          error: const StartupStageException.failure(
            '检查 Windows 运行权限',
            integrityError,
          ),
          stack: stack,
          copyDetails: (details) async => copied = details,
        ),
      ),
    );
    expect(find.text(integrityError.guidance), findsOneWidget);
    expect(find.text(integrityError.recovery), findsOneWidget);
    expect(find.textContaining('SQLite'), findsNothing);
    expect(find.textContaining('磁盘剩余空间'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('复制详情'));
    await tester.pumpAndSettle();
    expect(copied, contains('WIN-INTEGRITY-LOW'));
    expect(copied, contains('RID=4096'));
    expect(copied, contains(integrityError.snapshot.executablePath));
    expect(copied, contains(integrityError.snapshot.dataDirectoryCandidate!));
    expect(copied, contains('重新运行安装程序'));
    expect(tester.takeException(), isNull);
  });

  testWidgets('integrity query failure is not described as a low token', (
    tester,
  ) async {
    const error = WindowsIntegrityException(
      snapshot: WindowsIntegritySnapshot(
        executablePath: r'D:\FengWo\FengWo.exe',
        dataDirectoryCandidate: null,
      ),
      code: 'WIN-INTEGRITY-QUERY-DENIED',
      operation: 'OpenProcessToken',
      systemError: 5,
    );
    await tester.pumpWidget(
      const MaterialApp(
        home: InitErrorScreen(error: error, stack: StackTrace.empty),
      ),
    );
    expect(find.text(error.guidance), findsOneWidget);
    expect(find.textContaining('低完整性运行'), findsNothing);
    expect(find.textContaining('Windows 系统错误码：5'), findsOneWidget);
    expect(find.textContaining('WIN-INTEGRITY-QUERY-DENIED'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Windows storage failure fits a narrow window without Mac keys', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 480);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(platform: TargetPlatform.windows),
        home: InitErrorScreen(
          error: const StartupStageException.failure('恢复本地数据', storageError),
          stack: stack,
        ),
      ),
    );

    expect(find.textContaining('⌘Q'), findsNothing);
    expect(find.textContaining('磁盘剩余空间'), findsOneWidget);
    expect(find.textContaining('本次启动已停止'), findsOneWidget);
    expect(find.text('复制详情'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.drag(
      find.byType(SingleChildScrollView),
      const Offset(0, -500),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'copy includes system and safe error details without preferences',
    (tester) async {
      String? copied;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copied = (call.arguments as Map)['text'] as String;
          }
          return null;
        },
      );
      addTearDown(() {
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        );
      });
      const error = StartupStageException.failure('恢复本地数据', storageError);
      await tester.pumpWidget(
        MaterialApp(
          home: InitErrorScreen(error: error, stack: stack),
        ),
      );

      await tester.tap(find.text('复制详情'));
      await tester.pumpAndSettle();

      expect(copied, contains(Platform.operatingSystem));
      expect(copied, contains(Platform.operatingSystemVersion));
      expect(copied, contains(error.toString()));
      expect(copied, contains(stack.toString()));
      expect(copied, isNot(contains('private-token-do-not-export')));
      expect(copied, isNot(contains('private-account')));
      expect(copied, isNot(contains('"token"')));
      expect(find.text('错误详情已复制'), findsOneWidget);
    },
  );

  testWidgets(
    'copy disables repeat taps until the clipboard operation finishes',
    (tester) async {
      final completer = Completer<void>();
      var calls = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: InitErrorScreen(
            error: storageError,
            stack: stack,
            copyDetails: (_) {
              calls++;
              return completer.future;
            },
          ),
        ),
      );

      await tester.tap(find.text('复制详情'));
      await tester.tap(find.text('复制详情'));
      await tester.pump();
      expect(find.text('复制中…'), findsOneWidget);
      expect(
        tester
            .widget<FloatingActionButton>(find.byType(FloatingActionButton))
            .onPressed,
        isNull,
      );
      await tester.tap(find.text('复制中…'));
      expect(calls, 1);
      completer.complete();
      await tester.pumpAndSettle();
      expect(find.text('复制详情'), findsOneWidget);
      expect(find.text('错误详情已复制'), findsOneWidget);
    },
  );

  testWidgets('copy failure restores the button and offers manual copying', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: InitErrorScreen(
          error: storageError,
          stack: stack,
          copyDetails: (_) async => throw StateError('clipboard unavailable'),
        ),
      ),
    );

    await tester.tap(find.text('复制详情'));
    await tester.pumpAndSettle();
    expect(find.text('复制失败，请手动选择并复制下方错误详情。'), findsOneWidget);
    expect(find.text('错误详情已复制'), findsNothing);
    expect(find.text('复制详情'), findsOneWidget);
    expect(
      tester
          .widget<FloatingActionButton>(find.byType(FloatingActionButton))
          .onPressed,
      isNotNull,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'copy completion after disposal does not access the old context',
    (tester) async {
      final completer = Completer<void>();
      await tester.pumpWidget(
        MaterialApp(
          home: InitErrorScreen(
            error: storageError,
            stack: stack,
            copyDetails: (_) => completer.future,
          ),
        ),
      );

      await tester.tap(find.text('复制详情'));
      await tester.pumpWidget(const SizedBox.shrink());
      completer.completeError(StateError('clipboard unavailable'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('other startup errors retain generic recovery guidance', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: InitErrorScreen(
          error: StateError('startup failed'),
          stack: stack,
        ),
      ),
    );

    expect(find.textContaining('完全退出客户端后重试'), findsOneWidget);
    expect(find.textContaining('无法安全读写'), findsNothing);
    expect(find.textContaining('⌘Q'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}

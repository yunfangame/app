import 'dart:async';
import 'dart:io';

import 'package:fl_clash/pages/error.dart';
import 'package:fl_clash/state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rust_api/rust_api.dart';

import 'application.dart';
import 'common/common.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final startupStage = ValueNotifier<String>('正在准备运行环境…');
  runApp(InitLoadingScreen(stage: startupStage));
  await WidgetsBinding.instance.endOfFrame;
  var startupActive = true;
  final startupWindowFallback = system.isMacOS
      ? Timer(const Duration(seconds: 2), () {
          if (startupActive) {
            unawaited(window?.showStartup(isActive: () => startupActive));
          }
        })
      : null;
  try {
    if (system.isDesktop) {
      await runStartupStage<void>(
        stage: '加载本地组件',
        timeout: const Duration(seconds: 10),
        operation: RustLib.init,
        onStart: (stage) => startupStage.value = '$stage…',
      );
    }
    final version = await runStartupStage<int>(
      stage: '读取系统信息',
      timeout: const Duration(seconds: 10),
      operation: system.init,
      onStart: (stage) => startupStage.value = '$stage…',
    );
    final container = await runStartupStage<ProviderContainer>(
      stage: '恢复本地数据',
      timeout: const Duration(seconds: 20),
      operation: () => globalState.init(version),
      onStart: (stage) => startupStage.value = '$stage…',
    );
    startupActive = false;
    startupWindowFallback?.cancel();
    HttpOverrides.global = FlClashHttpOverrides();
    runApp(
      UncontrolledProviderScope(
        container: container,
        child: const Application(),
      ),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) => startupStage.dispose());
  } catch (e, s) {
    startupActive = false;
    startupWindowFallback?.cancel();
    runApp(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        home: InitErrorScreen(error: e, stack: s),
      ),
    );
    unawaited(window?.showInitFailure());
    WidgetsBinding.instance.addPostFrameCallback((_) => startupStage.dispose());
  }
}

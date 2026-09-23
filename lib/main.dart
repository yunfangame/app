import 'dart:async';
import 'dart:io';

import 'package:fl_clash/pages/error.dart';
import 'package:fl_clash/state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rust_api/rust_api.dart';

import 'application.dart';
import 'common/common.dart';
import 'common/windows_integrity.dart';
import 'common/windows_tls_trust.dart';
import 'common/windows_preferences.dart';

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
  WindowsIntegritySnapshot? windowsIntegrity;
  try {
    if (Platform.isWindows) {
      windowsIntegrity = await runStartupStage<WindowsIntegritySnapshot?>(
        stage: '检查 Windows 运行权限',
        timeout: const Duration(seconds: 5),
        operation: () async => verifyWindowsStartupIntegrity(),
        onStart: (stage) => startupStage.value = '$stage…',
      );
      installWindowsPreferencesStore(
        store: WindowsPreferencesStore(
          onDiagnostic: (error) {
            unawaited(
              diagnosticLog.record(
                'preferences.backup_degraded',
                fields: {
                  'operation': error.operation,
                  'diagnostic_code': error.code,
                  'error_type': error.cause.runtimeType.toString(),
                },
              ),
            );
          },
        ),
      );
      try {
        final rootCount = await runStartupStage<int>(
          stage: '准备安全连接',
          timeout: const Duration(seconds: 5),
          operation: windowsTlsTrust.initialize,
          onStart: (stage) => startupStage.value = '$stage…',
        );
        unawaited(
          diagnosticLog.record(
            'tls.trust.initialized',
            fields: {'supplemental_roots': rootCount, 'bundle_version': 1},
          ),
        );
      } catch (error) {
        unawaited(
          diagnosticLog.record(
            'tls.trust.failed',
            fields: {'error_type': error.runtimeType.toString()},
          ),
        );
      }
    }
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
      stage: '读取本地设置',
      timeout: const Duration(seconds: 20),
      operation: () => globalState.init(version),
      onStart: (stage) => startupStage.value = '$stage…',
    );
    if (windowsIntegrity != null) {
      unawaited(
        diagnosticLog.record(
          'startup.windows_integrity_verified',
          fields: windowsIntegrity.diagnosticFields,
        ),
      );
    }
    startupActive = false;
    startupWindowFallback?.cancel();
    HttpOverrides.global = FlClashHttpOverrides();
    runApp(
      UncontrolledProviderScope(
        container: container,
        child: const Application(),
      ),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      startupStage.dispose();
      unawaited(diagnosticLog.record('startup.ready'));
    });
  } catch (e, s) {
    startupActive = false;
    startupWindowFallback?.cancel();
    final cause = e is StartupStageException ? e.cause : e;
    if (cause is WindowsIntegrityException) {
      reportWindowsIntegrityFailure(cause);
    } else {
      unawaited(
        diagnosticLog.record(
          'startup.failed',
          fields: {
            'error_type': e.runtimeType.toString(),
            if (windowsIntegrity != null) ...windowsIntegrity.diagnosticFields,
            if (e is StartupStageException) ...{
              'stage': e.stage,
              'cause_type': e.cause.runtimeType.toString(),
            },
          },
        ),
      );
    }
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

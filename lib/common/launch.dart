import 'dart:async';
import 'dart:io';

import 'package:launch_at_startup/launch_at_startup.dart';

import 'constant.dart';
import 'system.dart';
import 'windows_auto_launch.dart';

bool shouldHideWindowAtStartup({
  required bool silentLaunch,
  required bool hasAuthenticatedSession,
}) => silentLaunch && hasAuthenticatedSession;

class AutoLaunchException implements Exception {
  final String code;

  const AutoLaunchException(this.code);

  @override
  String toString() => 'AutoLaunchException($code)';
}

class AutoLaunch {
  final Future<bool> Function() _read;
  final Future<void> Function(bool) _write;
  final Future<void> Function() Function()? _captureRestore;
  Future<void> _pending = Future.value();

  AutoLaunch.withBackend({
    required Future<bool> Function() read,
    required Future<void> Function(bool) write,
    Future<void> Function() Function()? captureRestore,
  }) : _read = read,
       _write = write,
       _captureRestore = captureRestore;

  factory AutoLaunch() {
    if (Platform.isWindows) {
      final backend = WindowsAutoLaunchBackend(
        executable: Platform.resolvedExecutable,
      );
      return AutoLaunch.withBackend(
        read: backend.isEnabled,
        write: backend.setEnabled,
        captureRestore: backend.captureRestore,
      );
    }
    launchAtStartup.setup(
      appName: appName,
      appPath: Platform.resolvedExecutable,
    );
    return AutoLaunch.withBackend(
      read: launchAtStartup.isEnabled,
      write: (enabled) async {
        final success = enabled
            ? await launchAtStartup.enable()
            : await launchAtStartup.disable();
        if (!success) throw const AutoLaunchException('changeFailed');
      },
    );
  }

  Future<bool> get isEnable async {
    await _pending;
    try {
      return await _read();
    } catch (_) {
      throw const AutoLaunchException('readFailed');
    }
  }

  Future<void> updateStatus(
    bool enabled, {
    Future<void> Function(bool)? persist,
  }) {
    final operation = _pending.then((_) => _update(enabled, persist));
    _pending = operation.then<void>((_) {}, onError: (Object _) {});
    return operation;
  }

  Future<void> _update(
    bool enabled,
    Future<void> Function(bool)? persist,
  ) async {
    final bool previous;
    final Future<void> Function()? restore;
    try {
      previous = await _read();
      restore = _captureRestore?.call();
    } catch (_) {
      throw const AutoLaunchException('readFailed');
    }
    var failureCode = 'changeFailed';
    try {
      await _write(enabled);
      failureCode = 'verificationFailed';
      if (await _read() != enabled) {
        throw const AutoLaunchException('verificationFailed');
      }
      failureCode = 'persistenceFailed';
      await persist?.call(enabled);
    } catch (_) {
      try {
        if (restore != null) {
          await restore();
        } else if (await _read() != previous) {
          await _write(previous);
        }
        if (await _read() != previous) {
          throw const AutoLaunchException('rollbackFailed');
        }
      } catch (_) {
        throw const AutoLaunchException('rollbackFailed');
      }
      throw AutoLaunchException(failureCode);
    }
  }
}

final autoLaunch = system.isDesktop ? AutoLaunch() : null;

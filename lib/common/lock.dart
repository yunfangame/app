import 'dart:io';

import 'package:fl_clash/common/common.dart';

class SingleInstanceLock {
  static SingleInstanceLock? _instance;
  RandomAccessFile? _accessFile;
  Future<bool>? _pending;

  SingleInstanceLock._internal();

  factory SingleInstanceLock() {
    _instance ??= SingleInstanceLock._internal();
    return _instance!;
  }

  Future<bool> acquire() {
    if (_accessFile != null) return Future.value(true);
    return _pending ??= _acquire().whenComplete(() => _pending = null);
  }

  Future<bool> _acquire() async {
    RandomAccessFile? accessFile;
    try {
      final lockFilePath = await appPath.lockFilePath;
      final lockFile = File(lockFilePath);
      await lockFile.create();
      accessFile = await lockFile.open(mode: FileMode.write);
      await accessFile.lock();
      _accessFile = accessFile;
      return true;
    } catch (_) {
      await accessFile?.close();
      return false;
    }
  }
}

final singleInstanceLock = SingleInstanceLock();

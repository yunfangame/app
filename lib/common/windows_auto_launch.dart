import 'dart:typed_data';

import 'package:win32/win32.dart';
import 'package:win32_registry/win32_registry.dart';

abstract interface class WindowsAutoLaunchRegistry {
  RegistryValue? read(String path, String name);
  void write(String path, String name, RegistryValue? value);
}

class WindowsAutoLaunchBackend {
  static const runPath = r'Software\Microsoft\Windows\CurrentVersion\Run';
  static const approvedPath =
      r'Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run';
  static const valueName = 'FengWo';
  static const legacyValueName = 'FlClash';

  final String executable;
  final WindowsAutoLaunchRegistry registry;

  WindowsAutoLaunchBackend({
    required this.executable,
    WindowsAutoLaunchRegistry? registry,
  }) : registry = registry ?? _NativeAutoLaunchRegistry() {
    if (executable.isEmpty || executable.contains('"')) {
      throw ArgumentError.value(executable, 'executable');
    }
  }

  String get command => '"$executable"';

  bool _owns(RegistryValue? value) {
    if (value is! StringValue) return false;
    var path = value.value.trim();
    if (path.length >= 2 && path.startsWith('"') && path.endsWith('"')) {
      path = path.substring(1, path.length - 1);
    }
    return path.replaceAll('/', '\\').toLowerCase() ==
        executable.replaceAll('/', '\\').toLowerCase();
  }

  bool _approved(String name) {
    final value = registry.read(approvedPath, name);
    return value == null ||
        (value is BinaryValue &&
            (value.value.isEmpty || value.value.first.isEven));
  }

  Future<bool> isEnabled() async {
    return (_owns(registry.read(runPath, valueName)) && _approved(valueName)) ||
        (_owns(registry.read(runPath, legacyValueName)) &&
            _approved(legacyValueName));
  }

  Future<void> setEnabled(bool enabled) async {
    final ownsLegacy = _owns(registry.read(runPath, legacyValueName));
    final names = [valueName, if (ownsLegacy) legacyValueName];
    final previous = <(String, String), RegistryValue?>{
      for (final name in names)
        for (final path in [runPath, approvedPath])
          (path, name): registry.read(path, name),
    };
    final changed = <(String, String)>[];
    void write(String path, String name, RegistryValue? value) {
      if (registry.read(path, name) == value) return;
      registry.write(path, name, value);
      changed.add((path, name));
    }

    try {
      if (enabled) {
        final approved = Uint8List(12)..[0] = 2;
        write(runPath, valueName, RegistryValue.string(command));
        write(approvedPath, valueName, RegistryValue.binary(approved));
      } else {
        write(runPath, valueName, null);
        write(approvedPath, valueName, null);
      }
      if (ownsLegacy) {
        write(runPath, legacyValueName, null);
        write(approvedPath, legacyValueName, null);
      }
    } catch (_) {
      for (final (path, name) in changed.reversed) {
        registry.write(path, name, previous[(path, name)]);
      }
      rethrow;
    }
  }

  Future<void> Function() captureRestore() {
    final names = [
      valueName,
      if (_owns(registry.read(runPath, legacyValueName))) legacyValueName,
    ];
    final previous = <(String, String), RegistryValue?>{
      for (final name in names)
        for (final path in [runPath, approvedPath])
          (path, name): registry.read(path, name),
    };
    return () async {
      for (final entry in previous.entries) {
        final (path, name) = entry.key;
        if (registry.read(path, name) != entry.value) {
          registry.write(path, name, entry.value);
        }
      }
      for (final entry in previous.entries) {
        final (path, name) = entry.key;
        if (registry.read(path, name) != entry.value) {
          throw StateError('Autostart registration rollback was rejected');
        }
      }
    };
  }
}

class _NativeAutoLaunchRegistry implements WindowsAutoLaunchRegistry {
  @override
  RegistryValue? read(String path, String name) {
    RegistryKey? key;
    try {
      key = CURRENT_USER.open(path);
      return key.getValue(name);
    } on WindowsException catch (error) {
      if (error.hr.toInt() & 0xffff == 2) return null;
      rethrow;
    } finally {
      key?.close();
    }
  }

  @override
  void write(String path, String name, RegistryValue? value) {
    if (value == null && read(path, name) == null) return;
    final key = CURRENT_USER.open(
      path,
      config: RegistryOpenConfig(
        access: RegistryAccess.readWrite,
        create: value != null,
      ),
    );
    try {
      if (value == null) {
        key.removeValue(name);
      } else {
        key.setValue(name, value);
      }
    } finally {
      key.close();
    }
  }
}

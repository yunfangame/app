import 'dart:io';

class PreferenceStorageException implements Exception {
  const PreferenceStorageException({
    required this.operation,
    required this.cause,
    this.path,
  });

  final String operation;
  final Object cause;
  final String? path;

  String get code {
    final error = cause;
    if (error is PreferenceStorageException) return error.code;
    if (error is FormatException || error is TypeError) return 'PREF-FORMAT';
    if (error is FileSystemException) {
      return switch (error.osError?.errorCode) {
        5 || 13 => 'PREF-ACCESS',
        32 || 33 => 'PREF-LOCKED',
        28 || 39 || 112 => 'PREF-DISK',
        _ => 'PREF-IO',
      };
    }
    if (operation == 'decode') return 'PREF-FORMAT';
    return 'PREF-STORAGE';
  }

  @override
  String toString() {
    final action = switch (operation) {
      'initialize' => '初始化本地配置',
      'read' => '读取本地配置',
      'decode' => '解析本地配置',
      'backup' => '备份本地配置',
      'recover' => '恢复本地配置备份',
      _ => '保存本地配置',
    };
    final reason = switch (code) {
      'PREF-FORMAT' => '配置文件不完整或格式无效',
      'PREF-ACCESS' => '配置目录或文件访问被拒绝，请检查访问权限',
      'PREF-LOCKED' => '配置文件被占用，请退出其他客户端后重试',
      'PREF-DISK' => '磁盘空间不足或存储空间不可用',
      'PREF-IO' => '文件读写失败',
      _ => '本地存储组件未能完成操作',
    };
    final error = cause;
    final osCode = error is FileSystemException
        ? error.osError?.errorCode
        : null;
    final suffix = osCode == null ? '' : '，系统错误码 $osCode';
    final location = path == null ? '' : '\n配置文件：$path';
    return '$action失败：$reason（$code$suffix）。$location';
  }
}

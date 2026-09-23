import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:path/path.dart' as path;

const windowsMediumIntegrityRid = 8192;

final class WindowsIntegritySnapshot {
  const WindowsIntegritySnapshot({
    required this.executablePath,
    required this.dataDirectoryCandidate,
    this.rid,
  });

  final String executablePath;
  final String? dataDirectoryCandidate;
  final int? rid;

  String get label => switch (rid) {
    null => '未能读取',
    < 4096 => '不受信任（Untrusted）',
    < windowsMediumIntegrityRid => '低（Low）',
    < 8448 => '中（Medium）',
    < 12288 => '中增强（Medium Plus）',
    < 16384 => '高（High）',
    < 20480 => '系统（System）',
    _ => '受保护（Protected）',
  };

  Map<String, Object?> get diagnosticFields => {
    'integrity_rid': rid,
    'integrity_label': label,
    'executable_path': executablePath,
    'data_directory_candidate': dataDirectoryCandidate,
  };

  String get details =>
      '完整性级别：$label${rid == null ? '' : '，RID=$rid'}\n'
      '程序路径：$executablePath\n'
      '数据目录（候选）：${dataDirectoryCandidate ?? '未设置 APPDATA 环境变量'}';
}

final class WindowsIntegrityQueryException implements Exception {
  const WindowsIntegrityQueryException(this.operation, this.systemError);

  final String operation;
  final int systemError;
}

final class WindowsIntegrityException implements Exception {
  const WindowsIntegrityException({
    required this.snapshot,
    required this.code,
    this.operation,
    this.systemError,
    this.errorType,
  });

  final WindowsIntegritySnapshot snapshot;
  final String code;
  final String? operation;
  final int? systemError;
  final String? errorType;

  bool get isRestricted => code == 'WIN-INTEGRITY-LOW';

  String get guidance => isRestricted
      ? 'Windows 将客户端以低完整性运行，无法保存本地配置。当前安装目录的安全标签或启动方式可能让程序受到限制。'
      : '无法检查客户端的 Windows 运行权限，本次启动已停止。请复制错误详情发送给客服。';

  String get recovery => isRestricted
      ? '请完全退出客户端，重新运行安装程序并选择正常的安装目录，或修复蜂窝自身安装目录后重新启动。不要删除用户数据。'
      : '请从正常的桌面快捷方式重新启动；如果仍失败，请将下方诊断码、系统错误码和路径发送给客服排查。';

  Map<String, Object?> get diagnosticFields => {
    ...snapshot.diagnosticFields,
    'diagnostic_code': code,
    if (operation != null) 'operation': operation,
    if (systemError != null) 'system_error': systemError,
    if (errorType != null) 'error_type': errorType,
  };

  @override
  String toString() =>
      '$guidance\n$recovery\n诊断码：$code\n${snapshot.details}'
      '${operation == null ? '' : '\n检测步骤：$operation'}'
      '${systemError == null ? '' : '\nWindows 系统错误码：$systemError'}'
      '${errorType == null ? '' : '\n错误类型：$errorType'}';
}

WindowsIntegritySnapshot? verifyWindowsStartupIntegrity({
  bool? isWindows,
  int Function()? readIntegrityRid,
  String Function()? executablePath,
  String? Function()? roamingDirectory,
}) {
  if (!(isWindows ?? Platform.isWindows)) return null;
  final executable = (executablePath ?? (() => Platform.resolvedExecutable))();
  final roaming =
      (roamingDirectory ?? (() => Platform.environment['APPDATA']))();
  final dataDirectory = roaming == null || roaming.trim().isEmpty
      ? null
      : path.windows.join(roaming, 'com.follow', '蜂窝加速器');
  final unknown = WindowsIntegritySnapshot(
    executablePath: executable,
    dataDirectoryCandidate: dataDirectory,
  );
  final int rid;
  try {
    rid = (readIntegrityRid ?? readCurrentWindowsIntegrityRid)();
    if (rid < 0 || rid > 0xffffffff) {
      throw const WindowsIntegrityQueryException('ValidateIntegrityRid', 13);
    }
  } on WindowsIntegrityQueryException catch (error) {
    throw WindowsIntegrityException(
      snapshot: unknown,
      code: error.systemError == 5
          ? 'WIN-INTEGRITY-QUERY-DENIED'
          : 'WIN-INTEGRITY-QUERY-FAILED',
      operation: error.operation,
      systemError: error.systemError,
    );
  } catch (error) {
    throw WindowsIntegrityException(
      snapshot: unknown,
      code: 'WIN-INTEGRITY-QUERY-FAILED',
      operation: 'ReadProcessIntegrity',
      errorType: error.runtimeType.toString(),
    );
  }
  final snapshot = WindowsIntegritySnapshot(
    executablePath: executable,
    dataDirectoryCandidate: dataDirectory,
    rid: rid,
  );
  if (rid < windowsMediumIntegrityRid) {
    throw WindowsIntegrityException(
      snapshot: snapshot,
      code: 'WIN-INTEGRITY-LOW',
    );
  }
  return snapshot;
}

final class _TokenMandatoryLabel extends Struct {
  external Pointer<Void> sid;

  @Uint32()
  external int attributes;
}

int readCurrentWindowsIntegrityRid() {
  final kernel32 = DynamicLibrary.open('kernel32.dll');
  final advapi32 = DynamicLibrary.open('advapi32.dll');
  final getCurrentProcess = kernel32
      .lookupFunction<Pointer<Void> Function(), Pointer<Void> Function()>(
        'GetCurrentProcess',
      );
  final getLastError = kernel32
      .lookupFunction<Uint32 Function(), int Function()>('GetLastError');
  final closeHandle = kernel32
      .lookupFunction<
        Int32 Function(Pointer<Void>),
        int Function(Pointer<Void>)
      >('CloseHandle');
  final openProcessToken = advapi32
      .lookupFunction<
        Int32 Function(Pointer<Void>, Uint32, Pointer<Pointer<Void>>),
        int Function(Pointer<Void>, int, Pointer<Pointer<Void>>)
      >('OpenProcessToken');
  final getTokenInformation = advapi32
      .lookupFunction<
        Int32 Function(
          Pointer<Void>,
          Int32,
          Pointer<Void>,
          Uint32,
          Pointer<Uint32>,
        ),
        int Function(Pointer<Void>, int, Pointer<Void>, int, Pointer<Uint32>)
      >('GetTokenInformation');
  final isValidSid = advapi32
      .lookupFunction<
        Int32 Function(Pointer<Void>),
        int Function(Pointer<Void>)
      >('IsValidSid');
  final getSidSubAuthorityCount = advapi32
      .lookupFunction<
        Pointer<Uint8> Function(Pointer<Void>),
        Pointer<Uint8> Function(Pointer<Void>)
      >('GetSidSubAuthorityCount');
  final getSidSubAuthority = advapi32
      .lookupFunction<
        Pointer<Uint32> Function(Pointer<Void>, Uint32),
        Pointer<Uint32> Function(Pointer<Void>, int)
      >('GetSidSubAuthority');
  final token = calloc<Pointer<Void>>();
  final length = calloc<Uint32>();
  Pointer<Uint8> buffer = nullptr;
  try {
    if (openProcessToken(getCurrentProcess(), 0x0008, token) == 0) {
      throw WindowsIntegrityQueryException('OpenProcessToken', getLastError());
    }
    final measured = getTokenInformation(token.value, 25, nullptr, 0, length);
    final measureError = getLastError();
    if (measured == 0 && measureError != 122) {
      throw WindowsIntegrityQueryException(
        'GetTokenInformation.size',
        measureError,
      );
    }
    final capacity = length.value;
    if (capacity < sizeOf<_TokenMandatoryLabel>() + 12 || capacity > 65536) {
      throw const WindowsIntegrityQueryException('ValidateTokenSize', 13);
    }
    buffer = calloc<Uint8>(capacity);
    if (getTokenInformation(token.value, 25, buffer.cast(), capacity, length) ==
        0) {
      throw WindowsIntegrityQueryException(
        'GetTokenInformation.read',
        getLastError(),
      );
    }
    final sid = buffer.cast<_TokenMandatoryLabel>().ref.sid;
    final end = buffer.address + length.value;
    if (length.value < sizeOf<_TokenMandatoryLabel>() + 12 ||
        length.value > capacity ||
        sid.address < buffer.address + sizeOf<_TokenMandatoryLabel>() ||
        sid.address + 8 > end) {
      throw const WindowsIntegrityQueryException('ValidateIntegritySid', 13);
    }
    final count = getSidSubAuthorityCount(sid).value;
    if (count < 1 ||
        count > 15 ||
        sid.address + 8 + count * 4 > end ||
        isValidSid(sid) == 0) {
      throw const WindowsIntegrityQueryException('ValidateIntegritySid', 13);
    }
    return getSidSubAuthority(sid, count - 1).value;
  } finally {
    if (buffer != nullptr) calloc.free(buffer);
    if (token.value != nullptr) closeHandle(token.value);
    calloc.free(length);
    calloc.free(token);
  }
}

void reportWindowsIntegrityFailure(WindowsIntegrityException error) {
  if (!Platform.isWindows) return;
  try {
    final output = DynamicLibrary.open('kernel32.dll')
        .lookupFunction<
          Void Function(Pointer<Utf16>),
          void Function(Pointer<Utf16>)
        >('OutputDebugStringW');
    final message = jsonEncode({
      'event': 'startup.windows_integrity_failed',
      'fields': error.diagnosticFields,
    }).toNativeUtf16();
    try {
      output(message);
    } finally {
      calloc.free(message);
    }
  } catch (_) {}
}

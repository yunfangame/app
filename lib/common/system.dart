import 'dart:ffi';
import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:ffi/ffi.dart';
import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/common/system_dns.dart';
import 'package:fl_clash/core/desktop/helper_client.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/plugins/app.dart';
import 'package:fl_clash/state.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/services.dart';
import 'package:path/path.dart';

typedef ProcessRunner =
    Future<ProcessResult> Function(String executable, List<String> arguments);

class System {
  static System? _instance;
  bool _isTV = false;

  @visibleForTesting
  ProcessRunner runProcess = Process.run;

  System._internal();

  factory System() {
    _instance ??= System._internal();
    return _instance!;
  }

  bool get isDesktop => isWindows || isMacOS || isLinux;

  bool get isWindows => Platform.isWindows;

  bool get isMacOS => Platform.isMacOS;

  bool get isAndroid => Platform.isAndroid;

  bool get isLinux => Platform.isLinux;

  bool get isTV => _isTV;

  Future<int> init() async {
    final deviceInfo = await DeviceInfoPlugin().deviceInfo;
    _isTV = switch (deviceInfo) {
      AndroidDeviceInfo(:final systemFeatures) => systemFeatures.any(
        const {
          'android.hardware.type.television',
          'android.software.leanback',
        }.contains,
      ),
      _ => false,
    };
    return switch (Platform.operatingSystem) {
      'macos' => (deviceInfo as MacOsDeviceInfo).majorVersion,
      'android' => (deviceInfo as AndroidDeviceInfo).version.sdkInt,
      'windows' => (deviceInfo as WindowsDeviceInfo).majorVersion,
      String() => 0,
    };
  }

  Future<bool> didCrashOnPreviousExecution() async {
    if (!isAndroid) return false;
    return await app?.didCrashOnPreviousExecution() ?? false;
  }

  @visibleForTesting
  static List<String> statArguments(String corePath, {required bool isMacOS}) {
    return isMacOS
        ? ['-f', '%Su:%Sg %Sp', corePath]
        : ['-c', '%U:%G %A', corePath];
  }

  @visibleForTesting
  static bool isPrivilegedStatOutput(
    String output, {
    required String ownerPrefix,
  }) {
    final trimmed = output.trim();
    return trimmed.startsWith(ownerPrefix) && trimmed.contains('rws');
  }

  bool get isAppImage =>
      isLinux && Platform.environment.containsKey('APPIMAGE');

  bool get hasHelperService => helperServiceAvailable(
    isWindows: isWindows,
    isLinux: isLinux,
    isAppImage: isAppImage,
    hasSystemd: isLinux && Directory('/run/systemd/system').existsSync(),
  );

  @visibleForTesting
  static bool helperServiceAvailable({
    required bool isWindows,
    required bool isLinux,
    required bool isAppImage,
    required bool hasSystemd,
  }) => isWindows || (isLinux && !isAppImage && hasSystemd);

  Future<bool> checkIsAdmin() async {
    if (hasHelperService) {
      return await helperClient.readiness() == HelperReadiness.ready;
    } else if (system.isMacOS) {
      final result = await runProcess(
        'stat',
        statArguments(appPath.corePath, isMacOS: true),
      );
      return isPrivilegedStatOutput(
        result.stdout.toString(),
        ownerPrefix: 'root:admin',
      );
    } else if (Platform.isLinux) {
      final result = await runProcess(
        'stat',
        statArguments(appPath.corePath, isMacOS: false),
      );
      return isPrivilegedStatOutput(
        result.stdout.toString(),
        ownerPrefix: 'root:',
      );
    }
    return true;
  }

  static const _inheritedAclPermissions =
      'list,search,add_file,add_subdirectory,delete,delete_child,'
      'file_inherit,directory_inherit';

  @visibleForTesting
  static List<String> aclArguments(String homeDirPath, String userName) {
    return [
      '-R',
      '+a',
      'user:$userName allow $_inheritedAclPermissions',
      homeDirPath,
    ];
  }

  Future<void> grantHomeDirAccess(String homeDirPath) async {
    if (!isMacOS) {
      return;
    }
    final userName = Platform.environment['USER'];
    if (userName == null || userName.isEmpty) {
      return;
    }
    try {
      final result = await runProcess(
        'chmod',
        aclArguments(homeDirPath, userName),
      );
      if (result.exitCode != 0) {
        commonPrint.log(
          'chmod +a exited with ${result.exitCode}: ${result.stderr.toString().trim()}',
          logLevel: LogLevel.warning,
        );
      }
    } catch (error) {
      commonPrint.log('chmod +a failed: $error', logLevel: LogLevel.warning);
    }
  }

  static String _shellEscape(String value) {
    return "'${value.replaceAll("'", "'\\''")}'";
  }

  Future<AuthorizeCode> authorizeCore() async {
    if (system.isAndroid) {
      return AuthorizeCode.error;
    }
    if (system.isWindows) {
      return await windows?.registerService() ?? AuthorizeCode.error;
    }
    if (hasHelperService) {
      return await linux?.registerService() ?? AuthorizeCode.error;
    }
    if (isAppImage) return AuthorizeCode.error;
    final isAdmin = await checkIsAdmin();
    if (isAdmin) {
      return AuthorizeCode.none;
    }

    if (system.isMacOS) {
      final escapedPath = _shellEscape(appPath.corePath);
      final shell = 'chown root:admin $escapedPath && chmod +sx $escapedPath';
      final arguments = [
        '-e',
        'do shell script "$shell" with administrator privileges',
      ];
      final result = await runProcess('osascript', arguments);
      if (result.exitCode != 0) {
        return AuthorizeCode.error;
      }
      return AuthorizeCode.success;
    } else if (Platform.isLinux) {
      final escapedCorePath = _shellEscape(appPath.corePath);
      try {
        final result = await runProcess('pkexec', [
          '/bin/sh',
          '-c',
          'chown root:root $escapedCorePath && chmod +sx $escapedCorePath',
        ]);
        if (result.exitCode != 0) return AuthorizeCode.error;
      } on ProcessException catch (error) {
        commonPrint.log('pkexec failed: $error', logLevel: LogLevel.error);
        return AuthorizeCode.error;
      }
      return AuthorizeCode.success;
    }
    return AuthorizeCode.error;
  }

  Future<void> back() async {
    await app?.moveTaskToBack();
    await window?.hide();
  }

  Future<void> exit() async {
    if (system.isAndroid) {
      await SystemNavigator.pop();
    }
    window?.forceExit();
  }
}

final system = System();

class Windows {
  static Windows? _instance;
  late DynamicLibrary _shell32;

  Windows._internal() {
    _shell32 = DynamicLibrary.open('shell32.dll');
  }

  factory Windows() {
    _instance ??= Windows._internal();
    return _instance!;
  }

  bool runas(String command, String arguments) {
    final commandPtr = command.toNativeUtf16();
    final argumentsPtr = arguments.toNativeUtf16();
    final operationPtr = 'runas'.toNativeUtf16();

    final shellExecute = _shell32
        .lookupFunction<
          Int32 Function(
            Pointer<Utf16> hwnd,
            Pointer<Utf16> lpOperation,
            Pointer<Utf16> lpFile,
            Pointer<Utf16> lpParameters,
            Pointer<Utf16> lpDirectory,
            Int32 nShowCmd,
          ),
          int Function(
            Pointer<Utf16> hwnd,
            Pointer<Utf16> lpOperation,
            Pointer<Utf16> lpFile,
            Pointer<Utf16> lpParameters,
            Pointer<Utf16> lpDirectory,
            int nShowCmd,
          )
        >('ShellExecuteW');

    final result = shellExecute(
      nullptr,
      operationPtr,
      commandPtr,
      argumentsPtr,
      nullptr,
      1,
    );

    calloc.free(commandPtr);
    calloc.free(argumentsPtr);
    calloc.free(operationPtr);

    commonPrint.log(
      'windows runas: $command $arguments resultCode:$result',
      logLevel: LogLevel.warning,
    );

    if (result <= 32) {
      return false;
    }
    return true;
  }

  Future<AuthorizeCode> registerService() =>
      registerHelperService(() async => runas(appPath.helperPath, 'install'));

  Future<bool> registerTask(String appName) async {
    final taskXml =
        '''
<?xml version="1.0" encoding="UTF-16"?>
<Task version="1.3" xmlns="http://schemas.microsoft.com/windows/2004/02/mit/task">
  <Principals>
    <Principal id="Author">
      <LogonType>InteractiveToken</LogonType>
      <RunLevel>HighestAvailable</RunLevel>
    </Principal>
  </Principals>
  <Triggers>
    <LogonTrigger/>
  </Triggers>
  <Settings>
    <MultipleInstancesPolicy>Parallel</MultipleInstancesPolicy>
    <DisallowStartIfOnBatteries>false</DisallowStartIfOnBatteries>
    <StopIfGoingOnBatteries>false</StopIfGoingOnBatteries>
    <AllowHardTerminate>false</AllowHardTerminate>
    <StartWhenAvailable>false</StartWhenAvailable>
    <RunOnlyIfNetworkAvailable>false</RunOnlyIfNetworkAvailable>
    <IdleSettings>
      <StopOnIdleEnd>false</StopOnIdleEnd>
      <RestartOnIdle>false</RestartOnIdle>
    </IdleSettings>
    <AllowStartOnDemand>true</AllowStartOnDemand>
    <Enabled>true</Enabled>
    <Hidden>false</Hidden>
    <RunOnlyIfIdle>false</RunOnlyIfIdle>
    <WakeToRun>false</WakeToRun>
    <ExecutionTimeLimit>PT72H</ExecutionTimeLimit>
    <Priority>7</Priority>
  </Settings>
  <Actions Context="Author">
    <Exec>
      <Command>"${Platform.resolvedExecutable}"</Command>
    </Exec>
  </Actions>
</Task>''';
    final taskPath = join(await appPath.tempPath, 'task.xml');
    await File(taskPath).create(recursive: true);
    await File(
      taskPath,
    ).writeAsBytes(taskXml.encodeUtf16LeWithBom, flush: true);
    final commandLine = [
      '/Create',
      '/TN',
      appName,
      '/XML',
      '%s',
      '/F',
    ].join(' ');
    return runas('schtasks', commandLine.replaceFirst('%s', taskPath));
  }
}

Future<AuthorizeCode> registerHelperService(
  Future<bool> Function() install, {
  Future<HelperReadiness> Function()? readiness,
}) async {
  final probe = readiness ?? () => helperClient.readiness();
  final status = await probe();
  switch (status) {
    case HelperReadiness.ready:
      commonPrint.log('helper service is ready');
      return AuthorizeCode.none;
    case HelperReadiness.manifestMissing:
      commonPrint.log(
        'Core manifest is missing or invalid; Helper service unavailable, '
        'falling back to direct Core',
        logLevel: LogLevel.warning,
      );
      globalState.showNotifier(currentAppLocalizations.helperCorruptTip);
      return AuthorizeCode.error;
    case HelperReadiness.notReady:
      break;
  }

  commonPrint.log(
    'helper service is unavailable, requesting elevated installation',
    logLevel: LogLevel.warning,
  );
  if (!await install()) {
    commonPrint.log(
      'failed to launch elevated helper installation',
      logLevel: LogLevel.error,
    );
    return AuthorizeCode.error;
  }

  final isRunning = await _waitForHelperService(readiness: readiness);
  commonPrint.log(
    isRunning
        ? 'helper service installation completed'
        : 'helper service did not become ready after installation',
    logLevel: isRunning ? LogLevel.info : LogLevel.error,
  );
  return isRunning ? AuthorizeCode.success : AuthorizeCode.error;
}

Future<bool> _waitForHelperService({
  Future<HelperReadiness> Function()? readiness,
}) async {
  const timeout = Duration(seconds: 6);
  const interval = Duration(seconds: 1);
  const maxAttempts = 6;
  final stopwatch = Stopwatch()..start();
  for (var attempt = 0; attempt < maxAttempts; attempt++) {
    final remaining = timeout - stopwatch.elapsed;
    if (remaining <= Duration.zero) return false;
    final isRunning =
        await (readiness?.call() ??
                helperClient.readiness(timeout: remaining, logFailure: false))
            .timeout(remaining, onTimeout: () => HelperReadiness.notReady) ==
        HelperReadiness.ready;
    if (isRunning) return true;
    final delay = timeout - stopwatch.elapsed;
    if (delay <= Duration.zero || attempt == maxAttempts - 1) return false;
    await Future.delayed(delay < interval ? delay : interval);
  }
  return false;
}

final windows = system.isWindows ? Windows() : null;

class Linux {
  Linux({ProcessRunner? runProcess}) : runProcess = runProcess ?? Process.run;

  final ProcessRunner runProcess;

  Future<AuthorizeCode> registerService() =>
      registerHelperService(() => installService(appPath.helperPath));

  Future<bool> installService(String helperPath) async {
    try {
      final result = await runProcess('pkexec', [helperPath, 'install']);
      if (result.exitCode == 0) return true;
      commonPrint.log(
        'pkexec helper install failed: ${result.exitCode}',
        logLevel: LogLevel.error,
      );
    } on ProcessException catch (error) {
      commonPrint.log('pkexec failed: $error', logLevel: LogLevel.error);
    }
    return false;
  }
}

final linux = system.isLinux && system.hasHelperService ? Linux() : null;

class MacOS implements SystemDnsPort {
  static MacOS? _instance;

  @visibleForTesting
  ProcessRunner runProcess = Process.run;

  MacOS._internal();

  factory MacOS() {
    _instance ??= MacOS._internal();
    return _instance!;
  }

  @visibleForTesting
  static String? parseDefaultInterface(String routeOutput) {
    final deviceLine = routeOutput
        .split('\n')
        .firstWhere((s) => s.contains('interface:'), orElse: () => '');
    final lineSplits = deviceLine.trim().split(' ');
    if (lineSplits.length != 2) {
      return null;
    }
    return lineSplits[1];
  }

  @visibleForTesting
  static String? parseServiceName(String serviceOrderOutput, String device) {
    final currentService = serviceOrderOutput
        .split('\n\n')
        .firstWhere((s) => s.contains('Device: $device'), orElse: () => '');
    if (currentService.isEmpty) {
      return null;
    }
    final nameLine = currentService
        .split('\n')
        .firstWhere(
          (line) => RegExp(r'^\(\d+\).*').hasMatch(line),
          orElse: () => '',
        );
    final name = RegExp(
      r'^\(\d+\)\s+(.+)$',
    ).firstMatch(nameLine.trim())?.group(1)?.trim();
    if (name == null || name.isEmpty) {
      return null;
    }
    return name;
  }

  @visibleForTesting
  static List<String> parseDnsServers(String getDnsServersOutput) {
    final output = getDnsServersOutput.trim();
    if (output.startsWith("There aren't any DNS Servers set on")) {
      return [];
    }
    return output.split('\n');
  }

  @override
  Future<String?> resolveDefaultService() async {
    final result = await _run('route', ['-n', 'get', 'default']);
    if (result == null) {
      return null;
    }
    final device = parseDefaultInterface(result.stdout.toString());
    if (device == null) {
      return null;
    }
    final serviceResult = await _run('networksetup', [
      '-listnetworkserviceorder',
    ]);
    if (serviceResult == null) {
      return null;
    }
    return parseServiceName(serviceResult.stdout.toString(), device);
  }

  @override
  Future<List<String>?> readDnsServers(String service) async {
    final result = await _run('networksetup', ['-getdnsservers', service]);
    if (result == null) {
      return null;
    }
    return parseDnsServers(result.stdout.toString());
  }

  @override
  Future<bool> writeDnsServers(String service, List<String> servers) async {
    final result = await _run('networksetup', [
      '-setdnsservers',
      service,
      if (servers.isEmpty) 'Empty',
      if (servers.isNotEmpty) ...servers,
    ], logLevel: LogLevel.error);
    return result != null;
  }

  Future<ProcessResult?> _run(
    String executable,
    List<String> arguments, {
    LogLevel logLevel = LogLevel.warning,
  }) async {
    final label = '$executable ${arguments.first}';
    try {
      final result = await runProcess(executable, arguments);
      if (result.exitCode != 0) {
        commonPrint.log(
          '$label exited with ${result.exitCode}: ${result.stderr.toString().trim()}',
          logLevel: logLevel,
        );
        return null;
      }
      return result;
    } catch (error) {
      commonPrint.log('$label failed: $error', logLevel: logLevel);
      return null;
    }
  }
}

final macOS = system.isMacOS ? MacOS() : null;

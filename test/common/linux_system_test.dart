import 'dart:io';

import 'package:fl_clash/common/system.dart';
import 'package:fl_clash/core/desktop/helper_client.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('installed Linux uses Helper only when systemd is available', () {
    bool available({bool systemd = true, bool appImage = false}) =>
        System.helperServiceAvailable(
          isWindows: false,
          isLinux: true,
          isAppImage: appImage,
          hasSystemd: systemd,
        );
    expect(available(), isTrue);
    expect(available(systemd: false), isFalse);
    expect(available(appImage: true), isFalse);
    expect(
      System.helperServiceAvailable(
        isWindows: true,
        isLinux: false,
        isAppImage: false,
        hasSystemd: false,
      ),
      isTrue,
    );
    expect(
      System.helperServiceAvailable(
        isWindows: false,
        isLinux: false,
        isAppImage: false,
        hasSystemd: false,
      ),
      isFalse,
    );
  });

  test(
    'Linux authorization passes the executable path literally to pkexec',
    () async {
      const path = "/opt/Feng Wo's/FlClashHelperService";
      final linux = Linux(
        runProcess: (command, arguments) async {
          expect(command, 'pkexec');
          expect(arguments, [path, 'install']);
          return ProcessResult(1, 0, '', '');
        },
      );
      expect(await linux.installService(path), isTrue);
    },
  );

  test('cancelled and missing polkit authorization report failure', () async {
    for (final code in [126, 127]) {
      final linux = Linux(
        runProcess: (_, _) async => ProcessResult(1, code, '', ''),
      );
      expect(await linux.installService('/opt/FlClashHelperService'), isFalse);
    }
    final linux = Linux(
      runProcess: (_, _) async => throw const ProcessException('pkexec', []),
    );
    expect(await linux.installService('/opt/FlClashHelperService'), isFalse);
  });

  test('ready Helper does not prompt for installation again', () async {
    var installations = 0;
    final result = await registerHelperService(() async {
      installations++;
      return true;
    }, readiness: () async => HelperReadiness.ready);
    expect(result, AuthorizeCode.none);
    expect(installations, 0);
  });

  test(
    'successful install must become ready before TUN is authorized',
    () async {
      var probes = 0;
      var installations = 0;
      final result = await registerHelperService(
        () async {
          installations++;
          return true;
        },
        readiness: () async =>
            ++probes == 1 ? HelperReadiness.notReady : HelperReadiness.ready,
      );
      expect(result, AuthorizeCode.success);
      expect(installations, 1);
      expect(probes, 2);
    },
  );

  test('declined installation never reports TUN authorized', () async {
    final result = await registerHelperService(
      () async => false,
      readiness: () async => HelperReadiness.notReady,
    );
    expect(result, AuthorizeCode.error);
  });
}

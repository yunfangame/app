import 'dart:io';

import 'package:fl_clash/common/windows_integrity.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const executable = r'D:\Favorites\蜂窝\FengWo.exe';
  const roaming = r'C:\Users\用户\AppData\Roaming';
  const expectedData = '$roaming\\com.follow\\蜂窝加速器';

  WindowsIntegritySnapshot? inspect(int rid) => verifyWindowsStartupIntegrity(
    isWindows: true,
    readIntegrityRid: () => rid,
    executablePath: () => executable,
    roamingDirectory: () => roaming,
  );

  test(
    'other platforms skip every Windows dependency and filesystem lookup',
    () {
      Never unexpected() => throw StateError('Windows dependency accessed');
      expect(
        verifyWindowsStartupIntegrity(
          isWindows: false,
          readIntegrityRid: unexpected,
          executablePath: unexpected,
          roamingDirectory: unexpected,
        ),
        isNull,
      );
    },
  );

  for (final rid in [0, 1, 4095, 4096, 8191]) {
    test('RID $rid blocks startup with actionable diagnostic context', () {
      expect(
        () => inspect(rid),
        throwsA(
          isA<WindowsIntegrityException>()
              .having((e) => e.isRestricted, 'restricted', isTrue)
              .having((e) => e.code, 'code', 'WIN-INTEGRITY-LOW')
              .having((e) => e.snapshot.rid, 'actual RID', rid)
              .having((e) => e.snapshot.executablePath, 'exe', executable)
              .having(
                (e) => e.snapshot.dataDirectoryCandidate,
                'data',
                expectedData,
              )
              .having((e) => e.toString(), 'copy details', contains(executable))
              .having((e) => e.toString(), 'copy data', contains(expectedData))
              .having((e) => e.recovery, 'recovery', contains('重新运行安装程序')),
        ),
      );
    });
  }

  for (final entry in {
    8192: '中（Medium）',
    8448: '中增强（Medium Plus）',
    12288: '高（High）',
    16384: '系统（System）',
    20480: '受保护（Protected）',
  }.entries) {
    test(
      'RID ${entry.key} permits startup without requiring administrator',
      () {
        final snapshot = inspect(entry.key)!;
        expect(snapshot.rid, entry.key);
        expect(snapshot.label, entry.value);
        expect(snapshot.executablePath, executable);
        expect(snapshot.dataDirectoryCandidate, expectedData);
        expect(snapshot.diagnosticFields['integrity_rid'], entry.key);
        expect(snapshot.diagnosticFields['integrity_label'], entry.value);
      },
    );
  }

  for (final entry in {
    5: 'WIN-INTEGRITY-QUERY-DENIED',
    87: 'WIN-INTEGRITY-QUERY-FAILED',
    122: 'WIN-INTEGRITY-QUERY-FAILED',
  }.entries) {
    test('Win32 failure ${entry.key} stops with exact code and operation', () {
      expect(
        () => verifyWindowsStartupIntegrity(
          isWindows: true,
          readIntegrityRid: () => throw WindowsIntegrityQueryException(
            'GetTokenInformation.read',
            entry.key,
          ),
          executablePath: () => executable,
          roamingDirectory: () => roaming,
        ),
        throwsA(
          isA<WindowsIntegrityException>()
              .having((e) => e.code, 'code', entry.value)
              .having((e) => e.systemError, 'Win32 code', entry.key)
              .having(
                (e) => e.operation,
                'operation',
                'GetTokenInformation.read',
              )
              .having((e) => e.snapshot.rid, 'unknown RID', isNull)
              .having(
                (e) => e.isRestricted,
                'no unsupported low diagnosis',
                isFalse,
              )
              .having((e) => e.snapshot.label, 'unknown level', '未能读取'),
        ),
      );
    });
  }

  test(
    'binding failure does not claim a low token or expose arbitrary errors',
    () {
      expect(
        () => verifyWindowsStartupIntegrity(
          isWindows: true,
          readIntegrityRid: () => throw StateError('secret-do-not-copy'),
          executablePath: () => executable,
          roamingDirectory: () => roaming,
        ),
        throwsA(
          isA<WindowsIntegrityException>()
              .having((e) => e.code, 'code', 'WIN-INTEGRITY-QUERY-FAILED')
              .having((e) => e.errorType, 'type', 'StateError')
              .having(
                (e) => e.toString(),
                'safe details',
                isNot(contains('secret-do-not-copy')),
              ),
        ),
      );
    },
  );

  test('invalid RID cannot be accepted as elevated', () {
    for (final rid in [-1, 0x100000000]) {
      expect(
        () => inspect(rid),
        throwsA(
          isA<WindowsIntegrityException>()
              .having((e) => e.code, 'code', 'WIN-INTEGRITY-QUERY-FAILED')
              .having((e) => e.systemError, 'invalid data', 13),
        ),
      );
    }
  });

  test(
    'missing APPDATA is reported without guessing or creating directories',
    () {
      final snapshot = verifyWindowsStartupIntegrity(
        isWindows: true,
        readIntegrityRid: () => 8192,
        executablePath: () => executable,
        roamingDirectory: () => null,
      )!;
      expect(snapshot.dataDirectoryCandidate, isNull);
      expect(snapshot.details, contains('未设置 APPDATA'));
    },
  );

  test(
    'native Win32 token query returns the current process integrity',
    () {
      final rid = readCurrentWindowsIntegrityRid();
      expect(rid, greaterThanOrEqualTo(0));
      expect(rid, lessThanOrEqualTo(0xffffffff));
      final whoami = Process.runSync(
        '${Platform.environment['SystemRoot']}\\System32\\whoami.exe',
        ['/groups', '/fo', 'csv', '/nh'],
      );
      expect(whoami.exitCode, 0);
      final integritySids = RegExp(
        r'S-1-16-(\d+)',
      ).allMatches(whoami.stdout as String).toList();
      expect(integritySids, hasLength(1));
      expect(rid, int.parse(integritySids.single.group(1)!));
      if (rid >= windowsMediumIntegrityRid) {
        final snapshot = verifyWindowsStartupIntegrity()!;
        expect(snapshot.rid, rid);
        expect(snapshot.executablePath, Platform.resolvedExecutable);
        expect(snapshot.dataDirectoryCandidate, contains('com.follow'));
      } else {
        expect(
          verifyWindowsStartupIntegrity,
          throwsA(
            isA<WindowsIntegrityException>().having(
              (e) => e.snapshot.rid,
              'RID',
              rid,
            ),
          ),
        );
      }
    },
    skip: !Platform.isWindows,
  );
}

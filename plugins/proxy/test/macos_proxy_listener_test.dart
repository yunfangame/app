import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:proxy/src/macos_proxy.dart';
import 'package:proxy/src/proxy_command.dart';

void main() {
  for (final address in [
    InternetAddress.loopbackIPv4,
    InternetAddress.loopbackIPv6,
  ]) {
    test(
      'native listener guard preserves ${address.address}',
      () async {
        final listener = await ServerSocket.bind(
          address,
          0,
          v6Only: address.type == InternetAddressType.IPv6,
        );
        var inspections = 0;
        final proxy = MacosProxy(
          commandRunner: ProxyCommandRunner((
            executable,
            arguments, {
            runInShell = false,
          }) async {
            expect(executable, '/usr/sbin/lsof');
            expect(arguments, [
              '-nP',
              '-a',
              '-iTCP:${listener.port}',
              '-sTCP:LISTEN',
              '-Fp',
            ]);
            inspections++;
            return Process.run(executable, arguments, runInShell: runInShell);
          }),
        );
        try {
          final result = await proxy.repairStaleDetailed(listener.port);
          expect(result.success, isTrue);
          expect(result.stage, 'skipped_active_listener');
          expect(result.writeSkipped, isTrue);
          expect(inspections, 1);
        } finally {
          await listener.close();
        }
      },
      skip: !Platform.isMacOS,
    );
  }
}

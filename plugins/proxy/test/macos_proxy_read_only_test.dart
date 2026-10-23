import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:proxy/src/macos_proxy.dart';
import 'package:proxy/src/proxy_command.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'real read-only inspection agrees with a simulated WPAD getter failure',
    () async {
      var fallbackReads = 0;

      Future<ProcessResult> run(
        String executable,
        List<String> arguments, {
        bool runInShell = false,
        bool simulateFailure = false,
      }) async {
        expect(runInShell, isFalse);
        if (executable == '/usr/sbin/networksetup') {
          expect(arguments.first, matches(RegExp(r'^-(get|list)')));
          if (simulateFailure && arguments.first == '-getproxyautodiscovery') {
            return ProcessResult(
              0,
              4,
              '** Error: The parameters were not valid.\n',
              '',
            );
          }
        } else if (executable == '/usr/bin/plutil') {
          expect(arguments.take(4), [
            '-extract',
            'NetworkServices',
            'json',
            '-o',
          ]);
          expect(arguments[4], '-');
          fallbackReads++;
        } else if (executable == '/bin/sh') {
          expect(arguments[1], contains("printf 'show "));
          expect(arguments[1], endsWith("\\nquit\\n' | /usr/sbin/scutil"));
          expect(arguments[1], isNot(contains('set ')));
        } else {
          expect(executable, '/sbin/route');
          expect(arguments, ['-n', 'get', 'default']);
        }
        return Process.run(executable, arguments);
      }

      final baseline = await MacosProxy(
        commandRunner: ProxyCommandRunner(run),
        verificationAttempts: 1,
      ).inspectDetailed(65534);
      expect(baseline.stage, isNot('readback'));
      expect(baseline.connectionName, isNotNull);

      final fallback = await MacosProxy(
        commandRunner: ProxyCommandRunner(
          (executable, arguments, {runInShell = false}) => run(
            executable,
            arguments,
            runInShell: runInShell,
            simulateFailure: true,
          ),
        ),
        verificationAttempts: 1,
      ).inspectDetailed(65534);

      expect(fallbackReads, 1);
      expect(fallback.fallbackUsed, isTrue);
      expect(fallback.command, isNull);
      expect(fallback.success, baseline.success);
      expect(fallback.stage, baseline.stage);
      expect(fallback.connectionName, baseline.connectionName);
      expect(fallback.enabled, baseline.enabled);
      expect(fallback.automaticProxyEnabled, baseline.automaticProxyEnabled);
      expect(fallback.server, baseline.server);
    },
    skip:
        !Platform.isMacOS ||
        Platform.environment['FENGWO_MACOS_PROXY_READ_ONLY_TEST'] != '1',
  );
}

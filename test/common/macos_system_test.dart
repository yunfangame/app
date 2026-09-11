import 'package:fl_clash/common/system.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('setuid Core checks', () {
    test('passes paths with spaces to stat unchanged', () {
      const path = '/Users/a b/FlClash.app/Contents/MacOS/FlClashCore';
      final arguments = System.statArguments(path, isMacOS: true);

      expect(arguments, ['-f', '%Su:%Sg %Sp', path]);
      expect(arguments.last, isNot(contains(r'\')));
    });

    test('accepts only a root-owned setuid Core', () {
      expect(
        System.isPrivilegedStatOutput(
          'root:admin -rwsr-sr-x',
          ownerPrefix: 'root:admin',
        ),
        isTrue,
      );
      expect(
        System.isPrivilegedStatOutput(
          'root:admin -rwxr-xr-x',
          ownerPrefix: 'root:admin',
        ),
        isFalse,
      );
    });

    test('grants inheriting access without changing ownership', () {
      const path = '/Users/a b/Library/Application Support/com.follow.clash';
      final arguments = System.aclArguments(path, 'alice');

      expect(arguments.first, '-R');
      expect(arguments[1], '+a');
      expect(arguments[2], startsWith('user:alice allow '));
      expect(arguments[2], isNot(contains('chown')));
      expect(arguments.last, path);
    });
  });

  group('macOS network parsing', () {
    test('resolves the default interface and a service name with spaces', () {
      const route = 'destination: default\n  interface: en0\n';
      const order = '''
(1) Thunderbolt Bridge
(Hardware Port: Thunderbolt Bridge, Device: en0)
''';

      expect(MacOS.parseDefaultInterface(route), 'en0');
      expect(MacOS.parseServiceName(order, 'en0'), 'Thunderbolt Bridge');
    });

    test('maps an empty DNS setup back to DHCP', () {
      expect(
        MacOS.parseDnsServers("There aren't any DNS Servers set on Wi-Fi."),
        isEmpty,
      );
      expect(MacOS.parseDnsServers('1.1.1.1\n8.8.8.8\n'), [
        '1.1.1.1',
        '8.8.8.8',
      ]);
    });
  });
}

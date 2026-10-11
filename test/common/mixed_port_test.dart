import 'package:fl_clash/common/mixed_port.dart';
import 'package:fl_clash/models/clash_config.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Windows and Mac share the independent desktop default', () {
    expect(defaultMixedPortForPlatform(isWindows: true, isMacOS: false), 17980);
    expect(defaultMixedPortForPlatform(isWindows: false, isMacOS: true), 17980);
  });

  test('mobile and other platforms keep the original default', () {
    expect(defaultMixedPortForPlatform(isWindows: false, isMacOS: false), 7890);
    expect(const PatchClashConfig().mixedPort, defaultMixedPort);
  });
}

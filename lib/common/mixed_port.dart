import 'dart:io';

import 'package:fl_clash/models/clash_config.dart';

const desktopDefaultMixedPort = 17980;

int defaultMixedPortForPlatform({bool? isWindows, bool? isMacOS}) {
  return (isWindows ?? Platform.isWindows) || (isMacOS ?? Platform.isMacOS)
      ? desktopDefaultMixedPort
      : defaultMixedPort;
}

import 'dart:io';

import 'package:fl_clash/common/api_health.dart';

Future<void> main() async {
  final snapshot = await ApiHealthService().check();
  stdout.writeln(
    'total=${snapshot.total} reachable=${snapshot.reachableCount} '
    'percentage=${snapshot.percentage}',
  );
  for (final endpoint in snapshot.endpoints) {
    stdout.writeln(
      '${endpoint.endpoint} reachable=${endpoint.reachable} '
      'latency=${endpoint.latency.inMilliseconds}ms',
    );
  }
  if (snapshot.total == 0) {
    stderr.writeln('error=${snapshot.error}');
    exitCode = 1;
  }
}

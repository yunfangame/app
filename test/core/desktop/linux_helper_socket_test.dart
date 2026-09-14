import 'dart:convert';
import 'dart:io';

import 'package:fl_clash/common/constant.dart';
import 'package:fl_clash/core/desktop/helper_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  test(
    'Helper ping and session commands travel over Unix socket',
    () async {
      final directory = await Directory('/tmp').createTemp('fw-helper-');
      final socket = '${directory.path}/helper.sock';
      final server = await HttpServer.bind(
        InternetAddress(socket, type: InternetAddressType.unix),
        0,
      );
      const helperPath = '/opt/Feng Wo/FlClashHelperService';
      const hash =
          '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef';
      const session = '0123456789abcdef0123456789abcdef';
      final received = <String>[];
      final listener = server.listen((request) async {
        received.add(request.uri.path);
        request.response.headers.set(
          helperProtocolVersionHeader,
          helperProtocolVersion,
        );
        if (request.uri.path == '/ping') {
          expect(request.uri.queryParameters['coreSha256'], hash);
          request.response.write(helperPath);
        } else {
          final body =
              jsonDecode(await utf8.decoder.bind(request).join()) as Map;
          expect(body['sessionId'], session);
          request.response.headers.contentType = ContentType.json;
          request.response.write(
            jsonEncode({
              'sessionId': session,
              if (request.uri.path == '/start')
                'pid': 1234
              else
                'stopped': true,
            }),
          );
        }
        await request.response.close();
      });
      try {
        final client = HelperClient(
          socketPath: socket,
          pathContext: p.Context(style: p.Style.posix),
          expectedHelperPath: () => helperPath,
          readCoreSha256: () async => hash,
        );
        expect(await client.readiness(), HelperReadiness.ready);
        expect(
          (await client.start(
            address: '/tmp/FlClashSocket_1234.sock',
            sessionId: session,
          )).pid,
          1234,
        );
        expect((await client.stop(session)).stopped, isTrue);
        expect(received, ['/ping', '/start', '/stop']);
      } finally {
        await server.close(force: true);
        await listener.cancel();
        await directory.delete(recursive: true);
      }
    },
    skip: Platform.isWindows,
  );
}

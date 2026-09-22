import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:fl_clash/common/windows_tls_trust.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('non-Windows does not load assets or change trust', () async {
    final trust = WindowsTlsTrust(
      isWindows: false,
      loadAsset: (_) => throw StateError('Must not load'),
      context: () => throw StateError('Must not touch context'),
    );
    expect(await trust.initialize(), 0);
  });

  test('packaged public roots match pinned fingerprints', () async {
    final trust = WindowsTlsTrust(
      isWindows: true,
      context: () => SecurityContext(withTrustedRoots: false),
    );
    expect(await trust.initialize(), windowsSupplementalRoots.length);
    for (final root in windowsSupplementalRoots) {
      final asset = await rootBundle.load(root.asset);
      expect(
        sha256.convert(asset.buffer.asUint8List()).toString(),
        root.sha256Hex,
      );
    }
  });

  test('concurrent initialization loads each certificate once', () async {
    var loadCount = 0;
    final trust = WindowsTlsTrust(
      isWindows: true,
      loadAsset: (asset) async {
        loadCount++;
        return File(asset).readAsBytes();
      },
      context: () => SecurityContext(withTrustedRoots: false),
    );
    final first = trust.initialize();
    expect(identical(first, trust.initialize()), isTrue);
    await first;
    await trust.initialize();
    expect(loadCount, windowsSupplementalRoots.length);
  });

  test('integrity failure cannot modify trust', () async {
    var contextRequested = false;
    final trust = WindowsTlsTrust(
      isWindows: true,
      loadAsset: (asset) async => Uint8List.fromList([1, 2, 3]),
      context: () {
        contextRequested = true;
        return SecurityContext(withTrustedRoots: false);
      },
    );
    await expectLater(trust.initialize(), throwsFormatException);
    expect(contextRequested, isFalse);
  });

  test('missing bundle cannot modify trust', () async {
    final trust = WindowsTlsTrust(
      isWindows: true,
      loadAsset: (_) async => throw const FileSystemException('Missing asset'),
      context: () => throw StateError('Must not touch context'),
    );
    await expectLater(trust.initialize(), throwsA(isA<FileSystemException>()));
  });

  test('missing issuer fails before supplement and succeeds after', () async {
    final context = SecurityContext(withTrustedRoots: false);
    final server = await _server('valid_a');
    await expectLater(
      _request(server, context),
      throwsA(isA<HandshakeException>()),
    );
    await _supplement(context, 'root_a');
    expect(await _request(server, context), [42]);
  });

  test('supplementing a root preserves previously trusted roots', () async {
    final context = SecurityContext(withTrustedRoots: false);
    await _supplement(context, 'root_b');
    final firstServer = await _server('valid_a');
    final secondServer = await _server('valid_b');
    expect(await _request(secondServer, context), [42]);
    await _supplement(context, 'root_a');
    expect(await _request(firstServer, context), [42]);
    expect(await _request(secondServer, context), [42]);
  });

  for (final certificate in ['wrong_host', 'expired', 'valid_b']) {
    test('supplement still rejects $certificate', () async {
      final context = SecurityContext(withTrustedRoots: false);
      await _supplement(context, 'root_a');
      final server = await _server(certificate);
      await expectLater(
        _request(server, context),
        throwsA(isA<HandshakeException>()),
      );
    });
  }
}

Future<Uint8List> _fixture(String name) =>
    File('test/fixtures/tls/$name').readAsBytes();

Future<void> _supplement(SecurityContext context, String name) async {
  final bytes = await _fixture('$name.der');
  await WindowsTlsTrust(
    isWindows: true,
    roots: [
      WindowsTrustedRoot(
        asset: name,
        sha256Hex: sha256.convert(bytes).toString(),
      ),
    ],
    loadAsset: (_) async => bytes,
    context: () => context,
  ).initialize();
}

Future<SecureServerSocket> _server(String name) async {
  final context = SecurityContext(withTrustedRoots: false)
    ..useCertificateChainBytes(await _fixture('$name.pem'))
    ..usePrivateKeyBytes(await _fixture('${name}_test_key.pem'));
  final server = await SecureServerSocket.bind(
    InternetAddress.loopbackIPv4,
    0,
    context,
  );
  final sockets = <SecureSocket>[];
  final subscription = server.listen((socket) {
    sockets.add(socket);
    socket.add([42]);
    unawaited(socket.flush().catchError((Object _) {}));
  }, onError: (Object _) {});
  addTearDown(() async {
    for (final socket in sockets) {
      socket.destroy();
    }
    await subscription.cancel();
    await server.close();
  });
  return server;
}

Future<List<int>> _request(
  SecureServerSocket server,
  SecurityContext context,
) async {
  final socket = await SecureSocket.connect(
    InternetAddress.loopbackIPv4,
    server.port,
    context: context,
    timeout: const Duration(seconds: 3),
  );
  try {
    return await socket.first.timeout(const Duration(seconds: 3));
  } finally {
    socket.destroy();
  }
}

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';

class WindowsTrustedRoot {
  const WindowsTrustedRoot({required this.asset, required this.sha256Hex});

  final String asset;
  final String sha256Hex;
}

const windowsSupplementalRoots = [
  WindowsTrustedRoot(
    asset: 'assets/certificates/certum_trusted_network_ca.der',
    sha256Hex:
        '5c58468d55f58e497e743982d2b50010b6d165374acf83a7d4a32db768c4408e',
  ),
  WindowsTrustedRoot(
    asset: 'assets/certificates/isrg_root_x1.der',
    sha256Hex:
        '96bcec06264976f37460779acf28c5a7cfe8a3c0aae11a8ffcee05c0bddf08c6',
  ),
];

class WindowsTlsTrust {
  WindowsTlsTrust({
    bool? isWindows,
    Future<Uint8List> Function(String)? loadAsset,
    SecurityContext Function()? context,
    this.roots = windowsSupplementalRoots,
  }) : _isWindows = isWindows ?? Platform.isWindows,
       _loadAsset = loadAsset ?? _loadBundledAsset,
       _context = context ?? (() => SecurityContext.defaultContext);

  final bool _isWindows;
  final Future<Uint8List> Function(String) _loadAsset;
  final SecurityContext Function() _context;
  final List<WindowsTrustedRoot> roots;
  Future<int>? _initialization;

  Future<int> initialize() => _initialization ??= _initialize();

  Future<int> _initialize() async {
    if (!_isWindows) return 0;
    final certificates = <Uint8List>[];
    for (final root in roots) {
      final bytes = await _loadAsset(root.asset);
      if (sha256.convert(bytes).toString() != root.sha256Hex) {
        throw const FormatException('Bundled TLS root integrity mismatch');
      }
      certificates.add(bytes);
    }
    final context = _context();
    for (final certificate in certificates) {
      final encoded = base64.encode(certificate);
      final lines = RegExp('.{1,64}').allMatches(encoded).map((m) => m[0]!);
      context.setTrustedCertificatesBytes(
        utf8.encode(
          '-----BEGIN CERTIFICATE-----\n${lines.join('\n')}\n'
          '-----END CERTIFICATE-----\n',
        ),
      );
    }
    return certificates.length;
  }

  static Future<Uint8List> _loadBundledAsset(String asset) async {
    final data = await rootBundle.load(asset);
    return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  }
}

final windowsTlsTrust = WindowsTlsTrust();

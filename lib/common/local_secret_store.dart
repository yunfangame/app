import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

const macOsFileSecretStorageEnabled = bool.fromEnvironment(
  'MACOS_FILE_SECRET_STORAGE',
);

abstract interface class SecretStringStore {
  Future<String?> read(String key);

  Future<void> write(String key, String value);

  Future<void> delete(String key);
}

class FlutterSecureSecretStringStore implements SecretStringStore {
  FlutterSecureSecretStringStore({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);

  @override
  Future<void> delete(String key) => _storage.delete(key: key);
}

class EncryptedFileSecretStringStore implements SecretStringStore {
  EncryptedFileSecretStringStore({
    Future<Directory> Function()? directoryLoader,
    Random? random,
  }) : _directoryLoader = directoryLoader ?? _defaultDirectory,
       _random = random ?? Random.secure();

  static final _masterKeyFutures = <String, Future<SecretKey>>{};
  static final _algorithm = AesGcm.with256bits();

  final Future<Directory> Function() _directoryLoader;
  final Random _random;

  @override
  Future<String?> read(String key) async {
    final directory = await _loadDirectory();
    final file = _valueFile(directory, key);
    if (!await file.exists()) return null;
    final payload = base64Url.decode((await file.readAsString()).trim());
    final secretBox = SecretBox.fromConcatenation(
      payload,
      nonceLength: _algorithm.nonceLength,
      macLength: _algorithm.macAlgorithm.macLength,
    );
    final clearBytes = await _algorithm.decrypt(
      secretBox,
      secretKey: await _loadMasterKey(directory),
      aad: utf8.encode(key),
    );
    return utf8.decode(clearBytes);
  }

  @override
  Future<void> write(String key, String value) async {
    final directory = await _loadDirectory();
    final secretBox = await _algorithm.encrypt(
      utf8.encode(value),
      secretKey: await _loadMasterKey(directory),
      nonce: _randomBytes(_algorithm.nonceLength),
      aad: utf8.encode(key),
    );
    await _writeAtomically(
      _valueFile(directory, key),
      utf8.encode(base64UrlEncode(secretBox.concatenation())),
    );
  }

  @override
  Future<void> delete(String key) async {
    final directory = await _loadDirectory();
    final file = _valueFile(directory, key);
    if (await file.exists()) await file.delete();
  }

  Future<Directory> _loadDirectory() async {
    final directory = await _directoryLoader();
    await directory.create(recursive: true);
    await _protect(directory.path, directory: true);
    return directory;
  }

  Future<SecretKey> _loadMasterKey(Directory directory) {
    return _masterKeyFutures.putIfAbsent(
      directory.absolute.path,
      () => _readOrCreateMasterKey(directory),
    );
  }

  Future<SecretKey> _readOrCreateMasterKey(Directory directory) async {
    final file = File(p.join(directory.path, '.master-key'));
    if (await file.exists()) {
      return SecretKey(base64Url.decode((await file.readAsString()).trim()));
    }
    final bytes = _randomBytes(32);
    await _writeAtomically(file, utf8.encode(base64UrlEncode(bytes)));
    return SecretKey(bytes);
  }

  File _valueFile(Directory directory, String key) {
    final digest = sha256.convert(utf8.encode(key)).toString();
    return File(p.join(directory.path, '$digest.secret'));
  }

  List<int> _randomBytes(int length) =>
      List<int>.generate(length, (_) => _random.nextInt(256), growable: false);

  Future<void> _writeAtomically(File file, List<int> bytes) async {
    final suffix = _random.nextInt(0x7fffffff).toRadixString(16);
    final temporary = File('${file.path}.$pid.$suffix.tmp');
    try {
      await temporary.writeAsBytes(bytes, flush: true);
      await _protect(temporary.path);
      await temporary.rename(file.path);
      await _protect(file.path);
    } finally {
      if (await temporary.exists()) await temporary.delete();
    }
  }

  Future<void> _protect(String path, {bool directory = false}) async {
    if (!Platform.isMacOS && !Platform.isLinux) return;
    final result = await Process.run('chmod', [
      directory ? '700' : '600',
      path,
    ]);
    if (result.exitCode != 0) {
      throw FileSystemException('Unable to protect local secret storage', path);
    }
  }

  static Future<Directory> _defaultDirectory() async {
    final support = await getApplicationSupportDirectory();
    return Directory(p.join(support.path, '.secure-storage'));
  }
}

SecretStringStore createPlatformSecretStringStore({
  FlutterSecureStorage? secureStorage,
  Future<Directory> Function()? directoryLoader,
}) {
  if (Platform.isMacOS && (kDebugMode || macOsFileSecretStorageEnabled)) {
    return EncryptedFileSecretStringStore(directoryLoader: directoryLoader);
  }
  return FlutterSecureSecretStringStore(storage: secureStorage);
}

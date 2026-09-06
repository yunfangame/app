import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:fl_clash/common/local_secret_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('encrypted file store persists values without plaintext', () async {
    final directory = await Directory.systemTemp.createTemp(
      'fengwo-secret-store-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final store = EncryptedFileSecretStringStore(
      directoryLoader: () async => directory,
      random: Random(17),
    );

    await store.write('account.token', 'sensitive-token-value');

    expect(await store.read('account.token'), 'sensitive-token-value');
    final contents = await Future.wait(
      directory.listSync().whereType<File>().map((file) => file.readAsString()),
    );
    expect(contents.join('\n'), isNot(contains('sensitive-token-value')));
  });

  test('encrypted file store separates keys and deletes values', () async {
    final directory = await Directory.systemTemp.createTemp(
      'fengwo-secret-store-delete-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final store = EncryptedFileSecretStringStore(
      directoryLoader: () async => directory,
      random: Random(29),
    );

    await store.write('first', 'same-value');
    await store.write('second', 'same-value');
    expect(await store.read('first'), 'same-value');
    expect(await store.read('second'), 'same-value');

    await store.delete('first');
    expect(await store.read('first'), isNull);
    expect(await store.read('second'), 'same-value');
  });

  test('failed master key load can recover without restarting', () async {
    final directory = await Directory.systemTemp.createTemp(
      'fengwo-secret-store-recovery-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final master = File('${directory.path}/.master-key');
    await master.writeAsString('not base64!');
    final store = EncryptedFileSecretStringStore(
      directoryLoader: () async => directory,
      random: Random(41),
    );

    await expectLater(store.write('password', 'first'), throwsFormatException);
    expect(await master.readAsString(), 'not base64!');
    await master.writeAsString(base64UrlEncode(List.filled(32, 7)));

    await store.write('password', 'recovered');
    expect(await store.read('password'), 'recovered');
  });

  test('invalid master key length is not cached or replaced', () async {
    final directory = await Directory.systemTemp.createTemp(
      'fengwo-secret-store-key-length-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final master = File('${directory.path}/.master-key');
    final invalidKey = base64UrlEncode(List.filled(16, 7));
    await master.writeAsString(invalidKey);
    final store = EncryptedFileSecretStringStore(
      directoryLoader: () async => directory,
      random: Random(53),
    );

    await expectLater(store.write('password', 'first'), throwsFormatException);
    expect(await master.readAsString(), invalidKey);
    await master.writeAsString(base64UrlEncode(List.filled(32, 11)));

    final recreated = EncryptedFileSecretStringStore(
      directoryLoader: () async => directory,
    );
    await recreated.write('password', 'recovered');
    expect(await store.read('password'), 'recovered');
  });

  test('concurrent failed master key loads can both recover', () async {
    final directory = await Directory.systemTemp.createTemp(
      'fengwo-secret-store-concurrent-recovery-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final master = File('${directory.path}/.master-key');
    await master.writeAsString('not base64!');
    final first = EncryptedFileSecretStringStore(
      directoryLoader: () async => directory,
    );
    final second = EncryptedFileSecretStringStore(
      directoryLoader: () async => directory,
    );

    await Future.wait([
      expectLater(first.write('first', 'one'), throwsFormatException),
      expectLater(second.write('second', 'two'), throwsFormatException),
    ]);
    await master.writeAsString(base64UrlEncode(List.filled(32, 13)));

    await Future.wait([
      first.write('first', 'one'),
      second.write('second', 'two'),
    ]);
    expect(await first.read('first'), 'one');
    expect(await second.read('second'), 'two');
  });
}

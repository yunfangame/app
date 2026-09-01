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
}

import 'dart:io';
import 'dart:typed_data';

import 'package:fl_clash/common/profile_file_write.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory directory;
  late File file;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('profile-file-write-');
    file = File('${directory.path}/profile.yaml');
    await file.writeAsBytes([1, 2, 3]);
  });

  tearDown(() => directory.delete(recursive: true));

  test(
    'a committed write registers its exact content with the owner',
    () async {
      final scope = ProfileFileWriteScope(file.path);
      addTearDown(scope.dispose);
      await scope.run(
        () => writeProfileFileBytes(file, Uint8List.fromList([4, 5, 6])),
      );
      expect(scope.ownsReceipt, isTrue);
      expect(scope.receipt!.path, file.path);
      expect(scope.receipt!.bytes, [4, 5, 6]);
      expect(await file.readAsBytes(), [4, 5, 6]);
      expect(directory.listSync(), hasLength(1));
    },
  );

  test(
    'a later writer supersedes a receipt even with identical bytes',
    () async {
      final scope = ProfileFileWriteScope(file.path);
      addTearDown(scope.dispose);
      final bytes = Uint8List.fromList([4, 5, 6]);
      await scope.run(() => writeProfileFileBytes(file, bytes));
      await writeProfileFileBytes(file, bytes);
      expect(scope.ownsReceipt, isFalse);
      expect(scope.hasForeignWrite, isTrue);
    },
  );

  test(
    'concurrent writers commit in submission order with matching owners',
    () async {
      final first = ProfileFileWriteScope(file.path);
      final second = ProfileFileWriteScope(file.path);
      addTearDown(first.dispose);
      addTearDown(second.dispose);
      final writingFirst = first.run(
        () => writeProfileFileBytes(file, Uint8List.fromList([4, 5, 6])),
      );
      final writingSecond = second.run(
        () => writeProfileFileBytes(file, Uint8List.fromList([7, 8, 9])),
      );
      await Future.wait([writingFirst, writingSecond]);
      expect(await file.readAsBytes(), [7, 8, 9]);
      expect(first.ownsReceipt, isFalse);
      expect(second.ownsReceipt, isTrue);
    },
  );

  test('failed atomic commit does not claim file ownership', () async {
    final scope = ProfileFileWriteScope(file.path);
    addTearDown(scope.dispose);
    await scope.run(
      () => writeProfileFileBytes(file, Uint8List.fromList([4, 5, 6])),
    );
    final accepted = scope.receipt;
    await file.delete();
    await Directory(file.path).create();
    await expectLater(
      writeProfileFileBytes(file, Uint8List.fromList([7, 8, 9])),
      throwsA(isA<FileSystemException>()),
    );
    expect(scope.receipt, same(accepted));
    expect(scope.ownsReceipt, isTrue);
    expect(scope.hasForeignWrite, isFalse);
  });

  for (final restoreFirst in [false, true]) {
    test(
      'restore and new write share one commit owner ($restoreFirst)',
      () async {
        final scope = ProfileFileWriteScope(file.path);
        addTearDown(scope.dispose);
        final candidate = Uint8List.fromList([4, 5, 6]);
        await scope.run(() => writeProfileFileBytes(file, candidate));
        Future<void> restore() => restoreProfileFileBytes(
          file,
          Uint8List.fromList([1, 2, 3]),
          expectedBytes: candidate,
          isCurrent: () => scope.ownsReceipt,
        );
        Future<void> writeNew() => writeProfileFileBytes(file, candidate);
        await Future.wait(
          restoreFirst ? [restore(), writeNew()] : [writeNew(), restore()],
        );
        expect(await file.readAsBytes(), candidate);
        expect(scope.hasForeignWrite, isTrue);
      },
    );
  }

  test('queued write rechecks intent before committing', () async {
    var current = true;
    final first = writeProfileFileBytes(file, Uint8List.fromList([4, 5, 6]));
    final queued = writeProfileFileBytes(
      file,
      Uint8List.fromList([7, 8, 9]),
      isCurrent: () => current,
    );
    final rejected = expectLater(queued, throwsStateError);
    current = false;
    await first;
    await rejected;
    expect(await file.readAsBytes(), [4, 5, 6]);
  });

  test('a stale write preserves the accepted file without a receipt', () async {
    final scope = ProfileFileWriteScope(file.path);
    addTearDown(scope.dispose);
    await expectLater(
      scope.run(
        () => writeProfileFileBytes(
          file,
          Uint8List.fromList([4, 5, 6]),
          isCurrent: () => false,
        ),
      ),
      throwsStateError,
    );
    expect(await file.readAsBytes(), [1, 2, 3]);
    expect(scope.receipt, isNull);
    expect(directory.listSync(), hasLength(1));
  });

  test(
    'disposed scopes release their receipt and receive no new writes',
    () async {
      final scope = ProfileFileWriteScope(file.path);
      await scope.run(
        () => writeProfileFileBytes(file, Uint8List.fromList([4, 5, 6])),
      );
      scope.dispose();
      await writeProfileFileBytes(file, Uint8List.fromList([7, 8, 9]));
      expect(scope.receipt, isNull);
      expect(scope.ownsReceipt, isFalse);
      expect(scope.hasForeignWrite, isFalse);
    },
  );
}

@TestOn('browser')
library;

import 'dart:typed_data';

import 'package:collection/collection.dart';
import 'package:powersync_core/src/attachments/storage/web_opfs_storage.dart';
import 'package:test/test.dart';

void main() {
  group('OpfsLocalStorage', () {
    late OpfsLocalStorage storage;

    setUp(() async {
      storage = OpfsLocalStorage(
          'dart-test-${DateTime.now().millisecondsSinceEpoch}');
      await storage.initialize();
    });

    tearDown(() async {
      await storage.clear();
    });

    group('saveFile and readFile', () {
      test('saves and reads binary data successfully', () async {
        const filePath = 'test_file';
        final data = Uint8List.fromList([1, 2, 3, 4, 5]);
        final size = await storage.saveFile(filePath, Stream.value(data));
        expect(size, equals(data.length));

        final resultStream = storage.readFile(filePath);
        final result = await resultStream.toList();
        expect(result, equals([data]));
      });

      test('throws when reading non-existent file', () async {
        const filePath = 'non_existent';
        expect(
          () => storage.readFile(filePath).toList(),
          throwsA(anything),
        );
      });

      test('creates parent directories if they do not exist', () async {
        const filePath = 'subdir/nested/test';
        final data = Uint8List.fromList([1, 2, 3]);

        final size = await storage.saveFile(filePath, Stream.value(data));
        expect(size, equals(data.length));

        final resultStream = storage.readFile(filePath);
        final result = await resultStream.toList();
        expect(result, equals([data]));
      });

      test('creates all parent directories for deeply nested file', () async {
        const filePath = 'a/b/c/d/e/f/g/h/i/j/testfile';
        final data = Uint8List.fromList([42, 43, 44]);

        final size = await storage.saveFile(filePath, Stream.value(data));
        expect(size, equals(data.length));

        final resultStream = storage.readFile(filePath);
        final result = await resultStream.toList();
        expect(result, equals([data]));
      });

      test('overwrites existing file', () async {
        const filePath = 'overwrite_test';
        final originalData = Uint8List.fromList([1, 2, 3]);
        final newData = Uint8List.fromList([4, 5, 6, 7]);

        await storage.saveFile(filePath, Stream.value(originalData));
        final size = await storage.saveFile(filePath, Stream.value(newData));
        expect(size, equals(newData.length));

        final resultStream = storage.readFile(filePath);
        final result = await resultStream.toList();
        expect(result, equals([newData]));
      });
    });

    group('edge cases and robustness', () {
      test('saveFile with empty data writes empty file and returns 0 size',
          () async {
        const filePath = 'empty_file';

        final size = await storage.saveFile(filePath, Stream.empty());
        expect(size, 0);

        final resultStream = storage.readFile(filePath);
        final chunks = await resultStream.toList();
        expect(chunks.flattenedToList, isEmpty);
      });

      test('readFile preserves byte order (chunking may differ)', () async {
        const filePath = 'ordered_chunks';
        final chunks = <Uint8List>[
          Uint8List.fromList([0, 1, 2]),
          Uint8List.fromList([3, 4]),
          Uint8List.fromList([5, 6, 7, 8]),
        ];
        final expectedBytes =
            Uint8List.fromList(chunks.expand((c) => c).toList());
        await storage.saveFile(filePath, Stream.value(expectedBytes));

        final outChunks = await storage.readFile(filePath).toList();
        final outBytes = Uint8List.fromList(
          outChunks.expand((c) => c).toList(),
        );
        expect(outBytes, equals(expectedBytes));
      });

      test('fileExists becomes false after deleteFile', () async {
        const filePath = 'exists_then_delete';
        await storage.saveFile(filePath, Stream.value(Uint8List.fromList([1])));
        expect(await storage.fileExists(filePath), isTrue);
        await storage.deleteFile(filePath);
        expect(await storage.fileExists(filePath), isFalse);
      });

      test('initialize is idempotent', () async {
        await storage.initialize();
        await storage.initialize();

        // Create a file, then re-initialize again
        const filePath = 'idempotent_test';
        await storage.saveFile(filePath, Stream.value(Uint8List.fromList([9])));
        await storage.initialize();

        // File should still exist (initialize should not clear data)
        expect(await storage.fileExists(filePath), isTrue);
      });

      test('supports unicode and emoji filenames', () async {
        const filePath = '測試_файл_📷.bin';
        final bytes = Uint8List.fromList([10, 20, 30, 40]);
        await storage.saveFile(filePath, Stream.value(bytes));

        final out = await storage.readFile(filePath).toList();
        expect(out, equals([bytes]));
      });

      test('readFile accepts mediaType parameter (ignored by IO impl)',
          () async {
        const filePath = 'with_media_type';
        final data = Uint8List.fromList([1, 2, 3]);
        await storage.saveFile(filePath, Stream.value(data));

        final result =
            await storage.readFile(filePath, mediaType: 'image/jpeg').toList();
        expect(result, equals([data]));
      });
    });

    group('deleteFile', () {
      test('deletes existing file', () async {
        const filePath = 'delete_test';
        final data = Uint8List.fromList([1, 2, 3]);

        await storage.saveFile(filePath, Stream.value(data));
        expect(await storage.fileExists(filePath), isTrue);

        await storage.deleteFile(filePath);
        expect(await storage.fileExists(filePath), isFalse);
      });

      test('does not throw when deleting non-existent file', () async {
        const filePath = 'non_existent';
        await storage.deleteFile(filePath);
      });
    });

    test('clear', () async {
      await storage.saveFile('foo', Stream.value([]));
      expect(await storage.fileExists('foo'), isTrue);
      await storage.clear();
      expect(await storage.fileExists('foo'), isFalse);
    });

    group('fileExists', () {
      test('returns true for existing file', () async {
        const filePath = 'exists_test';
        final data = Uint8List.fromList([1, 2, 3]);

        await storage.saveFile(filePath, Stream.value(data));
        expect(await storage.fileExists(filePath), isTrue);
      });

      test('returns false for non-existent file', () async {
        const filePath = 'non_existent';
        expect(await storage.fileExists(filePath), isFalse);
      });
    });

    group('file system integration', () {
      test('handles special characters in file path', () async {
        const filePath = 'file with spaces & symbols!@#';
        final data = Uint8List.fromList([1, 2, 3]);

        final size = await storage.saveFile(filePath, Stream.value(data));
        expect(size, equals(data.length));

        final resultStream = storage.readFile(filePath);
        final result = await resultStream.toList();
        expect(result, equals([data]));
      });

      test('handles large binary data stream', () async {
        const filePath = 'large_file';
        final data = Uint8List.fromList(List.generate(10000, (i) => i % 256));
        final chunkSize = 1000;
        final chunks = <Uint8List>[];
        for (var i = 0; i < data.length; i += chunkSize) {
          chunks.add(
            Uint8List.fromList(
              data.sublist(
                i,
                i + chunkSize < data.length ? i + chunkSize : data.length,
              ),
            ),
          );
        }
        final size = await storage.saveFile(filePath, Stream.value(data));
        expect(size, equals(data.length));

        final resultStream = storage.readFile(filePath);
        final result = Uint8List.fromList(
          (await resultStream.toList()).expand((chunk) => chunk).toList(),
        );
        expect(result, equals(data));
      });
    });

    group('concurrent operations', () {
      test('handles concurrent saves to different files', () async {
        final futures = <Future<void>>[];
        final fileCount = 10;

        for (int i = 0; i < fileCount; i++) {
          final data = Uint8List.fromList([i, i + 1, i + 2]);
          futures.add(storage.saveFile('file_$i', Stream.value(data)));
        }

        await Future.wait(futures);

        for (int i = 0; i < fileCount; i++) {
          final resultStream = storage.readFile('file_$i');
          final result = await resultStream.toList();
          expect(
            result,
            equals([
              Uint8List.fromList([i, i + 1, i + 2]),
            ]),
          );
        }
      });

      test('handles concurrent saves to the same file', () async {
        const filePath = 'concurrent_test';
        final data1 = Uint8List.fromList([1, 2, 3]);
        final data2 = Uint8List.fromList([4, 5, 6]);
        final futures = [
          storage.saveFile(filePath, Stream.value(data1)),
          storage.saveFile(filePath, Stream.value(data2)),
        ];

        await Future.wait(futures);

        final resultStream = storage.readFile(filePath);
        final result = await resultStream.toList();
        expect(result, anyOf(equals([data1]), equals([data2])));
      });
    });
  });
}

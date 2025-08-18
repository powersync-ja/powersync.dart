import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:path/path.dart' as p;
import 'package:powersync_core/attachments_stream/storage/io_local_storage.dart';
import 'package:test_descriptor/test_descriptor.dart' as d;

void main() {
  group('IOLocalStorage', () {
    late IOLocalStorage storage;

    setUp(() async {
      storage = IOLocalStorage(d.sandbox);
    });

    tearDown(() async {
      // Clean up is handled automatically by test_descriptor
      // No manual cleanup needed
    });

    group('saveFile and readFile', () {
      test('saves and reads binary data successfully', () async {
        const filePath = 'test_file';
        final data = Uint8List.fromList([1, 2, 3, 4, 5]);
        final size = await storage.saveFile(filePath, data);
        expect(size, equals(data.length));

        final resultStream = storage.readFile(filePath);
        final result = await resultStream.toList();
        expect(result, equals([data]));

        // Assert filesystem state using test_descriptor
        await d.file(filePath, data).validate();
      });

      test('throws when reading non-existent file', () async {
        const filePath = 'non_existent';
        expect(
          () => storage.readFile(filePath).toList(),
          throwsA(isA<FileSystemException>()),
        );

        // Assert file does not exist using Dart's File API
        expect(await File(p.join(d.sandbox, filePath)).exists(), isFalse);
      });

      test('creates parent directories if they do not exist', () async {
        const filePath = 'subdir/nested/test';
        final nonExistentDir = Directory(p.join(d.sandbox, 'subdir', 'nested'));
        final data = Uint8List.fromList([1, 2, 3]);

        expect(await nonExistentDir.exists(), isFalse);

        final size = await storage.saveFile(filePath, data);
        expect(size, equals(data.length));
        expect(await nonExistentDir.exists(), isTrue);

        final resultStream = storage.readFile(filePath);
        final result = await resultStream.toList();
        expect(result, equals([data]));

        // Assert directory structure
        await d.dir('subdir/nested', [d.file('test', data)]).validate();
      });

      test('creates all parent directories for deeply nested file', () async {
        const filePath = 'a/b/c/d/e/f/g/h/i/j/testfile';
        final nestedDir = Directory(
          p.join(d.sandbox, 'a', 'b', 'c', 'd', 'e', 'f', 'g', 'h', 'i', 'j'),
        );
        final data = Uint8List.fromList([42, 43, 44]);

        expect(await nestedDir.exists(), isFalse);

        final size = await storage.saveFile(filePath, data);
        expect(size, equals(data.length));
        expect(await nestedDir.exists(), isTrue);

        final resultStream = storage.readFile(filePath);
        final result = await resultStream.toList();
        expect(result, equals([data]));

        // Assert deep directory structure
        await d.dir('a/b/c/d/e/f/g/h/i/j', [
          d.file('testfile', data),
        ]).validate();
      });

      test('overwrites existing file', () async {
        const filePath = 'overwrite_test';
        final originalData = Uint8List.fromList([1, 2, 3]);
        final newData = Uint8List.fromList([4, 5, 6, 7]);

        await storage.saveFile(filePath, originalData);
        final size = await storage.saveFile(filePath, newData);
        expect(size, equals(newData.length));

        final resultStream = storage.readFile(filePath);
        final result = await resultStream.toList();
        expect(result, equals([newData]));

        // Assert file content
        await d.file(filePath, newData).validate();
      });
    });

    group('edge cases and robustness', () {
      test('saveFile with empty data writes empty file and returns 0 size',
          () async {
        const filePath = 'empty_file';
        final emptyBytes = Uint8List(0);

        final size = await storage.saveFile(filePath, emptyBytes);
        expect(size, 0);

        final resultStream = storage.readFile(filePath);
        final chunks = await resultStream.toList();
        expect(chunks, isEmpty);

        final file = File(p.join(d.sandbox, filePath));
        expect(await file.exists(), isTrue);
        expect(await file.length(), 0);
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
        await storage.saveFile(filePath, expectedBytes);

        final outChunks = await storage.readFile(filePath).toList();
        final outBytes = Uint8List.fromList(
          outChunks.expand((c) => c).toList(),
        );
        expect(outBytes, equals(expectedBytes));
      });

      test('fileExists becomes false after deleteFile', () async {
        const filePath = 'exists_then_delete';
        await storage.saveFile(filePath, Uint8List.fromList([1]));
        expect(await storage.fileExists(filePath), isTrue);
        await storage.deleteFile(filePath);
        expect(await storage.fileExists(filePath), isFalse);
      });

      test('initialize is idempotent', () async {
        await storage.initialize();
        await storage.initialize();

        // Create a file, then re-initialize again
        const filePath = 'idempotent_test';
        await storage.saveFile(filePath, Uint8List.fromList([9]));
        await storage.initialize();

        // File should still exist (initialize should not clear data)
        expect(await storage.fileExists(filePath), isTrue);
      });

      test('clear works even if base directory was removed externally',
          () async {
        await storage.initialize();

        // Remove the base dir manually
        final baseDir = Directory(d.sandbox);
        if (await baseDir.exists()) {
          await baseDir.delete(recursive: true);
        }

        // Calling clear should recreate base dir
        await storage.clear();
        expect(await baseDir.exists(), isTrue);
      });

      test('supports unicode and emoji filenames', () async {
        const filePath = '測試_файл_📷.bin';
        final bytes = Uint8List.fromList([10, 20, 30, 40]);
        await storage.saveFile(filePath, bytes);

        final out = await storage.readFile(filePath).toList();
        expect(out, equals([bytes]));

        await d.file(filePath, bytes).validate();
      });

      test('readFile accepts mediaType parameter (ignored by IO impl)',
          () async {
        const filePath = 'with_media_type';
        final data = Uint8List.fromList([1, 2, 3]);
        await storage.saveFile(filePath, data);

        final result =
            await storage.readFile(filePath, mediaType: 'image/jpeg').toList();
        expect(result, equals([data]));
      });
    });

    group('deleteFile', () {
      test('deletes existing file', () async {
        const filePath = 'delete_test';
        final data = Uint8List.fromList([1, 2, 3]);

        await storage.saveFile(filePath, data);
        expect(await storage.fileExists(filePath), isTrue);

        await storage.deleteFile(filePath);
        expect(await storage.fileExists(filePath), isFalse);

        // Assert file does not exist
        expect(await File(p.join(d.sandbox, filePath)).exists(), isFalse);
      });

      test('does not throw when deleting non-existent file', () async {
        const filePath = 'non_existent';
        await storage.deleteFile(filePath);
        expect(await File(p.join(d.sandbox, filePath)).exists(), isFalse);
      });
    });

    group('initialize and clear', () {
      test('initialize creates the base directory', () async {
        final newStorage = IOLocalStorage(p.join(d.sandbox, 'new_dir'));
        final baseDir = Directory(p.join(d.sandbox, 'new_dir'));

        expect(await baseDir.exists(), isFalse);

        await newStorage.initialize();

        expect(await baseDir.exists(), isTrue);
      });

      test('clear removes and recreates the base directory', () async {
        await storage.initialize();
        final testFile = p.join(d.sandbox, 'test_file');
        await File(testFile).writeAsString('test');

        expect(await File(testFile).exists(), isTrue);

        await storage.clear();

        expect(await Directory(d.sandbox).exists(), isTrue);
        expect(await File(testFile).exists(), isFalse);
      });
    });

    group('fileExists', () {
      test('returns true for existing file', () async {
        const filePath = 'exists_test';
        final data = Uint8List.fromList([1, 2, 3]);

        await storage.saveFile(filePath, data);
        expect(await storage.fileExists(filePath), isTrue);

        await d.file(filePath, data).validate();
      });

      test('returns false for non-existent file', () async {
        const filePath = 'non_existent';
        expect(await storage.fileExists(filePath), isFalse);
        expect(await File(p.join(d.sandbox, filePath)).exists(), isFalse);
      });
    });

    group('file system integration', () {
      test('handles special characters in file path', () async {
        const filePath = 'file with spaces & symbols!@#';
        final data = Uint8List.fromList([1, 2, 3]);

        final size = await storage.saveFile(filePath, data);
        expect(size, equals(data.length));

        final resultStream = storage.readFile(filePath);
        final result = await resultStream.toList();
        expect(result, equals([data]));

        await d.file(filePath, data).validate();
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
        final size = await storage.saveFile(filePath, data);
        expect(size, equals(data.length));

        final resultStream = storage.readFile(filePath);
        final result = Uint8List.fromList(
          (await resultStream.toList()).expand((chunk) => chunk).toList(),
        );
        expect(result, equals(data));

        await d.file(filePath, data).validate();
      });
    });

    group('concurrent operations', () {
      test('handles concurrent saves to different files', () async {
        final futures = <Future<void>>[];
        final fileCount = 10;

        for (int i = 0; i < fileCount; i++) {
          final data = Uint8List.fromList([i, i + 1, i + 2]);
          futures.add(storage.saveFile('file_$i', data));
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
          await d
              .file('file_$i', Uint8List.fromList([i, i + 1, i + 2]))
              .validate();
        }
      });

      test('handles concurrent saves to the same file', () async {
        const filePath = 'concurrent_test';
        final data1 = Uint8List.fromList([1, 2, 3]);
        final data2 = Uint8List.fromList([4, 5, 6]);
        final futures = [
          storage.saveFile(filePath, data1),
          storage.saveFile(filePath, data2),
        ];

        await Future.wait(futures);

        final resultStream = storage.readFile(filePath);
        final result = await resultStream.toList();
        expect(result, anyOf(equals([data1]), equals([data2])));

        // Assert one of the possible outcomes
        final file = File(p.join(d.sandbox, filePath));
        final fileData = await file.readAsBytes();
        expect(fileData, anyOf(equals(data1), equals(data2)));
      });
    });
  });
}

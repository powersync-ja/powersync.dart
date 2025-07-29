import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:test/test.dart';
import 'package:path/path.dart' as p;
import 'package:powersync_attachments_stream/src/storage/io_local_storage.dart';

void main() {
  group('IOLocalStorage', () {
    late Directory tempDir;
    late IOLocalStorage storage;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('local_storage_test_');
      storage = IOLocalStorage(tempDir);
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    group('saveFile and readFile', () {
      test('saves and reads binary data stream successfully', () async {
        const filePath = 'test_file';
        final data = Uint8List.fromList([1, 2, 3, 4, 5]);
        final dataStream = Stream.fromIterable([data]);

        final size = await storage.saveFile(filePath, dataStream);
        expect(size, equals(data.length));

        final resultStream = storage.readFile(filePath);
        final result = await resultStream.toList();
        expect(result, equals([data]));
      });

      test('throws when reading non-existent file', () async {
        const filePath = 'non_existent';
        expect(
          () => storage.readFile(filePath).toList(),
          throwsA(isA<FileSystemException>()),
        );
      });

      test('creates parent directories if they do not exist', () async {
        const filePath = 'subdir/nested/test';
        final nonExistentDir = Directory(p.join(tempDir.path, 'subdir', 'nested'));
        final data = Uint8List.fromList([1, 2, 3]);
        final dataStream = Stream.fromIterable([data]);

        expect(await nonExistentDir.exists(), isFalse);

        final size = await storage.saveFile(filePath, dataStream);
        expect(size, equals(data.length));
        expect(await nonExistentDir.exists(), isTrue);

        final resultStream = storage.readFile(filePath);
        final result = await resultStream.toList();
        expect(result, equals([data]));
      });

      test('overwrites existing file', () async {
        const filePath = 'overwrite_test';
        final originalData = Uint8List.fromList([1, 2, 3]);
        final newData = Uint8List.fromList([4, 5, 6, 7]);
        final originalStream = Stream.fromIterable([originalData]);
        final newStream = Stream.fromIterable([newData]);

        await storage.saveFile(filePath, originalStream);
        final size = await storage.saveFile(filePath, newStream);
        expect(size, equals(newData.length));

        final resultStream = storage.readFile(filePath);
        final result = await resultStream.toList();
        expect(result, equals([newData]));
      });
    });

    group('deleteFile', () {
      test('deletes existing file', () async {
        const filePath = 'delete_test';
        final data = Uint8List.fromList([1, 2, 3]);
        final dataStream = Stream.fromIterable([data]);

        await storage.saveFile(filePath, dataStream);
        expect(await storage.fileExists(filePath), isTrue);

        await storage.deleteFile(filePath);
        expect(await storage.fileExists(filePath), isFalse);
      });

      test('does not throw when deleting non-existent file', () async {
        await storage.deleteFile('non_existent');
      });
    });

    group('fileExists', () {
      test('returns true for existing file', () async {
        const filePath = 'exists_test';
        final data = Uint8List.fromList([1, 2, 3]);
        final dataStream = Stream.fromIterable([data]);

        await storage.saveFile(filePath, dataStream);
        expect(await storage.fileExists(filePath), isTrue);
      });

      test('returns false for non-existent file', () async {
        expect(await storage.fileExists('non_existent'), isFalse);
      });
    });

    group('makeDir', () {
      test('creates directory and its parents', () async {
        const dirPath = 'test_dir/subdir';
        final fullPath = Directory(p.join(tempDir.path, dirPath));

        expect(await fullPath.exists(), isFalse);
        await storage.makeDir(dirPath);
        expect(await fullPath.exists(), isTrue);
      });

      test('does not throw when directory already exists', () async {
        const dirPath = 'existing_dir';
        await storage.makeDir(dirPath);
        await storage.makeDir(dirPath); // Should not throw
        expect(await Directory(p.join(tempDir.path, dirPath)).exists(), isTrue);
      });
    });

    group('rmDir', () {
      test('recursively deletes directory with files and subdirectories', () async {
        const dirPath = 'test_dir';
        final file1Path = p.join(dirPath, 'file1');
        final file2Path = p.join(dirPath, 'subdir/file2');
        final data = Uint8List.fromList([1, 2, 3]);

        await storage.saveFile(file1Path, Stream.fromIterable([data]));
        await storage.saveFile(file2Path, Stream.fromIterable([data]));

        final dir = Directory(p.join(tempDir.path, dirPath));
        expect(await dir.exists(), isTrue);

        await storage.rmDir(dirPath);
        expect(await dir.exists(), isFalse);
      });

      test('does not throw when directory does not exist', () async {
        await storage.rmDir('non_existent_dir');
      });
    });

    group('copyFile', () {
      test('copies file to target path', () async {
        const sourcePath = 'source_file';
        const targetPath = 'target_file';
        final data = Uint8List.fromList([1, 2, 3]);
        final dataStream = Stream.fromIterable([data]);

        await storage.saveFile(sourcePath, dataStream);
        await storage.copyFile(sourcePath, targetPath);

        final resultStream = storage.readFile(targetPath);
        final result = await resultStream.toList();
        expect(result, equals([data]));
        expect(await storage.fileExists(sourcePath), isTrue); // Source still exists
      });

      test('throws when source file does not exist', () async {
        expect(
          () => storage.copyFile('non_existent', 'target'),
          throwsA(isA<FileSystemException>()),
        );
      });

      test('creates target parent directories', () async {
        const sourcePath = 'source_file';
        const targetPath = 'subdir/nested/target_file';
        final data = Uint8List.fromList([1, 2, 3]);
        final dataStream = Stream.fromIterable([data]);

        await storage.saveFile(sourcePath, dataStream);
        await storage.copyFile(sourcePath, targetPath);

        final resultStream = storage.readFile(targetPath);
        final result = await resultStream.toList();
        expect(result, equals([data]));
        expect(await Directory(p.join(tempDir.path, 'subdir', 'nested')).exists(), isTrue);
      });
    });

    group('file system integration', () {
      test('handles special characters in file path', () async {
        const filePath = 'file with spaces & symbols!@#';
        final data = Uint8List.fromList([1, 2, 3]);
        final dataStream = Stream.fromIterable([data]);

        final size = await storage.saveFile(filePath, dataStream);
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
          chunks.add(Uint8List.fromList(
              data.sublist(i, i + chunkSize < data.length ? i + chunkSize : data.length)));
        }
        final dataStream = Stream.fromIterable(chunks);

        final size = await storage.saveFile(filePath, dataStream);
        expect(size, equals(data.length));

        final resultStream = storage.readFile(filePath);
        final result = Uint8List.fromList((await resultStream.toList()).expand((chunk) => chunk).toList());
        expect(result, equals(data));
      });
    });

    group('concurrent operations', () {
      test('handles concurrent saves to different files', () async {
        final futures = <Future<void>>[];
        final fileCount = 10;

        for (int i = 0; i < fileCount; i++) {
          final data = Uint8List.fromList([i, i + 1, i + 2]);
          futures.add(storage.saveFile('file_$i', Stream.fromIterable([data])));
        }

        await Future.wait(futures);

        for (int i = 0; i < fileCount; i++) {
          final resultStream = storage.readFile('file_$i');
          final result = await resultStream.toList();
          expect(result, equals([Uint8List.fromList([i, i + 1, i + 2])]));
        }
      });

      test('handles concurrent saves to the same file', () async {
        const filePath = 'concurrent_test';
        final data1 = Uint8List.fromList([1, 2, 3]);
        final data2 = Uint8List.fromList([4, 5, 6]);
        final futures = [
          storage.saveFile(filePath, Stream.fromIterable([data1])),
          storage.saveFile(filePath, Stream.fromIterable([data2])),
        ];

        await Future.wait(futures);

        final resultStream = storage.readFile(filePath);
        final result = await resultStream.toList();
        expect(result, anyOf(equals([data1]), equals([data2])));
      });
    });
  });
}
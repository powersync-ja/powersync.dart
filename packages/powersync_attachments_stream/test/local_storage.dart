import 'dart:convert';
import 'dart:io';
import 'package:test/test.dart';
import 'package:path/path.dart' as p;
import 'package:powersync_attachments_stream/src/local_storage.dart';

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

    group('save and read', () {
      test('saves and reads binary data successfully', () async {
        const id = 'test_file';
        final data = [1, 2, 3, 4, 5];

        await storage.save(id, data);
        final result = await storage.read(id);

        expect(result, equals(data));
      });

      test('returns null when reading non-existent file', () async {
        final result = await storage.read('non_existent');
        expect(result, isNull);
      });

      test('creates base directory if it does not exist', () async {
        final nonExistentDir = Directory(p.join(tempDir.path, 'subdir', 'nested'));
        final nestedStorage = IOLocalStorage(nonExistentDir);
        
        expect(await nonExistentDir.exists(), isFalse);
        
        await nestedStorage.save('test', [1, 2, 3]);
        
        expect(await nonExistentDir.exists(), isTrue);
        final result = await nestedStorage.read('test');
        expect(result, equals([1, 2, 3]));
      });

      test('overwrites existing file', () async {
        const id = 'overwrite_test';
        final originalData = [1, 2, 3];
        final newData = [4, 5, 6, 7];

        await storage.save(id, originalData);
        await storage.save(id, newData);
        
        final result = await storage.read(id);
        expect(result, equals(newData));
      });
    });

    group('metadata', () {
      test('saves and retrieves metadata with mediaType only', () async {
        const id = 'test_with_media_type';
        final data = [1, 2, 3];
        const mediaType = 'image/jpeg';

        await storage.save(id, data, mediaType: mediaType);
        final metadata = await storage.getMetadata(id);

        expect(metadata, isNotNull);
        expect(metadata!['mediaType'], equals(mediaType));
        expect(metadata['metadata'], isNull);
      });

      test('saves and retrieves metadata with custom metadata only', () async {
        const id = 'test_with_metadata';
        final data = [1, 2, 3];
        final customMetadata = {'width': 800, 'height': 600, 'format': 'png'};

        await storage.save(id, data, metadata: customMetadata);
        final metadata = await storage.getMetadata(id);

        expect(metadata, isNotNull);
        expect(metadata!['mediaType'], isNull);
        expect(metadata['metadata'], equals(customMetadata));
      });

      test('saves and retrieves both mediaType and custom metadata', () async {
        const id = 'test_with_both';
        final data = [1, 2, 3];
        const mediaType = 'application/pdf';
        final customMetadata = {'pages': 10, 'author': 'Test Author'};

        await storage.save(id, data, mediaType: mediaType, metadata: customMetadata);
        final metadata = await storage.getMetadata(id);

        expect(metadata, isNotNull);
        expect(metadata!['mediaType'], equals(mediaType));
        expect(metadata['metadata'], equals(customMetadata));
      });

      test('returns null when getting metadata for non-existent file', () async {
        final metadata = await storage.getMetadata('non_existent');
        expect(metadata, isNull);
      });

      test('does not create metadata file when no metadata provided', () async {
        const id = 'no_metadata';
        final data = [1, 2, 3];

        await storage.save(id, data);
        
        final metaFile = File(p.join(tempDir.path, '$id.meta.json'));
        expect(await metaFile.exists(), isFalse);
        
        final metadata = await storage.getMetadata(id);
        expect(metadata, isNull);
      });

      test('overwrites existing metadata', () async {
        const id = 'metadata_overwrite';
        final data = [1, 2, 3];
        final originalMetadata = {'version': 1};
        final newMetadata = {'version': 2, 'updated': true};

        await storage.save(id, data, metadata: originalMetadata);
        await storage.save(id, data, metadata: newMetadata);
        
        final metadata = await storage.getMetadata(id);
        expect(metadata!['metadata'], equals(newMetadata));
      });
    });

    group('delete', () {
      test('deletes existing file and metadata', () async {
        const id = 'delete_test';
        final data = [1, 2, 3];
        final customMetadata = {'test': true};

        await storage.save(id, data, mediaType: 'text/plain', metadata: customMetadata);
        
        // Verify files exist
        expect(await storage.read(id), isNotNull);
        expect(await storage.getMetadata(id), isNotNull);
        
        await storage.delete(id);
        
        // Verify files are deleted
        expect(await storage.read(id), isNull);
        expect(await storage.getMetadata(id), isNull);
      });

      test('does not throw when deleting non-existent files', () async {
        // Should not throw exception
        await storage.delete('non_existent');
      });

      test('deletes only data file when metadata does not exist', () async {
        const id = 'data_only';
        final data = [1, 2, 3];

        await storage.save(id, data);  // No metadata
        expect(await storage.read(id), isNotNull);
        
        await storage.delete(id);
        expect(await storage.read(id), isNull);
      });

      test('handles partial deletion gracefully', () async {
        const id = 'partial_delete';
        final data = [1, 2, 3];

        await storage.save(id, data, metadata: {'test': true});
        
        // Manually delete just the data file
        final dataFile = File(p.join(tempDir.path, id));
        await dataFile.delete();
        
        // Delete should still work without throwing
        await storage.delete(id);
        
        expect(await storage.read(id), isNull);
        expect(await storage.getMetadata(id), isNull);
      });
    });

    group('file system integration', () {
      test('handles special characters in id', () async {
        const id = 'file with spaces & symbols!@#';
        final data = [1, 2, 3];

        await storage.save(id, data);
        final result = await storage.read(id);
        
        expect(result, equals(data));
      });

      test('handles empty data', () async {
        const id = 'empty_file';
        final data = <int>[];

        await storage.save(id, data);
        final result = await storage.read(id);
        
        expect(result, equals(data));
      });

      test('handles large binary data', () async {
        const id = 'large_file';
        final data = List.generate(10000, (i) => i % 256);

        await storage.save(id, data);
        final result = await storage.read(id);
        
        expect(result, equals(data));
      });

      test('metadata file has correct JSON format', () async {
        const id = 'json_format_test';
        final data = [1, 2, 3];
        const mediaType = 'application/json';
        final customMetadata = {'test': true, 'number': 42};

        await storage.save(id, data, mediaType: mediaType, metadata: customMetadata);
        
        // Read metadata file directly
        final metaFile = File(p.join(tempDir.path, '$id.meta.json'));
        final content = await metaFile.readAsString();
        final parsed = jsonDecode(content) as Map<String, dynamic>;
        
        expect(parsed['mediaType'], equals(mediaType));
        expect(parsed['metadata'], equals(customMetadata));
      });
    });

    group('concurrent operations', () {
      test('handles concurrent saves to different files', () async {
        final futures = <Future<void>>[];
        
        for (int i = 0; i < 10; i++) {
          futures.add(storage.save('file_$i', [i, i + 1, i + 2]));
        }
        
        await Future.wait(futures);
        
        for (int i = 0; i < 10; i++) {
          final result = await storage.read('file_$i');
          expect(result, equals([i, i + 1, i + 2]));
        }
      });

      test('handles concurrent operations on same file', () async {
        const id = 'concurrent_test';
        final data1 = [1, 2, 3];
        final data2 = [4, 5, 6];
        
        final futures = [
          storage.save(id, data1),
          storage.save(id, data2),
        ];
        
        await Future.wait(futures);
        
        final result = await storage.read(id);
        expect(result, isNotNull);
        expect(result, anyOf(equals(data1), equals(data2)));
      });
    });
  });
}
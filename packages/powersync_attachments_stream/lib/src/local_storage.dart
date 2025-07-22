import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;

abstract class LocalStorage {
  /// Saves binary data to storage with an identifier
  /// 
  /// [id] - Unique identifier for the stored data
  /// [bytes] - Binary data to store
  /// [mediaType] - Optional MIME type of the data (e.g., 'image/jpeg')
  /// [metadata] - Optional key-value pairs for additional data information
  Future<void> save(String id, List<int> bytes, {String? mediaType, Map<String, dynamic>? metadata});
  
  /// Retrieves binary data by identifier
  /// 
  /// [id] - Unique identifier of the data to retrieve
  /// Returns the binary data if found, null otherwise
  Future<List<int>?> read(String id);
  
  /// Removes data and its metadata from storage
  /// 
  /// [id] - Unique identifier of the data to delete
  Future<void> delete(String id);
  
  /// Retrieves metadata associated with stored data
  /// 
  /// [id] - Unique identifier of the data
  /// Returns metadata map if found, null otherwise
  Future<Map<String, dynamic>?> getMetadata(String id);
}

class IOLocalStorage implements LocalStorage {
  final Directory baseDir;

  IOLocalStorage(this.baseDir);

  File _fileFor(String id) => File(p.join(baseDir.path, id));
  File _metaFileFor(String id) => File(p.join(baseDir.path, '$id.meta.json'));

  @override
  Future<void> save(String id, List<int> bytes, {String? mediaType, Map<String, dynamic>? metadata}) async {
    await baseDir.create(recursive: true);
    await _fileFor(id).writeAsBytes(bytes);
    if (mediaType != null || metadata != null) {
      final meta = <String, dynamic>{};
      if (mediaType != null) meta['mediaType'] = mediaType;
      if (metadata != null) meta['metadata'] = metadata;
      await _metaFileFor(id).writeAsString(jsonEncode(meta));
    }
  }

  @override
  Future<List<int>?> read(String id) async {
    final file = _fileFor(id);
    if (await file.exists()) {
      return await file.readAsBytes();
    }
    return null;
  }

  @override
  Future<void> delete(String id) async {
    try {
      await _fileFor(id).delete();
    } on FileSystemException {
      // File doesn't exist, ignore
    }
    try {
      await _metaFileFor(id).delete();
    } on FileSystemException {
      // File doesn't exist, ignore
    }
  }

  @override
  Future<Map<String, dynamic>?> getMetadata(String id) async {
    final metaFile = _metaFileFor(id);
    if (await metaFile.exists()) {
      final content = await metaFile.readAsString();
      return jsonDecode(content) as Map<String, dynamic>;
    }
    return null;
  }
}
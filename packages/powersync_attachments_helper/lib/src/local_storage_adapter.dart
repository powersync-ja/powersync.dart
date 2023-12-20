import 'dart:io';
import 'dart:typed_data';
import 'package:path_provider/path_provider.dart';

/// Storage adapter for local storage
class LocalStorageAdapter {
  Future<File> saveFile(String fileUri, Uint8List data) async {
    final file = File(fileUri);
    return await file.writeAsBytes(data);
  }

  Future<Uint8List> readFile(String fileUri, {String? mediaType}) async {
    final file = File(fileUri);
    return await file.readAsBytes();
  }

  Future<void> deleteFile(String fileUri) async {
    if (await fileExists(fileUri)) {
      File file = File(fileUri);
      await file.delete();
    }
  }

  Future<bool> fileExists(String fileUri) async {
    File file = File(fileUri);
    bool exists = await file.exists();
    return exists;
  }

  Future<void> makeDir(String fileUri) async {
    bool exists = await fileExists(fileUri);
    if (!exists) {
      Directory newDirectory = Directory(fileUri);
      await newDirectory.create(recursive: true);
    }
  }

  Future<void> copyFile(String sourceUri, String targetUri) async {
    File file = File(sourceUri);
    await file.copy(targetUri);
  }

  Future<String> getUserStorageDirectory() async {
    final directory = await getApplicationDocumentsDirectory();
    return directory.path;
  }
}

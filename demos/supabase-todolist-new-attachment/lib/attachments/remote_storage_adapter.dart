import 'dart:io';
import 'dart:typed_data';
import 'package:powersync_attachments_stream/powersync_attachments_stream.dart';
import 'package:powersync_flutter_demo_new/app_config.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:image/image.dart' as img;

class SupabaseStorageAdapter implements RemoteStorage {
  @override
  Future<void> uploadFile(
      Stream<List<int>> fileData, Attachment attachment) async {
    _checkSupabaseBucketIsConfigured();
    final tempFile =
        File('${Directory.systemTemp.path}/${attachment.filename}');
    final sink = tempFile.openWrite();
    await for (final chunk in fileData) {
      sink.add(chunk);
    }
    await sink.close();
    print('uploadFile: ${attachment.filename}');
    try {
      await Supabase.instance.client.storage
          .from(AppConfig.supabaseStorageBucket)
          .upload(attachment.filename, tempFile,
              fileOptions: FileOptions(
                  contentType:
                      attachment.mediaType ?? 'application/octet-stream'));

    } catch (error) {
      throw Exception(error);
    } finally {
      if (await tempFile.exists()) {
        await tempFile.delete();
      }
    }
  }

  @override
  Future<Stream<List<int>>> downloadFile(Attachment attachment) async {
    _checkSupabaseBucketIsConfigured();
    print('downloadFile: ${attachment.filename}');
    try {
      Uint8List fileBlob = await Supabase.instance.client.storage
          .from(AppConfig.supabaseStorageBucket)
          .download(attachment.filename);
      final image = img.decodeImage(fileBlob);
      Uint8List blob = img.JpegEncoder().encode(image!);
      print('downloadFile: ${blob.length}');
      return Stream.value(blob);
    } catch (error) {
      throw Exception(error);
    }
  }

  @override
  Future<void> deleteFile(Attachment attachment) async {
    print('deleteFile: ${attachment.filename}');
    _checkSupabaseBucketIsConfigured();
    try {
      await Supabase.instance.client.storage
          .from(AppConfig.supabaseStorageBucket)
          .remove([attachment.filename]);
    } catch (error) {
      throw Exception(error);
    }
  }

  void _checkSupabaseBucketIsConfigured() {
    if (AppConfig.supabaseStorageBucket.isEmpty) {
      throw Exception(
          'Supabase storage bucket is not configured in app_config.dart');
    }
  }
}

import 'dart:io';
import 'dart:typed_data';
import 'package:powersync_attachments_helper/powersync_attachments_helper.dart';
import 'package:powersync_flutter_demo/app_config.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:image/image.dart' as img;

class SupabaseStorageAdapter implements AbstractRemoteStorageAdapter {
  @override
  Future<void> uploadFile(String filename, File file,
      {String mediaType = 'text/plain'}) async {
    _checkSupabaseBucketIsConfigured();

    try {
      await Supabase.instance.client.storage
          .from(AppConfig.supabaseStorageBucket)
          .upload(filename, file,
              fileOptions: FileOptions(contentType: mediaType));
    } catch (error) {
      throw Exception(error);
    }
  }

  @override
  Future<Uint8List> downloadFile(String filePath) async {
    _checkSupabaseBucketIsConfigured();
    try {
      Uint8List fileBlob = await Supabase.instance.client.storage
          .from(AppConfig.supabaseStorageBucket)
          .download(filePath);
      final image = img.decodeImage(fileBlob);
      Uint8List blob = img.JpegEncoder().encode(image!);
      return blob;
    } catch (error) {
      throw Exception(error);
    }
  }

  @override
  Future<void> deleteFile(String filename) async {
    _checkSupabaseBucketIsConfigured();

    try {
      await Supabase.instance.client.storage
          .from(AppConfig.supabaseStorageBucket)
          .remove([filename]);
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

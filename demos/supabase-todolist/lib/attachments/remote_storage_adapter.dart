import 'dart:io';
import 'dart:typed_data';
import 'package:powersync_attachments_stream/powersync_attachments_stream.dart';
import 'package:powersync_flutter_demo/app_config.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:logging/logging.dart';

class SupabaseStorageAdapter implements AbstractRemoteStorageAdapter {
  static final _log = Logger('SupabaseStorageAdapter');

  @override
  Future<void> uploadFile(
      Stream<List<int>> fileData, Attachment attachment) async {
    _checkSupabaseBucketIsConfigured();

    // Check if attachment size is specified (required for buffer allocation)
    final byteSize = attachment.size;
    if (byteSize == null) {
      throw Exception('Cannot upload a file with no byte size specified');
    }

    _log.info('uploadFile: ${attachment.filename} (size: $byteSize bytes)');

    // Collect all stream data into a single Uint8List buffer
    final buffer = Uint8List(byteSize);
    var position = 0;

    await for (final chunk in fileData) {
      if (position + chunk.length > byteSize) {
        throw Exception('File data exceeds specified size');
      }
      buffer.setRange(position, position + chunk.length, chunk);
      position += chunk.length;
    }

    if (position != byteSize) {
      throw Exception(
          'File data size ($position) does not match specified size ($byteSize)');
    }

    // Create a temporary file from the buffer for upload
    final tempFile =
        File('${Directory.systemTemp.path}/${attachment.filename}');
    try {
      await tempFile.writeAsBytes(buffer);

      await Supabase.instance.client.storage
          .from(AppConfig.supabaseStorageBucket)
          .upload(attachment.filename, tempFile,
              fileOptions: FileOptions(
                  contentType:
                      attachment.mediaType ?? 'application/octet-stream'));

      _log.info('Successfully uploaded ${attachment.filename}');
    } catch (error) {
      _log.severe('Error uploading ${attachment.filename}', error);
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
    try {
      _log.info('downloadFile: ${attachment.filename}');

      Uint8List fileBlob = await Supabase.instance.client.storage
          .from(AppConfig.supabaseStorageBucket)
          .download(attachment.filename);

      _log.info(
          'Successfully downloaded ${attachment.filename} (${fileBlob.length} bytes)');

      // Return the raw file data as a stream
      return Stream.value(fileBlob);
    } catch (error) {
      _log.severe('Error downloading ${attachment.filename}', error);
      throw Exception(error);
    }
  }

  @override
  Future<void> deleteFile(Attachment attachment) async {
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

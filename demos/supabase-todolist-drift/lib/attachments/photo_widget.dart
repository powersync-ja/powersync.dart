import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:powersync_attachments_helper/powersync_attachments_helper.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:supabase_todolist_drift/attachments/camera_helpers.dart';
import 'package:supabase_todolist_drift/attachments/photo_capture_widget.dart';
import 'package:supabase_todolist_drift/attachments/queue.dart';
import 'package:supabase_todolist_drift/database.dart';

part 'photo_widget.g.dart';

final class PhotoWidget extends ConsumerWidget {
  final TodoItem todo;

  const PhotoWidget({super.key, required this.todo});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final photoState = ref.watch(_getPhotoStateProvider(todo.photoId));
    if (!photoState.hasValue) {
      return Container();
    }

    final data = photoState.value;
    Widget takePhotoButton = ElevatedButton(
      onPressed: () async {
        final camera = await setupCamera();
        if (!context.mounted) return;

        if (camera == null) {
          const snackBar = SnackBar(
            content: Text('No camera available'),
            backgroundColor: Colors.red, // Optional: to highlight it's an error
          );

          ScaffoldMessenger.of(context).showSnackBar(snackBar);
          return;
        }

        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) =>
                TakePhotoWidget(todoId: todo.id, camera: camera),
          ),
        );
      },
      child: const Text('Take Photo'),
    );

    if (data == null) {
      return takePhotoButton;
    }

    String? filePath = data.photoPath;
    bool fileIsDownloading = !data.fileExists;
    bool fileArchived =
        data.attachment?.state == AttachmentState.archived.index;

    if (fileArchived) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text("Unavailable"),
          const SizedBox(height: 8),
          takePhotoButton
        ],
      );
    }

    if (fileIsDownloading) {
      return const Text("Downloading...");
    }

    File imageFile = File(filePath!);
    int lastModified = imageFile.existsSync()
        ? imageFile.lastModifiedSync().millisecondsSinceEpoch
        : 0;
    Key key = ObjectKey('$filePath:$lastModified');

    return Image.file(
      key: key,
      imageFile,
      width: 50,
      height: 50,
    );
  }
}

class _ResolvedPhotoState {
  String? photoPath;
  bool fileExists;
  Attachment? attachment;

  _ResolvedPhotoState(
      {required this.photoPath, required this.fileExists, this.attachment});
}

@riverpod
Future<_ResolvedPhotoState> _getPhotoState(Ref ref, String? photoId) async {
  if (photoId == null) {
    return _ResolvedPhotoState(photoPath: null, fileExists: false);
  }
  final queue = await ref.read(attachmentQueueProvider.future);
  final photoPath = await queue.getLocalUri('$photoId.jpg');

  bool fileExists = await File(photoPath).exists();

  final row = await queue.db
      .getOptional('SELECT * FROM attachments_queue WHERE id = ?', [photoId]);

  if (row != null) {
    Attachment attachment = Attachment.fromRow(row);
    return _ResolvedPhotoState(
        photoPath: photoPath, fileExists: fileExists, attachment: attachment);
  }

  return _ResolvedPhotoState(
      photoPath: photoPath, fileExists: fileExists, attachment: null);
}

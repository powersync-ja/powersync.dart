import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:powersync_core/attachments/attachments.dart';
import 'package:powersync_core/attachments/io.dart';
import 'package:powersync_flutter_demo/attachments/camera_helpers.dart';
import 'package:powersync_flutter_demo/attachments/photo_capture_widget.dart';

import '../models/todo_item.dart';
import '../powersync.dart';
import 'queue.dart';

class PhotoWidget extends StatelessWidget {
  final TodoItem todo;

  PhotoWidget({
    required this.todo,
  }) : super(key: ObjectKey(todo.id));

  @override
  Widget build(BuildContext context) {
    return StreamBuilder(
      stream: _attachmentState(todo.photoId),
      builder: (context, snapshot) {
        if (snapshot.data == null) {
          return Container();
        }
        final data = snapshot.data!;
        final attachment = data.attachment;
        if (todo.photoId == null || attachment == null) {
          return TakePhotoButton(todoId: todo.id);
        }

        var fileArchived = data.attachment?.state == AttachmentState.archived;

        if (fileArchived) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text("Unavailable"),
              const SizedBox(height: 8),
              TakePhotoButton(todoId: todo.id),
            ],
          );
        }

        if (!data.fileExists) {
          return const Text('Downloading...');
        }

        if (kIsWeb) {
          // We can't use Image.file on the web, so fall back to loading the
          // image from OPFS.
          return _WebAttachmentImage(attachment: attachment);
        } else {
          final path =
              (localStorage as IOLocalStorage).pathFor(attachment.filename);
          return Image.file(
            key: ValueKey(attachment),
            File(path),
            width: 50,
            height: 50,
          );
        }
      },
    );
  }

  static Stream<_AttachmentState> _attachmentState(String? id) {
    return db.watch('SELECT * FROM attachments_queue WHERE id = ?',
        parameters: [id]).asyncMap((rows) async {
      if (rows.isEmpty) {
        return const _AttachmentState(null, false);
      }

      final attachment = Attachment.fromRow(rows.single);
      final exists = await localStorage.fileExists(attachment.filename);
      return _AttachmentState(attachment, exists);
    });
  }
}

class TakePhotoButton extends StatelessWidget {
  final String todoId;

  const TakePhotoButton({super.key, required this.todoId});

  @override
  Widget build(BuildContext context) {
    return ElevatedButton(
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
                TakePhotoWidget(todoId: todoId, camera: camera),
          ),
        );
      },
      child: const Text('Take Photo'),
    );
  }
}

final class _AttachmentState {
  final Attachment? attachment;
  final bool fileExists;

  const _AttachmentState(this.attachment, this.fileExists);
}

/// A widget showing an [Attachment] as an image by loading it into memory.
///
/// On native platforms, using a file path is more efficient.
class _WebAttachmentImage extends StatefulWidget {
  final Attachment attachment;

  const _WebAttachmentImage({required this.attachment});

  @override
  State<_WebAttachmentImage> createState() => _AttachmentImageState();
}

class _AttachmentImageState extends State<_WebAttachmentImage> {
  Future<Uint8List?>? _imageBytes;

  void _loadBytes() {
    setState(() {
      _imageBytes = Future(() async {
        final buffer = BytesBuilder();
        if (!await localStorage.fileExists(widget.attachment.filename)) {
          return null;
        }

        await localStorage
            .readFile(widget.attachment.filename)
            .forEach(buffer.add);
        return buffer.takeBytes();
      });
    });
  }

  @override
  void initState() {
    super.initState();
    _loadBytes();
  }

  @override
  void didUpdateWidget(covariant _WebAttachmentImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.attachment != widget.attachment) {
      _loadBytes();
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder(
      future: _imageBytes,
      builder: (context, snapshot) {
        if (snapshot.data case final bytes?) {
          return Image.memory(
            bytes,
            width: 50,
            height: 50,
          );
        } else {
          return Container();
        }
      },
    );
  }
}

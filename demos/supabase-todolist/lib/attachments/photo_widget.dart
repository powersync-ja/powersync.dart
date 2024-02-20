import 'dart:io';

import 'package:flutter/material.dart';
import 'package:powersync_flutter_demo/attachments/camera_helpers.dart';
import 'package:powersync_flutter_demo/attachments/photo_capture_widget.dart';
import 'package:powersync_flutter_demo/attachments/queue.dart';
import 'package:powersync_flutter_demo/database.dart';

class PhotoWidget extends StatefulWidget {
  final TodoItem todo;

  PhotoWidget({
    required this.todo,
  }) : super(key: ObjectKey(todo.id));

  @override
  State<StatefulWidget> createState() {
    return _PhotoWidgetState();
  }
}

class _ResolvedPhotoState {
  String? photoPath;
  bool fileExists;

  _ResolvedPhotoState({required this.photoPath, required this.fileExists});
}

class _PhotoWidgetState extends State<PhotoWidget> {
  late String photoPath;

  Future<_ResolvedPhotoState> _getPhotoState(photoId) async {
    if (photoId == null) {
      return _ResolvedPhotoState(photoPath: null, fileExists: false);
    }
    photoPath = await attachmentQueue.getLocalUri('$photoId.jpg');

    bool fileExists = await File(photoPath).exists();

    return _ResolvedPhotoState(photoPath: photoPath, fileExists: fileExists);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder(
        future: _getPhotoState(widget.todo.photoId),
        builder: (BuildContext context,
            AsyncSnapshot<_ResolvedPhotoState> snapshot) {
          if (snapshot.data == null) {
            return Container();
          }
          final data = snapshot.data!;
          Widget takePhotoButton = ElevatedButton(
            onPressed: () async {
              final camera = await setupCamera();
              if (!context.mounted) return;

              if (camera == null) {
                const snackBar = SnackBar(
                  content: Text('No camera available'),
                  backgroundColor:
                      Colors.red, // Optional: to highlight it's an error
                );

                ScaffoldMessenger.of(context).showSnackBar(snackBar);
                return;
              }

              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) =>
                      TakePhotoWidget(todoId: widget.todo.id, camera: camera),
                ),
              );
            },
            child: const Text('Take Photo'),
          );

          if (widget.todo.photoId == null) {
            return takePhotoButton;
          }

          String? filePath = data.photoPath;
          bool fileIsDownloading = !data.fileExists;

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
        });
  }
}

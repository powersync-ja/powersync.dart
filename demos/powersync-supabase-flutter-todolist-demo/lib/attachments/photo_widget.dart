import 'dart:io';

import 'package:flutter/material.dart';
import 'package:powersync_flutter_demo/attachments/photo_capture_widget.dart';
import 'package:powersync_flutter_demo/attachments/queue.dart';

import '../models/todo_item.dart';

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

class _PhotoWidgetState extends State<PhotoWidget> {
  late String photoPath;

  Future<Map<String, dynamic>> _getPhoto(photoId) async {
    if (photoId == null) {
      return {"photoPath": null, "fileExists": false};
    }
    photoPath = await attachmentQueue.getLocalUri('$photoId.jpg');

    bool fileExists = await File(photoPath).exists();

    return {"photoPath": photoPath, "fileExists": fileExists};
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder(
        future: _getPhoto(widget.todo.photoId),
        builder: (BuildContext context, AsyncSnapshot snapshot) {
          Widget takePhotoButton = ElevatedButton(
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => TakePhotoWidget(todoId: widget.todo.id),
                ),
              );
            },
            child: const Text('Take Photo'),
          );

          if (widget.todo.photoId == null) {
            return takePhotoButton;
          }

          if (snapshot.hasData) {
            String filePath = snapshot.data['photoPath'];
            bool fileIsDownloading = !snapshot.data['fileExists'];

            if (fileIsDownloading) {
              return const Text("Downloading...");
            }

            File imageFile = File(filePath);
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

          return takePhotoButton;
        });
  }
}

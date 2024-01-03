import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:powersync/powersync.dart' as powersync;
import 'package:powersync_flutter_demo/attachments/queue.dart';
import 'package:powersync_flutter_demo/models/todo_item.dart';
import 'package:powersync_flutter_demo/powersync.dart';

class TakePhotoWidget extends StatefulWidget {
  final String todoId;
  final CameraDescription camera;

  const TakePhotoWidget(
      {super.key, required this.todoId, required this.camera});

  @override
  State<StatefulWidget> createState() {
    return _TakePhotoWidgetState();
  }
}

class _TakePhotoWidgetState extends State<TakePhotoWidget> {
  late CameraController _cameraController;
  late Future<void> _initializeControllerFuture;

  @override
  void initState() {
    super.initState();

    _cameraController = CameraController(
      widget.camera,
      ResolutionPreset.medium,
    );

    _initializeControllerFuture = _cameraController.initialize();
  }

  @override
  // Dispose of the camera controller when the widget is disposed
  void dispose() {
    _cameraController.dispose();
    super.dispose();
  }

  Future<void> _takePhoto(context) async {
    try {
      // Ensure the camera is initialized before taking a photo
      await _initializeControllerFuture;

      final XFile photo = await _cameraController.takePicture();
      // copy photo to new directory with ID as name
      String photoId = powersync.uuid.v4();
      String storageDirectory = await attachmentQueue.getStorageDirectory();
      await attachmentQueue.localStorage
          .copyFile(photo.path, '$storageDirectory/$photoId.jpg');

      int photoSize = await photo.length();

      TodoItem.addPhoto(photoId, widget.todoId);
      attachmentQueue.savePhoto(photoId, photoSize);
    } catch (e) {
      log.info('Error taking photo: $e');
    }

    // After taking the photo, navigate back to the previous screen
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        FutureBuilder<void>(
          future: _initializeControllerFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.done) {
              return CameraPreview(_cameraController);
            } else {
              return const CircularProgressIndicator();
            }
          },
        ),
        const SizedBox(height: 16),
        ElevatedButton(
          onPressed: () => _takePhoto(context),
          child: const Text('Take Photo'),
        ),
      ],
    );
  }
}

import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:logging/logging.dart';
import 'package:powersync/powersync.dart' as powersync;

import '../powersync/attachments/queue.dart';
import '../powersync/database.dart';

final _log = Logger('TakePhotoWidget');

@RoutePage()
class TakePhotoPage extends ConsumerStatefulWidget {
  final String todoId;
  final CameraDescription camera;

  const TakePhotoPage({super.key, required this.todoId, required this.camera});

  @override
  ConsumerState<TakePhotoPage> createState() {
    return _TakePhotoWidgetState();
  }
}

class _TakePhotoWidgetState extends ConsumerState<TakePhotoPage> {
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

  Future<void> _takePhoto(BuildContext context) async {
    try {
      // Ensure the camera is initialized before taking a photo
      await _initializeControllerFuture;

      final XFile photo = await _cameraController.takePicture();
      // copy photo to new directory with ID as name
      String photoId = powersync.uuid.v4();
      final queue = await ref.read(attachmentQueueProvider.future);
      String storageDirectory = await queue.getStorageDirectory();
      await queue.localStorage
          .copyFile(photo.path, '$storageDirectory/$photoId.jpg');

      int photoSize = await photo.length();

      await ref.read(driftDatabase).addTodoPhoto(widget.todoId, photoId);
      await queue.saveFile(photoId, photoSize);
    } catch (e) {
      _log.info('Error taking photo: $e');
    }

    // After taking the photo, navigate back to the previous screen
    if (context.mounted) {
      Navigator.pop(context);
    }
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

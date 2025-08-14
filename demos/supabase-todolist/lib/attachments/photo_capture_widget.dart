import 'dart:async';
import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:logging/logging.dart';
import 'package:powersync_flutter_demo/attachments/queue.dart';

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
  final log = Logger('TakePhotoWidget');

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
  void dispose() {
    _cameraController.dispose();
    super.dispose();
  }

  Future<void> _takePhoto(context) async {
    try {
      log.info('Taking photo for todo: ${widget.todoId}');
      await _initializeControllerFuture;
      final XFile photo = await _cameraController.takePicture();

      // Read the photo data as bytes
      final photoFile = File(photo.path);
      if (!await photoFile.exists()) {
        log.warning('Photo file does not exist: ${photo.path}');
        return;
      }

      final photoData = await photoFile.readAsBytes();

      // Save the photo attachment with the byte data
      final attachment = await savePhotoAttachment(photoData, widget.todoId);

      log.info('Photo attachment saved with ID: ${attachment.id}');
    } catch (e) {
      log.severe('Error taking photo: $e');
    }
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

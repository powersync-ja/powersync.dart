import 'package:camera/camera.dart';
import 'package:flutter/widgets.dart';

late final CameraDescription? camera;

Future<CameraDescription?> setupCamera() async {
  // Ensure that plugin services are initialized so that `availableCameras()`
  // can be called before `runApp()`
  WidgetsFlutterBinding.ensureInitialized();
  // Obtain a list of the available cameras on the device.
  final cameras = await availableCameras();
  // Get a specific camera from the list of available cameras.
  final camera = cameras.isNotEmpty ? cameras.first : null;
  return camera;
}

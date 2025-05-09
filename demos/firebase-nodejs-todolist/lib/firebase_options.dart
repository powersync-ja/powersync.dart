// File generated by FlutterFire CLI.
// ignore_for_file: type=lint
import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

/// Default [FirebaseOptions] for use with your Firebase apps.
///
/// Example:
/// ```dart
/// import 'firebase_options.dart';
/// // ...
/// await Firebase.initializeApp(
///   options: DefaultFirebaseOptions.currentPlatform,
/// );
/// ```
class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      throw UnsupportedError(
        'DefaultFirebaseOptions have not been configured for web - '
        'you can reconfigure this by running the FlutterFire CLI again.',
      );
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      case TargetPlatform.macOS:
        return macos;
      case TargetPlatform.windows:
        return windows;
      case TargetPlatform.linux:
        throw UnsupportedError(
          'DefaultFirebaseOptions have not been configured for linux - '
          'you can reconfigure this by running the FlutterFire CLI again.',
        );
      default:
        throw UnsupportedError(
          'DefaultFirebaseOptions are not supported for this platform.',
        );
    }
  }

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyDBk2GgaUqLvPWGe6cI0h6G4ZZweS2JKGE',
    appId: '1:1069616552579:android:d2cb390fea186a49db59b6',
    messagingSenderId: '1069616552579',
    projectId: 'sample-firebase-ai-app-27d98',
    storageBucket: 'sample-firebase-ai-app-27d98.firebasestorage.app',
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyAOcRgRnbZv_aXm4jukQnLR4YR1nFNL8eQ',
    appId: '1:1069616552579:ios:0d30b90e81427c07db59b6',
    messagingSenderId: '1069616552579',
    projectId: 'sample-firebase-ai-app-27d98',
    storageBucket: 'sample-firebase-ai-app-27d98.firebasestorage.app',
    iosBundleId: 'co.powersync.demotodolist',
  );

  static const FirebaseOptions macos = FirebaseOptions(
    apiKey: 'AIzaSyAOcRgRnbZv_aXm4jukQnLR4YR1nFNL8eQ',
    appId: '1:1069616552579:ios:0d30b90e81427c07db59b6',
    messagingSenderId: '1069616552579',
    projectId: 'sample-firebase-ai-app-27d98',
    storageBucket: 'sample-firebase-ai-app-27d98.firebasestorage.app',
    iosBundleId: 'co.powersync.demotodolist',
  );

  static const FirebaseOptions windows = FirebaseOptions(
    apiKey: 'AIzaSyCSsnrrJEu126-EL0MMpLbdmt44nBinONo',
    appId: '1:1069616552579:web:795aadd36a32e2c5db59b6',
    messagingSenderId: '1069616552579',
    projectId: 'sample-firebase-ai-app-27d98',
    authDomain: 'sample-firebase-ai-app-27d98.firebaseapp.com',
    storageBucket: 'sample-firebase-ai-app-27d98.firebasestorage.app',
  );
}

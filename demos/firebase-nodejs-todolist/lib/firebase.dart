import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';

loadFirebase() async {
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
}

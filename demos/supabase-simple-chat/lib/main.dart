// ignore_for_file: avoid_print

import 'package:flutter/material.dart';
import './utils/constants.dart';
import './pages/splash_page.dart';
import './powersync.dart';
import 'package:logging/logging.dart';

final log = Logger('powersync-supabase');

Future<void> main() async {
  Logger.root.level = Level.INFO;
  Logger.root.onRecord.listen((record) {
    print(
        '[${record.loggerName}] ${record.level.name}: ${record.time}: ${record.message}');

    if (record.error != null) {
      print(record.error);
    }
    if (record.stackTrace != null) {
      print(record.stackTrace);
    }
  });

  WidgetsFlutterBinding.ensureInitialized();

  await openDatabase();

  //Some example code showing printf() style debugging
  final testResults = await db.getAll('SELECT * from messages');
  log.info('testResults = $testResults');

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'My Chat App',
      theme: appTheme,
      home: const SplashPage(),
    );
  }
}

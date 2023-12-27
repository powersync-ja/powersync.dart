import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:logging/logging.dart';

import './powersync.dart';
import './widgets/home_page.dart';
import './widgets/status_app_bar.dart';

void main() async {
  // Log info from PowerSync
  Logger.root.level = Level.INFO;
  Logger.root.onRecord.listen((record) {
    if (kDebugMode) {
      print(
          '[${record.loggerName}] ${record.level.name}: ${record.time}: ${record.message}');

      if (record.error != null) {
        print(record.error);
      }
      if (record.stackTrace != null) {
        print(record.stackTrace);
      }
    }
  });

  WidgetsFlutterBinding
      .ensureInitialized(); //required to get sqlite filepath from path_provider before UI has initialized
  await openDatabase();

  runApp(const MyApp());
}

const homePage = HomePage();

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
        title: 'PowerSync Flutter Demo',
        theme: ThemeData(
          primarySwatch: Colors.blue,
        ),
        home: homePage);
  }
}

class MyHomePage extends StatelessWidget {
  const MyHomePage({super.key, required this.title, required this.content});

  final String title;
  final Widget content;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: StatusAppBar(title: title),
      body: Center(child: content),
    );
  }
}

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';
import 'package:supabase_todolist_drift/models/schema.dart';
import 'package:supabase_todolist_drift/supabase.dart';

import 'powersync.dart';
import 'widgets/lists_page.dart';
import 'widgets/login_page.dart';
import 'widgets/query_widget.dart';
import 'widgets/signup_page.dart';
import 'widgets/status_app_bar.dart';

void main() async {
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

  //required to get sqlite filepath from path_provider before UI has initialized
  WidgetsFlutterBinding.ensureInitialized();
  await loadSupabase();

  runApp(const MyApp());
}

const defaultQuery = 'SELECT * from $todosTable';

const listsPage = ListsPage();
const homePage = listsPage;

const sqlConsolePage = Scaffold(
    appBar: StatusAppBar(title: 'SQL Console'),
    body: QueryWidget(defaultQuery: defaultQuery));

const loginPage = LoginPage();

const signupPage = SignupPage();

class MyApp extends ConsumerWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp(
      title: 'PowerSync Flutter Demo',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: ref.watch(isLoggedInProvider) ? homePage : loginPage,
    );
  }
}

class MyHomePage extends StatelessWidget {
  const MyHomePage(
      {super.key,
      required this.title,
      required this.content,
      this.floatingActionButton});

  final String title;
  final Widget content;
  final Widget? floatingActionButton;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: StatusAppBar(title: title),
      body: Center(child: content),
      floatingActionButton: floatingActionButton,
      drawer: Drawer(
        // Add a ListView to the drawer. This ensures the user can scroll
        // through the options in the drawer if there isn't enough vertical
        // space to fit everything.
        child: ListView(
          // Important: Remove any padding from the ListView.
          padding: EdgeInsets.zero,
          children: [
            const DrawerHeader(
              decoration: BoxDecoration(
                color: Colors.blue,
              ),
              child: Text(''),
            ),
            ListTile(
              title: const Text('SQL Console'),
              onTap: () {
                var navigator = Navigator.of(context);
                navigator.pop();

                navigator.push(MaterialPageRoute(
                  builder: (context) => sqlConsolePage,
                ));
              },
            ),
            ListTile(
              title: const Text('Sign Out'),
              onTap: () async {
                var navigator = Navigator.of(context);
                navigator.pop();
                await logout();

                navigator.pushReplacement(MaterialPageRoute(
                  builder: (context) => loginPage,
                ));
              },
            ),
          ],
        ),
      ),
    );
  }
}

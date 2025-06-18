import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:logging/logging.dart';

import './powersync/powersync.dart';
import './widgets/query_widget.dart';
import './widgets/status_app_bar.dart';
import 'models/counter.dart';

const String currentUserId = "test"; // Default current user ID

void main() async {
  Logger.root.level = Level.INFO;
  Logger.root.onRecord.listen((record) {
    if (kDebugMode) {
      print(
        '[${record.loggerName}] ${record.level.name}: ${record.time}: ${record.message}',
      );

      if (record.error != null) {
        print(record.error);
      }
      if (record.stackTrace != null) {
        print(record.stackTrace);
      }
    }
  });

  WidgetsFlutterBinding.ensureInitialized();
  await openDatabase(currentUserId);

  runApp(MyApp(loggedIn: true));
}

const defaultQuery = 'SELECT * from counter';

const countersPage = CountersPage();

const sqlConsolePage = Scaffold(
  appBar: StatusAppBar(title: Text('SQL Console')),
  body: QueryWidget(defaultQuery: defaultQuery),
);

class MyApp extends StatelessWidget {
  final bool loggedIn;

  const MyApp({super.key, required this.loggedIn});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'PowerSync Flutter Demo',
      theme: ThemeData(primarySwatch: Colors.blue),
      home: countersPage,
    );
  }
}

class CountersPage extends StatelessWidget {
  const CountersPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: StatusAppBar(title: const Text('User Counters')),
      body: Column(
        children: [
          // Current User Section
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            margin: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.blue.shade50,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.blue.shade200),
            ),
            child: StreamBuilder<Counter?>(
              stream: Counter.watchCurrentUserCounter(currentUserId),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                final counter = snapshot.data;
                final count = counter?.count ?? 0;

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Your Counter',
                      style: Theme.of(
                        context,
                      ).textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: Colors.blue.shade800,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text('User ID: $currentUserId'),
                    Text('Count: $count'),
                    const SizedBox(height: 12),
                    ElevatedButton.icon(
                      onPressed: () async {
                        if (counter == null) {
                          await Counter.create(
                            currentUserId,
                          ); 
                        } else {
                          await Counter.incrementCurrentUser(currentUserId);
                        }
                      },
                      icon: const Icon(Icons.add),
                      label: Text(
                        counter == null
                            ? 'Create Counter'
                            : 'Increment My Counter',
                      ),
                    ),
                  ],
                );
              },
            ),
          ),

          // Divider
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: Divider(thickness: 2),
          ),

          // All Users Section
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              'All User Counters',
              style: Theme.of(
                context,
              ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
            ),
          ),

          Expanded(
            child: StreamBuilder<List<Counter>>(
              stream: Counter.watchAllCounters(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (!snapshot.hasData || snapshot.data!.isEmpty) {
                  return const Center(child: Text('No counters yet'));
                }

                final counters = snapshot.data!;
                return ListView.builder(
                  itemCount: counters.length,
                  itemBuilder: (context, index) {
                    final counter = counters[index];
                    final isCurrentUser = counter.userId == currentUserId;

                    return ListTile(
                      leading:
                          isCurrentUser
                              ? Icon(Icons.person, color: Colors.blue.shade600)
                              : const Icon(Icons.person_outline),
                      title: Text(
                        'User: ${counter.userId}${isCurrentUser ? ' (You)' : ''}',
                        style: TextStyle(
                          fontWeight:
                              isCurrentUser
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                          color: isCurrentUser ? Colors.blue.shade800 : null,
                        ),
                      ),
                      subtitle: Text('Count: ${counter.count}'),
                      tileColor: isCurrentUser ? Colors.blue.shade50 : null,
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
      drawer: Drawer(
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            const DrawerHeader(
              decoration: BoxDecoration(color: Colors.blue),
              child: Text('Menu'),
            ),
            ListTile(
              title: const Text('SQL Console'),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => sqlConsolePage),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

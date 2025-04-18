import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:logging/logging.dart';

import 'navigation.dart';
import 'supabase.dart';
import 'utils/provider_observer.dart';

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

  runApp(const ProviderScope(
    observers: [LoggingProviderObserver()],
    child: MyApp(),
  ));
}

class MyApp extends HookConsumerWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(appRouter);

    // Bridge riverpod session provider to the listenable that auto_route wants
    // to re-evaluate route guards.
    final sessionNotifier = useValueNotifier(ref.read(isLoggedInProvider));
    ref.listen(isLoggedInProvider, (prev, now) {
      if (sessionNotifier.value != now) {
        // Using Timer.run() here to work around an issue with auto_route during
        // initialization.
        Timer.run(() {
          sessionNotifier.value = now;
        });
      }
    });

    return MaterialApp.router(
      routerConfig: router.config(
        reevaluateListenable: sessionNotifier,
      ),
      title: 'PowerSync Flutter Demo',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
    );
  }
}

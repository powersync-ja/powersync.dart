import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../navigation.gr.dart';
import '../supabase.dart';
import 'app_bar.dart';

final class PageLayout extends ConsumerWidget {
  final Widget content;
  final Widget? title;
  final Widget? floatingActionButton;
  final bool showDrawer;

  const PageLayout({
    super.key,
    required this.content,
    this.title,
    this.floatingActionButton,
    this.showDrawer = true,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: StatusAppBar(
        title: title ?? const Text('PowerSync Demo'),
      ),
      body: Center(child: content),
      floatingActionButton: floatingActionButton,
      drawer: showDrawer
          ? Drawer(
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
                      final route = context.topRoute;
                      if (route.name != SqlConsoleRoute.name) {
                        context.pushRoute(const SqlConsoleRoute());
                      }
                    },
                  ),
                  ListTile(
                    title: const Text('Sign Out'),
                    onTap: () async {
                      ref.read(authNotifierProvider.notifier).signOut();
                    },
                  ),
                ],
              ),
            )
          : null,
    );
  }
}

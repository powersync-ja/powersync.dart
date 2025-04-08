import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../supabase.dart';
import 'app_bar.dart';

final class PageLayout extends ConsumerWidget {
  final Widget content;
  final Widget? title;
  final Widget? floatingActionButton;

  const PageLayout({
    super.key,
    required this.content,
    this.title,
    this.floatingActionButton,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: StatusAppBar(title: title ?? const Text('PowerSync Demo')),
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
              onTap: () {},
            ),
            ListTile(
              title: const Text('Sign Out'),
              onTap: () async {
                ref.read(authNotifierProvider.notifier).signOut();
              },
            ),
          ],
        ),
      ),
    );
  }
}

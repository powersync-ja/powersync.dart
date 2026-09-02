import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:material_ui/material_ui.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:riverpod/experimental/mutation.dart';

import '../app_config.dart';
import '../navigation.gr.dart';
import '../stores/refresh.dart';
import '../supabase.dart';
import 'app_bar.dart';

final class PageLayout extends HookConsumerWidget {
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
    Widget body = Center(child: content);

    if (AppConfig.enableCheckpointRequests) {
      final refreshIndicatorKey =
          useMemoized(() => GlobalKey<RefreshIndicatorState>());
      final isRefreshing = ref.watch(refresh).isPending;
      final refreshingBefore = usePrevious(isRefreshing) ?? false;
      final scaffoldMessenger = ScaffoldMessenger.of(context);

      useEffect(() {
        // Show the refresh indicator when a refresh is triggered.
        if (!refreshingBefore && isRefreshing) {
          refreshIndicatorKey.currentState?.show();
        }

        // Show a status snackbar on completed sync.
        if (refreshingBefore && !isRefreshing) {
          SchedulerBinding.instance.addPostFrameCallback((_) {
            switch (ref.read(refresh)) {
              case MutationError():
                scaffoldMessenger
                    .showSnackBar(SnackBar(content: Text('Sync failed.')));
              case MutationSuccess():
                scaffoldMessenger.showSnackBar(
                    SnackBar(content: Text('Sync refresh complete!')));
              default:
                break;
            }
          });
        }
        return null;
      }, [refreshIndicatorKey, refreshingBefore, isRefreshing]);

      body = RefreshIndicator(
        key: refreshIndicatorKey,
        onRefresh: () {
          // This is called both when a child scrollable is swiped to refresh,
          // and by the useEffect hook above. Depending on what triggered it, we
          // either request a checkpoint or wait for the previous one to
          // complete.
          final isPending = ref.read(refresh).isPending;
          if (isPending) {
            final completer = Completer<void>();
            late final ProviderSubscription<MutationState> subscription;
            subscription = ref.listenManual(refresh, (previous, next) {
              if (!next.isPending) {
                subscription.close();
                completer.complete();
              }
            });
            return completer.future;
          } else {
            return syncNow(ref);
          }
        },
        child: body,
      );
    }

    return Scaffold(
      appBar: StatusAppBar(
        title: title ?? const Text('PowerSync Demo'),
      ),
      body: body,
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
                      ref.read(authProvider.notifier).signOut();
                    },
                  ),
                ],
              ),
            )
          : null,
    );
  }
}

import 'package:auto_route/auto_route.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:powersync/powersync.dart';

import '../app_config.dart';
import '../powersync/powersync.dart';
import '../screens/search.dart';
import '../stores/refresh.dart';

final appBar = AppBar(
  title: const Text('PowerSync Flutter Demo'),
);

final class StatusAppBar extends ConsumerWidget implements PreferredSizeWidget {
  final Widget title;

  const StatusAppBar({super.key, required this.title});

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final syncState = ref.watch(syncStatus);
    final statusIcon = _getStatusIcon(syncState);

    return AppBar(
      leading: const AutoLeadingButton(),
      title: title,
      actions: <Widget>[
        const _RefreshButton(),
        IconButton(
          onPressed: () {
            showSearch(context: context, delegate: FtsSearchDelegate());
          },
          icon: const Icon(Icons.search),
        ),
        statusIcon,
        // Make some space for the "Debug" banner, so that the status
        // icon isn't hidden
        if (kDebugMode) _makeIcon('Debug mode', Icons.developer_mode),
      ],
    );
  }
}

Widget _makeIcon(String text, IconData icon) {
  return Tooltip(
      message: text,
      child: SizedBox(width: 40, height: null, child: Icon(icon, size: 24)));
}

Widget _getStatusIcon(SyncStatus status) {
  if (status.anyError != null) {
    // The error message is verbose, could be replaced with something
    // more user-friendly
    if (!status.connected) {
      return _makeIcon(status.anyError!.toString(), Icons.cloud_off);
    } else {
      return _makeIcon(status.anyError!.toString(), Icons.sync_problem);
    }
  } else if (status.connecting) {
    return _makeIcon('Connecting', Icons.cloud_sync_outlined);
  } else if (!status.connected) {
    return _makeIcon('Not connected', Icons.cloud_off);
  } else if (status.uploading && status.downloading) {
    // The status changes often between downloading, uploading and both,
    // so we use the same icon for all three
    return _makeIcon('Uploading and downloading', Icons.cloud_sync_outlined);
  } else if (status.uploading) {
    return _makeIcon('Uploading', Icons.cloud_sync_outlined);
  } else if (status.downloading) {
    return _makeIcon('Downloading', Icons.cloud_sync_outlined);
  } else {
    return _makeIcon('Connected', Icons.cloud_queue);
  }
}

/// A port of `auto_route`'s` `AutoLeadingButton` that works with the standalone
/// `material_ui` package.
class AutoLeadingButton extends StatefulWidget {
  const AutoLeadingButton({super.key});

  @override
  State<AutoLeadingButton> createState() => _AutoLeadingButtonState();
}

class _AutoLeadingButtonState extends State<AutoLeadingButton> {
  late final PagelessRoutesObserver _pagelessRoutesObserver;

  @override
  void initState() {
    super.initState();
    _pagelessRoutesObserver = AutoRouter.of(context).pagelessRoutesObserver;
    _pagelessRoutesObserver.addListener(_handleRebuild);
  }

  @override
  void dispose() {
    super.dispose();
    _pagelessRoutesObserver.removeListener(_handleRebuild);
  }

  @override
  Widget build(BuildContext context) {
    final scope = RouterScope.of(context, watch: true);
    Widget? leading;
    if (scope.controller.canPop()) {
      final topPage = scope.controller.topPage;
      final useCloseButton = topPage?.fullscreenDialog ?? false;
      leading = useCloseButton
          ? CloseButton(
              key: const ValueKey(LeadingType.close),
              onPressed: scope.controller.maybePopTop,
            )
          : BackButton(
              key: const ValueKey(LeadingType.back),
              onPressed: scope.controller.maybePopTop,
            );
    }
    final ScaffoldState? scaffold = Scaffold.maybeOf(context);
    if (scaffold?.hasDrawer == true) {
      leading = IconButton(
        key: const ValueKey(LeadingType.drawer),
        icon: const Icon(Icons.menu),
        iconSize: Theme.of(context).iconTheme.size ?? 24,
        onPressed: _handleDrawerButton,
        tooltip: MaterialLocalizations.of(context).openAppDrawerTooltip,
      );
    }

    return leading ??
        const SizedBox.shrink(
          key: ValueKey(LeadingType.noLeading),
        );
  }

  void _handleDrawerButton() {
    Scaffold.of(context).openDrawer();
  }

  void _handleRebuild() {
    setState(() {});
  }
}

/// A refresh button implemented with [Sync Catch-Up](https://docs.powersync.com/client-sdks/advanced/checkpoint-requests).
class _RefreshButton extends HookConsumerWidget {
  const _RefreshButton();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!AppConfig.enableCheckpointRequests) {
      return const SizedBox.shrink();
    }

    final canRefreshNow = ref.watch(canRefresh);
    final isRefreshing = ref.watch(refresh).isPending;
    final controller = useAnimationController(
      duration: const Duration(seconds: 1),
    );

    useEffect(() {
      if (isRefreshing) {
        controller.repeat();
      } else {
        controller.reset();
      }
      return null;
    }, [isRefreshing]);

    void triggerRefresh() {
      syncNow(ref);
    }

    return Tooltip(
      message: 'Sync now',
      child: IconButton(
        onPressed: canRefreshNow ? triggerRefresh : null,
        icon: RotationTransition(
          turns: controller,
          child: const Icon(Icons.refresh),
        ),
      ),
    );
  }
}

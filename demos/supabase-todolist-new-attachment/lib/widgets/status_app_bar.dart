import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:powersync/powersync.dart';
import 'package:powersync_flutter_demo_new/widgets/fts_search_delegate.dart';
import '../powersync.dart';

class StatusAppBar extends StatelessWidget implements PreferredSizeWidget {
  final Widget title;

  const StatusAppBar({super.key, required this.title});

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    return StreamBuilder(
      stream: db.statusStream,
      initialData: db.currentStatus,
      builder: (context, snapshot) {
        final status = snapshot.data!;
        final statusIcon = _getStatusIcon(status);

        return AppBar(
          title: title,
          actions: <Widget>[
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
      },
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

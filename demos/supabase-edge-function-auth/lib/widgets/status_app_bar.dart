import 'dart:async';

import 'package:flutter/material.dart';
import 'package:powersync/powersync.dart';
import '../powersync.dart';

class StatusAppBar extends StatefulWidget implements PreferredSizeWidget {
  const StatusAppBar({super.key, required this.title});

  final String title;

  @override
  State<StatusAppBar> createState() => _StatusAppBarState();

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);
}

class _StatusAppBarState extends State<StatusAppBar> {
  late SyncStatus _connectionState;
  StreamSubscription<SyncStatus>? _syncStatusSubscription;

  @override
  void initState() {
    super.initState();
    _connectionState = db.currentStatus;
    _syncStatusSubscription = db.statusStream.listen((event) {
      setState(() {
        _connectionState = db.currentStatus;
      });
    });
  }

  @override
  void dispose() {
    super.dispose();
    _syncStatusSubscription?.cancel();
  }

  @override
  Widget build(BuildContext context) {
    const connectedIcon = IconButton(
      icon: Icon(Icons.wifi),
      tooltip: 'Connected',
      onPressed: null,
    );
    const disconnectedIcon = IconButton(
      icon: Icon(Icons.wifi_off),
      tooltip: 'Not connected',
      onPressed: null,
    );

    return AppBar(
      title: Text(widget.title),
      actions: <Widget>[
        _connectionState.connected ? connectedIcon : disconnectedIcon
      ],
    );
  }
}

import 'package:devtools_extensions/devtools_extensions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:powersync_devtools_extension/ui/appbar.dart';

import 'ui/common.dart';
import 'ui/overview.dart';
import 'ui/sql.dart';

void main() {
  runApp(const ProviderScope(child: PowerSyncDevToolsExtension()));
}

final class PowerSyncDevToolsExtension extends StatelessWidget {
  const PowerSyncDevToolsExtension({super.key});

  @override
  Widget build(BuildContext context) {
    return DevToolsExtension(
      child: DefaultTabController(
        length: 2,
        child: Scaffold(
          appBar: AppBar(
            leadingWidth: 150,
            leading: const PowerSyncLogo(),
            actions: const [SelectPowerSyncDatabase()],
            title: Text('Database Inspector'),
            bottom: TabBar(
              tabAlignment: .fill,
              tabs: [
                Tab(text: 'Overview'),
                Tab(text: 'SQL Console'),
              ],
            ),
          ),
          body: TabBarView(
            children: [
              HasDatabaseGuard(child: OverviewPage()),
              HasDatabaseGuard(child: SqlPage()),
            ],
          ),
        ),
      ),
    );
  }
}

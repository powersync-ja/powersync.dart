import 'package:devtools_app_shared/ui.dart';
import 'package:devtools_app_shared/utils.dart';
import 'package:devtools_extensions/devtools_extensions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:powersync/powersync.dart' hide Column;
import 'package:powersync_devtools_extension/state/databases.dart';

import '../state/sync_status.dart';

class OverviewPage extends ConsumerWidget {
  const OverviewPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(syncStatus);

    if (status == null) {
      return Text('Sync status could not be resolved');
    }

    return ListView(
      children: [
        _StatusSection(
          title: Text('Database Status'),
          body: _SyncStatus(status: status),
        ),
        _StatusSection(
          title: Text('Sync Streams'),
          body: _SyncStreams(status: status),
        ),
      ],
    );
  }
}

class _StatusSection extends StatelessWidget {
  final Widget title;
  final Widget body;

  const _StatusSection({required this.title, required this.body});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: IntrinsicHeight(
        child: DevToolsAreaPane(
          header: AreaPaneHeader(title: title),
          child: SelectableRegion(
            selectionControls: emptyTextSelectionControls,
            child: Padding(padding: const EdgeInsets.all(12.0), child: body),
          ),
        ),
      ),
    );
  }
}

class _SyncStatus extends ConsumerWidget {
  final SyncStatus status;

  const _SyncStatus({required this.status});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final credentials = ref.watch(lastCredentials);
    final filePath = ref.watch(selectedDatabase)?.ref.path;

    return Column(
      crossAxisAlignment: .start,
      children: [
        Row(
          children: [
            Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: 'Database path: ',
                    style: TextStyle(fontWeight: .bold),
                  ),
                  TextSpan(text: filePath),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(4),
              child: DevToolsButton(
                onPressed: () {
                  if (filePath != null) {
                    extensionManager.copyToClipboard(filePath);
                  }
                },
                outlined: false,
                tooltip: 'Copy path',
                icon: Icons.copy,
              ),
            ),
          ],
        ),
        if (credentials != null) ...[
          Row(
            children: [
              Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: 'Service URL: ',
                      style: TextStyle(fontWeight: .bold),
                    ),
                    TextSpan(text: credentials.original.endpoint),
                  ],
                ),
              ),
            ],
          ),
          Row(
            children: [
              Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: 'User ID: ',
                      style: TextStyle(fontWeight: .bold),
                    ),
                    TextSpan(text: credentials.userId),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(4),
                child: RoundedButtonGroup(
                  items: [
                    ButtonGroupItemData(
                      label: 'Show token',
                      onPressed: () {
                        showDialog(
                          barrierDismissible: true,
                          context: context,
                          builder: (_) =>
                              _TokenDetailsDialog(credentials: credentials),
                        );
                      },
                    ),
                    ButtonGroupItemData(
                      label: 'Open in Diagnostics App',
                      onPressed: () {
                        final url =
                            Uri.https('diagnostics-app.powersync.com', '/', {
                              'token': credentials.original.token,
                              'endpoint': credentials.original.endpoint,
                            });
                        launchUrl(url.toString());
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
        _SyncIssues(status: status),
      ],
    );
  }
}

final class _SyncIssues extends ConsumerWidget {
  final SyncStatus status;

  const _SyncIssues({required this.status});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pendingCrud = ref.watch(pendingCrudItems);
    final waitingForCheckpoint = ref.watch(isWaitingForCheckpoint);
    final issues = <Widget>[];

    void trackIssue(Widget issue) {
      if (issues.isNotEmpty) issues.add(const PaddedDivider.thin());
      issues.add(issue);
    }

    if (!status.connected) {
      if (status.connecting) {
        trackIssue(
          Text('Connection to PowerSync service is being established.'),
        );
      } else {
        trackIssue(
          Text.rich(
            TextSpan(
              text: 'Disconnected (no ongoing connection). ',
              children: [
                LinkTextSpan(
                  link: Link(
                    display: 'Learn how to connect to PowerSync',
                    url:
                        'https://docs.powersync.com/intro/setup-guide#connect-to-powersync-service-instance',
                  ),
                  context: context,
                ),
              ],
            ),
          ),
        );
      }
    }

    if (status.downloadError case final downloadError?) {
      trackIssue(Text('Download error: $downloadError'));
    }
    if (status.uploadError case final uploadError?) {
      trackIssue(Text('Upload error: $uploadError'));
    }
    if (pendingCrud.value case final value? when value > 0) {
      trackIssue(
        Text(
          '$value pending items in ps_crud prevent new data from being synced.',
        ),
      );
    } else if (waitingForCheckpoint.value == true) {
      trackIssue(
        Text(
          'Waiting for a write checkpoint containing previous uploads. If this status persists, new data would not be synced.',
        ),
      );
    }

    if (issues.isEmpty) {
      return Text('Sync client is connected without reported issues.');
    } else {
      return Column(
        crossAxisAlignment: .stretch,
        children: [
          Text(
            'These issues might affect PowerSync in your app',
            style: TextTheme.of(context).bodyLarge,
          ),
          Padding(
            padding: EdgeInsets.only(top: 16, left: 16),
            child: Column(crossAxisAlignment: .start, children: issues),
          ),
        ],
      );
    }
  }
}

class _SyncStreams extends StatelessWidget {
  final SyncStatus status;

  const _SyncStreams({required this.status});

  @override
  Widget build(BuildContext context) {
    if (status.syncStreams?.isEmpty != false) {
      return Text.rich(
        TextSpan(
          text: 'No Sync Streams found. ',
          children: [
            LinkTextSpan(
              link: Link(
                display: 'Learn more about Sync Streams',
                url: 'https://docs.powersync.com/sync/streams/overview',
              ),
              context: context,
            ),
          ],
        ),
      );
    }

    return DataTable(
      columns: [
        DataColumn(label: Text('Stream name')),
        DataColumn(label: Text('Parameters')),
        DataColumn(label: Text('Default')),
        DataColumn(label: Text('Active')),
        DataColumn(label: Text('Explicit')),
        DataColumn(label: Text('Priority')),
        DataColumn(label: Text('Last Synced')),
        DataColumn(label: Text('Eviction Time')),
      ],
      rows: [
        for (final stream in status.syncStreams ?? const <SyncStreamStatus>[])
          DataRow(
            cells: [
              DataCell(Text(stream.subscription.name)),
              DataCell(switch (stream.subscription.parameters) {
                null => Text('No parameters'),
                final parameters => FormattedJson(json: parameters),
              }),
              DataCell(Text(stream.subscription.isDefault ? 'Yes' : 'No')),
              DataCell(Text(stream.subscription.active ? 'Yes' : 'No')),
              DataCell(
                Text(
                  stream.subscription.hasExplicitSubscription ? 'Yes' : 'No',
                ),
              ),
              DataCell(Text(stream.priority.priorityNumber.toString())),
              DataCell(
                Text(
                  stream.subscription.lastSyncedAt?.toIso8601String() ??
                      'never',
                ),
              ),
              DataCell(
                Text(
                  stream.subscription.expiresAt?.toIso8601String() ?? 'never',
                ),
              ),
            ],
          ),
      ],
    );
  }
}

class _TokenDetailsDialog extends StatelessWidget {
  final DecodedCredentials credentials;

  const _TokenDetailsDialog({required this.credentials});

  @override
  Widget build(BuildContext context) {
    final tokenComponents = credentials.original.token.split('.');
    final componentColors = [Colors.orange, Colors.purple, Colors.green];

    return DevToolsDialog(
      includeDivider: false,
      title: Text('Token details'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 500),
        child: Column(
          crossAxisAlignment: .start,
          children: [
            SelectableText.rich(
              TextSpan(
                children: [
                  for (final (i, component) in tokenComponents.indexed) ...[
                    if (i != 0) TextSpan(text: '.'),
                    TextSpan(
                      text: component,
                      style: TextStyle(
                        color: componentColors[i % componentColors.length],
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (credentials.decodedClaims case final decoded?) ...[
              PaddedDivider(),
              FormattedJson(json: decoded),
            ],
          ],
        ),
      ),
      actions: [
        DevToolsButton(
          onPressed: () {
            Navigator.of(context).pop();
          },
          label: 'Done',
        ),
      ],
    );
  }
}

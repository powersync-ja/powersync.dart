import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:web/web.dart' as web;

import '../state/databases.dart';

final class PowerSyncLogo extends StatelessWidget {
  const PowerSyncLogo({super.key});

  @override
  Widget build(BuildContext context) {
    final asset = switch (Theme.brightnessOf(context)) {
      .light => 'light.svg',
      .dark => 'dark.svg',
    };

    return Padding(
      padding: const EdgeInsets.only(left: 8),
      child: HtmlElementView.fromTagName(
        key: ValueKey(asset),
        tagName: 'img',
        onElementCreated: (img) {
          img as web.HTMLImageElement;

          img.alt = 'PowerSync Logo';
          img.src = '/icons/$asset';
          img.style
            ..height = '100%'
            ..width = '100%';
        },
      ),
    );
  }
}

final class SelectPowerSyncDatabase extends ConsumerWidget {
  const SelectPowerSyncDatabase({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final databases = ref.watch(databaseList).value;
    final selected = ref.watch(selectedDatabase);
    final disabled = databases == null || databases.isEmpty || selected == null;

    return DropdownButton<DatabaseReference>(
      value: selected?.ref,
      disabledHint: Text('No database found'),
      items: disabled
          ? null
          : [
              for (final database in databases)
                DropdownMenuItem(value: database, child: Text(database.name)),
            ],
      onChanged: disabled ? null : (value) {},
    );
  }
}

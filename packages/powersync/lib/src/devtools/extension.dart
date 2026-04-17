import 'dart:async';
import 'dart:convert';
import 'dart:developer';

import 'package:path/path.dart' as p;

import '../version.dart';
import 'devtools.dart';
import 'protocol.dart';

final class PowerSyncDevToolsExtension {
  final Map<int, StreamSubscription<void>> _clientSubscriptions = {};
  int _subscriptionId = 0;

  Future<Object?> _handle(Map<String, String> parameters) async {
    final command = parameters['command'];
    final databaseId = int.parse(parameters['db']!);
    final tracked = ExposedPowerSyncDatabase.byId[databaseId];
    if (tracked == null) {
      throw ArgumentError('Unknown database handle: $databaseId');
    }

    switch (command) {
      case 'execute':
        final sql = parameters['sql']!;
        final sqlParameters = (json.decode(parameters['params']!) as List)
            .map(decodeSqlValue)
            .toList();

        await tracked.database.execute(sql, sqlParameters);
        return null;
      case 'select':
        final sql = parameters['sql']!;
        final sqlParameters = (json.decode(parameters['params']!) as List)
            .map(decodeSqlValue)
            .toList();

        final rs = await tracked.database
            .writeLock((ctx) => ctx.getAll(sql, sqlParameters));
        return {
          'columnNames': rs.columnNames,
          'rows': [
            for (final row in rs)
              [for (final column in row.values) encodeSqlValue(column)],
          ],
        };
      case 'schema':
        return tracked.database.schema.toJson();
      case 'table-updates-listen':
        final stream = tracked.database
            .onChange(null, throttle: const Duration(milliseconds: 100));
        final id = _subscriptionId++;
        _clientSubscriptions[id] = stream.listen((updateNotification) {
          postEvent('table-updates', {
            'subscription': id,
            'tables': updateNotification.tables.toList(),
          });
        });
        return id;
      case 'status-listen':
        final stream = tracked.database.statusStream;
        final id = _subscriptionId++;

        _clientSubscriptions[id] = stream.listen((status) {
          postEvent('status-updates', {
            'subscription': id,
            'status': serializeSyncStatus(status),
          });
        });

        return {
          'id': id,
          'current': serializeSyncStatus(tracked.database.currentStatus),
        };
      case 'unsubscribe':
        _clientSubscriptions.remove(int.parse(parameters['id']!))?.cancel();
        return null;
      default:
        throw UnsupportedError('Unsupported command: $command');
    }
  }

  static bool _registered = false;

  /// Registers the `ext.powersync` extension if it has not yet been registered
  /// on this isolate.
  static void registerIfNeeded() {
    if (!_registered) {
      _registered = true;

      final extension = PowerSyncDevToolsExtension();
      registerExtension('ext.powersync.database', (method, parameters) async {
        try {
          final result = await extension._handle(parameters);
          return ServiceExtensionResponse.result(json.encode({'ok': result}));
        } catch (error, stackTrace) {
          return ServiceExtensionResponse.error(
            ServiceExtensionResponse.extensionErrorMin,
            json.encode({
              'error': error.toString(),
              'trace': stackTrace.toString(),
            }),
          );
        }
      });

      registerExtension('ext.powersync.version', (method, parameters) async {
        return ServiceExtensionResponse.result(
            json.encode({'version': libraryVersion}));
      });

      registerExtension('ext.powersync.list', (method, parameters) async {
        return ServiceExtensionResponse.result(json.encode({
          'databases': [
            for (final db in ExposedPowerSyncDatabase.byId.values)
              {
                'id': db.id,
                'path': db.database.group.identifier,
                'name': p.basename(db.database.group.identifier),
                'lastCredentials': switch (db.lastCredentials) {
                  null => null,
                  final credentials => {
                      'endpoint': credentials.endpoint,
                      'token': credentials.token,
                    },
                }
              }
          ]
        }));
      });
    }
  }
}

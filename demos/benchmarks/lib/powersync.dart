// This file performs setup of the PowerSync database
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'package:flutter/foundation.dart';
import 'package:logging/logging.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:powersync/powersync.dart';
import 'package:powersync_benchmarks/models/benchmark_item.dart';

import './app_config.dart';
import './models/schema.dart';

final log = Logger('powersync-supabase');

/// Use Supabase for authentication and data upload.
class BackendConnector extends PowerSyncBackendConnector {
  http.Client client;

  BackendConnector() : client = http.Client();

  @override
  Future<PowerSyncCredentials?> fetchCredentials() async {
    return PowerSyncCredentials(
        endpoint: AppConfig.powersyncUrl, token: AppConfig.token);
  }

  // Upload pending changes to Supabase.
  @override
  Future<void> uploadData(PowerSyncDatabase database) async {
    // This function is called whenever there is data to upload, whether the
    // device is online or offline.
    // If this call throws an error, it is retried periodically.
    final transaction = await database.getNextCrudTransaction();
    if (transaction == null) {
      return;
    }

    var uri = Uri.parse('${AppConfig.backendUrl}/api/data');

    var body = jsonEncode({
      'batch': transaction.crud.map((op) {
        if (op.op == UpdateType.put) {
          return {
            'op': 'PUT',
            'table': op.table,
            'id': op.id,
            'data': op.opData
          };
        } else if (op.op == UpdateType.patch) {
          return {
            'op': 'PATCH',
            'table': op.table,
            'id': op.id,
            'data': op.opData
          };
        } else if (op.op == UpdateType.delete) {
          return {'op': 'DELETE', 'table': op.table, 'id': op.id};
        }
      }).toList()
    });
    var response = await client.post(uri,
        headers: {'Content-Type': 'application/json'}, body: body);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw http.ClientException(
          'Data upload failed with ${response.statusCode} ${response.body}');
    }

    await transaction.complete();
  }
}

/// Global reference to the database
late final PowerSyncDatabase db;

Future<String> getDatabasePath() async {
  const dbFilename = 'powersync-benchmarks.db';
  // getApplicationSupportDirectory is not supported on Web
  if (kIsWeb) {
    return dbFilename;
  }
  final dir = await getApplicationSupportDirectory();
  return join(dir.path, dbFilename);
}

Future<void> openDatabase() async {
  // Open the local database
  db = PowerSyncDatabase(
      schema: schema, path: await getDatabasePath(), logger: attachedLogger);
  await db.initialize();

  BenchmarkItem.updateItemBenchmarks();

  var currentConnector = BackendConnector();

  db.connect(
      connector: currentConnector,
      crudThrottleTime: const Duration(milliseconds: 1));
}

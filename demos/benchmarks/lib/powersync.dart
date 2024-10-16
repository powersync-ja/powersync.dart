// This file performs setup of the PowerSync database
import 'package:flutter/foundation.dart';
import 'package:logging/logging.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:powersync/powersync.dart';

import './app_config.dart';
import './models/schema.dart';

final log = Logger('powersync-supabase');

/// Use Supabase for authentication and data upload.
class BackendConnector extends PowerSyncBackendConnector {
  BackendConnector();

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

    // TODO: Implement
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

  var currentConnector = BackendConnector();

  db.connect(connector: currentConnector);
}

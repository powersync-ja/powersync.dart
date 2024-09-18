// This file performs setup of the PowerSync database
import 'package:flutter/foundation.dart';
import 'package:logging/logging.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:powersync/powersync.dart';
import 'package:powersync_django_todolist_demo/migrations/fts_setup.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:powersync_django_todolist_demo/api_client.dart';

import './app_config.dart';
import './models/schema.dart';

final log = Logger('powersync-django');
final prefs = SharedPreferencesAsync();

/// Postgres Response codes that we cannot recover from by retrying.
final List<RegExp> fatalResponseCodes = [
  // Class 22 — Data Exception
  // Examples include data type mismatch.
  RegExp(r'^22...$'),
  // Class 23 — Integrity Constraint Violation.
  // Examples include NOT NULL, FOREIGN KEY and UNIQUE violations.
  RegExp(r'^23...$'),
  // INSUFFICIENT PRIVILEGE - typically a row-level security violation
  RegExp(r'^42501$'),
];

class DjangoConnector extends PowerSyncBackendConnector {
  DjangoConnector();

  final ApiClient apiClient = ApiClient(AppConfig.djangoUrl);

  /// Get a token to authenticate against the PowerSync instance.
  @override
  Future<PowerSyncCredentials?> fetchCredentials() async {
    final userId = await getUserId();
    if (userId == null) {
      throw Exception('User does not have session');
    }
    // Somewhat contrived to illustrate usage, see auth docs here:
    // https://docs.powersync.com/usage/installation/authentication-setup/custom
    final session = await apiClient.getToken(userId);
    return PowerSyncCredentials(
        endpoint: AppConfig.powersyncUrl, token: session['token']);
  }

  // Upload pending changes to Postgres via Django backend
  @override
  Future<void> uploadData(PowerSyncDatabase database) async {
    final transaction = await database.getNextCrudTransaction();

    if (transaction == null) {
      return;
    }

    try {
      for (var op in transaction.crud) {
        final record = {
          'table': op.table,
          'data': {'id': op.id, ...?op.opData},
        };

        switch (op.op) {
          case UpdateType.put:
            await apiClient.upsert(record);
            break;
          case UpdateType.patch:
            await apiClient.update(record);
            break;
          case UpdateType.delete:
            await apiClient.delete(record);
            break;
        }
      }
      await transaction.complete();
    } on Exception catch (e) {
      log.severe('Error uploading data', e);
      // Error may be retryable - e.g. network error or temporary server error.
      // Throwing an error here causes this call to be retried after a delay.
      rethrow;
    }
  }
}

/// Global reference to the database
late final PowerSyncDatabase db;

// Hacky flag to ensure the database is only initialized once, better to do this with listeners
bool _dbInitialized = false;

/// id of the user currently logged in
Future<String?> getUserId() async {
  return await prefs.getString('id');
}

Future<bool> isLoggedIn() async {
  final userId = await getUserId();
  return userId != null;
}

Future<String> getDatabasePath() async {
  const dbFilename = 'powersync-demo.db';
  // getApplicationSupportDirectory is not supported on Web
  if (kIsWeb) {
    return dbFilename;
  }

  final dir = await getApplicationSupportDirectory();
  return join(dir.path, dbFilename);
}

// opens the database and connects if logged in
Future<void> openDatabase() async {
  // Open the local database
  if (!_dbInitialized) {
    db = PowerSyncDatabase(
        schema: schema, path: await getDatabasePath(), logger: attachedLogger);
    await db.initialize();

    // Demo using SQLite Full-Text Search with PowerSync.
    // See https://docs.powersync.com/usage-examples/full-text-search for more details
    await configureFts(db);
    _dbInitialized = true;
  }

  DjangoConnector? currentConnector;

  if (await isLoggedIn()) {
    // If the user is already logged in, connect immediately.
    // Otherwise, connect once logged in.
    currentConnector = DjangoConnector();
    db.connect(connector: currentConnector);
  }
}

/// Explicit sign out - clear database and log out.
Future<void> logout() async {
  await prefs.remove('id');
  await db.disconnectAndClear();
}

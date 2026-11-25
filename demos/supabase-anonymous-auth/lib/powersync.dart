// This file performs setup of the PowerSync database
import 'package:universal_io/io.dart';
import 'package:flutter/foundation.dart';
import 'package:logging/logging.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:powersync/powersync.dart';

import 'package:supabase_flutter/supabase_flutter.dart';

import './app_config.dart';
import './models/schema.dart';
import './supabase.dart';

final log = Logger('powersync-supabase');

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

/// Use Supabase for authentication and data upload.
class SupabaseConnector implements Authenticator, MutationUploader {
  String? _token;

  SupabaseConnector();

  /// Get a Supabase token to authenticate against the PowerSync instance.
  @override
  Future<String> resolveCredentials(Future<void> abortSignal) async {
    if (_token case final token?) {
      return token;
    }

    final authResponse = await Supabase.instance.client.functions
        .invoke('powersync-auth-anonymous', method: HttpMethod.get);
    if (authResponse.status != 200) {
      throw HttpException(
          "Failed to get PowerSync Token, code=${authResponse.status}");
    }

    final data = authResponse.data as Map<String, dynamic>;
    return _token = data['token'] as String;
  }

  @override
  void invalidateCredentials() {
    _token = null;
  }

  @override
  Future<void> upload(
    PowerSyncDatabase database,
    Future<void> abortSignal,
  ) async {
    // This function is called whenever there is data to upload, whether the
    // device is online or offline.
    // If this call throws an error, it is retried periodically.
    final transaction = await database.getNextCrudTransaction();
    if (transaction == null) {
      return;
    }

    final rest = Supabase.instance.client.rest;
    CrudEntry? lastOp;
    try {
      // Note: If transactional consistency is important, use database functions
      // or edge functions to process the entire transaction in a single call.
      for (var op in transaction.crud) {
        lastOp = op;

        final table = rest.from(op.table);
        if (op.op == UpdateType.put) {
          var data = Map<String, dynamic>.of(op.opData!);
          data['id'] = op.id;
          await table.upsert(data);
        } else if (op.op == UpdateType.patch) {
          await table.update(op.opData!).eq('id', op.id);
        } else if (op.op == UpdateType.delete) {
          await table.delete().eq('id', op.id);
        }
      }

      // All operations successful.
      await transaction.complete();
    } on PostgrestException catch (e) {
      if (e.code != null &&
          fatalResponseCodes.any((re) => re.hasMatch(e.code!))) {
        /// Instead of blocking the queue with these errors,
        /// discard the (rest of the) transaction.
        ///
        /// Note that these errors typically indicate a bug in the application.
        /// If protecting against data loss is important, save the failing records
        /// elsewhere instead of discarding, and/or notify the user.
        log.severe('Data upload error - discarding $lastOp', e);
        await transaction.complete();
      } else {
        // Error may be retryable - e.g. network error or temporary server error.
        // Throwing an error here causes this call to be retried after a delay.
        rethrow;
      }
    }
  }
}

/// Global reference to the database
late final PowerSyncDatabase db;

/// id of the user currently logged in
String? getUserId() {
  return Supabase.instance.client.auth.currentSession?.user.id;
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

Future<void> openDatabase() async {
  // Open the local database
  db = PowerSyncDatabase(schema: schema, path: await getDatabasePath());
  await db.initialize();

  await loadSupabase();

  final connector = SupabaseConnector();
  db.connect(
    connector: ConnectRequest(
      endpoint: AppConfig.powersyncUrl,
      authenticator: connector,
      uploader: connector,
    ),
  );
}

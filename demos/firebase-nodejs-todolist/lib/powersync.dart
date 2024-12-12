// This file performs setup of the PowerSync database
import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:logging/logging.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:powersync/powersync.dart';
import 'package:http/http.dart' as http;

import './app_config.dart';
import './models/schema.dart';
import './firebase.dart';

final log = Logger('powersync-nodejs');

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

/// Use Custom Node.js backend for authentication and data upload.
class BackendConnector extends PowerSyncBackendConnector {
  PowerSyncDatabase db;
  //ignore: unused_field
  Future<void>? _refreshFuture;

  BackendConnector(this.db);

  /// Get a token to authenticate against the PowerSync instance.
  @override
  Future<PowerSyncCredentials?> fetchCredentials() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      // Not logged in
      return null;
    }
    final idToken = await user.getIdToken();

    var url = Uri.parse("${AppConfig.backendUrl}/api/auth/token");

    Map<String, String> headers = {
      'Authorization': 'Bearer $idToken',
      'Content-Type': 'application/json', // Adjust content-type if needed
    };

    final response = await http.get(
      url,
      headers: headers,
    );

    if (response.statusCode == 200) {
      final body = response.body;
      Map<String, dynamic> parsedBody = jsonDecode(body);
      // Use the access token to authenticate against PowerSync
      // userId and expiresAt are for debugging purposes only
      final expiresAt = parsedBody['expiresAt'] == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(
              parsedBody['expiresAt']! * 1000);
      return PowerSyncCredentials(
          endpoint: parsedBody['powerSyncUrl'],
          token: parsedBody['token'],
          userId: parsedBody['userId'],
          expiresAt: expiresAt);
    } else {
      print('Request failed with status: ${response.statusCode}');
      return null;
    }
  }

  @override
  void invalidateCredentials() {
    // Trigger a session refresh if auth fails on PowerSync.
    // However, in some cases it can be a while before the session refresh is
    // retried. We attempt to trigger the refresh as soon as we get an auth
    // failure on PowerSync.
    //
    // This could happen if the device was offline for a while and the session
    // expired, and nothing else attempt to use the session it in the meantime.
    //
    // Timeout the refresh call to avoid waiting for long retries,
    // and ignore any errors. Errors will surface as expired tokens.
  }

  // Upload pending changes to Node.js Backend.
  @override
  Future<void> uploadData(PowerSyncDatabase database) async {
    // This function is called whenever there is data to upload, whether the
    // device is online or offline.
    // If this call throws an error, it is retried periodically.
    final transaction = await database.getNextCrudTransaction();
    if (transaction == null) {
      return;
    }

    CrudEntry? lastOp;
    try {
      // Note: If transactional consistency is important, use database functions
      // or edge functions to process the entire transaction in a single call.
      for (var op in transaction.crud) {
        lastOp = op;

        var row = Map<String, dynamic>.of(op.opData!);
        row['id'] = op.id;
        Map<String, dynamic> data = {"table": op.table, "data": row};
        if (op.op == UpdateType.put) {
          await upsert(data);
        } else if (op.op == UpdateType.patch) {
          await update(data);
        } else if (op.op == UpdateType.delete) {
          data = {
            "table": op.table,
            "data": {"id": op.id}
          };
          await delete(data);
        }
      }

      // All operations successful.
      await transaction.complete();
    } on http.ClientException catch (e) {
      // Error may be retryable - e.g. network error or temporary server error.
      // Throwing an error here causes this call to be retried after a delay.
      log.warning('Client exception', e);
      rethrow;
    } catch (e) {
      /// Instead of blocking the queue with these errors,
      /// discard the (rest of the) transaction.
      ///
      /// Note that these errors typically indicate a bug in the application.
      /// If protecting against data loss is important, save the failing records
      /// elsewhere instead of discarding, and/or notify the user.
      log.severe('Data upload error - discarding $lastOp', e);
      await transaction.complete();
    }
  }
}

/// Global reference to the database
late final PowerSyncDatabase db;

upsert(data) async {
  var url = Uri.parse("${AppConfig.backendUrl}/api/data");

  try {
    var response = await http.put(
      url,
      headers: <String, String>{
        'Content-Type': 'application/json', // Adjust content-type if needed
      },
      body: jsonEncode(data), // Encode data to JSON
    );

    if (response.statusCode == 200) {
      log.info('PUT request successful: ${response.body}');
    } else {
      log.severe('PUT request failed with status: ${response.statusCode}');
    }
  } catch (e) {
    log.severe('Exception occurred: $e');
    rethrow;
  }
}

update(data) async {
  var url = Uri.parse("${AppConfig.backendUrl}/api/data");

  try {
    var response = await http.patch(
      url,
      headers: <String, String>{
        'Content-Type': 'application/json', // Adjust content-type if needed
      },
      body: jsonEncode(data), // Encode data to JSON
    );

    if (response.statusCode == 200) {
      log.info('PUT request successful: ${response.body}');
    } else {
      log.severe('PUT request failed with status: ${response.statusCode}');
    }
  } catch (e) {
    log.severe('Exception occurred: $e');
    rethrow;
  }
}

delete(data) async {
  var url = Uri.parse("${AppConfig.backendUrl}/api/data");

  try {
    var response = await http.delete(
      url,
      headers: <String, String>{
        'Content-Type': 'application/json', // Adjust content-type if needed
      },
      body: jsonEncode(data), // Encode data to JSON
    );

    if (response.statusCode == 200) {
      log.info('DELETE request successful: ${response.body}');
    } else {
      log.severe('DELETE request failed with status: ${response.statusCode}');
    }
  } catch (e) {
    log.severe('Exception occurred: $e');
    rethrow;
  }
}

isLoggedIn() {
  final user = FirebaseAuth.instance.currentUser;
  return user != null;
}

/// id of the user currently logged in
String? getUserId() {
  final user = FirebaseAuth.instance.currentUser;
  return user!.uid;
}

Future<String> getDatabasePath() async {
  final dir = await getApplicationSupportDirectory();
  return join(dir.path, 'powersync-demo.db');
}

Future<void> openDatabase() async {
  // Open the local database
  db = PowerSyncDatabase(
    schema: schema,
    path: await getDatabasePath(),
    logger: attachedLogger,
  );
  await db.initialize();
  BackendConnector? currentConnector;

  await loadFirebase();

  final userLoggedIn = isLoggedIn();
  if (userLoggedIn) {
    // If the user is already logged in, connect immediately.
    // Otherwise, connect once logged in.
    currentConnector = BackendConnector(db);
    db.connect(connector: currentConnector);
  } else {
    log.info('User not logged in, setting connection');
  }

  FirebaseAuth.instance.authStateChanges().listen((User? user) async {
    if (user != null) {
      // Connect to PowerSync when the user is signed in
      currentConnector = BackendConnector(db);
      db.connect(connector: currentConnector!);
    } else {
      currentConnector = null;
      await db.disconnect();
    }
  });
}

/// Explicit sign out - clear database and log out.
Future<void> logout() async {
  await FirebaseAuth.instance.signOut();
  await db.disconnectAndClear();
}

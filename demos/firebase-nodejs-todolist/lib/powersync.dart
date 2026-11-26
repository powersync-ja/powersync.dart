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
class BackendConnector implements Authenticator, MutationUploader {
  String? _token;

  BackendConnector();

  /// Get a token to authenticate against the PowerSync instance.
  @override
  Future<String> resolveCredentials(Future<void> abortSignal) async {
    if (_token case String token) {
      return token;
    }

    final idToken = await FirebaseAuth.instance.currentUser?.getIdToken();
    if (idToken == null) {
      throw StateError('No Firebase ID token available');
    }

    final url = Uri.parse('${AppConfig.backendUrl}/api/auth/token');
    final response = await http.get(
      url,
      headers: {
        'Authorization': 'Bearer $idToken',
        'Content-Type': 'application/json',
      },
    );

    if (response.statusCode != 200) {
      throw http.ClientException(
        'Failed to get PowerSync token, status=${response.statusCode}',
        url,
      );
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    return _token = data['token'] as String;
  }

  @override
  void invalidateCredentials() {
    _token = null;
  }

  // Upload pending changes to Node.js Backend.
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

Future<void> upsert(Map<String, dynamic> data) async {
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

Future<void> update(Map<String, dynamic> data) async {
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

Future<void> delete(Map<String, dynamic> data) async {
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

bool isLoggedIn() {
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

  await loadFirebase();

  final userLoggedIn = isLoggedIn();
  if (userLoggedIn) {
    // If the user is already logged in, connect immediately.
    // Otherwise, connect once logged in.
    final connector = BackendConnector();
    db.connect(
      connector: ConnectRequest(
        endpoint: AppConfig.powersyncUrl,
        authenticator: connector,
        uploader: connector,
      ),
    );
  } else {
    log.info('User not logged in, setting connection');
  }

  FirebaseAuth.instance.authStateChanges().listen((User? user) async {
    if (user != null) {
      // Connect to PowerSync when the user is signed in
      final connector = BackendConnector();
      db.connect(
        connector: ConnectRequest(
          endpoint: AppConfig.powersyncUrl,
          authenticator: connector,
          uploader: connector,
        ),
      );
    } else {
      await db.disconnect();
    }
  });
}

/// Explicit sign out - clear database and log out.
Future<void> logout() async {
  await FirebaseAuth.instance.signOut();
  await db.disconnectAndClear();
}

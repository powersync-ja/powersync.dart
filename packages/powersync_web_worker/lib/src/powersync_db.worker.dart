library;

/// This file needs to be compiled to JavaScript with the command
/// dart compile js -O4 packages/powersync_web_worker/lib/src/powersync_db.worker.dart -o assets/powersync_db.worker.js
/// The output should then be included in each project's `web` directory
///
/// NOTE: This package contains some code duplicated from [sqlite_async.dart]
/// and [powersync.dart].
/// This is only necessary while we are using a
/// [forked](https://github.com/powersync-ja/drift/tree/test) version of Drift
/// which is not published as a package, but imported from a Git Repository.
///
/// [sqlite_async.dart] is a published package which cannot depend on Git
/// Repository dependencies, it instead depends on `drift: 2.15.0`.
/// This is possible since the forked changes are only on the compiled
/// worker side. SQLite Async can use the standard Drift client.
///
/// [powersync.dart] depends on [sqlite_async.dart], but it needs to use
/// the forked [drift.dart] library in order to compile its web worker.
/// Since both packages are published, they cannot depend on the forked
/// Drift Git repository.
///
/// This intermediate package exists only to compile the Javascript
/// web worker for [powersync.dart]. It cannot depend on [powersync.dart]
/// or [sqlite_async.dart] since those require the hosted `drift: 2.15.0`
/// dependency. Dart's package manager cannot resolve using both.
///
/// Code duplication is required since this package cannot depend on the
/// other libraries. This will be solved once a published Drift package
/// is available.

import 'dart:convert';

import 'package:drift/wasm.dart';
import 'package:sqlite3/common.dart';
import 'package:uuid/uuid.dart';
import 'package:uuid/data.dart';
import 'package:uuid/rng.dart';

/// Custom function which exposes CommonDatabase.autocommit
const sqliteAsyncAutoCommitCommand = 'sqlite_async_autocommit';

void setupDB(CommonDatabase database) {
  /// Duplicate from [sqlite_async.dart]
  database.createFunction(
      functionName: sqliteAsyncAutoCommitCommand,
      argumentCount: const AllowedArgumentCount(0),
      function: (args) {
        return database.autocommit;
      });

  /// Functions below are duplicates from [powersync.dart]
  database.createFunction(
      functionName: 'powersync_diff',
      argumentCount: const AllowedArgumentCount(2),
      deterministic: true,
      directOnly: false,
      function: (args) {
        final oldData = jsonDecode(args[0] as String) as Map<String, dynamic>;
        final newData = jsonDecode(args[1] as String) as Map<String, dynamic>;

        Map<String, dynamic> result = {};

        for (final newEntry in newData.entries) {
          final oldValue = oldData[newEntry.key];
          final newValue = newEntry.value;

          if (newValue != oldValue) {
            result[newEntry.key] = newValue;
          }
        }

        for (final key in oldData.keys) {
          if (!newData.containsKey(key)) {
            result[key] = null;
          }
        }

        return jsonEncode(result);
      });

  final uuid = Uuid(goptions: GlobalOptions(CryptoRNG()));

  database.createFunction(
    functionName: 'uuid',
    argumentCount: const AllowedArgumentCount(0),
    function: (args) {
      return uuid.v4();
    },
  );
  database.createFunction(
    // Postgres compatibility
    functionName: 'gen_random_uuid',
    argumentCount: const AllowedArgumentCount(0),
    function: (args) => uuid.v4(),
  );
  database.createFunction(
    functionName: 'powersync_sleep',
    argumentCount: const AllowedArgumentCount(1),
    function: (args) {
      // Can't perform synchronous sleep on web
      final millis = args[0] as int;
      return millis;
    },
  );

  database.createFunction(
    functionName: 'powersync_connection_name',
    argumentCount: const AllowedArgumentCount(0),
    function: (args) {
      return 'N/A';
    },
  );
}

void main() {
  WasmDatabase.workerMainForOpen(
    setupAllDatabases: setupDB,
  );
}

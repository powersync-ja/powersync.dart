import 'dart:convert';

import 'package:sqlite_async/sqlite3_common.dart' as sqlite;
import 'package:sqlite_async/sqlite3_common.dart';

void setupCommonDBFunctions(CommonDatabase db) {
  db.createFunction(
      functionName: 'powersync_diff',
      argumentCount: const sqlite.AllowedArgumentCount(2),
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
}

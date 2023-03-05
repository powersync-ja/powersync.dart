import './schema.dart';

import 'package:sqlite3/sqlite3.dart' as sqlite;

const String maxOpId = '9223372036854775807';

String createViewStatement(Table table) {
  final columnNames =
      table.columns.map((column) => '"${column.name}"').join(', ');

  if (table.insertOnly) {
    final nulls = table.columns.map((column) => 'NULL').join(', ');
    return 'CREATE TEMP VIEW IF NOT EXISTS "${table.name}"("id", $columnNames) AS SELECT NULL, $nulls WHERE 0';
  }
  final select = table.columns.map(mapColumn).join(', ');
  return 'CREATE TEMP VIEW IF NOT EXISTS "${table.name}"("id", $columnNames) AS SELECT "id", $select FROM "${table.internalName}"';
}

String mapColumn(Column column) {
  return "CAST(json_extract(data, '\$.${column.name}') as ${column.type})";
}

List<String> createViewTriggerStatements(Table table) {
  if (table.localOnly) {
    return createViewTriggerStatementsLocal(table);
  } else if (table.insertOnly) {
    return createViewTriggerStatementsInsert(table);
  }
  final type = table.name;
  final internalNameE = '"${table.internalName}"';

  final jsonFragment = table.columns
      .map((column) => "'${column.name}', NEW.${column.name}")
      .join(', ');
  final jsonFragmentOld = table.columns
      .map((column) => "'${column.name}', OLD.${column.name}")
      .join(', ');
  return [
    """
CREATE TEMP TRIGGER IF NOT EXISTS "ps_view_insert_$type"
INSTEAD OF INSERT ON "$type"
FOR EACH ROW
BEGIN
  SELECT CASE
    WHEN (NEW.id IS NULL)
    THEN RAISE (FAIL, 'id is required')
  END;
  INSERT INTO $internalNameE(id, data)
    SELECT NEW.id, json_object($jsonFragment);
  INSERT INTO ps_crud(data) SELECT json_object('op', 'PUT', 'type', '$type', 'id', NEW.id, 'data', json(powersync_diff('{}', json_object($jsonFragment))));
  INSERT INTO ps_oplog(bucket, op_id, op, row_type, row_id, hash, superseded)
    SELECT '\$local',
           1,
           'REMOVE',
           '$type',
           NEW.id,
           0,
           0;
  INSERT OR REPLACE INTO ps_buckets(name, pending_delete, last_op, target_op) VALUES('\$local', 1, 0, $maxOpId);
END;""",
    """
CREATE TEMP TRIGGER IF NOT EXISTS "ps_view_update_$type"
INSTEAD OF UPDATE ON "$type"
FOR EACH ROW
BEGIN
  SELECT CASE
    WHEN (OLD.id != NEW.id)
    THEN RAISE (FAIL, 'Cannot update id')
  END;
  UPDATE $internalNameE
        SET data = json_object($jsonFragment)
        WHERE id = NEW.id;
  INSERT INTO ps_crud(data) SELECT json_object('op', 'PATCH', 'type', '$type', 'id', NEW.id, 'data', json(powersync_diff(json_object($jsonFragmentOld), json_object($jsonFragment))));
  INSERT INTO ps_oplog(bucket, op_id, op, row_type, row_id, hash, superseded)
    SELECT '\$local',
           1,
           'REMOVE',
           '$type',
           NEW.id,
           0,
           0;
  INSERT OR REPLACE INTO ps_buckets(name, pending_delete, last_op, target_op) VALUES('\$local', 1, 0, $maxOpId);
END;""",
    """
CREATE TEMP TRIGGER IF NOT EXISTS "ps_view_delete_$type"
INSTEAD OF DELETE ON "$type"
FOR EACH ROW
BEGIN
  DELETE FROM $internalNameE WHERE id = OLD.id;
  INSERT INTO ps_crud(data) SELECT json_object('op', 'DELETE', 'type', '$type', 'id', OLD.id);
END;"""
  ];
}

List<String> createViewTriggerStatementsLocal(Table table) {
  final type = table.name;
  final internalNameE = '"${table.internalName}"';

  final jsonFragment = table.columns
      .map((column) => "'${column.name}', NEW.${column.name}")
      .join(', ');
  return [
    """
CREATE TEMP TRIGGER IF NOT EXISTS "ps_view_insert_$type"
INSTEAD OF INSERT ON "$type"
FOR EACH ROW
BEGIN
  INSERT INTO $internalNameE(id, data)
    SELECT NEW.id, json_object($jsonFragment);
END;""",
    """
CREATE TEMP TRIGGER IF NOT EXISTS "ps_view_update_$type"
INSTEAD OF UPDATE ON "$type"
FOR EACH ROW
BEGIN
  SELECT CASE
    WHEN (OLD.id != NEW.id)
    THEN RAISE (FAIL, 'Cannot update id')
  END;
  UPDATE $internalNameE
        SET data = json_object($jsonFragment)
        WHERE id = NEW.id;
END;""",
    """
CREATE TEMP TRIGGER IF NOT EXISTS "ps_view_delete_$type"
INSTEAD OF DELETE ON "$type"
FOR EACH ROW
BEGIN
  DELETE FROM $internalNameE WHERE id = OLD.id;
END;"""
  ];
}

List<String> createViewTriggerStatementsInsert(Table table) {
  final type = table.name;

  final jsonFragment = table.columns
      .map((column) => "'${column.name}', NEW.${column.name}")
      .join(', ');
  return [
    """
CREATE TEMP TRIGGER IF NOT EXISTS "ps_view_insert_$type"
INSTEAD OF INSERT ON "$type"
FOR EACH ROW
BEGIN
  INSERT INTO ps_crud(data) SELECT json_object('op', 'PUT', 'type', '$type', 'id', NEW.id, 'data', json(powersync_diff('{}', json_object($jsonFragment))));
END;"""
  ];
}

/// Sync the schema to the local database.
///
/// Must be wrapped in a transaction.
///
/// Returns a list of temporary statements to execute in other db connections.
List<String> updateSchema(sqlite.Database db, Schema schema) {
  List<String> secondaryConnectionOps = [];

  secondaryConnectionOps = [];
  _createTablesAndIndexes(db, schema);

  for (var model in schema.tables) {
    var createViewOp = createViewStatement(model);
    secondaryConnectionOps.add(createViewOp);
    db.execute(createViewOp);
    for (final op in createViewTriggerStatements(model)) {
      secondaryConnectionOps.add(op);
      db.execute(op);
    }
  }

  return secondaryConnectionOps;
}

/// Sync the schema to the local database.
///
/// Does not create triggers or temporary views.
///
/// Must be wrapped in a transaction.
void _createTablesAndIndexes(sqlite.Database db, Schema schema) {
  // Make sure to refresh tables in the same transaction as updating them
  final existingTableRows = db.select(
      "SELECT name FROM sqlite_master WHERE type='table' AND name GLOB 'ps_data_*'");
  final existingIndexRows = db.select(
      "SELECT name, sql FROM sqlite_master WHERE type='index' AND name GLOB 'ps_data_*'");

  final Set<String> remainingTables = {};
  final Map<String, String> remainingIndexes = {};
  for (final row in existingTableRows) {
    remainingTables.add(row['name'] as String);
  }
  for (final row in existingIndexRows) {
    remainingIndexes[row['name'] as String] = row['sql'] as String;
  }

  for (final table in schema.tables) {
    if (table.insertOnly) {
      // Does not have a physical table
      continue;
    }
    final tableName = table.internalName;
    final exists = remainingTables.contains(tableName);
    remainingTables.remove(tableName);
    if (exists) {
      continue;
    }

    db.execute("""CREATE TABLE "$tableName"
    (
    id   TEXT PRIMARY KEY NOT NULL,
    data TEXT
    )""");

    if (!table.localOnly) {
      db.execute("""INSERT INTO "$tableName"(id, data)
    SELECT id, data
    FROM ps_untyped
    WHERE type = ?""", [table.name]);
      db.execute("""DELETE
    FROM ps_untyped
    WHERE type = ?""", [table.name]);
    }

    for (final index in table.indexes) {
      final fullName = index.fullName(table);
      final sql = index.toSqlDefinition(table);
      if (remainingIndexes.containsKey(fullName)) {
        final existingSql = remainingIndexes[fullName];
        if (existingSql == sql) {
          continue;
        } else {
          db.execute('DROP INDEX "$fullName"');
        }
      }
      db.execute(sql);
    }
  }

  for (final indexName in remainingIndexes.keys) {
    db.execute('DROP INDEX "$indexName"');
  }

  for (final tableName in remainingTables) {
    final typeMatch = RegExp("^ps_data__(.+)\$").firstMatch(tableName);
    if (typeMatch != null) {
      // Not local-only
      final type = typeMatch[1];
      db.execute(
          'INSERT INTO ps_untyped(type, id, data) SELECT ?, id, data FROM "$tableName"',
          [type]);
    }
    db.execute('DROP TABLE "$tableName"');
  }
}

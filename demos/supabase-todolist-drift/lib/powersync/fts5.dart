import 'dart:async';

import 'package:drift/drift.dart';

import 'schema.dart';

Future<void> createFts5Tables({
  required DatabaseConnectionUser db,
  required String tableName,
  required List<String> columns,
  String tokenizationMethod = 'unicode61',
}) async {
  String internalName =
      schema.tables.firstWhere((table) => table.name == tableName).internalName;
  String stringColumns = columns.join(', ');

  await db.customStatement('''
      CREATE VIRTUAL TABLE IF NOT EXISTS fts_$tableName
      USING fts5(id UNINDEXED, $stringColumns, tokenize='$tokenizationMethod');
    ''');
  // Copy over records already in table
  await db.customStatement('''
      INSERT INTO fts_$tableName(rowid, id, $stringColumns)
      SELECT rowid, id, ${generateJsonExtracts(ExtractType.columnOnly, 'data', columns)} FROM $internalName;
    ''');
  // Add INSERT, UPDATE and DELETE and triggers to keep fts table in sync with table
  await db.customStatement('''
      CREATE TRIGGER IF NOT EXISTS fts_insert_trigger_$tableName AFTER INSERT ON $internalName
      BEGIN
        INSERT INTO fts_$tableName(rowid, id, $stringColumns)
        VALUES (
          NEW.rowid,
          NEW.id,
          ${generateJsonExtracts(ExtractType.columnOnly, 'NEW.data', columns)}
        );
      END;
    ''');
  await db.customStatement('''
      CREATE TRIGGER IF NOT EXISTS fts_update_trigger_$tableName AFTER UPDATE ON $internalName BEGIN
        UPDATE fts_$tableName
        SET ${generateJsonExtracts(ExtractType.columnInOperation, 'NEW.data', columns)}
        WHERE rowid = NEW.rowid;
      END;
    ''');
  await db.customStatement('''
      CREATE TRIGGER IF NOT EXISTS fts_delete_trigger_$tableName AFTER DELETE ON $internalName BEGIN
        DELETE FROM fts_$tableName WHERE rowid = OLD.rowid;
      END;
    ''');
}

typedef ExtractGenerator = String Function(String, String);

enum ExtractType {
  columnOnly,
  columnInOperation,
}

typedef ExtractGeneratorMap = Map<ExtractType, ExtractGenerator>;

String _createExtract(String jsonColumnName, String columnName) =>
    'json_extract($jsonColumnName, \'\$.$columnName\')';

ExtractGeneratorMap extractGeneratorsMap = {
  ExtractType.columnOnly: (
    String jsonColumnName,
    String columnName,
  ) =>
      _createExtract(jsonColumnName, columnName),
  ExtractType.columnInOperation: (
    String jsonColumnName,
    String columnName,
  ) =>
      '$columnName = ${_createExtract(jsonColumnName, columnName)}',
};

String generateJsonExtracts(
    ExtractType type, String jsonColumnName, List<String> columns) {
  ExtractGenerator? generator = extractGeneratorsMap[type];
  if (generator == null) {
    throw StateError('Unexpected null generator for key: $type');
  }

  if (columns.length == 1) {
    return generator(jsonColumnName, columns.first);
  }

  return columns.map((column) => generator(jsonColumnName, column)).join(', ');
}

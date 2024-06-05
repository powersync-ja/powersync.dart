import 'package:powersync/powersync.dart';
import 'package:powersync/sqlite_async.dart';

import 'helpers.dart';
import '../models/schema.dart';

final migrations = SqliteMigrations();

/// Create a Full Text Search table for the given table and columns
/// with an option to use a different tokenizer otherwise it defaults
/// to unicode61. It also creates the triggers that keep the FTS table
/// and the PowerSync table in sync.
SqliteMigration createFtsMigration(
    {required int migrationVersion,
    required String tableName,
    required List<String> columns,
    String tokenizationMethod = 'unicode61'}) {
  String internalName =
      schema.tables.firstWhere((table) => table.name == tableName).internalName;
  String stringColumns = columns.join(', ');

  return SqliteMigration(migrationVersion, (tx) async {
    // Add FTS table
    await tx.execute('''
      CREATE VIRTUAL TABLE IF NOT EXISTS fts_$tableName
      USING fts5(id UNINDEXED, $stringColumns, tokenize='$tokenizationMethod');
    ''');
    // Copy over records already in table
    await tx.execute('''
      INSERT INTO fts_$tableName(rowid, id, $stringColumns)
      SELECT rowid, id, ${generateJsonExtracts(ExtractType.columnOnly, 'data', columns)} FROM $internalName;
    ''');
    // Add INSERT, UPDATE and DELETE and triggers to keep fts table in sync with table
    await tx.execute('''
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
    await tx.execute('''
      CREATE TRIGGER IF NOT EXISTS fts_update_trigger_$tableName AFTER UPDATE ON $internalName BEGIN
        UPDATE fts_$tableName
        SET ${generateJsonExtracts(ExtractType.columnInOperation, 'NEW.data', columns)}
        WHERE rowid = NEW.rowid;
      END;
    ''');
    await tx.execute('''
      CREATE TRIGGER IF NOT EXISTS fts_delete_trigger_$tableName AFTER DELETE ON $internalName BEGIN
        DELETE FROM fts_$tableName WHERE rowid = OLD.rowid;
      END;
    ''');
  });
}

/// This is where you can add more migrations to generate FTS tables
/// that correspond to the tables in your schema and populate them
/// with the data you would like to search on
Future<void> configureFts(PowerSyncDatabase db) async {
  migrations
    ..add(createFtsMigration(
        migrationVersion: 1,
        tableName: 'lists',
        columns: ['name'],
        tokenizationMethod: 'porter unicode61'))
    ..add(createFtsMigration(
      migrationVersion: 2,
      tableName: 'todos',
      columns: ['description', 'list_id'],
    ));
  await migrations.migrate(db);
}

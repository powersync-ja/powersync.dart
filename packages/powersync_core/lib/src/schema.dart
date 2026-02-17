/// @docImport 'database/powersync_db_mixin.dart';
library;

import 'crud.dart';
import 'schema_logic.dart';

/// The schema used by the database.
///
/// The implementation uses the schema as a "VIEW" on top of JSON data.
/// No migrations are required on the client.
class Schema {
  /// List of tables in the schema.
  ///
  /// When opening a PowerSync database, these tables will be created and
  /// migrated automatically.
  final List<Table> tables;

  /// A list of [RawTable]s in addition to PowerSync-managed [tables].
  ///
  /// Raw tables give users full control over the SQLite tables, but that
  /// includes the responsibility to create those tables and to write migrations
  /// for them.
  ///
  /// For more information on raw tables, see [RawTable] and [the documentation](https://docs.powersync.com/usage/use-case-examples/raw-tables).
  final List<RawTable> rawTables;

  const Schema(this.tables, {this.rawTables = const []});

  Map<String, dynamic> toJson() => {'raw_tables': rawTables, 'tables': tables};

  void validate() {
    Set<String> tableNames = {};
    for (var table in tables) {
      table.validate();

      if (tableNames.contains(table.name)) {
        throw AssertionError("Duplicate table name: ${table.name}");
      }

      tableNames.add(table.name);
    }
  }
}

/// Options to include old values in [CrudEntry] for update statements.
///
/// These options are enabled by passing them to a non-local [Table]
/// constructor.
final class TrackPreviousValuesOptions {
  /// A filter of column names for which updates should be tracked.
  ///
  /// When set to a non-null value, columns not included in this list will not
  /// appear in [CrudEntry.previousValues]. By default, all columns are
  /// included.
  final List<String>? columnFilter;

  /// Whether to only include old values when they were changed by an update,
  /// instead of always including all old values.
  final bool onlyWhenChanged;

  const TrackPreviousValuesOptions(
      {this.columnFilter, this.onlyWhenChanged = false});
}

/// Common options that can be applied on [Table] and [RawTable] (through
/// [RawTableSchema]).
final class TableOptions {
  /// Whether to add a hidden `_metadata` column that will be enabled for
  /// updates to attach custom information about writes that will be reported
  /// through [CrudEntry.metadata].
  final bool trackMetadata;

  /// Whether to track old values of columns for [CrudEntry.previousValues].
  ///
  /// See [TrackPreviousValuesOptions] for details.
  final TrackPreviousValuesOptions? trackPreviousValues;

  /// Whether the table only exists locally.
  final bool localOnly;

  /// Whether this is an insert-only table.
  final bool insertOnly;

  /// Whether an `UPDATE` statement that doesn't change any values should be
  /// ignored when creating CRUD entries.
  final bool ignoreEmptyUpdates;

  const TableOptions({
    this.trackMetadata = false,
    this.trackPreviousValues,
    this.localOnly = false,
    this.insertOnly = false,
    this.ignoreEmptyUpdates = false,
  });

  void _validateOptions() {
    if (trackMetadata && localOnly) {
      throw AssertionError("Local-only tables can't track metadata");
    }

    if (trackPreviousValues != null && localOnly) {
      throw AssertionError("Local-only tables can't track old values");
    }
  }

  Map<String, dynamic> _optionsToJson() {
    return {
      'local_only': localOnly,
      'insert_only': insertOnly,
      'ignore_empty_update': ignoreEmptyUpdates,
      'include_metadata': trackMetadata,
      if (trackPreviousValues case final trackPreviousValues?) ...{
        'include_old': trackPreviousValues.columnFilter ?? true,
        'include_old_only_when_changed': trackPreviousValues.onlyWhenChanged,
      },
    };
  }
}

/// A single table in the schema.
@Deprecated.subclass(
    'Avoid extending table, create an instance or extension type around it instead.')
base class Table extends TableOptions {
  static const _maxNumberOfColumns = 1999;

  /// The synced table name, matching sync rules.
  final String name;

  /// List of columns.
  final List<Column> columns;

  /// List of indexes.
  final List<Index> indexes;

  /// Override the name for the view
  final String? _viewNameOverride;

  /// powersync-sqlite-core limits the number of columns
  /// per table to 1999, due to internal SQLite limits.
  ///
  /// In earlier versions this was limited to 63.
  final int maxNumberOfColumns = _maxNumberOfColumns;

  /// Internal use only.
  ///
  /// Name of the table that stores the underlying data.
  String get internalName {
    if (localOnly) {
      return "ps_data_local__$name";
    } else {
      return "ps_data__$name";
    }
  }

  /// Create a synced table.
  ///
  /// Local changes are recorded, and remote changes are synced to the local table.
  const Table(
    this.name,
    this.columns, {
    this.indexes = const [],
    String? viewName,
    super.localOnly,
    super.ignoreEmptyUpdates,
    super.trackMetadata,
    super.trackPreviousValues,
  })  : _viewNameOverride = viewName,
        super(insertOnly: false);

  /// Create a table that only exists locally.
  ///
  /// This table does not record changes, and is not synchronized from the service.
  const Table.localOnly(this.name, this.columns,
      {this.indexes = const [], String? viewName})
      : _viewNameOverride = viewName,
        super(localOnly: true);

  /// Create a table that only supports inserts.
  ///
  /// This table supports INSERT statements, operations are recorded internally
  /// and are cleared once handled in the `PowerSyncBackendConnector.uploadData`
  /// method.
  ///
  /// SELECT queries on the table will always return 0 rows.
  ///
  const Table.insertOnly(
    this.name,
    this.columns, {
    String? viewName,
    super.ignoreEmptyUpdates,
    super.trackMetadata,
    super.trackPreviousValues,
  })  : indexes = const [],
        _viewNameOverride = viewName,
        super(localOnly: false, insertOnly: true);

  Column operator [](String columnName) {
    return columns.firstWhere((element) => element.name == columnName);
  }

  bool get validName {
    return !invalidSqliteCharacters.hasMatch(name) &&
        (_viewNameOverride == null ||
            !invalidSqliteCharacters.hasMatch(_viewNameOverride));
  }

  /// Check that there are no issues in the table definition.
  void validate() {
    if (columns.length > _maxNumberOfColumns) {
      throw AssertionError(
          "Table $name has more than $_maxNumberOfColumns columns, which is not supported");
    }

    if (invalidSqliteCharacters.hasMatch(name)) {
      throw AssertionError("Invalid characters in table name: $name");
    }

    if (_viewNameOverride != null &&
        invalidSqliteCharacters.hasMatch(_viewNameOverride)) {
      throw AssertionError(
          "Invalid characters in view name: $_viewNameOverride");
    }

    _validateOptions();

    Set<String> columnNames = {"id"};
    for (var column in columns) {
      if (column.name == 'id') {
        throw AssertionError(
            "$name: id column is automatically added, custom id columns are not supported");
      } else if (columnNames.contains(column.name)) {
        throw AssertionError("Duplicate column $name.${column.name}");
      } else if (invalidSqliteCharacters.hasMatch(column.name)) {
        throw AssertionError(
            "Invalid characters in column name: $name.${column.name}");
      }

      columnNames.add(column.name);
    }
    Set<String> indexNames = {};

    for (var index in indexes) {
      if (indexNames.contains(index.name)) {
        throw AssertionError("Duplicate index $name.${index.name}");
      } else if (invalidSqliteCharacters.hasMatch(index.name)) {
        throw AssertionError(
            "Invalid characters in index name: $name.${index.name}");
      }

      for (var column in index.columns) {
        if (!columnNames.contains(column.column)) {
          throw AssertionError(
              "Column $name.${column.column} not found for index ${index.name}");
        }
      }

      indexNames.add(index.name);
    }
  }

  /// Name for the view, used for queries.
  /// Defaults to the synced table name.
  String get viewName {
    return _viewNameOverride ?? name;
  }

  Map<String, dynamic> toJson() => {
        'name': name,
        'view_name': _viewNameOverride,
        'columns': columns,
        'indexes': indexes.map((e) => e.toJson(this)).toList(growable: false),
        ..._optionsToJson(),
      };
}

class Index {
  /// Descriptive name of the index.
  final String name;

  /// List of columns used for the index.
  final List<IndexedColumn> columns;

  /// Construct a new index with the specified columns.
  const Index(this.name, this.columns);

  /// Construct a new index with the specified column names.
  factory Index.ascending(String name, List<String> columns) {
    return Index(name,
        columns.map((e) => IndexedColumn.ascending(e)).toList(growable: false));
  }

  /// Internal use only.
  ///
  /// Specifies the full name of this index on a table.
  String fullName(Table table) {
    return "${table.internalName}__$name";
  }

  Map<String, dynamic> toJson(Table table) => {
        'name': name,
        'columns': columns.map((c) => c.toJson(table)).toList(growable: false)
      };
}

/// Describes an indexed column.
class IndexedColumn {
  /// Name of the column to index.
  final String column;

  /// Whether this column is stored in ascending order in the index.
  final bool ascending;

  const IndexedColumn(this.column, {this.ascending = true});
  const IndexedColumn.ascending(this.column) : ascending = true;
  const IndexedColumn.descending(this.column) : ascending = false;

  Map<String, dynamic> toJson(Table table) {
    final t = table[column].type;

    return {'name': column, 'ascending': ascending, 'type': t.sqlite};
  }
}

/// A single column in a table schema.
class Column {
  /// Name of the column.
  final String name;

  /// Type of the column.
  ///
  /// If the underlying data does not match this type,
  /// it is cast automatically.
  ///
  /// For details on the cast, see:
  /// https://www.sqlite.org/lang_expr.html#castexpr
  final ColumnType type;

  const Column(this.name, this.type);

  /// Create a TEXT column.
  const Column.text(this.name) : type = ColumnType.text;

  /// Create an INTEGER column.
  const Column.integer(this.name) : type = ColumnType.integer;

  /// Create a REAL column.
  const Column.real(this.name) : type = ColumnType.real;

  Map<String, dynamic> toJson() => {'name': name, 'type': type.sqlite};
}

/// A raw table, defined by the user instead of being managed by PowerSync.
///
/// Any ordinary SQLite table can be defined as a raw table, which enables:
///
/// - More performant queries, since data is stored in typed rows instead of the
///   schemaless JSON view PowerSync uses by default.
/// - More control over the table, since custom column constraints can be used
///   in its definition.
///
/// PowerSync doesn't know anything about the internal structure of raw tables -
/// instead, it relies on user-defined [put] and [delete] statements to sync
/// data into them.
///
/// When using raw tables, you are responsible for creating and migrating them
/// when they've changed. Further, triggers are necessary to collect local
/// writes to those tables. For more information, see
/// [the documentation](https://docs.powersync.com/usage/use-case-examples/raw-tables).
///
/// Note that raw tables are only supported by the Rust sync client, which needs
/// to be enabled when connecting with raw tables.
final class RawTable {
  /// The name of the table as used by the sync service.
  ///
  /// This doesn't necessarily have to match the name of the SQLite table that
  /// [put] and [delete] write to. Instead, it's used by the sync client to
  /// identify which statements to use when it encounters sync operations for
  /// this table.
  final String name;

  /// A statement responsible for inserting or updating a row in this raw table
  /// based on data from the sync service.
  ///
  /// See [PendingStatement] for details.
  final PendingStatement? put;

  /// A statement responsible for deleting a row based on its PowerSync id.
  ///
  /// See [PendingStatement] for details. Note that [PendingStatementValue]s
  /// used here must all be [PendingStatementValue.id].
  final PendingStatement? delete;

  /// For [RawTable.inferred] tables, the schema from which [put] and [delete]
  /// statemenst are inferred.
  final RawTableSchema? schema;

  /// An optional statement to run when [PowerSyncDatabaseMixin.disconnectAndClear]
  /// is called.
  final String? clear;

  /// Creates a raw table with explicit [put] and [delete] statements.
  ///
  /// These can also be [RawTable.inferred] when providing a [RawTableSchema].
  const RawTable({
    required this.name,
    required PendingStatement this.put,
    required PendingStatement this.delete,
    this.clear,
  }) : schema = null;

  /// Creates a raw table where [put] and [delete] statements are optional
  /// because the sync client can infer defaults from the [schema] of the table
  /// in the local database.
  const RawTable.inferred({
    required this.name,
    required RawTableSchema this.schema,
    this.put,
    this.delete,
    this.clear,
  });

  Map<String, dynamic> toJson() => {
        'name': name,
        'put': put,
        'delete': delete,
        'clear': clear,
        ...?schema?._toJson(),
      };
}

/// The schema of a [RawTable] in the local database.
///
/// This information is optional when declaring raw tables with [RawTable.new].
/// However, providing it allows the sync client to infer [RawTable.put] and
/// [RawTable.delete] statements automatically.
final class RawTableSchema {
  /// The actual name of the raw table in the local schema.
  ///
  /// Unlike [RawTable.name], which describes the name of _synced_ tables to
  /// match, this reflects the local SQLite table name. This is used to infer
  /// [RawTable.put] and [RawTable.delete] statements for the sync client. It
  /// can also be used to auto-generate triggers forwarding writes on raw tables
  /// into the CRUD upload queue (using the `powersync_create_raw_table_crud_trigger`
  /// SQL function).
  final String tableName;

  /// An optional filter of columns that should be synced.
  ///
  /// By default, all columns in raw tables are considered for sync. If a filter
  /// is specified, PowerSync treats unmatched columns as local-only and will
  /// not attempt to sync them.
  final List<String>? syncedColumns;

  /// Common options affecting how the `powersync_create_raw_table_crud_trigger`
  /// SQL function generates triggers.
  final TableOptions options;

  const RawTableSchema({
    required this.tableName,
    this.syncedColumns,
    this.options = const TableOptions(),
  });

  Map<String, dynamic> _toJson() => {
        'table_name': tableName,
        if (syncedColumns != null) 'synced_columns': syncedColumns,
        ...options._optionsToJson(),
      };
}

/// An SQL statement to be run by the sync client against raw tables.
///
/// Since raw tables are managed by the user, PowerSync can't know how to apply
/// serverside changes to them. These statements bridge raw tables and PowerSync
/// by providing upserts and delete statements.
///
/// For more information, see [the documentation](https://docs.powersync.com/usage/use-case-examples/raw-tables)
final class PendingStatement {
  /// The SQL statement to run to upsert or delete data from a raw table.
  final String sql;

  /// A list of value identifiers for parameters in [sql].
  ///
  /// Put statements can use both [PendingStatementValue.id] and
  /// [PendingStatementValue.column], whereas delete statements can only use
  /// [PendingStatementValue.id].
  final List<PendingStatementValue> params;

  const PendingStatement({required this.sql, required this.params});

  Map<String, dynamic> toJson() => {
        'sql': sql,
        'params': params,
      };
}

/// A description of a value that will be resolved in the sync client when
/// running a [PendingStatement] for a [RawTable].
sealed class PendingStatementValue {
  /// A value that is bound to the textual id used in the PowerSync protocol.
  const factory PendingStatementValue.id() = _PendingStmtValueId;

  /// A value that is bound to a JSON object containing all columns from the
  /// synced row that haven't been matched by a [PendingStatementValue.column]
  /// value in the same statement.
  const factory PendingStatementValue.rest() = _PendingStmtValueRest;

  /// A value that is bound to the value of a column in a replace (`PUT`)
  /// operation of the PowerSync protocol.
  factory PendingStatementValue.column(String column) = _PendingStmtValueColumn;

  dynamic toJson();
}

class _PendingStmtValueColumn implements PendingStatementValue {
  final String column;
  const _PendingStmtValueColumn(this.column);

  @override
  dynamic toJson() {
    return {
      'Column': column,
    };
  }
}

class _PendingStmtValueId implements PendingStatementValue {
  const _PendingStmtValueId();

  @override
  dynamic toJson() {
    return 'Id';
  }
}

class _PendingStmtValueRest implements PendingStatementValue {
  const _PendingStmtValueRest();

  @override
  dynamic toJson() {
    return 'Rest';
  }
}

/// Type of column.
enum ColumnType {
  /// TEXT column.
  text('TEXT'),

  /// INTEGER column.
  integer('INTEGER'),

  /// REAL column.
  real('REAL');

  final String sqlite;

  const ColumnType(this.sqlite);

  @override
  toString() {
    return sqlite;
  }
}

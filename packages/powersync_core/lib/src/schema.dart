import 'crud.dart';
import 'schema_logic.dart';

/// The schema used by the database.
///
/// The implementation uses the schema as a "VIEW" on top of JSON data.
/// No migrations are required on the client.
class Schema {
  /// List of tables in the schema.
  final List<Table> tables;
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

/// A single table in the schema.
class Table {
  static const _maxNumberOfColumns = 1999;

  /// The synced table name, matching sync rules.
  final String name;

  /// List of columns.
  final List<Column> columns;

  /// List of indexes.
  final List<Index> indexes;

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
    this.localOnly = false,
    this.ignoreEmptyUpdates = false,
    this.trackMetadata = false,
    this.trackPreviousValues,
  })  : insertOnly = false,
        _viewNameOverride = viewName;

  /// Create a table that only exists locally.
  ///
  /// This table does not record changes, and is not synchronized from the service.
  const Table.localOnly(this.name, this.columns,
      {this.indexes = const [], String? viewName})
      : localOnly = true,
        insertOnly = false,
        trackMetadata = false,
        trackPreviousValues = null,
        ignoreEmptyUpdates = false,
        _viewNameOverride = viewName;

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
    this.ignoreEmptyUpdates = false,
    this.trackMetadata = false,
    this.trackPreviousValues,
  })  : localOnly = false,
        insertOnly = true,
        indexes = const [],
        _viewNameOverride = viewName;

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

    if (trackMetadata && localOnly) {
      throw AssertionError("Local-only tables can't track metadata");
    }

    if (trackPreviousValues != null && localOnly) {
      throw AssertionError("Local-only tables can't track old values");
    }

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
        'local_only': localOnly,
        'insert_only': insertOnly,
        'columns': columns,
        'indexes': indexes.map((e) => e.toJson(this)).toList(growable: false),
        'ignore_empty_update': ignoreEmptyUpdates,
        'include_metadata': trackMetadata,
        if (trackPreviousValues case final trackPreviousValues?) ...{
          'include_old': trackPreviousValues.columnFilter ?? true,
          'include_old_only_when_changed': trackPreviousValues.onlyWhenChanged,
        },
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

class RawTable {
  final String
      name; // TODO: it does not need to be the same name as the raw table
  final PendingStatement put;
  final PendingStatement delete;

  const RawTable({
    required this.name,
    required this.put,
    required this.delete,
  });

  Map<String, dynamic> toJson() => {
        'name': name,
        'put': put,
        'delete': delete,
      };
}

class PendingStatement {
  final String sql;
  final List<PendingStatementValue> params;

  PendingStatement({required this.sql, required this.params});

  Map<String, dynamic> toJson() => {
        'sql': sql,
        'params': params,
      };
}

sealed class PendingStatementValue {
  dynamic toJson();
}

class PendingStmtValueColumn extends PendingStatementValue {
  final String column;
  PendingStmtValueColumn(this.column);

  @override
  dynamic toJson() {
    return {
      'Column': column,
    };
  }
}

class PendingStmtValueId extends PendingStatementValue {
  @override
  dynamic toJson() {
    return 'Id';
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

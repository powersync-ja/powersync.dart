import 'schema_logic.dart';

/// The schema used by the database.
///
/// The implementation uses the schema as a "VIEW" on top of JSON data.
/// No migrations are required on the client.
class Schema {
  /// List of tables in the schema.
  final List<Table> tables;

  const Schema(this.tables);

  Map<String, dynamic> toJson() => {'tables': tables};
}

/// A single table in the schema.
class Table {
  /// The table name, as used in queries.
  final String name;

  /// List of columns.
  final List<Column> columns;

  /// List of indexes.
  final List<Index> indexes;

  /// Whether the table only exists only.
  final bool localOnly;

  /// Whether this is an insert-only table.
  final bool insertOnly;

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
  const Table(this.name, this.columns, {this.indexes = const []})
      : localOnly = false,
        insertOnly = false;

  /// Create a table that only exists locally.
  ///
  /// This table does not record changes, and is not synchronized from the service.
  const Table.localOnly(this.name, this.columns, {this.indexes = const []})
      : localOnly = true,
        insertOnly = false;

  /// Create a table that only supports inserts.
  ///
  /// This table records INSERT statements, but does not persist data locally.
  ///
  /// SELECT queries on the table will always return 0 rows.
  const Table.insertOnly(this.name, this.columns)
      : localOnly = false,
        insertOnly = true,
        indexes = const [];

  Column operator [](String columnName) {
    return columns.firstWhere((element) => element.name == columnName);
  }

  bool get validName {
    return !invalidSqliteCharacters.hasMatch(name);
  }

  Map<String, dynamic> toJson() => {
        'name': name,
        'local_only': localOnly,
        'insert_only': insertOnly,
        'columns': columns,
        'indexes': indexes.map((e) => e.toJson(this)).toList(growable: false)
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

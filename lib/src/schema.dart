import 'package:powersync/src/schema_logic.dart';

/// The schema used by the database.
///
/// The implementation uses the schema as a "VIEW" on top of JSON data.
/// No migrations are required on the client.
class Schema {
  /// List of tables in the schema.
  final List<Table> tables;

  const Schema(this.tables);
}

/// A single table in the schema.
class Table {
  /// The table name, as used in queries.
  final String name;

  /// List of columns.
  final List<Column> columns;

  final List<Index> indexes;

  final bool localOnly;
  final bool insertOnly;

  String get internalName {
    if (localOnly) {
      return "ps_data_local__$name";
    } else {
      return "ps_data__$name";
    }
  }

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
  /// This table records INSERTS, but does not persist data locally.
  const Table.insertOnly(this.name, this.columns)
      : localOnly = false,
        insertOnly = true,
        indexes = const [];

  Column operator [](String columnName) {
    return columns.firstWhere((element) => element.name == columnName);
  }
}

class Index {
  final String name;
  final List<IndexedColumn> columns;

  const Index(this.name, this.columns);

  factory Index.ascending(String name, List<String> columns) {
    return Index(name,
        columns.map((e) => IndexedColumn.ascending(e)).toList(growable: false));
  }

  String fullName(Table table) {
    return "${table.internalName}__$name";
  }

  String toSqlDefinition(Table table) {
    var fields = columns.map((column) => column.toSql(table)).join(', ');
    return 'CREATE INDEX "${fullName(table)}" ON "${table.internalName}"($fields)';
  }
}

class IndexedColumn {
  final String column;
  final bool ascending;

  const IndexedColumn(this.column, {this.ascending = true});
  const IndexedColumn.ascending(this.column) : ascending = true;
  const IndexedColumn.descending(this.column) : ascending = false;

  String toSql(Table table) {
    final fullColumn = table[column]; // errors if not found

    if (ascending) {
      return mapColumn(fullColumn);
    } else {
      return "${mapColumn(fullColumn)} DESC";
    }
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

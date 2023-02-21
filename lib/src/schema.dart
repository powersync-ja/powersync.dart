class Schema {
  final List<Table> tables;

  const Schema(this.tables);
}

class Table {
  final String name;
  final List<Column> columns;

  const Table(this.name, this.columns);
}

class Column {
  final String name;
  final ColumnType type;

  const Column(this.name, this.type);

  const Column.text(this.name) : type = ColumnType.text;
  const Column.integer(this.name) : type = ColumnType.integer;
  const Column.real(this.name) : type = ColumnType.real;
}

enum ColumnType {
  text('TEXT'),
  integer('INTEGER'),
  real('REAL');

  final String sqlite;

  const ColumnType(this.sqlite);

  @override
  toString() {
    return sqlite;
  }
}

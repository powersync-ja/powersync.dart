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
  final String type;

  const Column(this.name, this.type);
}

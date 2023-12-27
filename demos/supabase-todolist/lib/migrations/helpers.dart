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

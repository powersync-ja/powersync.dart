const String maxOpId = '9223372036854775807';

final invalidSqliteCharacters = RegExp(r'''["'%,\.#\s\[\]]''');

String? friendlyTableName(String table) {
  final re = RegExp(r"^ps_data__(.+)$");
  final re2 = RegExp(r"^ps_data_local__(.+)$");
  final match = re.firstMatch(table) ?? re2.firstMatch(table);
  return match?.group(1);
}

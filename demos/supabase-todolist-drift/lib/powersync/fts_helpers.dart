import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'powersync.dart';

part 'fts_helpers.g.dart';

String _createSearchTermWithOptions(String searchTerm) {
  // adding * to the end of the search term will match any word that starts with the search term
  // e.g. searching bl will match blue, black, etc.
  // consult FTS5 Full-text Query Syntax documentation for more options
  String searchTermWithOptions = '$searchTerm*';
  return searchTermWithOptions;
}

/// Search the FTS table for the given searchTerm
@riverpod
Future<List> search(Ref ref, String searchTerm, String tableName) async {
  String searchTermWithOptions = _createSearchTermWithOptions(searchTerm);
  final db = await ref.read(powerSyncInstanceProvider.future);
  return await db.getAll(
      'SELECT * FROM fts_$tableName WHERE fts_$tableName MATCH ? ORDER BY rank',
      [searchTermWithOptions]);
}

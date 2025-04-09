import 'package:drift/drift.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../powersync/database.dart';
import '../supabase.dart';

part 'lists.g.dart';

@riverpod
final class ListsNotifier extends _$ListsNotifier {
  @override
  Stream<List<ListItemWithStats>> build() {
    final database = ref.watch(driftDatabase);
    return database.listsWithStats().watch();
  }

  Future<void> createNewList(String name) async {
    final database = ref.read(driftDatabase);
    await database.listItems.insertOne(ListItemsCompanion.insert(
      name: name,
      ownerId: Value(ref.read(userIdProvider)),
    ));
  }

  Future<void> deleteList(String id) async {
    // We only need to delete the list here, the foreign key constraint on the
    // server will delete related todos (which will delete them locally after
    // the next sync).
    final database = ref.read(driftDatabase);
    final stmt = database.listItems.delete()..where((row) => row.id.equals(id));
    await stmt.go();
  }
}

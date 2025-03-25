import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:supabase_todolist_drift/database.dart';
import 'package:supabase_todolist_drift/fts_helpers.dart' as fts_helpers;
import 'package:supabase_todolist_drift/powersync.dart';

import 'todo_list_page.dart';

part 'fts_search_delegate.g.dart';

final log = Logger('powersync-supabase');

class FtsSearchDelegate extends SearchDelegate {
  @override
  List<Widget>? buildActions(BuildContext context) {
    return [
      IconButton(
        onPressed: () {
          query = '';
        },
        icon: const Icon(Icons.clear),
      ),
    ];
  }

  @override
  Widget? buildLeading(BuildContext context) {
    return IconButton(
      onPressed: () {
        close(context, null);
      },
      icon: const Icon(Icons.arrow_back),
    );
  }

  @override
  Widget buildResults(BuildContext context) {
    return Consumer(builder: (context, ref, _) {
      final results = ref.watch(_searchProvider(query));

      return results.maybeWhen(
        data: (rows) {
          return ListView.builder(
            itemBuilder: (context, index) {
              return ListTile(
                title: Text(rows[index]['name']),
                onTap: () {
                  close(context, null);
                },
              );
            },
            itemCount: rows.length,
          );
        },
        orElse: () => const Center(
          child: CircularProgressIndicator(),
        ),
      );
    });
  }

  @override
  Widget buildSuggestions(BuildContext context) {
    NavigatorState navigator = Navigator.of(context);

    return Consumer(
      builder: (context, ref, _) {
        final results = ref.watch(_searchProvider(query));
        final appDb = ref.watch(driftDatabase);

        return results.maybeWhen(
          data: (rows) {
            return ListView.builder(
              itemBuilder: (context, index) {
                return ListTile(
                  title: Text(rows[index]['name'] ?? ''),
                  onTap: () async {
                    ListItem list = await appDb.findList(rows[index]['id']);
                    navigator.push(MaterialPageRoute(
                      builder: (context) => TodoListPage(list: list),
                    ));
                  },
                );
              },
              itemCount: rows.length,
            );
          },
          orElse: () => const Center(
            child: CircularProgressIndicator(),
          ),
        );
      },
    );
  }
}

@riverpod
Future<List> _search(Ref ref, String query) async {
  if (query.isEmpty) return [];
  final listsSearchResults =
      await ref.watch(fts_helpers.searchProvider(query, 'lists').future);
  final todoItemsSearchResults =
      await ref.watch(fts_helpers.searchProvider(query, 'todos').future);

  List formattedListResults = listsSearchResults
      .map((result) => {"id": result['id'], "name": result['name']})
      .toList();
  List formattedTodoItemsResults = todoItemsSearchResults
      .map((result) => {
            // Use list_id so the navigation goes to the list page
            "id": result['list_id'],
            "name": result['description'],
          })
      .toList();
  List formattedResults = [
    ...formattedListResults,
    ...formattedTodoItemsResults
  ];
  return formattedResults;
}

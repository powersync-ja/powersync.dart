import 'dart:async';

import 'package:flutter/material.dart';
import 'package:powersync/sqlite3.dart' as sqlite;

import './resultset_table.dart';
import '../powersync.dart';

class QueryWidget extends StatefulWidget {
  final String defaultQuery;

  const QueryWidget({super.key, required this.defaultQuery});

  @override
  State<StatefulWidget> createState() {
    return QueryWidgetState();
  }
}

class QueryWidgetState extends State<QueryWidget> {
  sqlite.ResultSet? _data;
  late TextEditingController _controller;
  late String _query;
  String? _error;
  StreamSubscription? _subscription;

  QueryWidgetState();

  @override
  void initState() {
    super.initState();
    _error = null;
    _controller = TextEditingController(text: widget.defaultQuery);
    _query = _controller.text;
    _refresh();
  }

  @override
  void dispose() {
    super.dispose();
    _controller.dispose();
    _subscription?.cancel();
  }

  _refresh() async {
    _subscription?.cancel();
    final stream = db.watch(_query);
    _subscription = stream.listen((data) {
      if (!mounted) {
        return;
      }
      setState(() {
        _data = data;
        _error = null;
      });
    }, onError: (e) {
      setState(() {
        if (e is sqlite.SqliteException) {
          _error = "${e.message}!";
        } else {
          _error = e.toString();
        }
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: TextField(
            controller: _controller,
            onEditingComplete: () {
              setState(() {
                _query = _controller.text;
                _refresh();
              });
            },
            decoration: InputDecoration(
                isDense: false,
                border: const OutlineInputBorder(),
                labelText: 'Query',
                errorText: _error),
          ),
        ),
        Expanded(
            child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SingleChildScrollView(
            scrollDirection: Axis.vertical,
            child: ResultSetTable(data: _data),
          ),
        ))
      ],
    );
  }
}

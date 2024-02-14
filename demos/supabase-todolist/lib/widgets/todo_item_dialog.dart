import 'package:flutter/material.dart';
import 'package:powersync_flutter_demo/database.dart';
import 'package:powersync_flutter_demo/powersync.dart';

class TodoItemDialog extends StatefulWidget {
  final ListItem list;

  const TodoItemDialog({super.key, required this.list});

  @override
  State<StatefulWidget> createState() {
    return _TodoItemDialogState();
  }
}

class _TodoItemDialogState extends State<TodoItemDialog> {
  final TextEditingController _textFieldController = TextEditingController();

  _TodoItemDialogState();

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    super.dispose();
    _textFieldController.dispose();
  }

  Future<void> add() async {
    Navigator.of(context).pop();

    await appDb.addTodo(widget.list, _textFieldController.text);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add a new todo item'),
      content: TextField(
        controller: _textFieldController,
        decoration: const InputDecoration(hintText: 'Type your new todo'),
        onSubmitted: (value) {
          add();
        },
        autofocus: true,
      ),
      actions: <Widget>[
        OutlinedButton(
          child: const Text('Cancel'),
          onPressed: () {
            _textFieldController.clear();
            Navigator.of(context).pop();
          },
        ),
        ElevatedButton(
          onPressed: add,
          child: const Text('Add'),
        ),
      ],
    );
  }
}

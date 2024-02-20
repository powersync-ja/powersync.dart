import 'package:flutter/material.dart';
import 'package:powersync_flutter_demo/powersync.dart';

class ListItemDialog extends StatefulWidget {
  const ListItemDialog({super.key});

  @override
  State<StatefulWidget> createState() {
    return _ListItemDialogState();
  }
}

class _ListItemDialogState extends State<ListItemDialog> {
  final TextEditingController _textFieldController = TextEditingController();

  _ListItemDialogState();

  @override
  void dispose() {
    super.dispose();
    _textFieldController.dispose();
  }

  Future<void> add() async {
    await appDb.createList(_textFieldController.text);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add a new list'),
      content: TextField(
        controller: _textFieldController,
        decoration: const InputDecoration(hintText: 'List name'),
        onSubmitted: (value) async {
          Navigator.of(context).pop();
          await add();
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
          child: const Text('Create'),
          onPressed: () async {
            Navigator.of(context).pop();
            await add();
          },
        ),
      ],
    );
  }
}

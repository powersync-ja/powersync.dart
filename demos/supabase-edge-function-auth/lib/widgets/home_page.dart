import 'package:flutter/material.dart';

import '../main.dart';

class ListsPage extends StatelessWidget {
  const ListsPage({super.key});

  @override
  Widget build(BuildContext context) {
    const content = Text('Hello World');

    const page = MyHomePage(
      title: 'JWT Auth Demo',
      content: content,
    );
    return page;
  }
}

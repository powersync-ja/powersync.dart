import 'package:material_ui/material_ui.dart';

import '../main.dart';

class HomePage extends StatelessWidget {
  const HomePage({super.key});

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

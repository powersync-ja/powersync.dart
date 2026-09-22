import 'package:devtools_extensions/devtools_extensions.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:web/web.dart' as web;

import 'src/integration/library.dart';

void main() {
  runApp(const ProviderScope(child: PowerSyncDevToolsExtension()));
}

final class const PowerSyncDevToolsExtension({super.key})
    extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return DevToolsExtension(child: _ExtensionFrame());
  }
}

final class const _ExtensionFrame() extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final app = ref.watch(vueApp);
    switch (app) {
      case AsyncData<VueApp>(:final value):
        return _RenderedVueApp(app: value);
      case AsyncError(:final error, :final stackTrace):
        return Text('Internal error:$error\n$stackTrace');
      case AsyncLoading():
        return const SizedBox.shrink();
    }
  }
}

final class _RenderedVueApp({required final VueApp app})
    extends StatefulWidget {
  @override
  State<_RenderedVueApp> createState() => _RenderedVueAppState();
}

class _RenderedVueAppState extends State<_RenderedVueApp> {
  VueApp? _mountedApp;

  void _unmountApp() {
    _mountedApp?.unmount();
    _mountedApp = null;
  }

  @override
  void dispose() {
    super.dispose();
    _unmountApp();
  }

  @override
  Widget build(BuildContext context) {
    return HtmlElementView.fromTagName(
      tagName: 'div',
      onElementCreated: (element) {
        _mountedApp = widget.app..mount(element as web.HTMLDivElement);
      },
    );
  }
}

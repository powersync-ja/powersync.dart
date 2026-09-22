import 'dart:js_interop';

import 'package:riverpod/riverpod.dart';

import 'integration.dart';

/// The loaded ESM module of `js/index.ts`.
extension type LoadedDiagnosticsLibrary(JSObject _) implements JSObject {
  external VueApp appFactory(JSObject integration);
}

extension type VueApp(JSObject _) implements JSObject {
  external void mount(JSAny rootContainer);
  external void unmount();
}

final _integration = Provider(DartSdkIntegration.new);

final vueApp = FutureProvider((ref) async {
  final import = importModule('./js-dist/index.js'.toJS);
  final integration = ref.read(_integration);

  final lib = (await import.toDart) as LoadedDiagnosticsLibrary;
  final app = lib.appFactory(createJSInteropWrapper(integration));
  return app;
});

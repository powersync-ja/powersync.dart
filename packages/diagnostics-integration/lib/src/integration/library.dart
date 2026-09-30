import 'dart:js_interop';

import 'package:riverpod/riverpod.dart';

import '../state/ui.dart';
import 'integration.dart';

/// The loaded ESM module of `js/index.ts`.
extension type LoadedDiagnosticsLibrary(JSObject _) implements JSObject {
  external VueApp appFactory(JSObject integration, VueRef theme);

  external VueRef<T> ref<T extends JSAny>(T value);
}

extension type VueRef<T extends JSAny>(JSObject _) implements JSObject {
  external T value;
}

extension type VueApp(JSObject _) implements JSObject {
  external void mount(JSAny rootContainer);
  external void unmount();
}

final _integration = Provider(DartSdkIntegration.new);

final _diagnosticsTheme = Provider(
  (ref) => (ref.watch(darkModeEnabled).value ? 'dark' : 'light').toJS,
);

final vueApp = FutureProvider((ref) async {
  final import = importModule('./js-dist/index.js'.toJS);
  final integration = ref.read(_integration);

  final lib = (await import.toDart) as LoadedDiagnosticsLibrary;

  final themeRef = lib.ref(ref.read(_diagnosticsTheme));
  ref.listen(_diagnosticsTheme, (_, theme) => themeRef.value = theme);
  final app = lib.appFactory(createJSInteropWrapper(integration), themeRef);
  return app;
});

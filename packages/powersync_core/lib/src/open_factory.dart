// This follows the pattern from here: https://stackoverflow.com/questions/58710226/how-to-import-platform-specific-dependency-in-flutter-dart-combine-web-with-an
// To conditionally export an implementation for either web or "native" platforms
// The sqlite library uses dart:ffi which is not supported on web

export 'open_factory/open_factory_stub.dart'
    // ignore: uri_does_not_exist
    if (dart.library.io) 'open_factory/native/native_open_factory.dart'
    // ignore: uri_does_not_exist
    if (dart.library.html) 'open_factory/web/web_open_factory.dart';

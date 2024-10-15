// This follows the pattern from here: https://stackoverflow.com/questions/58710226/how-to-import-platform-specific-dependency-in-flutter-dart-combine-web-with-an
// To conditionally export an implementation for either web or "native" platforms
// The sqlite library uses dart:ffi which is not supported on web

export 'powersync_database_impl_stub.dart'
    // ignore: uri_does_not_exist
    if (dart.library.io) './native/native_powersync_database.dart'
    // ignore: uri_does_not_exist
    if (dart.library.html) './web/web_powersync_database.dart';

export './user_agent_stub.dart'
    // ignore: uri_does_not_exist
    if (dart.library.io) './user_agent_native.dart'
    // ignore: uri_does_not_exist
    if (dart.library.js_interop) './user_agent_web.dart';

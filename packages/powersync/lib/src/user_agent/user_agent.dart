export './user_agent_stub.dart'
    // ignore: uri_does_not_exist
    if (dart.library.io) './user_agent_native.dart'
    // ignore: uri_does_not_exist
    if (dart.library.html) './user_agent_web.dart';

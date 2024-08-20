// For native, expose a user agent.
// For web, we're not able to override the user agent anyway.

export './user_agent_stub.dart'
    // ignore: uri_does_not_exist
    if (dart.library.io) './user_agent_native.dart';

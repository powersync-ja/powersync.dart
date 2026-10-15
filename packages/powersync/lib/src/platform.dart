/// @docImport 'package:powersync/native.dart';
library;

import 'package:sqlite_async/sqlite_async.dart';

import 'platform_specific/platform_specific.dart' as defaults;

/// Abstraction over platform-specific functionality needed by the PowerSync
/// SDK.
///
/// The SDK provides a default implementation of this based on conditional
/// imports, but this class can be extended to customize e.g. the locking scheme
/// used by PowerSync clients.
base class PowerSyncPlatform {
  const PowerSyncPlatform();

  /// Creates a named, async mutex.
  ///
  /// The default implementation uses [web locks] on the web to avoid races
  /// between tabs. On native platforms, this uses a simple mutex implementation
  /// based on future chaining that doesn't take multiple isolates or processes
  /// into consideration. Apps opening multiple instances of the same PowerSync
  /// database in the same or different processes should override this method to
  /// return [FileMutex] instead.
  ///
  /// [web locks]: https://developer.mozilla.org/en-US/docs/Web/API/Web_Locks_API
  Mutex namedMutex(String identifier) {
    return defaults.potentiallySharedMutex(identifier);
  }
}

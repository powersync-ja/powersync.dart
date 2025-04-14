import 'package:meta/meta.dart';
import 'package:sqlite_async/sqlite_async.dart';

/// A collection of PowerSync database instances that are using the same
/// underlying SQLite database.
///
/// We expect that each group will only ever have one database because we
/// encourage users to manage their databases as singletons. So, we print a
/// warning when two databases are part of the same group.
///
/// This can only detect two database instances being opened on the same
/// isolate, we can't provide these checks acros isolates. Since most users
/// aren't opening databases on background isolates though, this still guards
/// against most misuses.
@internal
final class ActiveDatabaseGroup {
  int refCount = 0;

  /// Use to prevent multiple connections from being opened concurrently
  final Mutex syncConnectMutex = Mutex();
  final String identifier;

  ActiveDatabaseGroup._(this.identifier);

  void close() {
    if (--refCount == 0) {
      final removedGroup = _activeGroups.remove(identifier);
      assert(removedGroup == this);
    }
  }

  static final Map<String, ActiveDatabaseGroup> _activeGroups = {};

  static ActiveDatabaseGroup referenceDatabase(String identifier) {
    final group = _activeGroups.putIfAbsent(
        identifier, () => ActiveDatabaseGroup._(identifier));
    group.refCount++;
    return group;
  }
}

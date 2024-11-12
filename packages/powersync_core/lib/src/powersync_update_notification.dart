import 'package:sqlite_async/sqlite_async.dart';
import 'schema_logic.dart';

class PowerSyncUpdateNotification extends UpdateNotification {
  PowerSyncUpdateNotification(super.tables);

  factory PowerSyncUpdateNotification.fromRawTables(
      Iterable<String> originalTables) {
    return PowerSyncUpdateNotification(_friendlyTableNames(originalTables));
  }

  factory PowerSyncUpdateNotification.fromUpdateNotification(
      UpdateNotification updateNotification) {
    return PowerSyncUpdateNotification.fromRawTables(updateNotification.tables);
  }

  factory PowerSyncUpdateNotification.empty() {
    return PowerSyncUpdateNotification(const {});
  }

  bool get isEmpty {
    return tables.isEmpty;
  }

  bool get isNotEmpty {
    return tables.isNotEmpty;
  }

  @override
  PowerSyncUpdateNotification union(UpdateNotification other) {
    if (other is PowerSyncUpdateNotification) {
      return PowerSyncUpdateNotification(tables.union(other.tables));
    } else {
      return PowerSyncUpdateNotification(tables.union(
          PowerSyncUpdateNotification.fromUpdateNotification(other).tables));
    }
  }

  @override
  bool containsAny(Set<String> tableFilter) {
    return super.containsAny(_friendlyTableNames(tableFilter));
  }
}

Set<String> _friendlyTableNames(Iterable<String> originalTables) {
  Set<String> tables = {};
  for (var table in originalTables) {
    var friendlyName = friendlyTableName(table);
    if (friendlyName != null) {
      tables.add(friendlyName);
    } else if (!table.startsWith('ps_')) {
      tables.add(table);
    }
  }
  return tables;
}

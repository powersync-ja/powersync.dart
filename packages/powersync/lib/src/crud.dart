import 'dart:convert';

import 'package:collection/collection.dart';
import 'package:powersync/sqlite3_common.dart' as sqlite;

/// A batch of client-side changes.
class CrudBatch {
  /// List of client-side changes.
  List<CrudEntry> crud;

  /// true if there are more changes in the local queue
  bool haveMore;

  /// Call to remove the changes from the local queue, once successfully uploaded.
  ///
  /// [writeCheckpoint] is optional.
  Future<void> Function({String? writeCheckpoint}) complete;

  CrudBatch(
      {required this.crud, required this.haveMore, required this.complete});
}

class CrudTransaction {
  /// Unique transaction id.
  ///
  /// If null, this contains a list of changes recorded without an explicit transaction associated.
  final int? transactionId;

  /// List of client-side changes.
  final List<CrudEntry> crud;

  /// Call to remove the changes from the local queue, once successfully uploaded.
  final Future<void> Function({String? writeCheckpoint}) complete;

  CrudTransaction(
      {required this.crud,
      required this.complete,
      required this.transactionId});

  @override
  String toString() {
    return "CrudTransaction<$transactionId, $crud>";
  }
}

/// A single client-side change.
class CrudEntry {
  /// Auto-incrementing client-side id.
  ///
  /// Reset whenever the database is re-created.
  final int clientId;

  /// Auto-incrementing transaction id. This is the same for all operations
  /// within the same transaction.
  ///
  /// Reset whenever the database is re-created.
  ///
  /// Currently, this is only present when [PowerSyncDatabase.writeTransaction] is used.
  /// This may change in the future.
  final int? transactionId;

  /// Type of change.
  final UpdateType op;

  /// Table that contained the change.
  final String table;

  /// ID of the changed row.
  final String id;

  /// Data associated with the change.
  ///
  /// For PUT, this is contains all non-null columns of the row.
  ///
  /// For PATCH, this is contains the columns that changed.
  ///
  /// For DELETE, this is null.
  final Map<String, dynamic>? opData;

  CrudEntry(this.clientId, this.op, this.table, this.id, this.transactionId,
      this.opData);

  factory CrudEntry.fromRow(sqlite.Row row) {
    final data = jsonDecode(row['data']);
    return CrudEntry(row['id'], UpdateType.fromJsonChecked(data['op'])!,
        data['type'], data['id'], row['tx_id'], data['data']);
  }

  /// Converts the change to JSON format, as required by the dev crud API.
  Map<String, dynamic> toJson() {
    return {
      'op_id': clientId,
      'op': op.toJson(),
      'type': table,
      'id': id,
      'tx_id': transactionId,
      'data': opData
    };
  }

  @override
  String toString() {
    return "CrudEntry<$transactionId/$clientId ${op.toJson()} $table/$id $opData>";
  }

  @override
  bool operator ==(Object other) {
    return (other is CrudEntry &&
        other.transactionId == transactionId &&
        other.clientId == clientId &&
        other.op == op &&
        other.table == table &&
        other.id == id &&
        const MapEquality().equals(other.opData, opData));
  }

  @override
  int get hashCode {
    return Object.hash(transactionId, clientId, op.toJson(), table, id,
        const MapEquality().hash(opData));
  }
}

/// Type of local change.
enum UpdateType {
  /// Insert or replace a row. All non-null columns are included in the data.
  put('PUT'),
  // Update a row if it exists. All updated columns are included in the data.
  patch('PATCH'),
  // Delete a row if it exists.
  delete('DELETE');

  final String json;

  const UpdateType(this.json);

  String toJson() {
    return json;
  }

  static UpdateType? fromJson(String json) {
    switch (json) {
      case 'PUT':
        return put;
      case 'PATCH':
        return patch;
      case 'DELETE':
        return delete;
      default:
        return null;
    }
  }

  static UpdateType? fromJsonChecked(String json) {
    var v = fromJson(json);
    assert(v != null, "Unexpected updateType: $json");
    return v;
  }
}

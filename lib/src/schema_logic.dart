import './schema.dart';

const String maxOpId = '9223372036854775807';

String createViewStatement(Table table) {
  final columnNames =
      table.columns.map((column) => '"${column.name}"').join(', ');
  final select = table.columns.map(mapColumn).join(', ');
  return 'CREATE TEMP VIEW IF NOT EXISTS "${table.name}"("id", $columnNames) AS SELECT "id", $select FROM "${table.internalName}"';
}

String mapColumn(Column column) {
  return "CAST(json_extract(data, '\$.${column.name}') as ${column.type})";
}

List<String> createViewTriggerStatements(Table table) {
  if (table.localOnly) {
    return createViewTriggerStatementsLocal(table);
  }
  final type = table.name;
  final internalNameE = '"${table.internalName}"';

  final jsonFragment = table.columns
      .map((column) => "'${column.name}', NEW.${column.name}")
      .join(', ');
  final jsonFragmentOld = table.columns
      .map((column) => "'${column.name}', OLD.${column.name}")
      .join(', ');
  return [
    """
CREATE TEMP TRIGGER IF NOT EXISTS "ps_view_insert_$type"
INSTEAD OF INSERT ON "$type"
FOR EACH ROW
BEGIN
  SELECT CASE
    WHEN (NEW.id IS NULL)
    THEN RAISE (FAIL, 'id is required')
  END;
  INSERT INTO $internalNameE(id, data)
    SELECT NEW.id, json_object($jsonFragment);
  INSERT INTO ps_crud(data) SELECT json_object('op', 'PUT', 'type', '$type', 'id', NEW.id, 'data', json(powersync_diff('{}', json_object($jsonFragment))));
  INSERT INTO ps_oplog(bucket, op_id, op, object_type, object_id, hash, superseded)
    SELECT '\$local',
           1,
           'REMOVE',
           '$type',
           NEW.id,
           0,
           0;
  INSERT OR REPLACE INTO ps_buckets(name, pending_delete, last_op, target_op) VALUES('\$local', 1, 0, $maxOpId);
END;""",
    """
CREATE TEMP TRIGGER IF NOT EXISTS "ps_view_update_$type"
INSTEAD OF UPDATE ON "$type"
FOR EACH ROW
BEGIN
  SELECT CASE
    WHEN (OLD.id != NEW.id)
    THEN RAISE (FAIL, 'Cannot update id')
  END;
  UPDATE $internalNameE
        SET data = json_object($jsonFragment)
        WHERE id = NEW.id;
  INSERT INTO ps_crud(data) SELECT json_object('op', 'PATCH', 'type', '$type', 'id', NEW.id, 'data', json(powersync_diff(json_object($jsonFragmentOld), json_object($jsonFragment))));
  INSERT INTO ps_oplog(bucket, op_id, op, object_type, object_id, hash, superseded)
    SELECT '\$local',
           1,
           'REMOVE',
           '$type',
           NEW.id,
           0,
           0;
  INSERT OR REPLACE INTO ps_buckets(name, pending_delete, last_op, target_op) VALUES('\$local', 1, 0, $maxOpId);
END;""",
    """
CREATE TEMP TRIGGER IF NOT EXISTS "ps_view_delete_$type"
INSTEAD OF DELETE ON "$type"
FOR EACH ROW
BEGIN
  DELETE FROM $internalNameE WHERE id = OLD.id;
  INSERT INTO ps_crud(data) SELECT json_object('op', 'DELETE', 'type', '$type', 'id', OLD.id);
END;"""
  ];
}

List<String> createViewTriggerStatementsLocal(Table table) {
  final type = table.name;
  final internalNameE = '"${table.internalName}"';

  final jsonFragment = table.columns
      .map((column) => "'${column.name}', NEW.${column.name}")
      .join(', ');
  return [
    """
CREATE TEMP TRIGGER IF NOT EXISTS "ps_view_insert_$type"
INSTEAD OF INSERT ON "$type"
FOR EACH ROW
BEGIN
  INSERT INTO $internalNameE(id, data)
    SELECT NEW.id, json_object($jsonFragment);
END;""",
    """
CREATE TEMP TRIGGER IF NOT EXISTS "ps_view_update_$type"
INSTEAD OF UPDATE ON "$type"
FOR EACH ROW
BEGIN
  SELECT CASE
    WHEN (OLD.id != NEW.id)
    THEN RAISE (FAIL, 'Cannot update id')
  END;
  UPDATE $internalNameE
        SET data = json_object($jsonFragment)
        WHERE id = NEW.id;
END;""",
    """
CREATE TEMP TRIGGER IF NOT EXISTS "ps_view_delete_$type"
INSTEAD OF DELETE ON "$type"
FOR EACH ROW
BEGIN
  DELETE FROM $internalNameE WHERE id = OLD.id;
END;"""
  ];
}

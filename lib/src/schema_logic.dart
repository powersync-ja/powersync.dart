import './schema.dart';

const String maxOpId = '9223372036854775807';

String createViewStatement(Table table) {
  final columnNames =
      table.columns.map((column) => '"${column.name}"').join(', ');
  final select = table.columns
      .map((column) =>
          "CAST(json_extract(data, '\$.${column.name}') as ${column.type})")
      .join(', ');
  return 'CREATE TEMP VIEW IF NOT EXISTS "${table.name}"("id", $columnNames) AS SELECT "id", $select FROM "objects__${table.name}"';
}

List<String> createViewTriggerStatements(Table table) {
  final type = table.name;
  final jsonFragment = table.columns
      .map((column) => "'${column.name}', NEW.${column.name}")
      .join(', ');
  final jsonFragmentOld = table.columns
      .map((column) => "'${column.name}', OLD.${column.name}")
      .join(', ');
  return [
    """
CREATE TEMP TRIGGER IF NOT EXISTS view_insert_$type
INSTEAD OF INSERT ON $type
FOR EACH ROW
BEGIN
  INSERT INTO objects__$type(id, data)
    SELECT NEW.id, json_object($jsonFragment);
  INSERT INTO crud(data) SELECT json_object('op', 'PUT', 'type', '$type', 'id', NEW.id, 'data', json(powersync_diff('{}', json_object($jsonFragment))));
  INSERT INTO oplog(bucket, op_id, op, object_type, object_id, hash, superseded)
    SELECT '\$local',
           1,
           'REMOVE',
           '$type',
           NEW.id,
           0,
           0;
  INSERT OR REPLACE INTO buckets(name, pending_delete, last_op, target_op) VALUES('\$local', 1, 0, $maxOpId);
END;""",
    """
CREATE TEMP TRIGGER IF NOT EXISTS view_update_$type
INSTEAD OF UPDATE ON $type
FOR EACH ROW
BEGIN
  SELECT CASE
    WHEN (OLD.id != NEW.id)
    THEN RAISE (FAIL, 'Cannot update id')
  END;
  UPDATE objects__$type
        SET data = json_object($jsonFragment)
        WHERE id = NEW.id;
  INSERT INTO crud(data) SELECT json_object('op', 'PATCH', 'type', '$type', 'id', NEW.id, 'data', json(powersync_diff(json_object($jsonFragmentOld), json_object($jsonFragment))));
  INSERT INTO oplog(bucket, op_id, op, object_type, object_id, hash, superseded)
    SELECT '\$local',
           1,
           'REMOVE',
           '$type',
           NEW.id,
           0,
           0;
  INSERT OR REPLACE INTO buckets(name, pending_delete, last_op, target_op) VALUES('\$local', 1, 0, $maxOpId);
END;""",
    """
CREATE TEMP TRIGGER IF NOT EXISTS view_delete_$type
INSTEAD OF DELETE ON $type
FOR EACH ROW
BEGIN
  DELETE FROM objects__$type WHERE id = OLD.id;
  INSERT INTO crud(data) SELECT json_object('op', 'DELETE', 'type', '$type', 'id', OLD.id);
END;"""
  ];
}

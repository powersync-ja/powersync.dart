// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'database.dart';

// ignore_for_file: type=lint
class $ListItemsTable extends ListItems
    with TableInfo<$ListItemsTable, ListItem> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ListItemsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
      'id', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      clientDefault: () => uuid.v4());
  static const VerificationMeta _createdAtMeta =
      const VerificationMeta('createdAt');
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
      'created_at', aliasedName, false,
      type: DriftSqlType.dateTime,
      requiredDuringInsert: false,
      clientDefault: () => DateTime.now());
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
      'name', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _ownerIdMeta =
      const VerificationMeta('ownerId');
  @override
  late final GeneratedColumn<String> ownerId = GeneratedColumn<String>(
      'owner_id', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  @override
  List<GeneratedColumn> get $columns => [id, createdAt, name, ownerId];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'lists';
  @override
  VerificationContext validateIntegrity(Insertable<ListItem> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('created_at')) {
      context.handle(_createdAtMeta,
          createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta));
    }
    if (data.containsKey('name')) {
      context.handle(
          _nameMeta, name.isAcceptableOrUnknown(data['name']!, _nameMeta));
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('owner_id')) {
      context.handle(_ownerIdMeta,
          ownerId.isAcceptableOrUnknown(data['owner_id']!, _ownerIdMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => const {};
  @override
  ListItem map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ListItem(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}id'])!,
      createdAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}created_at'])!,
      name: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}name'])!,
      ownerId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}owner_id']),
    );
  }

  @override
  $ListItemsTable createAlias(String alias) {
    return $ListItemsTable(attachedDatabase, alias);
  }
}

class ListItem extends DataClass implements Insertable<ListItem> {
  final String id;
  final DateTime createdAt;
  final String name;
  final String? ownerId;
  const ListItem(
      {required this.id,
      required this.createdAt,
      required this.name,
      this.ownerId});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['created_at'] = Variable<DateTime>(createdAt);
    map['name'] = Variable<String>(name);
    if (!nullToAbsent || ownerId != null) {
      map['owner_id'] = Variable<String>(ownerId);
    }
    return map;
  }

  ListItemsCompanion toCompanion(bool nullToAbsent) {
    return ListItemsCompanion(
      id: Value(id),
      createdAt: Value(createdAt),
      name: Value(name),
      ownerId: ownerId == null && nullToAbsent
          ? const Value.absent()
          : Value(ownerId),
    );
  }

  factory ListItem.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ListItem(
      id: serializer.fromJson<String>(json['id']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      name: serializer.fromJson<String>(json['name']),
      ownerId: serializer.fromJson<String?>(json['ownerId']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'name': serializer.toJson<String>(name),
      'ownerId': serializer.toJson<String?>(ownerId),
    };
  }

  ListItem copyWith(
          {String? id,
          DateTime? createdAt,
          String? name,
          Value<String?> ownerId = const Value.absent()}) =>
      ListItem(
        id: id ?? this.id,
        createdAt: createdAt ?? this.createdAt,
        name: name ?? this.name,
        ownerId: ownerId.present ? ownerId.value : this.ownerId,
      );
  @override
  String toString() {
    return (StringBuffer('ListItem(')
          ..write('id: $id, ')
          ..write('createdAt: $createdAt, ')
          ..write('name: $name, ')
          ..write('ownerId: $ownerId')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, createdAt, name, ownerId);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ListItem &&
          other.id == this.id &&
          other.createdAt == this.createdAt &&
          other.name == this.name &&
          other.ownerId == this.ownerId);
}

class ListItemsCompanion extends UpdateCompanion<ListItem> {
  final Value<String> id;
  final Value<DateTime> createdAt;
  final Value<String> name;
  final Value<String?> ownerId;
  final Value<int> rowid;
  const ListItemsCompanion({
    this.id = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.name = const Value.absent(),
    this.ownerId = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ListItemsCompanion.insert({
    this.id = const Value.absent(),
    this.createdAt = const Value.absent(),
    required String name,
    this.ownerId = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : name = Value(name);
  static Insertable<ListItem> custom({
    Expression<String>? id,
    Expression<DateTime>? createdAt,
    Expression<String>? name,
    Expression<String>? ownerId,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (createdAt != null) 'created_at': createdAt,
      if (name != null) 'name': name,
      if (ownerId != null) 'owner_id': ownerId,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ListItemsCompanion copyWith(
      {Value<String>? id,
      Value<DateTime>? createdAt,
      Value<String>? name,
      Value<String?>? ownerId,
      Value<int>? rowid}) {
    return ListItemsCompanion(
      id: id ?? this.id,
      createdAt: createdAt ?? this.createdAt,
      name: name ?? this.name,
      ownerId: ownerId ?? this.ownerId,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (ownerId.present) {
      map['owner_id'] = Variable<String>(ownerId.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ListItemsCompanion(')
          ..write('id: $id, ')
          ..write('createdAt: $createdAt, ')
          ..write('name: $name, ')
          ..write('ownerId: $ownerId, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $TodoItemsTable extends TodoItems
    with TableInfo<$TodoItemsTable, TodoItem> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $TodoItemsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
      'id', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      clientDefault: () => uuid.v4());
  static const VerificationMeta _listIdMeta = const VerificationMeta('listId');
  @override
  late final GeneratedColumn<String> listId = GeneratedColumn<String>(
      'list_id', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: true,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('REFERENCES lists (id)'));
  static const VerificationMeta _photoIdMeta =
      const VerificationMeta('photoId');
  @override
  late final GeneratedColumn<String> photoId = GeneratedColumn<String>(
      'photo_id', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _createdAtMeta =
      const VerificationMeta('createdAt');
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
      'created_at', aliasedName, true,
      type: DriftSqlType.dateTime, requiredDuringInsert: false);
  static const VerificationMeta _completedAtMeta =
      const VerificationMeta('completedAt');
  @override
  late final GeneratedColumn<DateTime> completedAt = GeneratedColumn<DateTime>(
      'completed_at', aliasedName, true,
      type: DriftSqlType.dateTime, requiredDuringInsert: false);
  static const VerificationMeta _completedMeta =
      const VerificationMeta('completed');
  @override
  late final GeneratedColumn<bool> completed = GeneratedColumn<bool>(
      'completed', aliasedName, true,
      type: DriftSqlType.bool,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('CHECK ("completed" IN (0, 1))'));
  static const VerificationMeta _descriptionMeta =
      const VerificationMeta('description');
  @override
  late final GeneratedColumn<String> description = GeneratedColumn<String>(
      'description', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _createdByMeta =
      const VerificationMeta('createdBy');
  @override
  late final GeneratedColumn<String> createdBy = GeneratedColumn<String>(
      'created_by', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _completedByMeta =
      const VerificationMeta('completedBy');
  @override
  late final GeneratedColumn<String> completedBy = GeneratedColumn<String>(
      'completed_by', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  @override
  List<GeneratedColumn> get $columns => [
        id,
        listId,
        photoId,
        createdAt,
        completedAt,
        completed,
        description,
        createdBy,
        completedBy
      ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'todos';
  @override
  VerificationContext validateIntegrity(Insertable<TodoItem> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('list_id')) {
      context.handle(_listIdMeta,
          listId.isAcceptableOrUnknown(data['list_id']!, _listIdMeta));
    } else if (isInserting) {
      context.missing(_listIdMeta);
    }
    if (data.containsKey('photo_id')) {
      context.handle(_photoIdMeta,
          photoId.isAcceptableOrUnknown(data['photo_id']!, _photoIdMeta));
    }
    if (data.containsKey('created_at')) {
      context.handle(_createdAtMeta,
          createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta));
    }
    if (data.containsKey('completed_at')) {
      context.handle(
          _completedAtMeta,
          completedAt.isAcceptableOrUnknown(
              data['completed_at']!, _completedAtMeta));
    }
    if (data.containsKey('completed')) {
      context.handle(_completedMeta,
          completed.isAcceptableOrUnknown(data['completed']!, _completedMeta));
    }
    if (data.containsKey('description')) {
      context.handle(
          _descriptionMeta,
          description.isAcceptableOrUnknown(
              data['description']!, _descriptionMeta));
    } else if (isInserting) {
      context.missing(_descriptionMeta);
    }
    if (data.containsKey('created_by')) {
      context.handle(_createdByMeta,
          createdBy.isAcceptableOrUnknown(data['created_by']!, _createdByMeta));
    }
    if (data.containsKey('completed_by')) {
      context.handle(
          _completedByMeta,
          completedBy.isAcceptableOrUnknown(
              data['completed_by']!, _completedByMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => const {};
  @override
  TodoItem map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return TodoItem(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}id'])!,
      listId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}list_id'])!,
      photoId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}photo_id']),
      createdAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}created_at']),
      completedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}completed_at']),
      completed: attachedDatabase.typeMapping
          .read(DriftSqlType.bool, data['${effectivePrefix}completed']),
      description: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}description'])!,
      createdBy: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}created_by']),
      completedBy: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}completed_by']),
    );
  }

  @override
  $TodoItemsTable createAlias(String alias) {
    return $TodoItemsTable(attachedDatabase, alias);
  }
}

class TodoItem extends DataClass implements Insertable<TodoItem> {
  final String id;
  final String listId;
  final String? photoId;
  final DateTime? createdAt;
  final DateTime? completedAt;
  final bool? completed;
  final String description;
  final String? createdBy;
  final String? completedBy;
  const TodoItem(
      {required this.id,
      required this.listId,
      this.photoId,
      this.createdAt,
      this.completedAt,
      this.completed,
      required this.description,
      this.createdBy,
      this.completedBy});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['list_id'] = Variable<String>(listId);
    if (!nullToAbsent || photoId != null) {
      map['photo_id'] = Variable<String>(photoId);
    }
    if (!nullToAbsent || createdAt != null) {
      map['created_at'] = Variable<DateTime>(createdAt);
    }
    if (!nullToAbsent || completedAt != null) {
      map['completed_at'] = Variable<DateTime>(completedAt);
    }
    if (!nullToAbsent || completed != null) {
      map['completed'] = Variable<bool>(completed);
    }
    map['description'] = Variable<String>(description);
    if (!nullToAbsent || createdBy != null) {
      map['created_by'] = Variable<String>(createdBy);
    }
    if (!nullToAbsent || completedBy != null) {
      map['completed_by'] = Variable<String>(completedBy);
    }
    return map;
  }

  TodoItemsCompanion toCompanion(bool nullToAbsent) {
    return TodoItemsCompanion(
      id: Value(id),
      listId: Value(listId),
      photoId: photoId == null && nullToAbsent
          ? const Value.absent()
          : Value(photoId),
      createdAt: createdAt == null && nullToAbsent
          ? const Value.absent()
          : Value(createdAt),
      completedAt: completedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(completedAt),
      completed: completed == null && nullToAbsent
          ? const Value.absent()
          : Value(completed),
      description: Value(description),
      createdBy: createdBy == null && nullToAbsent
          ? const Value.absent()
          : Value(createdBy),
      completedBy: completedBy == null && nullToAbsent
          ? const Value.absent()
          : Value(completedBy),
    );
  }

  factory TodoItem.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return TodoItem(
      id: serializer.fromJson<String>(json['id']),
      listId: serializer.fromJson<String>(json['listId']),
      photoId: serializer.fromJson<String?>(json['photoId']),
      createdAt: serializer.fromJson<DateTime?>(json['createdAt']),
      completedAt: serializer.fromJson<DateTime?>(json['completedAt']),
      completed: serializer.fromJson<bool?>(json['completed']),
      description: serializer.fromJson<String>(json['description']),
      createdBy: serializer.fromJson<String?>(json['createdBy']),
      completedBy: serializer.fromJson<String?>(json['completedBy']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'listId': serializer.toJson<String>(listId),
      'photoId': serializer.toJson<String?>(photoId),
      'createdAt': serializer.toJson<DateTime?>(createdAt),
      'completedAt': serializer.toJson<DateTime?>(completedAt),
      'completed': serializer.toJson<bool?>(completed),
      'description': serializer.toJson<String>(description),
      'createdBy': serializer.toJson<String?>(createdBy),
      'completedBy': serializer.toJson<String?>(completedBy),
    };
  }

  TodoItem copyWith(
          {String? id,
          String? listId,
          Value<String?> photoId = const Value.absent(),
          Value<DateTime?> createdAt = const Value.absent(),
          Value<DateTime?> completedAt = const Value.absent(),
          Value<bool?> completed = const Value.absent(),
          String? description,
          Value<String?> createdBy = const Value.absent(),
          Value<String?> completedBy = const Value.absent()}) =>
      TodoItem(
        id: id ?? this.id,
        listId: listId ?? this.listId,
        photoId: photoId.present ? photoId.value : this.photoId,
        createdAt: createdAt.present ? createdAt.value : this.createdAt,
        completedAt: completedAt.present ? completedAt.value : this.completedAt,
        completed: completed.present ? completed.value : this.completed,
        description: description ?? this.description,
        createdBy: createdBy.present ? createdBy.value : this.createdBy,
        completedBy: completedBy.present ? completedBy.value : this.completedBy,
      );
  @override
  String toString() {
    return (StringBuffer('TodoItem(')
          ..write('id: $id, ')
          ..write('listId: $listId, ')
          ..write('photoId: $photoId, ')
          ..write('createdAt: $createdAt, ')
          ..write('completedAt: $completedAt, ')
          ..write('completed: $completed, ')
          ..write('description: $description, ')
          ..write('createdBy: $createdBy, ')
          ..write('completedBy: $completedBy')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, listId, photoId, createdAt, completedAt,
      completed, description, createdBy, completedBy);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is TodoItem &&
          other.id == this.id &&
          other.listId == this.listId &&
          other.photoId == this.photoId &&
          other.createdAt == this.createdAt &&
          other.completedAt == this.completedAt &&
          other.completed == this.completed &&
          other.description == this.description &&
          other.createdBy == this.createdBy &&
          other.completedBy == this.completedBy);
}

class TodoItemsCompanion extends UpdateCompanion<TodoItem> {
  final Value<String> id;
  final Value<String> listId;
  final Value<String?> photoId;
  final Value<DateTime?> createdAt;
  final Value<DateTime?> completedAt;
  final Value<bool?> completed;
  final Value<String> description;
  final Value<String?> createdBy;
  final Value<String?> completedBy;
  final Value<int> rowid;
  const TodoItemsCompanion({
    this.id = const Value.absent(),
    this.listId = const Value.absent(),
    this.photoId = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.completedAt = const Value.absent(),
    this.completed = const Value.absent(),
    this.description = const Value.absent(),
    this.createdBy = const Value.absent(),
    this.completedBy = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  TodoItemsCompanion.insert({
    this.id = const Value.absent(),
    required String listId,
    this.photoId = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.completedAt = const Value.absent(),
    this.completed = const Value.absent(),
    required String description,
    this.createdBy = const Value.absent(),
    this.completedBy = const Value.absent(),
    this.rowid = const Value.absent(),
  })  : listId = Value(listId),
        description = Value(description);
  static Insertable<TodoItem> custom({
    Expression<String>? id,
    Expression<String>? listId,
    Expression<String>? photoId,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? completedAt,
    Expression<bool>? completed,
    Expression<String>? description,
    Expression<String>? createdBy,
    Expression<String>? completedBy,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (listId != null) 'list_id': listId,
      if (photoId != null) 'photo_id': photoId,
      if (createdAt != null) 'created_at': createdAt,
      if (completedAt != null) 'completed_at': completedAt,
      if (completed != null) 'completed': completed,
      if (description != null) 'description': description,
      if (createdBy != null) 'created_by': createdBy,
      if (completedBy != null) 'completed_by': completedBy,
      if (rowid != null) 'rowid': rowid,
    });
  }

  TodoItemsCompanion copyWith(
      {Value<String>? id,
      Value<String>? listId,
      Value<String?>? photoId,
      Value<DateTime?>? createdAt,
      Value<DateTime?>? completedAt,
      Value<bool?>? completed,
      Value<String>? description,
      Value<String?>? createdBy,
      Value<String?>? completedBy,
      Value<int>? rowid}) {
    return TodoItemsCompanion(
      id: id ?? this.id,
      listId: listId ?? this.listId,
      photoId: photoId ?? this.photoId,
      createdAt: createdAt ?? this.createdAt,
      completedAt: completedAt ?? this.completedAt,
      completed: completed ?? this.completed,
      description: description ?? this.description,
      createdBy: createdBy ?? this.createdBy,
      completedBy: completedBy ?? this.completedBy,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (listId.present) {
      map['list_id'] = Variable<String>(listId.value);
    }
    if (photoId.present) {
      map['photo_id'] = Variable<String>(photoId.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (completedAt.present) {
      map['completed_at'] = Variable<DateTime>(completedAt.value);
    }
    if (completed.present) {
      map['completed'] = Variable<bool>(completed.value);
    }
    if (description.present) {
      map['description'] = Variable<String>(description.value);
    }
    if (createdBy.present) {
      map['created_by'] = Variable<String>(createdBy.value);
    }
    if (completedBy.present) {
      map['completed_by'] = Variable<String>(completedBy.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('TodoItemsCompanion(')
          ..write('id: $id, ')
          ..write('listId: $listId, ')
          ..write('photoId: $photoId, ')
          ..write('createdAt: $createdAt, ')
          ..write('completedAt: $completedAt, ')
          ..write('completed: $completed, ')
          ..write('description: $description, ')
          ..write('createdBy: $createdBy, ')
          ..write('completedBy: $completedBy, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  late final $ListItemsTable listItems = $ListItemsTable(this);
  late final $TodoItemsTable todoItems = $TodoItemsTable(this);
  Selectable<ListItemWithStats> listsWithStats() {
    return customSelect(
        'SELECT"self"."id" AS "nested_0.id", "self"."created_at" AS "nested_0.created_at", "self"."name" AS "nested_0.name", "self"."owner_id" AS "nested_0.owner_id", (SELECT count() FROM todos WHERE list_id = self.id AND completed = TRUE) AS completed_count, (SELECT count() FROM todos WHERE list_id = self.id AND completed = FALSE) AS pending_count FROM lists AS self ORDER BY created_at',
        variables: [],
        readsFrom: {
          todoItems,
          listItems,
        }).asyncMap((QueryRow row) async => ListItemWithStats(
          await listItems.mapFromRow(row, tablePrefix: 'nested_0'),
          row.read<int>('completed_count'),
          row.read<int>('pending_count'),
        ));
  }

  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [listItems, todoItems];
  @override
  DriftDatabaseOptions get options =>
      const DriftDatabaseOptions(storeDateTimeAsText: true);
}

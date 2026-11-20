// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'app_database.dart';

// ignore_for_file: type=lint
class $BooksTable extends Books with TableInfo<$BooksTable, BookRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $BooksTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _titleMeta = const VerificationMeta('title');
  @override
  late final GeneratedColumn<String> title = GeneratedColumn<String>(
    'title',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _entryUrlMeta = const VerificationMeta(
    'entryUrl',
  );
  @override
  late final GeneratedColumn<String> entryUrl = GeneratedColumn<String>(
    'entry_url',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _scopePrefixMeta = const VerificationMeta(
    'scopePrefix',
  );
  @override
  late final GeneratedColumn<String> scopePrefix = GeneratedColumn<String>(
    'scope_prefix',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _iconUrlMeta = const VerificationMeta(
    'iconUrl',
  );
  @override
  late final GeneratedColumn<String> iconUrl = GeneratedColumn<String>(
    'icon_url',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _themeColorMeta = const VerificationMeta(
    'themeColor',
  );
  @override
  late final GeneratedColumn<int> themeColor = GeneratedColumn<int>(
    'theme_color',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _groupIdMeta = const VerificationMeta(
    'groupId',
  );
  @override
  late final GeneratedColumn<String> groupId = GeneratedColumn<String>(
    'group_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _sortIndexMeta = const VerificationMeta(
    'sortIndex',
  );
  @override
  late final GeneratedColumn<int> sortIndex = GeneratedColumn<int>(
    'sort_index',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _presetIdMeta = const VerificationMeta(
    'presetId',
  );
  @override
  late final GeneratedColumn<String> presetId = GeneratedColumn<String>(
    'preset_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _deletedAtMeta = const VerificationMeta(
    'deletedAt',
  );
  @override
  late final GeneratedColumn<DateTime> deletedAt = GeneratedColumn<DateTime>(
    'deleted_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    title,
    entryUrl,
    scopePrefix,
    iconUrl,
    themeColor,
    groupId,
    sortIndex,
    presetId,
    createdAt,
    updatedAt,
    deletedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'books';
  @override
  VerificationContext validateIntegrity(
    Insertable<BookRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('title')) {
      context.handle(
        _titleMeta,
        title.isAcceptableOrUnknown(data['title']!, _titleMeta),
      );
    } else if (isInserting) {
      context.missing(_titleMeta);
    }
    if (data.containsKey('entry_url')) {
      context.handle(
        _entryUrlMeta,
        entryUrl.isAcceptableOrUnknown(data['entry_url']!, _entryUrlMeta),
      );
    } else if (isInserting) {
      context.missing(_entryUrlMeta);
    }
    if (data.containsKey('scope_prefix')) {
      context.handle(
        _scopePrefixMeta,
        scopePrefix.isAcceptableOrUnknown(
          data['scope_prefix']!,
          _scopePrefixMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_scopePrefixMeta);
    }
    if (data.containsKey('icon_url')) {
      context.handle(
        _iconUrlMeta,
        iconUrl.isAcceptableOrUnknown(data['icon_url']!, _iconUrlMeta),
      );
    }
    if (data.containsKey('theme_color')) {
      context.handle(
        _themeColorMeta,
        themeColor.isAcceptableOrUnknown(data['theme_color']!, _themeColorMeta),
      );
    }
    if (data.containsKey('group_id')) {
      context.handle(
        _groupIdMeta,
        groupId.isAcceptableOrUnknown(data['group_id']!, _groupIdMeta),
      );
    }
    if (data.containsKey('sort_index')) {
      context.handle(
        _sortIndexMeta,
        sortIndex.isAcceptableOrUnknown(data['sort_index']!, _sortIndexMeta),
      );
    }
    if (data.containsKey('preset_id')) {
      context.handle(
        _presetIdMeta,
        presetId.isAcceptableOrUnknown(data['preset_id']!, _presetIdMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    if (data.containsKey('deleted_at')) {
      context.handle(
        _deletedAtMeta,
        deletedAt.isAcceptableOrUnknown(data['deleted_at']!, _deletedAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  BookRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return BookRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      title: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}title'],
      )!,
      entryUrl: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}entry_url'],
      )!,
      scopePrefix: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}scope_prefix'],
      )!,
      iconUrl: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}icon_url'],
      ),
      themeColor: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}theme_color'],
      ),
      groupId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}group_id'],
      ),
      sortIndex: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}sort_index'],
      )!,
      presetId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}preset_id'],
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
      deletedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}deleted_at'],
      ),
    );
  }

  @override
  $BooksTable createAlias(String alias) {
    return $BooksTable(attachedDatabase, alias);
  }
}

class BookRow extends DataClass implements Insertable<BookRow> {
  final String id;
  final String title;
  final String entryUrl;
  final String scopePrefix;
  final String? iconUrl;
  final int? themeColor;
  final String? groupId;
  final int sortIndex;

  /// 这本书打开时使用的深色注入预设 id。
  ///
  /// null 表示「默认」—— 不注入任何样式，网页原样显示。
  final String? presetId;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;
  const BookRow({
    required this.id,
    required this.title,
    required this.entryUrl,
    required this.scopePrefix,
    this.iconUrl,
    this.themeColor,
    this.groupId,
    required this.sortIndex,
    this.presetId,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['title'] = Variable<String>(title);
    map['entry_url'] = Variable<String>(entryUrl);
    map['scope_prefix'] = Variable<String>(scopePrefix);
    if (!nullToAbsent || iconUrl != null) {
      map['icon_url'] = Variable<String>(iconUrl);
    }
    if (!nullToAbsent || themeColor != null) {
      map['theme_color'] = Variable<int>(themeColor);
    }
    if (!nullToAbsent || groupId != null) {
      map['group_id'] = Variable<String>(groupId);
    }
    map['sort_index'] = Variable<int>(sortIndex);
    if (!nullToAbsent || presetId != null) {
      map['preset_id'] = Variable<String>(presetId);
    }
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    if (!nullToAbsent || deletedAt != null) {
      map['deleted_at'] = Variable<DateTime>(deletedAt);
    }
    return map;
  }

  BooksCompanion toCompanion(bool nullToAbsent) {
    return BooksCompanion(
      id: Value(id),
      title: Value(title),
      entryUrl: Value(entryUrl),
      scopePrefix: Value(scopePrefix),
      iconUrl: iconUrl == null && nullToAbsent
          ? const Value.absent()
          : Value(iconUrl),
      themeColor: themeColor == null && nullToAbsent
          ? const Value.absent()
          : Value(themeColor),
      groupId: groupId == null && nullToAbsent
          ? const Value.absent()
          : Value(groupId),
      sortIndex: Value(sortIndex),
      presetId: presetId == null && nullToAbsent
          ? const Value.absent()
          : Value(presetId),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
      deletedAt: deletedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(deletedAt),
    );
  }

  factory BookRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return BookRow(
      id: serializer.fromJson<String>(json['id']),
      title: serializer.fromJson<String>(json['title']),
      entryUrl: serializer.fromJson<String>(json['entryUrl']),
      scopePrefix: serializer.fromJson<String>(json['scopePrefix']),
      iconUrl: serializer.fromJson<String?>(json['iconUrl']),
      themeColor: serializer.fromJson<int?>(json['themeColor']),
      groupId: serializer.fromJson<String?>(json['groupId']),
      sortIndex: serializer.fromJson<int>(json['sortIndex']),
      presetId: serializer.fromJson<String?>(json['presetId']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
      deletedAt: serializer.fromJson<DateTime?>(json['deletedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'title': serializer.toJson<String>(title),
      'entryUrl': serializer.toJson<String>(entryUrl),
      'scopePrefix': serializer.toJson<String>(scopePrefix),
      'iconUrl': serializer.toJson<String?>(iconUrl),
      'themeColor': serializer.toJson<int?>(themeColor),
      'groupId': serializer.toJson<String?>(groupId),
      'sortIndex': serializer.toJson<int>(sortIndex),
      'presetId': serializer.toJson<String?>(presetId),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
      'deletedAt': serializer.toJson<DateTime?>(deletedAt),
    };
  }

  BookRow copyWith({
    String? id,
    String? title,
    String? entryUrl,
    String? scopePrefix,
    Value<String?> iconUrl = const Value.absent(),
    Value<int?> themeColor = const Value.absent(),
    Value<String?> groupId = const Value.absent(),
    int? sortIndex,
    Value<String?> presetId = const Value.absent(),
    DateTime? createdAt,
    DateTime? updatedAt,
    Value<DateTime?> deletedAt = const Value.absent(),
  }) => BookRow(
    id: id ?? this.id,
    title: title ?? this.title,
    entryUrl: entryUrl ?? this.entryUrl,
    scopePrefix: scopePrefix ?? this.scopePrefix,
    iconUrl: iconUrl.present ? iconUrl.value : this.iconUrl,
    themeColor: themeColor.present ? themeColor.value : this.themeColor,
    groupId: groupId.present ? groupId.value : this.groupId,
    sortIndex: sortIndex ?? this.sortIndex,
    presetId: presetId.present ? presetId.value : this.presetId,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    deletedAt: deletedAt.present ? deletedAt.value : this.deletedAt,
  );
  BookRow copyWithCompanion(BooksCompanion data) {
    return BookRow(
      id: data.id.present ? data.id.value : this.id,
      title: data.title.present ? data.title.value : this.title,
      entryUrl: data.entryUrl.present ? data.entryUrl.value : this.entryUrl,
      scopePrefix: data.scopePrefix.present
          ? data.scopePrefix.value
          : this.scopePrefix,
      iconUrl: data.iconUrl.present ? data.iconUrl.value : this.iconUrl,
      themeColor: data.themeColor.present
          ? data.themeColor.value
          : this.themeColor,
      groupId: data.groupId.present ? data.groupId.value : this.groupId,
      sortIndex: data.sortIndex.present ? data.sortIndex.value : this.sortIndex,
      presetId: data.presetId.present ? data.presetId.value : this.presetId,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      deletedAt: data.deletedAt.present ? data.deletedAt.value : this.deletedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('BookRow(')
          ..write('id: $id, ')
          ..write('title: $title, ')
          ..write('entryUrl: $entryUrl, ')
          ..write('scopePrefix: $scopePrefix, ')
          ..write('iconUrl: $iconUrl, ')
          ..write('themeColor: $themeColor, ')
          ..write('groupId: $groupId, ')
          ..write('sortIndex: $sortIndex, ')
          ..write('presetId: $presetId, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deletedAt: $deletedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    title,
    entryUrl,
    scopePrefix,
    iconUrl,
    themeColor,
    groupId,
    sortIndex,
    presetId,
    createdAt,
    updatedAt,
    deletedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is BookRow &&
          other.id == this.id &&
          other.title == this.title &&
          other.entryUrl == this.entryUrl &&
          other.scopePrefix == this.scopePrefix &&
          other.iconUrl == this.iconUrl &&
          other.themeColor == this.themeColor &&
          other.groupId == this.groupId &&
          other.sortIndex == this.sortIndex &&
          other.presetId == this.presetId &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt &&
          other.deletedAt == this.deletedAt);
}

class BooksCompanion extends UpdateCompanion<BookRow> {
  final Value<String> id;
  final Value<String> title;
  final Value<String> entryUrl;
  final Value<String> scopePrefix;
  final Value<String?> iconUrl;
  final Value<int?> themeColor;
  final Value<String?> groupId;
  final Value<int> sortIndex;
  final Value<String?> presetId;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  final Value<DateTime?> deletedAt;
  final Value<int> rowid;
  const BooksCompanion({
    this.id = const Value.absent(),
    this.title = const Value.absent(),
    this.entryUrl = const Value.absent(),
    this.scopePrefix = const Value.absent(),
    this.iconUrl = const Value.absent(),
    this.themeColor = const Value.absent(),
    this.groupId = const Value.absent(),
    this.sortIndex = const Value.absent(),
    this.presetId = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.deletedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  BooksCompanion.insert({
    required String id,
    required String title,
    required String entryUrl,
    required String scopePrefix,
    this.iconUrl = const Value.absent(),
    this.themeColor = const Value.absent(),
    this.groupId = const Value.absent(),
    this.sortIndex = const Value.absent(),
    this.presetId = const Value.absent(),
    required DateTime createdAt,
    required DateTime updatedAt,
    this.deletedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       title = Value(title),
       entryUrl = Value(entryUrl),
       scopePrefix = Value(scopePrefix),
       createdAt = Value(createdAt),
       updatedAt = Value(updatedAt);
  static Insertable<BookRow> custom({
    Expression<String>? id,
    Expression<String>? title,
    Expression<String>? entryUrl,
    Expression<String>? scopePrefix,
    Expression<String>? iconUrl,
    Expression<int>? themeColor,
    Expression<String>? groupId,
    Expression<int>? sortIndex,
    Expression<String>? presetId,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
    Expression<DateTime>? deletedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (title != null) 'title': title,
      if (entryUrl != null) 'entry_url': entryUrl,
      if (scopePrefix != null) 'scope_prefix': scopePrefix,
      if (iconUrl != null) 'icon_url': iconUrl,
      if (themeColor != null) 'theme_color': themeColor,
      if (groupId != null) 'group_id': groupId,
      if (sortIndex != null) 'sort_index': sortIndex,
      if (presetId != null) 'preset_id': presetId,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (deletedAt != null) 'deleted_at': deletedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  BooksCompanion copyWith({
    Value<String>? id,
    Value<String>? title,
    Value<String>? entryUrl,
    Value<String>? scopePrefix,
    Value<String?>? iconUrl,
    Value<int?>? themeColor,
    Value<String?>? groupId,
    Value<int>? sortIndex,
    Value<String?>? presetId,
    Value<DateTime>? createdAt,
    Value<DateTime>? updatedAt,
    Value<DateTime?>? deletedAt,
    Value<int>? rowid,
  }) {
    return BooksCompanion(
      id: id ?? this.id,
      title: title ?? this.title,
      entryUrl: entryUrl ?? this.entryUrl,
      scopePrefix: scopePrefix ?? this.scopePrefix,
      iconUrl: iconUrl ?? this.iconUrl,
      themeColor: themeColor ?? this.themeColor,
      groupId: groupId ?? this.groupId,
      sortIndex: sortIndex ?? this.sortIndex,
      presetId: presetId ?? this.presetId,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      deletedAt: deletedAt ?? this.deletedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (entryUrl.present) {
      map['entry_url'] = Variable<String>(entryUrl.value);
    }
    if (scopePrefix.present) {
      map['scope_prefix'] = Variable<String>(scopePrefix.value);
    }
    if (iconUrl.present) {
      map['icon_url'] = Variable<String>(iconUrl.value);
    }
    if (themeColor.present) {
      map['theme_color'] = Variable<int>(themeColor.value);
    }
    if (groupId.present) {
      map['group_id'] = Variable<String>(groupId.value);
    }
    if (sortIndex.present) {
      map['sort_index'] = Variable<int>(sortIndex.value);
    }
    if (presetId.present) {
      map['preset_id'] = Variable<String>(presetId.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (deletedAt.present) {
      map['deleted_at'] = Variable<DateTime>(deletedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('BooksCompanion(')
          ..write('id: $id, ')
          ..write('title: $title, ')
          ..write('entryUrl: $entryUrl, ')
          ..write('scopePrefix: $scopePrefix, ')
          ..write('iconUrl: $iconUrl, ')
          ..write('themeColor: $themeColor, ')
          ..write('groupId: $groupId, ')
          ..write('sortIndex: $sortIndex, ')
          ..write('presetId: $presetId, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $GroupsTable extends Groups with TableInfo<$GroupsTable, GroupRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $GroupsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _sortIndexMeta = const VerificationMeta(
    'sortIndex',
  );
  @override
  late final GeneratedColumn<int> sortIndex = GeneratedColumn<int>(
    'sort_index',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _deletedAtMeta = const VerificationMeta(
    'deletedAt',
  );
  @override
  late final GeneratedColumn<DateTime> deletedAt = GeneratedColumn<DateTime>(
    'deleted_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    name,
    sortIndex,
    updatedAt,
    deletedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'groups';
  @override
  VerificationContext validateIntegrity(
    Insertable<GroupRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('sort_index')) {
      context.handle(
        _sortIndexMeta,
        sortIndex.isAcceptableOrUnknown(data['sort_index']!, _sortIndexMeta),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    if (data.containsKey('deleted_at')) {
      context.handle(
        _deletedAtMeta,
        deletedAt.isAcceptableOrUnknown(data['deleted_at']!, _deletedAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  GroupRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return GroupRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      sortIndex: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}sort_index'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
      deletedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}deleted_at'],
      ),
    );
  }

  @override
  $GroupsTable createAlias(String alias) {
    return $GroupsTable(attachedDatabase, alias);
  }
}

class GroupRow extends DataClass implements Insertable<GroupRow> {
  final String id;
  final String name;
  final int sortIndex;
  final DateTime updatedAt;
  final DateTime? deletedAt;
  const GroupRow({
    required this.id,
    required this.name,
    required this.sortIndex,
    required this.updatedAt,
    this.deletedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['name'] = Variable<String>(name);
    map['sort_index'] = Variable<int>(sortIndex);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    if (!nullToAbsent || deletedAt != null) {
      map['deleted_at'] = Variable<DateTime>(deletedAt);
    }
    return map;
  }

  GroupsCompanion toCompanion(bool nullToAbsent) {
    return GroupsCompanion(
      id: Value(id),
      name: Value(name),
      sortIndex: Value(sortIndex),
      updatedAt: Value(updatedAt),
      deletedAt: deletedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(deletedAt),
    );
  }

  factory GroupRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return GroupRow(
      id: serializer.fromJson<String>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      sortIndex: serializer.fromJson<int>(json['sortIndex']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
      deletedAt: serializer.fromJson<DateTime?>(json['deletedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'name': serializer.toJson<String>(name),
      'sortIndex': serializer.toJson<int>(sortIndex),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
      'deletedAt': serializer.toJson<DateTime?>(deletedAt),
    };
  }

  GroupRow copyWith({
    String? id,
    String? name,
    int? sortIndex,
    DateTime? updatedAt,
    Value<DateTime?> deletedAt = const Value.absent(),
  }) => GroupRow(
    id: id ?? this.id,
    name: name ?? this.name,
    sortIndex: sortIndex ?? this.sortIndex,
    updatedAt: updatedAt ?? this.updatedAt,
    deletedAt: deletedAt.present ? deletedAt.value : this.deletedAt,
  );
  GroupRow copyWithCompanion(GroupsCompanion data) {
    return GroupRow(
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      sortIndex: data.sortIndex.present ? data.sortIndex.value : this.sortIndex,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      deletedAt: data.deletedAt.present ? data.deletedAt.value : this.deletedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('GroupRow(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('sortIndex: $sortIndex, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deletedAt: $deletedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, name, sortIndex, updatedAt, deletedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is GroupRow &&
          other.id == this.id &&
          other.name == this.name &&
          other.sortIndex == this.sortIndex &&
          other.updatedAt == this.updatedAt &&
          other.deletedAt == this.deletedAt);
}

class GroupsCompanion extends UpdateCompanion<GroupRow> {
  final Value<String> id;
  final Value<String> name;
  final Value<int> sortIndex;
  final Value<DateTime> updatedAt;
  final Value<DateTime?> deletedAt;
  final Value<int> rowid;
  const GroupsCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.sortIndex = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.deletedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  GroupsCompanion.insert({
    required String id,
    required String name,
    this.sortIndex = const Value.absent(),
    required DateTime updatedAt,
    this.deletedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       name = Value(name),
       updatedAt = Value(updatedAt);
  static Insertable<GroupRow> custom({
    Expression<String>? id,
    Expression<String>? name,
    Expression<int>? sortIndex,
    Expression<DateTime>? updatedAt,
    Expression<DateTime>? deletedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (sortIndex != null) 'sort_index': sortIndex,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (deletedAt != null) 'deleted_at': deletedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  GroupsCompanion copyWith({
    Value<String>? id,
    Value<String>? name,
    Value<int>? sortIndex,
    Value<DateTime>? updatedAt,
    Value<DateTime?>? deletedAt,
    Value<int>? rowid,
  }) {
    return GroupsCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
      sortIndex: sortIndex ?? this.sortIndex,
      updatedAt: updatedAt ?? this.updatedAt,
      deletedAt: deletedAt ?? this.deletedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (sortIndex.present) {
      map['sort_index'] = Variable<int>(sortIndex.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (deletedAt.present) {
      map['deleted_at'] = Variable<DateTime>(deletedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('GroupsCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('sortIndex: $sortIndex, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ProgressEntriesTable extends ProgressEntries
    with TableInfo<$ProgressEntriesTable, ProgressRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ProgressEntriesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _bookIdMeta = const VerificationMeta('bookId');
  @override
  late final GeneratedColumn<String> bookId = GeneratedColumn<String>(
    'book_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _urlMeta = const VerificationMeta('url');
  @override
  late final GeneratedColumn<String> url = GeneratedColumn<String>(
    'url',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _pageTitleMeta = const VerificationMeta(
    'pageTitle',
  );
  @override
  late final GeneratedColumn<String> pageTitle = GeneratedColumn<String>(
    'page_title',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _pageHashMeta = const VerificationMeta(
    'pageHash',
  );
  @override
  late final GeneratedColumn<String> pageHash = GeneratedColumn<String>(
    'page_hash',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _anchorJsonMeta = const VerificationMeta(
    'anchorJson',
  );
  @override
  late final GeneratedColumn<String> anchorJson = GeneratedColumn<String>(
    'anchor_json',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _deviceIdMeta = const VerificationMeta(
    'deviceId',
  );
  @override
  late final GeneratedColumn<String> deviceId = GeneratedColumn<String>(
    'device_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('local'),
  );
  @override
  List<GeneratedColumn> get $columns => [
    bookId,
    url,
    pageTitle,
    pageHash,
    anchorJson,
    updatedAt,
    deviceId,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'progress_entries';
  @override
  VerificationContext validateIntegrity(
    Insertable<ProgressRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('book_id')) {
      context.handle(
        _bookIdMeta,
        bookId.isAcceptableOrUnknown(data['book_id']!, _bookIdMeta),
      );
    } else if (isInserting) {
      context.missing(_bookIdMeta);
    }
    if (data.containsKey('url')) {
      context.handle(
        _urlMeta,
        url.isAcceptableOrUnknown(data['url']!, _urlMeta),
      );
    } else if (isInserting) {
      context.missing(_urlMeta);
    }
    if (data.containsKey('page_title')) {
      context.handle(
        _pageTitleMeta,
        pageTitle.isAcceptableOrUnknown(data['page_title']!, _pageTitleMeta),
      );
    }
    if (data.containsKey('page_hash')) {
      context.handle(
        _pageHashMeta,
        pageHash.isAcceptableOrUnknown(data['page_hash']!, _pageHashMeta),
      );
    }
    if (data.containsKey('anchor_json')) {
      context.handle(
        _anchorJsonMeta,
        anchorJson.isAcceptableOrUnknown(data['anchor_json']!, _anchorJsonMeta),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    if (data.containsKey('device_id')) {
      context.handle(
        _deviceIdMeta,
        deviceId.isAcceptableOrUnknown(data['device_id']!, _deviceIdMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {bookId, url};
  @override
  ProgressRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ProgressRow(
      bookId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}book_id'],
      )!,
      url: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}url'],
      )!,
      pageTitle: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}page_title'],
      )!,
      pageHash: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}page_hash'],
      ),
      anchorJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}anchor_json'],
      ),
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
      deviceId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}device_id'],
      )!,
    );
  }

  @override
  $ProgressEntriesTable createAlias(String alias) {
    return $ProgressEntriesTable(attachedDatabase, alias);
  }
}

class ProgressRow extends DataClass implements Insertable<ProgressRow> {
  final String bookId;
  final String url;
  final String pageTitle;
  final String? pageHash;
  final String? anchorJson;
  final DateTime updatedAt;
  final String deviceId;
  const ProgressRow({
    required this.bookId,
    required this.url,
    required this.pageTitle,
    this.pageHash,
    this.anchorJson,
    required this.updatedAt,
    required this.deviceId,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['book_id'] = Variable<String>(bookId);
    map['url'] = Variable<String>(url);
    map['page_title'] = Variable<String>(pageTitle);
    if (!nullToAbsent || pageHash != null) {
      map['page_hash'] = Variable<String>(pageHash);
    }
    if (!nullToAbsent || anchorJson != null) {
      map['anchor_json'] = Variable<String>(anchorJson);
    }
    map['updated_at'] = Variable<DateTime>(updatedAt);
    map['device_id'] = Variable<String>(deviceId);
    return map;
  }

  ProgressEntriesCompanion toCompanion(bool nullToAbsent) {
    return ProgressEntriesCompanion(
      bookId: Value(bookId),
      url: Value(url),
      pageTitle: Value(pageTitle),
      pageHash: pageHash == null && nullToAbsent
          ? const Value.absent()
          : Value(pageHash),
      anchorJson: anchorJson == null && nullToAbsent
          ? const Value.absent()
          : Value(anchorJson),
      updatedAt: Value(updatedAt),
      deviceId: Value(deviceId),
    );
  }

  factory ProgressRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ProgressRow(
      bookId: serializer.fromJson<String>(json['bookId']),
      url: serializer.fromJson<String>(json['url']),
      pageTitle: serializer.fromJson<String>(json['pageTitle']),
      pageHash: serializer.fromJson<String?>(json['pageHash']),
      anchorJson: serializer.fromJson<String?>(json['anchorJson']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
      deviceId: serializer.fromJson<String>(json['deviceId']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'bookId': serializer.toJson<String>(bookId),
      'url': serializer.toJson<String>(url),
      'pageTitle': serializer.toJson<String>(pageTitle),
      'pageHash': serializer.toJson<String?>(pageHash),
      'anchorJson': serializer.toJson<String?>(anchorJson),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
      'deviceId': serializer.toJson<String>(deviceId),
    };
  }

  ProgressRow copyWith({
    String? bookId,
    String? url,
    String? pageTitle,
    Value<String?> pageHash = const Value.absent(),
    Value<String?> anchorJson = const Value.absent(),
    DateTime? updatedAt,
    String? deviceId,
  }) => ProgressRow(
    bookId: bookId ?? this.bookId,
    url: url ?? this.url,
    pageTitle: pageTitle ?? this.pageTitle,
    pageHash: pageHash.present ? pageHash.value : this.pageHash,
    anchorJson: anchorJson.present ? anchorJson.value : this.anchorJson,
    updatedAt: updatedAt ?? this.updatedAt,
    deviceId: deviceId ?? this.deviceId,
  );
  ProgressRow copyWithCompanion(ProgressEntriesCompanion data) {
    return ProgressRow(
      bookId: data.bookId.present ? data.bookId.value : this.bookId,
      url: data.url.present ? data.url.value : this.url,
      pageTitle: data.pageTitle.present ? data.pageTitle.value : this.pageTitle,
      pageHash: data.pageHash.present ? data.pageHash.value : this.pageHash,
      anchorJson: data.anchorJson.present
          ? data.anchorJson.value
          : this.anchorJson,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      deviceId: data.deviceId.present ? data.deviceId.value : this.deviceId,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ProgressRow(')
          ..write('bookId: $bookId, ')
          ..write('url: $url, ')
          ..write('pageTitle: $pageTitle, ')
          ..write('pageHash: $pageHash, ')
          ..write('anchorJson: $anchorJson, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deviceId: $deviceId')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    bookId,
    url,
    pageTitle,
    pageHash,
    anchorJson,
    updatedAt,
    deviceId,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ProgressRow &&
          other.bookId == this.bookId &&
          other.url == this.url &&
          other.pageTitle == this.pageTitle &&
          other.pageHash == this.pageHash &&
          other.anchorJson == this.anchorJson &&
          other.updatedAt == this.updatedAt &&
          other.deviceId == this.deviceId);
}

class ProgressEntriesCompanion extends UpdateCompanion<ProgressRow> {
  final Value<String> bookId;
  final Value<String> url;
  final Value<String> pageTitle;
  final Value<String?> pageHash;
  final Value<String?> anchorJson;
  final Value<DateTime> updatedAt;
  final Value<String> deviceId;
  final Value<int> rowid;
  const ProgressEntriesCompanion({
    this.bookId = const Value.absent(),
    this.url = const Value.absent(),
    this.pageTitle = const Value.absent(),
    this.pageHash = const Value.absent(),
    this.anchorJson = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.deviceId = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ProgressEntriesCompanion.insert({
    required String bookId,
    required String url,
    this.pageTitle = const Value.absent(),
    this.pageHash = const Value.absent(),
    this.anchorJson = const Value.absent(),
    required DateTime updatedAt,
    this.deviceId = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : bookId = Value(bookId),
       url = Value(url),
       updatedAt = Value(updatedAt);
  static Insertable<ProgressRow> custom({
    Expression<String>? bookId,
    Expression<String>? url,
    Expression<String>? pageTitle,
    Expression<String>? pageHash,
    Expression<String>? anchorJson,
    Expression<DateTime>? updatedAt,
    Expression<String>? deviceId,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (bookId != null) 'book_id': bookId,
      if (url != null) 'url': url,
      if (pageTitle != null) 'page_title': pageTitle,
      if (pageHash != null) 'page_hash': pageHash,
      if (anchorJson != null) 'anchor_json': anchorJson,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (deviceId != null) 'device_id': deviceId,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ProgressEntriesCompanion copyWith({
    Value<String>? bookId,
    Value<String>? url,
    Value<String>? pageTitle,
    Value<String?>? pageHash,
    Value<String?>? anchorJson,
    Value<DateTime>? updatedAt,
    Value<String>? deviceId,
    Value<int>? rowid,
  }) {
    return ProgressEntriesCompanion(
      bookId: bookId ?? this.bookId,
      url: url ?? this.url,
      pageTitle: pageTitle ?? this.pageTitle,
      pageHash: pageHash ?? this.pageHash,
      anchorJson: anchorJson ?? this.anchorJson,
      updatedAt: updatedAt ?? this.updatedAt,
      deviceId: deviceId ?? this.deviceId,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (bookId.present) {
      map['book_id'] = Variable<String>(bookId.value);
    }
    if (url.present) {
      map['url'] = Variable<String>(url.value);
    }
    if (pageTitle.present) {
      map['page_title'] = Variable<String>(pageTitle.value);
    }
    if (pageHash.present) {
      map['page_hash'] = Variable<String>(pageHash.value);
    }
    if (anchorJson.present) {
      map['anchor_json'] = Variable<String>(anchorJson.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (deviceId.present) {
      map['device_id'] = Variable<String>(deviceId.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ProgressEntriesCompanion(')
          ..write('bookId: $bookId, ')
          ..write('url: $url, ')
          ..write('pageTitle: $pageTitle, ')
          ..write('pageHash: $pageHash, ')
          ..write('anchorJson: $anchorJson, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deviceId: $deviceId, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $SyncSnapshotsTable extends SyncSnapshots
    with TableInfo<$SyncSnapshotsTable, SyncSnapshot> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SyncSnapshotsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _bookIdMeta = const VerificationMeta('bookId');
  @override
  late final GeneratedColumn<String> bookId = GeneratedColumn<String>(
    'book_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _seenAtMeta = const VerificationMeta('seenAt');
  @override
  late final GeneratedColumn<DateTime> seenAt = GeneratedColumn<DateTime>(
    'seen_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [bookId, seenAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'sync_snapshots';
  @override
  VerificationContext validateIntegrity(
    Insertable<SyncSnapshot> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('book_id')) {
      context.handle(
        _bookIdMeta,
        bookId.isAcceptableOrUnknown(data['book_id']!, _bookIdMeta),
      );
    } else if (isInserting) {
      context.missing(_bookIdMeta);
    }
    if (data.containsKey('seen_at')) {
      context.handle(
        _seenAtMeta,
        seenAt.isAcceptableOrUnknown(data['seen_at']!, _seenAtMeta),
      );
    } else if (isInserting) {
      context.missing(_seenAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {bookId};
  @override
  SyncSnapshot map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SyncSnapshot(
      bookId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}book_id'],
      )!,
      seenAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}seen_at'],
      )!,
    );
  }

  @override
  $SyncSnapshotsTable createAlias(String alias) {
    return $SyncSnapshotsTable(attachedDatabase, alias);
  }
}

class SyncSnapshot extends DataClass implements Insertable<SyncSnapshot> {
  /// 快照里记录的书 ID。
  final String bookId;

  /// 上次同步时这本书是否存在(含墓碑时仍为 true)。
  ///
  /// 目前只用存在性,但保留时间戳便于将来做更细的判定。
  final DateTime seenAt;
  const SyncSnapshot({required this.bookId, required this.seenAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['book_id'] = Variable<String>(bookId);
    map['seen_at'] = Variable<DateTime>(seenAt);
    return map;
  }

  SyncSnapshotsCompanion toCompanion(bool nullToAbsent) {
    return SyncSnapshotsCompanion(bookId: Value(bookId), seenAt: Value(seenAt));
  }

  factory SyncSnapshot.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SyncSnapshot(
      bookId: serializer.fromJson<String>(json['bookId']),
      seenAt: serializer.fromJson<DateTime>(json['seenAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'bookId': serializer.toJson<String>(bookId),
      'seenAt': serializer.toJson<DateTime>(seenAt),
    };
  }

  SyncSnapshot copyWith({String? bookId, DateTime? seenAt}) => SyncSnapshot(
    bookId: bookId ?? this.bookId,
    seenAt: seenAt ?? this.seenAt,
  );
  SyncSnapshot copyWithCompanion(SyncSnapshotsCompanion data) {
    return SyncSnapshot(
      bookId: data.bookId.present ? data.bookId.value : this.bookId,
      seenAt: data.seenAt.present ? data.seenAt.value : this.seenAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SyncSnapshot(')
          ..write('bookId: $bookId, ')
          ..write('seenAt: $seenAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(bookId, seenAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SyncSnapshot &&
          other.bookId == this.bookId &&
          other.seenAt == this.seenAt);
}

class SyncSnapshotsCompanion extends UpdateCompanion<SyncSnapshot> {
  final Value<String> bookId;
  final Value<DateTime> seenAt;
  final Value<int> rowid;
  const SyncSnapshotsCompanion({
    this.bookId = const Value.absent(),
    this.seenAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SyncSnapshotsCompanion.insert({
    required String bookId,
    required DateTime seenAt,
    this.rowid = const Value.absent(),
  }) : bookId = Value(bookId),
       seenAt = Value(seenAt);
  static Insertable<SyncSnapshot> custom({
    Expression<String>? bookId,
    Expression<DateTime>? seenAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (bookId != null) 'book_id': bookId,
      if (seenAt != null) 'seen_at': seenAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SyncSnapshotsCompanion copyWith({
    Value<String>? bookId,
    Value<DateTime>? seenAt,
    Value<int>? rowid,
  }) {
    return SyncSnapshotsCompanion(
      bookId: bookId ?? this.bookId,
      seenAt: seenAt ?? this.seenAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (bookId.present) {
      map['book_id'] = Variable<String>(bookId.value);
    }
    if (seenAt.present) {
      map['seen_at'] = Variable<DateTime>(seenAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SyncSnapshotsCompanion(')
          ..write('bookId: $bookId, ')
          ..write('seenAt: $seenAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  $AppDatabaseManager get managers => $AppDatabaseManager(this);
  late final $BooksTable books = $BooksTable(this);
  late final $GroupsTable groups = $GroupsTable(this);
  late final $ProgressEntriesTable progressEntries = $ProgressEntriesTable(
    this,
  );
  late final $SyncSnapshotsTable syncSnapshots = $SyncSnapshotsTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    books,
    groups,
    progressEntries,
    syncSnapshots,
  ];
}

typedef $$BooksTableCreateCompanionBuilder = BooksCompanion Function({
  required String id,
  required String title,
  required String entryUrl,
  required String scopePrefix,
  Value<String?> iconUrl,
  Value<int?> themeColor,
  Value<String?> groupId,
  Value<int> sortIndex,
  Value<String?> presetId,
  required DateTime createdAt,
  required DateTime updatedAt,
  Value<DateTime?> deletedAt,
  Value<int> rowid,
});
typedef $$BooksTableUpdateCompanionBuilder = BooksCompanion Function({
  Value<String> id,
  Value<String> title,
  Value<String> entryUrl,
  Value<String> scopePrefix,
  Value<String?> iconUrl,
  Value<int?> themeColor,
  Value<String?> groupId,
  Value<int> sortIndex,
  Value<String?> presetId,
  Value<DateTime> createdAt,
  Value<DateTime> updatedAt,
  Value<DateTime?> deletedAt,
  Value<int> rowid,
});

class $$BooksTableFilterComposer extends Composer<_$AppDatabase, $BooksTable> {
  $$BooksTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get entryUrl => $composableBuilder(
    column: $table.entryUrl,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get scopePrefix => $composableBuilder(
    column: $table.scopePrefix,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get iconUrl => $composableBuilder(
    column: $table.iconUrl,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get themeColor => $composableBuilder(
    column: $table.themeColor,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get groupId => $composableBuilder(
    column: $table.groupId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get sortIndex => $composableBuilder(
    column: $table.sortIndex,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get presetId => $composableBuilder(
    column: $table.presetId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$BooksTableOrderingComposer
    extends Composer<_$AppDatabase, $BooksTable> {
  $$BooksTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get entryUrl => $composableBuilder(
    column: $table.entryUrl,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get scopePrefix => $composableBuilder(
    column: $table.scopePrefix,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get iconUrl => $composableBuilder(
    column: $table.iconUrl,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get themeColor => $composableBuilder(
    column: $table.themeColor,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get groupId => $composableBuilder(
    column: $table.groupId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get sortIndex => $composableBuilder(
    column: $table.sortIndex,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get presetId => $composableBuilder(
    column: $table.presetId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$BooksTableAnnotationComposer
    extends Composer<_$AppDatabase, $BooksTable> {
  $$BooksTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get title =>
      $composableBuilder(column: $table.title, builder: (column) => column);

  GeneratedColumn<String> get entryUrl =>
      $composableBuilder(column: $table.entryUrl, builder: (column) => column);

  GeneratedColumn<String> get scopePrefix => $composableBuilder(
    column: $table.scopePrefix,
    builder: (column) => column,
  );

  GeneratedColumn<String> get iconUrl =>
      $composableBuilder(column: $table.iconUrl, builder: (column) => column);

  GeneratedColumn<int> get themeColor => $composableBuilder(
    column: $table.themeColor,
    builder: (column) => column,
  );

  GeneratedColumn<String> get groupId =>
      $composableBuilder(column: $table.groupId, builder: (column) => column);

  GeneratedColumn<int> get sortIndex =>
      $composableBuilder(column: $table.sortIndex, builder: (column) => column);

  GeneratedColumn<String> get presetId =>
      $composableBuilder(column: $table.presetId, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<DateTime> get deletedAt =>
      $composableBuilder(column: $table.deletedAt, builder: (column) => column);
}

class $$BooksTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $BooksTable,
          BookRow,
          $$BooksTableFilterComposer,
          $$BooksTableOrderingComposer,
          $$BooksTableAnnotationComposer,
          $$BooksTableCreateCompanionBuilder,
          $$BooksTableUpdateCompanionBuilder,
          (BookRow, BaseReferences<_$AppDatabase, $BooksTable, BookRow>),
          BookRow,
          PrefetchHooks Function()
        > {
  $$BooksTableTableManager(_$AppDatabase db, $BooksTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$BooksTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$BooksTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$BooksTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> title = const Value.absent(),
                Value<String> entryUrl = const Value.absent(),
                Value<String> scopePrefix = const Value.absent(),
                Value<String?> iconUrl = const Value.absent(),
                Value<int?> themeColor = const Value.absent(),
                Value<String?> groupId = const Value.absent(),
                Value<int> sortIndex = const Value.absent(),
                Value<String?> presetId = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<DateTime?> deletedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => BooksCompanion(
                id: id,
                title: title,
                entryUrl: entryUrl,
                scopePrefix: scopePrefix,
                iconUrl: iconUrl,
                themeColor: themeColor,
                groupId: groupId,
                sortIndex: sortIndex,
                presetId: presetId,
                createdAt: createdAt,
                updatedAt: updatedAt,
                deletedAt: deletedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String title,
                required String entryUrl,
                required String scopePrefix,
                Value<String?> iconUrl = const Value.absent(),
                Value<int?> themeColor = const Value.absent(),
                Value<String?> groupId = const Value.absent(),
                Value<int> sortIndex = const Value.absent(),
                Value<String?> presetId = const Value.absent(),
                required DateTime createdAt,
                required DateTime updatedAt,
                Value<DateTime?> deletedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => BooksCompanion.insert(
                id: id,
                title: title,
                entryUrl: entryUrl,
                scopePrefix: scopePrefix,
                iconUrl: iconUrl,
                themeColor: themeColor,
                groupId: groupId,
                sortIndex: sortIndex,
                presetId: presetId,
                createdAt: createdAt,
                updatedAt: updatedAt,
                deletedAt: deletedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$BooksTable, BookRow>(table),
                  BaseReferences<_$AppDatabase, $BooksTable, BookRow>(
                    db,
                    table,
                    e,
                  ),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$BooksTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $BooksTable,
      BookRow,
      $$BooksTableFilterComposer,
      $$BooksTableOrderingComposer,
      $$BooksTableAnnotationComposer,
      $$BooksTableCreateCompanionBuilder,
      $$BooksTableUpdateCompanionBuilder,
      (BookRow, BaseReferences<_$AppDatabase, $BooksTable, BookRow>),
      BookRow,
      PrefetchHooks Function()
    >;
typedef $$GroupsTableCreateCompanionBuilder = GroupsCompanion Function({
  required String id,
  required String name,
  Value<int> sortIndex,
  required DateTime updatedAt,
  Value<DateTime?> deletedAt,
  Value<int> rowid,
});
typedef $$GroupsTableUpdateCompanionBuilder = GroupsCompanion Function({
  Value<String> id,
  Value<String> name,
  Value<int> sortIndex,
  Value<DateTime> updatedAt,
  Value<DateTime?> deletedAt,
  Value<int> rowid,
});

class $$GroupsTableFilterComposer
    extends Composer<_$AppDatabase, $GroupsTable> {
  $$GroupsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get sortIndex => $composableBuilder(
    column: $table.sortIndex,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$GroupsTableOrderingComposer
    extends Composer<_$AppDatabase, $GroupsTable> {
  $$GroupsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get sortIndex => $composableBuilder(
    column: $table.sortIndex,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$GroupsTableAnnotationComposer
    extends Composer<_$AppDatabase, $GroupsTable> {
  $$GroupsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<int> get sortIndex =>
      $composableBuilder(column: $table.sortIndex, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<DateTime> get deletedAt =>
      $composableBuilder(column: $table.deletedAt, builder: (column) => column);
}

class $$GroupsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $GroupsTable,
          GroupRow,
          $$GroupsTableFilterComposer,
          $$GroupsTableOrderingComposer,
          $$GroupsTableAnnotationComposer,
          $$GroupsTableCreateCompanionBuilder,
          $$GroupsTableUpdateCompanionBuilder,
          (GroupRow, BaseReferences<_$AppDatabase, $GroupsTable, GroupRow>),
          GroupRow,
          PrefetchHooks Function()
        > {
  $$GroupsTableTableManager(_$AppDatabase db, $GroupsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$GroupsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$GroupsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$GroupsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<int> sortIndex = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<DateTime?> deletedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => GroupsCompanion(
                id: id,
                name: name,
                sortIndex: sortIndex,
                updatedAt: updatedAt,
                deletedAt: deletedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String name,
                Value<int> sortIndex = const Value.absent(),
                required DateTime updatedAt,
                Value<DateTime?> deletedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => GroupsCompanion.insert(
                id: id,
                name: name,
                sortIndex: sortIndex,
                updatedAt: updatedAt,
                deletedAt: deletedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$GroupsTable, GroupRow>(table),
                  BaseReferences<_$AppDatabase, $GroupsTable, GroupRow>(
                    db,
                    table,
                    e,
                  ),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$GroupsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $GroupsTable,
      GroupRow,
      $$GroupsTableFilterComposer,
      $$GroupsTableOrderingComposer,
      $$GroupsTableAnnotationComposer,
      $$GroupsTableCreateCompanionBuilder,
      $$GroupsTableUpdateCompanionBuilder,
      (GroupRow, BaseReferences<_$AppDatabase, $GroupsTable, GroupRow>),
      GroupRow,
      PrefetchHooks Function()
    >;
typedef $$ProgressEntriesTableCreateCompanionBuilder =
    ProgressEntriesCompanion Function({
      required String bookId,
      required String url,
      Value<String> pageTitle,
      Value<String?> pageHash,
      Value<String?> anchorJson,
      required DateTime updatedAt,
      Value<String> deviceId,
      Value<int> rowid,
    });
typedef $$ProgressEntriesTableUpdateCompanionBuilder =
    ProgressEntriesCompanion Function({
      Value<String> bookId,
      Value<String> url,
      Value<String> pageTitle,
      Value<String?> pageHash,
      Value<String?> anchorJson,
      Value<DateTime> updatedAt,
      Value<String> deviceId,
      Value<int> rowid,
    });

class $$ProgressEntriesTableFilterComposer
    extends Composer<_$AppDatabase, $ProgressEntriesTable> {
  $$ProgressEntriesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get bookId => $composableBuilder(
    column: $table.bookId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get url => $composableBuilder(
    column: $table.url,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get pageTitle => $composableBuilder(
    column: $table.pageTitle,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get pageHash => $composableBuilder(
    column: $table.pageHash,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get anchorJson => $composableBuilder(
    column: $table.anchorJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get deviceId => $composableBuilder(
    column: $table.deviceId,
    builder: (column) => ColumnFilters(column),
  );
}

class $$ProgressEntriesTableOrderingComposer
    extends Composer<_$AppDatabase, $ProgressEntriesTable> {
  $$ProgressEntriesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get bookId => $composableBuilder(
    column: $table.bookId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get url => $composableBuilder(
    column: $table.url,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get pageTitle => $composableBuilder(
    column: $table.pageTitle,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get pageHash => $composableBuilder(
    column: $table.pageHash,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get anchorJson => $composableBuilder(
    column: $table.anchorJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get deviceId => $composableBuilder(
    column: $table.deviceId,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$ProgressEntriesTableAnnotationComposer
    extends Composer<_$AppDatabase, $ProgressEntriesTable> {
  $$ProgressEntriesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get bookId =>
      $composableBuilder(column: $table.bookId, builder: (column) => column);

  GeneratedColumn<String> get url =>
      $composableBuilder(column: $table.url, builder: (column) => column);

  GeneratedColumn<String> get pageTitle =>
      $composableBuilder(column: $table.pageTitle, builder: (column) => column);

  GeneratedColumn<String> get pageHash =>
      $composableBuilder(column: $table.pageHash, builder: (column) => column);

  GeneratedColumn<String> get anchorJson => $composableBuilder(
    column: $table.anchorJson,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<String> get deviceId =>
      $composableBuilder(column: $table.deviceId, builder: (column) => column);
}

class $$ProgressEntriesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $ProgressEntriesTable,
          ProgressRow,
          $$ProgressEntriesTableFilterComposer,
          $$ProgressEntriesTableOrderingComposer,
          $$ProgressEntriesTableAnnotationComposer,
          $$ProgressEntriesTableCreateCompanionBuilder,
          $$ProgressEntriesTableUpdateCompanionBuilder,
          (
            ProgressRow,
            BaseReferences<_$AppDatabase, $ProgressEntriesTable, ProgressRow>,
          ),
          ProgressRow,
          PrefetchHooks Function()
        > {
  $$ProgressEntriesTableTableManager(
    _$AppDatabase db,
    $ProgressEntriesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ProgressEntriesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ProgressEntriesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ProgressEntriesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> bookId = const Value.absent(),
                Value<String> url = const Value.absent(),
                Value<String> pageTitle = const Value.absent(),
                Value<String?> pageHash = const Value.absent(),
                Value<String?> anchorJson = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<String> deviceId = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ProgressEntriesCompanion(
                bookId: bookId,
                url: url,
                pageTitle: pageTitle,
                pageHash: pageHash,
                anchorJson: anchorJson,
                updatedAt: updatedAt,
                deviceId: deviceId,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String bookId,
                required String url,
                Value<String> pageTitle = const Value.absent(),
                Value<String?> pageHash = const Value.absent(),
                Value<String?> anchorJson = const Value.absent(),
                required DateTime updatedAt,
                Value<String> deviceId = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ProgressEntriesCompanion.insert(
                bookId: bookId,
                url: url,
                pageTitle: pageTitle,
                pageHash: pageHash,
                anchorJson: anchorJson,
                updatedAt: updatedAt,
                deviceId: deviceId,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$ProgressEntriesTable, ProgressRow>(table),
                  BaseReferences<
                    _$AppDatabase,
                    $ProgressEntriesTable,
                    ProgressRow
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$ProgressEntriesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $ProgressEntriesTable,
      ProgressRow,
      $$ProgressEntriesTableFilterComposer,
      $$ProgressEntriesTableOrderingComposer,
      $$ProgressEntriesTableAnnotationComposer,
      $$ProgressEntriesTableCreateCompanionBuilder,
      $$ProgressEntriesTableUpdateCompanionBuilder,
      (
        ProgressRow,
        BaseReferences<_$AppDatabase, $ProgressEntriesTable, ProgressRow>,
      ),
      ProgressRow,
      PrefetchHooks Function()
    >;
typedef $$SyncSnapshotsTableCreateCompanionBuilder =
    SyncSnapshotsCompanion Function({
      required String bookId,
      required DateTime seenAt,
      Value<int> rowid,
    });
typedef $$SyncSnapshotsTableUpdateCompanionBuilder =
    SyncSnapshotsCompanion Function({
      Value<String> bookId,
      Value<DateTime> seenAt,
      Value<int> rowid,
    });

class $$SyncSnapshotsTableFilterComposer
    extends Composer<_$AppDatabase, $SyncSnapshotsTable> {
  $$SyncSnapshotsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get bookId => $composableBuilder(
    column: $table.bookId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get seenAt => $composableBuilder(
    column: $table.seenAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$SyncSnapshotsTableOrderingComposer
    extends Composer<_$AppDatabase, $SyncSnapshotsTable> {
  $$SyncSnapshotsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get bookId => $composableBuilder(
    column: $table.bookId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get seenAt => $composableBuilder(
    column: $table.seenAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$SyncSnapshotsTableAnnotationComposer
    extends Composer<_$AppDatabase, $SyncSnapshotsTable> {
  $$SyncSnapshotsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get bookId =>
      $composableBuilder(column: $table.bookId, builder: (column) => column);

  GeneratedColumn<DateTime> get seenAt =>
      $composableBuilder(column: $table.seenAt, builder: (column) => column);
}

class $$SyncSnapshotsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $SyncSnapshotsTable,
          SyncSnapshot,
          $$SyncSnapshotsTableFilterComposer,
          $$SyncSnapshotsTableOrderingComposer,
          $$SyncSnapshotsTableAnnotationComposer,
          $$SyncSnapshotsTableCreateCompanionBuilder,
          $$SyncSnapshotsTableUpdateCompanionBuilder,
          (
            SyncSnapshot,
            BaseReferences<_$AppDatabase, $SyncSnapshotsTable, SyncSnapshot>,
          ),
          SyncSnapshot,
          PrefetchHooks Function()
        > {
  $$SyncSnapshotsTableTableManager(_$AppDatabase db, $SyncSnapshotsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SyncSnapshotsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SyncSnapshotsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SyncSnapshotsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> bookId = const Value.absent(),
                Value<DateTime> seenAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SyncSnapshotsCompanion(
                bookId: bookId,
                seenAt: seenAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String bookId,
                required DateTime seenAt,
                Value<int> rowid = const Value.absent(),
              }) => SyncSnapshotsCompanion.insert(
                bookId: bookId,
                seenAt: seenAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$SyncSnapshotsTable, SyncSnapshot>(table),
                  BaseReferences<
                    _$AppDatabase,
                    $SyncSnapshotsTable,
                    SyncSnapshot
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$SyncSnapshotsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $SyncSnapshotsTable,
      SyncSnapshot,
      $$SyncSnapshotsTableFilterComposer,
      $$SyncSnapshotsTableOrderingComposer,
      $$SyncSnapshotsTableAnnotationComposer,
      $$SyncSnapshotsTableCreateCompanionBuilder,
      $$SyncSnapshotsTableUpdateCompanionBuilder,
      (
        SyncSnapshot,
        BaseReferences<_$AppDatabase, $SyncSnapshotsTable, SyncSnapshot>,
      ),
      SyncSnapshot,
      PrefetchHooks Function()
    >;

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $$BooksTableTableManager get books =>
      $$BooksTableTableManager(_db, _db.books);
  $$GroupsTableTableManager get groups =>
      $$GroupsTableTableManager(_db, _db.groups);
  $$ProgressEntriesTableTableManager get progressEntries =>
      $$ProgressEntriesTableTableManager(_db, _db.progressEntries);
  $$SyncSnapshotsTableTableManager get syncSnapshots =>
      $$SyncSnapshotsTableTableManager(_db, _db.syncSnapshots);
}

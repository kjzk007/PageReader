import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

part 'app_database.g.dart';

/// 书:一本书 = 一个路径前缀。删除用墓碑,同步时才不会把它复活。
@DataClassName('BookRow')
class Books extends Table {
  TextColumn get id => text()();
  TextColumn get title => text()();
  TextColumn get entryUrl => text()();
  TextColumn get scopePrefix => text()();
  TextColumn get iconUrl => text().nullable()();
  IntColumn get themeColor => integer().nullable()();
  TextColumn get groupId => text().nullable()();
  IntColumn get sortIndex => integer().withDefault(const Constant(0))();

  /// 这本书打开时使用的深色注入预设 id。
  ///
  /// null 表示「默认」—— 不注入任何样式，网页原样显示。
  TextColumn get presetId => text().nullable()();

  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  DateTimeColumn get deletedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// 分组:单层,parentId 暂不启用。
@DataClassName('GroupRow')
class Groups extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  IntColumn get sortIndex => integer().withDefault(const Constant(0))();
  DateTimeColumn get updatedAt => dateTime()();
  DateTimeColumn get deletedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// 进度:主键 (bookId, url),一页一条。
/// url 已归一化(去 fragment),pageHash 单独存,用于回到页内小节。
@DataClassName('ProgressRow')
class ProgressEntries extends Table {
  TextColumn get bookId => text()();
  TextColumn get url => text()();
  TextColumn get pageTitle => text().withDefault(const Constant(''))();
  TextColumn get pageHash => text().nullable()();
  TextColumn get anchorJson => text().nullable()();
  DateTimeColumn get updatedAt => dateTime()();
  TextColumn get deviceId => text().withDefault(const Constant('local'))();

  @override
  Set<Column> get primaryKey => {bookId, url};
}

/// 上次同步时的书架快照。
///
/// 为什么需要这张表:
/// 「一端把书删了」和「一端从来没有这本书」在数据上完全一样 ——
/// 都是"对端清单里没有这本书"。没有历史就无法区分。
///
/// 有了快照:
///   * 快照里有、现在没有 → 这本书是**被删的**,删除应该传播
///   * 快照里没有、现在也没有 → 本来就没有,不是删除
///
/// 这张表只在同步成功后写入(记录当时的完整清单),
/// 平时不参与任何业务逻辑。
class SyncSnapshots extends Table {
  /// 快照里记录的书 ID。
  TextColumn get bookId => text()();

  /// 上次同步时这本书是否存在(含墓碑时仍为 true)。
  ///
  /// 目前只用存在性,但保留时间戳便于将来做更细的判定。
  DateTimeColumn get seenAt => dateTime()();

  @override
  Set<Column> get primaryKey => {bookId};
}

@DriftDatabase(tables: [Books, Groups, ProgressEntries, SyncSnapshots])
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.e);

  /// 打开本地库。位置由 path_provider 决定:Windows 在 AppData,Android 在应用私有目录。
  AppDatabase.open() : super(_openConnection());

  /// 测试用:内存库,不落盘。
  AppDatabase.memory() : super(NativeDatabase.memory());

  @override
  int get schemaVersion => 3;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) async {
      await m.createAll();
    },
    // v1 → v2:新增同步快照表。
    //
    // 老库升级时这张表是空的。第一次同步会把它填上(记录当时的清单),
    // 从那之后的删除才能被正确判定。升级前的历史删除无法追溯 ——
    // 那些书本来就没有墓碑,也不会被误判。
    //
    // v2 → v3:书可以绑定深色注入预设。
    // 老书全部为 null,即「默认」不注入,行为和升级前一致。
    onUpgrade: (m, from, to) async {
      if (from < 2) {
        await m.createTable(syncSnapshots);
      }
      if (from < 3) {
        await m.addColumn(books, books.presetId);
      }
    },
  );

  static LazyDatabase _openConnection() {
    return LazyDatabase(() async {
      // 允许用环境变量重定向数据目录。
      //
      // 唯一的用途是验收脚本:它需要在一个隔离的沙箱里跑,
      // 绝不能碰用户真实的书架数据。
      // 之前验收脚本直接删 %APPDATA% 下的库,把用户手动添加的书
      // 全清空了 —— 开发工具污染产品数据,不可接受。
      final override = Platform.environment['PAGEREADER_DATA_DIR'];
      final dir = override != null && override.trim().isNotEmpty
          ? Directory(override.trim())
          : await getApplicationSupportDirectory();
      if (!dir.existsSync()) dir.createSync(recursive: true);
      final file = File(p.join(dir.path, 'pagereader.sqlite'));
      return NativeDatabase.createInBackground(file);
    });
  }
}
import 'dart:convert';

import 'package:drift/drift.dart';

import '../../core/domain/models.dart';
import '../../core/ports/ports.dart';
import 'db/app_database.dart';

/// LibraryStore 的 SQLite 实现。UI 与 service 层只认接口,换实现不动它们。
class SqliteLibraryStore implements LibraryStore {
  SqliteLibraryStore(this._db);

  final AppDatabase _db;

  @override
  Future<List<BookGroup>> loadGroups() async {
    final rows = await (_db.select(_db.groups)
          ..where((g) => g.deletedAt.isNull())
          ..orderBy([(g) => OrderingTerm.asc(g.sortIndex)]))
        .get();
    return rows
        .map(
          (row) => BookGroup(
            id: row.id,
            name: row.name,
            sortIndex: row.sortIndex,
            updatedAt: row.updatedAt,
            deletedAt: row.deletedAt,
          ),
        )
        .toList();
  }

  @override
  Future<List<Book>> loadBooks() async {
    final rows = await (_db.select(_db.books)
          ..where((b) => b.deletedAt.isNull())
          ..orderBy([(b) => OrderingTerm.asc(b.sortIndex)]))
        .get();
    return rows.map(_toBook).toList();
  }

  /// 含墓碑的书列表。同步专用。
  ///
  /// 与 loadBooks 的区别只有一个:不过滤 deletedAt。
  /// 同步必须看到墓碑,否则"删除"这个动作永远传不到另一端。
  @override
  Future<List<Book>> loadBooksIncludingDeleted() async {
    final rows = await (_db.select(
      _db.books,
    )..orderBy([(b) => OrderingTerm.asc(b.sortIndex)])).get();
    return rows.map(_toBook).toList();
  }

  @override
  Future<int> nextSortIndex() async {
    final rows = await (_db.select(_db.books)
          ..where((b) => b.deletedAt.isNull()))
        .get();
    if (rows.isEmpty) return 0;
    var max = 0;
    for (final r in rows) {
      if (r.sortIndex > max) max = r.sortIndex;
    }
    return max + 1;
  }

  // ---------------------------------------------------------------- 分组

  @override
  Future<void> upsertGroup(BookGroup group) async {
    await _db
        .into(_db.groups)
        .insertOnConflictUpdate(
          GroupsCompanion.insert(
            id: group.id,
            name: group.name,
            sortIndex: Value(group.sortIndex),
            updatedAt: group.updatedAt,
            deletedAt: Value(group.deletedAt),
          ),
        );
  }

  /// 删组只解散:把组内的书置为未分组,书本身不动、进度也不动。
  @override
  Future<void> deleteGroup(String groupId) async {
    await (_db.update(_db.books)..where((b) => b.groupId.equals(groupId)))
        .write(const BooksCompanion(groupId: Value(null)));
    await (_db.update(_db.groups)..where((g) => g.id.equals(groupId))).write(
      GroupsCompanion(deletedAt: Value(DateTime.now())),
    );
  }

  @override
  Future<void> upsertBook(Book book) async {
    await _db
        .into(_db.books)
        .insertOnConflictUpdate(
          BooksCompanion.insert(
            id: book.id,
            title: book.title,
            entryUrl: book.entryUrl,
            scopePrefix: book.scopePrefix,
            iconUrl: Value(book.iconUrl),
            themeColor: Value(book.themeColor),
            groupId: Value(book.groupId),
            sortIndex: Value(book.sortIndex),
            createdAt: book.createdAt,
            updatedAt: book.updatedAt,
            deletedAt: Value(book.deletedAt),
          ),
        );
  }

  @override
  Future<void> deleteBook(String bookId) async {
    // 软删书本身:留墓碑,避免同步把已删的书又推回来。
    await (_db.update(_db.books)..where((b) => b.id.equals(bookId))).write(
      BooksCompanion(deletedAt: Value(DateTime.now())),
    );
    // 进度是硬删。
    //
    // 为什么两种处理不同:
    //   * 书的墓碑需要留下 —— 它是"这本书被删了"这个事实,要传给另一端;
    //   * 进度没有传播的价值 —— 书都没了,进度留着只会被同步到处传,
    //     让数据库越积越大,而且万一同名书被重新添加会读到脏数据。
    await deleteProgressOf(bookId);
  }

  @override
  Future<void> deleteProgressOf(String bookId) async {
    await (_db.delete(
      _db.progressEntries,
    )..where((p) => p.bookId.equals(bookId))).go();
  }

  // ---------------------------------------------------------------- 同步快照

  /// 读上次同步时的书架快照(书 ID 集合)。
  ///
  /// 用途:区分「这本书被删了」和「这本书从来不存在」。
  /// 快照里有、现在没有 → 删了;快照里也没有 → 本来就没有。
  @override
  Future<Set<String>> loadSyncSnapshot() async {
    final rows = await _db.select(_db.syncSnapshots).get();
    return rows.map((r) => r.bookId).toSet();
  }

  /// 保存本次同步后的书架快照。
  ///
  /// 整表替换:快照反映的是"同步那一刻的完整状态",
  /// 增量更新容易残留已消失的书,导致下次误判为删除。
  @override
  Future<void> saveSyncSnapshot(Set<String> bookIds) async {
    await _db.transaction(() async {
      await _db.delete(_db.syncSnapshots).go();
      await _db.batch((b) {
        for (final id in bookIds) {
          b.insert(
            _db.syncSnapshots,
            SyncSnapshotsCompanion.insert(
              bookId: id,
              seenAt: DateTime.now(),
            ),
          );
        }
      });
    });
  }

  @override
  Future<ProgressSnapshot?> latestProgress(String bookId) async {
    final row =
        await (_db.select(_db.progressEntries)
              ..where((p) => p.bookId.equals(bookId))
              ..orderBy([(p) => OrderingTerm.desc(p.updatedAt)])
              ..limit(1))
            .getSingleOrNull();
    return row == null ? null : _toSnapshot(row);
  }

  @override
  Future<void> saveProgress(ProgressSnapshot snapshot) async {
    await _db
        .into(_db.progressEntries)
        .insertOnConflictUpdate(
          ProgressEntriesCompanion.insert(
            bookId: snapshot.bookId,
            url: snapshot.url,
            pageTitle: Value(snapshot.pageTitle),
            pageHash: Value(snapshot.pageHash),
            anchorJson: Value(
              snapshot.anchor == null ? null : jsonEncode(snapshot.anchor!.toJson()),
            ),
            updatedAt: snapshot.updatedAt,
            deviceId: Value(snapshot.deviceId),
          ),
        );
  }

  @override
  Future<List<ProgressSnapshot>> recentProgress({int limit = 20}) async {
    final rows = await (_db.select(_db.progressEntries)
          ..orderBy([(p) => OrderingTerm.desc(p.updatedAt)])
          ..limit(limit))
        .get();
    return rows.map(_toSnapshot).toList();
  }

  /// 书架首屏用:一次查询拿到"每本书的最新一条进度",避免 N+1。
  @override
  Future<Map<String, ProgressSnapshot>> latestProgressByBook() async {
    final rows = await (_db.select(_db.progressEntries)
          ..orderBy([(p) => OrderingTerm.desc(p.updatedAt)]))
        .get();
    final result = <String, ProgressSnapshot>{};
    for (final row in rows) {
      result.putIfAbsent(row.bookId, () => _toSnapshot(row));
    }
    return result;
  }

  Book _toBook(BookRow row) => Book(
    id: row.id,
    title: row.title,
    entryUrl: row.entryUrl,
    scopePrefix: row.scopePrefix,
    iconUrl: row.iconUrl,
    themeColor: row.themeColor,
    groupId: row.groupId,
    sortIndex: row.sortIndex,
    createdAt: row.createdAt,
    updatedAt: row.updatedAt,
    deletedAt: row.deletedAt,
  );

  ProgressSnapshot _toSnapshot(ProgressRow row) => ProgressSnapshot(
    bookId: row.bookId,
    url: row.url,
    pageTitle: row.pageTitle,
    pageHash: row.pageHash,
    anchor: Anchor.fromJson(
      row.anchorJson == null
          ? null
          : jsonDecode(row.anchorJson!) as Map<String, Object?>,
    ),
    updatedAt: row.updatedAt,
    deviceId: row.deviceId,
  );
}
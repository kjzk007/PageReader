import 'package:flutter_test/flutter_test.dart';
import 'package:pagereader/core/domain/models.dart';
import 'package:pagereader/data/db/app_database.dart';
import 'package:pagereader/data/sqlite_library_store.dart';

/// 真库测试:用内存 SQLite,不落盘、不联网。
/// 覆盖分组管理、排序去重、墓碑语义这些"只写了代码没验证过"的部分。
void main() {
  late AppDatabase db;
  late SqliteLibraryStore store;

  setUp(() {
    db = AppDatabase.memory();
    store = SqliteLibraryStore(db);
  });

  tearDown(() async {
    await db.close();
  });

  Book book(String id, {String? group, int sort = 0, DateTime? at}) {
    final now = at ?? DateTime(2026, 1, 1);
    return Book(
      id: id,
      title: '书 $id',
      entryUrl: 'https://a.dev/$id',
      scopePrefix: 'https://a.dev/$id',
      groupId: group,
      sortIndex: sort,
      createdAt: now,
      updatedAt: now,
    );
  }

  group('分组管理', () {
    test('新建后能读到', () async {
      await store.upsertGroup(
        BookGroup(
          id: 'g1',
          name: '前端',
          sortIndex: 0,
          updatedAt: DateTime(2026, 1, 1),
        ),
      );
      final groups = await store.loadGroups();
      expect(groups.length, 1);
      expect(groups.first.name, '前端');
    });

    test('改名保留同一个 id', () async {
      await store.upsertGroup(
        BookGroup(
          id: 'g1',
          name: '旧名',
          sortIndex: 0,
          updatedAt: DateTime(2026, 1, 1),
        ),
      );
      await store.upsertGroup(
        BookGroup(
          id: 'g1',
          name: '新名',
          sortIndex: 0,
          updatedAt: DateTime(2026, 1, 2),
        ),
      );
      final groups = await store.loadGroups();
      expect(groups.length, 1);
      expect(groups.first.name, '新名');
    });

    test('删除分组只解散:书转为未分组,书本身不删', () async {
      await store.upsertGroup(
        BookGroup(
          id: 'g1',
          name: '前端',
          sortIndex: 0,
          updatedAt: DateTime(2026, 1, 1),
        ),
      );
      await store.upsertBook(book('b1', group: 'g1'));
      await store.upsertBook(book('b2', group: 'g1'));

      await store.deleteGroup('g1');

      final groups = await store.loadGroups();
      expect(groups, isEmpty, reason: '分组应已删除');
      final books = await store.loadBooks();
      expect(books.length, 2, reason: '书不能被连带删掉');
      expect(books.every((b) => b.groupId == null), isTrue, reason: '书应转为未分组');
    });

    test('删除分组不影响进度', () async {
      await store.upsertGroup(
        BookGroup(
          id: 'g1',
          name: '前端',
          sortIndex: 0,
          updatedAt: DateTime(2026, 1, 1),
        ),
      );
      await store.upsertBook(book('b1', group: 'g1'));
      await store.saveProgress(
        ProgressSnapshot(
          bookId: 'b1',
          url: 'https://a.dev/b1/x',
          pageTitle: '页面',
          updatedAt: DateTime(2026, 1, 5),
          deviceId: 'test',
        ),
      );

      await store.deleteGroup('g1');

      final p = await store.latestProgress('b1');
      expect(p, isNotNull, reason: '删分组不该动进度');
    });
  });

  group('排序序号', () {
    test('空库从 0 开始', () async {
      expect(await store.nextSortIndex(), 0);
    });

    test('追加时取最大值 +1,而不是当前数量', () async {
      await store.upsertBook(book('b1', sort: 0));
      await store.upsertBook(book('b2', sort: 1));
      await store.upsertBook(book('b3', sort: 2));
      expect(await store.nextSortIndex(), 3);

      // 删掉中间一本:数量变成 2,但最大序号仍是 2。
      await store.deleteBook('b2');
      expect(
        await store.nextSortIndex(),
        3,
        reason: '用数量当序号会算出 2,和已有记录撞号',
      );
    });

    test('删除后的书不参与序号计算', () async {
      await store.upsertBook(book('b1', sort: 0));
      await store.upsertBook(book('b2', sort: 9));
      await store.deleteBook('b2');
      expect(await store.nextSortIndex(), 1);
    });
  });

  group('书的删除', () {
    test('软删:留墓碑,不出现在列表里', () async {
      await store.upsertBook(book('b1'));
      await store.deleteBook('b1');
      expect(await store.loadBooks(), isEmpty);

      // 墓碑还在,再次 upsert 同 id 应恢复
      await store.upsertBook(book('b1'));
      expect((await store.loadBooks()).length, 1);
    });
  });

  group('进度', () {
    test('同页覆盖写,不产生多条', () async {
      final url = 'https://a.dev/b1/page';
      await store.saveProgress(
        ProgressSnapshot(
          bookId: 'b1',
          url: url,
          pageTitle: '第一次',
          updatedAt: DateTime(2026, 1, 1),
          deviceId: 'test',
        ),
      );
      await store.saveProgress(
        ProgressSnapshot(
          bookId: 'b1',
          url: url,
          pageTitle: '第二次',
          updatedAt: DateTime(2026, 1, 2),
          deviceId: 'test',
        ),
      );
      final p = await store.latestProgress('b1');
      expect(p?.pageTitle, '第二次');
      final all = await store.recentProgress();
      expect(all.length, 1, reason: '主键是 (bookId,url),应覆盖而非追加');
    });

    test('latestProgressByBook 每本只取最新一条', () async {
      await store.saveProgress(
        ProgressSnapshot(
          bookId: 'b1',
          url: 'https://a.dev/b1/old',
          pageTitle: 'old',
          updatedAt: DateTime(2026, 1, 1),
          deviceId: 'test',
        ),
      );
      await store.saveProgress(
        ProgressSnapshot(
          bookId: 'b1',
          url: 'https://a.dev/b1/new',
          pageTitle: 'new',
          updatedAt: DateTime(2026, 1, 5),
          deviceId: 'test',
        ),
      );
      await store.saveProgress(
        ProgressSnapshot(
          bookId: 'b2',
          url: 'https://a.dev/b2/x',
          pageTitle: 'b2',
          updatedAt: DateTime(2026, 1, 3),
          deviceId: 'test',
        ),
      );

      final map = await store.latestProgressByBook();
      expect(map.length, 2);
      expect(map['b1']?.pageTitle, 'new');
      expect(map['b2']?.pageTitle, 'b2');
    });

    test('锚点能完整往返', () async {
      const anchor = Anchor(
        cssPath: 'main > p:nth-of-type(3)',
        textFingerprint: '某段文字',
        textLength: 120,
        offsetPx: 47.5,
        docRatio: 0.62,
      );
      await store.saveProgress(
        ProgressSnapshot(
          bookId: 'b1',
          url: 'https://a.dev/b1/page',
          pageTitle: 't',
          anchor: anchor,
          pageHash: '#section-2',
          updatedAt: DateTime(2026, 1, 1),
          deviceId: 'test',
        ),
      );
      final p = await store.latestProgress('b1');
      expect(p?.anchor?.cssPath, anchor.cssPath);
      expect(p?.anchor?.textFingerprint, anchor.textFingerprint);
      expect(p?.anchor?.offsetPx, anchor.offsetPx);
      expect(p?.anchor?.docRatio, anchor.docRatio);
      expect(p?.pageHash, '#section-2');
    });
  });
}

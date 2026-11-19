import 'package:flutter_test/flutter_test.dart';
import 'package:pagereader/core/domain/models.dart';
import 'package:pagereader/core/sync/sync_merger.dart';
import 'package:pagereader/core/sync/sync_protocol.dart';

import 'sync_merger_test.dart' show FakeStore, book, syncBook, syncProgress;

/// 删除同步的测试。
///
/// 三个真实 bug(用户实测发现):
///   1. 书籍不同步 —— 一端的书架有两本,另一端好几本,互相看不到对方的书
///   2. 删了的书还留在另一端 —— 删除永远传不过去
///   3. 删书后进度还在 —— 数据库里留着一堆指向已删书的进度
///
/// 根因都在同一处:同步只导出"活着的书",墓碑(deletedAt)从来没被传出去。
void main() {
  group('删除会传播到对端', () {
    test('对端删了书,本地也会删掉', () async {
      final store = FakeStore(books: [book('a', title: '要删的书')]);
      final merger = SyncMerger(store);

      // 对端传来墓碑:deletedAt 非空
      await merger.merge(
        SyncPayload(
          books: [
            SyncBook(
              id: 'a',
              title: '要删的书',
              entryUrl: 'https://a.dev/docs',
              scopePrefix: 'https://a.dev/docs',
              sortIndex: 0,
              createdAt: DateTime(2025),
              updatedAt: DateTime(2026, 3),
              deletedAt: DateTime(2026, 3),
            ),
          ],
          progress: const [],
        ),
      );

      // 书架上不该再有它
      expect((await store.loadBooks()).where((b) => b.id == 'a'), isEmpty);
      // 但墓碑应该在(防止它被重新推回来)
      final all = await store.loadBooksIncludingDeleted();
      final tomb = all.where((b) => b.id == 'a').firstOrNull;
      expect(tomb, isNotNull, reason: '墓碑必须留下');
      expect(tomb!.deletedAt, isNotNull);
    });

    test('删除时间更晚的赢过本地的"还活着"', () async {
      final store = FakeStore(
        books: [book('a', updatedAt: DateTime(2026, 1))],
      );
      final merger = SyncMerger(store);

      await merger.merge(
        SyncPayload(
          books: [
            SyncBook(
              id: 'a',
              title: 'a',
              entryUrl: 'https://a.dev/docs',
              scopePrefix: 'https://a.dev/docs',
              sortIndex: 0,
              createdAt: DateTime(2025),
              updatedAt: DateTime(2026, 5),
              deletedAt: DateTime(2026, 5),
            ),
          ],
          progress: const [],
        ),
      );

      expect((await store.loadBooks()).where((b) => b.id == 'a'), isEmpty);
    });

    test('本地删得更晚,对端的活书推不回来', () async {
      // 本地在 6 月删了,对端的书最后一次更新在 3 月 —— 删除更新,不该复活
      final store = FakeStore(books: [book('a')]);
      await store.deleteBook('a');
      // 直接把墓碑时间改成 6 月
      final all = await store.loadBooksIncludingDeleted();
      final tomb = all.firstWhere((b) => b.id == 'a');
      expect(tomb.deletedAt, isNotNull);

      final merger = SyncMerger(store);
      await merger.merge(
        SyncPayload(
          books: [
            SyncBook(
              id: 'a',
              title: 'a',
              entryUrl: 'https://a.dev/docs',
              scopePrefix: 'https://a.dev/docs',
              sortIndex: 0,
              createdAt: DateTime(2025),
              updatedAt: DateTime(2020), // 远早于删除时间
              deletedAt: null,
            ),
          ],
          progress: const [],
        ),
      );

      expect(
        (await store.loadBooks()).where((b) => b.id == 'a'),
        isEmpty,
        reason: '本地删除时间晚于对端更新,不该复活',
      );
    });
  });

  group('删书时进度一起清掉', () {
    test('deleteBook 会删掉该书的进度', () async {
      final store = FakeStore(books: [book('a')]);
      await store.saveProgress(
        ProgressSnapshot(
          bookId: 'a',
          url: 'https://a.dev/docs',
          pageTitle: 't',
          updatedAt: DateTime(2026),
          deviceId: 'd',
        ),
      );
      expect(store.progress, hasLength(1));

      await store.deleteBook('a');

      expect(store.progress, isEmpty, reason: '书删了,进度没意义了');
    });

    test('deleteProgressOf 只删指定书的进度', () async {
      final store = FakeStore();
      await store.saveProgress(
        ProgressSnapshot(
          bookId: 'a',
          url: 'u1',
          pageTitle: '',
          updatedAt: DateTime(2026),
          deviceId: 'd',
        ),
      );
      await store.saveProgress(
        ProgressSnapshot(
          bookId: 'b',
          url: 'u2',
          pageTitle: '',
          updatedAt: DateTime(2026),
          deviceId: 'd',
        ),
      );

      await store.deleteProgressOf('a');

      expect(store.progress, hasLength(1));
      expect(store.progress.first.bookId, 'b');
    });

    test('对端传来墓碑时也清本地进度', () async {
      final store = FakeStore(books: [book('a')]);
      await store.saveProgress(
        ProgressSnapshot(
          bookId: 'a',
          url: 'https://a.dev/docs',
          pageTitle: 't',
          updatedAt: DateTime(2026, 1),
          deviceId: 'd',
        ),
      );

      final merger = SyncMerger(store);
      await merger.merge(
        SyncPayload(
          books: [
            SyncBook(
              id: 'a',
              title: 'a',
              entryUrl: 'https://a.dev/docs',
              scopePrefix: 'https://a.dev/docs',
              sortIndex: 0,
              createdAt: DateTime(2025),
              updatedAt: DateTime(2026, 5),
              deletedAt: DateTime(2026, 5),
            ),
          ],
          progress: const [],
        ),
      );

      expect(store.progress, isEmpty);
    });
  });

  group('导出包含墓碑', () {
    test('已删的书会出现在导出里', () async {
      final store = FakeStore(books: [book('a'), book('b')]);
      await store.deleteBook('a');

      final merger = SyncMerger(store);
      final payload = await merger.export();

      final exported = payload.books.map((b) => b.id).toSet();
      expect(
        exported,
        contains('a'),
        reason: '墓碑必须导出,否则删除传不到另一端',
      );
      expect(exported, contains('b'));
    });

    test('已删书的进度不会被导出', () async {
      final store = FakeStore(books: [book('a'), book('b')]);
      await store.saveProgress(
        ProgressSnapshot(
          bookId: 'a',
          url: 'u1',
          pageTitle: '',
          updatedAt: DateTime(2026),
          deviceId: 'd',
        ),
      );
      await store.saveProgress(
        ProgressSnapshot(
          bookId: 'b',
          url: 'u2',
          pageTitle: '',
          updatedAt: DateTime(2026),
          deviceId: 'd',
        ),
      );

      // 删 a —— 它的进度会被 deleteBook 清掉
      await store.deleteBook('a');

      final merger = SyncMerger(store);
      final payload = await merger.export();

      expect(
        payload.progress.where((p) => p.bookId == 'a'),
        isEmpty,
        reason: '书都删了,不该再传它的进度',
      );
    });
  });

  group('新增的书仍能同步', () {
    test('对端新增的书会加到本地', () async {
      final store = FakeStore(books: [book('a')]);
      final merger = SyncMerger(store);

      await merger.merge(
        SyncPayload(
          books: [syncBook('b', title: '新书')],
          progress: [syncProgress('b', 'https://b.dev/docs',
              updatedAt: DateTime(2026))],
        ),
      );

      expect(store.books.map((b) => b.id).toSet(), {'a', 'b'});
      expect(store.progress.where((p) => p.bookId == 'b'), hasLength(1));
    });
  });
}

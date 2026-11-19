import 'package:flutter_test/flutter_test.dart';
import 'package:pagereader/core/domain/models.dart';
import 'package:pagereader/core/sync/sync_mirror.dart';
import 'package:pagereader/core/sync/sync_protocol.dart';

import 'sync_merger_test.dart' show FakeStore, book, syncBook, syncProgress;

/// 同步策略测试：**按操作时间取最新**。
///
/// 不偏向任何一端。逐项比较 updatedAt：
///   * 谁动得更晚，就用谁的状态
///   * 删除也是动作 —— 删得晚的那端赢
///   * 两端最终完全一致
void main() {
  group('按操作时间取最新', () {
    test('对端更新 → 用对端的', () async {
      final local = FakeStore(
        books: [book('a', title: '旧标题', updatedAt: DateTime(2026, 1))],
      );
      final mirror = SyncMirror(local);

      await mirror.merge(
        SyncPayload(
          books: [syncBook('a', title: '新标题', updatedAt: DateTime(2026, 6))],
          progress: const [],
        ),
      );

      final books = await local.loadBooks();
      expect(books.first.title, '新标题');
    });

    test('本地更新 → 保留本地的', () async {
      final local = FakeStore(
        books: [book('a', title: '本地新', updatedAt: DateTime(2026, 6))],
      );
      final mirror = SyncMirror(local);

      await mirror.merge(
        SyncPayload(
          books: [syncBook('a', title: '对端旧', updatedAt: DateTime(2026, 1))],
          progress: const [],
        ),
      );

      expect((await local.loadBooks()).first.title, '本地新');
    });

    test('本地没有 → 从对端加进来', () async {
      final local = FakeStore();
      final mirror = SyncMirror(local);

      await mirror.merge(
        SyncPayload(
          books: [syncBook('a', title: '新书')],
          progress: const [],
        ),
      );

      expect(await local.loadBooks(), hasLength(1));
    });
  });

  group('删除按时间仲裁', () {
    test('对端删得更晚 → 本地也删', () async {
      final local = FakeStore(
        books: [book('a', updatedAt: DateTime(2026, 1))],
      );
      final mirror = SyncMirror(local);

      await mirror.merge(
        SyncPayload(
          books: [
            SyncBook(
              id: 'a',
              title: 'a',
              entryUrl: 'https://a.dev/docs',
              scopePrefix: 'https://a.dev/docs',
              sortIndex: 0,
              createdAt: DateTime(2025),
              updatedAt: DateTime(2026, 6),
              deletedAt: DateTime(2026, 6),
            ),
          ],
          progress: const [],
        ),
      );

      expect(await local.loadBooks(), isEmpty);
    });

    test('本地删得更晚 → 对端的活书推不回来', () async {
      final local = FakeStore(books: [book('a')]);
      await local.deleteBook('a'); // 删除时间 = now(2026-11-19)

      final mirror = SyncMirror(local);
      await mirror.merge(
        SyncPayload(
          books: [syncBook('a', updatedAt: DateTime(2026, 1))],
          progress: const [],
        ),
      );

      expect(
        await local.loadBooks(),
        isEmpty,
        reason: '本地删除时间比对端更新晚,不该复活',
      );
    });

    test('对端删了、本地之后又更新过 → 保留本地', () async {
      final local = FakeStore(
        books: [book('a', title: '改过名', updatedAt: DateTime(2026, 9))],
      );
      final mirror = SyncMirror(local);

      await mirror.merge(
        SyncPayload(
          books: [
            SyncBook(
              id: 'a',
              title: 'a',
              entryUrl: 'https://a.dev/docs',
              scopePrefix: 'https://a.dev/docs',
              sortIndex: 0,
              createdAt: DateTime(2025),
              updatedAt: DateTime(2026, 6),
              deletedAt: DateTime(2026, 6),
            ),
          ],
          progress: const [],
        ),
      );

      expect(
        await local.loadBooks(),
        hasLength(1),
        reason: '本地在删除之后改过名,本地动作更晚,不该被删',
      );
    });

    test('对端清单里没有、本地更新更晚 → 保留（刚加的）', () async {
      final local = FakeStore(
        books: [book('fresh', updatedAt: DateTime(2026, 12))],
      );
      final mirror = SyncMirror(local);

      // 对端只有一个早先更新的书
      await mirror.merge(
        SyncPayload(
          books: [syncBook('old', updatedAt: DateTime(2026, 1))],
          progress: const [],
        ),
      );

      final ids = (await local.loadBooks()).map((b) => b.id).toSet();
      expect(ids, contains('fresh'), reason: '本地刚加的书不该被当成删除');
    });

    test('对端清单里没有、且快照里有 → 删掉（对端删了）', () async {
      final local = FakeStore(
        books: [book('gone', updatedAt: DateTime(2026, 1))],
      );
      // 上次同步时两端都有 gone —— 这次对端没有,说明被删了
      await local.saveSyncSnapshot({'gone'});
      final mirror = SyncMirror(local);

      await mirror.merge(
        SyncPayload(
          books: [syncBook('other', updatedAt: DateTime(2026, 9))],
          progress: const [],
        ),
      );

      final ids = (await local.loadBooks()).map((b) => b.id).toSet();
      expect(ids, isNot(contains('gone')));
    });
  });

  group('书架变一致', () {
    test('两端都有的书最终状态相同', () async {
      final local = FakeStore(
        books: [book('a', title: 'A-本地', updatedAt: DateTime(2026, 3))],
      );
      final mirror = SyncMirror(local);

      await mirror.merge(
        SyncPayload(
          books: [syncBook('a', title: 'A-对端', updatedAt: DateTime(2026, 5))],
          progress: const [],
        ),
      );

      expect((await local.loadBooks()).first.title, 'A-对端');
    });

    test('进度按时间取新', () async {
      final local = FakeStore(books: [book('a')]);
      await local.saveProgress(
        ProgressSnapshot(
          bookId: 'a',
          url: 'old',
          pageTitle: '',
          updatedAt: DateTime(2026, 1),
          deviceId: 'local',
        ),
      );

      final mirror = SyncMirror(local);
      await mirror.merge(
        SyncPayload(
          books: [syncBook('a')],
          progress: [syncProgress('a', 'new', updatedAt: DateTime(2026, 9))],
        ),
      );

      expect((await local.latestProgress('a'))?.url, 'new');
    });

    test('本地进度更新 → 不被对端覆盖', () async {
      final local = FakeStore(books: [book('a')]);
      await local.saveProgress(
        ProgressSnapshot(
          bookId: 'a',
          url: 'local-new',
          pageTitle: '',
          updatedAt: DateTime(2026, 9),
          deviceId: 'local',
        ),
      );

      final mirror = SyncMirror(local);
      await mirror.merge(
        SyncPayload(
          books: [syncBook('a')],
          progress: [syncProgress('a', 'remote-old', updatedAt: DateTime(2026, 1))],
        ),
      );

      expect((await local.latestProgress('a'))?.url, 'local-new');
    });
  });

  group('分组', () {
    test('对端的分组会建到本地', () async {
      final local = FakeStore();
      final mirror = SyncMirror(local);

      await mirror.merge(
        SyncPayload(
          books: [syncBook('a', groupName: '前端')],
          progress: const [],
        ),
      );

      expect((await local.loadGroups()).map((g) => g.name), contains('前端'));
    });

    test('有空分组时解散', () async {
      final local = FakeStore(
        groups: [
          BookGroup(
            id: 'g1',
            name: '空分组',
            sortIndex: 0,
            updatedAt: DateTime(2026),
          ),
        ],
      );
      final mirror = SyncMirror(local);

      await mirror.merge(
        SyncPayload(books: const [], progress: const []),
      );

      expect(await local.loadGroups(), isEmpty);
    });

    test('有书的分组不解散', () async {
      final local = FakeStore(
        books: [book('a', groupId: 'g1', updatedAt: DateTime(2026, 12))],
        groups: [
          BookGroup(
            id: 'g1',
            name: '有书的分组',
            sortIndex: 0,
            updatedAt: DateTime(2026),
          ),
        ],
      );
      final mirror = SyncMirror(local);

      await mirror.merge(
        SyncPayload(books: const [], progress: const []),
      );

      expect(
        await local.loadGroups(),
        hasLength(1),
        reason: '组里还有书（且书是本地更新的），分组要留着',
      );
    });
  });

  group('导出', () {
    test('包含墓碑——删除必须能被对端看见', () async {
      final local = FakeStore(books: [book('a'), book('b')]);
      await local.deleteBook('b');

      final mirror = SyncMirror(local);
      final payload = await mirror.export();

      final ids = payload.books.map((b) => b.id).toSet();
      expect(ids, {'a', 'b'});
      final b = payload.books.firstWhere((x) => x.id == 'b');
      expect(b.deletedAt, isNotNull);
    });

    test('已删书的进度不导出', () async {
      final local = FakeStore(books: [book('a')]);
      await local.saveProgress(
        ProgressSnapshot(
          bookId: 'a',
          url: 'u',
          pageTitle: '',
          updatedAt: DateTime(2026),
          deviceId: 'd',
        ),
      );
      await local.deleteBook('a');

      final mirror = SyncMirror(local);
      final payload = await mirror.export();

      expect(payload.progress, isEmpty);
    });
  });
}

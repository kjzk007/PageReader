import 'package:flutter_test/flutter_test.dart';
import 'package:pagereader/core/sync/sync_mirror.dart';
import 'package:pagereader/core/sync/sync_protocol.dart';

import 'sync_merger_test.dart' show FakeStore, book, syncBook;

/// 同步快照判定删除的测试。
///
/// ── 为什么需要快照 ──
///
/// 「对端把书删了」和「对端从来没有这本书」在数据上是同一件事:
/// 都是"对端清单里没有它"。没有历史就无法区分,只能猜 ——
/// 猜错就是误删用户的书。
///
/// 快照记录"上次同步时的完整清单":
///   * 快照里有、现在对端没有 → 对端删了 → 本地也删
///   * 快照里没有 → 上次同步后才加的,对端还没见过 → 保留
void main() {
  group('快照判定删除', () {
    test('快照里有、对端没有 → 删除（对端删了）', () async {
      final local = FakeStore(books: [book('a'), book('b')]);
      // 上次同步时两端都有 a 和 b
      await local.saveSyncSnapshot({'a', 'b'});

      final mirror = SyncMirror(local);
      // 这次对端只有 a —— b 被删了
      await mirror.merge(
        SyncPayload(books: [syncBook('a')], progress: const []),
      );

      final ids = (await local.loadBooks()).map((b) => b.id).toSet();
      expect(ids, {'a'}, reason: 'b 在上次同步时有、这次没有 = 被删了');
    });

    test('快照里没有、对端也没有 → 保留（本地刚加的）', () async {
      final local = FakeStore(books: [book('fresh'), book('old')]);
      // 上次同步时只有 old
      await local.saveSyncSnapshot({'old'});

      final mirror = SyncMirror(local);
      // 对端这次也没有 fresh(没见过),也没有 old(删了)
      await mirror.merge(
        SyncPayload(books: const [], progress: const []),
      );

      final ids = (await local.loadBooks()).map((b) => b.id).toSet();
      expect(
        ids,
        {'fresh'},
        reason: 'fresh 是上次同步后才加的,对端没见过,不该被删',
      );
    });

    test('快照为空（首次同步）→ 保守保留本地书', () async {
      final local = FakeStore(books: [book('a'), book('b')]);
      // 首次同步,还没有快照

      final mirror = SyncMirror(local);
      await mirror.merge(
        SyncPayload(books: const [], progress: const []),
      );

      expect(
        await local.loadBooks(),
        hasLength(2),
        reason: '没有快照就无法判断是删除还是没见过,宁可多留',
      );
    });

    test('两端都有的书不受快照影响', () async {
      final local = FakeStore(books: [book('a', updatedAt: DateTime(2026, 1))]);
      await local.saveSyncSnapshot({'a'});

      final mirror = SyncMirror(local);
      await mirror.merge(
        SyncPayload(
          books: [syncBook('a', title: '新名', updatedAt: DateTime(2026, 5))],
          progress: const [],
        ),
      );

      final books = await local.loadBooks();
      expect(books, hasLength(1));
      expect(books.first.title, '新名');
    });
  });

  group('完整同步场景', () {
    test('手机清空书架 → 桌面端也清空（有快照）', () async {
      final desktop = FakeStore(
        books: [book('a'), book('b'), book('c')],
      );
      // 上次同步时两端都有这三本
      await desktop.saveSyncSnapshot({'a', 'b', 'c'});

      final mirror = SyncMirror(desktop);
      // 手机这次推来空清单
      await mirror.merge(
        const SyncPayload(books: [], progress: []),
      );

      expect(
        await desktop.loadBooks(),
        isEmpty,
        reason: '这正是用户遇到的场景',
      );
    });

    test('一端新增、一端无快照 → 新增的保留', () async {
      final desktop = FakeStore();
      // 桌面端没有快照

      final mirror = SyncMirror(desktop);
      await mirror.merge(
        SyncPayload(
          books: [syncBook('new', title: '手机新增')],
          progress: const [],
        ),
      );

      expect(await desktop.loadBooks(), hasLength(1));
    });
  });
}

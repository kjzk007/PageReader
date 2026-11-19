import 'package:flutter_test/flutter_test.dart';
import 'package:pagereader/core/domain/models.dart';
import 'package:pagereader/core/sync/sync_mirror.dart';
import 'package:pagereader/core/sync/sync_protocol.dart';

import 'sync_merger_test.dart' show FakeStore, book, syncBook;

/// 用户报的三个问题对应的测试。
///
/// 1. 配对后设备列表不自动刷新 —— 改为轮询,见 sync_desktop_page
/// 2. 书同步了但分类没同步 —— 载荷里根本没带分组
/// 3. 建完书不能改分类 —— 菜单缺「移动到分类」
void main() {
  group('分类同步', () {
    test('空分组也会同步过去', () async {
      final local = FakeStore();
      final mirror = SyncMirror(local);

      // 对端有一个空分组(没有书用它)
      await mirror.merge(
        SyncPayload(
          books: const [],
          progress: const [],
          groups: [
            SyncGroup(
              name: '待读',
              sortIndex: 0,
              updatedAt: DateTime(2026),
            ),
          ],
        ),
      );

      final names = (await local.loadGroups()).map((g) => g.name).toSet();
      expect(
        names,
        contains('待读'),
        reason: '空分组也要建出来 —— 用户可能先建分类再往里放书',
      );
    });

    test('分组排序会同步', () async {
      final local = FakeStore(
        groups: [
          BookGroup(
            id: 'g1',
            name: '前端',
            sortIndex: 5,
            updatedAt: DateTime(2026),
          ),
        ],
      );
      final mirror = SyncMirror(local);

      await mirror.merge(
        SyncPayload(
          books: const [],
          progress: const [],
          groups: [
            SyncGroup(
              name: '前端',
              sortIndex: 1,
              updatedAt: DateTime(2026, 6),
            ),
          ],
        ),
      );

      final g = (await local.loadGroups()).firstWhere((x) => x.name == '前端');
      expect(g.sortIndex, 1, reason: '分组顺序也该跟着对端');
    });

    test('对端没有的分组会被解散（组内无书时）', () async {
      final local = FakeStore(
        groups: [
          BookGroup(
            id: 'g1',
            name: '多余分组',
            sortIndex: 0,
            updatedAt: DateTime(2026),
          ),
        ],
      );
      final mirror = SyncMirror(local);

      await mirror.merge(
        const SyncPayload(books: [], progress: [], groups: []),
      );

      expect(await local.loadGroups(), isEmpty);
    });

    test('组内有书的分组不解散', () async {
      final local = FakeStore(
        books: [book('a', groupId: 'g1', updatedAt: DateTime(2026, 12))],
        groups: [
          BookGroup(
            id: 'g1',
            name: '有书',
            sortIndex: 0,
            updatedAt: DateTime(2026),
          ),
        ],
      );
      final mirror = SyncMirror(local);

      await mirror.merge(
        const SyncPayload(books: [], progress: [], groups: []),
      );

      expect(await local.loadGroups(), hasLength(1));
    });

    test('export 会带上分组', () async {
      final local = FakeStore(
        groups: [
          BookGroup(
            id: 'g1',
            name: '前端',
            sortIndex: 2,
            updatedAt: DateTime(2026),
          ),
        ],
      );

      final mirror = SyncMirror(local);
      final payload = await mirror.export();

      expect(payload.groups, hasLength(1));
      expect(payload.groups.first.name, '前端');
      expect(payload.groups.first.sortIndex, 2);
    });

    test('老版本载荷（没有 groups 字段）仍能处理', () async {
      final local = FakeStore();
      final mirror = SyncMirror(local);

      // 模拟老载荷:只有 books,书本带 groupName
      final old = SyncPayload.decode(
        '{"version":1,"books":[{"id":"a","title":"A",'
        '"entryUrl":"https://a.dev/d","scopePrefix":"https://a.dev/d",'
        '"sortIndex":0,"createdAt":1000000000000,'
        '"updatedAt":2000000000000,"groupName":"前端"}],"progress":[]}',
      );

      await mirror.merge(old);

      final names = (await local.loadGroups()).map((g) => g.name).toSet();
      expect(names, contains('前端'), reason: '老载荷靠书本的 groupName 反推');
    });
  });

  group('书移到别的分类', () {
    test('改 groupId 并更新时间戳后，同步会认这边更新', () async {
      // 本地把书从「前端」移到「后端」,时间戳更新
      final localTime = DateTime(2026, 12);
      final local = FakeStore(
        books: [book('a', groupId: 'g2', updatedAt: localTime)],
        groups: [
          BookGroup(
            id: 'g1',
            name: '前端',
            sortIndex: 0,
            updatedAt: DateTime(2026),
          ),
          BookGroup(
            id: 'g2',
            name: '后端',
            sortIndex: 1,
            updatedAt: DateTime(2026),
          ),
        ],
      );

      final mirror = SyncMirror(local);
      // 对端的同一本书还在「前端」,时间更早
      await mirror.merge(
        SyncPayload(
          books: [
            syncBook('a', groupName: '前端', updatedAt: DateTime(2026, 1)),
          ],
          progress: const [],
          groups: [
            SyncGroup(
              name: '前端',
              sortIndex: 0,
              updatedAt: DateTime(2026),
            ),
            SyncGroup(
              name: '后端',
              sortIndex: 1,
              updatedAt: DateTime(2026),
            ),
          ],
        ),
      );

      final books = await local.loadBooks();
      final gid = books.firstWhere((b) => b.id == 'a').groupId;
      final groupName =
          (await local.loadGroups()).firstWhere((g) => g.id == gid).name;
      expect(
        groupName,
        '后端',
        reason: '本地移动时间更晚,对端的「前端」不该覆盖',
      );
    });

    test('对端移动更晚时，本地跟着改', () async {
      final local = FakeStore(
        books: [book('a', groupId: 'g1', updatedAt: DateTime(2026, 1))],
        groups: [
          BookGroup(
            id: 'g1',
            name: '前端',
            sortIndex: 0,
            updatedAt: DateTime(2026),
          ),
        ],
      );

      final mirror = SyncMirror(local);
      await mirror.merge(
        SyncPayload(
          books: [
            syncBook('a', groupName: '后端', updatedAt: DateTime(2026, 12)),
          ],
          progress: const [],
          groups: [
            SyncGroup(
              name: '后端',
              sortIndex: 0,
              updatedAt: DateTime(2026, 12),
            ),
          ],
        ),
      );

      final books = await local.loadBooks();
      final gid = books.firstWhere((b) => b.id == 'a').groupId;
      final g = (await local.loadGroups()).firstWhere((x) => x.id == gid);
      expect(g.name, '后端');
    });

    test('移到未分组（groupId 为 null）能同步', () async {
      final local = FakeStore(
        books: [book('a', groupId: null, updatedAt: DateTime(2026, 12))],
        groups: [
          BookGroup(
            id: 'g1',
            name: '前端',
            sortIndex: 0,
            updatedAt: DateTime(2026),
          ),
        ],
      );

      final mirror = SyncMirror(local);
      await mirror.merge(
        SyncPayload(
          books: [
            // groupName 为空 = 未分组
            syncBook('a', updatedAt: DateTime(2026, 1)),
          ],
          progress: const [],
          groups: const [],
        ),
      );

      final books = await local.loadBooks();
      expect(
        books.firstWhere((b) => b.id == 'a').groupId,
        isNull,
        reason: '本地移到未分组,对端的老分类不该把它拽回去',
      );
    });
  });
}

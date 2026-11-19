import 'package:flutter_test/flutter_test.dart';
import 'package:pagereader/core/domain/models.dart';
import 'package:pagereader/core/ports/ports.dart';
import 'package:pagereader/core/sync/sync_merger.dart';
import 'package:pagereader/core/sync/sync_protocol.dart';

/// 同步合并逻辑的测试。
///
/// 冲突策略:按 updatedAt 取新。这里重点验证
/// "更新的赢、更旧的不能覆盖、相同时间不重复写"。
class FakeStore implements LibraryStore {
  FakeStore({List<Book>? books, List<BookGroup>? groups})
    : _books = [...?books],
      _groups = [...?groups];

  final List<Book> _books;
  final List<BookGroup> _groups;
  final List<ProgressSnapshot> _progress = [];

  @override
  Future<List<Book>> loadBooks() async =>
      _books.where((b) => b.deletedAt == null).toList();

  @override
  Future<List<Book>> loadBooksIncludingDeleted() async => List.of(_books);

  @override
  Future<void> deleteProgressOf(String bookId) async {
    _progress.removeWhere((p) => p.bookId == bookId);
  }

  Set<String> _syncSnapshot = {};

  @override
  Future<Set<String>> loadSyncSnapshot() async => Set.of(_syncSnapshot);

  @override
  Future<void> saveSyncSnapshot(Set<String> bookIds) async {
    _syncSnapshot = Set.of(bookIds);
  }

  @override
  Future<List<BookGroup>> loadGroups() async => List.of(_groups);

  @override
  Future<int> nextSortIndex() async => _books.length;

  @override
  Future<void> upsertBook(Book book) async {
    final i = _books.indexWhere((b) => b.id == book.id);
    if (i >= 0) {
      _books[i] = book;
    } else {
      _books.add(book);
    }
  }

  @override
  Future<void> deleteBook(String bookId) async {
    // 与 SqliteLibraryStore 一致:软删书(留墓碑),硬删进度。
    final i = _books.indexWhere((b) => b.id == bookId);
    if (i >= 0) {
      final b = _books[i];
      _books[i] = Book(
        id: b.id,
        title: b.title,
        entryUrl: b.entryUrl,
        scopePrefix: b.scopePrefix,
        groupId: b.groupId,
        sortIndex: b.sortIndex,
        createdAt: b.createdAt,
        updatedAt: DateTime.now(),
        iconUrl: b.iconUrl,
        themeColor: b.themeColor,
        deletedAt: DateTime.now(),
      );
    }
    await deleteProgressOf(bookId);
  }

  @override
  Future<void> upsertGroup(BookGroup group) async {
    final i = _groups.indexWhere((g) => g.id == group.id);
    if (i >= 0) {
      _groups[i] = group;
    } else {
      _groups.add(group);
    }
  }

  @override
  Future<void> deleteGroup(String groupId) async {
    _groups.removeWhere((g) => g.id == groupId);
  }

  @override
  Future<ProgressSnapshot?> latestProgress(String bookId) async {
    final mine = _progress.where((p) => p.bookId == bookId).toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return mine.isEmpty ? null : mine.first;
  }

  @override
  Future<Map<String, ProgressSnapshot>> latestProgressByBook() async {
    final out = <String, ProgressSnapshot>{};
    for (final p in _progress) {
      final cur = out[p.bookId];
      if (cur == null || p.updatedAt.isAfter(cur.updatedAt)) {
        out[p.bookId] = p;
      }
    }
    return out;
  }

  @override
  Future<void> saveProgress(ProgressSnapshot s) async {
    _progress.removeWhere((p) => p.bookId == s.bookId && p.url == s.url);
    _progress.add(s);
  }

  @override
  Future<List<ProgressSnapshot>> recentProgress({int limit = 20}) async {
    final sorted = List.of(_progress)
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return sorted.take(limit).toList();
  }

  List<Book> get books => _books;
  List<BookGroup> get groups => _groups;
  List<ProgressSnapshot> get progress => _progress;
}

Book book(
  String id, {
  String title = '',
  DateTime? updatedAt,
  String? groupId,
}) {
  final t = updatedAt ?? DateTime(2026, 1, 1);
  return Book(
    id: id,
    title: title.isEmpty ? id : title,
    entryUrl: 'https://$id.dev/docs',
    scopePrefix: 'https://$id.dev/docs',
    groupId: groupId,
    sortIndex: 0,
    createdAt: DateTime(2025, 1, 1),
    updatedAt: t,
  );
}

SyncBook syncBook(
  String id, {
  DateTime? updatedAt,
  String? groupName,
  String title = '',
}) {
  final t = updatedAt ?? DateTime(2026, 1, 1);
  return SyncBook(
    id: id,
    title: title.isEmpty ? id : title,
    entryUrl: 'https://$id.dev/docs',
    scopePrefix: 'https://$id.dev/docs',
    sortIndex: 0,
    createdAt: DateTime(2025, 1, 1),
    updatedAt: t,
    groupName: groupName,
  );
}

SyncProgress syncProgress(
  String bookId,
  String url, {
  required DateTime updatedAt,
  double? ratio,
}) {
  return SyncProgress(
    bookId: bookId,
    url: url,
    updatedAt: updatedAt,
    pageTitle: 'title-$bookId',
    anchor: Anchor(
      cssPath: 'body > main',
      textFingerprint: 'fp',
      textLength: 10,
      offsetPx: 100,
      docRatio: ratio ?? 0.5,
    ),
  );
}

void main() {
  group('书的合并', () {
    test('本地没有 → 新增', () async {
      final store = FakeStore();
      final merger = SyncMerger(store);
      final r = await merger.merge(
        SyncPayload(books: [syncBook('a')], progress: const []),
      );
      expect(r.booksAdded, 1);
      expect(store.books.length, 1);
      expect(store.books.first.id, 'a');
    });

    test('对端更新 → 覆盖', () async {
      final store = FakeStore(
        books: [book('a', title: '旧名', updatedAt: DateTime(2026, 1, 1))],
      );
      final merger = SyncMerger(store);
      final r = await merger.merge(
        SyncPayload(
          books: [
            syncBook('a', title: '新名', updatedAt: DateTime(2026, 2, 1)),
          ],
          progress: const [],
        ),
      );
      expect(r.booksUpdated, 1);
      expect(store.books.first.title, '新名');
    });

    test('本地更新 → 不覆盖', () async {
      final store = FakeStore(
        books: [book('a', title: '本地新', updatedAt: DateTime(2026, 3, 1))],
      );
      final merger = SyncMerger(store);
      final r = await merger.merge(
        SyncPayload(
          books: [
            syncBook('a', title: '对端旧', updatedAt: DateTime(2026, 1, 1)),
          ],
          progress: const [],
        ),
      );
      expect(r.booksUpdated, 0);
      expect(store.books.first.title, '本地新');
    });

    test('时间相同 → 不重复写', () async {
      final t = DateTime(2026, 1, 1);
      final store = FakeStore(books: [book('a', title: '原名', updatedAt: t)]);
      final merger = SyncMerger(store);
      final r = await merger.merge(
        SyncPayload(
          books: [syncBook('a', title: '对端名', updatedAt: t)],
          progress: const [],
        ),
      );
      expect(r.booksUpdated, 0);
      expect(store.books.first.title, '原名');
    });
  });

  group('分组的合并', () {
    test('对端有分组名、本地没有 → 新建分组', () async {
      final store = FakeStore();
      final merger = SyncMerger(store);
      await merger.merge(
        SyncPayload(
          books: [syncBook('a', groupName: '前端')],
          progress: const [],
        ),
      );
      expect(store.groups.length, 1);
      expect(store.groups.first.name, '前端');
      expect(store.books.first.groupId, store.groups.first.id);
    });

    test('同名分组已存在 → 不重复建', () async {
      final store = FakeStore(
        groups: [
          BookGroup(
            id: 'g1',
            name: '前端',
            sortIndex: 0,
            updatedAt: DateTime(2026, 1, 1),
          ),
        ],
      );
      final merger = SyncMerger(store);
      await merger.merge(
        SyncPayload(
          books: [syncBook('a', groupName: '前端')],
          progress: const [],
        ),
      );
      expect(store.groups.length, 1);
      expect(store.books.first.groupId, 'g1');
    });
  });

  group('进度的合并', () {
    test('本地没有 → 插入', () async {
      final store = FakeStore();
      final merger = SyncMerger(store);
      final r = await merger.merge(
        SyncPayload(
          books: const [],
          progress: [
            syncProgress('a', 'https://a.dev/docs', updatedAt: DateTime(2026)),
          ],
        ),
      );
      expect(r.progressUpdated, 1);
      expect(store.progress.length, 1);
    });

    test('对端更新 → 覆盖', () async {
      final store = FakeStore();
      await store.saveProgress(
        ProgressSnapshot(
          bookId: 'a',
          url: 'https://a.dev/docs',
          pageTitle: '旧',
          anchor: const Anchor(
            cssPath: 'x',
            textFingerprint: 'y',
            textLength: 1,
            offsetPx: 0,
            docRatio: 0.1,
          ),
          updatedAt: DateTime(2026, 1, 1),
          deviceId: 'd',
        ),
      );
      final merger = SyncMerger(store);
      final r = await merger.merge(
        SyncPayload(
          books: const [],
          progress: [
            syncProgress(
              'a',
              'https://a.dev/docs',
              updatedAt: DateTime(2026, 2, 1),
              ratio: 0.8,
            ),
          ],
        ),
      );
      expect(r.progressUpdated, 1);
      expect(store.progress.first.anchor?.docRatio, 0.8);
    });

    test('本地更新 → 保留本地', () async {
      final store = FakeStore();
      await store.saveProgress(
        ProgressSnapshot(
          bookId: 'a',
          url: 'https://a.dev/docs',
          pageTitle: '本地新',
          anchor: const Anchor(
            cssPath: 'x',
            textFingerprint: 'y',
            textLength: 1,
            offsetPx: 0,
            docRatio: 0.9,
          ),
          updatedAt: DateTime(2026, 5, 1),
          deviceId: 'd',
        ),
      );
      final merger = SyncMerger(store);
      final r = await merger.merge(
        SyncPayload(
          books: const [],
          progress: [
            syncProgress(
              'a',
              'https://a.dev/docs',
              updatedAt: DateTime(2026, 1, 1),
              ratio: 0.2,
            ),
          ],
        ),
      );
      expect(r.progressUpdated, 0);
      expect(r.progressKept, 1);
      expect(store.progress.first.anchor?.docRatio, 0.9);
    });
  });

  group('导出', () {
    test('带出书、分组名、每本最新进度', () async {
      final store = FakeStore(
        books: [book('a', groupId: 'g1')],
        groups: [
          BookGroup(
            id: 'g1',
            name: '前端',
            sortIndex: 0,
            updatedAt: DateTime(2026),
          ),
        ],
      );
      await store.saveProgress(
        ProgressSnapshot(
          bookId: 'a',
          url: 'https://a.dev/docs',
          pageTitle: 't',
          updatedAt: DateTime(2026, 3, 1),
          deviceId: 'd',
        ),
      );
      final merger = SyncMerger(store);
      final payload = await merger.export();
      expect(payload.books.length, 1);
      expect(payload.books.first.groupName, '前端');
      expect(payload.progress.length, 1);
    });
  });

  group('协议编解码', () {
    test('往返不丢字段', () {
      final p = SyncPayload(
        books: [syncBook('a', groupName: '前端')],
        progress: [
          syncProgress('a', 'https://a.dev/docs', updatedAt: DateTime(2026)),
        ],
      );
      final back = SyncPayload.decode(p.encode());
      expect(back.books.length, 1);
      expect(back.books.first.groupName, '前端');
      expect(back.progress.length, 1);
      expect(back.progress.first.anchor?.docRatio, 0.5);
    });

    test('未知字段忽略', () {
      const raw = '{"version":1,"books":[{"id":"a","entryUrl":"u",'
          '"futureField":123}],"progress":[]}';
      final p = SyncPayload.decode(raw);
      expect(p.books.length, 1);
    });

    test('缺少必需字段的条目被丢弃', () {
      const raw = '{"books":[{"title":"没有 id"},'
          '{"id":"ok","entryUrl":"u"}],"progress":[]}';
      final p = SyncPayload.decode(raw);
      expect(p.books.length, 1);
      expect(p.books.first.id, 'ok');
    });

    test('格式不对时报错', () {
      expect(() => SyncPayload.decode('not json'), throwsFormatException);
    });

    test('空载荷合法', () {
      final p = SyncPayload.decode('{"books":[],"progress":[]}');
      expect(p.books, isEmpty);
      expect(p.progress, isEmpty);
    });
  });

  group('结果描述', () {
    test('无变化', () {
      const r = SyncResult();
      expect(r.changedAnything, isFalse);
      // 镜像同步后两端一致,文案改成「两端已经一致」更准确
      expect(r.describe(), contains('两端已经一致'));
    });

    test('删除也计入变化', () {
      const r = SyncResult(booksRemoved: 3);
      expect(r.changedAnything, isTrue);
      expect(r.describe(), contains('删除 3 本书'));
    });

    test('有变化时说清改了啥', () {
      const r = SyncResult(booksAdded: 2, progressUpdated: 3);
      expect(r.describe(), contains('新增 2 本书'));
      expect(r.describe(), contains('更新 3 条进度'));
    });
  });
}

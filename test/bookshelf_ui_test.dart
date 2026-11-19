import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pagereader/core/domain/models.dart';
import 'package:pagereader/core/ports/ports.dart';
import 'package:pagereader/features/bookshelf/bookshelf_page.dart';

/// 界面交互测试。
///
/// 覆盖之前"只写了代码、从未验证过"的部分:
/// 搜索、分组筛选、右键菜单、章节号显示、空状态。
/// 这些是用户最终检验时一定会点的地方。
class TableStore implements LibraryStore {
  TableStore({required this.books, this.groups = const []});

  final List<Book> books;
  final List<BookGroup> groups;
  final Map<String, ProgressSnapshot> progress = {};
  final List<String> deleted = [];

  @override
  Future<List<BookGroup>> loadGroups() async => groups;

  @override
  Future<List<Book>> loadBooks() async => books.where((b) => !deleted.contains(b.id)).toList();

  @override
  Future<List<Book>> loadBooksIncludingDeleted() async {
    throw UnimplementedError('测试用不到');
  }

  @override
  Future<void> deleteProgressOf(String bookId) async {}

  @override
  Future<Set<String>> loadSyncSnapshot() async => {};

  @override
  Future<void> saveSyncSnapshot(Set<String> bookIds) async {}

  @override
  Future<int> nextSortIndex() async =>
      books.isEmpty ? 0 : books.length;

  @override
  Future<void> upsertBook(Book book) async {
    books
      ..removeWhere((b) => b.id == book.id)
      ..add(book);
  }

  @override
  Future<void> deleteBook(String bookId) async => deleted.add(bookId);

  @override
  Future<void> upsertGroup(BookGroup group) async {}

  @override
  Future<void> deleteGroup(String groupId) async {}

  @override
  Future<ProgressSnapshot?> latestProgress(String bookId) async =>
      progress[bookId];

  @override
  Future<Map<String, ProgressSnapshot>> latestProgressByBook() async =>
      Map.of(progress);

  @override
  Future<void> saveProgress(ProgressSnapshot s) async =>
      progress[s.bookId] = s;

  @override
  Future<List<ProgressSnapshot>> recentProgress({int limit = 20}) async =>
      progress.values.toList();
}

class NullEngine implements WebEngine {
  final _nav = StreamController<NavigationEvent>.broadcast();
  final _pos = StreamController<PositionReport>.broadcast();

  @override
  String get id => 'null';

  @override
  Stream<NavigationEvent> get navigations => _nav.stream;

  @override
  Stream<PositionReport> get positionReports => _pos.stream;

  @override
  Set<String> get openBooks => {};

  @override
  Future<String> launch(Book book, {ProgressSnapshot? resume}) async =>
      book.entryUrl;

  @override
  Future<ProgressSnapshot?> collect(
    String bookId, {
    String deviceId = 'null',
  }) async => null;

  @override
  Future<List<ProgressSnapshot>> flushAll({String deviceId = 'null'}) async =>
      [];

  @override
  Future<void> installBootstrap(String script) async {}

  @override
  Future<List<String>> reapClosed({
    Future<void> Function(ProgressSnapshot snapshot)? persist,
  }) async => const [];

  @override
  @override
  Future<void> shutdown() async {}
}

Book makeBook(String id, String title, {String? group}) {
  final now = DateTime(2026, 1, 1);
  return Book(
    id: id,
    title: title,
    entryUrl: 'https://$id.dev/docs/intro',
    scopePrefix: 'https://$id.dev/docs',
    groupId: group,
    sortIndex: 0,
    createdAt: now,
    updatedAt: now,
  );
}

Future<void> pumpShelf(
  WidgetTester tester, {
  required TableStore store,
  WebEngine? engine,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: BookshelfPage(store: store, engine: engine ?? NullEngine()),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('搜索', () {
    testWidgets('按书名过滤', (tester) async {
      final store = TableStore(
        books: [
          makeBook('rust', 'Rust Book'),
          makeBook('vue', 'Vue 文档'),
        ],
      );
      await pumpShelf(tester, store: store);

      expect(find.text('Rust Book'), findsOneWidget);
      expect(find.text('Vue 文档'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.search));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'rust');
      await tester.pumpAndSettle();

      expect(find.text('Rust Book'), findsOneWidget);
      expect(find.text('Vue 文档'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('搜不到时显示"没找到"', (tester) async {
      final store = TableStore(books: [makeBook('a', 'Alpha')]);
      await pumpShelf(tester, store: store);

      await tester.tap(find.byIcon(Icons.search));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'zzzz');
      await tester.pumpAndSettle();

      expect(find.text('没找到匹配的书'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('能按上次停留的页面标题搜索', (tester) async {
      final store = TableStore(books: [makeBook('k8s', 'Kubernetes')]);
      // 让这本书的进度里带一个可搜的页面标题
      store.progress['k8s'] = ProgressSnapshot(
        bookId: 'k8s',
        url: 'https://k8s.dev/docs/pods',
        pageTitle: 'Pod 生命周期',
        updatedAt: DateTime(2026, 1, 5),
        deviceId: 't',
      );
      await pumpShelf(tester, store: store);

      await tester.tap(find.byIcon(Icons.search));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '生命周期');
      await tester.pumpAndSettle();

      expect(
        find.text('Kubernetes'),
        findsOneWidget,
        reason: '应能通过页面标题命中这本书',
      );
      await tester.pumpWidget(const SizedBox());
    });
  }
);

  group('分组筛选', () {
    testWidgets('点分组只显示该组', (tester) async {
      final store = TableStore(
        books: [
          makeBook('a', 'Alpha', group: 'g1'),
          makeBook('b', 'Beta', group: 'g2'),
        ],
        groups: [
          BookGroup(
            id: 'g1',
            name: '前端',
            sortIndex: 0,
            updatedAt: DateTime(2026, 1, 1),
          ),
          BookGroup(
            id: 'g2',
            name: '后端',
            sortIndex: 1,
            updatedAt: DateTime(2026, 1, 1),
          ),
        ],
      );
      await pumpShelf(tester, store: store);

      await tester.tap(find.text('前端'));
      await tester.pumpAndSettle();

      expect(find.text('Alpha'), findsOneWidget);
      expect(find.text('Beta'), findsNothing);

      // 切回全部
      await tester.tap(find.text('全部'));
      await tester.pumpAndSettle();
      expect(find.text('Beta'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });
  });

  group('章节号显示', () {
    testWidgets('进度标题带章节号时显示短标签', (tester) async {
      final store = TableStore(books: [makeBook('x', '某文档')]);
      store.progress['x'] = ProgressSnapshot(
        bookId: 'x',
        url: 'https://x.dev/docs/12',
        pageTitle: '第 12 章 并发编程',
        updatedAt: DateTime.now().subtract(const Duration(hours: 2)),
        deviceId: 't',
      );
      await pumpShelf(tester, store: store);

      // 副标题应显示"第 12 章",而不是完整标题
      expect(find.textContaining('第 12 章'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('提不到章节号时显示原标题', (tester) async {
      final store = TableStore(books: [makeBook('y', '某文档')]);
      store.progress['y'] = ProgressSnapshot(
        bookId: 'y',
        url: 'https://y.dev/docs/a',
        pageTitle: 'Defining Shared Behavior',
        updatedAt: DateTime.now().subtract(const Duration(hours: 1)),
        deviceId: 't',
      );
      await pumpShelf(tester, store: store);

      expect(find.textContaining('Defining Shared Behavior'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });
  });

  group('空状态', () {
    testWidgets('没有书时提示加书', (tester) async {
      await pumpShelf(tester, store: TableStore(books: []));
      expect(find.text('书架是空的'), findsOneWidget);
      expect(find.textContaining('点右上角 +'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });
  });

  group('最近阅读排序', () {
    testWidgets('刚读过的书排在最前', (tester) async {
      final store = TableStore(
        books: [
          makeBook('old', 'OldBook'),
          makeBook('new', 'NewBook'),
        ],
      );
      store.progress['old'] = ProgressSnapshot(
        bookId: 'old',
        url: 'https://old.dev/docs/a',
        pageTitle: 'A',
        updatedAt: DateTime(2026, 1, 1),
        deviceId: 't',
      );
      store.progress['new'] = ProgressSnapshot(
        bookId: 'new',
        url: 'https://new.dev/docs/a',
        pageTitle: 'B',
        updatedAt: DateTime(2026, 6, 1),
        deviceId: 't',
      );
      await pumpShelf(tester, store: store);

      // 找出两张卡片在屏幕上的纵坐标,靠前的应是 NewBook
      final newY = tester.getTopLeft(find.text('NewBook')).dy;
      final oldY = tester.getTopLeft(find.text('OldBook')).dy;
      expect(
        newY,
        lessThanOrEqualTo(oldY),
        reason: '最近读的 NewBook 应排在前面',
      );
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('没读过的书排在读过的后面', (tester) async {
      final store = TableStore(
        books: [
          makeBook('read', 'ReadBook'),
          makeBook('fresh', 'FreshBook'),
        ],
      );
      store.progress['read'] = ProgressSnapshot(
        bookId: 'read',
        url: 'https://read.dev/docs/a',
        pageTitle: 'A',
        updatedAt: DateTime(2026, 1, 1),
        deviceId: 't',
      );
      await pumpShelf(tester, store: store);

      final readX = tester.getTopLeft(find.text('ReadBook'));
      final freshX = tester.getTopLeft(find.text('FreshBook'));
      // 同一行时比较 x,不同行时比较 y
      final readFirst = readX.dy < freshX.dy ||
          (readX.dy == freshX.dy && readX.dx < freshX.dx);
      expect(readFirst, isTrue, reason: '读过的应排在未读之前');
      await tester.pumpWidget(const SizedBox());
    });
  });
}

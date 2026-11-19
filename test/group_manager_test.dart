import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pagereader/core/domain/models.dart';
import 'package:pagereader/core/ports/ports.dart';
import 'package:pagereader/features/bookshelf/bookshelf_page.dart';

/// 分组管理对话框的测试。
///
/// 这块之前只写了代码、从未渲染验证过。
/// 它涉及"删除分组只解散"这个关键语义 —— 做错了会连带删掉书和进度。
class GroupStore implements LibraryStore {
  GroupStore({required this.books, required this.groups});

  final List<Book> books;
  final List<BookGroup> groups;
  final Map<String, ProgressSnapshot> progress = {};
  final List<String> deletedGroups = [];
  final List<BookGroup> upsertedGroups = [];

  @override
  Future<List<BookGroup>> loadGroups() async => groups
      .where((g) => !deletedGroups.contains(g.id))
      .toList();

  @override
  Future<List<Book>> loadBooks() async => books;

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
  Future<int> nextSortIndex() async => books.length;

  @override
  Future<void> upsertBook(Book book) async {}

  @override
  Future<void> deleteBook(String bookId) async {}

  @override
  Future<void> upsertGroup(BookGroup group) async => upsertedGroups.add(group);

  @override
  Future<void> deleteGroup(String groupId) async =>
      deletedGroups.add(groupId);

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

class NoopEngine implements WebEngine {
  final _n = StreamController<NavigationEvent>.broadcast();
  final _p = StreamController<PositionReport>.broadcast();

  @override
  String get id => 'noop';

  @override
  Stream<NavigationEvent> get navigations => _n.stream;

  @override
  Stream<PositionReport> get positionReports => _p.stream;

  @override
  Set<String> get openBooks => {};

  @override
  Future<String> launch(Book book, {ProgressSnapshot? resume}) async =>
      book.entryUrl;

  @override
  Future<ProgressSnapshot?> collect(
    String bookId, {
    String deviceId = 'noop',
  }) async => null;

  @override
  Future<List<ProgressSnapshot>> flushAll({String deviceId = 'noop'}) async =>
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

Book b(String id, String title, {String? group}) => Book(
  id: id,
  title: title,
  entryUrl: 'https://$id.dev/docs',
  scopePrefix: 'https://$id.dev/docs',
  groupId: group,
  sortIndex: 0,
  createdAt: DateTime(2026, 1, 1),
  updatedAt: DateTime(2026, 1, 1),
);

BookGroup g(String id, String name) => BookGroup(
  id: id,
  name: name,
  sortIndex: 0,
  updatedAt: DateTime(2026, 1, 1),
);

Future<void> openManager(WidgetTester tester, GroupStore store) async {
  await tester.pumpWidget(
    MaterialApp(home: BookshelfPage(store: store, engine: NoopEngine())),
  );
  await tester.pumpAndSettle();
  // 分组栏末尾的"管理"按钮
  await tester.tap(find.byIcon(Icons.tune));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('能打开管理对话框并列出分组', (tester) async {
    final store = GroupStore(
      books: [b('a', 'A', group: 'g1')],
      groups: [g('g1', '前端'), g('g2', '后端')],
    );
    await openManager(tester, store);

    expect(find.text('管理分组'), findsOneWidget);
    expect(find.text('前端'), findsWidgets);
    expect(find.text('后端'), findsWidgets);
    expect(find.text('1 本'), findsOneWidget, reason: '应显示组内书数');
    await tester.pumpWidget(const SizedBox());
  }
);

  testWidgets('空分组列表给出提示', (tester) async {
    final store = GroupStore(books: [], groups: []);
    await openManager(tester, store);

    expect(find.textContaining('还没有分组'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('点新建分组能落库', (tester) async {
    final store = GroupStore(books: [], groups: []);
    await openManager(tester, store);

    // 对话框标题和按钮同名,要用按钮定位
    await tester.tap(find.widgetWithText(FilledButton, '新建分组'));
    await tester.pumpAndSettle();

    // 弹出输入框
    expect(find.text('新建分组'), findsWidgets);
    await tester.enterText(find.byType(TextField), '我的分组');
    await tester.pumpAndSettle();
    await tester.tap(find.text('确定'));
    await tester.pumpAndSettle();

    expect(store.upsertedGroups.length, 1);
    expect(store.upsertedGroups.first.name, '我的分组');
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('改名会带上原 id', (tester) async {
    final store = GroupStore(
      books: [],
      groups: [g('g1', '旧名')],
    );
    await openManager(tester, store);

    await tester.tap(find.byIcon(Icons.edit).first);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '新名');
    await tester.pumpAndSettle();
    await tester.tap(find.text('确定'));
    await tester.pumpAndSettle();

    expect(store.upsertedGroups.length, 1);
    expect(store.upsertedGroups.first.id, 'g1', reason: '改名必须保留 id');
    expect(store.upsertedGroups.first.name, '新名');
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('删除分组要先确认,且提示书会转为未分组', (tester) async {
    final store = GroupStore(
      books: [b('a', 'A', group: 'g1'), b('c', 'C', group: 'g1')],
      groups: [g('g1', '前端')],
    );
    await openManager(tester, store);

    await tester.tap(find.byIcon(Icons.delete_outline).first);
    await tester.pumpAndSettle();

    expect(find.textContaining('删除分组'), findsOneWidget);
    expect(
      find.textContaining('2 本书会转为未分组'),
      findsOneWidget,
      reason: '必须告知书不会被删',
    );

    await tester.tap(find.text('移除'));
    await tester.pumpAndSettle();

    expect(store.deletedGroups, contains('g1'));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('删除确认里点取消不会删', (tester) async {
    final store = GroupStore(
      books: [],
      groups: [g('g1', '前端')],
    );
    await openManager(tester, store);

    await tester.tap(find.byIcon(Icons.delete_outline).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();

    expect(store.deletedGroups, isEmpty);
    await tester.pumpWidget(const SizedBox());
  });
}

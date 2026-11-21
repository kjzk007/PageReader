import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pagereader/core/domain/models.dart';
import 'package:pagereader/core/ports/ports.dart';
import 'package:pagereader/features/bookshelf/bookshelf_page.dart';

/// 检测不到浏览器时的界面行为。
///
/// 这是最坏情况:用户装完程序打开,发现点书没反应。
/// 至少要保证:
///   1. 应用不崩溃、书架正常显示
///   2. 点书时给出**可操作**的提示,而不是一句"找不到"
class S implements LibraryStore {
  S(this.books);
  final List<Book> books;
  @override
  Future<List<BookGroup>> loadGroups() async => [];
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
  Future<void> upsertBook(Book b) async {}
  @override
  Future<void> deleteBook(String id) async {}
  @override
  Future<void> upsertGroup(BookGroup g) async {}
  @override
  Future<void> deleteGroup(String id) async {}
  @override
  Future<ProgressSnapshot?> latestProgress(String b) async => null;
  @override
  Future<Map<String, ProgressSnapshot>> latestProgressByBook() async => {};
  @override
  Future<void> saveProgress(ProgressSnapshot s) async {}
  @override
  Future<List<ProgressSnapshot>> recentProgress({int limit = 20}) async => [];
}

Book makeBook() => Book(
  id: 'b1',
  title: '测试书',
  entryUrl: 'https://a.dev/docs',
  scopePrefix: 'https://a.dev/docs',
  sortIndex: 0,
  createdAt: DateTime(2026, 1, 1),
  updatedAt: DateTime(2026, 1, 1),
);

void main() {
  testWidgets('没有引擎时书架正常显示,不崩溃', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: BookshelfPage(store: S([makeBook()]), engine: null),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('测试书'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('没有引擎时点书给出准确提示', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: BookshelfPage(store: S([makeBook()]), engine: null),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('测试书'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // 内嵌内核没有外部依赖，"找不到浏览器"这种说法已经不成立了。
    // 引擎为 null 只可能是还在初始化，提示必须说清这一点。
    expect(
      find.textContaining('内核正在准备'),
      findsOneWidget,
      reason: '引擎未就绪时要说明是"正在准备"，而不是让用户去装浏览器'
    );
    // 不能再出现要求用户装浏览器的文案
    expect(find.textContaining('Edge'), findsNothing);
    expect(find.textContaining('Chrome'), findsNothing);
    expect(find.textContaining('没有找到浏览器'), findsNothing);
    expect(find.textContaining('Exception'), findsNothing);

    await tester.pumpWidget(const SizedBox());
  });
}

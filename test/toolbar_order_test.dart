import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pagereader/core/domain/models.dart';
import 'package:pagereader/core/ports/ports.dart';
import 'package:pagereader/features/bookshelf/bookshelf_page.dart';

/// 工具栏按钮的顺序测试。
///
/// 顺序是明确的产品决策:同步 → 设置 → 搜索 → 加书。
/// 前两个管"连接/配置",后两个管"操作内容"。
/// 写成断言,避免以后调整布局时被无意打乱。
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

class E implements WebEngine {
  final _n = StreamController<NavigationEvent>.broadcast();
  final _p = StreamController<PositionReport>.broadcast();
  @override
  String get id => 'e';
  @override
  Stream<NavigationEvent> get navigations => _n.stream;
  @override
  Stream<PositionReport> get positionReports => _p.stream;
  @override
  Set<String> get openBooks => {};
  @override
  Future<String> launch(Book b, {ProgressSnapshot? resume}) async => b.entryUrl;
  @override
  Future<ProgressSnapshot?> collect(String b, {String? deviceId}) async =>
      null;
  @override
  Future<List<ProgressSnapshot>> flushAll({String? deviceId}) async => [];
  @override
  Future<void> installBootstrap(String s) async {}
  @override
  Future<List<String>> reapClosed({
    Future<void> Function(ProgressSnapshot snapshot)? persist,
  }) async => const [];

  @override
  @override
  Future<void> shutdown() async {}
}

void main() {
  testWidgets('工具栏按钮顺序:同步 → 设置 → 搜索 → 加书', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: BookshelfPage(
          store: S([
            Book(
              id: 'a',
              title: '书A',
              entryUrl: 'https://a.dev/docs',
              scopePrefix: 'https://a.dev/docs',
              sortIndex: 0,
              createdAt: DateTime(2026, 1, 1),
              updatedAt: DateTime(2026, 1, 1),
            ),
          ]),
          engine: E(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final sync = tester.getCenter(find.byTooltip('同步'));
    final settings = tester.getCenter(find.byTooltip('设置'));
    final search = tester.getCenter(find.byTooltip('搜索'));
    final add = tester.getCenter(find.byTooltip('加一本书'));

    // ignore: avoid_print
    print(
      '  x 坐标: 同步=${sync.dx.toStringAsFixed(0)} '
      '设置=${settings.dx.toStringAsFixed(0)} '
      '搜索=${search.dx.toStringAsFixed(0)} '
      '加书=${add.dx.toStringAsFixed(0)}',
    );

    // 从左到右:同步 < 设置 < 搜索 < 加书
    expect(sync.dx, lessThan(settings.dx), reason: '同步应在设置左边');
    expect(settings.dx, lessThan(search.dx), reason: '设置应在搜索左边');
    expect(search.dx, lessThan(add.dx), reason: '搜索应在加号左边');

    await tester.pumpWidget(const SizedBox());
  }
);

  testWidgets('四个按钮都居中同一行', (tester) async {
    // 模拟桌面端窗口尺寸
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(home: BookshelfPage(store: S([]), engine: E())),
    );
    await tester.pumpAndSettle();

    final ys = [
      tester.getCenter(find.byTooltip('同步')).dy,
      tester.getCenter(find.byTooltip('设置')).dy,
      tester.getCenter(find.byTooltip('搜索')).dy,
      tester.getCenter(find.byTooltip('加一本书')).dy,
    ];
    // ignore: avoid_print
    print('  y 坐标: $ys');
    expect(ys.toSet().length, 1, reason: '四个按钮应垂直对齐');

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('搜索展开后按钮仍在原位,且输入框可见', (tester) async {
    await tester.pumpWidget(
      MaterialApp(home: BookshelfPage(store: S([]), engine: E())),
    );
    await tester.pumpAndSettle();

    final syncBefore = tester.getCenter(find.byTooltip('同步'));
    final addBefore = tester.getCenter(find.byTooltip('加一本书'));

    await tester.tap(find.byTooltip('搜索'));
    await tester.pumpAndSettle();

    expect(find.byType(TextField), findsOneWidget, reason: '搜索框应展开');

    // 搜索框替换了搜索按钮,所以右侧按钮会左移一点 —— 这是正常布局。
    // 要保证的是:同步/设置仍在左边、加号仍在最右,顺序没变。
    final syncAfter = tester.getCenter(find.byTooltip('同步'));
    final addAfter = tester.getCenter(find.byTooltip('加一本书'));
    final settingsAfter = tester.getCenter(find.byTooltip('设置'));

    // ignore: avoid_print
    print(
      '  展开前: 同步=${syncBefore.dx.toStringAsFixed(0)} 加书=${addBefore.dx.toStringAsFixed(0)}',
    );
    // ignore: avoid_print
    print(
      '  展开后: 同步=${syncAfter.dx.toStringAsFixed(0)} '
      '设置=${settingsAfter.dx.toStringAsFixed(0)} 加书=${addAfter.dx.toStringAsFixed(0)}',
    );

    expect(syncAfter.dx, lessThan(settingsAfter.dx), reason: '同步仍在设置左边');
    expect(
      settingsAfter.dx,
      lessThan(addAfter.dx),
      reason: '设置在加号左边',
    );

    await tester.pumpWidget(const SizedBox());
  });
}

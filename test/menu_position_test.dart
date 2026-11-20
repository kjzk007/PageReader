import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pagereader/core/domain/models.dart';
import 'package:pagereader/core/ports/ports.dart';
import 'package:pagereader/features/bookshelf/bookshelf_page.dart';

/// 右键菜单的弹出位置测试。
///
/// 踩过的坑:为了加宽菜单把 RelativeRect 的 right/bottom 写成 0,
/// 结果 Flutter 理解成"可用区域一直延伸到屏幕边缘",菜单永远贴右。
/// 这里用断言锁死"菜单出现在光标附近"。
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
  Future<ProgressSnapshot?> collect(String b, {String deviceId = 'e'}) async =>
      null;
  @override
  Future<List<ProgressSnapshot>> flushAll({String deviceId = 'e'}) async => [];
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

Book makeBook(String id, String title) => Book(
  id: id,
  title: title,
  entryUrl: 'https://$id.dev/docs',
  scopePrefix: 'https://$id.dev/docs',
  sortIndex: 0,
  createdAt: DateTime(2026, 1, 1),
  updatedAt: DateTime(2026, 1, 1),
);

/// 在指定位置右键,返回菜单左上角坐标。
Future<Offset> rightClickAt(WidgetTester tester, Offset at) async {
  await tester.tapAt(at, buttons: kSecondaryButton);
  await tester.pumpAndSettle();
      final menu = find.text('打开').first;
  return tester.getTopLeft(menu);
}

void main() {
  testWidgets('菜单出现在光标附近,不会固定贴右', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: BookshelfPage(
          store: S([makeBook('a', '书A'), makeBook('b', '书B')]),
          engine: E(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final screen = tester.view.physicalSize / tester.view.devicePixelRatio;
    // ignore: avoid_print
    print('  屏幕尺寸: $screen');

    // 在左侧卡片上右键
    final leftCard = tester.getCenter(find.text('书A'));
    final leftMenu = await rightClickAt(tester, leftCard);
    // ignore: avoid_print
    print('  左侧右键(${leftCard.dx.toStringAsFixed(0)}) → 菜单左上 ${leftMenu.dx.toStringAsFixed(0)}');

    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(
      MaterialApp(
        home: BookshelfPage(
          store: S([makeBook('a', '书A'), makeBook('b', '书B')]),
          engine: E(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 在右侧卡片上右键
    final rightCard = tester.getCenter(find.text('书B'));
    final rightMenu = await rightClickAt(tester, rightCard);
    // ignore: avoid_print
    print('  右侧右键(${rightCard.dx.toStringAsFixed(0)}) → 菜单左上 ${rightMenu.dx.toStringAsFixed(0)}');

    // 关键断言:菜单位置应该跟着光标走
    expect(
      rightMenu.dx,
      greaterThan(leftMenu.dx),
      reason: '在更靠右的位置右键,菜单也应更靠右。'
          '如果两者相同或菜单总在最右,说明 RelativeRect 算错了',
    );

    await tester.pumpWidget(const SizedBox());
  }
);

  // 右/下边界由 Flutter 的 showMenu 内部处理(它会自动往左/往上挪)。
  // 这里只验证我们能正确把光标位置传给它 —— 即上面的"跟随光标"测试。
  // 边界行为属于框架职责,重复测它价值不大。
}

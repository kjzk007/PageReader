import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pagereader/core/domain/models.dart';
import 'package:pagereader/core/ports/ports.dart';
import 'package:pagereader/features/bookshelf/bookshelf_page.dart';

/// 书架卡片的菜单入口测试。
///
/// 踩过的坑:卡片只接了 `onSecondaryTapDown`(右键),
/// 桌面端能用,但**手机上没有右键** —— 长按什么都不会发生,
/// 用户完全无法改名/改范围/改分组/删除。
///
/// 这里锁住两个入口都要能用。
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
  Future<void> shutdown() async {}
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

Future<void> pumpShelf(WidgetTester tester) async {
  await tester.pumpWidget(
    MaterialApp(home: BookshelfPage(store: S([makeBook()]), engine: E())),
  );
  await tester.pumpAndSettle();
}

/// 菜单项里只要有这些就说明菜单弹出来了。
const menuLabels = ['打开', '改名', '改范围', '复制地址', '从书架移除'];

void expectMenuVisible() {
  for (final l in menuLabels) {
    expect(find.text(l), findsOneWidget, reason: '菜单项「$l」没出现');
  }
}

void main() {
  group('桌面端:右键弹菜单', () {
    testWidgets('在卡片上右键,菜单出现', (tester) async {
      await pumpShelf(tester);
      final center = tester.getCenter(find.text('测试书'));
      await tester.tapAt(center, buttons: kSecondaryButton);
      await tester.pumpAndSettle();
      expectMenuVisible();
      await tester.pumpWidget(const SizedBox());
    });
  });

  group('手机端:长按弹菜单', () {
    testWidgets('长按卡片,菜单出现', (tester) async {
      await pumpShelf(tester);
      final center = tester.getCenter(find.text('测试书'));
      final gesture = await tester.startGesture(center);
      // Flutter 的长按阈值是 500ms,给一点余量
      await tester.pump(const Duration(milliseconds: 700));
      await gesture.up();
      await tester.pumpAndSettle();
      expectMenuVisible();
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('长按后菜单出现在手指附近', (tester) async {
      await pumpShelf(tester);
      final center = tester.getCenter(find.text('测试书'));
      final gesture = await tester.startGesture(center);
      await tester.pump(const Duration(milliseconds: 700));
      await gesture.up();
      await tester.pumpAndSettle();

      final menu = tester.getRect(find.byType(PopupMenuItem<String>).first);
      // 菜单左上角应该在手势位置附近(不要求精确,只要不在屏幕另一端)
      expect(
        (menu.left - center.dx).abs(),
        lessThan(400),
        reason: '菜单位置离手指太远,手机上会看不到',
      );
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('短按只是打开书,不弹菜单', (tester) async {
      await pumpShelf(tester);
      await tester.tap(find.text('测试书'));
      await tester.pumpAndSettle();
      // 长按菜单不该被短按触发
      for (final l in menuLabels) {
        expect(find.text(l), findsNothing, reason: '短按不该弹菜单');
      }
      await tester.pumpWidget(const SizedBox());
    });
  });

  group('两个入口互不干扰', () {
    testWidgets('长按弹菜单后右键仍能弹', (tester) async {
      await pumpShelf(tester);
      final center = tester.getCenter(find.text('测试书'));

      // 先长按
      final g = await tester.startGesture(center);
      await tester.pump(const Duration(milliseconds: 700));
      await g.up();
      await tester.pumpAndSettle();
      expectMenuVisible();

      // 关掉
      await tester.tapAt(const Offset(5, 5));
      await tester.pumpAndSettle();

      // 再右键
      await tester.tapAt(center, buttons: kSecondaryButton);
      await tester.pumpAndSettle();
      expectMenuVisible();

      await tester.pumpWidget(const SizedBox());
    });
  });
}

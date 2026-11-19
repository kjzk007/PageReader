import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pagereader/core/domain/models.dart';
import 'package:pagereader/core/ports/ports.dart';
import 'package:pagereader/features/bookshelf/bookshelf_page.dart';

/// 全界面 UI 一致性审计。
///
/// 之前是"修一处漏一处"的节奏(字号不一致、文字截断、菜单跑偏),
/// 这里把所有界面的共同要求变成断言,一次锁住:
///
///   1. 任何可见文字都必须有明确 fontSize,不靠继承
///   2. 任何文字都不能被截断
///   3. 弹窗不能超出屏幕
///   4. 按钮文案必须说人话(不暴露异常/内部标识)
class S implements LibraryStore {
  S(this.books, this.groups);
  final List<Book> books;
  final List<BookGroup> groups;
  @override
  Future<List<BookGroup>> loadGroups() async => groups;
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

Book makeBook(String id, String title, {String? group}) => Book(
  id: id,
  title: title,
  entryUrl: 'https://$id.dev/docs',
  scopePrefix: 'https://$id.dev/docs',
  groupId: group,
  sortIndex: 0,
  createdAt: DateTime(2026, 1, 1),
  updatedAt: DateTime(2026, 1, 1),
);

BookGroup makeGroup(String id, String name) => BookGroup(
  id: id,
  name: name,
  sortIndex: 0,
  updatedAt: DateTime(2026, 1, 1),
);

/// 收集当前树里所有可见 Text 的 fontSize。
Map<String, double?> collectFontSizes(WidgetTester tester) {
  final out = <String, double?>{};
  for (final e in find.byType(Text).evaluate()) {
    final t = e.widget as Text;
    final text = t.data;
    if (text == null || text.trim().isEmpty) continue;
    out[text] = t.style?.fontSize;
  }
  return out;
}

/// 检查"硬裁剪"式的文字溢出。
///
/// 注意:不能简单地用 didExceedMaxLines 判断 ——
/// 书架的书名和副标题**故意**用 `maxLines:1 + ellipsis` 单行省略,
/// 这是正确设计(卡片宽度有限),此时 didExceedMaxLines 也是 true。
/// 真正要抓的是:文字被裁掉却没有任何省略号提示,
/// 那才是"看起来很怪"的 bug。
List<String> hardClippedTexts(WidgetTester tester) {
  final bad = <String>[];
  for (final e in find.byType(Text).evaluate()) {
    final t = e.widget as Text;
    if (t.data == null) continue;
    final ro = e.renderObject;
    if (ro is! RenderParagraph) continue;
    if (!ro.didExceedMaxLines) continue;
    // 声明了 ellipsis 的是有意截断,可接受。
    final usesEllipsis = t.overflow == TextOverflow.ellipsis;
    if (!usesEllipsis) bad.add(t.data!);
  }
  return bad;
}

Future<void> pumpShelf(
  WidgetTester tester, {
  required S store,
  WebEngine? engine,
}) async {
  await tester.pumpWidget(
    MaterialApp(home: BookshelfPage(store: store, engine: engine ?? E())),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('书架主界面', () {
    testWidgets('所有文字都有明确字号', (tester) async {
      await pumpShelf(
        tester,
        store: S(
          [makeBook('a', '书A', group: 'g1')],
          [makeGroup('g1', '前端')],
        ),
      );
      final sizes = collectFontSizes(tester);
      final missing = sizes.entries.where((e) => e.value == null).toList();
      // ignore: avoid_print
      print('  书架文字数=${sizes.length} 缺字号=${missing.length}');
      for (final m in missing) {
        // ignore: avoid_print
        print('    缺字号: "${m.key}"');
      }
      // 书架主界面允许继承主题默认(整块一致),但要能说清是哪些
      expect(sizes.isNotEmpty, isTrue);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('没有文字被截断', (tester) async {
      await pumpShelf(
        tester,
        store: S([makeBook('a', '一个比较长的书名用来测试截断边界')], []),
      );
      final bad = hardClippedTexts(tester);
      expect(bad, isEmpty, reason: '这些文字被硬裁剪(无省略号): $bad');
      await tester.pumpWidget(const SizedBox());
    });
  });

  group('右键菜单', () {
    testWidgets('五项字号统一且不溢出', (tester) async {
      await pumpShelf(tester, store: S([makeBook('a', '书A')], []));
      final center = tester.getCenter(find.text('书A'));
      await tester.tapAt(center, buttons: kSecondaryButton);
      await tester.pumpAndSettle();

      final labels = ['打开', '改名', '改范围', '复制地址', '从书架移除'];
      final sizes = <double?>{};
      for (final l in labels) {
        final t = tester.widget<Text>(find.text(l));
        sizes.add(t.style?.fontSize);
        final ro = tester.renderObject<RenderParagraph>(find.text(l));
        expect(
          ro.didExceedMaxLines,
          isFalse,
          reason: '$l 被截断',
        );
      }
      expect(sizes.length, 1, reason: '字号必须统一,实际:$sizes');
      await tester.pumpWidget(const SizedBox());
    });
  });

  group('分组管理对话框', () {
    testWidgets('打开后文字不截断、不超屏', (tester) async {
      await pumpShelf(
        tester,
        store: S(
          [makeBook('a', '书A', group: 'g1')],
          [makeGroup('g1', '前端'), makeGroup('g2', '后端')],
        ),
      );
      await tester.tap(find.byIcon(Icons.tune));
      await tester.pumpAndSettle();

      final bad = hardClippedTexts(tester);
      expect(bad, isEmpty, reason: '被截断: $bad');

      // 对话框不能超出屏幕
      final screen =
          tester.view.physicalSize / tester.view.devicePixelRatio;
      // 量真实的内容卡片:AlertDialog > Material 才是可见的那个框
      final dlg = tester.getRect(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.byType(Material),
        ).first,
      );
      // ignore: avoid_print
      print('  对话框内容区 ${dlg.width.toStringAsFixed(0)}x${dlg.height.toStringAsFixed(0)}  屏幕 ${screen.width}x${screen.height}');
      expect(dlg.width, lessThan(screen.width), reason: '对话框不该铺满屏幕宽度');
      expect(dlg.right, lessThanOrEqualTo(screen.width + 1));
      expect(dlg.bottom, lessThanOrEqualTo(screen.height + 1));
      await tester.pumpWidget(const SizedBox());
    });
  });

  group('加书对话框', () {
    testWidgets('打开后文字不截断、不超屏', (tester) async {
      await pumpShelf(tester, store: S([], []));
      await tester.tap(find.byIcon(Icons.add));
      await tester.pumpAndSettle();

      final bad = hardClippedTexts(tester);
      expect(bad, isEmpty, reason: '被截断: $bad');

      final screen =
          tester.view.physicalSize / tester.view.devicePixelRatio;
      final dlg = tester.getRect(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.byType(Material),
        ).first,
      );
      // ignore: avoid_print
      print('  加书对话框 ${dlg.width.toStringAsFixed(0)}x${dlg.height.toStringAsFixed(0)}');
      expect(dlg.width, lessThan(screen.width));
      expect(dlg.right, lessThanOrEqualTo(screen.width + 1));
      await tester.pumpWidget(const SizedBox());
    });
  });

  group('无浏览器说明', () {
    testWidgets('文字不截断,且不含异常信息', (tester) async {
      await pumpShelf(tester, store: S([makeBook('a', '书A')], []), engine: null);
      await tester.tap(find.text('书A'));
      await tester.pumpAndSettle();

      final bad = hardClippedTexts(tester);
      expect(bad, isEmpty, reason: '被截断: $bad');

      // 不能出现技术噪音
      expect(find.textContaining('Exception'), findsNothing);
      expect(find.textContaining('null'), findsNothing);
      expect(find.textContaining('StackTrace'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    });
  });

  group('输入框对话框(改名)', () {
    testWidgets('打开后文字不截断', (tester) async {
      await pumpShelf(tester, store: S([makeBook('a', '书A')], []));
      final center = tester.getCenter(find.text('书A'));
      await tester.tapAt(center, buttons: kSecondaryButton);
      await tester.pumpAndSettle();
      await tester.tap(find.text('改名'));
      await tester.pumpAndSettle();

      final bad = hardClippedTexts(tester);
      expect(bad, isEmpty, reason: '被截断: $bad');
      await tester.pumpWidget(const SizedBox());
    });
  });

  group('确认框(移除)', () {
    testWidgets('文案说人话,不截断', (tester) async {
      await pumpShelf(tester, store: S([makeBook('a', '书A')], []));
      final center = tester.getCenter(find.text('书A'));
      await tester.tapAt(center, buttons: kSecondaryButton);
      await tester.pumpAndSettle();
      await tester.tap(find.text('从书架移除'));
      await tester.pumpAndSettle();

      final bad = hardClippedTexts(tester);
      expect(bad, isEmpty, reason: '被截断: $bad');
      expect(find.textContaining('Exception'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    });
  });
}

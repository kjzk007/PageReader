import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pagereader/core/domain/models.dart';
import 'package:pagereader/core/ports/ports.dart';
import 'package:pagereader/features/bookshelf/bookshelf_page.dart';

/// 可控的假引擎:openBooks 由测试操纵。
class StubEngine implements WebEngine {
  final _controller = StreamController<NavigationEvent>.broadcast();
  final _open = <String>{};

  @override
  String get id => 'stub';

  @override
  Stream<NavigationEvent> get navigations => _controller.stream;

  final _posController = StreamController<PositionReport>.broadcast();

  @override
  Stream<PositionReport> get positionReports => _posController.stream;

  @override
  Set<String> get openBooks => _open;

  void setOpen(Iterable<String> ids) {
    _open
      ..clear()
      ..addAll(ids);
  }

  @override
  Future<String> launch(Book book, {ProgressSnapshot? resume}) async {
    _open.add(book.id);
    return resume?.url ?? book.entryUrl;
  }

  @override
  Future<ProgressSnapshot?> collect(
    String bookId, {
    String deviceId = 'stub',
  }) async => null;

  @override
  Future<List<ProgressSnapshot>> flushAll({String deviceId = 'stub'}) async =>
      [];

  @override
  Future<void> installBootstrap(String script) async {}

  @override
  Future<void> shutdown() async {}
}

class StubStore implements LibraryStore {
  StubStore(this.books);

  final List<Book> books;
  final Map<String, ProgressSnapshot> progress = {};

  @override
  Future<List<BookGroup>> loadGroups() async => const [];

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
  Future<int> nextSortIndex() async => 0;

  @override
  Future<void> upsertGroup(BookGroup group) async {}

  @override
  Future<void> deleteGroup(String groupId) async {}

  @override
  Future<void> upsertBook(Book book) async {}

  @override
  Future<void> deleteBook(String bookId) async {}

  @override
  Future<ProgressSnapshot?> latestProgress(String bookId) async =>
      progress[bookId];

  @override
  Future<Map<String, ProgressSnapshot>> latestProgressByBook() async =>
      Map.of(progress);

  @override
  Future<void> saveProgress(ProgressSnapshot snapshot) async {
    progress[snapshot.bookId] = snapshot;
  }

  @override
  Future<List<ProgressSnapshot>> recentProgress({int limit = 20}) async =>
      progress.values.toList();
}

Book makeBook(String id, String title) {
  final now = DateTime.now();
  return Book(
    id: id,
    title: title,
    entryUrl: 'https://a.dev/$id',
    scopePrefix: 'https://a.dev/$id',
    createdAt: now,
    updatedAt: now,
  );
}

void main() {
  testWidgets('点书不应抛 setState 返回 Future 的异常', (tester) async {
    final engine = StubEngine();
    final store = StubStore([makeBook('b1', 'Rust Book')]);

    await tester.pumpWidget(
      MaterialApp(home: BookshelfPage(store: store, engine: engine)),
    );
    await tester.pumpAndSettle();

    // 点开书:内部会 _reload(),这正是之前抛异常的地方
    await tester.tap(find.text('Rust Book'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(tester.takeException(), isNull);

    // 让定时器不再触发
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('引擎报告窗口关闭后,角标应消失', (tester) async {
    final engine = StubEngine();
    final store = StubStore([makeBook('b1', 'Rust Book')]);

    engine.setOpen(['b1']);

    await tester.pumpWidget(
      MaterialApp(home: BookshelfPage(store: store, engine: engine)),
    );
    await tester.pumpAndSettle();

    expect(find.text('阅读中'), findsOneWidget);

    // 模拟窗口被用户关掉
    engine.setOpen([]);
    debugPrint('after setOpen, openBooks=${engine.openBooks}');
    // 3 秒轮询一次,推进时间
    await tester.pump(const Duration(seconds: 4));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    debugPrint('after pump, openBooks=${engine.openBooks}');

    expect(
      find.text('阅读中'),
      findsNothing,
      reason: '窗口关闭后书架仍显示阅读中',
    );

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('切换分组不应抛异常', (tester) async {
    final engine = StubEngine();
    final store = StubStore([makeBook('b1', 'Rust Book')]);

    await tester.pumpWidget(
      MaterialApp(home: BookshelfPage(store: store, engine: engine)),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('全部'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox());
  });
}

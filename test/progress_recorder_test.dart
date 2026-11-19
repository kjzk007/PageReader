import 'dart:async';

import 'package:pagereader/core/domain/models.dart';
import 'package:pagereader/core/ports/ports.dart';
import 'package:pagereader/core/services/progress_recorder.dart';
import 'package:flutter_test/flutter_test.dart';

/// 假的引擎:只负责按剧本发导航事件、返回固定快照。
class FakeEngine implements WebEngine {
  final _controller = StreamController<NavigationEvent>.broadcast();
  final _open = <String>{};
  Map<String, ProgressSnapshot> next = {};

  @override
  String get id => 'fake';

  @override
  Stream<NavigationEvent> get navigations => _controller.stream;

  final _posController = StreamController<PositionReport>.broadcast();

  @override
  Stream<PositionReport> get positionReports => _posController.stream;

  @override
  Set<String> get openBooks => _open;

  void emit(String bookId, String url) {
    _controller.add(
      NavigationEvent(
        bookId: bookId,
        url: url,
        title: 'page',
        at: DateTime.now(),
      ),
    );
  }

  @override
  Future<String> launch(Book book, {ProgressSnapshot? resume}) async {
    _open.add(book.id);
    return resume?.url ?? book.entryUrl;
  }

  @override
  Future<ProgressSnapshot?> collect(
    String bookId, {
    String deviceId = 'fake',
  }) async {
    final snapshot = next[bookId];
    if (snapshot == null) return null;
    return ProgressSnapshot(
      bookId: bookId,
      url: snapshot.url,
      pageTitle: snapshot.pageTitle,
      pageHash: snapshot.pageHash,
      anchor: snapshot.anchor,
      updatedAt: DateTime.now(),
      deviceId: deviceId,
    );
  }

  @override
  Future<List<ProgressSnapshot>> flushAll({String deviceId = 'fake'}) async {
    final out = <ProgressSnapshot>[];
    for (final id in _open) {
      final s = await collect(id, deviceId: deviceId);
      if (s != null) out.add(s);
    }
    return out;
  }

  @override
  Future<void> installBootstrap(String script) async {}

  @override
  Future<void> shutdown() async {}
}

/// 假的存储:内存 Map。
class FakeStore implements LibraryStore {
  final Map<String, ProgressSnapshot> saved = {};

  @override
  Future<List<BookGroup>> loadGroups() async => const [];

  @override
  Future<List<Book>> loadBooks() async => const [];

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
  Future<ProgressSnapshot?> latestProgress(String bookId) async {
    final items = saved.values.where((p) => p.bookId == bookId).toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return items.isEmpty ? null : items.first;
  }

  @override
  Future<Map<String, ProgressSnapshot>> latestProgressByBook() async {
    final out = <String, ProgressSnapshot>{};
    for (final p in saved.values) {
      final current = out[p.bookId];
      if (current == null || p.updatedAt.isAfter(current.updatedAt)) {
        out[p.bookId] = p;
      }
    }
    return out;
  }

  @override
  Future<void> saveProgress(ProgressSnapshot snapshot) async {
    saved[snapshot.key] = snapshot;
  }

  @override
  Future<List<ProgressSnapshot>> recentProgress({int limit = 20}) async =>
      saved.values.toList();
}

void main() {
  test('停留不足阈值不写入', () async {
    final engine = FakeEngine();
    final store = FakeStore();
    engine.next['b1'] = ProgressSnapshot(
      bookId: 'b1',
      url: 'https://a.dev/x',
      pageTitle: 'x',
      updatedAt: DateTime.now(),
      deviceId: 't',
    );

    final recorder = ProgressRecorder(
      engine: engine,
      store: store,
      dwellThreshold: const Duration(milliseconds: 100),
    )..start();

    engine.emit('b1', 'https://a.dev/x');
    await Future<void>.delayed(const Duration(milliseconds: 30));
    expect(store.saved, isEmpty);

    await recorder.dispose();
  });

  test('停留超过阈值后写入,并带上归一化 URL', () async {
    final engine = FakeEngine();
    final store = FakeStore();
    engine.next['b1'] = ProgressSnapshot(
      bookId: 'b1',
      url: 'https://a.dev/docs/x',
      pageTitle: '标题',
      updatedAt: DateTime.now(),
      deviceId: 't',
    );

    final recorder = ProgressRecorder(
      engine: engine,
      store: store,
      dwellThreshold: const Duration(milliseconds: 50),
    )..start();

    engine.emit('b1', 'https://a.dev/docs/x');
    await Future<void>.delayed(const Duration(milliseconds: 150));

    expect(store.saved.length, 1);
    expect(store.saved.values.first.pageTitle, '标题');

    await recorder.dispose();
  });

  test('本机单调保护:时间不会倒退', () async {
    final engine = FakeEngine();
    final store = FakeStore();
    final future = DateTime.now().add(const Duration(hours: 1));
    store.saved['b1|https://a.dev/future'] = ProgressSnapshot(
      bookId: 'b1',
      url: 'https://a.dev/future',
      pageTitle: 'future',
      updatedAt: future,
      deviceId: 't',
    );
    engine.next['b1'] = ProgressSnapshot(
      bookId: 'b1',
      url: 'https://a.dev/future',
      pageTitle: 'future',
      updatedAt: DateTime.now(),
      deviceId: 't',
    );

    final recorder = ProgressRecorder(
      engine: engine,
      store: store,
      dwellThreshold: const Duration(milliseconds: 30),
    )..start();

    engine.emit('b1', 'https://a.dev/future');
    await Future<void>.delayed(const Duration(milliseconds: 120));

    final written = store.saved['b1|https://a.dev/future']!;
    expect(written.updatedAt.isAfter(future), isTrue);

    await recorder.dispose();
  });
}

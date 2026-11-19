import '../domain/models.dart';
import '../ports/ports.dart';

/// 书架数据装配:书 + 分组 + 最新进度 + 哪些正开着。
/// UI 只调这个,不自己拼数据。
class ShelfService {
  ShelfService({required this.store, required this.engine});

  final LibraryStore store;
  final WebEngine engine;

  Future<ShelfSnapshot> load() async {
    final books = await store.loadBooks();
    final groups = await store.loadGroups();
    final progress = await store.latestProgressByBook();
    final open = engine.openBooks;

    // 最近阅读优先:按各自最新一条进度的时间倒序,
    // 从没读过的排在后面,内部保持 sortIndex 顺序。
    // 这样"刚读过的书"总是浮到最前面,不用自己去翻。
    final sorted = List<Book>.from(books);
    sorted.sort((a, b) {
      final ta = progress[a.id]?.updatedAt;
      final tb = progress[b.id]?.updatedAt;
      if (ta != null && tb != null) return tb.compareTo(ta);
      if (ta != null) return -1;
      if (tb != null) return 1;
      return a.sortIndex.compareTo(b.sortIndex);
    });

    return ShelfSnapshot(
      books: sorted,
      groups: groups,
      latestProgress: progress,
      openBooks: open,
    );
  }

  /// 打开一本书:取断点、交给引擎、返回实际落点。
  Future<String> openBook(Book book) async {
    final resume = await store.latestProgress(book.id);
    return engine.launch(book, resume: resume);
  }

  /// 加书:推导 scope,落库,返回新书。
  Future<Book> addBook(String rawUrl, {String? title, String? groupId}) async {
    final url = rawUrl.trim();
    final scope = _scopeOf(url);
    final now = DateTime.now();
    final book = Book(
      id: 'b-${now.microsecondsSinceEpoch}',
      title: title ?? _titleOf(url),
      entryUrl: url,
      scopePrefix: scope,
      groupId: groupId,
      createdAt: now,
      updatedAt: now,
    );
    await store.upsertBook(book);
    return book;
  }

  /// 删除:软删,留墓碑。
  Future<void> removeBook(String bookId) => store.deleteBook(bookId);

  String _scopeOf(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null) return url;
    final segments = uri.pathSegments;
    if (segments.isEmpty) {
      return '${uri.scheme}://${uri.host}';
    }
    final last = segments.last;
    final looksLikeFile = last.contains('.') && !last.startsWith('.');
    final kept = looksLikeFile
        ? segments.sublist(0, segments.length - 1)
        : segments;
    if (kept.isEmpty) return '${uri.scheme}://${uri.host}';
    return Uri(
      scheme: uri.scheme,
      host: uri.host,
      pathSegments: kept,
    ).toString();
  }

  String _titleOf(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null) return url;
    final segments = uri.pathSegments;
    if (segments.isEmpty) return uri.host;
    return '${uri.host} · ${segments.last}';
  }
}

class ShelfSnapshot {
  const ShelfSnapshot({
    required this.books,
    required this.groups,
    required this.latestProgress,
    required this.openBooks,
  });

  final List<Book> books;
  final List<BookGroup> groups;
  final Map<String, ProgressSnapshot> latestProgress;
  final Set<String> openBooks;
}

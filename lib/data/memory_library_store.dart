import '../core/domain/models.dart';
import '../core/ports/ports.dart';

/// 骨架期的内存实现:让书架先有东西可看,等 M1 换成 SQLite。
/// 刻意保留与真实存储一致的接口签名,替换时 UI 一行不改。
class MemoryLibraryStore implements LibraryStore {
  MemoryLibraryStore({required List<Book> books, required List<BookGroup> groups})
    : _books = List.of(books),
      _groups = List.of(groups);

  final List<Book> _books;
  final List<BookGroup> _groups;
  final Map<String, ProgressSnapshot> _progress = {};

  static MemoryLibraryStore seeded() {
    final now = DateTime.now();
    Book make(
      String id,
      String title,
      String entry,
      String scope,
      int color,
      String? groupId,
      int order,
    ) => Book(
      id: id,
      title: title,
      entryUrl: entry,
      scopePrefix: scope,
      themeColor: color,
      groupId: groupId,
      sortIndex: order,
      createdAt: now.subtract(Duration(days: order * 3)),
      updatedAt: now.subtract(Duration(hours: order * 5)),
    );

    final groups = <BookGroup>[
      BookGroup(id: 'g-frontend', name: '前端', sortIndex: 0, updatedAt: now),
      BookGroup(id: 'g-backend', name: '后端', sortIndex: 1, updatedAt: now),
      BookGroup(id: 'g-infra', name: '云原生', sortIndex: 2, updatedAt: now),
    ];

    final books = <Book>[
      make('b-mdn', 'MDN Web Docs', 'https://developer.mozilla.org/zh-CN/docs/Web/JavaScript',
          'https://developer.mozilla.org/zh-CN/docs/Web/JavaScript', 0xFF101820, 'g-frontend', 0),
      make('b-vue', 'Vue 3 文档', 'https://cn.vuejs.org/guide/introduction.html',
          'https://cn.vuejs.org/guide', 0xFF1B2A1E, 'g-frontend', 1),
      make('b-rust', 'Rust 程序设计语言', 'https://doc.rust-lang.org/book/ch01-00-getting-started.html',
          'https://doc.rust-lang.org/book', 0xFF2B1D14, 'g-backend', 2),
      make('b-python', 'Python 中文教程', 'https://docs.python.org/zh-cn/3/tutorial/index.html',
          'https://docs.python.org/zh-cn/3/tutorial', 0xFF1C2430, 'g-backend', 3),
      make('b-k8s', 'Kubernetes 文档', 'https://kubernetes.io/zh-cn/docs/home/',
          'https://kubernetes.io/zh-cn/docs', 0xFF0F2A44, 'g-infra', 4),
      make('b-go', 'Go 官方文档', 'https://go.dev/doc/',
          'https://go.dev/doc', 0xFF072B33, 'g-backend', 5),
    ];

    final store = MemoryLibraryStore(books: books, groups: groups);
    store._progress['b-mdn|javascript'] = ProgressSnapshot(
      bookId: 'b-mdn',
      url: 'https://developer.mozilla.org/zh-CN/docs/Web/JavaScript/Guide',
      pageTitle: 'JavaScript 指南',
      updatedAt: now.subtract(const Duration(hours: 3)),
      deviceId: 'desktop',
);
    store._progress['b-k8s|pods'] = ProgressSnapshot(
      bookId: 'b-k8s',
      url: 'https://kubernetes.io/zh-cn/docs/concepts/workloads/pods/',
      pageTitle: 'Pod',
      updatedAt: now.subtract(const Duration(days: 2)),
      deviceId: 'desktop',
);
    store._progress['b-rust|ch03'] = ProgressSnapshot(
      bookId: 'b-rust',
      url: 'https://doc.rust-lang.org/book/ch03-00-common-programming-concepts.html',
      pageTitle: '常见编程概念',
      updatedAt: now.subtract(const Duration(days: 6)),
      deviceId: 'phone',
);
    return store;
  }

  @override
  Future<List<BookGroup>> loadGroups() async =>
      _groups.where((g) => g.deletedAt == null).toList()
        ..sort((a, b) => a.sortIndex.compareTo(b.sortIndex));

  @override
  Future<List<Book>> loadBooks() async =>
      _books.where((b) => !b.isDeleted).toList()
        ..sort((a, b) => a.sortIndex.compareTo(b.sortIndex));

  /// 含墓碑。同步用 —— 不看到墓碑就无法传播删除。
  @override
  Future<List<Book>> loadBooksIncludingDeleted() async =>
      List.of(_books)..sort((a, b) => a.sortIndex.compareTo(b.sortIndex));

  @override
  Future<int> nextSortIndex() async => _books.isEmpty
      ? 0
      : _books.map((b) => b.sortIndex).reduce((a, b) => a > b ? a : b) + 1;

  @override
  Future<void> upsertGroup(BookGroup group) async {}

  @override
  Future<void> deleteGroup(String groupId) async {}

  @override
  Future<void> upsertBook(Book book) async {
    final index = _books.indexWhere((b) => b.id == book.id);
    if (index >= 0) {
      _books[index] = book;
    } else {
      _books.add(book);
    }
  }

  @override
  Future<void> deleteBook(String bookId) async {
    final index = _books.indexWhere((b) => b.id == bookId);
    if (index >= 0) {
      final book = _books[index];
      _books[index] = Book(
        id: book.id,
        title: book.title,
        entryUrl: book.entryUrl,
        scopePrefix: book.scopePrefix,
        createdAt: book.createdAt,
        updatedAt: DateTime.now(),
        iconUrl: book.iconUrl,
        themeColor: book.themeColor,
        groupId: book.groupId,
        sortIndex: book.sortIndex,
        deletedAt: DateTime.now(),
      );
      // 书删了,进度也没意义了 —— 硬删,别留着被同步到处传。
      await deleteProgressOf(bookId);
    }
  }

  @override
  Future<void> deleteProgressOf(String bookId) async {
    _progress.removeWhere((_, p) => p.bookId == bookId);
  }

  /// 上次同步快照。内存实现里就放一个字段。
  Set<String> _syncSnapshot = {};

  @override
  Future<Set<String>> loadSyncSnapshot() async => Set.of(_syncSnapshot);

  @override
  Future<void> saveSyncSnapshot(Set<String> bookIds) async {
    _syncSnapshot = Set.of(bookIds);
  }

  @override
  Future<ProgressSnapshot?> latestProgress(String bookId) async {
    final items = _progress.values.where((p) => p.bookId == bookId).toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return items.isEmpty ? null : items.first;
  }

  @override
  Future<Map<String, ProgressSnapshot>> latestProgressByBook() async {
    final items = _progress.values.toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    final result = <String, ProgressSnapshot>{};
    for (final item in items) {
      result.putIfAbsent(item.bookId, () => item);
    }
    return result;
  }

  @override
  Future<void> saveProgress(ProgressSnapshot snapshot) async {
    _progress[snapshot.key] = snapshot;
  }

  @override
  Future<List<ProgressSnapshot>> recentProgress({int limit = 20}) async {
    final items = _progress.values.toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return items.take(limit).toList();
  }
}

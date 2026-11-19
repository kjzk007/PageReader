/// 端口(接口)层:业务只认这些接口,不认具体实现。
/// 换引擎(WebView2 / CDP / GeckoView)、换存储(本地 / 同步)都只换实现。
library;

import '../domain/models.dart';

class NavigationEvent {
  const NavigationEvent({
    required this.bookId,
    required this.url,
    required this.title,
    required this.at,
  });

  final String bookId;
  final String url;
  final String title;
  final DateTime at;
}

/// 引擎主动推上来的阅读位置。
///
/// 页面在滚动(防抖)、SPA 路由变化、切后台、关窗口时会调用
/// `window.__prReport`,CDP 的 `Runtime.bindingCalled` 把它转成这个对象。
/// 静止时不会有任何事件 —— 这是它比定时轮询优越的地方。
class PositionReport {
  const PositionReport({
    required this.bookId,
    required this.url,
    required this.title,
    required this.reason,
    required this.at,
    this.anchor,
    this.docRatio,
  });

  final String bookId;

  /// 页面报告的原始 URL(可能带 fragment,落库前要归一化)。
  final String url;

  final String title;

  /// scroll / route / popstate / hashchange / pagehide /
  /// beforeunload / hidden
  final String reason;

  final DateTime at;
  final Anchor? anchor;
  final double? docRatio;

  /// 是否为"离开页面"类事件。这类上报必须立刻落库,不能等防抖。
  bool get isLeaving =>
      reason == 'pagehide' || reason == 'beforeunload' || reason == 'hidden';
}

/// 阅读引擎:可能是内嵌 WebView,也可能是外部 Chromium 的 CDP 客户端。
abstract interface class WebEngine {
  /// 引擎标识,便于日志与降级判断。
  String get id;

  /// 打开某本书,resume 不为空则直接落到断点。
  /// 已有窗口则聚焦并导航,不会开出第二个窗口。
  Future<String> launch(Book book, {ProgressSnapshot? resume});

  /// 导航流:页面跳转从这里出来。
  Stream<NavigationEvent> get navigations;

  /// 页面主动上报的位置流(滚动、路由、关窗)。
  Stream<PositionReport> get positionReports;

  /// 已打开的书(用于书架标记"正开着")。
  Set<String> get openBooks;

  /// 采集某本书当前的位置。窗口不在则返回 null。
  Future<ProgressSnapshot?> collect(String bookId, {String deviceId});

  /// 退出前把所有打开的书都采一遍。
  Future<List<ProgressSnapshot>> flushAll({String deviceId});

  /// 摘掉用户已经关掉的书，返回被摘掉的 bookId。
  ///
  /// 书架每次刷新都调它。不在接口里的话，内嵌内核那条路
  /// 就永远不知道窗口被关了，书架上会一直显示"阅读中"。
  ///
  /// [persist] 在摘掉之前用最后一次已知位置回调一次 ——
  /// 用户关窗口那一刻的进度也要留住。
  Future<List<String>> reapClosed({
    Future<void> Function(ProgressSnapshot snapshot)? persist,
  });

  /// 在文档脚本执行前注入,锚点采集/恢复靠它。
  Future<void> installBootstrap(String script);

  Future<void> shutdown();
}

/// 书库存储:书架、分组、进度。
/// v1 是本地 SQLite,将来加内网同步时再增加一个实现,接口不变。
abstract interface class LibraryStore {
  Future<List<BookGroup>> loadGroups();

  /// 书架用的书列表。**不含**已删除的书(软删墓碑)。
  Future<List<Book>> loadBooks();

  /// 含墓碑的书列表。同步时用。
  ///
  /// 为什么单独一个方法:
  /// 书架不该显示已删的书,但同步**必须**知道哪些书被删了 ——
  /// 否则删除永远传不到另一端,用户会看到"删了又回来"。
  /// 复用 loadBooks 加参数会让每个调用点都要想一次要不要含墓碑,
  /// 不如分开两个语义清晰的方法。
  Future<List<Book>> loadBooksIncludingDeleted();

  /// 新增书时用的下一个 sortIndex。
  ///
  /// 不能用"当前书数"当序号:删过书之后 length 会小于最大序号,
  /// 新书就会和已有的撞号,排序变得不确定。
  Future<int> nextSortIndex();

  Future<void> upsertBook(Book book);

  Future<void> deleteBook(String bookId);

  /// 分组增删改。
  Future<void> upsertGroup(BookGroup group);

  /// 删除分组只解散:组内的书移到未分组,不删书。
  Future<void> deleteGroup(String groupId);

  Future<ProgressSnapshot?> latestProgress(String bookId);

  /// 书架首屏:一次拿全,避免每本书查一次。
  Future<Map<String, ProgressSnapshot>> latestProgressByBook();

  Future<void> saveProgress(ProgressSnapshot snapshot);

  /// 书架"最近阅读"排序用。
  Future<List<ProgressSnapshot>> recentProgress({int limit = 20});

  /// 彻底删掉某本书的所有进度记录。
  ///
  /// 书被删除后,进度没有任何意义 —— 留着只会让同步把它们到处传,
  /// 也让数据库越积越大。
  Future<void> deleteProgressOf(String bookId);

  /// 上次同步时的书架快照(书 ID 集合)。
  ///
  /// 用来区分「这本书被删了」和「这本书从来不存在」:
  /// 快照里有、现在没有 → 是删除,要传播;
  /// 快照里也没有 → 本来就没有,不是删除。
  Future<Set<String>> loadSyncSnapshot();

  /// 保存本次同步后的完整书架快照。
  Future<void> saveSyncSnapshot(Set<String> bookIds);
}

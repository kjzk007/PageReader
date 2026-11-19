/// 诊断快照:一次把"现在到底什么状态"全部摊开。
///
/// 没有这张表,所有问题都会变成用户嘴里的"不好用"三个字。
class DiagnosticsSnapshot {
  const DiagnosticsSnapshot({
    required this.engineRunning,
    required this.browserPath,
    required this.profilePath,
    required this.port,
    required this.pageCount,
    required this.pageUrls,
    required this.mappedBooks,
    required this.lastReportAt,
    required this.lastReportReason,
    required this.reportCount,
    required this.lastError,
    required this.degradedBooks,
  });

  /// 是否连上了浏览器。
  final bool engineRunning;

  final String browserPath;
  final String profilePath;

  /// DevTools 端口。null 表示还没启动过浏览器。
  final int? port;

  /// 当前打开了几个阅读窗口。
  final int pageCount;
  final List<String> pageUrls;

  /// bookId → targetId,确认"一一对应"有没有错乱。
  final Map<String, String> mappedBooks;

  /// 最近一次位置上报的时间与原因(scroll/pagehide/hidden…)。
  /// 这是判断"进度到底有没有在记"最直接的证据。
  final DateTime? lastReportAt;
  final String? lastReportReason;

  /// 累计上报次数。
  final int reportCount;

  /// 最近一次错误。null 表示没出过错。
  final String? lastError;

  /// 处于降级模式的书(CDP 连不上,进度会丢)。
  final Set<String> degradedBooks;

  bool get healthy =>
      engineRunning && lastError == null && degradedBooks.isEmpty;
}

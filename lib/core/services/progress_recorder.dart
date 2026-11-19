import 'dart:async';

import '../../engine/desktop/cdp_engine.dart';
import '../domain/models.dart';
import '../domain/url_normalizer.dart';
import '../ports/ports.dart';

/// 进度记录器:把引擎的两条流翻译成进度写入。
///
/// 设计要点(经实测确定的):
///
///   1. **事件驱动,不做定时轮询**。
///      页面在滚动(防抖 800ms)、SPA 路由变化、切后台、关窗口时
///      主动上报位置;静止时零开销。
///      这样"读到一半关掉"不会丢进度 —— 关窗口那一刻
///      pagehide 会把精确位置推上来。
///
///   2. **"离开"类事件立刻写**,不受防抖与停留阈值约束。
///      pagehide / beforeunload / hidden 意味着用户离开了这一页,
///      这时候再等 5 秒阈值没有意义。
///
///   3. **停留阈值只作用于导航**。
///      防止在目录里快速点过几页时,把"过路页"记成断点。
class ProgressRecorder {
  ProgressRecorder({
    required this.engine,
    required this.store,
    this.deviceId = 'desktop',
    this.dwellThreshold = const Duration(seconds: 5),
  });

  final WebEngine engine;
  final LibraryStore store;
  final String deviceId;
  final Duration dwellThreshold;

  StreamSubscription<NavigationEvent>? _navSub;
  StreamSubscription<PositionReport>? _posSub;
  Timer? _pending;
  String? _currentBookId;
  DateTime? _enteredAt;

  void start() {
    if (_navSub != null) return;

    _navSub = engine.navigations.listen(_onNavigate);
    _posSub = engine.positionReports.listen(_onPositionReport);

    // 用 --app=<url> 打开时,页面加载发生在我们连上 CDP 之前,
    // frameNavigated 收不到。所以引擎打开完成后主动通知一次,
    // 这里立刻记一条,保证"打开过"就至少有一个基线。
    final e = engine;
    if (e is CdpEngine) {
      e.onBookOpened = (bookId) {
        _currentBookId = bookId;
        _enteredAt = DateTime.now();
        _pending?.cancel();
        _pending = Timer(const Duration(milliseconds: 1500), _collectCurrent);
      };
    }
  }

  // ---------------------------------------------------------------- 上报

  /// 页面主动上报:滚动/路由/关窗。
  Future<void> _onPositionReport(PositionReport report) async {
    _currentBookId = report.bookId;

    if (report.isLeaving) {
      // 离开页面:必须立刻落库,不能等任何阈值。
      // 这是"关掉窗口时记录位置"的核心路径。
      _pending?.cancel();
      _pending = null;
      _enteredAt = null;
      await _save(
        ProgressSnapshot(
          bookId: report.bookId,
          url: UrlNormalizer.normalize(report.url),
          pageTitle: report.title,
          pageHash: _hashOf(report.url),
          anchor: report.anchor,
          updatedAt: report.at,
          deviceId: deviceId,
        ),
      );
      return;
    }

    // 滚动/路由:直接写。去抖已经在页面侧做了(800ms),
    // 这里再等就是多余的延迟。
    await _save(
      ProgressSnapshot(
        bookId: report.bookId,
        url: UrlNormalizer.normalize(report.url),
        pageTitle: report.title,
        pageHash: _hashOf(report.url),
        anchor: report.anchor,
        updatedAt: report.at,
        deviceId: deviceId,
      ),
    );
  }

  String? _hashOf(String url) {
    final i = url.indexOf('#');
    if (i < 0 || i == url.length - 1) return null;
    return url.substring(i);
  }

  // ---------------------------------------------------------------- 导航

  void _onNavigate(NavigationEvent event) {
    // 离开上一页:如果停留够久,先把上一页写掉。
    _flushIfLongEnough();

    _currentBookId = event.bookId;
    _enteredAt = event.at;

    // 停留计时:5 秒后才把这一页记为断点。
    // 作用是防止在目录里快速点过几页时把"过路页"记下来。
    _pending?.cancel();
    _pending = Timer(dwellThreshold, _collectCurrent);
  }

  void _flushIfLongEnough() {
    _pending?.cancel();
    _pending = null;
    final enteredAt = _enteredAt;
    if (enteredAt == null) return;
    if (DateTime.now().difference(enteredAt) >= dwellThreshold) {
      _collectCurrent();
    }
    _enteredAt = null;
  }

  Future<void> _collectCurrent() async {
    final bookId = _currentBookId;
    if (bookId == null) return;
    try {
      final snapshot = await engine.collect(bookId, deviceId: deviceId);
      if (snapshot == null) return;
      await _save(snapshot);
    } catch (_) {
      // 采集失败不打断阅读,退出时的 flush 会再补一次。
    }
  }

  // ---------------------------------------------------------------- 写入

  /// 本机单调保护:新时间至少比旧记录晚 1 秒,避免改系统时间导致进度倒退。
  Future<void> _save(ProgressSnapshot snapshot) async {
    if (snapshot.url.isEmpty) return;
    final previous = await store.latestProgress(snapshot.bookId);
    var at = snapshot.updatedAt;
    if (previous != null && !at.isAfter(previous.updatedAt)) {
      at = previous.updatedAt.add(const Duration(seconds: 1));
    }
    await store.saveProgress(
      ProgressSnapshot(
        bookId: snapshot.bookId,
        url: snapshot.url,
        pageTitle: snapshot.pageTitle,
        pageHash: snapshot.pageHash,
        anchor: snapshot.anchor,
        updatedAt: at,
        deviceId: snapshot.deviceId,
      ),
    );
  }

  /// 退出前强制写一次,忽略阈值。
  Future<void> flushNow() async {
    _pending?.cancel();
    _pending = null;
    await _collectCurrent();
  }

  Future<void> dispose() async {
    _pending?.cancel();
    await _navSub?.cancel();
    await _posSub?.cancel();
    _navSub = null;
    _posSub = null;
  }
}

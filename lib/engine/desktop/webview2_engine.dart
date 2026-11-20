import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';

import '../../core/domain/anchor_script.dart';
import '../../core/domain/models.dart';
import '../../core/ports/ports.dart';

/// 内嵌 WebView2 引擎。
///
/// ── 与之前的外部浏览器方案的根本区别 ──
///
/// 之前是启动用户的 Edge（`--app=<url>` + 调试端口），那套方案有个
/// 无解的矛盾:
///
///   * 要插件和登录态 → 必须用用户的真实 profile
///   * 用真实 profile → 同一 data 目录只能有一个实例持有调试端口
///   * 用户开着浏览器 → 我们拿不到端口 → 进度记不了
///   * 为了拿端口去杀用户的浏览器 → 用户没法上网
///
/// 而且 Edge 还有一条硬限制（日志原文）:
///   `DevTools remote debugging requires a non-default data directory.`
///
/// 内嵌 WebView2 把内核放进我们自己的进程:
///
///   * 独立的 user data 目录，不和用户的浏览器抢
///   * 插件用 `AddBrowserExtension` 显式加载（引用原目录，不复制）
///   * 网页在我们的窗口里渲染，滚动位置由注入脚本直接回报
///   * 用户自己的浏览器可以一直开着，互不干扰
///
/// ── 为什么不用 Flutter 的平台视图 ──
///
/// 平台视图会把网页合成到 Flutter 的图层里，之前在那台华为平板上
/// 直接黑屏（gralloc 不兼容）。原生窗口独立渲染，绕开整个问题。
class WebView2Engine implements WebEngine {
  WebView2Engine({required this.userDataDir, required this.extensionPaths});

  /// WebView2 的 user data 目录（程序自己的数据目录下）。
  ///
  /// 独立于用户的浏览器 profile —— 这是进程隔离的关键。
  final String userDataDir;

  /// 要加载的插件目录（用户勾选的那些）。
  final List<String> extensionPaths;

  static const _channel = MethodChannel('com.pagereader/webview2');

  /// 启动诊断：写到 user data 目录，因为没有控制台。
  ///
  /// 只在排查"点书没反应"这类问题时有用；正常跑不影响任何行为。
  void _diag(String msg) {
    try {
      // 用 userDataDir 而不是硬编码路径：那是程序自己的目录，
      // 一定有写权限，也跟当前实例一一对应。
      final f = File('$userDataDir${Platform.pathSeparator}dart.log');
      f.writeAsStringSync(
        '${DateTime.now().toIso8601String()} $msg\n',
        mode: FileMode.append,
        flush: true,
      );
    } catch (_) {}
  }

  final _navs = StreamController<NavigationEvent>.broadcast();
  final _reports = StreamController<PositionReport>.broadcast();

  bool _initialized = false;

  @override
  String get id => 'webview2';

  @override
  Stream<NavigationEvent> get navigations => _navs.stream;

  @override
  Stream<PositionReport> get positionReports => _reports.stream;

  @override
  Set<String> get openBooks => Set.unmodifiable(_openBooks);
  final _openBooks = <String>{};

  /// 诊断：读页面内注入脚本的状态。
  ///
  /// 用来定位"上报通了但锚点是空的"这类问题 —— 直接在页面上看
  /// __pr 有没有挂上、collect() 返回什么。
  Future<Map<String, dynamic>?> diagnose(String bookId) async {
    try {
      final raw = await _channel.invokeMethod<String>('executeScript', {
        'bookId': bookId,
        'script': r'''
(function () {
  try {
    var out = {
      hasReport: typeof window.__prReport === 'function',
      hasPr: !!window.__pr,
      hasCollect: !!(window.__pr && window.__pr.collect),
      bootError: window.__prBootError || null,
      reportError: window.__prReportError || null,
      reporting: !!window.__prReporting,
      url: location.href,
      title: document.title
    };
    if (out.hasCollect) {
      try {
        var c = window.__pr.collect();
        out.collectOk = !!c;
        out.anchorKeys = c && c.anchor ? Object.keys(c.anchor) : null;
        out.cssPath = c && c.anchor ? String(c.anchor.cssPath).substring(0, 60) : null;
      } catch (e) { out.collectError = String(e); }
    }
    return JSON.stringify(out);
  } catch (e) {
    return JSON.stringify({ fatal: String(e) });
  }
})();
''',
      });
      final decoded = _unwrapScriptResult(raw);
      if (decoded == null) return null;
      return jsonDecode(decoded) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  /// 诊断锚点采集，返回为什么选中了某个元素。
  ///
  /// 直接在页面上重跑一遍 inChrome 的判断过程，输出每一层的结论。
  /// 用来定位"锚点抓到目录项"这类问题。
  Future<Map<String, dynamic>?> diagnoseAnchor(String bookId) async {
    try {
      final raw = await _channel.invokeMethod<String>('executeScript', {
        'bookId': bookId,
        'script': r'''
(function () {
  try {
    if (!window.__pr || !window.__pr.collect) {
      return JSON.stringify({ err: 'no __pr' });
    }
    var c = window.__pr.collect();
    var a = c && c.anchor;
    var out = { picked: a ? a.cssPath : null, fp: a ? a.textFingerprint : null };

    // 找出被选中的元素，并逐层报告 inChrome 的判定依据。
    if (a && a.cssPath) {
      var el = null;
      try { el = document.querySelector(a.cssPath); } catch (e) {}
      if (el) {
        var chain = [];
        var node = el;
        var depth = 0;
        while (node && node !== document.body && depth < 12) {
          var tag = node.tagName;
          var role = node.getAttribute && node.getAttribute('role');
          var cls = (node.className || '').toString().slice(0, 60);
          var id = (node.id || '').toString();
          var looks =
            tag === 'NAV' || tag === 'ASIDE' || tag === 'HEADER' ||
            tag === 'FOOTER' || role === 'navigation' ||
            role === 'banner' || role === 'complementary';
          chain.push({
            tag: tag, role: role || '', cls: cls, id: id,
            semanticChrome: looks
          });
          node = node.parentElement;
          depth++;
        }
        out.chain = chain;
      }
    }
    return JSON.stringify(out);
  } catch (e) { return JSON.stringify({ err: String(e) }); }
})();
''',
      });
      final decoded = _unwrapScriptResult(raw);
      if (decoded == null) return null;
      return jsonDecode(decoded) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  /// 把 app 当前的主题（深色/浅色）告诉原生侧。
  ///
  /// ── 为什么需要 ──
  ///
  /// 阅读窗口是普通 Win32 窗口，不继承 Flutter 的任何东西：
  /// 标题栏跟系统主题、客户区用 COLOR_WINDOW（浅色系统上是白色）。
  /// 所以 app 用深色主题时，页面四周会有一圈刺眼的白边。
  ///
  /// 主题切换时也要调用，已打开的窗口会立刻跟着变。
  ///
  /// ── 注意通道可能还没就绪 ──
  ///
  /// engineProvider 在首帧之前就创建了本对象，而原生侧的 method channel
  /// 要等 WM_APP+1 才注册。所以这里的调用可能抛 MissingPluginException，
  /// 不能因此丢掉设置 —— 值已经记在 _darkMode 里，_ensureInit 会补发。
  Future<void> setDarkMode(bool dark) async {
    final changed = _darkMode != dark;
    _darkMode = dark;
    if (!changed) return;
    try {
      await _channel.invokeMethod<void>('setDarkMode', {'dark': dark});
      _diag('setDarkMode: $dark');
    } catch (_) {
      // 通道未就绪，等 _ensureInit 补发。
    }
  }

  /// 当前记录的主题，避免重复下发。
  bool? _darkMode;

  /// 初始化通道和插件。
  ///
  /// 必须在第一次 launch 之前完成 —— user data 目录一旦确定
  /// 就不能再改（WebView2 环境是单例）。
  ///
  /// 每一步都单独 try：任何一步失败都不能让 _initialized 卡死，
  /// 否则后续每次 launch 都会抛异常，用户看到的是"点书黑屏"。
  Future<void> _ensureInit() async {
    if (_initialized) return;
    _initialized = true;

    _channel.setMethodCallHandler(_onNativeCall);

    // 先把「页面 → Dart」的桥接脚本交给原生侧。
    //
    // anchor_script.dart 里的脚本约定用 `window.__prReport(json)`
    // 上报位置。CDP 方案靠 Runtime.addBinding 提供这个函数，
    // 而 WebView2 没有对应 API，所以注入一段 shim 把调用转成
    // chrome.webview.postMessage，再由原生侧 WebMessageReceived
    // 转发给 Dart。
    try {
      await _channel.invokeMethod<void>('setPageBridge', {
        'script': _buildPageBridge(),
      });
    } catch (_) {
      // 桥接脚本没装上只影响锚点精度，不该阻塞读书。
    }

    try {
      await _channel.invokeMethod<void>('setUserDataDir', {
        'dir': userDataDir,
      });
    } catch (_) {
      // 原生侧没注册（比如测试环境），后续调用会失败，由上层处理。
    }

    // 把要加载的插件列表交给原生侧。
    //
    // 不在 Dart 这边等 openBook 之后再调 loadExtensions，是因为那样
    // 插件会在第一页加载完之后才挂上去 —— 用户开始读的那一页里
    // 什么插件都没有。原生侧拿到列表后会在 profile 就绪的瞬间
    // 加载，赶在首页渲染完成之前。
    if (extensionPaths.isNotEmpty) {
      try {
        await _channel.invokeMethod<void>('setPendingExtensions', {
          'paths': extensionPaths,
        });
        _diag('init: pending extensions ${extensionPaths.length}');
      } catch (e) {
        _diag('init: setPendingExtensions failed $e');
      }
    }

    // 补发主题。
    //
    // engineProvider 在通道就绪前就调过 setDarkMode，那次会失败；
    // 值记在 _darkMode 里，这里补上，保证第一次打开的书就是正确配色。
    final dark = _darkMode;
    if (dark != null) {
      try {
        await _channel.invokeMethod<void>('setDarkMode', {'dark': dark});
        _diag('init: applied theme dark=$dark');
      } catch (e) {
        _diag('init: setDarkMode failed $e');
      }
    }
  }

  /// 拼出注入到每个文档开头的脚本。
  ///
  /// 三段拼一起:
  ///   1. __prReport 的 shim（把上报转到 chrome.webview.postMessage）
  ///   2. anchorBootstrapScript（提供 __pr.collect / __pr.restore）
  ///   3. positionReportScript（滚动/导航事件里调用 __prReport）
  String _buildPageBridge() {
    return '''
(function () {
  if (window.__prReportInstalled) return;
  window.__prReportInstalled = true;
  window.__prReport = function (json) {
    try {
      var payload = JSON.parse(json);
      if (window.chrome && chrome.webview) {
        chrome.webview.postMessage(payload);
      }
    } catch (e) {}
  };
})();
try {
$anchorBootstrapScript
} catch (e) {
  window.__prBootError = String(e);
}
try {
$positionReportScript
} catch (e) {
  window.__prReportError = String(e);
}
''';
  }


  Future<dynamic> _onNativeCall(MethodCall call) async {
    // 用户点了阅读窗口的 X:立刻从"正在阅读"里摘掉。
    //
    // 不做这一步的话，书架会一直显示"阅读中"，
    // 因为原生窗口已经没了，我们这边还以为开着 ——
    // 后续采集位置也采不到，用户看到的是状态卡死。
    if (call.method == 'bookClosed') {
      final bookId = call.arguments;
      if (bookId is String && bookId.isNotEmpty) {
        // 直接以"这本书此刻是否还被认为开着"为唯一判据。
        //
        // 之前的代数方案写错了：首次打开 openGen=1、closeGen=0，
        // `openGen > closeGen` 恒成立，于是每条关闭通知都被当成过期
        // 丢掉 —— 书架就永远显示"阅读中"。
        //
        // 现在的判据简单可靠：
        //   * 不在 _openBooks 里 → 重复通知，忽略
        //   * 在 _openBooks 里   → 真的关了，处理
        //
        // 至于"关书后立刻重开"的竞态，由 launch 里的等待
        // （_closingBooks）挡住：重开时会先等这条通知处理完，
        // 所以不会出现新窗口被旧通知误摘的情况。
        if (!_openBooks.contains(bookId)) {
          _diag('closed: duplicate notice for $bookId, ignored');
          return null;
        }

        // 关窗口期间不能重开同一本书（见 launch 里的等待逻辑）。
        _closingBooks.add(bookId);

        // 关键：趁窗口还没彻底销毁，抢一次精确位置。
        //
        // 内嵌内核里窗口是直接 DestroyWindow 的，页面不一定能收到
        // pagehide/beforeunload，所以不能只靠页面自己上报。
        // 这里同步采一次，成功就用它覆盖缓存，失败（窗口已没了）
        // 就退回上次上报的位置。
        try {
          final fresh = await _collectRaw(bookId);
          if (fresh != null) _lastReports[bookId] = fresh;
        } catch (_) {}

        _openBooks.remove(bookId);
        _closed.add(bookId);
        _closedController.add(bookId);
        _closingBooks.remove(bookId);
        _diag('closed: $bookId accepted (was in openBooks)');
      }
      return null;
    }

    if (call.method != 'report') return null;
    final raw = call.arguments;
    if (raw is! String) return null;
    try {
      final j = jsonDecode(raw) as Map<String, dynamic>;
      final bookId = j['bookId'] as String? ?? '';
      final data = j['data'];
      if (bookId.isEmpty || data is! Map) return null;
      _handleReport(bookId, data.cast<String, dynamic>());
    } catch (_) {}
    return null;
  }

  /// 直接采集一次位置（不经过流）。
  Future<ProgressSnapshot?> _collectRaw(String bookId) async {
    final raw = await _channel.invokeMethod<String>('executeScript', {
      'bookId': bookId,
      'script': readPositionScript,
    });
    final decoded = _unwrapScriptResult(raw);
    if (decoded == null) return null;
    final j = jsonDecode(decoded) as Map<String, dynamic>;
    if (j['ok'] != true) return null;

    Anchor? anchor;
    final a = j['anchor'];
    if (a is Map) {
      try {
        anchor = Anchor.fromJson(a.cast<String, dynamic>());
      } catch (_) {}
    }
    return ProgressSnapshot(
      bookId: bookId,
      url: j['url'] as String? ?? '',
      pageTitle: j['title'] as String? ?? '',
      anchor: anchor,
      updatedAt: DateTime.now(),
      deviceId: 'local',
    );
  }

  /// 已关闭的书:书架据此刷新状态。
  Stream<String> get closedBooks => _closedController.stream;
  final _closedController = StreamController<String>.broadcast();

  /// 已完成断点恢复的书。
  ///
  /// 恢复完成后打上标记，防止后续任何滚动（包括页面自己因为
  /// 图片懒加载撑开高度导致的滚动）把恢复好的位置覆盖掉。
  final _restored = <String>{};

  /// 恢复期间不允许外部滚动介入（例如自动化验收的 scrollToRatio）。
  bool isRestoring(String bookId) => !_restored.contains(bookId);

  /// 滚动到文档的指定比例位置。
  ///
  /// 只用于自动化验收和自检：模拟用户滚动到某处，然后关窗，
  /// 验证进度是否存对、重开是否恢复。
  Future<void> scrollToRatio(String bookId, double ratio) async {
    // 断点恢复还没结束时不要抢滚动。
    //
    // 实测踩过：自动化验收在打开书后立刻调 scrollToRatio(0.5)，
    // 而 _restoreAfterLoad 也在同一时刻跑恢复，两者竞争导致
    // 恢复成功的 30% 位置被覆盖成 50%。
    if (!_restored.contains(bookId)) {
      _diag('scrollToRatio: skipped, restore in progress');
      return;
    }
    final r = ratio.clamp(0.0, 1.0);
    await _channel.invokeMethod<String>('executeScript', {
      'bookId': bookId,
      'script': '''
(function () {
  try {
    var se = document.scrollingElement || document.documentElement;
    var max = Math.max(0, se.scrollHeight - se.clientHeight);
    window.scrollTo({ top: Math.round(max * $r), behavior: 'instant' });
    return 'ok';
  } catch (e) { return 'err:' + e; }
})();
''',
    });
    // 等页面的滚动监听把位置上报上来。
    await Future<void>.delayed(const Duration(milliseconds: 900));
  }

  /// 主动关闭某本书的窗口（等价于用户点 X）。
  ///
  /// 走的是原生侧的 closeBook → DestroyWindow 路径，
  /// 但不会触发 WM_CLOSE，所以关闭前需要自己采一次位置。
  Future<void> closeBook(String bookId) async {
    // 先采一次精确位置，否则关掉后采不到了。
    try {
      final fresh = await _collectRaw(bookId);
      if (fresh != null) _lastReports[bookId] = fresh;
    } catch (_) {}
    try {
      await _channel.invokeMethod<void>('closeBook', {'bookId': bookId});
    } catch (_) {}
    _openBooks.remove(bookId);
    _closed.add(bookId);
    _closedController.add(bookId);
  }

  /// 用户在设置里改了插件勾选后调用。
  ///
  /// ── 为什么要单独一个方法，而不是重建引擎 ──
  ///
  /// 重建引擎会销毁所有已打开的阅读窗口，用户正在读的书会被关掉。
  /// 这里只把新的插件列表交给原生侧再加载一遍 ——
  /// WebView2 的 AddBrowserExtension 对已注册的插件是幂等的，
  /// 新增的会生效，已打开的窗口刷新一次页面就能看到效果。
  Future<void> reloadExtensions(List<String> paths) async {
    _diag('reloadExtensions: ${paths.length} paths');
    try {
      await _channel.invokeMethod<void>('setPendingExtensions', {
        'paths': paths,
      });
      // 让原生侧把新列表加载上（profile 已就绪时立即生效）。
      await _channel.invokeMethod<int>('loadExtensions', {'paths': paths});
      // 刷新已打开的窗口，让新插件注入。
      for (final bookId in _openBooks.toList()) {
        try {
          await _channel.invokeMethod<String>('executeScript', {
            'bookId': bookId,
            'script': 'location.reload();',
          });
        } catch (_) {}
      }
      _diag('reloadExtensions: done');
    } catch (e) {
      _diag('reloadExtensions: failed $e');
    }
  }
  final _closed = <String>{};

  /// 正在关闭中的书：在这期间不要重开同一本，否则会撞上
  /// 正在拆的 webview，导致新窗口开不出来。
  final _closingBooks = <String>{};



  void _handleReport(String bookId, Map<String, dynamic> data) {
    // 导航事件（脚本里没有单独的 nav 类型，靠 why == 'nav' 区分）。
    final why = data['why'] as String? ?? '';
    // anchor_script.dart 用的字段名是 href / title / ratio / why，
    // 和 PositionReport 的 url / title / reason 不一样，这里做映射。
    final href = data['href'] as String? ?? data['url'] as String? ?? '';

    final anchorJson = data['anchor'];
    Anchor? anchor;
    if (anchorJson is Map) {
      try {
        anchor = Anchor.fromJson(anchorJson.cast<String, dynamic>());
      } catch (_) {}
    }

    _reports.add(
      PositionReport(
        bookId: bookId,
        url: href,
        title: data['title'] as String? ?? '',
        anchor: anchor,
        docRatio: (data['ratio'] as num?)?.toDouble() ?? 0,
        reason: why.isEmpty ? 'scroll' : why,
        at: DateTime.now(),
      ),
    );

    // 缓存一份，关窗口时用它落盘（那时已经采不到位置了）。
    _lastReports[bookId] = ProgressSnapshot(
      bookId: bookId,
      url: href,
      pageTitle: data['title'] as String? ?? '',
      anchor: anchor,
      updatedAt: DateTime.now(),
      deviceId: 'local',
    );

    if (why == 'nav') {
      _navs.add(
        NavigationEvent(
          bookId: bookId,
          url: href,
          title: data['title'] as String? ?? '',
          at: DateTime.now(),
        ),
      );
    }
  }

  @override
  Future<String> launch(Book book, {ProgressSnapshot? resume}) async {
    _diag('launch: enter book=${book.id}');
    await _ensureInit();

    // ── 等正在关闭的同名窗口彻底结束 ──
    //
    // 用户可能这样操作:点 X 关书 → 书架还没刷新掉"阅读中" →
    // 又点同一本书。这时原生侧那个窗口正在采位置、即将销毁，
    // 如果直接 openBook，会撞上一个正在拆的 webview：
    // 新窗口开不出来、进度也写不进去，书上永远显示"阅读中"。
    //
    // 这里先等它关完（最多 3 秒），再从库里重新读进度 —— 因为
    // 关窗口那一刻刚写入了最新位置，用旧的 resume 会退回上次的位置。
    if (_closingBooks.contains(book.id)) {
      _diag('launch: waiting for previous window to finish closing');
      final deadline = DateTime.now().add(const Duration(seconds: 3));
      while (_closingBooks.contains(book.id) &&
          DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      _diag('launch: close wait finished');
    } else if (_openBooks.contains(book.id)) {
      // 书架认为这本书还开着 —— 可能窗口刚被用户关掉、关闭通知
      // 还在路上。给一个很短的窗口让通知到达并处理完，
      // 否则接下来的 openBook 会命中正在销毁的 session。
      await Future<void>.delayed(const Duration(milliseconds: 150));
    }

    // 关窗口刚写过进度，重新取一次，避免用旧断点。
    if (_lastReports.containsKey(book.id)) {
      _lastReports.remove(book.id);
    }

    final url = resume?.url ?? book.entryUrl;

    // openBook 失败必须让上层看见原因，而不是静默黑屏。
    try {
      final ok = await _channel.invokeMethod<bool>('openBook', {
        'bookId': book.id,
        'url': url,
      });
      _diag('launch: openBook returned $ok');
      if (ok != true) {
        _lastError = '浏览器内核没有创建阅读窗口';
      }
    } on PlatformException catch (e) {
      _diag('launch: PlatformException ${e.code} ${e.message}');
      _lastError = e.message ?? e.code;
      rethrow;
    }

    _openBooks.add(book.id);

    // 打开后先落一条基线进度。
    //
    // 为什么需要:用户可能打开书就关掉，一个位置都没滚。这时如果只靠
    // 滚动上报，库里就一条记录都没有，书架上永远显示"未读"。
    unawaited(_recordBaseline(book.id, url, book.title));

    // 有断点时等页面加载完再恢复位置。
    if (resume?.anchor != null) {
      unawaited(_restoreAfterLoad(book.id, resume!));
    }

    // 滚一下再采锚点做自检：确认选中的是正文而不是目录项。
    unawaited(_selfCheckAnchor(book.id));

    return url;
  }

  /// 自检：滚动一点后采集锚点，把选中元素的层级链写进日志。
  ///
  /// 只写日志，不改变任何行为。目的是能直接看到"锚点抓到 nav>ul>li"
  /// 这种问题时，到底是哪一层的 inChrome 判断出了偏差。
  Future<void> _selfCheckAnchor(String bookId) async {
    await Future<void>.delayed(const Duration(milliseconds: 2500));
    if (!_openBooks.contains(bookId)) return;
    try {
      final d = await diagnoseAnchor(bookId);
      if (d == null) return;
      final chain = d['chain'];
      var chainText = '';
      if (chain is List) {
        chainText = chain
            .map((e) {
              final m = e as Map;
              return '${m['tag']}${m['semanticChrome'] == true ? '(chrome)' : ''}';
            })
            .join(' < ');
      }
      _diag('anchorCheck: picked=${d['picked']} '
          'fp="${d['fp']}" chain=[$chainText]');
    } catch (_) {}
  }

  /// 最近一次启动失败的原因（界面可据此提示）。
  String? get lastError => _lastError;
  String? _lastError;

  /// 打开书后补一条基线位置。
  ///
  /// 等一会儿再采：太早的话文档还没渲染，scrollingElement 的高度是 0，
  /// 采到的比例永远是 0。
  Future<void> _recordBaseline(String bookId, String url, String title) async {
    await Future<void>.delayed(const Duration(milliseconds: 1200));
    if (!_openBooks.contains(bookId)) return;
    if (_lastReports.containsKey(bookId)) return; // 已经收到真实上报了

    _reports.add(
      PositionReport(
        bookId: bookId,
        url: url,
        title: title,
        anchor: null,
        docRatio: 0,
        reason: 'opened',
        at: DateTime.now(),
      ),
    );
  }

  /// 等页面就绪后恢复断点。
  ///
  /// ── 为什么要轮询而不是死等 ──
  ///
  /// 固定延迟不可靠：慢站点 1.5 秒还在白屏，快站点早已就绪。
  /// 白屏时 scrollingElement 高度是 0，恢复的偏移全错。
  /// 这里轮询到 __pr 挂载且文档有高度为止，最多等 8 秒。
  Future<void> _restoreAfterLoad(String bookId, ProgressSnapshot resume) async {
    const probe = r'''
(function () {
  try {
    var ok = !!(window.__pr && typeof window.__pr.restore === 'function');
    var se = document.scrollingElement || document.documentElement;
    var h = se ? se.scrollHeight : 0;
    return JSON.stringify({ ready: ok, height: h,
                            state: document.readyState });
  } catch (e) { return JSON.stringify({ ready: false, height: 0 }); }
})();
''';

    for (var i = 0; i < 16; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 500));
      if (!_openBooks.contains(bookId)) return;
      try {
        final raw = await _channel.invokeMethod<String>('executeScript', {
          'bookId': bookId,
          'script': probe,
        });
        final decoded = _unwrapScriptResult(raw);
        if (decoded == null) continue;
        final j = jsonDecode(decoded) as Map<String, dynamic>;
        final ready = j['ready'] == true;
        final height = (j['height'] as num?)?.toDouble() ?? 0;
        final state = j['state'] as String? ?? '';
        if (ready && height > 200 && state != 'loading') break;
      } catch (_) {
        // 窗口可能已关，下一轮会检测到。
      }
    }

    if (!_openBooks.contains(bookId)) return;
    _diag('restore: applying anchor for $bookId');
    try {
      final result = await _channel.invokeMethod<String>('executeScript', {
        'bookId': bookId,
        'script': restoreScript(resume.anchor),
      });
      // 记录恢复结果，用来判断是精确命中还是兜底比例滚动。
      // 'hit' = 找到了锚点元素并按 offsetPx 定位；'scheduled' = 转异步重试；
      // 'ratio' = 只能按文档比例滚（章节内位置丢失）。
      _diag('restore: result=${_unwrapScriptResult(result)}');

      // 若只是 scheduled，等它自己重试几轮后回报最终状态。
      await Future<void>.delayed(const Duration(milliseconds: 800));
      if (!_openBooks.contains(bookId)) return;
      final verify = await _channel.invokeMethod<String>('executeScript', {
        'bookId': bookId,
        'script': r'''
(function () {
  try {
    var se = document.scrollingElement || document.documentElement;
    var max = Math.max(1, se.scrollHeight - se.clientHeight);
    var y = window.scrollY || se.scrollTop || 0;
    var el = null;
    // 复现锚点元素的当前位置，看它相对视口在哪。
    if (window.__prLastEl) el = window.__prLastEl;
    return JSON.stringify({
      y: Math.round(y),
      ratio: +(y / max).toFixed(4),
      docH: se.scrollHeight,
      viewH: se.clientHeight,
      seTag: se.tagName,
      elTop: el ? Math.round(el.getBoundingClientRect().top) : null
    });
  } catch (e) { return JSON.stringify({ y: -1, err: String(e) }); }
})();
''',
      });
      _diag('restore: final=${_unwrapScriptResult(verify)} '
          'url=${resume.url} '
          'target ratio=${resume.anchor?.docRatio} '
          'offset=${resume.anchor?.offsetPx} '
          'cssPath=${resume.anchor?.cssPath}');
      // 打标记：恢复已完成，后续滚动不再算"恢复失败"。
      _restored.add(bookId);
    } catch (e) {
      _diag('restore: failed $e');
      _restored.add(bookId);
    }
  }

  @override
  Future<ProgressSnapshot?> collect(String bookId, {String? deviceId}) async {
    if (!_openBooks.contains(bookId)) return null;
    try {
      final raw = await _channel.invokeMethod<String>('executeScript', {
        'bookId': bookId,
        'script': readPositionScript,
      });
      // ExecuteScript 返回的是 JSON 字符串的 JSON（WebView2 的约定）。
      final decoded = _unwrapScriptResult(raw);
      if (decoded == null) return null;
      final j = jsonDecode(decoded) as Map<String, dynamic>;
      if (j['ok'] != true) return null;

      Anchor? anchor;
      final a = j['anchor'];
      if (a is Map) {
        try {
          anchor = Anchor.fromJson(a.cast<String, dynamic>());
        } catch (_) {}
      }
      return ProgressSnapshot(
        bookId: bookId,
        url: j['url'] as String? ?? '',
        pageTitle: j['title'] as String? ?? '',
        // 比例存在 anchor 里（ProgressSnapshot 没有单独的 docRatio 字段）。
        anchor: anchor,
        updatedAt: DateTime.now(),
        deviceId: deviceId ?? 'local',
        pageHash: j['hash'] as String?,
      );
    } catch (_) {
      return null;
    }
  }

  /// WebView2 的 ExecuteScript 返回的是「脚本返回值的 JSON 表示」。
  /// 我们的脚本返回字符串，所以要多解一层。
  String? _unwrapScriptResult(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      final first = jsonDecode(raw);
      if (first is String) return first;
      if (first is Map) return jsonEncode(first);
    } catch (_) {}
    return null;
  }

  @override
  Future<List<ProgressSnapshot>> flushAll({String? deviceId}) async {
    final out = <ProgressSnapshot>[];
    for (final id in _openBooks.toList()) {
      final s = await collect(id, deviceId: deviceId);
      if (s != null) out.add(s);
    }
    return out;
  }

  /// 摘掉用户已经关掉的书。
  ///
  /// 书架每次刷新都会调它。原生侧在窗口收到 WM_CLOSE 时把 bookId
  /// 推过来（见 _onNativeCall 的 bookClosed 分支），这里把它取走。
  ///
  /// 关之前先采一次位置 —— 用户关窗口那一刻的进度也要留住，
  /// 否则最后一屏的阅读位置会丢。
  @override
  Future<List<String>> reapClosed({
    Future<void> Function(ProgressSnapshot snapshot)? persist,
  }) async {
    if (_closed.isEmpty) return const [];

    final closed = _closed.toList();
    _closed.clear();

    if (persist != null) {
      for (final bookId in closed) {
        // 窗口已经销毁，采不到位置了；用最后一次上报的缓存。
        //
        // 这个缓存有两处写入:
        //   1. 每次页面主动上报（滚动去抖、导航）
        //   2. 关窗口的瞬间抢采一次（见 _onNativeCall 的 bookClosed）
        // 所以这里拿到的通常是窗口关闭那一刻的精确位置。
        final last = _lastReports[bookId];
        if (last != null) await persist(last);
      }
    }
    for (final id in closed) {
      _openBooks.remove(id);
      _lastReports.remove(id);
    }
    return closed;
  }

  /// 每本书最后一次上报的位置，关窗口时用来落盘。
  final _lastReports = <String, ProgressSnapshot>{};

  @override
  Future<void> shutdown() async {
    for (final id in _openBooks.toList()) {
      try {
        await _channel.invokeMethod<void>('closeBook', {'bookId': id});
      } catch (_) {}
    }
    _openBooks.clear();
    await _navs.close();
    await _reports.close();
  }

  @override
  Future<void> installBootstrap(String script) async {
    // 注入引导脚本到所有已开窗口。
    for (final id in _openBooks) {
      try {
        await _channel.invokeMethod<String>('executeScript', {
          'bookId': id,
          'script': script,
        });
      } catch (_) {}
    }
  }
}

/// 读取当前位置的脚本。
///
/// 返回值必须是一个 JSON 字符串，因为 WebView2 的 ExecuteScript
/// 只把结果序列化一层。
const readPositionScript = r'''
(function () {
  try {
    var se = document.scrollingElement || document.documentElement;
    var max = Math.max(1, se.scrollHeight - se.clientHeight);
    var y = window.scrollY || se.scrollTop || 0;
    var result = {
      ok: true,
      url: location.href,
      title: document.title || '',
      ratio: Math.min(1, Math.max(0, y / max)),
      y: y,
      anchor: (window.__prPickAnchor ? window.__prPickAnchor() : null)
    };
    return JSON.stringify(result);
  } catch (e) {
    return JSON.stringify({ ok: false, error: String(e) });
  }
})();
''';

/// 恢复位置的脚本。
///
/// ── 关键：函数名要用 __pr.restore ──
///
/// anchor_script.dart 里对外只暴露两个函数：
///   `window.__pr.collect()` 与 `window.__pr.restore(anchor)`
///
/// 之前这里写的是 `window.__prRestoreAnchor(...)`，那个函数根本不存在，
/// 于是恢复永远走兜底分支（按比例滚），锚点精度全部丢失 ——
/// 表现就是"回到上次位置"总是差很多。
String restoreScript(Anchor? anchor) {
  if (anchor == null) return '0;';
  final json = jsonEncode(anchor.toJson());
  return '''
(function () {
  try {
    if (window.__pr && typeof window.__pr.restore === 'function') {
      return String(window.__pr.restore($json));
    }
    // 兜底：脚本还没装上时按比例滚。
    var se = document.scrollingElement || document.documentElement;
    var max = Math.max(0, se.scrollHeight - se.clientHeight);
    window.scrollTo(0, Math.round(max * ${anchor.docRatio}));
    return 'ratio';
  } catch (e) { return 'error:' + e; }
})();
''';
}

import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:convert';

import 'package:webview_flutter/webview_flutter.dart';

import '../../core/domain/anchor_script.dart';
import '../../core/domain/models.dart';
import '../../core/domain/url_normalizer.dart';
import '../../core/ports/ports.dart';

/// Android 引擎:内嵌 WebView。
///
/// 与桌面端的根本差异:
///   * 桌面把渲染交给外部 Edge/Chrome,靠 CDP 注入与通信;
///   * 这里 WebView 就在应用进程内,注入走 onPageStarted、
///     通信走 JavaScriptChannel —— 没有外部进程,也不需要端口。
///
/// 共同点是 anchor_script.dart 完全复用:
/// `__pr.collect()` / `__pr.restore()` 两端行为一致,
/// 只是调用方式不同。
class WebViewEngine implements WebEngine {
  WebViewEngine({this.deviceId = 'android'});

  final String deviceId;

  final _navs = StreamController<NavigationEvent>.broadcast();
  final _reports = StreamController<PositionReport>.broadcast();

  /// bookId → controller。一本书一个 WebView 实例。
  final Map<String, WebViewController> _controllers = {};

  /// bookId → 最近一次已知位置。
  ///
  /// WebView 被回收(evaluateJavascript 失败)时用它兜底,
  /// 避免"采集不到就把进度丢了"。
  final Map<String, ProgressSnapshot> _lastKnown = {};

  /// bookId → 范围前缀,用于判断站外链接。
  final Map<String, String> _scopes = {};

  /// bookId → 断点,页面加载完后恢复。
  final Map<String, ProgressSnapshot> _pendingResume = {};

  /// bookId → 待注入的深色主题脚本。
  ///
  /// Android 的 WebView 不支持 document-start 注入（实测 MI PAD 4 PLUS
  /// 的 WebView 68、荣耀 KRJ-W09 的华为内核都不支持），只能在
  /// onPageFinished 之后 runJavaScript —— 打开书时会先看到原色闪一下。
  final Map<String, String> _pendingThemeScript = {};

  /// 深色引擎的失败状态上报。
  ///
  /// 只在确定没生效时发一条，UI 层用它提示用户。
  /// Android 上没有 DevTools，正常时不占页面空间。
  final _darkStatus = StreamController<Map<String, dynamic>>.broadcast();

  Stream<Map<String, dynamic>> get darkStatus => _darkStatus.stream;

  /// bookId → 加载进度(0-100)。
  final Map<String, int> _progress = {};

  /// 站外链接的处理(由 UI 层传入,通常是交给系统浏览器)。
  void Function(String url)? _openExternal;

  /// 双指横滑回调:bookId + 'back'/'forward'。
  void Function(String bookId, String action)? onGesture;

  String? _lastError;
  String? get lastError => _lastError;

  /// 当前主题模式,由阅读页在注入前写入。
  ///
  /// 只用于让注入的 matchMedia 覆盖知道该报 dark 还是 light。
  /// 真正的配色由原生 ForceDark 负责(见 webview_theme.dart 的说明)。
  static String themeMode = 'system';

  @override
  String get id => 'webview';

  @override
  Stream<NavigationEvent> get navigations => _navs.stream;

  @override
  Stream<PositionReport> get positionReports => _reports.stream;

  @override
  Set<String> get openBooks => Set.unmodifiable(_controllers.keys);

  // ---------------------------------------------------------------- 创建

  /// 创建并配置一个 WebView controller。
  Future<WebViewController> create(String bookId) async {
    final controller = WebViewController();

    await controller.setJavaScriptMode(JavaScriptMode.unrestricted);
    await controller.setBackgroundColor(const Color(0xFF18191B));

    // 上报通道:页面里的 window.__prReport 会调它。
    await controller.addJavaScriptChannel(
      'PRReport',
      onMessageReceived: (msg) => _handleReport(bookId, msg.message),
    );
    // 手势通道:页面检测到双指同向横滑后回传。
    //
    // 为什么手势要在页面内检测:
    // WebViewWidget 是平台视图,触摸事件由原生消费、不进 Flutter 的
    // PointerRouter,外层 Listener 收不到任何事件(实测无输出)。
    await controller.addJavaScriptChannel(
      'PRGesture',
      onMessageReceived: (msg) {
        final action = msg.message.trim();
        onGesture?.call(bookId, action);
      },
    );

    // 导航通道:页面 pushState 时通知 Dart。
    await controller.addJavaScriptChannel(
      'PRNav',
      onMessageReceived: (msg) {
        final url = msg.message.trim();
        if (url.isEmpty) return;
        _navs.add(
          NavigationEvent(
            bookId: bookId,
            url: url,
            title: '',
            at: DateTime.now(),
          ),
        );
      },
    );

    await controller.setNavigationDelegate(
      NavigationDelegate(
        onPageStarted: (url) async {
          await injectScripts(controller);
        },
        onPageFinished: (url) async {
          // 页面加载完再补一次:有些站点在 DOMContentLoaded 后
          // 才建立滚动容器,太早注入 __pr 会找不到滚动元素。
          await injectScripts(controller);

          // bridge 就位后再注入深色主题 —— 引擎会通过 __prReport
          // 上报失败原因，而它由 injectScripts 里的 _bridgeHeader 定义。
          final theme = _pendingThemeScript[bookId];
          if (theme != null) {
            await _injectTheme(controller, theme);
          }

          final resume = _pendingResume.remove(bookId);
          if (resume != null) {
            await _restoreAnchor(controller, resume);
          }
        },
        onProgress: (p) => _progress[bookId] = p,
        onWebResourceError: (e) {
          if (e.isForMainFrame ?? false) {
            _lastError = '${e.description} (${e.errorCode})';
          }
        },
        onNavigationRequest: (req) {
          final url = req.url;
          if (url.startsWith('about:')) return NavigationDecision.navigate;
          final scope = _scopes[bookId];
          if (scope != null && !url.startsWith(scope)) {
            _openExternal?.call(url);
            return NavigationDecision.prevent;
          }
          return NavigationDecision.navigate;
        },
      ),
    );

    await controller.setOnConsoleMessage((m) {
      if (m.level == JavaScriptLogLevel.error) {
        _lastError = m.message;
      }
    });

    _controllers[bookId] = controller;
    return controller;
  }

  /// 打开外部浏览器的回调。
  void setExternalOpener(void Function(String url) fn) => _openExternal = fn;

  /// 加载进度(0-100)。
  int progressOf(String bookId) => _progress[bookId] ?? 0;

  /// 准备打开一本书:记下 scope 与断点,供导航回调使用。
  void prepare(Book book, ProgressSnapshot? resume) {
    _scopes[book.id] = book.scopePrefix;
    if (resume != null) _pendingResume[book.id] = resume;
  }
  /// 合并后的注入脚本。供测试检查内容与语法。
  static String get debugBundle => _bootstrapBundle;

  static String get _bootstrapBundle =>
      '$_bridgeHeader\n$_colorSchemeScript\n$_gestureScript\n'
      '$anchorBootstrapScript\n$positionReportScript';

  /// 把注入脚本送进页面。
  ///
  /// 每个导航都要重新注入 —— 页面换了,旧的 `window.__pr` 就没了。
  Future<void> injectScripts(WebViewController controller) async {
    await controller.runJavaScript(_bootstrapBundle);
  }

  /// 让站点用自己的深色主题。
  ///
  /// ── 只做一件事:覆写 matchMedia ──
  ///
  /// 实测(Edge 114,MDN):
  ///   只覆写 matchMedia,不动 DOM:
  ///     700ms  html bg = rgba(0,0,0,0)      ← 页面还没渲染
  ///     1400ms html bg = rgb(24,25,27)      ← 变深色
  ///     之后一直稳定在 rgb(24,25,27),data-theme 始终是 "light dark"
  ///   说明站点**自己**会根据 matchMedia 的结果挑主题,我们不需要替它改属性。
  ///
  /// ── 之前为什么闪 ──
  ///
  /// 之前的版本除了覆写 matchMedia,还主动 setAttribute/data-theme 和
  /// classList.add('dark'),而且 apply() 被调了四次(立即、DOMContentLoaded、
  /// 400ms、1200ms)。站点自己的主题逻辑与我们反复互相覆盖,
  /// 用户看到的就是深浅来回跳。
  ///
  /// 现在只在文档开头覆写一次 matchMedia,之后完全交给站点。
  /// 这样只有一个"浅 → 深"的切换(站点首次算样式时),不会再抖。
  ///
  /// ── 不支持深色主题的站点 ──
  ///
  /// 保持浅色。这是刻意的:强行反转配色会把图片、代码高亮、logo 弄坏,
  /// 比"没跟随"更糟。
  static const String _colorSchemeScript = r'''
(function () {
  var mode = window.__PR_THEME_MODE__;
  if (!mode || mode === 'system') return;
  if (window.__prMatchMediaPatched) return;
  window.__prMatchMediaPatched = true;

  var wantDark = mode === 'dark';
  try {
    var orig = window.matchMedia.bind(window);
    window.matchMedia = function (query) {
      var mql = orig(query);
      if (!query || query.indexOf('prefers-color-scheme') < 0) return mql;
      var askDark = query.indexOf('dark') >= 0;
      var askLight = query.indexOf('light') >= 0;
      if (!askDark && !askLight) return mql;
      try {
        Object.defineProperty(mql, 'matches', {
          get: function () { return askDark ? wantDark : !wantDark; },
        });
      } catch (e) {}
      return mql;
    };
  } catch (e) {}
})();
''';

  /// 在页面内检测"双指同向横滑",通过 channel 回传给 Dart。
  ///
  /// 为什么必须在页面内做:
  /// `WebViewWidget` 底层是平台视图(AndroidView + Hybrid Composition),
  /// 触摸事件由原生 WebView 直接消费,**不经过 Flutter 的 PointerRouter**。
  /// 实测:在 WebView 外面包 Listener,一个 pointer 事件都收不到
  /// (日志里 `GESTURE` 完全没有输出)。
  ///
  /// 所以只能让页面自己的 JS 监听 touch 事件 —— 它拿得到完整的多指几何。
  ///
  /// 判定逻辑必须和"缩放"互斥:
  ///   * 两指距离变化 > 10%  → 在缩放,忽略
  ///   * 中心点横移 > 90px 且明显大于纵向位移 → 翻页
  ///
  /// 触发后发 `PRGesture` 消息,Dart 侧据此调 goBack/goForward。
  static const String _gestureScript = r'''
(function () {
  if (window.__prGestureInstalled) return;
  window.__prGestureInstalled = true;

  var startSpan = null;
  var startCenter = null;
  var fired = false;

  function post(action) {
    try { PRGesture.postMessage(action); } catch (e) {}
  }

  function geom(touches) {
    var a = touches[0], b = touches[1];
    var dx = a.clientX - b.clientX;
    var dy = a.clientY - b.clientY;
    return {
      span: Math.sqrt(dx * dx + dy * dy),
      cx: (a.clientX + b.clientX) / 2,
      cy: (a.clientY + b.clientY) / 2
    };
  }

  document.addEventListener('touchstart', function (e) {
    if (e.touches.length !== 2) return;
    var g = geom(e.touches);
    startSpan = g.span;
    startCenter = { x: g.cx, y: g.cy };
    fired = false;
  }, { passive: true, capture: true });

  document.addEventListener('touchmove', function (e) {
    if (fired || e.touches.length !== 2) return;
    if (startSpan === null || startCenter === null) return;
    var g = geom(e.touches);

    // 距离变化明显 = 在捏合缩放,不介入。
    if (Math.abs(g.span - startSpan) / Math.max(startSpan, 1) > 0.10) return;

    var dx = g.cx - startCenter.x;
    var dy = g.cy - startCenter.y;
    // 横向位移要足够大,且明显大于纵向 —— 否则是在斜着滚页。
    if (Math.abs(dx) <= 90) return;
    if (Math.abs(dx) <= Math.abs(dy) * 1.8) return;

    fired = true;
    post(dx > 0 ? 'back' : 'forward');
  }, { passive: true, capture: true });

  document.addEventListener('touchend', function (e) {
    if (e.touches.length < 2) {
      startSpan = null;
      startCenter = null;
    }
  }, { passive: true, capture: true });
})();
''';

  /// 把页面的上报接到 Dart 侧的桥。
  ///
  /// 桌面端用 CDP 的 Runtime.addBinding,WebView 没有这个机制,
  /// 换成 JavaScriptChannel:注入一个同名函数,内部调 channel。
  static const String _bridgeHeader = r'''
(function () {
  if (window.__prBridgeInstalled) return;
  window.__prBridgeInstalled = true;
  window.__prReport = function (payload) {
    try {
      PRReport.postMessage(
        typeof payload === 'string' ? payload : JSON.stringify(payload)
      );
    } catch (e) {}
  };
  // 路由变化时通知 Dart(用于刷新书架上的"正在读")。
  function notifyNav() {
    try { PRNav.postMessage(location.href); } catch (e) {}
  }
  var push = history.pushState;
  history.pushState = function () { push.apply(this, arguments); notifyNav(); };
  var replace = history.replaceState;
  history.replaceState = function () {
    replace.apply(this, arguments); notifyNav();
  };
  window.addEventListener('popstate', notifyNav);
  window.addEventListener('hashchange', notifyNav);
})();
''';

  /// 页面主动上报(滚动、路由、切后台、关窗)。
  void _handleReport(String bookId, String payload) {
    try {
      final data = jsonDecode(payload) as Map<String, dynamic>;
      final href = data['href'] as String? ?? '';
      if (href.isEmpty || href == 'about:blank') return;

      final anchorJson = data['anchor'];
      Anchor? anchor;
      if (anchorJson is Map<String, dynamic>) {
        anchor = Anchor.fromJson(anchorJson);
      }

      final report = PositionReport(
        bookId: bookId,
        url: href,
        title: (data['title'] as String? ?? '').trim(),
        anchor: anchor,
        docRatio: (data['ratio'] as num?)?.toDouble(),
        reason: data['why'] as String? ?? 'scroll',
        at: DateTime.now(),
      );

      _lastKnown[bookId] = ProgressSnapshot(
        bookId: bookId,
        url: UrlNormalizer.normalize(href),
        pageTitle: report.title,
        pageHash: _hashOf(href),
        anchor: anchor,
        updatedAt: report.at,
        deviceId: deviceId,
      );
      _reports.add(report);
    } catch (_) {
      // 上报格式异常就丢弃,不能因为一条脏数据影响阅读。
    }
  }

  String? _hashOf(String url) {
    final i = url.indexOf('#');
    if (i < 0 || i == url.length - 1) return null;
    return url.substring(i);
  }

  // ---------------------------------------------------------------- 打开

  @override
  Future<String> launch(Book book, {ProgressSnapshot? resume}) async {
    final url = resumeUrl(book, resume);
    final controller = _controllers[book.id];
    if (controller != null) {
      await controller.loadRequest(Uri.parse(url));
      await injectScripts(controller);
      await _restoreAnchor(controller, resume);
    }
    return url;
  }

  /// 目标 URL:带 fragment 才能落到页内小节。
  String resumeUrl(Book book, ProgressSnapshot? resume) {
    if (resume == null) return book.entryUrl;
    final hash = resume.pageHash;
    if (hash == null || hash.isEmpty) return resume.url;
    final fragment = hash.startsWith('#') ? hash.substring(1) : hash;
    return '${resume.url}#$fragment';
  }

  /// 等页面加载后恢复锚点。
  Future<void> _restoreAnchor(
    WebViewController controller,
    ProgressSnapshot? resume,
  ) async {
    final anchor = resume?.anchor;
    if (anchor == null) return;
    // 等布局稳定:懒加载会把高度改掉,太早恢复会滚不到位。
    for (var i = 0; i < 10; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 300));
      final h = await _evalInt(
        controller,
        '(document.scrollingElement || document.documentElement)'
        '.scrollHeight',
      );
      if (h > 1000) break;
    }
    // 恢复三次:应对懒加载导致的高度变化。
    for (var i = 0; i < 3; i++) {
      await controller.runJavaScript(
        '__pr && __pr.restore(${jsonEncode(anchor.toJson())})',
      );
      await Future<void>.delayed(const Duration(milliseconds: 400));
    }
  }

  Future<int> _evalInt(WebViewController c, String expr) async {
    try {
      final r = await c.runJavaScriptReturningResult('($expr) | 0');
      if (r is int) return r;
      return int.tryParse(r.toString().replaceAll('"', '')) ?? 0;
    } catch (_) {
      return 0;
    }
  }

  // ---------------------------------------------------------------- 采集

  @override
  Future<ProgressSnapshot?> collect(
    String bookId, {
    String? deviceId,
  }) async {
    final controller = _controllers[bookId];
    if (controller == null) return _lastKnown[bookId];

    try {
      final raw = await controller.runJavaScriptReturningResult(
        'JSON.stringify(__pr.collect())',
      );
      // WebView 返回的是 JSON 字符串,可能被再包一层引号。
      var text = raw.toString();
      if (text.startsWith('"') && text.endsWith('"')) {
        text = text.substring(1, text.length - 1);
      }
      text = text.replaceAll(r'\"', '"');
      if (text.isEmpty || text == 'null') return _lastKnown[bookId];

      final data = jsonDecode(text) as Map<String, dynamic>;
      final url = Uri.parse(data['url'] as String? ?? '');
      final anchorJson = data['anchor'];
      final hash = (data['hash'] as String? ?? '').trim();

      final snapshot = ProgressSnapshot(
        bookId: bookId,
        url: UrlNormalizer.normalize(
          '${url.scheme}://${url.host}${url.path}'
          '${url.hasQuery ? '?${url.query}' : ''}',
        ),
        pageTitle: (data['title'] as String? ?? '').trim(),
        pageHash: hash.isEmpty ? null : hash,
        anchor: anchorJson is Map<String, dynamic>
            ? Anchor.fromJson(anchorJson)
            : null,
        updatedAt: DateTime.now(),
        deviceId: deviceId ?? this.deviceId,
      );
      _lastKnown[bookId] = snapshot;
      return snapshot;
    } catch (_) {
      return _lastKnown[bookId];
    }
  }

  @override
  Future<List<ProgressSnapshot>> flushAll({String? deviceId}) async {
    final out = <ProgressSnapshot>[];
    for (final bookId in _controllers.keys.toList()) {
      final s = await collect(bookId, deviceId: deviceId);
      if (s != null) out.add(s);
    }
    return out;
  }

  /// Android 端所有阅读页都在本进程内，不存在"用户从外部关掉窗口"：
  /// 返回书架时 controller 由 openBooks 自己维护，没有需要摘除的残留。
  @override
  Future<List<String>> reapClosed({
    Future<void> Function(ProgressSnapshot snapshot)? persist,
  }) async => const [];

  @override
  Future<void> installBootstrap(String script) async {
    for (final c in _controllers.values) {
      try {
        await c.runJavaScript(script);
      } catch (_) {}
    }
  }

  /// 关掉某本书的 WebView(回书架时释放内存)。
  void release(String bookId) {
    _controllers.remove(bookId);
    _pendingThemeScript.remove(bookId);
  }

  /// 记下这本书要注入的深色脚本，由阅读页在打开书时调用。
  void setThemeScript(String bookId, String script) {
    _pendingThemeScript[bookId] = script;
  }

  /// 注入深色主题脚本。
  ///
  /// ── 为什么要分块 ──
  ///
  /// 引擎约 56 KB。实测在 WebView 68 上，单次 evaluateJavascript 传这么
  /// 大的脚本会**静默失败** —— 不抛错，但脚本一行都不执行。
  /// 分块后每块 4 KB 都能正常写入，最后在页面里用 new Function 拼起来跑。
  ///
  /// ── 为什么要反复重试 ──
  ///
  /// 实测同一份代码同一台机器，约 1/5 的概率首次不生效：
  /// onPageFinished 触发时页面的 readyState 在 WebView 68 上有时仍报
  /// 'loading'，引擎的启动分支等不到 DOMContentLoaded 就永远不跑。
  /// 表现是 preset 有值、但连 data-pr-dark 都没设上。
  ///
  /// 所以这里不只看结果，必要时**重新执行一次**脚本 ——
  /// 引擎自身有幂等保护（__prIife / __prMediaPatched 等标记）。
  Future<void> _injectTheme(
    WebViewController controller,
    String script,
  ) async {
    // 没绑预设时脚本只有几百字节（matchMedia 覆写），不用分块也不用催。
    final hasEngine = script.length > 2000;
    const chunkSize = 4000;

    // 串行化：同一个 WebView 上 onPageFinished 可能连续触发多次
    //（重定向、iframe、站点自己的 pushState 都会），并发起来时
    // 后一次的 join 会读走前一次的缓冲，导致长度对不上或直接读空。
    // 用上次注入的 Future 排队，确保同一时刻只有一次在跑。
    final prev = _injectChain;
    final completer = Completer<void>();
    _injectChain = completer.future;
    if (prev != null) {
      try {
        await prev;
      } catch (_) {}
    }

    try {
      if (!hasEngine) {
        await controller.runJavaScript(script);
        return;
      }

      // 先试单次整段注入。
      //
      // 早前判断「72KB 会静默失败」是被 class 字段语法错误误导的 ——
      // 那时脚本本身编译不过，表现成「注入成功但一行没跑」。
      // 语法修好后（esbuild 转译到 es2017）单次注入是可靠的，
      // 分块反而引入了跨轮缓冲污染的问题。
      //
      // 分块只在单次失败时兜底。
      await controller.runJavaScript(script);

      // 判断「真的生效了」不能只看内联样式数。
      //
      // 占位样式是写进一张 <style> 的（html,body 的背景色），
      // 不算内联 style；很多站点（尤其 SPA 空壳）元素本来就少。
      // 之前用 styled > 5 判定，结果页面明明已经变深色了还报失败。
      //
      // 改成看 body 的实际计算背景色是否接近预设背景。
      for (var attempt = 0; attempt < 6; attempt++) {
        final r = await controller.runJavaScriptReturningResult(
          '(function(){'
          '  var dark = document.documentElement.getAttribute("data-pr-dark");'
          '  var n = document.querySelectorAll("[style]").length;'
          '  if (dark === "1" && n > 5) return "ok";'
          // 元素少或样式走样式表时，用 body 的计算背景色兜底判断。
          '  if (dark === "1" && document.body) {'
          '    var bg = getComputedStyle(document.body).backgroundColor;'
          '    var want = window.__PR_DARK_PRESET'
          '      ? window.__PR_DARK_PRESET.background : "";'
          '    if (want && bg === want) return "ok";'
          '  }'
          '  if (window.__prForceWalk) {'
          '    try { window.__prForceWalk(); } catch (e) {}'
          '  }'
          '  return "retry dark=" + dark + " styled=" + n;'
          '})()',
        );
        if (r.toString().replaceAll('"', '') == 'ok') return;
        await Future<void>.delayed(const Duration(milliseconds: 300));
      }

      // 走到这里说明单次注入没成功：分块再试一次。
      final chunks = <String>[
        for (var i = 0; i < script.length; i += chunkSize)
          script.substring(
            i,
            i + chunkSize > script.length ? script.length : i + chunkSize,
          ),
      ];
      final token = DateTime.now().microsecondsSinceEpoch;
      final buf = '__prBuf$token';
      await controller.runJavaScript('window.$buf = [];');
      for (final chunk in chunks) {
        await controller.runJavaScript(
          'window.$buf.push(${jsonEncode(chunk)});',
        );
      }
      await controller.runJavaScript(
        'window.__prSource = window.$buf.join("");'
        'window.$buf = null;'
        'try { (new Function(window.__prSource))(); }'
        'catch (e) { window.__prDarkError = String(e); }',
      );

      for (var attempt = 0; attempt < 8; attempt++) {
        // 每次都清掉上一次的错误，避免读到过期的失败原因。
        await controller.runJavaScript(
          'window.__prDarkError = null;'
          'if (window.__prSource) {'
          '  try { (new Function(window.__prSource))(); }'
          '  catch (e) { window.__prDarkError = String(e); }'
          '}',
        );

        final r = await controller.runJavaScriptReturningResult(
          '(function(){'
          '  var dark = document.documentElement.getAttribute("data-pr-dark");'
          '  var n = document.querySelectorAll("[style]").length;'
          '  if (dark === "1" && n > 5) return "ok";'
          // 已启动但样式不够：让引擎重扫一遍即可。
          '  if (window.__prForceWalk) {'
          '    try { window.__prForceWalk(); } catch (e) {}'
          '  }'
          '  return "retry dark=" + dark + " styled=" + n +'
          '    " err=" + (window.__prDarkError || "none");'
          '})()',
        );
        final state = r.toString().replaceAll('"', '');
        if (state == 'ok') return;

        if (attempt == 7) {
          final detail = await controller.runJavaScriptReturningResult(
            '(function(){'
            '  var o = [];'
            '  o.push("preset=" + (!!window.__PR_DARK_PRESET));'
            '  o.push("bg=" + (window.__PR_DARK_PRESET ? window.__PR_DARK_PRESET.background : "-"));'
            '  o.push("keys=" + (window.__PR_DARK_PRESET ? Object.keys(window.__PR_DARK_PRESET).join(",") : "-"));'
            '  o.push("runErr=" + (window.__prDarkError || "none"));'
            '  o.push("errs=" + JSON.stringify((window.__prDarkErrors||[]).slice(0,3)));'
            '  o.push("forceWalk=" + (typeof window.__prForceWalk));'
            '  o.push("total=" + document.querySelectorAll("*").length);'
            '  o.push("bodyBg=" + (document.body ? getComputedStyle(document.body).backgroundColor : "-"));'
            '  return o.join(" ");'
            '})()',
          );
          final msg = detail.toString().replaceAll('"', '');
          debugPrint('深色注入未生效: $state | $msg');
          _darkStatus.add({'ok': false, 'error': msg});
        }
        await Future<void>.delayed(const Duration(milliseconds: 400));
      }
    } catch (e) {
      _darkStatus.add({'ok': false, 'error': '注入抛错: $e'});
    } finally {
      completer.complete();
      if (identical(_injectChain, completer.future)) {
        _injectChain = null;
      }
    }
  }

  /// 注入串行化用的链尾 Future。
  Future<void>? _injectChain;

  @override
  Future<void> shutdown() async {
    _controllers.clear();
    await _navs.close();
    await _reports.close();
    await _darkStatus.close();
  }
}

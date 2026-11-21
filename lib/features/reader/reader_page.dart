import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../core/domain/models.dart';
import '../../core/services/settings.dart';
import '../../core/services/webview_theme.dart';
import '../../engine/android/android_theme_script.dart';
import '../../engine/android/webview_engine.dart';
import 'dark_status_badge.dart';

/// Android 阅读页。
///
/// 交互设计:
///   * 返回键 / 边缘手势 = 回书架,**不消费网页历史**
///   * 双指同向横滑 = 页内前进/后退
///   * 切后台立刻落库,避免被系统杀掉丢进度
///
/// 为什么返回键不先走网页后退:
/// 文档站靠侧边栏跳转,历史里混着一堆目录点击,
/// 返回键后退的体验很差,还会把进度写回旧页。
/// 页内导航交给双指横滑,更符合"整页翻动"的直觉。
class ReaderPage extends ConsumerStatefulWidget {
  const ReaderPage({
    super.key,
    required this.engine,
    required this.book,
    required this.resume,
    required this.onProgress,
  });

  final WebViewEngine engine;
  final Book book;
  final ProgressSnapshot? resume;

  /// 离开页面时把最后位置交回上层落库。
  final Future<void> Function(ProgressSnapshot snapshot) onProgress;

  @override
  ConsumerState<ReaderPage> createState() => _ReaderPageState();
}

class _ReaderPageState extends ConsumerState<ReaderPage>
    with WidgetsBindingObserver {
  WebViewController? _controller;

  /// 深色引擎上报的执行状态（null 表示还没收到）。
  Map<String, dynamic>? _darkReport;
  // ignore: unused_field
  StreamSubscription<Map<String, dynamic>>? _darkSub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    // 订阅深色引擎的执行状态。
    //
    // 引擎注入后会自报一条 why=dark-status 的消息。Android 上没有
    // DevTools，不订阅就只能靠猜 —— 页面没变色时不知道是没注入、
    // 注入了但语法错误、还是注入了但没找到可算色的元素。
    _darkSub = widget.engine.darkStatus.listen((s) {
      if (!mounted) return;
      setState(() => _darkReport = s);
    });


    // 双指横滑由页面内的 JS 检测后回传。
    //
    // 为什么不在 Flutter 层做:
    // WebViewWidget 是平台视图,触摸事件由原生 WebView 直接消费,
    // **不经过 Flutter 的 PointerRouter** —— 外层包 Listener
    // 一个事件都收不到(实测日志完全没有输出)。
    // 所以只能让页面自己的 JS 监听 touch 事件。
    widget.engine.onGesture = (_, action) {
      if (!mounted) return;
      if (action == 'back') {
        _pageBack();
      } else if (action == 'forward') {
        _pageForward();
      }
    };

    _init();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.engine.onGesture = null;
    widget.engine.release(widget.book.id);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      // 切后台立刻落库:Android 可能直接把进程杀掉。
      _flush();
    }
  }

  Future<void> _init() async {
    // 把当前主题交给引擎:注入脚本要靠它决定切不切站点的深色主题。
    final mode = ref.read(themeModeProvider);
    WebViewEngine.themeMode = switch (mode) {
      ThemeMode.dark => 'dark',
      ThemeMode.light => 'light',
      ThemeMode.system => 'system',
    };

    final c = await widget.engine.create(widget.book.id);
    if (!mounted) return;

    // 注册「文档开始前」的主题脚本。
    //
    // 顺序至关重要:必须在 loadRequest **之前**注册。
    // 这个 API 只对之后创建的文档生效,先加载再注册就晚了 ——
    // 站点已经按浅色算完样式,用户看到的就是白底。
    final dark = WebViewTheme.resolveDark(
      mode,
      MediaQuery.platformBrightnessOf(context),
    );
    // 拼出本次要注入的脚本：预设 + 引擎全文。
    //
    // 没选预设时只做 matchMedia 覆写（让站点自己切深色）；
    // 选了预设才注入完整引擎 —— 这是「默认」档的语义。
    final preset = ref
        .read(themePresetsProvider.notifier)
        .byId(widget.book.presetId);
    final cap = await WebViewTheme.probe();
    final script = await AndroidThemeScript.build(
      preset: preset,
      dark: dark,
      webViewVersion: cap.webViewVersion,
    );

    // 实测 MI PAD 4 PLUS(WebView 68)和荣耀 KRJ-W09(华为内核)都不支持
    // document-start 注入。这两台上主题设置仍能用，只是打开书时会先
    // 看到原色闪一下 —— 这是设备的硬限制，不是实现没做好。
    final injected = await WebViewTheme.applyScript(
      c.platform,
      script: script,
    );
    if (!injected) {
      widget.engine.setThemeScript(widget.book.id, script);
    }
    if (!mounted) return;
    setState(() => _controller = c);

    final url = widget.engine.resumeUrl(widget.book, widget.resume);
    await c.loadRequest(Uri.parse(url));
  }

  Future<void> _flush() async {
    final s = await widget.engine.collect(widget.book.id);
    if (s != null) await widget.onProgress(s);
  }

  Future<void> _goBack() async {
    await _flush();
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  Future<void> _pageBack() async {
    final c = _controller;
    if (c == null) return;
    if (await c.canGoBack()) await c.goBack();
  }

  Future<void> _pageForward() async {
    final c = _controller;
    if (c == null) return;
    if (await c.canGoForward()) await c.goForward();
  }

  @override
  Widget build(BuildContext context) {
    // 监听主题变化:用户在设置里改了深浅色时,重新注册脚本。
    //
    // 注意:文档开始前脚本只对**之后创建**的文档生效,
    // 当前已加载的页面不会变。这里刻意不主动 reload ——
    // 用户可能正在读,突然刷新比配色暂时不更新更糟。
    // 下次翻页/重开书时就会用新主题。
    ref.listen(themeModeProvider, (prev, next) async {
      final c = _controller;
      if (c == null) return;
      final dark = WebViewTheme.resolveDark(
        next,
        MediaQuery.platformBrightnessOf(context),
      );
      // 重新拼脚本并注册。document-start 脚本只对之后创建的文档生效，
      // 当前页面不会立刻变 —— 这是刻意的：用户可能正在读，
      // 突然刷新比配色暂时不更新更糟。下次翻页或重开书时生效。
      final preset = ref
          .read(themePresetsProvider.notifier)
          .byId(widget.book.presetId);
      final cap = await WebViewTheme.probe();
      final script = await AndroidThemeScript.build(
        preset: preset,
        dark: dark,
        webViewVersion: cap.webViewVersion,
      );
      final ok = await WebViewTheme.applyScript(c.platform, script: script);
      if (!ok) {
        widget.engine.setThemeScript(widget.book.id, script);
      }
    });

    return PopScope(
      // 返回键直接回书架,不让 WebView 消费。
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        await _goBack();
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF0E0F12),
        body: SafeArea(
          child: Stack(
            children: [
              if (_controller == null)
                const Center(
                  child: CircularProgressIndicator(
                    color: Color(0xFF5AC8FA),
                    strokeWidth: 2,
                  ),
                )
              else
                WebViewWidget(controller: _controller!),
              // 深色引擎状态条：浮在页面顶部，能看见注入结果。
              //
              // 这是 Android 上唯一的排查手段 —— 没有 DevTools，
              // 出问题时只能靠这条信息判断「注入成功没有、有没有 JS 错误」。
              if (_darkReport != null)
                Positioned(
                  left: 8,
                  right: 8,
                  top: 8,
                  child: DarkStatusBadge(report: _darkReport!),
                ),
            ],
          ),
        ),
      ),
    );
  }
}


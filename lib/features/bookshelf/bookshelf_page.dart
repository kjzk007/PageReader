import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';

import '../../core/domain/theme_preset.dart';
import '../../core/domain/models.dart';
import '../../core/ports/ports.dart';
import '../../core/services/progress_recorder.dart';
import '../../core/services/settings.dart';
import '../../engine/desktop/cdp_engine.dart';
import '../../engine/desktop/webview2_engine.dart';
import '../settings/extension_onboarding.dart';
import '../../engine/android/webview_engine.dart';
import '../reader/reader_page.dart';
import '../sync/sync_desktop_page.dart';
import '../sync/sync_phone_page.dart';
import '../settings/settings_page.dart';
import '../settings/theme_preset_section.dart';
import '../diagnostics/diagnostics_page.dart';
import '../../core/domain/chapter_extractor.dart';
import '../../core/services/icon_fetcher.dart';
import '../../core/services/icon_palette.dart';
import 'add_book_dialog.dart';
import 'cached_cover.dart';

/// 书架:只依赖 LibraryStore 接口与可选的 WebEngine,不认具体实现。
class BookshelfPage extends StatefulWidget {
  const BookshelfPage({
    super.key,
    required this.store,
    this.engine,
    this.recorder,
    this.autoOpenBookId,
    this.autoCloseMs,
    this.autoScrollRatio,
    this.reloadSignal,
  });

  final LibraryStore store;

  /// 桌面端传入;移动端将来传 WebView 实现。为 null 时点书只提示。
  final WebEngine? engine;

  /// 进度记录器。必须传,否则进度一条都不会写入。
  final ProgressRecorder? recorder;

  /// 验收用:启动后自动打开这本书。命令行 `--open=id` 才会设置。
  final String? autoOpenBookId;

  /// 验收用:自动关掉刚打开的窗口(毫秒)。命令行 `--close-after=ms` 才会设置。
  final int? autoCloseMs;

  /// 自动化验收用：打开后先滚到这个比例（0~1），再执行关窗。
  final double? autoScrollRatio;

  /// 后台任务(图标补抓)完成时改变这个值,书架会自动重载。
  final ValueNotifier<int>? reloadSignal;

  @override
  State<BookshelfPage> createState() => _BookshelfPageState();
}

class _BookshelfPageState extends State<BookshelfPage> {
  late Future<_ShelfData> _future;
  String? _activeGroupId;
  final Set<String> _opening = {};

  /// 书架搜索关键词:书名、URL、上次停留的页面标题。
  String _query = '';
  bool _searching = false;
  final _searchController = TextEditingController();
  Timer? _reaper;

  /// 上次界面显示的"正开着"集合,用来判断要不要刷新。
  Set<String> _shownOpen = {};

  @override
  void initState() {
    super.initState();
    _future = _load();
    // 定期核对窗口是否还活着:用户直接点窗口的 X 时不会有什么事件通知我们,
    // 只能主动问浏览器。3 秒一次,开销很小。
    _reaper = Timer.periodic(const Duration(seconds: 3), (_) => _reap());

    widget.reloadSignal?.addListener(_onExternalReload);

    _searchController.addListener(() {
      setState(() {
        _query = _searchController.text;
      });
    });

    final autoId = widget.autoOpenBookId;
    if (autoId != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _autoOpen(autoId));
    }

  }

  /// 验收路径:自动打开指定书,可选定时关窗。仅命令行触发。
  Future<void> _autoOpen(String bookId) async {
    final data = await _future;
    final book = data.books.where((b) => b.id == bookId).firstOrNull;
    if (book == null) return;
    await _openBook(book);

    final closeAfter = widget.autoCloseMs;
    final engine = widget.engine;
    if (closeAfter != null && engine is CdpEngine) {
      await Future<void>.delayed(Duration(milliseconds: closeAfter));
      final targetId = engine.debugTargetFor(bookId);
      if (targetId != null) {
        await engine.debugCall('Target.closeTarget', {'targetId': targetId});
      }
    } else if (closeAfter != null && engine is WebView2Engine) {
      final wv2 = engine;
      // 内嵌内核的自动化验收：先滚到指定位置再关窗。
      // 这样才能验证"关闭时保存进度"和"重开时恢复"两条链路，
      // 而不是只看到窗口打开就算过。
      await Future<void>.delayed(const Duration(milliseconds: 4500));
      final ratio = widget.autoScrollRatio;
      if (ratio != null && ratio > 0) {
        try {
          await wv2.scrollToRatio(bookId, ratio);
          await Future<void>.delayed(const Duration(milliseconds: 1200));
        } catch (_) {}
      }
      await Future<void>.delayed(Duration(milliseconds: closeAfter));
      await wv2.closeBook(bookId);
    }
  }

  @override
  void dispose() {
    _reaper?.cancel();
    super.dispose();
  }

  /// 后台任务(图标补抓)完成时由外部触发重载。
  void _onExternalReload() {
    if (mounted) _reload();
  }

  /// 清掉已关闭的窗口。
  ///
  /// 关键点:不管哪个引擎实现,每轮都要重读 openBooks 并刷新界面。
  /// 之前只在数量变化时刷新,而首次构建拿到的就是空集合,
  /// 于是"角标永远不消失"或"角标永远不出现"。
  Future<void> _reap() async {
    final engine = widget.engine;
    if (engine == null || !mounted) return;
    try {
      // reapClosed 是所有引擎的接口方法（见 WebEngine），不该只管 CdpEngine。
      //
      // 之前写成 `if (engine is CdpEngine)`，结果内嵌 WebView2 那条路
      // 永远不会消费"窗口已关闭"事件 —— 书架一直显示"阅读中"，
      // 关窗口那一刻的进度也存不下来。
      await engine.reapClosed(
        persist: (snapshot) => widget.store.saveProgress(snapshot),
      );

      // 无条件重算:窗口的开关是引擎的实时状态,不能用"数量是否变化"当判据。
      final latest = engine.openBooks;
      if (!mounted) return;
      if (!setEquals(latest, _shownOpen)) {
        _reload();
      }
    } catch (_) {
      // 核对失败不影响使用,下一轮再试。
    }
  }

  Future<_ShelfData> _load() async {
    final groups = await widget.store.loadGroups();
    final books = await widget.store.loadBooks();
    final progress = await widget.store.latestProgressByBook();
    final open = widget.engine?.openBooks ?? const <String>{};

    // 最近阅读优先:读过的按最新进度时间倒序,没读过的按添加顺序排在后面。
    // 书架每天最常做的判断就是"上次读到哪本",不该让用户自己找。
    books.sort((a, b) {
      final ta = progress[a.id]?.updatedAt;
      final tb = progress[b.id]?.updatedAt;
      if (ta != null && tb != null) return tb.compareTo(ta);
      if (ta != null) return -1;
      if (tb != null) return 1;
      return a.sortIndex.compareTo(b.sortIndex);
    });
    _shownOpen = Set<String>.from(open);
    return _ShelfData(
      groups: groups,
      books: books,
      progress: progress,
      open: open,
    );
  }

  /// 重新取数据。
  /// 注意:必须用块语句。写成 `setState(() => _future = _load())` 时,
  /// 箭头函数会把赋值表达式的值(一个 Future)返回给 setState,
  /// Flutter 会抛 "callback argument returned a Future"。
  Future<void> _reload() async {
    final future = _load();
    setState(() {
      _future = future;
    });
    // 等数据回来再决定要不要重绘搜索/空状态,避免 FutureBuilder 闪一下。
    await future;
  }

  Future<void> _openBook(Book book) async {
    final engine = widget.engine;
    if (engine == null) {
      // 检测不到浏览器是最坏情况:整个应用无法打开任何书。
      // 不能只丢一句"找不到",要告诉用户具体怎么做。
      await _showNoBrowserHelp();
      return;
    }
    if (_opening.contains(book.id)) return;

    // 内嵌内核：第一次打开书之前问一次要启用哪些插件。
    //
    // 不做这一步的话，新用户装完直接打开书，一个插件都加载不上，
    // 而他未必会去设置页翻那个区块 —— 结果就是"说支持插件但什么都没有"。
    if (engine is WebView2Engine) {
      // 书架是普通 StatefulWidget，没有 ref，从 ProviderScope 拿容器。
      await showExtensionOnboarding(context, ProviderScope.containerOf(context));
    }

    // 同步占位，再做任何 await。
    //
    // ── 为什么必须同步 ──
    //
    // 之前的写法是先判 `_opening.contains`，再在下面 setState 里 add。
    // 中间隔着 `if (engine is WebViewEngine)` 和几个 await，两次点击
    // 只要落在这个缝隙里就都能通过检查 —— 实测每次点击会触发两次
    // launch（间隔 111~192ms）。后果是同一本书被 openBook 两次，
    // 第二次命中原生侧刚建好的 session 又 Navigate 一遍，
    // 两个恢复任务同时跑，位置会跳。
    //
    // setState 回调里只做 add 会返回 bool，Flutter 会报错，
    // 所以先 add 再 setState(() {}) 触发布丁。
    _opening.add(book.id);
    setState(() {});

    // Android:推一个阅读页,WebView 渲染在应用内。
    //
    // 桌面端是把书交给外部浏览器窗口,Android 没有这个概念,
    // 必须自己开一个页面并内嵌 WebView。
    if (engine is WebViewEngine) {
      try {
        await _openInAppReader(book, engine);
      } finally {
        if (mounted) {
          setState(() {
            _opening.remove(book.id);
          });
        }
      }
      return;
    }

    if (!mounted) return;
    _toast('正在打开《${book.title}》…');
    // 在第一个 await 之前取容器：后面再碰 context 会触发
    // "BuildContext across async gaps" 的实现隐患。
    // 在第一个 await 之前取容器：后面再碰 context 会触发
    // "BuildContext across async gaps" 的实现隐患。
    ProviderContainer? container;
    try {
      container = ProviderScope.containerOf(context);
    } catch (_) {
      // 裸组件树（测试）里没有 ProviderScope，按不注入处理。
    }
    _toast('正在打开《${book.title}》…');

    try {
      final resume = await widget.store.latestProgress(book.id);
      // 按这本书绑定的预设决定要不要注入深色样式。
      // presetId 为空 = 「默认」，不注入任何东西，网页原样。
      if (engine is WebView2Engine) {
        ThemePreset? preset;
        try {
          preset = container
              ?.read(themePresetsProvider.notifier)
              .byId(book.presetId);
        } catch (_) {
          preset = null;
        }
        engine.setActivePreset(preset);
      }
      final target = await engine.launch(book, resume: resume);
      if (!mounted) return;
      _toast(
        resume == null
            ? '已打开 ${book.title}'
            : '从上次读的位置继续:${_short(target)}',
      );
      // 打开成功后立刻启动记录:否则导航事件没人接,进度全丢。
      widget.recorder?.start();
      _reload();
    } on CdpLaunchError catch (e) {
      // 需要用户动手的错误（比如"先退出 Edge"）要完整、单独地展示，
      // 不能被通用 catch 吞成一句"打开失败"。
      if (!mounted) return;
      await _showLaunchHelp(e.message);
    } catch (error) {
      if (!mounted) return;
      _toast('打开失败：$error');
    } finally {
      if (mounted) {
        setState(() {
          _opening.remove(book.id);
        });
      }
    }
  }

  String _short(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null) return url;
    final segments = uri.pathSegments;
    if (segments.isEmpty) return uri.host;
    return segments.last;
  }

  /// 等一帧绘制完成。
  ///
  /// 用于"关闭对话框后立刻弹下一个"的场景:
  /// 直接接着弹会让新旧 Overlay 条目重叠,触发 build scope 断言。
  static Future<void> _afterNextFrame() {
    final completer = Completer<void>();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!completer.isCompleted) completer.complete();
    });
    WidgetsBinding.instance.scheduleFrame();
    // 兜底:极端情况下帧回调不来,也不能永远挂着。
    return completer.future.timeout(
      const Duration(milliseconds: 200),
      onTimeout: () {},
    );
  }

  /// 检测不到浏览器时的说明。
  ///
  /// 这是产品的启动前提,必须让用户能自己解决:
  /// 说清要装什么、为什么、装完怎么办,而不是只报一句"找不到"。
  /// Android:打开应用内阅读页。
  ///
  /// 与桌面路径的区别:
  ///   * 不是 spawn 外部进程,而是 push 一个页面;
  ///   * 返回时(用户按返回键)阅读页会先把位置交回来再 pop,
  ///     所以这里 await 完就能立刻刷新书架。
  Future<void> _openInAppReader(Book book, WebViewEngine engine) async {
    setState(() {
      _opening.add(book.id);
    });
    try {
      final resume = await widget.store.latestProgress(book.id);
      if (!mounted) return;
      widget.recorder?.start();

      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => ReaderPage(
            engine: engine,
            book: book,
            resume: resume,
            onProgress: (snapshot) async {
              await widget.store.saveProgress(snapshot);
            },
          ),
        ),
      );
      if (!mounted) return;
      // 从阅读页回来:进度已由阅读页落库,这里只刷新界面。
      await _reload();
    } finally {
      if (mounted) {
        setState(() {
          _opening.remove(book.id);
        });
      }
    }
  }

  /// 显示"启动浏览器失败但用户可以自己解决"的提示。
  ///
  /// 目前唯一场景:Edge 正在运行,接管不了调试端口。
  /// 这种错误必须完整展示 —— 用 toast 一闪而过的话,
  /// 用户只会看到"书没打开",不知道要先退出浏览器。
  Future<void> _showLaunchHelp(String message) async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF191B1F),
        title: const Text(
          '无法记录进度',
          style: TextStyle(
            color: Color(0xFFF2F3F5),
            fontSize: 17,
            fontFamily: 'Microsoft YaHei',
          ),
        ),
        content: Text(
          message,
          style: const TextStyle(
            color: Color(0xFF9AA0A6),
            fontSize: 13,
            fontFamily: 'Microsoft YaHei',
            height: 1.7,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text(
              '知道了',
              style: TextStyle(
                color: Color(0xFF5AC8FA),
                fontFamily: 'Microsoft YaHei',
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showNoBrowserHelp() async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF191B1F),
        title: const Text(
          '没有找到浏览器',
          style: TextStyle(color: Color(0xFFF2F3F5), fontSize: 17),
        ),
        content: const SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'PageReader 借用系统里的 Edge 或 Chrome 来显示网页,'
                '本身不带浏览器内核。',
                style: TextStyle(color: Color(0xFF9AA0A6), fontSize: 13),
              ),
              SizedBox(height: 12),
              Text(
                '安装任意一个即可：',
                style: TextStyle(color: Color(0xFFC9CDD3), fontSize: 13),
              ),
              SizedBox(height: 6),
              Text(
                '· Microsoft Edge（Windows 自带,一般不会缺）\n'
                '· Google Chrome',
                style: TextStyle(color: Color(0xFF7C8188), fontSize: 12),
              ),
              SizedBox(height: 12),
              Text(
                '装好后重新打开 PageReader 会自动识别。',
                style: TextStyle(color: Color(0xFF7C8188), fontSize: 12),
              ),
              SizedBox(height: 14),
              Text(
                '已装但没识别到？可能是安装在非常规位置。'
                '请把 msedge.exe 或 chrome.exe 的完整路径告诉我。',
                style: TextStyle(color: Color(0xFF6E747C), fontSize: 11),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text(
              '知道了',
              style: TextStyle(color: Color(0xFF5AC8FA)),
            ),
          ),
        ],
      ),
    );
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 2)),
    );
  }

  /// 打开同步页。
  ///
  /// 同步是高频动作,所以单独放在工具栏上,不埋在设置页里。
  /// 桌面端开服务 + 显示二维码;手机端扫码配对 + 一键同步。
  Future<void> _openSync() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => Platform.isAndroid
            ? SyncPhonePage(store: widget.store)
            : SyncDesktopPage(store: widget.store),
      ),
    );
    // 从同步页返回时重载书架。
    //
    // 同步会改数据库(增删书、改进度),不重载的话用户看到的是旧界面,
    // 会以为"点了同步没反应"。踩过这个坑。
    if (!mounted) return;
    setState(() {
      _future = _load();
    });
    await _future;
  }

  /// 打开设置页。
  void _openSettings() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const SettingsPage()),
    );
  }

  /// 打开展开诊断页。
  void _openDiagnostics() {
    final engine = widget.engine;
    if (engine is! CdpEngine) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => DiagnosticsPage(engine: engine),
      ),
    );
  }

  /// 打开加书对话框,确认后落库。书加完留在书架,不自动打开。
  /// 分组管理:新建 / 改名 / 删除。
  ///
  /// 删除只解散 —— 组内的书转为未分组,书和进度都不动。
  /// 这样误删一个分组不会连带丢数据。
  Future<void> _manageGroups(_ShelfData data) async {
    final action = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF191B1F),
        title: const Text(
          '管理分组',
          style: TextStyle(color: Color(0xFFF2F3F5), fontSize: 17),
        ),
        content: SizedBox(
          width: 380,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (data.groups.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    '还没有分组。分组只是书架上的分类,不影响阅读。',
                    style: TextStyle(color: Color(0xFF6E747C), fontSize: 12),
                  ),
                )
              else
                for (final g in data.groups)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            g.name,
                            style: const TextStyle(
                              color: Color(0xFFE3E5E8),
                              fontSize: 14,
                            ),
                          ),
                        ),
                        Text(
                          '${data.books.where((b) => b.groupId == g.id).length} 本',
                          style: const TextStyle(
                            color: Color(0xFF6E747C),
                            fontSize: 12,
                          ),
                        ),
                        IconButton(
                          tooltip: '改名',
                          iconSize: 18,
                          onPressed: () => Navigator.of(ctx).pop('rename:${g.id}'),
                          icon: const Icon(
                            Icons.edit,
                            color: Color(0xFF7C8188),
                          ),
                        ),
                        IconButton(
                          tooltip: '删除(书转为未分组)',
                          iconSize: 18,
                          onPressed: () =>
                              Navigator.of(ctx).pop('delete:${g.id}'),
                          icon: const Icon(
                            Icons.delete_outline,
                            color: Color(0xFFFF6B6B),
                          ),
                        ),
                      ],
                    ),
                  ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text(
              '关闭',
              style: TextStyle(color: Color(0xFF7C8188)),
            ),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop('create'),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF5AC8FA),
              foregroundColor: const Color(0xFF0E0F12),
            ),
            child: const Text('新建分组'),
          ),
        ],
      ),
    );
    if (action == null || !mounted) return;

    // 等对话框真正从 Overlay 上摘掉,再弹下一个。
    //
    // 只用 Future.delayed(Duration.zero) 不够:那只是让出微任务队列,
    // 上一帧的 Overlay 条目可能还在卸载中。接着弹会触发:
    //   "the offending element does not appear to be a descendant of the
    //    root of the build scope"
    // 表现是新建/改名/删除分组时报错。
    // 这里等到下一帧绘制完成,确保旧的 Overlay 条目已经移除。
    await _afterNextFrame();
    if (!mounted) return;

    if (action == 'create') {
      final name = await _promptText('新建分组', '分组名', '');
      if (name == null || name.trim().isEmpty) return;
      final now = DateTime.now();
      await widget.store.upsertGroup(
        BookGroup(
          id: 'g-${now.microsecondsSinceEpoch}',
          name: name.trim(),
          sortIndex: data.groups.length,
          updatedAt: now,
        ),
      );
      await _reload();
      return;
    }

    final parts = action.split(':');
    final id = parts.length > 1 ? parts[1] : '';
    final group = data.groups.where((g) => g.id == id).firstOrNull;
    if (group == null) return;

    if (parts.first == 'rename') {
      final name = await _promptText('分组改名', '分组名', group.name);
      if (name == null || name.trim().isEmpty) return;
      await widget.store.upsertGroup(
        BookGroup(
          id: group.id,
          name: name.trim(),
          sortIndex: group.sortIndex,
          updatedAt: DateTime.now(),
        ),
      );
      await _reload();
      return;
    }

    if (parts.first == 'delete') {
      final count = data.books.where((b) => b.groupId == id).length;
      final ok = await _confirm(
        '删除分组「${group.name}」?',
        count == 0 ? '分组是空的。' : '组内 $count 本书会转为未分组,书和阅读进度都不受影响。',
      );
      if (!ok) return;
      await widget.store.deleteGroup(id);
      if (!mounted) return;
      setState(() {
        if (_activeGroupId == id) _activeGroupId = null;
      });
      await _reload();
      if (!mounted) return;
      _toast('已删除分组「${group.name}」');
    }
  }

  Future<void> _showAddDialog(_ShelfData data) async {
    final groups = <(String, String)>[
      for (final g in data.groups) (g.id, g.name),
    ];
    final result = await showDialog<AddBookResult>(
      context: context,
      builder: (_) => AddBookDialog(groups: groups),
    );
    if (result == null || !mounted) return;

    final now = DateTime.now();
    final uri = Uri.tryParse(result.url);
    final title = result.title.isNotEmpty
        ? result.title
        : (uri == null
              ? result.url
              : '${uri.host}${uri.pathSegments.isEmpty ? '' : ' · ${uri.pathSegments.last}'}');

    final overlap = data.books.where(
      (b) =>
          b.scopePrefix.startsWith(result.scope) ||
          result.scope.startsWith(b.scopePrefix),
    );

    final book = Book(
      id: 'b-${now.microsecondsSinceEpoch}',
      title: title,
      entryUrl: result.url,
      scopePrefix: result.scope,
      groupId: result.groupId,
      sortIndex: await widget.store.nextSortIndex(),
      createdAt: now,
      updatedAt: now,
    );
    await widget.store.upsertBook(book);
    if (!mounted) return;

    _reload();
    if (overlap.isNotEmpty) {
      _toast('已加入。注意:与《${overlap.first.title}》范围重叠,进度可能互相影响');
    } else {
      _toast('已加入《$title》');
    }

    // 图标在后台抓,不阻塞加书:网络慢或站点没图标都不影响用户。
    // 抓到就更新这条记录,界面下次重建时自然显示。
    unawaited(_fetchIconLater(book));
  }

  /// 后台抓封面图标与底色。失败就保持首字母兜底。
  ///
  /// 必须与 main.dart 里的启动回填用**同一套规则**,否则新加的书
  /// 和旧书观感会不一致(踩过:新加 Python 会蓝压蓝,老书却正常)。
  ///
  /// 规则:
  ///   * 图标自带不透明底框 → 卡片用那块同色(图标边界消失)
  ///   * 透明图标 → 用主色,按它自身明暗决定提亮还是压暗
  Future<void> _fetchIconLater(Book book) async {
    try {
      final icon = await IconFetcher.find(book.entryUrl);
      if (icon == null || !mounted) return;

      int? color;
      final bg = await IconPalette.backgroundOf(icon.url);
      if (bg != null) {
        // 自带底框:严格原样使用,才能和图标完全融合。
        color = 0xFF000000 | (bg & 0xFFFFFF);
      } else {
        final dom = await IconPalette.dominantOf(icon.url);
        if (dom != null) color = _contrastColor(dom);
      }
      color ??= await IconFetcher.themeColor(book.entryUrl);
      if (!mounted) return;

      // 重新读一次,避免覆盖用户在这期间做的改动。
      final fresh = (await widget.store.loadBooks())
          .where((b) => b.id == book.id)
          .firstOrNull;
      if (fresh == null) return;

      await widget.store.upsertBook(
        _copyBook(
          fresh,
          iconUrl: icon.url,
          themeColor: color ?? fresh.themeColor,
          updatedAt: DateTime.now(),
        ),
      );
      if (!mounted) return;
      _reload();
    } catch (_) {
      // 抓不到就保持首字母,不打扰用户。
    }
  }

  /// 透明图标的主色 → 卡片底色。
  ///
  /// 深色图标(Vue 的黑 V、Rust 的黑书)必须提亮底色,否则看不见;
  /// 中亮图标(Python 的蓝、TS 的蓝)必须压暗,否则蓝压蓝。
  int _contrastColor(int argb) {
    final r = (argb >> 16) & 0xFF;
    final g = (argb >> 8) & 0xFF;
    final b = argb & 0xFF;
    final luma = 0.299 * r + 0.587 * g + 0.114 * b;

    if (luma < 90) {
      const target = 168.0;
      final t = (target - luma) / (255 - luma);
      final nr = (r + (255 - r) * t * 0.82).round().clamp(0, 255);
      final ng = (g + (255 - g) * t * 0.82).round().clamp(0, 255);
      final nb = (b + (255 - b) * t * 0.82).round().clamp(0, 255);
      return 0xFF000000 | (nr << 16) | (ng << 8) | nb;
    }

    const target = 58.0;
    if (luma <= target) return 0xFF000000 | (r << 16) | (g << 8) | b;
    final t = target / luma;
    return 0xFF000000 |
        ((r * t).round().clamp(0, 255) << 16) |
        ((g * t).round().clamp(0, 255) << 8) |
        (b * t).round().clamp(0, 255);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0E0F12),
      body: SafeArea(
        child: FutureBuilder<_ShelfData>(
          future: _future,
          builder: (context, snapshot) {
            final data = snapshot.data;
            if (data == null) {
              return const Center(
                child: CircularProgressIndicator(strokeWidth: 2),
              );
            }
            final query = _query.trim().toLowerCase();
            var visible = _activeGroupId == null
                ? data.books
                : data.books.where((b) => b.groupId == _activeGroupId).toList();
            if (query.isNotEmpty) {
              visible = visible.where((b) {
                if (b.title.toLowerCase().contains(query)) return true;
                if (b.entryUrl.toLowerCase().contains(query)) return true;
                // 也搜"上次停留的页面标题",符合"我上次读的那篇讲 Pod 的"这种心智。
                final p = data.progress[b.id];
                return p != null && p.pageTitle.toLowerCase().contains(query);
              }).toList();
            }
            if (visible.isEmpty) {
              return _emptyState(data, searching: query.isNotEmpty);
            }
            return CustomScrollView(
              slivers: [
                SliverToBoxAdapter(child: _header(data)),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
                  sliver: SliverGrid(
                    gridDelegate:
                        const SliverGridDelegateWithMaxCrossAxisExtent(
                          maxCrossAxisExtent: 156,
                          mainAxisSpacing: 22,
                          crossAxisSpacing: 16,
                          childAspectRatio: 0.60,
                        ),
                    delegate: SliverChildBuilderDelegate((context, index) {
                      final book = visible[index];
                      return _BookCard(
                        book: book,
                        progress: data.progress[book.id],
                        isOpen: data.open.contains(book.id),
                        isBusy: _opening.contains(book.id),
                        isDegraded:
                            widget.engine is CdpEngine &&
                            (widget.engine as CdpEngine).isDegraded(book.id),
                        onTap: () => _openBook(book),
                        onSecondaryTap: (position) =>
                            _showBookMenu(book, position),
                      );
                    }, childCount: visible.length),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _emptyState(_ShelfData data, {bool searching = false}) {
    return Column(
      children: [
        _header(data),
        Expanded(
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  searching ? '没找到匹配的书' : '书架是空的',
                  style: const TextStyle(
                    fontSize: 16,
                    color: Color(0xFF9AA0A6),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  searching ? '试试书名、网址,或者上次读到的页面标题' : '点右上角 + 粘贴一个文档站地址',
                  style: const TextStyle(
                    fontSize: 13,
                    color: Color(0xFF6E747C),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// 右键菜单:打开、改名、改范围、复制地址、移除。
  ///
  /// 这里踩过三个坑,都已修:
  ///   1. **字号不一致** —— "从书架移除"只给了颜色没给字号,
  ///      继承默认 14,比其它项大一圈。所有项共用同一个 style。
  ///   2. **文字被截断** —— 默认字体回退链把中文渲染得偏宽,
  ///      而菜单只有 112px 最小宽度,4 个字的"复制地址"放不下。
  ///      现在给菜单 `minWidth: 168`。
  ///   3. **菜单总是贴在右边** —— 我把 right/bottom 写成 0 想"放开宽度",
  ///      但 RelativeRect 的语义是"菜单可用的矩形区域"。
  ///      写成 right=0 等于告诉 Flutter「右边一直延伸到屏幕边缘」,
  ///      于是它总往右靠。正确做法是用 Overlay 的真实尺寸算出
  ///      "光标左侧还剩多少、右侧还剩多少"。
  /// 菜单里「主题设置」这一项的返回值前缀。
  /// 菜单里「主题设置」这一项的返回值前缀。
  /// 值形如 preset:加预设id，表示用户选了某个主题；空 id 表示改回默认。
  /// 改回默认（不注入）。用前缀而不是单独值，是为了让 switch 保持扁平。
  static const _kPresetMenuValue = 'preset:';

  Future<void> _showBookMenu(Book book, Offset position) async {
    const itemStyle = TextStyle(
      color: Color(0xFFE3E5E8),
      fontSize: 13,
      fontFamily: 'Microsoft YaHei',
    );

    // 用 Overlay 的尺寸算相对位置,这样菜单才会出现在光标附近。
    final overlay =
        Overlay.of(context).context.findRenderObject()! as RenderBox;
    final rect = RelativeRect.fromRect(
      Rect.fromPoints(position, position),
      Offset.zero & overlay.size,
    );

    final action = await showMenu<String>(
      context: context,
      position: rect,
      color: const Color(0xFF1C1E22),
      // 加边框:菜单底色 #1C1E22 和深色书籍封面(#15141A 左右)
      // 亮度差只有 9,低于肉眼可分辨的阈值,叠上去边界会糊掉。
      // 一条细边框比调背景色更稳 —— 不管底下是什么颜色都能区分。
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(6),
        side: const BorderSide(color: Color(0xFF3A3F47), width: 1),
      ),
      // 给菜单一个下限,避免窄屏或贴着右边缘时被压到 112px。
      constraints: const BoxConstraints(minWidth: 168),
      items: [
        PopupMenuItem(
          value: 'open',
          height: 40,
          child: const Text('打开', style: itemStyle),
        ),
        PopupMenuItem(
          value: 'rename',
          height: 40,
          child: const Text('改名', style: itemStyle),
        ),
        PopupMenuItem(
          value: 'scope',
          height: 40,
          child: const Text('改范围', style: itemStyle),
        ),
        // 移动到分类:建完书之后唯一能改分类的入口。
        //
        // 之前只能在建书时选分类,建完就固定了 ——
        // 用户想整理书架必须删了重加,这显然不合理。
        PopupMenuItem(
          value: 'move',
          height: 40,
          child: const Text('移动到分类', style: itemStyle),
        ),
        // 「主题设置」用悬停展开的子菜单，而不是二级弹窗。
        //
        // 右键菜单里再弹对话框会打断操作节奏；子菜单能把
        // 「有哪几套主题、当前用的是哪套」一次摊开看清楚。
        PopupMenuItem(
          value: _kPresetMenuValue,
          height: 40,
          child: const _PresetMenuLabel(),
        ),
          PopupMenuItem(
          value: 'copy',
          height: 40,
          child: const Text('复制地址', style: itemStyle),
        ),
        const PopupMenuDivider(),
        PopupMenuItem(
          value: 'delete',
          height: 40,
          // 危险操作用红色,但字号必须和上面一致 —— 这是另一个坑。
          child: const Text(
            '从书架移除',
            style: TextStyle(
              color: Color(0xFFFF6B6B),
              fontSize: 13,
              fontFamily: 'Microsoft YaHei',
            ),
          ),
        ),
      ],
    );
    if (action == null || !mounted) return;

    // 同上:等旧对话框完全卸载后再弹下一个。
    await _afterNextFrame();
    if (!mounted) return;

    switch (action) {
      case 'open':
        await _openBook(book);
      case 'rename':
        final name = await _promptText('改名', '书名', book.title);
        if (name == null || name.trim().isEmpty) return;
        await widget.store.upsertBook(
          _copyBook(book, title: name.trim(), updatedAt: DateTime.now()),
        );
        await _reload();
      case 'scope':
        final scope = await _promptText(
          '改范围',
          '这个前缀下的页面算同一本书',
          book.scopePrefix,
        );
        if (scope == null || scope.trim().isEmpty) return;
        // 进度按 URL 存,与范围解耦:改范围不删任何进度,
        // 书架重新计算断点时会自然只取落在新范围内的最新一条。
        await widget.store.upsertBook(
          _copyBook(book, scopePrefix: scope.trim(), updatedAt: DateTime.now()),
        );
        await _reload();
      case _kPresetMenuValue:
        final picked = await _showPresetSubmenu(book, position);
        if (picked == null) return;
        final isDefault = picked == kDefaultPresetId;
        await widget.store.upsertBook(
          _copyBook(
            book,
            presetId: isDefault ? null : picked,
            clearPreset: isDefault,
            updatedAt: DateTime.now(),
          ),
        );
        await _reload();
        if (!mounted) return;
        _toast(isDefault ? '已改为默认（不注入）' : '已应用主题');
      case 'copy':
        await Clipboard.setData(ClipboardData(text: book.entryUrl));
        if (!mounted) return;
        _toast('地址已复制');
      case 'move':
        await _moveToGroup(book);
      case 'delete':
        final ok = await _confirm('移除《${book.title}》?', '进度和封面缓存会一起删除。');
        if (!ok) return;
        await widget.store.deleteBook(book.id);
        await _reload();
        if (!mounted) return;
        _toast('已移除《${book.title}》');
    }
  }


  /// 主题选择子菜单。
  ///
  /// Flutter 的 showMenu 不支持「悬停展开二级菜单」，这里在父菜单右侧
  /// 再开一层 —— 比弹对话框轻，也比让用户先进设置页改再回来快。
  ///
  /// 返回预设 id 或 [kDefaultPresetId]；点空白处取消返回 null。
  Future<String?> _showPresetSubmenu(Book book, Offset position) async {
    final presets = ProviderScope.containerOf(
      context,
    ).read(themePresetsProvider);
    const labelStyle = TextStyle(
      color: Color(0xFFE3E5E8),
      fontSize: 13,
      fontFamily: 'Microsoft YaHei',
    );
    final overlay =
        Overlay.of(context).context.findRenderObject()! as RenderBox;
    // 贴在父菜单右侧展开：父菜单宽约 168，这里再往右让出一点。
    final rect = RelativeRect.fromRect(
      Rect.fromLTWH(position.dx + 156, position.dy + 18, 0, 0),
      Offset.zero & overlay.size,
    );

    Widget row(String text, bool selected, {Color? swatch}) => Row(
      children: [
        Container(
          width: 14,
          height: 14,
          decoration: BoxDecoration(
            color: swatch ?? const Color(0xFF2C3038),
            borderRadius: BorderRadius.circular(3),
            border: Border.all(color: const Color(0xFF3A3F47)),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(child: Text(text, style: labelStyle)),
        if (selected)
          const Icon(Icons.check, size: 15, color: Color(0xFF5AC8FA)),
      ],
    );

    return showMenu<String>(
      context: context,
      position: rect,
      color: const Color(0xFF1C1E22),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(6),
        side: const BorderSide(color: Color(0xFF3A3F47), width: 1),
      ),
      constraints: const BoxConstraints(minWidth: 190),
      items: [
        PopupMenuItem(
          value: kDefaultPresetId,
          height: 40,
          child: row('默认（不注入）', book.presetId == null),
        ),
        const PopupMenuDivider(),
        for (final p in presets)
          PopupMenuItem(
            value: p.id,
            height: 40,
            child: row(
              p.name,
              book.presetId == p.id,
              swatch: Color(p.backgroundArgb),
            ),
          ),
      ],
    );
  }
  Book _copyBook(
    Book b, {
    String? title,
    String? scopePrefix,
    String? groupId,
    String? iconUrl,
    int? themeColor,
    DateTime? updatedAt,
    String? presetId,
    bool clearPreset = false,
  }) => Book(
    id: b.id,
    title: title ?? b.title,
    entryUrl: b.entryUrl,
    scopePrefix: scopePrefix ?? b.scopePrefix,
    iconUrl: iconUrl ?? b.iconUrl,
    themeColor: themeColor ?? b.themeColor,
    groupId: groupId ?? b.groupId,
    sortIndex: b.sortIndex,
    presetId: clearPreset ? null : (presetId ?? b.presetId),
    createdAt: b.createdAt,
    updatedAt: updatedAt ?? b.updatedAt,
    deletedAt: b.deletedAt,
  );

  /// 把一本书移到另一个分类(或移到「未分组」)。
  ///
  /// ── 为什么必须更新 updatedAt ──
  ///
  /// 同步按 updatedAt 判断谁更新。如果只改 groupId 不动时间戳,
  /// 另一端会认为"这边没有新变化",分类改动同步不过去 ——
  /// 表现就是"手机上分了类,电脑上还是原来那样"。
  ///
  /// 移到「未分组」时 groupId 传 null,所以不能复用 _copyBook
  /// (它的 `groupId ?? b.groupId` 会把 null 当成"不改")。
  Future<void> _moveToGroup(Book book) async {
    final groups = await widget.store.loadGroups();
    if (!mounted) return;

    final picked = await showDialog<String?>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF191B1F),
        title: const Text(
          '移动到分类',
          style: TextStyle(
            color: Color(0xFFF2F3F5),
            fontSize: 16,
            fontFamily: 'Microsoft YaHei',
          ),
        ),
        content: SizedBox(
          width: 320,
          child: ListView(
            shrinkWrap: true,
            children: [
              // 「未分组」永远在第一个 —— 从分类移出去也要有入口。
              _MoveOption(
                label: '未分组',
                selected: (book.groupId ?? '').isEmpty,
                onTap: () => Navigator.of(ctx).pop(''),
              ),
              for (final g in groups)
                _MoveOption(
                  label: g.name,
                  selected: book.groupId == g.id,
                  onTap: () => Navigator.of(ctx).pop(g.id),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(null),
            child: const Text(
              '取消',
              style: TextStyle(
                color: Color(0xFF9AA0A6),
                fontFamily: 'Microsoft YaHei',
              ),
            ),
          ),
        ],
      ),
    );

    // null = 取消;空串 = 移到未分组
    if (picked == null) return;
    final newGroupId = picked.isEmpty ? null : picked;
    if (newGroupId == book.groupId) return;

    await widget.store.upsertBook(
      Book(
        id: book.id,
        title: book.title,
        entryUrl: book.entryUrl,
        scopePrefix: book.scopePrefix,
        iconUrl: book.iconUrl,
        themeColor: book.themeColor,
        groupId: newGroupId,
        sortIndex: book.sortIndex,
        createdAt: book.createdAt,
        // 关键:更新时间戳,同步才知道这边变了。
        updatedAt: DateTime.now(),
        deletedAt: book.deletedAt,
      ),
    );
    await _reload();
    if (!mounted) return;
    final name = newGroupId == null
        ? '未分组'
        : groups.firstWhere((g) => g.id == newGroupId).name;
    _toast('已移到「$name」');
  }

  Future<String?> _promptText(String title, String label, String initial) async {
    final controller = TextEditingController(text: initial);
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF191B1F),
        title: Text(
          title,
          style: const TextStyle(color: Color(0xFFF2F3F5), fontSize: 17),
        ),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: const TextStyle(color: Color(0xFFE3E5E8), fontSize: 14),
          decoration: InputDecoration(
            labelText: label,
            labelStyle: const TextStyle(color: Color(0xFF7C8188)),
          ),
          onSubmitted: (v) => Navigator.of(ctx).pop(v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text(
              '取消',
              style: TextStyle(color: Color(0xFF7C8188)),
            ),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF5AC8FA),
              foregroundColor: const Color(0xFF0E0F12),
            ),
            child: const Text('确定'),
          ),
        ],
      ),
    );
    // 不能立刻 dispose:对话框的退出动画还在播放,
    // TextField 仍在渲染并持有这个 controller。
    // 立刻销毁会让"确定/取消"之后的某一帧访问到已释放的对象,
    // 触发 build scope / RawGestureDetector 断言。
    // 等对话框彻底消失再释放。
    Future<void>.delayed(const Duration(milliseconds: 400), controller.dispose);
    return result;
  }

  Future<bool> _confirm(String title, String detail) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF191B1F),
        title: Text(
          title,
          style: const TextStyle(color: Color(0xFFF2F3F5), fontSize: 16),
        ),
        content: Text(
          detail,
          style: const TextStyle(color: Color(0xFF9AA0A6), fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text(
              '取消',
              style: TextStyle(color: Color(0xFF7C8188)),
            ),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFFF6B6B),
              foregroundColor: const Color(0xFF0E0F12),
            ),
            child: const Text('移除'),
          ),
        ],
      ),
    );
    return ok ?? false;
  }

  Widget _header(_ShelfData data) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 12, 8),
          child: Row(
            children: [
              const Text(
                '书架',
                style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFFF2F3F5),
                ),
              ),
              // Spacer 占掉中间所有剩余空间,把按钮推到右边。
              //
              const Spacer(),
              // 按钮顺序:同步 → 设置 → 搜索 → 加书。
              IconButton(
                onPressed: _openSync,
                tooltip: '同步',
                icon: const Icon(Icons.sync, color: Color(0xFF9AA0A6)),
              ),
              IconButton(
                onPressed: _openSettings,
                tooltip: '设置',
                icon: const Icon(
                  Icons.settings_outlined,
                  color: Color(0xFF9AA0A6),
                ),
              ),
              if (_searching)
                SizedBox(
                  width: 260,
                  height: 34,
                  child: TextField(
                    controller: _searchController,
                    autofocus: true,
                    style: const TextStyle(
                      color: Color(0xFFE3E5E8),
                      fontSize: 13,
                    ),
                    decoration: const InputDecoration(
                      isDense: true,
                      hintText: '书名 / 网址 / 页面标题',
                      hintStyle: TextStyle(
                        color: Color(0xFF4A4F56),
                        fontSize: 12,
                      ),
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 8,
                      ),
                      filled: true,
                      fillColor: Color(0xFF191B1F),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.all(Radius.circular(8)),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                )
              else
                IconButton(
                  onPressed: () {
                    setState(() {
                      _searching = true;
                    });
                  },
                  tooltip: '搜索',
                  icon: const Icon(Icons.search, color: Color(0xFF9AA0A6)),
                ),
              IconButton(
                onPressed: () => _showAddDialog(data),
                tooltip: '加一本书',
                icon: const Icon(Icons.add, color: Color(0xFF9AA0A6)),
              ),
              if (widget.engine is CdpEngine)
                IconButton(
                  onPressed: () => _openDiagnostics(),
                  tooltip: '诊断',
                  icon: const Icon(
                    Icons.monitor_heart_outlined,
                    color: Color(0xFF9AA0A6),
                    size: 20,
                  ),
                ),
            ],
          ),
        ),
        SizedBox(
          height: 44,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            children: [
              _GroupChip(
                label: '全部',
                selected: _activeGroupId == null,
                onTap: () {
                  setState(() {
                    _activeGroupId = null;
                  });
                },
              ),
              for (final group in data.groups)
                _GroupChip(
                  label: group.name,
                  selected: _activeGroupId == group.id,
                  onTap: () {
                    setState(() {
                      _activeGroupId = group.id;
                    });
                  },
                ),
              // 分组管理入口:放在标签末尾,和筛选标签同一行。
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: GestureDetector(
                  onTap: () => _manageGroups(data),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: const Color(0xFF2A2D33)),
                    ),
                    child: const Icon(
                      Icons.tune,
                      size: 16,
                      color: Color(0xFF7C8188),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
      ],
    );
  }
}

class _ShelfData {
  const _ShelfData({
    required this.groups,
    required this.books,
    required this.progress,
    required this.open,
  });

  final List<BookGroup> groups;
  final List<Book> books;
  final Map<String, ProgressSnapshot> progress;
  final Set<String> open;
}

class _GroupChip extends StatelessWidget {
  const _GroupChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? const Color(0xFF2A2D33) : Colors.transparent,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 14,
              color: selected
                  ? const Color(0xFFF2F3F5)
                  : const Color(0xFF7C8188),
              fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
            ),
          ),
        ),
      ),
    );
  }
}

class _BookCard extends StatelessWidget {
  const _BookCard({
    required this.book,
    required this.progress,
    required this.isOpen,
    required this.isBusy,
    required this.onTap,
    this.onSecondaryTap,
    this.isDegraded = false,
  });

  final Book book;
  final ProgressSnapshot? progress;
  final bool isOpen;
  final bool isBusy;
  final VoidCallback onTap;

  /// 右键菜单。桌面端有,移动端没有(那边用长按)。
  final void Function(Offset position)? onSecondaryTap;

  /// 这本书是否处于降级模式(CDP 打不开,进度会丢)。
  /// 必须显示出来,不能静默丢数据。
  final bool isDegraded;

  @override
  Widget build(BuildContext context) {
    final base = book.themeColor != null
        ? Color(book.themeColor!)
        : const Color(0xFF23262B);
    final initial = book.title.characters.first;
    final hasIcon = (book.iconUrl ?? '').isNotEmpty;

    return GestureDetector(
      onTap: onTap,
      // 长按:手机端唯一的菜单入口。
      //
      // 桌面端有右键(onSecondaryTapDown),但手机上根本没有右键 ——
      // 之前只接了右键,导致手机用户完全无法改名/改范围/删除。
      //
      // 用 onLongPressStart 而不是 onLongPress:前者能拿到手指坐标,
      // 菜单可以弹在手指附近,而不是屏幕固定位置。
      onLongPressStart: onSecondaryTap == null
          ? null
          : (details) => onSecondaryTap!(details.globalPosition),
      onSecondaryTapDown: onSecondaryTap == null
          ? null
          : (details) => onSecondaryTap!(details.globalPosition),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                // 有图标时必须用纯色。
                // 渐变会让白底图标的边框和卡片差一档,边界又冒出来 ——
                // 那就白做"融合"了。没图标(首字母)时才用渐变加层次。
                color: hasIcon ? base : null,
                gradient: hasIcon
                    ? null
                    : LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          Color.lerp(base, Colors.white, 0.10)!,
                          Color.lerp(base, Colors.black, 0.35)!,
                        ],
                      ),
                border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
              ),
              child: Stack(
                children: [
                  Center(
                    child: isBusy
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : _cover(initial),
                  ),
                  // 降级徽章:这本书 CDP 打不开、进度会丢,必须让用户看见。
                  if (isDegraded)
                    Positioned(
                      left: 8,
                      top: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 5,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFB454).withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text(
                          '不记进度',
                          style: TextStyle(
                            fontSize: 9,
                            color: Color(0xFFFFB454),
                          ),
                        ),
                      ),
                    ),
                  if (isOpen)
                    Positioned(
                      right: 8,
                      top: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFF5AC8FA).withValues(alpha: 0.18),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text(
                          '阅读中',
                          style: TextStyle(
                            fontSize: 10,
                            color: Color(0xFF5AC8FA),
                          ),
                        ),
                      ),
                    ),
                  if (progress != null)
                    Positioned(
                      right: 8,
                      bottom: 8,
                      child: Container(
                        width: 6,
                        height: 6,
                        decoration: const BoxDecoration(
                          color: Color(0xFF5AC8FA),
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            book.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 13,
              color: Color(0xFFE3E5E8),
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            _metaText(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 11, color: Color(0xFF6E747C)),
          ),
        ],
      ),
    );
  }

  /// 封面:图标坐在与它同色的底上,或者是首字母 + 站点色。
  ///
  /// 关键:底色必须由图标类型决定(见 main.dart 的底色回填逻辑):
  ///   * 自带不透明底框的图标(K8s 白底、MDN 深底)→ 卡片用那块同色,
  ///     图标边界消失,整张卡片就是封面。
  ///   * 透明图标(Python/Vue 的 SVG)→ 卡片用主色的深色版,
  ///     保证图标在深底上看得清。否则会蓝压蓝,图标直接消失。
  ///
  /// 图标走磁盘缓存(CachedCover):Image.network 只有内存缓存,
  /// 应用重启就全部重下;缓存后只有第一次联网。
  Widget _cover(String initial) {
    final iconUrl = book.iconUrl;
    if (!isRemoteIcon(iconUrl)) {
      return _initialTile(initial);
    }

    // 统一 padding:SVG 和 PNG 用同一个值。
    // 之前给 SVG 多 6 像素,人为制造了大小差,没必要。
    //
    // 28 是实测值:SizedBox.expand 让图标按最长边撑满可用区域,
    // padding 太小会顶到卡片边(视觉上"图溢出来"),
    // 28 四周留出均匀呼吸空间,四个图标看起来大小一致。
    return CachedCover(
      url: iconUrl!,
      fallback: _initialTile(initial),
      padding: 28,
    );
  }

  String _metaText() {
    final snapshot = progress;
    if (snapshot == null) return '未开始';

    // 优先显示章节号:书架上一排「3 天前 · 第 12 章」比一排完整页面标题好扫。
    // 提不到章节号才退回原页面标题。
    final chapter = ChapterExtractor.extract(snapshot.pageTitle);
    final label = chapter ?? snapshot.pageTitle;
    return '${_relative(snapshot.updatedAt)} · $label';
  }

  Widget _initialTile(String initial) => Text(
    initial,
    style: TextStyle(
      fontSize: 44,
      fontWeight: FontWeight.w700,
      color: Colors.white.withValues(alpha: 0.88),
    ),
  );

  static String _relative(DateTime at) {
    final diff = DateTime.now().difference(at);
    if (diff.inMinutes < 60) return '${diff.inMinutes} 分钟前';
    if (diff.inHours < 24) return '${diff.inHours} 小时前';
    if (diff.inDays < 30) return '${diff.inDays} 天前';
    return '${(diff.inDays / 30).floor()} 个月前';
  }
}

/// 「移动到分类」对话框里的一行。
///
/// 当前所在的分类右侧打勾,让用户知道现在在哪。
class _MoveOption extends StatelessWidget {
  const _MoveOption({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        margin: const EdgeInsets.only(bottom: 4),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFF23262B) : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  color: selected
                      ? const Color(0xFFF2F3F5)
                      : const Color(0xFFC4C8CC),
                  fontSize: 14,
                  fontFamily: 'Microsoft YaHei',
                ),
              ),
            ),
            if (selected)
              const Icon(Icons.check, size: 16, color: Color(0xFF5AC8FA)),
          ],
        ),
      ),
    );
  }
}
/// 右键菜单里「主题设置」那一项。
///
/// 该项本身不执行动作，只是把鼠标悬停变成展开子菜单的信号 ——
/// 见 _showBookMenu 里对 _kPresetMenuValue 的处理。
class _PresetMenuLabel extends StatelessWidget {
  const _PresetMenuLabel();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Expanded(
          child: Text(
            '主题设置',
            style: TextStyle(
              color: Color(0xFFE3E5E8),
              fontSize: 13,
              fontFamily: 'Microsoft YaHei',
            ),
          ),
        ),
        const Icon(Icons.chevron_right, size: 16, color: Color(0xFF8A9099)),
      ],
    );
  }
}

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../../core/domain/anchor_script.dart';
import '../../core/domain/diagnostics.dart';
import '../../core/domain/models.dart';
import '../../core/domain/url_normalizer.dart';
import '../../core/ports/ports.dart';

/// 启动浏览器失败,且原因需要让用户看见。
class CdpLaunchError implements Exception {
  const CdpLaunchError(this.message);

  final String message;

  @override
  String toString() => message;
}

/// 桌面端引擎:驱动外部 Chromium(Edge / Chrome)的 `--app` 窗口。
///
/// 实测结论(别改回去):
///
/// 1. `--app=<url>` + 固定调试端口一次启动就能同时得到
///    "无标签栏无地址栏的 app 窗口" 和 "可用的 CDP 端口"。
///    早期用 `about:blank` 保活再 `Target.createTarget` 是错的 ——
///    那样开出来的是普通标签页,所以会看到标签栏和地址栏。
///
/// 2. 浏览器已经在跑时,同一个 profile 再 spawn 会只转发 URL 就退出。
///    所以要提前检测并提示用户先退出浏览器 —— 见 CdpLaunchError。
///
/// 3. 必须连 browser target,再用 `Target.attachToTarget(flatten)` 拿 sessionId;
///    直接连 page target 的 WebSocket 会连上但收不到任何响应。
///
/// 4. 子进程 stdout/stderr 必须 drain,否则 Edge 日志写满管道会让浏览器假死。
///
/// 5. Chromium 是单实例的。上次进程被强杀留下的孤儿浏览器会占住 profile,
///    导致这次 spawn 只转发 URL 就退出、不写 DevToolsActivePort。
///    所以启动前必须清孤儿进程。
///
/// 6. `Target.getTargets` 返回的字段名是 `targetId`,不是 `id`。
///
/// 7. **用真实 profile 时不写 `DevToolsActivePort`。**
///    独立 profile 会写,真实 profile(指向用户日常的 User Data)不写 ——
///    实测等 30 秒也没有。所以必须用固定端口直接探。
///    这也是能不能用上用户插件的关键:独立 profile 能拿端口但没插件,
///    真实 profile 有插件但只能靠固定端口。
///
/// 8. **不要用 `--app-id`。**
///    Chromium 的 web app 走 `pwahelper.exe`,那是独立 helper 进程,
///    不持有调试端口 —— 实测 CDP 只能连 5 秒就断。
///    `--app=<url>` 效果等同"应用窗口"但仍在主进程内,CDP 可长期保持。
class CdpEngine implements WebEngine {
  CdpEngine({
    required this.browserPath,
    required this.profileDir,
    this.profileName = 'Default',
    this.headless = false,
    this.debugPort = defaultDebugPort,
  });

  final String browserPath;
  final Directory profileDir;

  /// 用哪个 profile 子目录。
  ///
  /// 不能写死 `Default`:用户可能用多账号,主 profile 叫 `Profile 1`
  /// 甚至从没碰过 Default。由 `BrowserProfile.defaultProfileName()`
  /// 读 `Local State` 里的 `last_used` 决定。
  final String profileName;

  final bool headless;

  /// 固定调试端口。
  ///
  /// 用真实 profile 时 Chromium 不写端口文件,只能靠固定端口连。
  /// 选 9333:高位、不常见、与常见调试端口(9222/9223)错开。
  final int debugPort;

  static const defaultDebugPort = 9333;



  Process? _process;
  WebSocket? _ws;
  int _nextId = 0;

  /// 启动/预热时那个空白窗口的 targetId,等着被第一本书用掉。
  String? _spareTarget;

  /// 引擎内的一次性回调:某本书打开完成后通知外部"可以开始记录了"。
  ///
  /// 为什么需要它:用 `--app=<url>` 打开时,页面加载发生在
  /// 我们 `Page.enable` 之前,`frameNavigated` 事件收不到。
  /// 也就是说用户"打开一本书"这个动作本身不会产生任何导航事件,
  /// 记录器就没有机会写入第一条进度 —— 表现为"从来没记录过"。
  void Function(String bookId)? onBookOpened;

  final Map<int, Completer<Map<String, dynamic>>> _pending = {};
  final Map<String, String> _bookToTarget = {};
  final Map<String, String> _targetToSession = {};
  final Map<String, String> _sessionToBook = {};

  /// 页面主动上报的位置流。事件驱动,静止时不会产生任何数据。
  final StreamController<PositionReport> _reports =
      StreamController<PositionReport>.broadcast();

  /// 页面里那个回调函数的名字,注册的是 window.__prReport。
  static const _bindingName = '__prReport';
  final StreamController<NavigationEvent> _navs =
      StreamController<NavigationEvent>.broadcast();

  @override
  String get id => 'cdp';

  @override
  Stream<NavigationEvent> get navigations => _navs.stream;

  @override
  Stream<PositionReport> get positionReports => _reports.stream;

  @override
  Set<String> get openBooks => Set.unmodifiable(_bookToTarget.keys);

  bool get isRunning => _ws != null;

  int get sessionCount => _targetToSession.length;

  /// 调试用。
  String? debugTargetFor(String bookId) => _bookToTarget[bookId];

  Future<Map<String, dynamic>> debugCall(
    String method, [
    Map<String, dynamic>? params,
  ]) => _send(method, params: params);

  /// 调试用:在当前页面执行一段 JS(取第一个受管 session)。
  Future<dynamic> debugEval(String expression) async {
    final session = _targetToSession.values.isEmpty
        ? null
        : _targetToSession.values.first;
    if (session == null) return null;
    return _eval(expression, session);
  }

  // ---------------------------------------------------------------- 启动

  /// 预热:提前把浏览器进程拉起来并连上 CDP。
  ///
  /// 只启动进程,不指望复用那个空白窗口 ——
  /// 复用反而要「先导航再等加载」,比新开一个窗口更慢(实测 4.6s vs 1.6s)。
  /// 真正省下的是 Chromium 冷启动那 3~5 秒。
  Future<void> prewarm() async {
    await _ensureStarted('about:blank', hideWindow: true);
  }

  /// 把一个藏在屏幕外的窗口挪到可见位置。
  /// 把窗口移到可见区并最大化。
  ///
  /// 阅读类产品里,每本书打开后都应该占满画面 ——
  /// 否则同一个站有时大有时小,阅读体验不一致。
  ///
  /// 用 `windowState: 'maximized'` 而不是给一个很大的 width/height:
  /// 后者在 4K 屏上仍然填不满,而且不会吸附到任务栏边缘。
  /// 实测 maximize 后 bounds 会变成 {-7,-7,1294,814}(Windows 的
  /// 最大化边框补偿),这是正常的。
  Future<void> revealTarget(String targetId) async {
    final res = await _send('Browser.getWindowForTarget', params: {
      'targetId': targetId,
    });
    // 注意:_send 返回的已经是 result 对象本身
    // (见 _onMessage 里 completer.complete(map['result']))。
    // 之前写成 res['result']['windowId'] 多取了一层,
    // 永远拿到 null,导致最大化静默失败。
    final win = res['windowId'];
    if (win is! int) {
      _lastError = '未找到窗口: $targetId';
      return;
    }

    // 预热时窗口被藏在屏幕外(-4000,-4000)。
    // 直接给 maximized 在某些情况下会被"藏在屏幕外"的状态干扰,
    // 所以先把位置挪回屏幕内,再最大化。
    final cur = await _send('Browser.getWindowBounds', params: {
      'windowId': win,
    });
    final bounds = cur['bounds'];
    final state = (bounds as Map?)?['windowState'];
    if (state == 'maximized') return;

    // 步骤 1:挪回可见区。必须给完整的 left/top/width/height,
    // 只给 windowState 时 Chrome 有时会忽略(实测)。
    await _send('Browser.setWindowBounds', params: {
      'windowId': win,
      'bounds': {'left': 100, 'top': 60, 'width': 1200, 'height': 860},
    });
    await Future<void>.delayed(const Duration(milliseconds: 150));

    // 步骤 2:最大化。单独一次调用,不和上面的位置调整合并。
    await _send('Browser.setWindowBounds', params: {
      'windowId': win,
      'bounds': {'windowState': 'maximized'},
    });

    // 步骤 3:回读确认。不确认就等于"以为设了"。
    await Future<void>.delayed(const Duration(milliseconds: 200));
    final check = await _send('Browser.getWindowBounds', params: {
      'windowId': win,
    });
    final cb = check['bounds'];
    if ((cb as Map?)?['windowState'] != 'maximized') {
      _lastError = '窗口最大化失败: ${cb?['windowState']}';
    }
  }

  /// 第一次启动需要知道首本书的 URL:用 `--app=<url>` 一次开出正确的窗口。
  ///
  /// `hideWindow` 为真时把窗口放到屏幕外,用于预热:
  /// 浏览器提前跑起来,但用户不会看到一个空白窗口跳出来。
  Future<void> _ensureStarted(String firstUrl, {bool hideWindow = false}) async {
    if (_ws != null) return;
    profileDir.createSync(recursive: true);

    final portFile = File(
      '${profileDir.path}${Platform.pathSeparator}DevToolsActivePort',
    );

    // 释放上一次留下的浏览器进程与过期端口文件。
    await _killOrphans();
    if (portFile.existsSync()) {
      try {
        portFile.deleteSync();
      } catch (_) {}
    }
    // 清理 Chromium 的单实例锁。
    //
    // 为什么必须做:上一次异常退出(崩溃、强杀、断电)会留下
    // SingletonLock / SingletonCookie / SingletonSocket / lockfile。
    // 新进程看到这些会认为"已有实例在跑",于是把 URL 转发给它然后
    // 自己以 exit code 0 退出 —— 表现是点击书籍完全没反应,
    // 而进程列表里一个 Edge 都没有。
    _clearSingletonLocks();

    // 用真实 profile 时,浏览器可能正被用户自己开着(甚至只是
    // 后台常驻的 `--no-startup-window`)。那种情况下新进程只会把 URL
    // 转发给已有实例然后退出,调试端口拿不到。
    //
    // 这里不提示用户"请先退出 Edge" —— 那是在推卸责任。
    // 上面的 _killOrphans 已经把这款浏览器的进程清干净了,
    // 接下来我们带端口启动自己的实例,由我们持有端口。

    final first = await Process.start(browserPath, [
      if (headless) '--headless=new',
      '--disable-gpu',
      '--no-first-run',
      '--no-default-browser-check',
      // 关掉同步/首次运行引导:否则会多出一个
      // edge://sync-confirmation-dialog/ 窗口,用户会以为打开了两个页面。
      '--disable-sync',
      '--disable-features=msEdgeSyncConfirmationDialog,EdgeSyncPromo',
      '--remote-allow-origins=*',
      // 固定端口。
      //
      // 为什么不用 0(系统随机分配):用真实 profile 时 Chromium
      // **不写 DevToolsActivePort 文件**(实测等 30 秒也没有),
      // 只能靠固定端口直接连 /json/version。这是能否用上用户插件
      // 的关键 —— 独立 profile 能写端口文件,但里面没有任何插件。
      '--remote-debugging-port=$debugPort',
      '--user-data-dir=${profileDir.path}',
      '--profile-directory=$profileName',
      // 不指定窗口尺寸时,--app 窗口可能被系统给一个很矮的高度,
      // 内容一屏就装下,于是永远"不可滚动",锚点也就永远是 0。
      '--window-size=1100,900',
      if (hideWindow && !headless) '--window-position=-4000,-4000',
      if (headless) firstUrl else '--app=$firstUrl',
    ]);
    _drain(first);
    _process = first;

    var alive = true;
    first.exitCode.then((_) => alive = false);

    // 两条路并行:优先看端口文件(独立 profile 会写),
    // 否则直接探端口(真实 profile 不写文件)。
    final port = await _waitForPort(portFile, () => alive) ??
        await _waitForDebugPort(debugPort, () => alive);
    if (port == null) {
      // 诊断信息:把关键事实都带上,方便定位"为什么拿不到端口"。
      //
      // 最常见的原因:
      //   * profile 被另一个浏览器实例占用(用户自己开着 Edge)
      //   * 启动参数没生效(比如 profile-directory 指向不存在的名字)
      final diag = StringBuffer()
        ..write('拿不到 DevTools 端口')
        ..write('\n  profile: ${profileDir.path}')
        ..write('\n  profileName: $profileName')
        ..write('\n  debugPort: $debugPort')
        ..write('\n  端口文件存在: ${portFile.existsSync()}')
        ..write('\n  进程存活: $alive');
      throw StateError(diag.toString());
    }

    _lastPort = port;

    // 从这里到连上 CDP 之间任何一步失败,都会让整次启动白费 ——
    // 浏览器看着起来了(端口也在),但拿不到 WS 就等于没有进度。
    // 所以每一步都留痕,方便定位。
    void trace(String msg) {
      try {
        final f = File(
          p.join(profileDir.parent.path, 'pagereader-cdp.log'),
        );
        f.writeAsStringSync(
          '${DateTime.now().toIso8601String()} $msg\n',
          mode: FileMode.append,
          flush: true,
        );
      } catch (_) {}
    }

    trace('端口就绪: $port');
    String wsUrl;
    try {
      wsUrl = await _browserWsUrl(port);
      trace('拿到 wsUrl: $wsUrl');
    } catch (e) {
      trace('取 wsUrl 失败: $e');
      rethrow;
    }

    WebSocket ws;
    try {
      ws = await WebSocket.connect(
        wsUrl,
      ).timeout(const Duration(seconds: 15));
      trace('WS 已连接');
    } catch (e) {
      trace('WS 连接失败: $e');
      rethrow;
    }
    _ws = ws;
    ws.listen(_onMessage, onDone: () => _ws = null);

    // 记下启动时那个空白/新标签窗口,第一本书直接复用它,
    // 这样预热之后不会再多开一个窗口。
    if (!headless) {
      _spareTarget = await _pickAppTarget();
      trace('spareTarget: $_spareTarget');
    }

    // 接管遗留窗口:浏览器可能在上一次应用被杀之后继续活着,
    // 那些窗口现在没人管,上报的 session 映射不到书,数据会被丢掉。
    // 这里连上去把它们认领回来并补注入,进度才能继续记。
    await adoptOrphanWindows();
  }

  /// 认领"上一次应用退出后仍开着"的阅读窗口。
  ///
  /// 判据:窗口里已经有内容 URL(不是空白页),而且当前没有映射。
  /// 书归属按 URL 前缀匹配 —— 引擎记得每本书的 scopePrefix 就能反查。
  Future<void> adoptOrphanWindows() async {
    if (_ws == null) return;
    final infos = await _listTargets();
    final claimed = _targetToSession.keys.toSet();

    for (final t in infos) {
      if (t['type'] != 'page') continue;
      final targetId = t['targetId'] as String?;
      if (targetId == null || targetId.isEmpty) continue;
      if (claimed.contains(targetId)) continue;
      final url = t['url'] as String? ?? '';
      if (url.isEmpty || url == 'about:blank') continue;
      if (url.startsWith('edge://') || url.startsWith('chrome://')) continue;

      // 反查这本窗口属于哪本书。
      String? bookId;
      for (final entry in _knownScopes.entries) {
        if (url.startsWith(entry.value)) {
          bookId = entry.key;
          break;
        }
      }
      if (bookId == null) continue;

      try {
        final session = await _attach(targetId, bookId);
        await _send('Page.enable', sessionId: session);
        await _send('Runtime.enable', sessionId: session);
        await _send(
          'Runtime.addBinding',
          params: {'name': _bindingName},
          sessionId: session,
        );
        await _send(
          'Runtime.evaluate',
          params: {
            'expression':
                'try{$positionReportScript}catch(e){}'
                'try{$anchorBootstrapScript}catch(e){}',
          },
          sessionId: session,
        );
        onBookOpened?.call(bookId);
      } catch (_) {
        // 单个窗口认领失败不影响其它。
      }
    }
  }

  /// 已登记的书 → 范围前缀。用于反查孤儿窗口归属。
  final Map<String, String> _knownScopes = {};

  /// 登记一本书的范围前缀,供接手孤儿窗口时反查。
  void registerScope(String bookId, String scopePrefix) {
    _knownScopes[bookId] = scopePrefix;
  }

  void _drain(Process proc) {
    // 丢弃浏览器的输出。
    //
    // ⚠ 曾经试过把输出写进文件,结果 Edge 反而拒绝开调试端口
    // (报 "DevTools remote debugging requires a non-default data
    //  directory")。所以保持最简单的 drain。
    proc.stdout.drain<void>();
    proc.stderr.drain<void>();
  }

  /// 杀掉所有用我们这个 profile 的浏览器进程(只杀我们自己的,不碰日常浏览器)。
  /// 删掉 Chromium 的单实例锁文件。
  ///
  /// 这四个文件是"已有实例在运行"的标记:
  ///   SingletonLock / SingletonCookie / SingletonSocket  —— 符号链接
  ///   lockfile                                            —— 普通文件
  ///
  /// 上次异常退出时它们不会被清理,新进程看到就会:
  ///   1. 认为已有实例,把 URL 转发过去
  ///   2. 自己立刻以 exit code 0 退出
  /// 结果:用户点了书,什么都没发生,进程列表里也看不到 Edge。
  ///
  /// 只在"已经杀掉了占用进程"之后调用,所以删掉是安全的 ——
  /// 此时不可能有活着的实例依赖这些锁。
  void _clearSingletonLocks() {
    const names = [
      'SingletonLock',
      'SingletonCookie',
      'SingletonSocket',
      'lockfile',
    ];
    for (final name in names) {
      final full = '${profileDir.path}${Platform.pathSeparator}$name';
      try {
        // 这些可能是符号链接(Windows 上 Edge 用 junction),
        // 也可能是普通文件,两种都要能删。
        final f = File(full);
        final l = Link(full);
        if (f.existsSync()) {
          f.deleteSync();
        } else if (l.existsSync()) {
          l.deleteSync();
        }
      } catch (_) {
        // 删不掉就算了 —— 可能是权限问题,不该阻塞启动。
      }
    }
  }

  /// 清掉**属于本引擎的**遗留浏览器进程。
  ///
  /// ── 只杀自己的,绝不能碰用户的 ──
  ///
  /// 用真实 profile 时,marker 不能用 `p.basename(profileDir.path)` ——
  /// 那是 `User Data`,而**每一个** Edge 进程的命令行都含这个词
  /// (包括用户自己开的、也包括我们刚启动的那个)。
  ///
  /// 踩过的坑:用它当 marker → 启动后立刻把自己刚起的浏览器杀掉 →
  /// 拿不到端口 → 反复重启 → 界面上一直转圈、显示"不记进度"。
  ///
  /// 正确做法:用**我们独有的调试端口号**当 marker。
  /// 但注意 Edge 会把命令行参数继承给子进程(实测 20 个进程里
  /// 14 个都带 `remote-debugging-port=9333`),所以还要排除
  /// `--type=` 的子进程 —— 只杀主进程,子进程会随之退出。
  Future<void> _killOrphans() async {
    if (!Platform.isWindows) return;
    // 已经连上 = 端口由我们的实例持有,不需要清理。
    if (_ws != null) return;

    try {
      final exeName = p.basename(browserPath);
      final marker = 'remote-debugging-port=$debugPort';
      // -notmatch '--type=' 排除所有子进程,只留浏览器主进程。
      final script =
          'Get-CimInstance Win32_Process -Filter "Name=\'\'$exeName\'\'" | '
          'Where-Object { \$_.CommandLine -like \'*$marker*\' '
          '-and \$_.CommandLine -notmatch \'--type=\' } | '
          'Select-Object -ExpandProperty ProcessId';
      final r = await Process.run('powershell', [
        '-NoProfile',
        '-Command',
        script,
      ]);
      final pids = (r.stdout as String)
          .split(RegExp(r'\s+'))
          .map(int.tryParse)
          .whereType<int>()
          .toList();
      for (final pid in pids) {
        await Process.run('taskkill', ['/F', '/PID', '$pid']);
      }
      if (pids.isNotEmpty) {
        await Future<void>.delayed(const Duration(milliseconds: 600));
      }
    } catch (_) {
      // 清理失败不阻塞启动。
    }
  }

  Future<int?> _waitForPort(File portFile, [bool Function()? stillAlive]) async {
    for (var i = 0; i < 150; i++) {
      if (portFile.existsSync()) {
        final lines = portFile.readAsLinesSync();
        if (lines.isNotEmpty) {
          final port = int.tryParse(lines.first.trim());
          if (port != null) return port;
        }
      }
      if (stillAlive != null && !stillAlive()) return null;
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    return null;
  }

  /// 直接探调试端口是否可用。
  ///
  /// 用真实 profile 时 Chromium 不写 `DevToolsActivePort`,
  /// 只能靠这个判断浏览器是否已经带着调试端口起来了。
  Future<int?> _waitForDebugPort(
    int port, [
    bool Function()? stillAlive,
  ]) async {
    for (var i = 0; i < 150; i++) {
      if (await _isDebugPortAliveAsync(port)) return port;
      if (stillAlive != null && !stillAlive()) return null;
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    return null;
  }

  /// 端口上是否有 CDP 服务在应答。
  Future<bool> _isDebugPortAliveAsync(int port) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 1);
    try {
      final req = await client.getUrl(
        Uri.parse('http://127.0.0.1:$port/json/version'),
      );
      final res = await req.close();
      await res.drain<void>();
      return res.statusCode == 200;
    } catch (_) {
      return false;
    } finally {
      client.close(force: true);
    }
  }

  Future<String> _browserWsUrl(int port) async {
    final client = HttpClient();
    try {
      final req = await client.getUrl(
        Uri.parse('http://127.0.0.1:$port/json/version'),
      );
      final res = await req.close();
      final body = await res.transform(utf8.decoder).join();
      final json = jsonDecode(body) as Map<String, dynamic>;
      return json['webSocketDebuggerUrl'] as String;
    } finally {
      client.close();
    }
  }

  // ---------------------------------------------------------------- 打开书

  @override
  Future<String> launch(Book book, {ProgressSnapshot? resume}) async {
    final url = _resumeUrl(book, resume);
    registerScope(book.id, book.scopePrefix);

    try {
      return await _launchWithCdp(book, url, resume);
    } on CdpLaunchError {
      // 这类错误是"需要用户动手"的(比如浏览器正开着),
      // 不该静默降级 —— 直接把原因抛给界面提示用户。
      // 降级到系统浏览器只会让人困惑:书打开了但进度不记,
      // 而真正的原因(先退出 Edge)反而看不到。
      rethrow;
    } catch (e) {
      // 其他失败:标成降级,由书架显示徽章。
      //
      // ⚠ 不要再调 `_openInDefaultBrowser`。
      // 走到这里时 `--app` 窗口往往已经开出来了(比如 CDP 握手失败),
      // 再开一个系统浏览器窗口 = 用户看到"一个应用窗口 + 一个网页窗口",
      // 而书其实已经在应用窗口里了。纯属干扰。
      //
      // 让书留在已经开出来的窗口里,只标记进度不可用。
      _degradedBooks.add(book.id);
      _lastError = e.toString();
      return url;
    }
  }

  /// 是否有书处于降级模式(界面据此显示提示)。
  bool get hasDegraded => _degradedBooks.isNotEmpty;

  /// 清掉某本书的降级标记(下次成功打开时)。
  void clearDegraded(String bookId) => _degradedBooks.remove(bookId);

  Future<String> _launchWithCdp(
    Book book,
    String url,
    ProgressSnapshot? resume,
  ) async {
    // 是否还有"待认领的空白窗口"。
    // 不能用 `_ws == null` 判断:连上之后 WS 可能仍在,
    // 但那个空白窗口还等着被第一本书用掉。
    final wasRunning = _ws != null;

    await _ensureStarted(url);

    // 能走到这里说明 CDP 正常,清掉之前的降级标记。
    _degradedBooks.remove(book.id);

    final target = _bookToTarget[book.id];

    // 已开着:聚焦并导航,绝不开第二个窗口。
    if (target != null && _targetToSession.containsKey(target)) {
      await _send('Target.activateTarget', params: {'targetId': target});
      await revealTarget(target);
      final session = _targetToSession[target]!;
      await _prepareAndMaybeReload(session, url, resume);
      onBookOpened?.call(book.id);
      return url;
    }

    // 有空白/预热窗口可认领:用它,绝不开第二个。
    // 预热场景(hadSpare && wasRunning)和首次冷启动都走这里。
    if (!wasRunning) {
      final existing = await _pickAppTarget(preferUrl: url);
      if (existing != null) {
        _spareTarget = null;
        await revealTarget(existing);
        final session = await _attach(existing, book.id);
        await _prepareAndMaybeReload(session, url, resume, alreadyAtUrl: false);
        onBookOpened?.call(book.id);
        return url;
      }
    }

    // 后续的书(含预热后的第一本):新开一个 --app 窗口。
    // 预热已经让进程就绪,这一步通常 1~2 秒,而不是冷启动的 5~6 秒。
    // 顺手把预热留下的隐藏空白窗口关掉,免得越攒越多。
    if (_spareTarget != null) {
      final spare = _spareTarget;
      _spareTarget = null;
      if (!_targetToSession.containsKey(spare)) {
        await _send('Target.closeTarget', params: {'targetId': spare});
      }
    }

    final before = (await _listTargets()).map((t) => t['targetId']).toSet();
    final proc = await Process.start(browserPath, [
      '--user-data-dir=${profileDir.path}',
      '--profile-directory=$profileName',
      '--disable-sync',
      '--disable-features=msEdgeSyncConfirmationDialog,EdgeSyncPromo',
      // 必须显式给位置:预热用的是 -4000,-4000(屏幕外),
      // 子窗口会继承那个位置,导致"窗口开出来了但用户看不见"。
      '--window-position=120,80',
      // 起步尺寸给个合理值,随后立刻用 CDP 最大化。
      // 直接用 --start-maximized 对 --app 窗口不生效(实测),
      // 所以必须开完再通过 CDP 设 windowState。
      '--window-size=1200,860',
      '--app=$url',
    ]);
    _drain(proc);

    final targetId = await _waitNewTarget(before);
    final session = await _attach(targetId, book.id);
    await _prepareAndMaybeReload(session, url, resume, alreadyAtUrl: true);
    // 开出来就最大化,和"点书即满屏阅读"的预期一致。
    await revealTarget(targetId);
    onBookOpened?.call(book.id);
    return url;
  }

  /// 注入脚本;如果这一页需要恢复位置,再 reload 一次让注入真正生效。
  ///
  /// `Page.addScriptToEvaluateOnNewDocument` 只对"之后的文档"生效,
  /// 对已经加载完的页面无效。所以有锚点要恢复时,必须 reload。
  /// 没有锚点就不 reload —— 首次打开不该白等一次加载。
  Future<void> _prepareAndMaybeReload(
    String session,
    String url,
    ProgressSnapshot? resume, {
    bool alreadyAtUrl = false,
  }) async {
    await _send('Page.enable', sessionId: session);
    await _send('Runtime.enable', sessionId: session);

    // 注册上报通道。页面里会得到一个 window.__prReport 函数,
    // 调用它就等于直接回调到 Dart(见 _onMessage 的 Runtime.bindingCalled)。
    // 比用 console.log 传字符串干净,也不用解析日志。
    await _send(
      'Runtime.addBinding',
      params: {'name': _bindingName},
      sessionId: session,
    );

    // 两个脚本都要在"新文档开头"就位:
    //   anchorBootstrapScript 负责采集/恢复锚点
    //   positionReportScript  负责在滚动/关窗时主动上报
    for (final script in [anchorBootstrapScript, positionReportScript]) {
      await _send(
        'Page.addScriptToEvaluateOnNewDocument',
        params: {'source': script},
        sessionId: session,
      );
    }

    // 当前这份文档是在注册之前就加载好的,上面的 addScript 只对之后的文档生效。
    // 所以先在当前文档里直接执行一次,让上报立刻可用;
    // 需要恢复位置时再 reload 一次,让脚本赶在文档开头。
    //
    // ⚠ 两个脚本都必须执行,缺一不可:
    //   * anchorBootstrapScript 定义 window.__pr(采集/恢复锚点)
    //   * positionReportScript  定义 window.__prReport(位置上报)
    // 之前只执行了后者,导致 window.__pr 不存在 ——
    // 表现为"上报有了但锚点永远是 null",而且只在
    // "不 reload 直接复用当前文档"的路径上出现,很难复现。
    await _send(
      'Runtime.evaluate',
      params: {
        'expression':
            'try{$anchorBootstrapScript}catch(e){}'
            'try{$positionReportScript}catch(e){}',
      },
      sessionId: session,
    );

    // 关键:判断页面是不是已经在目标 URL 上。
    //   * 已在 → 必须 reload。对同一 URL 调 Page.navigate 会被当作原地操作,
    //          不会重新加载文档,注入的脚本就永远不会生效(踩过这个坑)。
    //   * 不在 → navigate 过去,新文档自然会带上注入。
    final atTarget = alreadyAtUrl || await _isAtUrl(session, url);
    final needsRestore = resume?.anchor != null;

    if (needsRestore) {
      if (atTarget) {
        await _send('Page.reload', params: {}, sessionId: session);
      } else {
        await _send('Page.navigate', params: {'url': url}, sessionId: session);
      }
    } else if (!atTarget) {
      await _send('Page.navigate', params: {'url': url}, sessionId: session);
    }

    await _afterNavigate(session, resume);
  }

  /// 当前页面是否已在目标 URL 上(忽略 fragment)。
  Future<bool> _isAtUrl(String session, String url) async {
    final now = await _eval('location.href', session);
    if (now is! String || now.isEmpty) return false;
    String strip(String u) {
      final i = u.indexOf('#');
      final base = i < 0 ? u : u.substring(0, i);
      return base.endsWith('/') && base.length > 1
          ? base.substring(0, base.length - 1)
          : base;
    }

    return strip(now) == strip(url);
  }

  Future<String> _waitNewTarget(Set<dynamic> before) async {
    for (var i = 0; i < 120; i++) {
      final now = await _listTargets();
      for (final t in now) {
        final id = t['targetId'] as String? ?? '';
        if (id.isEmpty || before.contains(id)) continue;
        if (t['type'] != 'page') continue;
        final u = t['url'] as String? ?? '';
        // 排除真正的浏览器内部页面(设置、扩展、同步确认等),
        // 但 newtab/空白是我们自己的窗口,不能排除。
        final isChromePage =
            u.startsWith('edge://') || u.startsWith('chrome://');
        final isNewTab =
            u.startsWith('edge://newtab') ||
            u.startsWith('chrome://newtab') ||
            u == 'about:blank' ||
            u.isEmpty;
        if (isChromePage && !isNewTab) continue;
        return id;
      }
      await Future<void>.delayed(const Duration(milliseconds: 150));
    }
    throw StateError('窗口没起来');
  }

  /// 调试用:报告当前状态,便于定位"重开不恢复"这类问题。
  Future<Map<String, Object?>> debugState() async {
    final urls = await debugListUrls();
    return {
      'connected': _ws != null,
      'spare': _spareTarget,
      'bookToTarget': Map.of(_bookToTarget),
      'pages': urls,
    };
  }

  /// 诊断信息:给诊断面板用。
  ///
  /// 这类工具最容易出的事故是"进度没记上",而用户完全无法自查。
  /// 把端口、窗口数、最近落库时间暴露出来,出问题时一眼能看出卡在哪。
  Future<DiagnosticsSnapshot> diagnostics() async {
    final pages = await debugListUrls();
    final port = _lastPort;
    return DiagnosticsSnapshot(
      engineRunning: _ws != null,
      browserPath: browserPath,
      profilePath: profileDir.path,
      port: port,
      pageCount: pages.length,
      pageUrls: pages,
      mappedBooks: Map.of(_bookToTarget),
      lastReportAt: _lastReportAt,
      lastReportReason: _lastReportReason,
      reportCount: _reportCount,
      lastError: _lastError,
      degradedBooks: Set.of(_degradedBooks),
    );
  }

  int? _lastPort;
  DateTime? _lastReportAt;
  String? _lastReportReason;
  int _reportCount = 0;
  String? _lastError;

  /// 处于"降级模式"的书:CDP 连不上时退化为普通浏览器打开,
  /// 进度只能记到启动时那个 URL,之后的跳转全部丢失。
  /// 必须让用户看得见,不能静默丢数据。
  final Set<String> _degradedBooks = {};

  /// 某本书是否处于降级模式。
  bool isDegraded(String bookId) => _degradedBooks.contains(bookId);

  /// 查找当前所有页面 target 的 URL(诊断用)。
  Future<List<String>> debugListUrls() async {
    final infos = await _listTargets();
    return infos
        .where((t) => t['type'] == 'page')
        .map((t) => t['url'] as String? ?? '')
        .toList();
  }
  ///
  /// 注意:`--app=about:blank` 实际会变成 `edge://newtab/`,
  /// 所以不能把 `edge://` 一律排除掉 —— 那会把预热窗口漏掉,
  /// 导致新开第二个窗口。
  Future<String?> _pickAppTarget({String? preferUrl}) async {
    final infos = await _listTargets();
    String? blank;
    for (final t in infos) {
      final id = t['targetId'] as String? ?? '';
      if (id.isEmpty || t['type'] != 'page') continue;
      final u = t['url'] as String? ?? '';
      // 真正的浏览器内部页面(设置、扩展等)要排除,但 newtab 是我们的预热窗口。
      final isInternal = (u.startsWith('edge://') || u.startsWith('chrome://')) &&
          !u.startsWith('edge://newtab') &&
          !u.startsWith('chrome://newtab');
      if (isInternal) continue;

      if (preferUrl != null &&
          preferUrl != 'about:blank' &&
          u.isNotEmpty &&
          u.startsWith(UrlNormalizer.normalize(preferUrl))) {
        return id;
      }
      if (u == 'about:blank' ||
          u.isEmpty ||
          u.startsWith('edge://newtab') ||
          u.startsWith('chrome://newtab')) {
        blank ??= id;
      }
    }
    return blank;
  }

  String _resumeUrl(Book book, ProgressSnapshot? resume) {
    if (resume == null) return book.entryUrl;
    final hash = resume.pageHash;
    if (hash == null || hash.isEmpty) return resume.url;
    final fragment = hash.startsWith('#') ? hash.substring(1) : hash;
    return '${resume.url}#$fragment';
  }

  Future<List<Map<String, dynamic>>> _listTargets() async {
    final result = await _send('Target.getTargets');
    final infos = result['targetInfos'] as List<dynamic>? ?? [];
    return infos.cast<Map<String, dynamic>>();
  }

  Future<String> _attach(String targetId, String bookId) async {
    final result = await _send(
      'Target.attachToTarget',
      params: {'targetId': targetId, 'flatten': true},
    );
    final sessionId = result['sessionId'] as String?;
    if (sessionId == null) {
      throw StateError('附到窗口失败:$targetId → ${result['__error'] ?? result}');
    }
    _bookToTarget[bookId] = targetId;
    _targetToSession[targetId] = sessionId;
      _sessionToBook[sessionId] = bookId;
    return sessionId;
  }

  /// 等页面加载完,再按锚点恢复。
  ///
  /// 只等 readyState==complete 是不够的:那时 CSS 可能刚应用、
  /// 字体还没换、懒加载还没发生,scrollHeight 仍然是 0 或很小。
  /// 这时候读位置会得到 docRatio=0,或者恢复时滚不动。
  /// 所以要等到"可滚动高度连续两次读一样"再算稳定。
  Future<void> _afterNavigate(String sessionId, ProgressSnapshot? resume) async {
    for (var i = 0; i < 60; i++) {
      final state = await _eval('document.readyState', sessionId);
      if (state == 'complete') break;
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }

    var last = -1;
    var stable = false;
    for (var i = 0; i < 25; i++) {
      final h = await _eval(
        '(() => { const se = document.scrollingElement || document.documentElement;'
        'return (se ? se.scrollHeight - se.clientHeight : 0) | 0; })()',
        sessionId,
      );
      final height = h is num ? h.toInt() : 0;
      if (height == last && height > 0) {
        stable = true;
        break;
      }
      last = height;
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }

    // 兜底:内容一直没出来(可滚高度恒为 0,常见于 --app 首帧
    // 还没拿到正文就报了 complete)。这种状态下恢复锚点必然失败,
    // 而且是静默失败。reload 一次通常就好了。
    if (!stable) {
      final docH = await _eval(
        '(() => { const se = document.scrollingElement || document.documentElement;'
        'return (se ? se.scrollHeight : 0) | 0; })()',
        sessionId,
      );
      final h = docH is num ? docH.toInt() : 0;
      if (h <= 900) {
        await _send('Page.reload', params: {}, sessionId: sessionId);
        var prev = -1;
        for (var i = 0; i < 40; i++) {
          final hh = await _eval(
            '(() => { const se = document.scrollingElement || document.documentElement;'
            'return (se ? se.scrollHeight - se.clientHeight : 0) | 0; })()',
            sessionId,
          );
          final v = hh is num ? hh.toInt() : 0;
          if (v == prev && v > 0) break;
          prev = v;
          await Future<void>.delayed(const Duration(milliseconds: 250));
        }
      }
    }

    final anchor = resume?.anchor;
    if (anchor != null) {
      // 等注入脚本真的就位(reload 后脚本在文档开头执行,但 DOM 就绪有延迟)。
      var hasPr = false;
      for (var i = 0; i < 40; i++) {
        final t = await _eval('typeof window.__pr', sessionId);
        if (t == 'object') {
          hasPr = true;
          break;
        }
        await Future<void>.delayed(const Duration(milliseconds: 200));
      }
      if (!hasPr) {
        // 脚本没就位:再注入一次并 reload,这是最后一道保险。
        await _send(
          'Page.addScriptToEvaluateOnNewDocument',
          params: {'source': anchorBootstrapScript},
          sessionId: sessionId,
        );
        await _send('Page.reload', params: {}, sessionId: sessionId);
        for (var i = 0; i < 40; i++) {
          final t = await _eval('typeof window.__pr', sessionId);
          if (t == 'object') break;
          await Future<void>.delayed(const Duration(milliseconds: 200));
        }
        // reload 后布局会重来,再等一次稳定。
        var prevH = -1;
        for (var i = 0; i < 30; i++) {
          final hh = await _eval(
            '(() => { const se = document.scrollingElement || document.documentElement;'
            'return (se ? se.scrollHeight - se.clientHeight : 0) | 0; })()',
            sessionId,
          );
          final v = hh is num ? hh.toInt() : 0;
          if (v == prevH && v > 0) break;
          prevH = v;
          await Future<void>.delayed(const Duration(milliseconds: 250));
        }
      }

      // 多试几次:懒加载会把高度改掉,第一次滚动可能落不到位。
      for (var i = 0; i < 3; i++) {
        await _eval(
          '__pr && __pr.restore(${jsonEncode(anchor.toJson())})',
          sessionId,
        );
        await Future<void>.delayed(const Duration(milliseconds: 400));
      }
    }
  }

  // ---------------------------------------------------------------- 采集

  @override
  Future<ProgressSnapshot?> collect(
    String bookId, {
    String deviceId = 'desktop',
  }) async {
    final target = _bookToTarget[bookId];
    final session = target == null ? null : _targetToSession[target];
    if (session == null) return null;

    final alive = await _eval('document.readyState', session);
    if (alive == null) return null;

    final raw = await _eval('JSON.stringify(__pr.collect())', session);
    if (raw is! String || raw.isEmpty) return null;

    final data = jsonDecode(raw) as Map<String, dynamic>;
    final url = Uri.parse(data['url'] as String? ?? '');
    final anchorJson = data['anchor'];
    final hash = (data['hash'] as String? ?? '').trim();

    return ProgressSnapshot(
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
      deviceId: deviceId,
    );
  }

  @override
  Future<List<ProgressSnapshot>> flushAll({String deviceId = 'desktop'}) async {
    final out = <ProgressSnapshot>[];
    for (final bookId in List<String>.from(_bookToTarget.keys)) {
      try {
        final snapshot = await collect(bookId, deviceId: deviceId);
        if (snapshot != null) out.add(snapshot);
      } catch (_) {}
    }
    return out;
  }

  Future<void> restoreAnchor(String bookId, Anchor anchor) async {
    final target = _bookToTarget[bookId];
    final session = target == null ? null : _targetToSession[target];
    if (session == null) return;
    await _eval(
      '__pr && __pr.restore(${jsonEncode(anchor.toJson())})',
      session,
    );
  }

  /// 向浏览器核对一次:哪些 target 还活着。
  Future<void> refreshTargets() async {
    if (_ws == null) return;
    final result = await _send('Target.getTargets');
    final infos = result['targetInfos'] as List<dynamic>?;
    if (infos == null) return;

    final alive = <String>{};
    for (final raw in infos) {
      if (raw is Map<String, dynamic>) {
        final id = raw['targetId'] as String?;
        if (id != null) alive.add(id);
      }
    }

    for (final bookId in List<String>.from(_bookToTarget.keys)) {
      final target = _bookToTarget[bookId]!;
      if (!alive.contains(target)) {
        _bookToTarget.remove(bookId);
        final session = _targetToSession.remove(target);
        if (session != null) _sessionToBook.remove(session);
      }
    }
  }

  /// 采一次最后位置 → 核对 → 把已关闭的书落库。返回刚关闭的书。
  @override
  Future<List<String>> reapClosed({
    Future<void> Function(ProgressSnapshot snapshot)? persist,
  }) async {
    final before = Set<String>.from(_bookToTarget.keys);

    final lastKnown = <String, ProgressSnapshot>{};
    for (final bookId in before) {
      final snapshot = await collect(bookId);
      if (snapshot != null) lastKnown[bookId] = snapshot;
    }

    await refreshTargets();

    final closed = before.difference(_bookToTarget.keys.toSet());
    if (persist != null) {
      for (final bookId in closed) {
        final snapshot = lastKnown[bookId];
        if (snapshot != null) await persist(snapshot);
      }
    }
    return closed.toList();
  }

  // ---------------------------------------------------------------- 协议

  Future<Map<String, dynamic>> _send(
    String method, {
    Map<String, dynamic>? params,
    String? sessionId,
  }) {
    final ws = _ws;
    if (ws == null) {
      return Future<Map<String, dynamic>>.value({'error': 'not-connected'});
    }
    final id = ++_nextId;
    final completer = Completer<Map<String, dynamic>>();
    _pending[id] = completer;
    final payload = <String, dynamic>{
      'id': id,
      'method': method,
      'params': params ?? <String, dynamic>{},
    };
    if (sessionId != null) payload['sessionId'] = sessionId;
    ws.add(jsonEncode(payload));
    return completer.future.timeout(
      const Duration(seconds: 20),
      onTimeout: () => {'error': 'timeout:$method'},
    );
  }

  Future<dynamic> _eval(String expression, String sessionId) async {
    final result = await _send(
      'Runtime.evaluate',
      params: {'expression': expression, 'returnByValue': true},
      sessionId: sessionId,
    );
    final inner = result['result'];
    if (inner is Map) return inner['value'];
    return null;
  }

  void _onMessage(dynamic data) {
    final map = jsonDecode(data as String) as Map<String, dynamic>;
    final id = map['id'];
    if (id is int) {
      final completer = _pending.remove(id);
      if (completer == null) return;
      final error = map['error'];
      if (error != null) {
        completer.complete({'__error': error});
        return;
      }
      completer.complete(map['result'] as Map<String, dynamic>? ?? {});
      return;
    }

    final method = map['method'] as String?;
    final sessionId = map['sessionId'] as String?;

    if (method == 'Runtime.bindingCalled') {
      // 页面主动上报位置。只认本引擎登记过的 session,避免多窗口串数据。
      final params = map['params'] as Map<String, dynamic>? ?? {};
      if (params['name'] != _bindingName) return;
      final bookId = sessionId == null ? null : _sessionToBook[sessionId];
      if (bookId == null) {
        if (kDebugMode) {
          // ignore: avoid_print
          print('[PR] 上报 session=$sessionId 未映射到书,丢弃');
        }
        return;
      }
      final payload = params['payload'] as String?;
      if (payload == null || payload.isEmpty) return;
      try {
        final data = jsonDecode(payload) as Map<String, dynamic>;
        final href = data['href'] as String? ?? '';
        if (href.isEmpty || href == 'about:blank') return;
        final anchorJson = data['anchor'];
        if (kDebugMode) {
          // ignore: avoid_print
          print(
            '[PR] ${data['why']} book=$bookId ratio=${data['ratio']} '
            'y=${data['y']} anchor=${anchorJson != null}',
          );
        }
        _lastReportAt = DateTime.now();
        _lastReportReason = data['why'] as String? ?? 'scroll';
        _reportCount++;
        _reports.add(
          PositionReport(
            bookId: bookId,
            url: href,
            title: (data['title'] as String? ?? '').trim(),
            anchor: anchorJson is Map<String, dynamic>
                ? Anchor.fromJson(anchorJson)
                : null,
            docRatio: (data['ratio'] as num?)?.toDouble(),
            reason: data['why'] as String? ?? 'scroll',
            at: DateTime.now(),
          ),
        );
      } catch (_) {
        // 上报格式异常就丢掉,不能因为一条脏数据影响阅读。
      }
      return;
    }

    if (method == 'Page.frameNavigated' && sessionId != null) {
      final params = map['params'] as Map<String, dynamic>? ?? {};
      final frame = params['frame'] as Map<String, dynamic>? ?? {};
      if (frame['parentId'] != null) return;
      final bookId = _sessionToBook[sessionId];
      if (bookId == null) return;
      final url = frame['url'] as String? ?? '';
      if (url == 'about:blank' || url.isEmpty) return;
      _navs.add(
        NavigationEvent(
          bookId: bookId,
          url: url,
          title: frame['name'] as String? ?? '',
          at: DateTime.now(),
        ),
      );
      return;
    }

    // 页面标题变化也算一次位置更新:
    // SPA 里切章节常常不触发 frameNavigated,只改 title。
    if (method == 'Page.frameStoppedLoading' && sessionId != null) {
      final bookId = _sessionToBook[sessionId];
      if (bookId == null) return;
      _navs.add(
        NavigationEvent(
          bookId: bookId,
          url: '',
          title: '',
          at: DateTime.now(),
        ),
      );
      return;
    }

    if (method == 'Target.detachedFromTarget') {
      final params = map['params'] as Map<String, dynamic>? ?? {};
      final detached = params['sessionId'] as String?;
      if (detached == null) return;
      final bookId = _sessionToBook.remove(detached);
      if (bookId != null) {
        final target = _bookToTarget.remove(bookId);
        if (target != null) _targetToSession.remove(target);
      }
    }
  }

  @override
  Future<void> installBootstrap(String script) async {
    for (final session in _targetToSession.values) {
      await _send(
        'Page.addScriptToEvaluateOnNewDocument',
        params: {'source': script},
        sessionId: session,
      );
    }
  }

  @override
  Future<void> shutdown() async {
    await _ws?.close();
    _ws = null;
    _process?.kill();
    _process = null;
  }
}

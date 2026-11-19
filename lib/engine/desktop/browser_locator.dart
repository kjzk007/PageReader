import 'dart:io';

/// 找本机可用的 Chromium 内核浏览器。
///
/// 检测顺序(从最可靠到最兜底):
///
///   1. **注册表 App Paths** —— Windows 官方登记位置。
///      Edge/Chrome 的安装程序都会写 HKLM/HKCU
///      的 `...\App Paths\<exe>` 键,值就是 exe 的完整路径。
///      这是唯一"安装一定会有"的权威来源,不会因为装在哪而失效。
///
///   2. **环境变量推导的常见位置** —— 覆盖:
///      * Program Files / Program Files (x86)(标准安装)
///      * LOCALAPPDATA(用户级安装,企业部署常见)
///      用环境变量而不是写死盘符,装到 D 盘也能找到。
///
///   3. **`where` 命令** —— PATH 里能找到的情况(少数环境会配)。
///
/// 为什么不只靠硬编码路径:实测只在标准安装下命中。
/// 用户级安装(%LOCALAPPDATA%\Google\Chrome)和 32 位装在 64 位系统
/// 这两种真实场景都会漏掉,用户看到的是"找不到浏览器"。
class BrowserLocator {
  const BrowserLocator._();

  /// 支持的浏览器,按优先级排列。
  /// Edge 优先:Windows 自带,用户卸载它的概率远低于没装 Chrome。
  static const List<String> _executables = ['msedge.exe', 'chrome.exe'];

  /// 缓存结果,避免每次调用都跑一轮检测(注册表查询有开销)。
  static String? _cached;
  static bool _probed = false;

  /// 返回浏览器可执行文件路径,找不到返回 null。
  ///
  /// `preferred` 是用户手动指定的路径,存在就直接用。
  static String? find({String? preferred, bool refresh = false}) {
    if (preferred != null && File(preferred).existsSync()) return preferred;

    if (_probed && !refresh) return _cached;
    _probed = true;

    for (final exe in _executables) {
      final path = _fromRegistry(exe) ?? _fromLikelyPaths(exe) ?? _fromWhere(exe);
      if (path != null) {
        _cached = path;
        return path;
      }
    }
    _cached = null;
    return null;
  }

  /// 同步版本供启动时快速判断(走缓存)。
  static String? findCached() => _probed ? _cached : find();

  /// 1. 注册表:Windows 官方登记的安装路径。
  static String? _fromRegistry(String exe) {
    const roots = [
      'HKLM\\SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\App Paths',
      'HKLM\\SOFTWARE\\WOW6432Node\\Microsoft\\Windows\\CurrentVersion\\App Paths',
      'HKCU\\SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\App Paths',
    ];
    for (final root in roots) {
      try {
        final r = Process.runSync('reg', ['query', '$root\\$exe', '/ve']);
        if (r.exitCode != 0) continue;
        final out = r.stdout as String;
        // 输出形如:  (Default)    REG_SZ    C:\path\to\msedge.exe
        final m = RegExp(r'REG_SZ\s+(.+)').firstMatch(out);
        if (m == null) continue;
        var path = m.group(1)!.trim();
        // 注册表里偶尔带引号
        path = path.replaceAll('"', '');
        if (File(path).existsSync()) return path;
      } catch (_) {
        // 没有 reg 命令或权限不足,继续下一种方式。
      }
    }
    return null;
  }

  /// 2. 用环境变量推导常见安装位置。
  ///
  /// 关键是用 `%ProgramFiles%` / `%LOCALAPPDATA%` 而不是写死 `C:\`,
  /// 这样系统盘不在 C 盘、或用户级安装都能找到。
  static String? _fromLikelyPaths(String exe) {
    final env = Platform.environment;
    final roots = <String>[
      ?env['ProgramFiles'],
      ?env['ProgramFiles(x86)'],
      ?env['ProgramW6432'],
      // 用户级安装:Chrome 和 Edge 都支持"仅为当前用户安装",
      // 装在这里的浏览器在标准路径下完全找不到。
      ?env['LOCALAPPDATA'],
      ?(env['LOCALAPPDATA'] == null
          ? null
          : '${env['LOCALAPPDATA']}\\Programs'),
    ];

    // 每种浏览器的目录结构
    final subdirs = exe.startsWith('msedge')
        ? ['Microsoft\\Edge\\Application']
        : ['Google\\Chrome\\Application'];

    for (final root in roots) {
      for (final sub in subdirs) {
        final path = '$root\\$sub\\$exe';
        if (File(path).existsSync()) return path;
      }
    }
    return null;
  }

  /// 3. PATH 里找(少数环境会配)。
  static String? _fromWhere(String exe) {
    try {
      final r = Process.runSync('where', [exe]);
      if (r.exitCode != 0) return null;
      final first = (r.stdout as String)
          .split(RegExp(r'\r?\n'))
          .firstWhere((l) => l.trim().isNotEmpty, orElse: () => '')
          .trim();
      if (first.isNotEmpty && File(first).existsSync()) return first;
    } catch (_) {}
    return null;
  }

  /// 给界面/诊断用的显示名。
  static String displayName(String path) {
    final lower = path.toLowerCase();
    if (lower.contains('msedge')) return 'Microsoft Edge';
    if (lower.contains('chrome')) return 'Google Chrome';
    return path.split(Platform.pathSeparator).last;
  }

  /// 同步版本的检测,给"必须立刻知道"的地方用(如诊断面板)。
  ///
  /// 与 find() 的区别:不缓存、每次都重新查。
  /// 用户可能在程序运行期间装了浏览器,重新查能立刻看到。
  static String? detectNow() {
    for (final exe in _executables) {
      final path = _fromRegistry(exe) ?? _fromLikelyPaths(exe) ?? _fromWhere(exe);
      if (path != null) return path;
    }
    return null;
  }

  /// 清掉缓存(用户在设置里改了浏览器路径后调用)。
  static void invalidate() {
    _probed = false;
    _cached = null;
  }
}

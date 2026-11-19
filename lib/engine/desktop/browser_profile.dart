import 'dart:io';

import 'package:path/path.dart' as p;

/// 定位用户日常使用的浏览器 profile 目录。
///
/// ── 为什么必须用用户的真实 profile ──
///
/// 我们试过所有替代方案,全都不行:
///
///   * 空 profile + `--load-extension` 手动挂插件 ——
///     Chromium 113+ 起这个开关只允许加载内置组件,用户装的插件
///     一律被忽略(实测 Edge 157 / Chrome 都是如此)。
///   * 复制 profile 到别处 ——
///     Edge 启动时会删掉"未在 Secure Preferences 里注册"的插件,
///     19 个插件复制过去后只剩 3 个。
///
/// 结论:只有用真实 profile,插件和登录态才完整。
class BrowserProfile {
  const BrowserProfile._();

  /// 常见 Chromium 浏览器的 profile 根目录(相对 `%LOCALAPPDATA%`)。
  static const _candidates = [
    r'Microsoft\Edge\User Data',
    r'Google\Chrome\User Data',
    r'BraveSoftware\Brave-Browser\User Data',
    r'Chromium\User Data',
  ];

  /// 找到浏览器对应的 profile 根目录。
  ///
  /// [browserPath] 是浏览器的 exe 路径,用来判断是哪一家。
  /// 找不到时返回 null,调用方应退回独立 profile(并提示插件不可用)。
  static Directory? resolve(String browserPath) {
    if (!Platform.isWindows) return null;
    final local = Platform.environment['LOCALAPPDATA'];
    if (local == null || local.isEmpty) return null;

    final name = p.basename(browserPath).toLowerCase();
    final isEdge = name.contains('msedge');
    final isChrome = name.contains('chrome') && !name.contains('chromium');
    final isBrave = name.contains('brave');
    final isChromium = name.contains('chromium');

    // 按浏览器匹配对应目录,避免拿错 —— 用错 profile 会导致
    // 插件列表和登录态都对不上。
    final order = <String>[];
    if (isEdge) {
      order.add(_candidates[0]);
    } else if (isBrave) {
      order.add(_candidates[2]);
    } else if (isChromium) {
      order.add(_candidates[3]);
    } else if (isChrome) {
      order.add(_candidates[1]);
    } else {
      // 认不出来(比如用户配了自定义浏览器):按优先级全试。
      order.addAll(_candidates);
    }

    for (final rel in order) {
      final dir = Directory(p.join(local, rel));
      if (!dir.existsSync()) continue;
      // 必须至少有一个能用的 profile 子目录。
      if (defaultProfileName(dir) == null) continue;
      return dir;
    }
    return null;
  }

  /// 找出这个 profile 根下**实际在用**的 profile 名字。
  ///
  /// ── 为什么不能写死 `Default` ──
  ///
  /// 用户可能用多账号:主账号在 `Default`,工作区在 `Profile 1`,
  /// 甚至只用 `Profile 2` 而从没碰过 `Default`。
  /// 写死 Default 会让这些用户"找不到 profile"。
  ///
  /// 判定方式:
  ///   1. `Local State` 里的 `profile.last_used` 是最权威的 ——
  ///      Chromium 每次切换 profile 都会更新它。
  ///   2. 退化到目录扫描:优先 Default,其次 Profile N(取最大)。
  static String? defaultProfileName(Directory profileRoot) {
    // 1. 读 Local State 的 last_used
    try {
      final ls = File(p.join(profileRoot.path, 'Local State'));
      if (ls.existsSync()) {
        final raw = ls.readAsStringSync();
        // 不引入 json 依赖的轻量解析:直接找 "last_used":"xxx"
        final m = RegExp(
          r'"last_used"\s*:\s*"([^"]+)"',
        ).firstMatch(raw);
        if (m != null) {
          final name = m.group(1)!;
          if (Directory(p.join(profileRoot.path, name)).existsSync()) {
            return name;
          }
        }
      }
    } catch (_) {
      // 读不到就退化到扫描。
    }

    // 2. 目录扫描
    final names = <String>[];
    try {
      for (final e in profileRoot.listSync()) {
        if (e is! Directory) continue;
        final n = p.basename(e.path);
        if (n == 'Default' || RegExp(r'^Profile \d+$').hasMatch(n)) {
          // 必须有 Preferences 才算真 profile(空目录不算)。
          if (File(p.join(e.path, 'Preferences')).existsSync()) {
            names.add(n);
          }
        }
      }
    } catch (_) {
      return null;
    }
    if (names.isEmpty) return null;
    if (names.contains('Default')) return 'Default';
    // 取编号最大的那个
    names.sort((a, b) {
      final na = int.tryParse(a.replaceAll(RegExp(r'\D'), '')) ?? 0;
      final nb = int.tryParse(b.replaceAll(RegExp(r'\D'), '')) ?? 0;
      return nb.compareTo(na);
    });
    return names.first;
  }

  /// 这个 profile 里装了哪些插件(只看目录,不解析 manifest)。
  ///
  /// 用途:界面上告诉用户"将使用你已装的 N 个插件",
  /// 而不是让用户猜。
  static int countExtensions(
    Directory profileRoot, {
    String profileName = 'Default',
  }) {
    final extDir = Directory(
      p.join(profileRoot.path, profileName, 'Extensions'),
    );
    if (!extDir.existsSync()) return 0;
    try {
      return extDir.listSync().whereType<Directory>().length;
    } catch (_) {
      return 0;
    }
  }
}

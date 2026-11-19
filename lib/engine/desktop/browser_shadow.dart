import 'dart:io';

import 'package:path/path.dart' as p;

/// 用户浏览器 profile 的镜像副本。
///
/// ── 为什么必须复制,不能直接用真实目录 ──
///
/// Edge 有一条硬限制(日志原文):
///
///   DevTools remote debugging requires a non-default data directory.
///   Specify this using --user-data-dir.
///
/// 也就是说:对**默认数据目录**(`%LOCALAPPDATA%\Microsoft\Edge\User Data`)
/// 启动时,Edge 会拒绝开启调试端口 —— 参数传了也不生效。
/// 没有端口 = 完全无法记录进度。
///
/// 试过用 junction 指向真实目录(让路径看起来"非默认"):
/// 端口能开,但插件全部不加载(Edge 把它当成全新目录)。
///
/// 所以只有一条路:复制到真·非默认目录。
///
/// ── 复制后哪些能用 ──
///
/// 实测(2026-11-19):
///   * 端口:✓ 第 1 秒就绪
///   * 插件:✓ 已注册的那几个会加载(含豆包)
///   * Cookie:✓ 能解密(DPAPI 绑 Windows 用户,不绑路径)
///   * 登录态:✓ 复制时已有的登录态都能用
///
/// ── 注意 ──
///
/// Edge 启动时会删掉"未在 Secure Preferences 里注册"的插件目录。
/// 所以影子里插件数量会比源少 —— 这是 Edge 的行为,不是复制失败。
class BrowserShadow {
  const BrowserShadow._();

  /// 缓存目录:几个 GB 的垃圾,复制没有意义。
  ///
  /// 注意 `Extensions` 绝对不在排除列表 —— 那是插件本体。
  static const _excludeCaches = [
    r'\Default\Service Worker',
    r'\Default\Cache',
    r'\Default\Code Cache',
    r'\Default\GPUCache',
    r'\Default\DawnCache',
    r'\Default\DawnWebGPUCache',
    r'\Default\GrShaderCache',
    r'\Default\ShaderCache',
    r'\Default\Media Cache',
    r'\GrShaderCache',
    r'\ShaderCache',
    r'\Crashpad',
    r'\Default\Cache2',
  ];

  /// 镜像是否可用。
  ///
  /// 判据要有 `Preferences` + `Secure Preferences` ——
  /// 后者决定哪些插件会被 Edge 承认,缺了它插件一个都不会加载。
  static bool isReady(Directory shadow) {
    final base = p.join(shadow.path, 'Default');
    return File(p.join(base, 'Preferences')).existsSync() &&
        File(p.join(base, 'Secure Preferences')).existsSync();
  }

  /// 从 [source] 复制到 [shadow]。
  ///
  /// **调用前必须确保源浏览器已完全退出** ——
  /// 否则 Cookie 还在内存里没落盘,复制到的是旧数据。
  static Future<bool> sync({
    required Directory source,
    required Directory shadow,
  }) async {
    if (!Platform.isWindows) return false;
    try {
      shadow.createSync(recursive: true);
      final ok = await _robocopy(
        source.path,
        shadow.path,
        excludeDirs: _excludeCaches,
      );
      return ok && isReady(shadow);
    } catch (_) {
      return false;
    }
  }

  /// 给 WebView2 建"工作区"：只复制登录态，不复制插件。
  ///
  /// ── 为什么单独一个方法 ──
  ///
  /// WebView2 的插件不走 profile 复制这条路 —— 它用
  /// `AddBrowserExtension` 显式加载用户勾选的插件目录。
  /// 所以这里只需要把 Cookie 和本地存储搬过来，让网页打开时是登录态。
  ///
  /// 不复制插件目录的好处:用户可以在设置里随时增减插件，
  /// 而且不会因为 Edge 的插件注册校验导致插件被删。
  static Future<bool> bootstrapUserData({
    required Directory source,
    required Directory target,
  }) async {
    if (!Platform.isWindows) return false;
    try {
      target.createSync(recursive: true);

      // WebView2 的 user data 结构是 <dir>/EBWebView/Default/...，
      // 但 Cookie 等数据在第一次运行时才生成，所以这里直接写到
      // <target>/Default 下的对应位置会被忽略。改为复制整个
      // 「登录态相关」目录到 target，由 WebView2 首次运行时合并。
      //
      // 实测:WebView2 会忽略手工放进去的 Network/Cookies，
      // 所以真正可靠的途径是让它自己建目录，然后用 CookieManager
      // 逐条写入 —— 那部分在 Dart 侧用 CDP/CookieManager 做。
      //
      // 这里只搬运「非加密」的部分:Local Storage / IndexedDB
      // （插件的配置和网站数据），Cookie 走另一条路。
      const loginDirs = [
        r'Default\Local Storage',
        r'Default\IndexedDB',
        r'Default\Session Storage',
      ];
      for (final rel in loginDirs) {
        final src = p.join(source.path, rel);
        if (!Directory(src).existsSync()) continue;
        await _robocopy(src, p.join(target.path, rel));
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  /// 用 robocopy 复制。返回是否成功(退出码 < 8)。
  static Future<bool> _robocopy(
    String src,
    String dst, {
    List<String> excludeDirs = const [],
  }) async {
    try {
      final args = <String>[
        src,
        dst,
        '/E',
        '/NFL',
        '/NDL',
        '/NJH',
        '/NJS',
        '/NC',
        '/NS',
        '/MT:16',
        '/R:1',
        '/W:1',
        if (excludeDirs.isNotEmpty) ...['/XD', ...excludeDirs],
      ];
      final r = await Process.run('robocopy', args);
      return r.exitCode < 8;
    } catch (_) {
      return false;
    }
  }
}

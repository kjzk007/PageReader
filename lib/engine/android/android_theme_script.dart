
import 'package:flutter/services.dart';

import '../../core/domain/theme_preset.dart';

/// 把主题预设拼成一段可注入的脚本（Android 端用）。
///
/// ── 和桌面端的差别 ──
///
/// 桌面端（WebView2）用 `AddScriptToExecuteOnDocumentCreated` 注入，
/// 时机是 document-start，天然不闪。
///
/// Android 分两种情况：
///   * 设备支持 `DOCUMENT_START_SCRIPT` → 同样 document-start，不闪
///   * 不支持 → 只能在 `onPageFinished` 之后 `runJavaScript`，会闪一下
///
/// 两种情况下**注入的内容是同一份**：预设对象 + 引擎全文。
/// 所以这个类只负责拼字符串，不关心时机。
///
/// ── 为什么要有两个引擎文件 ──
///
/// `engine.js` 用了 `?.`、`??`、`replaceAll`，分别需要 Chrome 80/80/85。
/// 实测设备里 MI PAD 4 PLUS 是 WebView 68。
/// 语法错误会导致整段脚本解析失败 —— 表现是「什么都没发生」，
/// 连报错都只在控制台里，极难排查。
///
/// 所以构建时会额外产出 `engine.legacy.js`（把这些语法降级掉），
/// 运行时按 WebView 版本挑一个。
class AndroidThemeScript {
  const AndroidThemeScript._();

  /// 低于这个主版本用降级引擎。
  ///
  /// 引擎里 `?.` 和 `??` 需要 Chrome 80，`replaceAll` 需要 Chrome 85。
  /// 取 85 作分界：低于它一律用降级版，多降一次没有副作用。
  static const _legacyThreshold = 85;

  static String? _engineNew;
  static String? _engineLegacy;

  /// 加载引擎脚本（只读一次）。
  static Future<void> warmUp() async {
    if (_engineNew == null) {
      try {
        _engineNew = await rootBundle.loadString('assets/dark/engine.js');
      } catch (_) {}
    }
    if (_engineLegacy == null) {
      try {
        _engineLegacy = await rootBundle.loadString(
          'assets/dark/engine.legacy.js',
        );
      } catch (_) {}
    }
  }

  /// 按 WebView 主版本号挑引擎。
  ///
  /// [webViewVersion] 形如 `68.0.3440.91`。取不到就保守用降级版 ——
  /// 降级版在所有版本上都能跑，只是代码长一点点。
  static Future<String> engineFor(String webViewVersion) async {
    await warmUp();
    final major = int.tryParse(webViewVersion.split('.').first) ?? 0;
    if (major >= _legacyThreshold && _engineNew != null) {
      return _engineNew!;
    }
    return _engineLegacy ?? _engineNew ?? '';
  }

  /// 拼出完整注入脚本。
  ///
  /// 顺序很重要：
  ///   1. `window.__PR_DARK_PRESET` —— 引擎启动时会读它，必须先有
  ///   2. matchMedia 覆写 —— 让还没被算色的页面至少先切到深色底
  ///   3. 引擎全文 —— 逐元素算色
  static Future<String> build({
    required ThemePreset? preset,
    required bool dark,
    required String webViewVersion,
  }) async {
    final engine = await engineFor(webViewVersion);
    if (preset == null) {
      // 没选预设：只做 color-scheme 覆写，让站点自己切深色。
      // 这是「默认」档的语义 —— 不注入任何样式。
      return _matchMediaOnly(dark);
    }
    final presetJson = _toJson(preset);
    final mode = preset.isDarkScheme ? 1 : 0;
    return '''
window.__PR_DARK_PRESET = $presetJson;
(function(){
  try {
    if (window.__prMediaPatched) return;
    window.__prMediaPatched = true;
    var orig = window.matchMedia.bind(window);
    window.matchMedia = function (q) {
      var mql = orig(q);
      if (!q || q.indexOf('prefers-color-scheme') < 0) return mql;
      var askDark = q.indexOf('dark') >= 0;
      var askLight = q.indexOf('light') >= 0;
      if (!askDark && !askLight) return mql;
      try {
        Object.defineProperty(mql, 'matches', {
          get: function () { return askDark ? ${mode == 1 ? 'true' : 'false'} : ${mode == 1 ? 'false' : 'true'}; }
        });
      } catch (e) {}
      return mql;
    };
  } catch (e) {}
})();
try {
$engine
} catch (e) {
  // 引擎整体抛错时兜住，避免后面的页面脚本全部中断。
  // 具体的失败原因由引擎内部的 __prDarkErrors 记录，
  // Dart 侧的自检会读它并提示用户。
  window.__prDarkError = String(e);
}
''';
  }

  /// 「默认」档：只覆写 matchMedia。
  static String _matchMediaOnly(bool dark) {
    final v = dark ? 'true' : 'false';
    final inv = dark ? 'false' : 'true';
    return '''
(function(){
  if (window.__prMediaPatched) return;
  window.__prMediaPatched = true;
  try {
    var orig = window.matchMedia.bind(window);
    window.matchMedia = function (q) {
      var mql = orig(q);
      if (!q || q.indexOf('prefers-color-scheme') < 0) return mql;
      var askDark = q.indexOf('dark') >= 0;
      var askLight = q.indexOf('light') >= 0;
      if (!askDark && !askLight) return mql;
      try {
        Object.defineProperty(mql, 'matches', {
          get: function () { return askDark ? $v : $inv; }
        });
      } catch (e) {}
      return mql;
    };
  } catch (e) {}
})();
''';
  }

  /// 预设转成引擎认识的 JSON。
  ///
  /// 字段名和桌面端 `ThemePreset.toEngineJson()` 保持一致 ——
  /// 两端跑的是同一份引擎，结构必须一样。
  static String _toJson(ThemePreset p) {
    final m = p.toEngineJson();
    final buf = StringBuffer('{');
    var first = true;
    for (final e in m.entries) {
      if (!first) buf.write(',');
      first = false;
      buf.write('"${e.key}":');
      final v = e.value;
      if (v is String) {
        buf.write('"${v.replaceAll('"', r'\"')}"');
      } else if (v is bool) {
        buf.write(v ? 'true' : 'false');
      } else if (v is num) {
        buf.write(v);
      } else {
        buf.write('null');
      }
    }
    buf.write('}');
    return buf.toString();
  }
}

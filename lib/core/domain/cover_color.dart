/// 封面底色的三条策略。
///
/// 从 main.dart 抽出来,理由不只是"文件太长":
/// 这三条规则是全项目最容易改坏的地方 ——
/// 每次调整都会让某些站点的封面变难看,而肉眼看截图无法回归。
/// 抽成纯函数后可以写单测,改坏了立刻会被发现。
class CoverColor {
  const CoverColor._();

  /// 自带不透明底框的颜色:严格原样使用。
  ///
  /// 曾被"纯白在深色界面上太刺眼"的想法带偏,把 >250 亮度压成 #F2F2F2,
  /// 结果图标自身的纯白底和卡片差了一档,边框反而更明显 ——
  /// 正好制造了本来要消除的东西。融合的前提是完全同色。
  static int shelfSafe(int argb) => 0xFF000000 | (argb & 0xFFFFFF);

  /// 透明图标的主色 → 卡片底色。
  ///
  /// 根据图标本身的明暗决定往哪个方向调:
  ///   * 深色图标(Vue 的黑 V、Rust 的黑书)→ 提亮,否则黑压黑看不见
  ///   * 中亮图标(Python 的蓝、TS 的蓝)→ 压暗,否则蓝压蓝看不清
  ///
  /// 目标:卡片底色与图标主色的明度差足够大。
  static int forTransparentIcon(int argb) {
    final r = (argb >> 16) & 0xFF;
    final g = (argb >> 8) & 0xFF;
    final b = argb & 0xFF;
    final luma = luminance(argb);

    // 已经是舒适的深色:不动。
    //
    // 这个分支必须先判断。否则 #202020 这种"本来就够暗"的颜色
    // 会被当成深色图标去提亮,反而变成一片灰。
    // 判据是"暗但不至于看不见"——亮度在 40..90 之间说明它作为底色
    // 完全够用,不需要调整。
    if (luma >= 40 && luma < 90) {
      return 0xFF000000 | (r << 16) | (g << 8) | b;
    }

    // 极深的图标色(接近黑):提亮底色,否则黑压黑看不见。
    if (luma < 40) {
      const target = 168.0;
      final t = (target - luma) / (255 - luma);
      final nr = (r + (255 - r) * t * 0.82).round().clamp(0, 255);
      final ng = (g + (255 - g) * t * 0.82).round().clamp(0, 255);
      final nb = (b + (255 - b) * t * 0.82).round().clamp(0, 255);
      return 0xFF000000 | (nr << 16) | (ng << 8) | nb;
    }

    // 中等/明亮图标:压暗到深色书架的舒适区间。
    const target = 58.0;
    if (luma <= target) return 0xFF000000 | (r << 16) | (g << 8) | b;
    final t = target / luma;
    return 0xFF000000 |
        ((r * t).round().clamp(0, 255) << 16) |
        ((g * t).round().clamp(0, 255) << 8) |
        (b * t).round().clamp(0, 255);
  }

  /// 完全采不到颜色时按域名哈希到一个稳定的深色。
  ///
  /// 不用灰色的理由:灰色看起来像"没设置",而不是"一个配色"。
  /// 这组颜色明度低、饱和度适中,在深色书架上不刺眼,
  /// 而且同一本书每次都是同一个颜色,不会跳。
  static int fallback(String url) {
    final host = Uri.tryParse(url)?.host ?? url;
    const palette = <int>[
      0xFF1F3A5F, // 深蓝
      0xFF17404E, // 深青
      0xFF1E3A2B, // 墨绿
      0xFF2E2440, // 深紫
      0xFF3D2230, // 深玫瑰
      0xFF3A2E1B, // 深琥珀
      0xFF252B52, // 深靛
      0xFF1B3838, // 深青绿
    ];
    var hash = 0;
    for (final code in host.codeUnits) {
      hash = (hash * 31 + code) & 0x7FFFFFFF;
    }
    return palette[hash % palette.length];
  }

  /// 判断一个颜色是不是早期版本留下的"中性灰兜底"。
  ///
  /// 必须同时满足三条,否则会误伤真实配色:
  ///   * 通道差小(无彩色)
  ///   * 亮度在中间区间 —— 极暗(#15141a)和极亮(#ffffff)
  ///     都是站点的有意设计,不能当成兜底去重算
  ///
  /// 踩过的坑:只用通道差判断,MDN 的深底通道差只有 6,
  /// 结果每次启动都重采样一遍,白费网络。
  static bool looksLikeOldFallbackGray(int argb) {
    final r = (argb >> 16) & 0xFF;
    final g = (argb >> 8) & 0xFF;
    final b = argb & 0xFF;
    final maxC = [r, g, b].reduce((a, b) => a > b ? a : b);
    final minC = [r, g, b].reduce((a, b) => a < b ? a : b);
    final isGray = (maxC - minC) < 20;
    final isMidTone = maxC > 60 && maxC < 240;
    return isGray && isMidTone;
  }

  /// 感知亮度 0-255。
  static double luminance(int argb) {
    final r = (argb >> 16) & 0xFF;
    final g = (argb >> 8) & 0xFF;
    final b = argb & 0xFF;
    return 0.299 * r + 0.587 * g + 0.114 * b;
  }
}

/// 阅读主题预设。
///
/// 一套页面配色方案：背景色、文字色、亮度、对比度。
/// 用户在设置里建多个预设，然后给某本书指定用哪个；
/// 不指定就是「默认」—— 一个字都不注入，网页原样。
///
/// ── 不限于深色 ──
///
/// 名字里没有 "dark"：用户完全可以把背景设成米黄、浅灰甚至任何颜色，
/// 引擎按背景色的明暗自动决定「把页面往深算」还是「往浅算」，
/// 用户不需要理解这个机制。
class ThemePreset {
  const ThemePreset({
    required this.id,
    required this.name,
    this.background = '#14161a',
    this.text = '#d8dade',
    this.brightness = 100,
    this.contrast = 100,
    this.forceFont,
    this.builtin = false,
  });

  /// 稳定标识。内置预设用固定 id，用户新建的用时间戳。
  final String id;
  final String name;

  /// 页面底色（#RRGGBB）。明暗决定引擎往哪个方向算色。
  final String background;

  /// 正文颜色（#RRGGBB）。
  final String text;

  /// 0–160，100 表示不调整。
  final double brightness;

  /// 0–160。
  final double contrast;

  /// 强制字体名；null 表示不动站点字体。
  final String? forceFont;

  /// 内置预设不可删除。
  final bool builtin;

  /// 内置的唯一预设。
  ///
  /// 只做一个深色，够用就好。需要米黄、护眼、亮色的用户自己新建 ——
  /// 预置一堆没人用的方案只是噪音。
  static const builtinDark = ThemePreset(
    id: 'preset-night',
    name: '深色阅读',
    background: '#14161a',
    text: '#d8dade',
    builtin: true,
  );

  /// 背景色偏暗 → 把页面往深算；偏亮 → 往浅算。
  ///
  /// 用相对亮度判断，比阈值分档更稳（#808080 这种中灰也能正确归类）。
  bool get isDarkScheme {
    final h = background.replaceAll('#', '');
    if (h.length != 6) return true;
    final r = int.tryParse(h.substring(0, 2), radix: 16) ?? 0;
    final g = int.tryParse(h.substring(2, 4), radix: 16) ?? 0;
    final b = int.tryParse(h.substring(4, 6), radix: 16) ?? 0;
    final lum = (0.2126 * r + 0.7152 * g + 0.0722 * b) / 255;
    return lum < 0.5;
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'background': background,
    'text': text,
    'brightness': brightness,
    'contrast': contrast,
    'forceFont': forceFont,
    'builtin': builtin,
  };

  /// 供注入脚本消费的结构。
  ///
  /// `mode` 与算法里的约定一致：1 = 深色方案，0 = 浅色方案。
  Map<String, dynamic> toEngineJson() => {
    'enabled': true,
    'mode': isDarkScheme ? 1 : 0,
    'background': _hexToRgb(background),
    'text': _hexToRgb(text),
    'brightness': brightness,
    'contrast': contrast,
    'forceFont': forceFont,
  };

  static String _hexToRgb(String hex) {
    final h = hex.replaceAll('#', '');
    if (h.length != 6) return 'rgb(20, 22, 26)';
    final r = int.tryParse(h.substring(0, 2), radix: 16) ?? 0x14;
    final g = int.tryParse(h.substring(2, 4), radix: 16) ?? 0x16;
    final b = int.tryParse(h.substring(4, 6), radix: 16) ?? 0x1a;
    return 'rgb($r, $g, $b)';
  }

  /// 供 UI 直接用的颜色值。
  int get backgroundArgb =>
      0xFF000000 | (int.tryParse(background.replaceAll('#', ''), radix: 16) ?? 0x14161a);

  int get textArgb =>
      0xFF000000 | (int.tryParse(text.replaceAll('#', ''), radix: 16) ?? 0xd8dade);

  factory ThemePreset.fromJson(Map<String, dynamic> j) => ThemePreset(
    id: j['id'] as String? ?? 'preset-${DateTime.now().millisecondsSinceEpoch}',
    name: j['name'] as String? ?? '未命名',
    background: j['background'] as String? ?? '#14161a',
    text: j['text'] as String? ?? '#d8dade',
    brightness: (j['brightness'] as num?)?.toDouble() ?? 100,
    contrast: (j['contrast'] as num?)?.toDouble() ?? 100,
    forceFont: j['forceFont'] as String?,
    builtin: j['builtin'] as bool? ?? false,
  );

  ThemePreset copyWith({
    String? name,
    String? background,
    String? text,
    double? brightness,
    double? contrast,
    String? forceFont,
    bool clearFont = false,
  }) => ThemePreset(
    id: id,
    name: name ?? this.name,
    background: background ?? this.background,
    text: text ?? this.text,
    brightness: brightness ?? this.brightness,
    contrast: contrast ?? this.contrast,
    forceFont: clearFont ? null : (forceFont ?? this.forceFont),
    builtin: builtin,
  );
}
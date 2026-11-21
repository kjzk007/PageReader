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
    this.link = '#5ac8fa',
    this.selection = '#2f6f8f',
    this.secondaryBackground = '#1a1d23',
    this.secondaryText = '#a8b0bc',
    this.brightness = 100,
    this.contrast = 100,
    this.imageBrightness = 100,
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

  /// 正文里链接的颜色（#RRGGBB）。
  final String link;

  /// 选中文本的背景色（#RRGGBB）。
  final String selection;

  /// 次级背景色（#RRGGBB）：卡片、表格头、侧栏这类
  /// 「比页面主底色深/浅一档」的区域。
  ///
  /// 独立成一个可调项，而不是从主底色推导 —— 派生规则无论怎么写
  /// 都会在某些站点上不对，交给用户直接选最省事。
  final String secondaryBackground;

  /// 次级文字色（#RRGGBB）：说明文字、页脚、表格次要列。
  final String secondaryText;

  /// 0–160，100 表示不调整。
  final double brightness;

  /// 0–160。
  final double contrast;

  /// 图片和视频的亮度，0–150。100 表示不变。
  ///
  /// 深色背景上原图往往刺眼，需要单独压暗；纯文字亮度调不回来。
  final double imageBrightness;

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
    link: '#5ac8fa',
    selection: '#2f6f8f',
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
    'link': link,
    'selection': selection,
    'secondaryBackground': secondaryBackground,
    'secondaryText': secondaryText,
    'brightness': brightness,
    'contrast': contrast,
    'imageBrightness': imageBrightness,
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
    'link': _hexToRgb(link),
    'selection': _hexToRgb(selection),
    'brightness': brightness,
    'contrast': contrast,
    'imageBrightness': imageBrightness,
    // 代码块背景：正文色低浓度叠在页面底色上，随主题走。
    'codeBackground': codeBackground,
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

  int get linkArgb =>
      0xFF000000 | (int.tryParse(link.replaceAll('#', ''), radix: 16) ?? 0x5ac8fa);

  int get secondaryBackgroundArgb =>
      0xFF000000 |
      (int.tryParse(secondaryBackground.replaceAll('#', ''), radix: 16) ??
          0x1a1d23);

  int get secondaryTextArgb =>
      0xFF000000 |
      (int.tryParse(secondaryText.replaceAll('#', ''), radix: 16) ?? 0xa8b0bc);

  int get selectionArgb =>
      0xFF000000 | (int.tryParse(selection.replaceAll('#', ''), radix: 16) ?? 0x2f6f8f);

  /// 代码块背景：正文色以低不透明度叠在页面底色上。
  ///
  /// 代码块的**文字和语法高亮完全不动** —— 那是文档的配色信息。
  /// 但背景必须跟着主题走：站点普遍给代码块设白底，深色页面上
  /// 留一块白会非常刺眼。
  ///
  /// 用叠加而不是写死深色：用户可能建浅色主题，叠加算法两端都对。
  String get codeBackground {
    final bgH = background.replaceAll('#', '');
    final fgH = text.replaceAll('#', '');
    if (bgH.length != 6 || fgH.length != 6) return 'rgba(255,255,255,0.06)';
    final br = int.tryParse(bgH.substring(0, 2), radix: 16) ?? 0x14;
    final bgc = int.tryParse(bgH.substring(2, 4), radix: 16) ?? 0x16;
    final bb = int.tryParse(bgH.substring(4, 6), radix: 16) ?? 0x1a;
    final fr = int.tryParse(fgH.substring(0, 2), radix: 16) ?? 0xd8;
    final fgc = int.tryParse(fgH.substring(2, 4), radix: 16) ?? 0xda;
    final fb = int.tryParse(fgH.substring(4, 6), radix: 16) ?? 0xde;
    const a = 0.09;
    final r = (br * (1 - a) + fr * a).round();
    final g = (bgc * (1 - a) + fgc * a).round();
    final b = (bb * (1 - a) + fb * a).round();
    return 'rgb($r, $g, $b)';
  }

  factory ThemePreset.fromJson(Map<String, dynamic> j) => ThemePreset(
    id: j['id'] as String? ?? 'preset-${DateTime.now().millisecondsSinceEpoch}',
    name: j['name'] as String? ?? '未命名',
    background: j['background'] as String? ?? '#14161a',
    text: j['text'] as String? ?? '#d8dade',
    link: j['link'] as String? ?? '#5ac8fa',
    selection: j['selection'] as String? ?? '#2f6f8f',
    secondaryBackground: j['secondaryBackground'] as String? ?? '#1a1d23',
    secondaryText: j['secondaryText'] as String? ?? '#a8b0bc',
    brightness: (j['brightness'] as num?)?.toDouble() ?? 100,
    contrast: (j['contrast'] as num?)?.toDouble() ?? 100,
    imageBrightness: (j['imageBrightness'] as num?)?.toDouble() ?? 100,
    forceFont: j['forceFont'] as String?,
    builtin: j['builtin'] as bool? ?? false,
  );

  ThemePreset copyWith({
    String? name,
    String? background,
    String? text,
    String? link,
    String? selection,
    String? secondaryBackground,
    String? secondaryText,
    double? brightness,
    double? contrast,
    double? imageBrightness,
    String? forceFont,
    bool clearFont = false,
  }) => ThemePreset(
    id: id,
    name: name ?? this.name,
    background: background ?? this.background,
    text: text ?? this.text,
    link: link ?? this.link,
    selection: selection ?? this.selection,
    secondaryBackground: secondaryBackground ?? this.secondaryBackground,
    secondaryText: secondaryText ?? this.secondaryText,
    brightness: brightness ?? this.brightness,
    contrast: contrast ?? this.contrast,
    imageBrightness: imageBrightness ?? this.imageBrightness,
    forceFont: clearFont ? null : (forceFont ?? this.forceFont),
    builtin: builtin,
  );
}

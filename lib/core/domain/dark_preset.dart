/// 深色注入预设。
///
/// 一组参数，决定"按什么规则把浅色页面变成深色"。
/// 用户可以在设置里建多个预设，然后在书架上右键给某本书指定用哪个；
/// 不指定就是「默认」——一个字都不注入。
///
/// 设计上只有 dynamic 一种引擎模式：
/// - 不用 CSS filter 反色（蓝色会变橙、图片颜色错乱）
/// - 不用静态主题（需要站点配合，我们的站点是任意的）
/// 而是逐元素读 computed style，把浅色算成同色系的深色。
class DarkPreset {
  const DarkPreset({
    required this.id,
    required this.name,
    this.background = '#14161a',
    this.text = '#d8dade',
    this.brightness = 100,
    this.contrast = 100,
    this.grayscale = 0,
    this.sepia = 0,
    this.forceFont,
    this.builtin = false,
  });

  /// 稳定标识。内置预设用固定 id，用户新建的用时间戳。
  final String id;
  final String name;

  /// 页面底色（十六进制）。同时用于防闪白的占位色。
  final String background;

  /// 正文颜色（十六进制）。
  final String text;

  /// 0–160，100 表示不调整。
  final double brightness;

  /// 0–160。
  final double contrast;

  /// 0–100。
  final double grayscale;

  /// 0–100。
  final double sepia;

  /// 强制字体名；null 表示不动站点字体。
  final String? forceFont;

  /// 内置预设不可删除。
  final bool builtin;

  /// 内置的唯一预设。
  ///
  /// 只做一个：需要米黄、护眼的用户自己新建，不预置一堆没人用的。
  static const night = DarkPreset(
    id: 'preset-night',
    name: '深色模式',
    background: '#14161a',
    text: '#d8dade',
    builtin: true,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'background': background,
    'text': text,
    'brightness': brightness,
    'contrast': contrast,
    'grayscale': grayscale,
    'sepia': sepia,
    'forceFont': forceFont,
    'builtin': builtin,
  };

  /// 供注入脚本消费的结构。
  ///
  /// 只在启用时展开；字段名与引擎骨架里的 THEME 对应。
  Map<String, dynamic> toEngineJson() => {
    'enabled': true,
    'background': _hexToRgb(background),
    'text': _hexToRgb(text),
    'brightness': brightness,
    'contrast': contrast,
    'grayscale': grayscale,
    'sepia': sepia,
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

  factory DarkPreset.fromJson(Map<String, dynamic> j) => DarkPreset(
    id: j['id'] as String? ?? 'preset-${DateTime.now().millisecondsSinceEpoch}',
    name: j['name'] as String? ?? '未命名',
    background: j['background'] as String? ?? '#14161a',
    text: j['text'] as String? ?? '#d8dade',
    brightness: (j['brightness'] as num?)?.toDouble() ?? 100,
    contrast: (j['contrast'] as num?)?.toDouble() ?? 100,
    grayscale: (j['grayscale'] as num?)?.toDouble() ?? 0,
    sepia: (j['sepia'] as num?)?.toDouble() ?? 0,
    forceFont: j['forceFont'] as String?,
    builtin: j['builtin'] as bool? ?? false,
  );

  DarkPreset copyWith({
    String? name,
    String? background,
    String? text,
    double? brightness,
    double? contrast,
    double? grayscale,
    double? sepia,
    String? forceFont,
    bool clearFont = false,
  }) => DarkPreset(
    id: id,
    name: name ?? this.name,
    background: background ?? this.background,
    text: text ?? this.text,
    brightness: brightness ?? this.brightness,
    contrast: contrast ?? this.contrast,
    grayscale: grayscale ?? this.grayscale,
    sepia: sepia ?? this.sepia,
    forceFont: clearFont ? null : (forceFont ?? this.forceFont),
    builtin: builtin,
  );
}

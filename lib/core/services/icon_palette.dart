import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_cache_manager/flutter_cache_manager.dart';

/// 从图标里取颜色,用于决定封面底色。
///
/// 分两种情况,不能用同一套规则(踩过坑):
///
///   1. **自带不透明底框**的图标(K8s 的纯白底 PNG、MDN 的深色底 PNG):
///      直接拿那块底色当卡片底色。图标的白框就和卡片融为一体,
///      不再是"贴在封面上的补丁",整张卡片看起来就是封面。
///
///   2. **透明图标**(大多数 SVG,以及带 alpha 的 PNG):
///      不能用它的主色当底色 —— Python 的图标是蓝+黄,
///      给它铺一块蓝色卡片会蓝压蓝,图标直接看不见。
///      这类必须用主色的**深色版**,把明度差拉开来。
class IconPalette {
  const IconPalette._();

  /// 图标自带的不透明底色。null 表示透明或取不到。
  ///
  /// 判据:四角像素颜色完全一致且不透明。
  /// 只要有一个角不同,就说明是满幅图案或渐变,不该改卡片底色。
  ///
  /// 出口统一兜异常:缓存管理器依赖 path_provider,
  /// 在没有平台通道的环境(单元测试、早期启动)里会抛。
  /// 这类失败必须降级成 null,不能让"取底色"这种装饰性的事把主流程带崩。
  static Future<int?> backgroundOf(String url) async {
    try {
      return await _backgroundOf(url);
    } catch (_) {
      return null;
    }
  }

  static Future<int?> _backgroundOf(String url) async {
    final decoded = await _decode(url);
    if (decoded == null) return null;
    if (decoded.hasAlpha && decoded.cornersOpaque == false) return null;

    final corners = decoded.corners;
    final first = corners.first;
    for (final c in corners) {
      if (c != first) return null;
    }
    // 完全透明就当没有背景。
    if (((first >> 24) & 0xFF) < 200) return null;
    return first;
  }

  /// 图标的主色(出现最多的不透明颜色)。null 表示取不到。
  ///
  /// 只用来推导"深色版底色",不直接当卡片底面。
  static Future<int?> dominantOf(String url) async {
    try {
      return await _dominantOf(url);
    } catch (_) {
      return null;
    }
  }

  static Future<int?> _dominantOf(String url) async {
    // 空 URL 直接返回。
    //
    // 踩过的坑:没有这道防御时,空 URL 会拼成缓存 key 撞上别的条目,
    // 解出一张不相干的图的主色 —— Go 的底色变成奇怪的灰蓝就是这么来的,
    // 而它的图标其实是浅蓝地鼠。
    if (url.trim().isEmpty) return null;

    final clean = url.split('?').first.toLowerCase();
    if (clean.endsWith('.svg')) {
      final text = await _downloadText(url);
      if (text == null) return null;
      return _svgDominant(text);
    }
    final decoded = await _decode(url);
    return decoded?.dominant;
  }

  // ---------------------------------------------------------------- SVG

  /// 从 SVG 源码里统计出现最多的填充色。
  ///
  /// 纯文本正则就够:图标 SVG 的颜色都写在 fill/stroke/style 里,
  /// 不需要真的渲染。
  ///
  /// 但有三类要特殊处理(Go 的图标就是第三类):
  ///   1. 属性直接写色值:`fill="#5A9FD4"`
  ///   2. `<style>` 里定义:`svg { fill: white }`
  ///   3. 完全不给颜色(path 无 fill,靠外部 CSS 或 context)—— 采不到,
  ///      返回 null,由上层改用别的方式决定底色。
  static int? _svgDominant(String svg) {
    final counts = <int, int>{};

    // 1. 属性形式的色值。要求前面不是字母/连字符,
    //    避免把 `fill-opacity`、`color-scheme` 这类属性误当成颜色。
    final attrRe = RegExp(
      r'''(?:^|[\s;])(?:fill|stroke|stop-color)\s*=\s*["']\s*(#[0-9a-fA-F]{3,8})''',
    );
    for (final m in attrRe.allMatches(svg)) {
      _countColor(counts, _parseHex(m.group(1)!));
    }

    // 2. CSS 形式的色值(style 块或 style 属性)。
    //    同样要求前面是边界,避免 `-color:` 之类命中。
    final cssRe = RegExp(
      r'''(?:^|[\s;{])(?:fill|stroke|stop-color)\s*:\s*(#[0-9a-fA-F]{3,8})''',
    );
    for (final m in cssRe.allMatches(svg)) {
      _countColor(counts, _parseHex(m.group(1)!));
    }

    // 2b. CSS 里用颜色名:`fill: white`
    //
    // 这里**不再匹配 `color:`** —— Go 的图标里有
    // `@media (prefers-color-scheme: dark)`,旧的宽泛正则会把它误判成
    // "color: dark",进而当成灰色系,这正是 Go 底色变灰的真正原因。
    final namedRe = RegExp(
      r'''(?:^|[\s;{])(?:fill|stroke|stop-color)\s*:\s*(white|black|blue|red|green|gray|grey|orange|purple|navy|teal)\b''',
      caseSensitive: false,
    );
    for (final m in namedRe.allMatches(svg)) {
      _countColor(counts, _namedColor(m.group(1)!.toLowerCase()));
    }

    if (counts.isEmpty) return null;

    // 选主色:优先高饱和度的,其次出现次数多的。
    //
    // 为什么不能只看次数:Go 的 favicon 是完整吉祥物插画,
    // 身体深灰蓝 #384E54 出现 7 次、鳍的高光 #76E1FE 出现 3 次。
    // 按次数会选到身体色,提亮后就是无趣的灰;而浅蓝才是它的识别色。
    // 给"有彩度"的颜色加权,才能挑出真正有辨识度的那个。
    final scored = counts.entries.map((e) {
      final r = (e.key >> 16) & 0xFF;
      final g = (e.key >> 8) & 0xFF;
      final b = e.key & 0xFF;
      final maxC = [r, g, b].reduce((x, y) => x > y ? x : y);
      final minC = [r, g, b].reduce((x, y) => x < y ? x : y);
      final sat = maxC == 0 ? 0.0 : (maxC - minC) / maxC;
      final luma = (0.299 * r + 0.587 * g + 0.114 * b) / 255;
      // 太暗的颜色不适合当底色,降权。
      final lumaPenalty = luma < 0.18 ? 0.35 : 1.0;
      // 暖色(黄/橙)降权。
      //
      // 这类高饱和浅色压暗后必然变成浑浊的橄榄或褐色 ——
      // Python 图标的黄色高光就会让封面变成土黄,
      // 虽然算法上"够醒目",但视觉上不像那个站,也不好看。
      // 冷色(蓝/青/绿/紫)压暗后仍然清爽,更适合当深色底。
      final isWarm = r > g && g >= b && (r - b) > 40;
      final warmPenalty = isWarm ? 0.35 : 1.0;
      // 权重取中间值:
      //   * 纯按次数 → 会选到深灰蓝那种"面积大但没辨识度"的填充色
      //   * 纯按饱和度 → 会选到黄色高光
      // 次数仍然重要:面积大的颜色往往才是印象里的主色。
      final score = e.value * (0.5 + sat * 1.8) * lumaPenalty * warmPenalty;
      return (key: e.key, score: score);
    }).toList()..sort((a, b) => b.score.compareTo(a.score));

    return 0xFF000000 | scored.first.key;
  }

  static void _countColor(Map<int, int> counts, int? c) {
    if (c == null) return;
    // 忽略近乎白色:那不是图标的主体色,拿它做底色等于没做。
    final luma =
        0.299 * ((c >> 16) & 0xFF) +
        0.587 * ((c >> 8) & 0xFF) +
        0.114 * (c & 0xFF);
    if (luma > 235) return;
    final key = c & 0xFFFFFF;
    counts[key] = (counts[key] ?? 0) + 1;
  }

  static int? _namedColor(String name) => switch (name) {
    'white' => 0xFFFFFFFF,
    'black' => 0xFF000000,
    'blue' => 0xFF0000FF,
    'red' => 0xFFFF0000,
    'green' => 0xFF008000,
    'gray' || 'grey' => 0xFF808080,
    'orange' => 0xFFFFA500,
    'purple' => 0xFF800080,
    'navy' => 0xFF000080,
    'teal' => 0xFF008080,
    _ => null,
  };

  static int? _parseHex(String v) {
    var s = v.trim();
    if (!s.startsWith('#')) return null;
    s = s.substring(1);
    if (s.length == 3) {
      s = s.split('').map((c) => '$c$c').join();
    }
    if (s.length == 6) {
      final rgb = int.tryParse(s, radix: 16);
      return rgb == null ? null : (0xFF000000 | rgb);
    }
    if (s.length == 8) return int.tryParse(s, radix: 16);
    return null;
  }

  // ---------------------------------------------------------------- 解码入口

  static Future<_Decoded?> _decode(String url) async {
    // 先做纯字符串校验,别让非法 URL 走到下载环节。
    //
    // 为什么重要:下载要用 flutter_cache_manager,它会向
    // path_provider 要临时目录。在单元测试等没有平台通道的环境里,
    // 这一步抛 MissingPluginException,而且是在 binding 层抛出、
    // 被测代码 catch 不住 —— 一条本该"输入非法就返回 null"的
    // 简单用例,会变成环境异常。
    // 先挡掉空/畸形 URL,这些用例就永远碰不到平台通道。
    final trimmed = url.trim();
    if (trimmed.isEmpty) return null;
    final uri = Uri.tryParse(trimmed);
    if (uri == null) return null;
    if (!uri.hasScheme || (uri.scheme != 'http' && uri.scheme != 'https')) {
      return null;
    }
    if (uri.host.isEmpty) return null;

    final bytes = await _download(trimmed);
    if (bytes == null) return null;
    return _decodePng(bytes);
  }

  static Future<Uint8List?> _download(String url) async {
    // 先看磁盘缓存。
    //
    // 为什么重要:采样和显示走同一个图标 URL,如果各自发起请求,
    // 第二次会撞限流或超时,采样拿到空数据后颜色退成纯黑。
    // 复用缓存既快又稳,还能保证"看到的就是采样到的那张图"。
    try {
      final cached = await DefaultCacheManager().getFileFromCache(url);
      if (cached != null && cached.file.existsSync()) {
        return await cached.file.readAsBytes();
      }
    } catch (_) {
      // 缓存不可用(含无平台通道的测试环境)就继续走网络。
    }

    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 3);
    try {
      final uri = Uri.tryParse(url);
      if (uri == null) return null;
      final req = await client.getUrl(uri).timeout(const Duration(seconds: 3));
      final res = await req.close().timeout(const Duration(seconds: 3));
      if (res.statusCode != 200) {
        await res.drain<void>();
        return null;
      }
      final builder = BytesBuilder();
      var total = 0;
      await for (final chunk in res.timeout(const Duration(seconds: 3))) {
        total += chunk.length;
        // 图标不会太大;超过 2MB 当异常处理,避免拖慢启动。
        if (total > 2 * 1024 * 1024) return null;
        builder.add(chunk);
      }
      final bytes = builder.takeBytes();
      // 顺手落盘,下次采样和显示都能直接用。
      try {
        await DefaultCacheManager().putFile(
          url,
          bytes,
          fileExtension: uri.path.split('.').last,
        );
      } catch (_) {}
      return bytes;
    } catch (_) {
      return null;
    } finally {
      client.close(force: true);
    }
  }

  static Future<String?> _downloadText(String url) async {
    final bytes = await _download(url);
    if (bytes == null) return null;
    return String.fromCharCodes(bytes.take(262144));
  }

  // ---------------------------------------------------------------- PNG

  static _Decoded? _decodePng(Uint8List bytes) {
    if (bytes.length < 33) return null;
    const sig = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];
    for (var i = 0; i < 8; i++) {
      if (bytes[i] != sig[i]) return null;
    }

    var offset = 8;
    var width = 0, height = 0, bitDepth = 0, colorType = 0, interlace = 0;
    var palette = Uint8List(0);
    var hasTrns = false;

    while (offset + 8 <= bytes.length) {
      final length = _u32(bytes, offset);
      final type = String.fromCharCodes(bytes.sublist(offset + 4, offset + 8));
      if (type == 'IHDR') {
        width = _u32(bytes, offset + 8);
        height = _u32(bytes, offset + 12);
        bitDepth = bytes[offset + 16];
        colorType = bytes[offset + 17];
        interlace = bytes[offset + 20];
      } else if (type == 'PLTE') {
        palette = Uint8List.fromList(
          bytes.sublist(offset + 8, offset + 8 + length),
        );
      } else if (type == 'tRNS') {
        hasTrns = true;
      } else if (type == 'IDAT') {
        break;
      }
      offset += 12 + length;
    }

    if (interlace != 0 || width < 8 || height < 8) return null;

    final isPalette = colorType == 3 && bitDepth == 8;
    final isRgb =
        (colorType == 2 || colorType == 6) &&
        (bitDepth == 8 || bitDepth == 16);
    if (!isPalette && !isRgb) return null;

    final channels = switch (colorType) {
      2 => bitDepth == 16 ? 6 : 3,
      6 => bitDepth == 16 ? 8 : 4,
      _ => 1,
    };

    // 收集 IDAT
    offset = 8;
    final idat = BytesBuilder();
    while (offset + 8 <= bytes.length) {
      final length = _u32(bytes, offset);
      final type = String.fromCharCodes(bytes.sublist(offset + 4, offset + 8));
      if (type == 'IDAT') {
        idat.add(bytes.sublist(offset + 8, offset + 8 + length));
      } else if (type == 'IEND') {
        break;
      }
      offset += 12 + length;
    }

    final raw = idat.takeBytes();
    if (raw.isEmpty) return null;
    final stride = width * channels;
    final inflated = _inflate(raw);
    if (inflated == null || inflated.length < (stride + 1) * height) {
      return null;
    }
    final pixels = _unfilter(inflated, width, height, channels, stride);
    if (pixels == null) return null;

    int sample(int x, int y) {
      if (!isPalette) return _px(pixels, x, y, stride, channels);
      final idx = pixels[y * stride + x];
      final off = idx * 3;
      if (off + 2 >= palette.length) return 0;
      final a = hasTrns ? 255 : 255;
      return (a << 24) |
          (palette[off] << 16) |
          (palette[off + 1] << 8) |
          palette[off + 2];
    }

    final corners = [
      sample(0, 0),
      sample(width - 1, 0),
      sample(0, height - 1),
      sample(width - 1, height - 1),
    ];

    // 主色直方图:抽样即可,不用每个像素都算。
    final counts = <int, int>{};
    final step = (width * height ~/ 4096).clamp(1, 999999);
    for (var i = 0; i < width * height; i += step) {
      final x = i % width;
      final y = i ~/ width;
      final c = sample(x, y);
      final a = (c >> 24) & 0xFF;
      if (a < 200) continue;
      final luma =
          0.299 * ((c >> 16) & 0xFF) +
          0.587 * ((c >> 8) & 0xFF) +
          0.114 * (c & 0xFF);
      if (luma > 235) continue;
      final key = c & 0xFFFFFF;
      counts[key] = (counts[key] ?? 0) + 1;
    }

    // 同 SVG:优先高饱和度的颜色,而不是单纯按出现次数。
    int? dominant;
    var bestScore = 0.0;
    for (final e in counts.entries) {
      final r = (e.key >> 16) & 0xFF;
      final g = (e.key >> 8) & 0xFF;
      final b = e.key & 0xFF;
      final maxC = [r, g, b].reduce((x, y) => x > y ? x : y);
      final minC = [r, g, b].reduce((x, y) => x < y ? x : y);
      final sat = maxC == 0 ? 0.0 : (maxC - minC) / maxC;
      final luma = (0.299 * r + 0.587 * g + 0.114 * b) / 255;
      final penalty = luma < 0.18 ? 0.5 : 1.0;
      final score = e.value * (0.15 + sat * 2.5) * penalty;
      if (score > bestScore) {
        bestScore = score;
        dominant = e.key;
      }
    }

    final cornersOpaque = corners.every((c) => ((c >> 24) & 0xFF) >= 200);

    return _Decoded(
      corners: corners,
      dominant: dominant == null ? null : (0xFF000000 | dominant),
      hasAlpha: colorType == 6 || isPalette && hasTrns,
      cornersOpaque: cornersOpaque,
    );
  }

  static int _u32(Uint8List b, int o) =>
      (b[o] << 24) | (b[o + 1] << 16) | (b[o + 2] << 8) | b[o + 3];

  static int _px(Uint8List p, int x, int y, int stride, int bpp) {
    final i = y * stride + x * bpp;
    final r = p[i];
    final g = p[i + 1];
    final b = p[i + 2];
    final a = bpp == 4 ? p[i + 3] : (bpp == 8 ? p[i + 6] : 255);
    return (a << 24) | (r << 16) | (g << 8) | b;
  }

  static Uint8List? _inflate(Uint8List data) {
    try {
      return Uint8List.fromList(ZLibDecoder().convert(data));
    } catch (_) {
      return null;
    }
  }

  static Uint8List? _unfilter(
    Uint8List raw,
    int width,
    int height,
    int bpp,
    int stride,
  ) {
    final out = Uint8List(stride * height);
    var prev = Uint8List(stride);
    var pos = 0;
    for (var y = 0; y < height; y++) {
      if (pos >= raw.length) return null;
      final filter = raw[pos++];
      final line = Uint8List(stride);
      for (var i = 0; i < stride; i++) {
        if (pos >= raw.length) return null;
        final cur = raw[pos++];
        final a = i >= bpp ? line[i - bpp] : 0;
        final b = prev[i];
        final c = i >= bpp ? prev[i - bpp] : 0;
        final v = switch (filter) {
          0 => cur,
          1 => cur + a,
          2 => cur + b,
          3 => cur + ((a + b) >> 1),
          4 => cur + _paeth(a, b, c),
          _ => -1,
        };
        if (v < 0) return null;
        line[i] = v & 0xFF;
      }
      out.setRange(y * stride, (y + 1) * stride, line);
      prev = line;
    }
    return out;
  }

  static int _paeth(int a, int b, int c) {
    final p = a + b - c;
    final pa = (p - a).abs();
    final pb = (p - b).abs();
    final pc = (p - c).abs();
    if (pa <= pb && pa <= pc) return a;
    return pb <= pc ? b : c;
  }
}

class _Decoded {
  const _Decoded({
    required this.corners,
    required this.dominant,
    required this.hasAlpha,
    required this.cornersOpaque,
  });

  final List<int> corners;
  final int? dominant;
  final bool hasAlpha;
  final bool cornersOpaque;
}

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// 封面图标抓取。
///
/// 顺序(台账已定):
///   1. manifest 的 icons 512
///   2. apple-touch-icon 180
///   3. favicon,但只接受 ≥96px 的
///   4. 都没有 → 返回 null,界面用标题首字兜底
///
/// 为什么门槛是 96px:16/32px 的 favicon 放大到书架卡片那么大
/// 只会糊成一团色块,比首字母还难看。
///
/// 抓取失败一律返回 null,绝不抛异常、绝不阻塞加书。
class IconFetcher {
  const IconFetcher._();

  static const int minSize = 96;
  static const Duration timeout = Duration(seconds: 3);

  /// 返回图标 URL(不下载图片本身),找不到返回 null。
  static Future<IconInfo?> find(String pageUrl) async {
    final base = Uri.tryParse(pageUrl.trim());
    if (base == null || !base.hasScheme || base.host.isEmpty) return null;

    // 整体硬上限:抓图标是"锦上添花",绝不能拖住加书。
    // 实测个别站点(go.dev)单次就要 6 秒,重试会到 12 秒;
    // 超过这个时间就直接放弃,用首字母兜底。
    try {
      return await _findInternal(base).timeout(
        const Duration(seconds: 5),
        onTimeout: () => null,
      );
    } catch (_) {
      return null;
    }
  }

  static Future<IconInfo?> _findInternal(Uri base) async {
    final client = HttpClient()..connectionTimeout = timeout;
    try {
      // 1. 先看 HTML 里的 manifest 和各类 icon。
      final html = await _get(client, base);
      if (html != null) {
        final links = _linkTags(html);

        // manifest 里可能有 512 的大图,最清晰,优先。
        final manifestHref = _hrefByRel(links, (r) => r.contains('manifest'));
        if (manifestHref != null) {
          final manifestUri = base.resolve(manifestHref);
          final manifest = await _getJson(client, manifestUri);
          final icon = _pickFromManifest(manifest, manifestUri);
          if (icon != null) return icon;
        }

        // apple-touch-icon:常见 180,也有带尺寸后缀的(如 -256x256)。
        // 没写尺寸的也接受 —— Go 官方文档就是这样,它的图实际是合适的方图。
        final appleIcon = _hrefByRelPrefix(links, 'apple-touch-icon');
        if (appleIcon != null) {
          final size = _sizeForHref(links, appleIcon);
          return IconInfo(
            url: base.resolve(appleIcon).toString(),
            size: size >= minSize ? size : 180,
          );
        }

        // 普通 icon:声明了尺寸且够大才用。
        final iconHref = _hrefByRel(
          links,
          (r) => r == 'icon' || r == 'shortcut icon',
        );
        if (iconHref != null) {
          final size = _sizeForHref(links, iconHref);
          if (size >= minSize) {
            return IconInfo(url: base.resolve(iconHref).toString(), size: size);
          }
        }

        // 最后一道:SVG 图标。
        // 矢量图放大不糊,在书架上比 32px 的位图好看得多;
        // 之前一律跳过 SVG 是过度保守。
        final svgHref = _svgIconHref(links);
        if (svgHref != null) {
          return IconInfo(url: base.resolve(svgHref).toString(), size: minSize);
        }
      }

      // 2. 什么都没达标:直接放弃,让界面用首字母。
      //    16/32px 的 favicon 放大后只会糊成一团,比首字母更难看。
      return null;
    } catch (_) {
      return null;
    } finally {
      client.close(force: true);
    }
  }

  /// 顺带取主题色,用作封面底色。
  static Future<int?> themeColor(String pageUrl) async {
    final base = Uri.tryParse(pageUrl.trim());
    if (base == null || !base.hasScheme) return null;
    final client = HttpClient()..connectionTimeout = timeout;
    try {
      final html = await _get(client, base);
      if (html == null) return null;
      final m = RegExp(
        r'''<meta[^>]+name=["']theme-color["'][^>]+content=["']([^"']+)''',
        caseSensitive: false,
      ).firstMatch(html);
      return m == null ? null : _parseColor(m.group(1)!);
    } catch (_) {
      return null;
    } finally {
      client.close(force: true);
    }
  }

  // ---------------------------------------------------------------- 解析

  static Future<String?> _get(HttpClient client, Uri uri) async {
    // 失败重试一次:实测 MDN 这类大页面偶发超时,
    // 不重试会让同一本书的封面时有时无,不可预期。
    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        final req = await client.getUrl(uri).timeout(timeout);
        req.headers.set('User-Agent', 'PageReader/1.0');
        final res = await req.close().timeout(timeout);
        if (res.statusCode != 200) {
          await res.drain<void>();
          if (res.statusCode < 500) return null; // 4xx 重试也没用
          continue;
        }
        final bytes = await res
            .fold<BytesBuilder>(BytesBuilder(), (b, d) => b..add(d))
            .timeout(timeout);
        final all = bytes.takeBytes();
        // 只取前 512KB。图标信息都在 <head> 里,
        // 但有些站点 <head> 很长(MDN 光 <link> 就几百个),
        // 截太短会把 manifest 声明切掉 —— 那是封面清晰度的关键来源。
        final slice = all.length > 524288
            ? Uint8List.sublistView(all, 0, 524288)
            : all;
        return utf8.decode(slice, allowMalformed: true);
      } catch (_) {
        if (attempt == 1) return null;
        await Future<void>.delayed(const Duration(milliseconds: 300));
      }
    }
    return null;
  }

  static Future<Map<String, dynamic>?> _getJson(
    HttpClient client,
    Uri uri,
  ) async {
    final text = await _get(client, uri);
    if (text == null) return null;
    try {
      return jsonDecode(text) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  /// 把 <link> 标签解析成属性表。
  ///
  /// 必须自己解析而不是用正则抓 `rel="..."`:
  /// 很多站点写 `rel=icon href=/x.png`(属性不加引号),
  /// 用要求引号的正则会全部漏掉 —— kubernetes.io 就是这样,
  /// 而它其实有 256px 的 apple-touch-icon。
  static List<Map<String, String>> _linkTags(String html) {
    final out = <Map<String, String>>[];
    final tagRe = RegExp(r'<link\b[^>]*>', caseSensitive: false);
    // 属性值可带引号(单/双)或不带,不带时遇到空白或 > 结束。
    final attrRe = RegExp(
      r'''([a-zA-Z_:][-a-zA-Z0-9_:.]*)\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s"'>]+))''',
    );

    for (final tag in tagRe.allMatches(html)) {
      final text = tag.group(0)!;
      final attrs = <String, String>{};
      for (final a in attrRe.allMatches(text)) {
        final key = a.group(1)!.toLowerCase();
        final value = a.group(2) ?? a.group(3) ?? a.group(4) ?? '';
        attrs[key] = value;
      }
      if (attrs.isNotEmpty) out.add(attrs);
    }
    return out;
  }

  /// 找 SVG 图标。矢量图放大不糊,适合当封面。
  static String? _svgIconHref(List<Map<String, String>> links) {
    for (final a in links) {
      final rel = (a['rel'] ?? '').toLowerCase();
      final type = (a['type'] ?? '').toLowerCase();
      final href = a['href'];
      if (href == null || href.isEmpty) continue;
      final isIcon = rel == 'icon' || rel == 'shortcut icon';
      if (!isIcon) continue;
      if (type.contains('svg') || href.toLowerCase().endsWith('.svg')) {
        return href;
      }
    }
    return null;
  }

  /// 从 rel 里筛出指定类型,返回 href。
  static String? _hrefByRel(
    List<Map<String, String>> links,
    bool Function(String rel) match,
  ) {
    for (final a in links) {
      final rel = (a['rel'] ?? '').toLowerCase();
      final href = a['href'];
      if (href == null || href.isEmpty) continue;
      if (match(rel)) return href;
    }
    return null;
  }

  /// rel 形如 "apple-touch-icon-256x256" 也算 apple-touch-icon。
  static String? _hrefByRelPrefix(
    List<Map<String, String>> links,
    String prefix,
  ) {
    String? best;
    var bestSize = 0;
    for (final a in links) {
      final rel = (a['rel'] ?? '').toLowerCase();
      final href = a['href'];
      if (href == null || href.isEmpty) continue;
      if (!rel.startsWith(prefix)) continue;
      // 从 rel 或 sizes 里取尺寸,挑最大的。
      var px = 0;
      final m = RegExp(r'(\d+)').firstMatch(rel);
      if (m != null) px = int.tryParse(m.group(1)!) ?? 0;
      final sizes = a['sizes'] ?? '';
      final ms = RegExp(r'(\d+)').firstMatch(sizes);
      if (ms != null) {
        final v = int.tryParse(ms.group(1)!) ?? 0;
        if (v > px) px = v;
      }
      if (px > bestSize) {
        bestSize = px;
        best = href;
      }
    }
    return best;
  }

  /// 查某个 href 对应的图标在 HTML 里声明的尺寸。
  /// rel 里可能带尺寸(如 apple-touch-icon-256x256),sizes 属性里也可能有。
  static int _sizeForHref(List<Map<String, String>> links, String href) {
    for (final a in links) {
      if ((a['href'] ?? '') != href) continue;
      final sizes = a['sizes'] ?? '';
      final m = RegExp(r'(\d+)').firstMatch(sizes);
      if (m != null) return int.tryParse(m.group(1)!) ?? 0;
      final rel = (a['rel'] ?? '').toLowerCase();
      final mr = RegExp(r'(\d+)').firstMatch(rel);
      if (mr != null) return int.tryParse(mr.group(1)!) ?? 0;
    }
    return 0;
  }

  /// 从 manifest 里挑最大且接近方形的图标。
  static IconInfo? _pickFromManifest(
    Map<String, dynamic>? manifest,
    Uri manifestUri,
  ) {
    if (manifest == null) return null;
    final icons = manifest['icons'];
    if (icons is! List || icons.isEmpty) return null;

    IconInfo? best;
    for (final raw in icons) {
      if (raw is! Map) continue;
      final src = raw['src'] as String?;
      if (src == null || src.isEmpty) continue;
      final sizes = (raw['sizes'] as String? ?? '').toLowerCase();
      final type = (raw['type'] as String? ?? '').toLowerCase();
      if (type.startsWith('image/svg')) continue; // SVG 在书架上渲染不稳

      var px = 0;
      final m = RegExp(r'(\d+)').firstMatch(sizes);
      if (m != null) px = int.tryParse(m.group(1)!) ?? 0;
      if (px < minSize) continue;

      if (best == null || px > best.size) {
        best = IconInfo(url: manifestUri.resolve(src).toString(), size: px);
      }
    }
    return best;
  }

  static int? _parseColor(String value) {
    var v = value.trim();
    if (!v.startsWith('#')) return null;
    v = v.substring(1);
    if (v.length == 3) {
      v = v.split('').map((c) => '$c$c').join();
    }
    if (v.length == 6) {
      final rgb = int.tryParse(v, radix: 16);
      return rgb == null ? null : (0xFF000000 | rgb);
    }
    if (v.length == 8) {
      return int.tryParse(v, radix: 16);
    }
    return null;
  }
}

class IconInfo {
  const IconInfo({required this.url, required this.size});

  final String url;
  final int size;
}

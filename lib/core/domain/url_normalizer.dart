/// URL 归一化:进度能不能对上,全靠这一层。
///
/// 规则(已定):
///   1. scheme/host 小写,去掉默认端口
///   2. 丢掉 fragment(#后面的部分)
///   3. 丢掉 utm_* 与常见跟踪参数,其余 query 保留并排序
///   4. 路径末尾斜杠归一(根路径除外)
///   5. 不改动路径大小写:有些站点 /Docs 与 /docs 是两个页面
library;

class UrlNormalizer {
  const UrlNormalizer._();

  static const Set<String> _trackingParams = {
    'fbclid',
    'gclid',
    'mc_cid',
    'mc_eid',
    'ref',
    'spm',
    'from',
  };

  /// 用于"这一页是不是同一页"的判定,也是进度表的主键之一。
  static String normalize(String raw) {
    final uri = Uri.parse(raw.trim());
    if (!uri.hasScheme) {
      return normalize('https://$raw');
    }

    final kept = <String, String>{};
    uri.queryParameters.forEach((key, value) {
      final lower = key.toLowerCase();
      if (lower.startsWith('utm_') || _trackingParams.contains(lower)) return;
      kept[key] = value;
    });

    final sortedKeys = kept.keys.toList()..sort();
    final query = sortedKeys.isEmpty
        ? null
        : sortedKeys.map((k) => '$k=${kept[k]}').join('&');

    var path = uri.path;
    if (path == '/') {
      path = '';
    } else if (path.length > 1 && path.endsWith('/')) {
      path = path.substring(0, path.length - 1);
    }

    return Uri(
      scheme: uri.scheme.toLowerCase(),
      host: uri.host.toLowerCase(),
      port: uri.hasPort && uri.port != 80 && uri.port != 443 ? uri.port : null,
      path: path,
      query: query,
    ).toString();
  }

  /// 从用户输入推导"这本书"的范围。
  ///
  /// 输入是页面(.../ch01-00-getting-started.html)时取所在目录;
  /// 输入是目录(.../zh-cn/docs)时就用它自己。
  static String scopePrefixOf(String raw) {
    final normalized = normalize(raw);
    final uri = Uri.parse(normalized);
    final segments = uri.pathSegments;

    if (segments.isEmpty) {
      return Uri(scheme: uri.scheme, host: uri.host).toString();
    }

    final last = segments.last;
    final looksLikeFile = last.contains('.') && !last.startsWith('.');
    final kept = looksLikeFile
        ? segments.sublist(0, segments.length - 1)
        : segments;

    if (kept.isEmpty) {
      return Uri(scheme: uri.scheme, host: uri.host).toString();
    }
    return Uri(
      scheme: uri.scheme,
      host: uri.host,
      pathSegments: kept,
    ).toString();
  }
}

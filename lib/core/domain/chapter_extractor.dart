/// 从页面标题里提取章节号。
///
/// 技术文档的标题几乎都带编号,但书架上一排"第 12 章"远比一排
/// "第 12 章 - 某某文档"好扫。提取不到就原样返回,不做任何猜测。
///
/// 认这几种(台账已定的三种,外加两个实测常见变体):
///   「第 12 章」/「第十二章」
///   「Chapter 3」/「Ch. 3」
///   「3.2 生命周期」/「2.4.1」
class ChapterExtractor {
  const ChapterExtractor._();

  static final List<RegExp> _patterns = [
    // 第 12 章 / 第12章 / 第十二章
    RegExp(r'第\s*([0-9一二三四五六七八九十百零]+)\s*[章节]'),
    // Chapter 3 / CHAPTER 12
    RegExp(r'\bchapter\s+([0-9]+)', caseSensitive: false),
    // Ch. 3 / Ch 3
    RegExp(r'\bch\.?\s*([0-9]+)', caseSensitive: false),
    // 3.2 / 2.4.1 这种多层编号,只取出现在开头的
    RegExp(r'^\s*([0-9]+(?:\.[0-9]+)+)\b'),
    // 单个数字开头(如 "3 Getting Started"),要求后面有空格和字母,避免误判年份
    RegExp(r'^\s*([0-9]{1,2})\s+[A-Za-z\u4e00-\u9fa5]'),
  ];

  /// 返回形如「第 12 章」「3.2」的短标签,提取不到返回 null。
  static String? extract(String title) {
    final t = title.trim();
    if (t.isEmpty) return null;

    for (final re in _patterns) {
      final m = re.firstMatch(t);
      if (m == null) continue;
      final raw = m.group(1);
      if (raw == null || raw.isEmpty) continue;
      return _format(re, raw);
    }
    return null;
  }

  static String _format(RegExp re, String raw) {
    final source = re.pattern;
    if (source.contains('章')) {
      return '第 ${_toArabic(raw)} 章';
    }
    if (source.toLowerCase().contains('chapter')) {
      return 'Chapter $raw';
    }
    if (source.contains('ch')) {
      return 'Ch. $raw';
    }
    // 纯数字编号:多层保留原样,单层加"第 N 章"。
    if (raw.contains('.')) return raw;
    return '第 $raw 章';
  }

  /// 中文数字转阿拉伯数字,只为显示统一。
  static String _toArabic(String value) {
    final direct = int.tryParse(value);
    if (direct != null) return value;

    const digits = {
      '零': 0,
      '一': 1,
      '二': 2,
      '三': 3,
      '四': 4,
      '五': 5,
      '六': 6,
      '七': 7,
      '八': 8,
      '九': 9,
    };
    // 只处理 100 以内,足够章节用;更大就原样返回。
    if (!value.contains('十')) {
      final d = digits[value];
      return d == null ? value : '$d';
    }
    final parts = value.split('十');
    final tens = parts[0].isEmpty ? 1 : (digits[parts[0]] ?? 0);
    final ones = parts.length > 1 && parts[1].isNotEmpty
        ? (digits[parts[1]] ?? 0)
        : 0;
    final n = tens * 10 + ones;
    return '$n';
  }
}

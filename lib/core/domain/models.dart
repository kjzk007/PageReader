/// 领域模型:只依赖 dart 核心库,不 import 任何插件。
/// 这一层决定"什么是一本书""进度是什么",换引擎、换存储、换 UI 都不该动它。
library;

/// 阅读事件:唯一的时间线出口。
/// v1 只消费 pageEnter / pageLeave 来写 URL 级进度;
/// 将来的"阅读时长""高亮笔记"都挂在这条流上,不改动已有模型。
enum ReadingEventType { pageEnter, pageLeave, navigated }

class ReadingEvent {
  const ReadingEvent({
    required this.bookId,
    required this.url,
    required this.type,
    required this.at,
    this.dwellMs,
  });

  final String bookId;
  final String url;
  final ReadingEventType type;
  final DateTime at;

  /// 仅 pageLeave 有意义:本次停留时长。
  final int? dwellMs;
}

/// 一本书 = 一个 scope(路径前缀),不是一个域名。
/// 这样 kubernetes.io/zh-cn/docs 与 kubernetes.io/en/docs 可以是两本。
class Book {
  const Book({
    required this.id,
    required this.title,
    required this.entryUrl,
    required this.scopePrefix,
    required this.createdAt,
    required this.updatedAt,
    this.iconUrl,
    this.themeColor,
    this.groupId,
    this.sortIndex = 0,
      this.presetId,
    this.deletedAt,
  });

  final String id;
  final String title;

  /// 用户输入的原样 URL,用于"回到这本书"的兜底。
  final String entryUrl;

  /// 归一化后的路径前缀,用于判定某个页面属于哪本书。
  final String scopePrefix;

  /// manifest 或 apple-touch-icon 的地址;为空则回退标题首字。
  final String? iconUrl;

  /// 0xAARRGGBB,来自 manifest 的 theme_color 或图标主色。
  final int? themeColor;

  final String? groupId;
  final int sortIndex;

  /// 深色注入预设 id；null 表示「默认」，打开时不注入任何样式。
  final String? presetId;
  final DateTime createdAt;
  final DateTime updatedAt;

  /// 墓碑:同步时用来传播删除,不物理删除记录。
  final DateTime? deletedAt;

  bool get isDeleted => deletedAt != null;

  /// 判定一个归一化后的 URL 是否属于这本书。
  bool owns(String normalizedUrl) => normalizedUrl.startsWith(scopePrefix);
}

/// 书架分组:单归属,像多看那样一层层文件夹。
class BookGroup {
  const BookGroup({
    required this.id,
    required this.name,
    required this.sortIndex,
    required this.updatedAt,
    this.deletedAt,
  });

  final String id;
  final String name;
  final int sortIndex;
  final DateTime updatedAt;
  final DateTime? deletedAt;
}

/// 锚点:回到"上次那段"所需的最小信息。
/// 三级降级依次使用 cssPath -> textFingerprint -> docRatio。
class Anchor {
  const Anchor({
    required this.cssPath,
    required this.textFingerprint,
    required this.textLength,
    required this.offsetPx,
    required this.docRatio,
  });

  /// 块级元素的 nth-of-type 路径,如 "main > article:nth-of-type(1) > p:nth-of-type(7)"。
  final String cssPath;

  /// 元素文本前 40 字,用来校验 DOM 是否改版。
  final String textFingerprint;

  final int textLength;

  /// 元素顶边相对视口顶边的像素偏移,决定"回到段落的哪一行"。
  final double offsetPx;

  /// 文档整体比例,最后一道兜底。
  final double docRatio;

  Map<String, Object?> toJson() => {
    'cssPath': cssPath,
    'textFingerprint': textFingerprint,
    'textLength': textLength,
    'offsetPx': offsetPx,
    'docRatio': docRatio,
  };

  static Anchor? fromJson(Map<String, Object?>? json) {
    if (json == null) return null;
    return Anchor(
      cssPath: json['cssPath'] as String? ?? '',
      textFingerprint: json['textFingerprint'] as String? ?? '',
      textLength: (json['textLength'] as num?)?.toInt() ?? 0,
      offsetPx: (json['offsetPx'] as num?)?.toDouble() ?? 0,
      docRatio: (json['docRatio'] as num?)?.toDouble() ?? 0,
    );
  }
}

/// 一次"读到哪"的快照。主键是 (bookId, url),一页一条,覆盖写。
class ProgressSnapshot {
  const ProgressSnapshot({
    required this.bookId,
    required this.url,
    required this.pageTitle,
    required this.updatedAt,
    required this.deviceId,
    this.pageHash,
    this.anchor,
  });

  final String bookId;

  /// 归一化后的 URL,与 Book.scopePrefix 同一套规则。
  final String url;

  final String pageTitle;

  /// 页内小节(URL 里 # 后面的部分)。归一化时被剥掉,单独存。
  final String? pageHash;

  final DateTime updatedAt;

  /// 写入方设备标识。
  final String deviceId;

  /// 目录页/首页不记锚点,此时为 null,只记 URL。
  final Anchor? anchor;

  String get key => '$bookId|$url';
}


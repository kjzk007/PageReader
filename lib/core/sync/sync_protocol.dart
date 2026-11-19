import 'dart:convert';

import '../domain/models.dart';

/// 同步协议的数据结构。
///
/// 设计原则:**只传数据,不传实现细节**。
/// 两端可能跑不同版本的 app,协议要能向前兼容 ——
/// 未知字段忽略、缺失字段用默认值,不让旧版本直接失败。
///
/// 传输格式是 JSON,因为两端都是 Dart,而且便于用 curl 手工调试。

/// 同步时传输的一本书。
///
/// 只带同步必需的最小字段:书名、入口、范围、分组名。
/// 图标是本地缓存,不传 —— 对方会自己抓。
class SyncBook {
  const SyncBook({
    required this.id,
    required this.title,
    required this.entryUrl,
    required this.scopePrefix,
    required this.sortIndex,
    required this.createdAt,
    required this.updatedAt,
    this.groupName,
    this.iconUrl,
    this.deletedAt,
  });

  final String id;
  final String title;
  final String entryUrl;
  final String scopePrefix;
  final int sortIndex;
  final DateTime createdAt;
  final DateTime updatedAt;

  /// 用**分组名**而不是分组 ID。
  ///
  /// 为什么:分组 ID 是各自本地生成的(uuid / 时间戳),
  /// 两端不可能一致。用名字做匹配,同名即同组 —— 足够实用。
  final String? groupName;

  final String? iconUrl;

  /// 软删墓碑。非空表示这本书已被删除,同步时要传播删除。
  final DateTime? deletedAt;

  Map<String, Object?> toJson() => {
    'id': id,
    'title': title,
    'entryUrl': entryUrl,
    'scopePrefix': scopePrefix,
    'sortIndex': sortIndex,
    'createdAt': createdAt.millisecondsSinceEpoch,
    'updatedAt': updatedAt.millisecondsSinceEpoch,
    if (groupName != null) 'groupName': groupName,
    if (iconUrl != null) 'iconUrl': iconUrl,
    if (deletedAt != null) 'deletedAt': deletedAt!.millisecondsSinceEpoch,
  };

  static SyncBook? fromJson(Map<String, dynamic> j) {
    final id = j['id'] as String?;
    final entryUrl = j['entryUrl'] as String?;
    if (id == null || id.isEmpty) return null;
    if (entryUrl == null || entryUrl.isEmpty) return null;
    return SyncBook(
      id: id,
      title: j['title'] as String? ?? entryUrl,
      entryUrl: entryUrl,
      scopePrefix: j['scopePrefix'] as String? ?? entryUrl,
      sortIndex: (j['sortIndex'] as num?)?.toInt() ?? 0,
      createdAt: _date(j['createdAt']) ?? DateTime.now(),
      updatedAt: _date(j['updatedAt']) ?? DateTime.now(),
      groupName: j['groupName'] as String?,
      iconUrl: j['iconUrl'] as String?,
      deletedAt: _date(j['deletedAt']),
    );
  }

  /// 从本地 Book 转换。需要分组名(用 ID 查表得到)。
  static SyncBook fromBook(Book b, {String? groupName}) => SyncBook(
    id: b.id,
    title: b.title,
    entryUrl: b.entryUrl,
    scopePrefix: b.scopePrefix,
    sortIndex: b.sortIndex,
    createdAt: b.createdAt,
    updatedAt: b.updatedAt,
    groupName: groupName,
    iconUrl: b.iconUrl,
    deletedAt: b.deletedAt,
  );

  Book toBook({String? groupId}) => Book(
    id: id,
    title: title,
    entryUrl: entryUrl,
    scopePrefix: scopePrefix,
    groupId: groupId,
    sortIndex: sortIndex,
    createdAt: createdAt,
    updatedAt: updatedAt,
    iconUrl: iconUrl,
    deletedAt: deletedAt,
  );
}

/// 同步时传输的一条进度。
class SyncProgress {
  const SyncProgress({
    required this.bookId,
    required this.url,
    required this.updatedAt,
    this.pageTitle = '',
    this.pageHash,
    this.anchor,
    this.deviceId = '',
  });

  final String bookId;
  final String url;
  final DateTime updatedAt;
  final String pageTitle;
  final String? pageHash;
  final Anchor? anchor;
  final String deviceId;

  Map<String, Object?> toJson() => {
    'bookId': bookId,
    'url': url,
    'updatedAt': updatedAt.millisecondsSinceEpoch,
    if (pageTitle.isNotEmpty) 'pageTitle': pageTitle,
    if (pageHash != null) 'pageHash': pageHash,
    if (anchor != null) 'anchor': anchor!.toJson(),
    if (deviceId.isNotEmpty) 'deviceId': deviceId,
  };

  static SyncProgress? fromJson(Map<String, dynamic> j) {
    final bookId = j['bookId'] as String?;
    final url = j['url'] as String?;
    if (bookId == null || bookId.isEmpty) return null;
    if (url == null || url.isEmpty) return null;
    final anchorJson = j['anchor'];
    return SyncProgress(
      bookId: bookId,
      url: url,
      updatedAt: _date(j['updatedAt']) ?? DateTime.now(),
      pageTitle: j['pageTitle'] as String? ?? '',
      pageHash: j['pageHash'] as String?,
      anchor: anchorJson is Map<String, dynamic>
          ? Anchor.fromJson(anchorJson)
          : null,
      deviceId: j['deviceId'] as String? ?? '',
    );
  }

  static SyncProgress fromSnapshot(ProgressSnapshot s) => SyncProgress(
    bookId: s.bookId,
    url: s.url,
    updatedAt: s.updatedAt,
    pageTitle: s.pageTitle,
    pageHash: s.pageHash,
    anchor: s.anchor,
    deviceId: s.deviceId,
  );

  ProgressSnapshot toSnapshot({String? deviceId}) => ProgressSnapshot(
    bookId: bookId,
    url: url,
    pageTitle: pageTitle,
    pageHash: pageHash,
    anchor: anchor,
    updatedAt: updatedAt,
    deviceId: deviceId ?? this.deviceId,
  );
}

/// 一次同步的完整载荷。
/// 同步载荷里的分组。
///
/// 之前只靠书本的 groupName 反推分组,导致:
///   * 空分组传不过去
///   * 分组改名传不过去(名字就是身份)
///   * 分组排序传不过去
///
/// 现在把分组作为独立条目传,和书一样按名字对齐。
class SyncGroup {
  const SyncGroup({
    required this.name,
    required this.sortIndex,
    required this.updatedAt,
  });

  final String name;
  final int sortIndex;
  final DateTime updatedAt;

  Map<String, Object?> toJson() => {
    'name': name,
    'sortIndex': sortIndex,
    'updatedAt': updatedAt.millisecondsSinceEpoch,
  };

  static SyncGroup? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final name = raw['name'];
    if (name is! String || name.trim().isEmpty) return null;
    final t = raw['updatedAt'];
    return SyncGroup(
      name: name,
      sortIndex: raw['sortIndex'] is int ? raw['sortIndex'] as int : 0,
      updatedAt: t is int
          ? DateTime.fromMillisecondsSinceEpoch(t)
          : DateTime.now(),
    );
  }
}

class SyncPayload {
  const SyncPayload({
    required this.books,
    required this.progress,
    this.groups = const [],
  });

  const SyncPayload.empty()
      : books = const [],
        progress = const [],
        groups = const [];

  final List<SyncBook> books;
  final List<SyncProgress> progress;

  /// 分组清单。空表示对端还没开始传分组(老版本)。
  final List<SyncGroup> groups;

  Map<String, Object?> toJson() => {
    'version': protocolVersion,
    'books': books.map((b) => b.toJson()).toList(),
    'progress': progress.map((p) => p.toJson()).toList(),
    'groups': groups.map((g) => g.toJson()).toList(),
  };

  String encode() => jsonEncode(toJson());

  static SyncPayload decode(String raw) {
    final j = jsonDecode(raw);
    if (j is! Map<String, dynamic>) {
      throw const FormatException('同步数据格式不对');
    }
    return SyncPayload(
      books: (j['books'] as List? ?? [])
          .whereType<Map<String, dynamic>>()
          .map(SyncBook.fromJson)
          .whereType<SyncBook>()
          .toList(),
      groups: (j['groups'] as List? ?? [])
          .map(SyncGroup.fromJson)
          .whereType<SyncGroup>()
          .toList(),
      progress: (j['progress'] as List? ?? [])
          .whereType<Map<String, dynamic>>()
          .map(SyncProgress.fromJson)
          .whereType<SyncProgress>()
          .toList(),
    );
  }

  /// 协议版本。将来加字段时跟着加,旧版本可以据此拒绝或降级。
  static const protocolVersion = 1;
}

/// 合并结果:告诉用户这次同步改动了什么。
class SyncResult {
  const SyncResult({
    this.booksAdded = 0,
    this.booksUpdated = 0,
    this.booksRemoved = 0,
    this.progressUpdated = 0,
    this.progressKept = 0,
  });

  final int booksAdded;
  final int booksUpdated;

  /// 镜像同步时被删掉的书(权威端没有它)。
  final int booksRemoved;

  final int progressUpdated;

  /// 本地更新、未采用对端记录的数量(对端更旧)。
  final int progressKept;

  bool get changedAnything =>
      booksAdded > 0 ||
      booksUpdated > 0 ||
      booksRemoved > 0 ||
      progressUpdated > 0;

  String describe() {
    if (!changedAnything) return '两端已经一致';
    final parts = <String>[];
    if (booksAdded > 0) parts.add('新增 $booksAdded 本书');
    if (booksUpdated > 0) parts.add('更新 $booksUpdated 本书');
    if (booksRemoved > 0) parts.add('删除 $booksRemoved 本书');
    if (progressUpdated > 0) parts.add('更新 $progressUpdated 条进度');
    return parts.join('，');
  }
}

DateTime? _date(Object? v) {
  if (v is num) {
    return DateTime.fromMillisecondsSinceEpoch(v.toInt());
  }
  if (v is String) {
    final n = int.tryParse(v);
    if (n != null) return DateTime.fromMillisecondsSinceEpoch(n);
    return DateTime.tryParse(v);
  }
  return null;
}

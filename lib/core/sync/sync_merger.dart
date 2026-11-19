import '../domain/models.dart';
import '../ports/ports.dart';
import 'sync_protocol.dart';

/// 把对端数据合并进本地。
///
/// 冲突策略(已定):**按 updatedAt 取新**。
/// 同一本书/同一条进度,谁的时间戳更晚就用谁。
///
/// 为什么不用"取进度更靠后的":
/// 用户可能在另一台设备上故意往回翻到前面重读,
/// 那个位置时间戳更新、但 docRatio 更小 —— 按位置比较会把它判成"更旧",
/// 反而把用户刚读的位置丢掉。
///
/// 时间戳保护:两端的时钟可能不同步。合并时保留双方原始的
/// updatedAt,不做"取 max(now, ...)"这种本地化改写,
/// 否则每同步一次时间就往前跳一次。
class SyncMerger {
  const SyncMerger(this.store);

  final LibraryStore store;

  /// 把 [incoming] 合并进本地,返回改动统计。
  Future<SyncResult> merge(SyncPayload incoming) async {
    var booksAdded = 0;
    var booksUpdated = 0;
    var progressUpdated = 0;
    var progressKept = 0;

    // ---------------- 分组 ----------------
    //
    // 按名字匹配:两端的分组 ID 是各自本地生成的,不可能一致。
    // 对端有、本地没有的分组就新建。
    final localGroups = await store.loadGroups();
    final groupIdByName = {for (final g in localGroups) g.name: g.id};
    for (final sb in incoming.books) {
      final name = sb.groupName;
      if (name == null || name.isEmpty) continue;
      if (groupIdByName.containsKey(name)) continue;
      final now = DateTime.now();
      final group = BookGroup(
        id: 'g-sync-${now.microsecondsSinceEpoch}-${name.hashCode}',
        name: name,
        sortIndex: localGroups.length + groupIdByName.length,
        updatedAt: now,
      );
      await store.upsertGroup(group);
      groupIdByName[name] = group.id;
    }

    // ---------------- 书 ----------------
    //
    // 这里必须用 loadBooksIncludingDeleted:本地已删的书也在表里,
    // 才能正确判断"对端的墓碑是不是比我新"。
    // 用 loadBooks 会把本地墓碑藏起来,导致对端的删除每次都当成"新增"
    // 重新插回来 —— 用户删了书,同步后又出现。
    final localBooks = await store.loadBooksIncludingDeleted();
    final bookById = {for (final b in localBooks) b.id: b};

    for (final sb in incoming.books) {
      final existing = bookById[sb.id];

      // 对端传来墓碑:说明对端删了这本书。
      if (sb.deletedAt != null) {
        if (existing == null) {
          // 本地没有这本书,但既然对端删了,就没必要新建。
          // 记一个空墓碑成本很低,而且能防止它以后被别处推回来。
          await store.upsertBook(
            sb.toBook(groupId: groupIdByName[sb.groupName]),
          );
          await store.deleteProgressOf(sb.id);
          continue;
        }
        // 本地也有:谁删得晚听谁的。
        // 若本地这本书还活着(existing.deletedAt == null),
        // 用对端的删除时间覆盖 —— 删除是显式动作,应该赢过"没动过"。
        final localDeletedAt = existing.deletedAt;
        final remoteDeletedAt = sb.deletedAt!;
        final shouldDelete =
            localDeletedAt == null || remoteDeletedAt.isAfter(localDeletedAt);
        if (shouldDelete) {
          await store.upsertBook(
            sb.toBook(groupId: existing.groupId),
          );
          await store.deleteProgressOf(sb.id);
          booksUpdated++;
        }
        continue;
      }

      // 对端这本书是活的。
      if (existing == null) {
        await store.upsertBook(
          sb.toBook(groupId: groupIdByName[sb.groupName]),
        );
        booksAdded++;
        continue;
      }

      // 本地已删、对端还活着:谁更晚听谁的。
      //
      // 若本地删除时间晚于对端的 updatedAt,说明删除是更新的动作,
      // 不能因为对端还有这本书就把它复活。
      if (existing.deletedAt != null) {
        if (!sb.updatedAt.isAfter(existing.deletedAt!)) continue;
        // 对端确实在那之后又动过这本书 —— 当作显式恢复。
      }

      // 只有对端更新才覆盖。时间相同视为无变化,不重复写。
      if (!sb.updatedAt.isAfter(existing.updatedAt)) continue;
      await store.upsertBook(
        sb.toBook(
          groupId: groupIdByName[sb.groupName] ?? existing.groupId,
        ),
      );
      booksUpdated++;
    }

    // ---------------- 墓碑清理 ----------------
    //
    // 本地有墓碑、对端完全没有这本书的记录:
    // 保持删除,不做任何事(这正是"一端删了"的正常情况)。
    // 不主动删墓碑 —— 它是防止书被推回来的依据。

    // ---------------- 进度 ----------------
    //
    // 主键是 (bookId, url) —— 同一本书的不同页面各记一条。
    // 对端可能传来本地没有的页面进度,直接插入。
    for (final sp in incoming.progress) {
      final local = await _findProgress(sp.bookId, sp.url);
      if (local == null) {
        await store.saveProgress(sp.toSnapshot());
        progressUpdated++;
        continue;
      }
      if (sp.updatedAt.isAfter(local.updatedAt)) {
        await store.saveProgress(sp.toSnapshot());
        progressUpdated++;
      } else {
        progressKept++;
      }
    }

    return SyncResult(
      booksAdded: booksAdded,
      booksUpdated: booksUpdated,
      progressUpdated: progressUpdated,
      progressKept: progressKept,
    );
  }

  /// 找本地某本书某个 URL 的进度。
  ///
  /// LibraryStore 只有 latestProgress(按 bookId),
  /// 所以这里做一次过滤。数据量很小(一本书几十条),
  /// 不值得为它改接口。
  Future<ProgressSnapshot?> _findProgress(
    String bookId,
    String url,
  ) async {
    final recent = await store.recentProgress(limit: 500);
    for (final s in recent) {
      if (s.bookId == bookId && s.url == url) return s;
    }
    // 退一步:只看这本书最新的一条,URL 不同也视为同一本。
    return store.latestProgress(bookId);
  }

  /// 导出本地数据,准备发给对端。
  ///
  /// **包含已删除的书(墓碑)**。
  ///
  /// 这一点很关键:如果只导出活着的书,删除动作永远传不到另一端 ——
  /// 用户在一台机器上删了书,另一台上它还在,再同步还会被推回来。
  ///
  /// 删除的传播靠墓碑的 `deletedAt` 时间戳:
  /// 对端拿到后比较谁更新,新的赢。
  Future<SyncPayload> export() async {
    final books = await store.loadBooksIncludingDeleted();
    final groups = await store.loadGroups();
    final groupNameById = {for (final g in groups) g.id: g.name};

    // 已删的书不再带进度 —— 进度在删除时已被清掉,
    // 这里再传一遍会让对端凭空重建出该书的进度。
    final deletedIds = books
        .where((b) => b.deletedAt != null)
        .map((b) => b.id)
        .toSet();

    final progress = <SyncProgress>[];
    // 每本书只带最新一条 —— 同步是"接上进度",
    // 不需要传全部历史(那会让载荷膨胀,而且旧记录本来也会被覆盖)。
    final latest = await store.latestProgressByBook();
    for (final entry in latest.entries) {
      if (deletedIds.contains(entry.key)) continue;
      progress.add(SyncProgress.fromSnapshot(entry.value));
    }

    return SyncPayload(
      books: books
          .map(
            (b) => SyncBook.fromBook(
              b,
              groupName: groupNameById[b.groupId],
            ),
          )
          .toList(),
      progress: progress,
    );
  }
}

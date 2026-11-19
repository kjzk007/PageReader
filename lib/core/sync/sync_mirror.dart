import '../domain/models.dart';
import '../ports/ports.dart';
import 'sync_protocol.dart';

/// 镜像同步:让两端的书架**完全一致**。
///
/// ── 与 SyncMerger 的区别 ──
///
/// `SyncMerger` 是"合并":两边各留各的,取并集 + 逐项时间戳仲裁。
/// `SyncMirror` 是"对齐":先算出一份权威清单,再把本地改写成它的样子。
///
/// ── 谁是权威?按操作时间 ──
///
/// 不偏向任何一端。逐项比较 `updatedAt`:
///   * 这本书对端更新 → 用对端的(内容、分组、排序都跟它)
///   * 本地更新 → 保留本地的
///   * 本地没有 → 从对端加进来
///   * 对端没有、本地有:
///       - 本地更新时间晚于"对端最后一次书架操作" → 保留(对端还没见过它)
///       - 否则认为对端删了它 → 本地也删
///
/// 这样"在手机上删了一本"和"在桌面上删了一本"效果一样:
/// 谁删得更晚,另一端就跟着删。
///
/// ── 删除的判定 ──
///
/// 对端传墓碑过来是最明确的删除信号,直接用它的时间戳比。
/// 对端**没有**某本书(不是墓碑,而是压根不在清单里)时,
/// 需要区分两种情况:
///   1. 对端删了它 → 本地也该删
///   2. 本地刚加的、对端还没同步过 → 本地该保留
/// 判据是本地这本书的 updatedAt 是否晚于对端清单的"最新书架变更时间"。
class SyncMirror {
  const SyncMirror(this.store);

  final LibraryStore store;

  /// 导出本地数据,作为对端对齐的依据。
  ///
  /// **包含墓碑**:删除必须能被对端看见,否则"删了又回来"。
  /// **包含分组**:之前没带分组,导致空分组、分组改名、分组排序
  /// 都传不过去 —— 用户看到的就是"书同步了但分类没同步"。
  Future<SyncPayload> export() async {
    final books = await store.loadBooksIncludingDeleted();
    final groups = await store.loadGroups();
    final groupNameById = {for (final g in groups) g.id: g.name};

    final deletedIds = books
        .where((b) => b.deletedAt != null)
        .map((b) => b.id)
        .toSet();

    final latest = await store.latestProgressByBook();
    final progress = <SyncProgress>[];
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
      groups: groups
          .map(
            (g) => SyncGroup(
              name: g.name,
              sortIndex: g.sortIndex,
              updatedAt: g.updatedAt,
            ),
          )
          .toList(),
    );
  }

  /// 把对端数据与本地对齐。
  ///
  /// 返回本地视角的改动统计。
  Future<SyncResult> merge(SyncPayload incoming) async {
    var added = 0;
    var updated = 0;
    var removed = 0;
    var progressUpdated = 0;

    // ---------------- 分组 ----------------
    //
    // 分组按**名字**对齐(两端 ID 不同,名字才是身份)。
    //
    // 数据来源有两个,合并处理:
    //   1. 载荷里的 `groups` —— 权威清单(含空分组、排序、改名)
    //   2. 书本的 `groupName` —— 兼容老版本载荷(那时没有 groups 字段)
    //
    // 之前只用第 2 个,导致空分组传不过来、分组排序也不一致 ——
    // 用户看到的就是"书同步了但分类没同步"。
    final localGroups = await store.loadGroups();
    final groupIdByName = {for (final g in localGroups) g.name: g.id};

    // 权威端的分组名 → 排序。先用载荷里的 groups,再用书本补。
    final wantedGroups = <String, int>{};
    for (final sg in incoming.groups) {
      wantedGroups[sg.name] = sg.sortIndex;
    }
    for (final sb in incoming.books) {
      if (sb.deletedAt != null) continue;
      final n = sb.groupName;
      if (n == null || n.isEmpty) continue;
      wantedGroups.putIfAbsent(n, () => wantedGroups.length);
    }

    // 建缺失的分组
    for (final entry in wantedGroups.entries) {
      final name = entry.key;
      if (groupIdByName.containsKey(name)) {
        // 已存在:按权威端的排序更新(分组顺序也要同步)
        final existing = localGroups.firstWhere((g) => g.name == name);
        if (existing.sortIndex != entry.value) {
          await store.upsertGroup(
            BookGroup(
              id: existing.id,
              name: existing.name,
              sortIndex: entry.value,
              updatedAt: DateTime.now(),
            ),
          );
        }
        continue;
      }
      final now = DateTime.now();
      final g = BookGroup(
        id: 'g-mirror-${now.microsecondsSinceEpoch}-${name.hashCode}',
        name: name,
        sortIndex: entry.value,
        updatedAt: now,
      );
      await store.upsertGroup(g);
      groupIdByName[name] = g.id;
    }

    // 解散本地多出来的分组(只解散,不删书)
    final localBooksForGroup = await store.loadBooks();
    for (final g in localGroups) {
      if (wantedGroups.containsKey(g.name)) continue;
      // 该分组下还有书就不解散 —— 那些书是本地更新的,分组要留着。
      if (localBooksForGroup.any((b) => b.groupId == g.id)) continue;
      await store.deleteGroup(g.id);
    }

    // ---------------- 书 ----------------
    final localAll = await store.loadBooksIncludingDeleted();
    final localById = {for (final b in localAll) b.id: b};

    // 对端清单里"最新的一次书架变更"时间。
    //
    // 用途:判断"对端没有这本书"是"删了"还是"还没见过"。
    // 取所有条目的 updatedAt / deletedAt 最大值。
    DateTime? remoteLatestChange;
    for (final sb in incoming.books) {
      final t = sb.deletedAt != null && sb.deletedAt!.isAfter(sb.updatedAt)
          ? sb.deletedAt!
          : sb.updatedAt;
      if (remoteLatestChange == null || t.isAfter(remoteLatestChange)) {
        remoteLatestChange = t;
      }
    }

    final remoteIds = <String>{};

    for (final sb in incoming.books) {
      remoteIds.add(sb.id);
      final existing = localById[sb.id];

      // 对端是墓碑
      if (sb.deletedAt != null) {
        final remoteDel = sb.deletedAt!;
        if (existing == null) {
          // 本地没有:记个墓碑,防止它以后被别处推回来
          await store.upsertBook(
            sb.toBook(groupId: groupIdByName[sb.groupName]),
          );
          await store.deleteProgressOf(sb.id);
          continue;
        }
        if (existing.deletedAt != null) {
          // 两边都删了,保留更晚的时间
          if (remoteDel.isAfter(existing.deletedAt!)) {
            await store.upsertBook(sb.toBook(groupId: existing.groupId));
            await store.deleteProgressOf(sb.id);
          }
          continue;
        }
        // 本地活着、对端删了:比时间。
        // 本地若在那之后有更新(用户改过名、读过),说明本地动作更晚,不删。
        if (existing.updatedAt.isAfter(remoteDel)) continue;
        await store.upsertBook(
          Book(
            id: existing.id,
            title: existing.title,
            entryUrl: existing.entryUrl,
            scopePrefix: existing.scopePrefix,
            groupId: existing.groupId,
            sortIndex: existing.sortIndex,
            createdAt: existing.createdAt,
            updatedAt: remoteDel,
            iconUrl: existing.iconUrl,
            themeColor: existing.themeColor,
            deletedAt: remoteDel,
          ),
        );
        await store.deleteProgressOf(sb.id);
        removed++;
        continue;
      }

      // 对端活着
      final targetGroupId = groupIdByName[sb.groupName];

      if (existing == null) {
        await store.upsertBook(sb.toBook(groupId: targetGroupId));
        added++;
        continue;
      }

      // 本地是墓碑、对端活着
      if (existing.deletedAt != null) {
        // 本地删得比对端最后一次更新晚 → 删除是更新的动作,不复活
        if (existing.deletedAt!.isAfter(sb.updatedAt)) continue;
        // 对端更新更晚 → 当作恢复
        await store.upsertBook(
          Book(
            id: sb.id,
            title: sb.title,
            entryUrl: sb.entryUrl,
            scopePrefix: sb.scopePrefix,
            groupId: targetGroupId,
            sortIndex: sb.sortIndex,
            createdAt: existing.createdAt,
            updatedAt: sb.updatedAt,
            iconUrl: sb.iconUrl ?? existing.iconUrl,
            themeColor: existing.themeColor,
            deletedAt: null,
          ),
        );
        updated++;
        continue;
      }

      // 两边都活着:谁更新用谁
      if (!sb.updatedAt.isAfter(existing.updatedAt)) continue;
      await store.upsertBook(
        sb.toBook(groupId: targetGroupId ?? existing.groupId),
      );
      updated++;
    }

    // ---------------- 对端清单里没有的书 ----------------
    //
    // 这里是最难的部分:对端清单里没有某本书,可能是
    //   1. 对端把它删了 → 本地也该删
    //   2. 本地刚加的,对端还没同步过 → 本地保留
    //
    // 仅凭"对端清单里没有"无法区分。用**上次同步快照**判定:
    //   * 快照里有这本书、本地现在也有 → 说明上次同步时两端都有,
    //     现在对端没有了 → 对端删了 → 本地删
    //   * 快照里没有这本书 → 它是上次同步后才加的,
    //     对端还没见过 → 保留
    //
    // 快照为空(首次同步或老库升级)时保守处理:保留本地书。
    // 宁可多留,也不要误删用户的书。
    final snapshot = await store.loadSyncSnapshot();

    for (final b in localAll) {
      if (remoteIds.contains(b.id)) continue;
      if (b.deletedAt != null) continue; // 已经是墓碑

      // 快照里没有 → 上次同步之后才加的,对端还没见过,保留
      if (!snapshot.contains(b.id)) continue;

      // 快照里有,说明上次同步时两端都有;现在对端没有 = 对端删了
      await store.deleteBook(b.id);
      removed++;
    }

    // ---------------- 进度 ----------------
    //
    // 逐条按时间戳取新。
    for (final sp in incoming.progress) {
      final local = await store.latestProgress(sp.bookId);
      if (local == null) {
        await store.saveProgress(sp.toSnapshot());
        progressUpdated++;
        continue;
      }
      if (sp.updatedAt.isAfter(local.updatedAt)) {
        await store.saveProgress(sp.toSnapshot());
        progressUpdated++;
      }
    }

    return SyncResult(
      booksAdded: added,
      booksUpdated: updated,
      booksRemoved: removed,
      progressUpdated: progressUpdated,
    );
  }
}

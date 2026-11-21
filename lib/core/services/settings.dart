import 'dart:convert';
import '../domain/theme_preset.dart';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';


/// 应用设置的持久化。
///
/// 只存极少量键值,用最简单的实现:一个 JSON 文件。
/// 为什么不上 shared_preferences:
///   * 桌面端它依赖额外的平台实现,而本项目已经自己管理数据目录;
///   * 键值少、结构简单,自己写反而更可控,也便于同步功能将来复用。
class SettingsStore {
  SettingsStore(this._file);

  final File _file;
  Map<String, dynamic> _cache = {};
  bool _loaded = false;

  /// 打开设置文件。
  ///
  /// [dir] 为空时用默认数据目录(桌面 AppData / 手机应用私有目录),
  /// 也认 `PAGEREADER_DATA_DIR` 环境变量(验收脚本的沙箱隔离)。
  /// 测试传 [dir] 指到临时目录,避免碰用户真实配置。
  static Future<SettingsStore> open({Directory? dir}) async {
    // 与数据库同一个目录,便于整体备份/迁移。
    final override = Platform.environment['PAGEREADER_DATA_DIR'];
    final target = dir ??
        (override != null && override.trim().isNotEmpty
            ? Directory(override.trim())
            : await getApplicationSupportDirectory());
    if (!target.existsSync()) target.createSync(recursive: true);
    final store = SettingsStore(File(p.join(target.path, 'settings.json')));
    await store._load();
    return store;
  }

  Future<void> _load() async {
    if (_loaded) return;
    _loaded = true;
    try {
      if (!_file.existsSync()) return;
      final raw = await _file.readAsString();
      if (raw.trim().isEmpty) return;
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) _cache = decoded;
    } catch (_) {
      // 配置文件损坏不该影响启动,按默认值走。
      _cache = {};
    }
  }

  String readString(String key, [String fallback = '']) {
    final v = _cache[key];
    return v is String ? v : fallback;
  }

  bool readBool(String key, [bool fallback = false]) {
    final v = _cache[key];
    return v is bool ? v : fallback;
  }

  /// 读字符串列表。用于"启用的插件 ID"这类集合。
  List<String> readStringList(String key) {
    final v = _cache[key];
    if (v is! List) return const [];
    return v.whereType<String>().toList();
  }

  Future<void> writeString(String key, String value) async {
    _cache[key] = value;
    await _flush();
  }

  Future<void> writeBool(String key, bool value) async {
    _cache[key] = value;
    await _flush();
  }

  Future<void> writeStringList(String key, List<String> value) async {
    _cache[key] = value;
    await _flush();
  }

  Future<void> _flush() async {
    try {
      await _file.writeAsString(jsonEncode(_cache));
    } catch (_) {
      // 写失败就算了,设置在内存里仍然生效,下次改再试。
    }
  }
}

/// 主题模式:跟随系统 / 强制浅色 / 强制深色。
///
/// 为什么需要显式覆盖:
/// 阅读器深色更护眼,但用户的系统可能是浅色 ——
/// "app 用什么配色"与"系统偏好"是两件独立的事。
/// 这个值同时决定 WebView 报告给站点的 prefers-color-scheme。
class ThemeModeNotifier extends Notifier<ThemeMode> {
  @override
  ThemeMode build() {
    final store = ref.watch(settingsStoreProvider);
    return store == null
        ? ThemeMode.system
        : _decode(store.readString('themeMode', 'system'));
  }

  /// 从存储里解出主题模式,供 main() 在启动时使用。
  static ThemeMode decodeStored(SettingsStore store) =>
      _decode(store.readString('themeMode', 'system'));

  static ThemeMode _decode(String v) {
    switch (v) {
      case 'light':
        return ThemeMode.light;
      case 'dark':
        return ThemeMode.dark;
      default:
        return ThemeMode.system;
    }
  }

  static String _encode(ThemeMode m) {
    switch (m) {
      case ThemeMode.light:
        return 'light';
      case ThemeMode.dark:
        return 'dark';
      case ThemeMode.system:
        return 'system';
    }
  }

  Future<void> set(ThemeMode mode) async {
    state = mode;
    // 只改 app 自己的配色。
    //
    // 网页的深浅色跟随在 Android 上做不到 —— 详见 TODO.md 的
    // 「Android 端深色跟随：做不到」。站点是否变深取决于
    // 它自己是否响应 prefers-color-scheme，而 Android WebView
    // 没有引擎级的媒体查询覆盖 API。
    await ref.read(settingsStoreProvider)?.writeString(
      'themeMode',
      _encode(mode),
    );
  }
}

/// 设置存储:启动时加载一次,之后各处复用。
final settingsStoreProvider = Provider<SettingsStore?>((ref) => null);

/// 主题模式。
final themeModeProvider = NotifierProvider<ThemeModeNotifier, ThemeMode>(
  ThemeModeNotifier.new,
);


/// 用户勾选启用的浏览器插件。
///
/// ── 为什么让用户选，而不是全加载 ──
///
/// 用户装了 20 个插件，不代表希望阅读窗口里全跑起来:
/// 有些会注入浮窗、有些会改页面样式、有些纯粹是别处用的。
/// 全加载既慢又干扰阅读。所以首次启动时列出清单让用户勾，
/// 之后在设置里随时调整。
class ExtensionSettings {
  const ExtensionSettings({
    required this.enabledIds,
    this.asked = false,
    this.seenIds = const {},
  });

  /// 已启用的插件 ID。
  final Set<String> enabledIds;

  /// 是否已经问过用户要启用哪些插件。
  ///
  /// ── 为什么需要这个标记 ──
  ///
  /// 插件默认一个都不启用。新用户装完直接打开书，一个插件都加载不上，
  /// 而设置页里那个插件区块他又未必会注意到。所以要在他第一次打开书
  /// 之前主动问一次：列出本机插件让他勾。
  ///
  /// 问过之后就不再打扰 —— 哪怕他一个都没勾，那也是他的选择。
  final bool asked;

  /// 上次在设置里见过的插件 ID 集合。
  ///
  /// 用户可能在浏览器里新装插件，而 `asked` 只问一次 —— 之后收不到
  /// 任何提示，得自己想起去设置页翻。存下见过的集合就能比对出新增项，
  /// 在设置入口标个小提示。
  final Set<String> seenIds;

  /// 相对 [seenIds] 新增的插件 ID。
  ///
  /// [current] 是当前探查到的全部插件 ID。空列表表示没有新增。
  List<String> newIdsAgainst(Set<String> current) {
    if (seenIds.isEmpty) return const [];
    return current.where((id) => !seenIds.contains(id)).toList()..sort();
  }

  bool isEnabled(String id) => enabledIds.contains(id);

  ExtensionSettings copyWith({
    Set<String>? enabledIds,
    bool? asked,
    Set<String>? seenIds,
  }) => ExtensionSettings(
    enabledIds: enabledIds ?? this.enabledIds,
    asked: asked ?? this.asked,
    seenIds: seenIds ?? this.seenIds,
  );
}

class ExtensionSettingsNotifier extends Notifier<ExtensionSettings> {
  @override
  ExtensionSettings build() {
    final store = ref.read(settingsStoreProvider);
    if (store == null) {
      return const ExtensionSettings(enabledIds: {});
    }
    final raw = store.readStringList('extensions.enabled');
    final asked = store.readString('extensions.asked') == '1';
    final seen = store.readStringList('extensions.seen');
    return ExtensionSettings(
      enabledIds: raw.toSet(),
      asked: asked,
      seenIds: seen.toSet(),
    );
  }

  Future<void> setEnabled(Set<String> ids) async {
    state = state.copyWith(enabledIds: ids);
    await ref
        .read(settingsStoreProvider)
        ?.writeStringList('extensions.enabled', ids.toList()..sort());
  }

  /// 标记「已经问过用户」，之后不再弹引导。
  Future<void> markAsked() async {
    state = state.copyWith(asked: true);
    await ref.read(settingsStoreProvider)?.writeString('extensions.asked', '1');
  }

  /// 记下「这次见过哪些插件」，供下次比对新增。
  ///
  /// 只在用户真的打开过设置页时调 —— 否则等于把没看到的东西
  /// 标记成「已见过」，红点永远不会出现。
  Future<void> markSeen(Set<String> ids) async {
    state = state.copyWith(seenIds: ids);
    await ref
        .read(settingsStoreProvider)
        ?.writeStringList('extensions.seen', ids.toList()..sort());
  }

  Future<void> toggle(String id, bool enabled) async {
    final next = Set<String>.from(state.enabledIds);
    if (enabled) {
      next.add(id);
    } else {
      next.remove(id);
    }
    await setEnabled(next);
  }
}
final extensionSettingsProvider =
    NotifierProvider<ExtensionSettingsNotifier, ExtensionSettings>(
      ExtensionSettingsNotifier.new,
    );


/// 深色注入预设的集合。
///
/// 存法：整个列表序列化成一个字符串键，避免给 SettingsStore 加一堆
/// 针对单个预设的读写方法。
///
/// 内置预设「深色模式」始终存在，用户删不掉；其余由用户自建。
class ThemePresetsNotifier extends Notifier<List<ThemePreset>> {
  static const _key = 'dark.presets';

  @override
  List<ThemePreset> build() {
    final store = ref.read(settingsStoreProvider);
    if (store == null) return const [ThemePreset.builtinDark];
    final raw = store.readString(_key);
    if (raw.trim().isEmpty) return const [ThemePreset.builtinDark];
    try {
      final list = jsonDecode(raw);
      if (list is! List) return const [ThemePreset.builtinDark];
      final presets = list
          .whereType<Map<String, dynamic>>()
          .map(ThemePreset.fromJson)
          .toList();
      // 内置的不能被删掉，缺了就补回来（比如手工编辑坏了配置）。
      if (!presets.any((p) => p.id == ThemePreset.builtinDark.id)) {
        presets.insert(0, ThemePreset.builtinDark);
      }
      return presets;
    } catch (_) {
      return const [ThemePreset.builtinDark];
    }
  }

  /// 找预设；找不到返回 null（书绑定了一个已删除的预设时）。
  ThemePreset? byId(String? id) {
    if (id == null || id.isEmpty) return null;
    for (final p in state) {
      if (p.id == id) return p;
    }
    return null;
  }

  Future<void> _persist(List<ThemePreset> next) async {
    state = next;
    await ref
        .read(settingsStoreProvider)
        ?.writeString(_key, jsonEncode(next.map((p) => p.toJson()).toList()));
  }

  Future<void> upsert(ThemePreset preset) async {
    final next = [...state];
    final i = next.indexWhere((p) => p.id == preset.id);
    if (i >= 0) {
      next[i] = preset;
    } else {
      next.add(preset);
    }
    await _persist(next);
  }

  Future<void> remove(String id) async {
    if (id == ThemePreset.builtinDark.id) return; // 内置不删
    await _persist(state.where((p) => p.id != id).toList());
  }

  /// 新建一个预设，返回它（调用方拿 id 去绑定书）。
  Future<ThemePreset> create(String name) async {
    final p = ThemePreset(
      id: 'preset-${DateTime.now().millisecondsSinceEpoch}',
      name: name.trim().isEmpty ? '未命名预设' : name.trim(),
    );
    await upsert(p);
    return p;
  }
}

final themePresetsProvider =
    NotifierProvider<ThemePresetsNotifier, List<ThemePreset>>(
      ThemePresetsNotifier.new,
    );

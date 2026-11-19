import 'dart:convert';

import '../services/settings.dart';

/// 一台已配对的设备。
///
/// ── 为什么要持久化 ──
///
/// 手机端拿到 token 后会长期保存(`sync.token`)。如果桌面端每次重启
/// 都换一批 token,手机上存的就全部失效 —— 用户每次开电脑都要重新扫码。
///
/// 所以 token 必须落盘,并且能在界面上看到"哪些设备配对过、什么时候配的",
/// 让用户能主动断开某一台。
class PairedDevice {
  const PairedDevice({
    required this.token,
    required this.name,
    required this.pairedAt,
    this.lastSeenAt,
  });

  /// 这台设备的凭证。手机端保存的就是它。
  final String token;

  /// 展示名。来自配对时手机上报的型号。
  final String name;

  final DateTime pairedAt;

  /// 最后一次成功通信的时间。空表示配对后没再同步过。
  final DateTime? lastSeenAt;

  PairedDevice copyWith({String? name, DateTime? lastSeenAt}) => PairedDevice(
    token: token,
    name: name ?? this.name,
    pairedAt: pairedAt,
    lastSeenAt: lastSeenAt ?? this.lastSeenAt,
  );

  Map<String, Object?> toJson() => {
    'token': token,
    'name': name,
    'pairedAt': pairedAt.millisecondsSinceEpoch,
    'lastSeenAt': lastSeenAt?.millisecondsSinceEpoch,
  };

  static PairedDevice? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final token = raw['token'];
    if (token is! String || token.isEmpty) return null;
    final paired = raw['pairedAt'];
    final seen = raw['lastSeenAt'];
    return PairedDevice(
      token: token,
      name: raw['name'] is String ? raw['name'] as String : '未知设备',
      pairedAt: paired is int
          ? DateTime.fromMillisecondsSinceEpoch(paired)
          : DateTime.now(),
      lastSeenAt: seen is int
          ? DateTime.fromMillisecondsSinceEpoch(seen)
          : null,
    );
  }
}

/// 已配对设备的清单,存在 settings.json 里。
///
/// 用设置存储而不是数据库:这是一份很小的配置(通常 1~3 条),
/// 而且要在服务启动时立刻读到 —— 走数据库要多一次异步初始化。
class PairedDeviceStore {
  const PairedDeviceStore(this._settings);

  final SettingsStore _settings;

  static const _key = 'sync.pairedDevices';

  List<PairedDevice> load() {
    final raw = _settings.readString(_key, '');
    if (raw.isEmpty) return const [];
    try {
      final list = jsonDecode(raw);
      if (list is! List) return const [];
      return list
          .map(PairedDevice.fromJson)
          .whereType<PairedDevice>()
          .toList();
    } catch (_) {
      return const [];
    }
  }

  Future<void> save(List<PairedDevice> devices) async {
    await _settings.writeString(
      _key,
      jsonEncode(devices.map((d) => d.toJson()).toList()),
    );
  }

  Future<void> add(PairedDevice device) async {
    final all = load().where((d) => d.token != device.token).toList()
      ..add(device);
    await save(all);
  }

  /// 断开一台设备:从清单里移除,它的 token 立即失效。
  Future<void> remove(String token) async {
    final all = load().where((d) => d.token != token).toList();
    await save(all);
  }

  /// 记录一次通信。用于显示"最近活跃"。
  Future<void> touch(String token, {String? name}) async {
    final all = load();
    final i = all.indexWhere((d) => d.token == token);
    if (i < 0) return;
    all[i] = all[i].copyWith(name: name, lastSeenAt: DateTime.now());
    await save(all);
  }

  bool contains(String token) => load().any((d) => d.token == token);
}

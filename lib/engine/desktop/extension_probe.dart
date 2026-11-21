import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

/// 一个可供加载的浏览器插件。
class BrowserExtension {
  const BrowserExtension({
    required this.id,
    required this.name,
    required this.version,
    required this.path,
    this.description = '',
  });

  final String id;

  /// 展示名。manifest 里可能是 `__MSG_xxx__` 占位符，此时回退到 ID。
  final String name;

  final String version;

  /// 含 manifest.json 的目录绝对路径（可直接传给 AddBrowserExtension）。
  final String path;

  final String description;

  bool get isUsable =>
      path.isNotEmpty && File(p.join(path, 'manifest.json')).existsSync();

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'version': version,
    'path': path,
    'description': description,
  };

  static BrowserExtension? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final id = raw['id'];
    final path = raw['path'];
    if (id is! String || id.isEmpty) return null;
    if (path is! String || path.isEmpty) return null;
    return BrowserExtension(
      id: id,
      name: raw['name'] is String ? raw['name'] as String : id,
      version: raw['version'] is String ? raw['version'] as String : '',
      path: path,
      description: raw['description'] is String
          ? raw['description'] as String
          : '',
    );
  }
}

/// 探查本机浏览器里已安装的插件。
///
/// 只读 manifest.json，不解析插件内部逻辑。
class ExtensionProbe {
  const ExtensionProbe._();

  /// 找本机所有可加载的插件。
  ///
  /// 按 profile 逐个扫。同一插件在多个 profile 里都有时只保留一份
  /// （用户视角是"我装了这个插件"，不是一个 profile 一个）。
  ///
  /// ── 为什么要扫多处 ──
  ///
  /// 只扫浏览器的 Extensions 目录不够:Edge 会在启动时删掉
  /// "未在 Secure Preferences 里注册"的目录，一旦注册信息坏了，
  /// 插件就这么没了。所以额外扫我们自己的备份目录，
  /// 只要还留着一份就能给用户勾选。
  static List<BrowserExtension> probe() {
    if (!Platform.isWindows) return const [];
    final local = Platform.environment['LOCALAPPDATA'];
    if (local == null || local.isEmpty) return const [];

    // 已知浏览器的 User Data 根目录。
    const roots = [
      r'Microsoft\Edge\User Data',
      r'Google\Chrome\User Data',
      r'BraveSoftware\Brave-Browser\User Data',
    ];

    final seen = <String>{};
    final out = <BrowserExtension>[];

    // 1. 浏览器自己的插件目录
    for (final rel in roots) {
      final root = Directory(p.join(local, rel));
      if (!root.existsSync()) continue;
      for (final profile in _profileDirs(root)) {
        for (final ext in _extensionsIn(profile)) {
          if (!seen.add(ext.id)) continue;
          out.add(ext);
        }
      }
    }


    out.sort((a, b) => a.name.compareTo(b.name));
    return out;
  }

  /// 按数字分段比较版本目录名（`1.10.0_0` vs `1.9.0_0`）。
  ///
  /// 不能用字符串比较：`"1.10.0_0" < "1.9.0_0"`，因为逐字符比到第二位
  /// 时 `'1' < '9'`。插件从 1.9 升到 1.10 后如果旧目录还在，就会一直
  /// 加载旧版。
  ///
  /// 规则：按 `.` `_` 切成段，双方都能转成 int 时按数值比；
  /// 转不动的段退回字符串比。
  static int _compareVersion(String a, String b) {
    final pa = a.split(RegExp(r'[._]'));
    final pb = b.split(RegExp(r'[._]'));
    final n = pa.length < pb.length ? pa.length : pb.length;
    for (var i = 0; i < n; i++) {
      final na = int.tryParse(pa[i]);
      final nb = int.tryParse(pb[i]);
      if (na != null && nb != null) {
        if (na != nb) return na.compareTo(nb);
      } else {
        final c = pa[i].compareTo(pb[i]);
        if (c != 0) return c;
      }
    }
    return pa.length.compareTo(pb.length);
  }

  static List<String> _profileDirs(Directory root) {
    final out = <String>[];
    try {
      for (final e in root.listSync()) {
        if (e is! Directory) continue;
        final n = p.basename(e.path);
        if (n == 'Default' || RegExp(r'^Profile \d+$').hasMatch(n)) {
          out.add(e.path);
        }
      }
    } catch (_) {}
    return out;
  }

  static List<BrowserExtension> _extensionsIn(String profilePath) {
    final extRoot = Directory(p.join(profilePath, 'Extensions'));
    if (!extRoot.existsSync()) return const [];
    final out = <BrowserExtension>[];
    try {
      for (final idDir in extRoot.listSync()) {
        if (idDir is! Directory) continue;
        final id = p.basename(idDir.path);
        // 取版本最高的那个目录。
        Directory? best;
        try {
          for (final vDir in idDir.listSync()) {
            if (vDir is! Directory) continue;
            if (!File(p.join(vDir.path, 'manifest.json')).existsSync()) {
              continue;
            }
              if (best == null ||
                  _compareVersion(
                        p.basename(vDir.path),
                        p.basename(best.path),
                      ) >
                      0) {
                best = vDir;
              }
          }
        } catch (_) {}
        if (best == null) continue;
        final info = _readManifest(best.path);
        out.add(
          BrowserExtension(
            id: id,
            name: info.$1.isEmpty ? id : info.$1,
            version: info.$2,
            path: best.path,
            description: info.$3,
          ),
        );
      }
    } catch (_) {}
    return out;
  }

  /// 读 manifest 里的 name / version / description。
  ///
  /// name 常见形如 `__MSG_appName__`，需要从 `_locales` 里取真实文本。
  static (String, String, String) _readManifest(String dir) {
    try {
      final f = File(p.join(dir, 'manifest.json'));
      if (!f.existsSync()) return ('', '', '');
      final raw = jsonDecode(f.readAsStringSync());
      if (raw is! Map) return ('', '', '');
      final version = raw['version'] is String
          ? raw['version'] as String
          : '';
      final name = _resolveMsg(dir, raw['name']);
      final desc = _resolveMsg(dir, raw['description']);
      return (name, version, desc);
    } catch (_) {
      return ('', '', '');
    }
  }

  /// 解析 `__MSG_key__` 形式的本地化文本。
  ///
  /// 优先 zh_CN，其次中文其它变体，最后 en。都找不到就返回空串
  /// （调用方会回退到插件 ID）。
  static String _resolveMsg(String dir, Object? value) {
    if (value is! String) return '';
    if (!value.startsWith('__MSG_') || !value.endsWith('__')) return value;
    final key = value.substring(6, value.length - 2);

    const locales = ['zh_CN', 'zh', 'zh_TW', 'en', 'en_US'];
    for (final loc in locales) {
      final f = File(p.join(dir, '_locales', loc, 'messages.json'));
      if (!f.existsSync()) continue;
      try {
        final j = jsonDecode(f.readAsStringSync());
        if (j is Map && j[key] is Map) {
          final m = j[key] as Map;
          if (m['message'] is String) return m['message'] as String;
        }
      } catch (_) {}
    }
    return '';
  }
}

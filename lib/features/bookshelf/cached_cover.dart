import 'dart:io';

import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter/widgets.dart';

/// 带磁盘缓存的封面图标。
///
/// 为什么必须做:Image.network 只有内存缓存,应用一重启就全部重下。
/// 书架每次打开都重新扒一遍图标,既慢又浪费 ——
/// 而且站点挂掉时封面会集体变回字母。
///
/// 用 flutter_cache_manager 落盘,并按 URL 复用:
///   * 首次访问下载并写盘
///   * 之后直接读本地文件,不联网
///   * 缓存失效后仍然先显示旧图(offline fallback)
class CachedCover extends StatefulWidget {
  const CachedCover({
    super.key,
    required this.url,
    required this.fallback,
    this.padding = 16,
  });

  final String url;

  /// 加载中/失败时显示的内容(首字母)。
  final Widget fallback;

  final double padding;

  @override
  State<CachedCover> createState() => _CachedCoverState();
}

class _CachedCoverState extends State<CachedCover> {
  String? _path;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _resolve();
  }

  @override
  void didUpdateWidget(covariant CachedCover oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url) {
      _path = null;
      _loaded = false;
      _resolve();
    }
  }

  Future<void> _resolve() async {
    final url = widget.url;
    if (url.isEmpty) return;
    try {
      // getSingleFile 会优先返回本地缓存;没有才联网。
      final file = await DefaultCacheManager().getSingleFile(url);
      if (!mounted || widget.url != url) return;
      setState(() {
        _path = file.path;
        _loaded = true;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loaded = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // 还没读完:显示兜底,不闪烁空白。
    if (!_loaded || _path == null) {
      return Padding(
        padding: EdgeInsets.all(widget.padding),
        child: widget.fallback,
      );
    }

    final path = _path!;
    final isSvg = widget.url.split('?').first.toLowerCase().endsWith('.svg');

    // 关键:必须给紧约束(SizedBox.expand)。
    //
    // SvgPicture / Image 在宽松约束下会按"内在尺寸"渲染:
    // Python 的 SVG 写死 16×16,就会在大卡片里画成一个小点;
    // Vue 的 viewBox 是 128×128,恰好显得很大 —— 同一套代码出现巨大差异。
    // 撑满可用区域后,BoxFit.contain 才能等比缩放到统一大小。
    return Padding(
      padding: EdgeInsets.all(widget.padding),
      child: SizedBox.expand(
        child: isSvg
            ? SvgPicture.file(
                File(path),
                fit: BoxFit.contain,
                placeholderBuilder: (_) => widget.fallback,
              )
            : Image.file(
                File(path),
                fit: BoxFit.contain,
                errorBuilder: (_, _, _) => widget.fallback,
              ),
      ),
    );
  }
}

/// 预取封面到本地缓存。
///
/// 加书后立刻调用一次,用户下次打开书架就不用等下载。
/// 失败静默:封面是锦上添花,不该影响任何主流程。
Future<void> warmCoverCache(String url) async {
  try {
    await DefaultCacheManager().downloadFile(url);
  } catch (_) {
    // 忽略。
  }
}

/// 让缓存管理更可控:图标很少变,有效期给长一点。
class CoverCache {
  const CoverCache._();

  /// 清理全部封面缓存(设置里的"清空数据"会用到)。
  static Future<void> clear() async {
    await DefaultCacheManager().emptyCache();
  }

  /// 当前缓存占用字节数,诊断面板用。
  ///
  /// flutter_cache_manager 的 store 不暴露目录,这里按应用支持目录
  /// 下的默认缓存路径估算;拿不到就当 0,不影响功能。
  static Future<int> size() async {
    try {
      final base = Directory.systemTemp;
      // 缓存库把文件放在系统临时目录下的子目录里。
      var total = 0;
      await for (final e in base.list(recursive: false)) {
        if (e is Directory && e.path.contains('libCachedImageData')) {
          await for (final f in e.list(recursive: true)) {
            if (f is File) total += await f.length();
          }
        }
      }
      return total;
    } catch (_) {
      return 0;
    }
  }
}

/// 供 UI 层判断是否需要走缓存路径。
bool isRemoteIcon(String? url) =>
    url != null && url.isNotEmpty && url.startsWith('http');

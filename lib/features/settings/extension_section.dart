import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/services/settings.dart';
import '../../engine/desktop/extension_probe.dart';
import '../../engine/desktop/webview2_engine.dart';
import '../../main.dart';

/// 设置里的插件开关列表。
///
/// ── 为什么要让用户选 ──
///
/// 用户浏览器里装了 20 个插件，不代表希望阅读窗口里全跑起来:
/// 有些会注入浮窗挡住正文、有些会改页面样式、有些纯粹是别处用的。
/// 全加载既慢又干扰阅读。
///
/// 插件本体不做复制 —— 加载时直接引用原目录(WebView2 的
/// AddBrowserExtension 支持传路径)，所以用户随时可以在这里增减。
class ExtensionSection extends ConsumerStatefulWidget {
  const ExtensionSection({super.key});

  @override
  ConsumerState<ExtensionSection> createState() => _ExtensionSectionState();
}

class _ExtensionSectionState extends ConsumerState<ExtensionSection> {
  List<BrowserExtension>? _extensions;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    // 扫磁盘可能要几百毫秒，放后台。
    final list = await Future<List<BrowserExtension>>.microtask(
      ExtensionProbe.probe,
    );
    if (!mounted) return;
    setState(() {
      _extensions = list;
      _loading = false;
    });
      // 用户真正看到了这份列表，才算「见过」。
      //
      // 不能在启动时标记 —— 那时列表还没渲染过，等于替用户把
      // 还没看到的新插件标成已读，后续的新增提示永远不会出现。
      await ref
          .read(extensionSettingsProvider.notifier)
          .markSeen(list.map((e) => e.id).toSet());
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 16),
        child: Text(
          '正在查找本机插件…',
          style: TextStyle(color: Color(0xFF9AA0A6), fontSize: 13),
        ),
      );
    }

    final list = _extensions ?? const <BrowserExtension>[];
    if (list.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 12),
        child: Text(
          '没有在本机浏览器里找到插件。',
          style: TextStyle(color: Color(0xFF9AA0A6), fontSize: 13),
        ),
      );
    }

    final settings = ref.watch(extensionSettingsProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(bottom: 8),
          child: Text(
            '勾选后，阅读窗口里会加载这些插件。插件本身不会被复制，'
            '用的就是你浏览器里的那份。',
            style: TextStyle(color: Color(0xFF9AA0A6), fontSize: 12),
          ),
        ),
        ...list.map((ext) {
          final enabled = settings.isEnabled(ext.id);
          return CheckboxListTile(
            value: enabled,
            onChanged: (v) async {
              await ref
                  .read(extensionSettingsProvider.notifier)
                  .toggle(ext.id, v ?? false);

              // 让引擎立刻重新加载插件列表。
              //
              // 不重启程序就能生效：之前是用 ref.read 取一次快照，
              // 改完设置必须重启才生效，用户体验上等于"设置没用"。
              if (!context.mounted) return;
              final engine = await ref.read(engineProvider.future);
              if (engine is WebView2Engine) {
                final enabled = ref
                    .read(extensionSettingsProvider)
                    .enabledIds
                    .toList();
                final paths = ExtensionProbe.probe()
                    .where((e) => enabled.contains(e.id) && e.isUsable)
                    .map((e) => e.path)
                    .toList();
                await engine.reloadExtensions(paths);
              }
            },
            dense: true,
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            activeColor: const Color(0xFF7C9CFF),
            checkColor: const Color(0xFF0E0F12),
            title: Text(
              ext.name,
              style: const TextStyle(
                color: Color(0xFFE3E5E8),
                fontSize: 14,
              ),
            ),
            subtitle: Text(
              ext.version.isEmpty ? ext.id : 'v${ext.version}',
              style: const TextStyle(
                color: Color(0xFF6B7075),
                fontSize: 11,
              ),
            ),
          );
        }),
      ],
    );
  }
}
